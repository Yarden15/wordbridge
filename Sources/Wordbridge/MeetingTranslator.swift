import AppKit
import Combine
import SwiftUI

/// Where meeting text comes from.
enum MeetingSource: String, CaseIterable {
    /// The meeting's own captions when they're on, otherwise Wordbridge's speech recognition.
    case automatic
    case captions
    case voice

    static var preferred: MeetingSource {
        get { MeetingSource(rawValue: UserDefaults.standard.string(forKey: "meetingSource") ?? "") ?? .automatic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "meetingSource") }
    }

    var menuTitle: String {
        switch self {
        case .automatic: "Automatic"
        case .captions: "Meeting Captions (Meet / Zoom)"
        case .voice: "Wordbridge Voice Recognition"
        }
    }
}

/// A live meeting: follows what's said, and translates each finished sentence.
@MainActor
final class MeetingSession: ObservableObject {
    enum Mode: String { case captions, voice }

    struct Entry: Identifiable {
        let id = UUID()
        var key: String?
        var speaker: String?
        var original: String
        var translation: String?
        /// The text the translation was made from (the line may have grown since).
        var translatedFrom: String?
        var failed = false
        var isSelf = false
        var changedAt = Date()
        /// The newest line on screen, which may still be growing.
        var isTail = false
        var target: AppLanguage = .hebrew
        /// Already in the language we translate to (e.g. you said something in Hebrew): shown as is.
        var needsNoTranslation = false
    }

    /// The language people speak in the meeting (used for speech recognition).
    @Published private(set) var spoken: AppLanguage = MeetingSession.saved("meetingSpoken") ?? .english
    /// The language to translate into.
    @Published private(set) var target: AppLanguage = MeetingSession.saved("meetingTarget") ?? .hebrew
    /// Also listen to your microphone (voice mode), so your own sentences show up too.
    @Published private(set) var includeMe: Bool = UserDefaults.standard.object(forKey: "meetingIncludeMe") as? Bool ?? true

    @Published private(set) var entries: [Entry] = []
    /// Words being recognized right now (voice mode).
    @Published private(set) var live = ""
    /// What you're saying right now (voice mode, microphone).
    @Published private(set) var liveSelf = ""
    @Published private(set) var status = ""
    @Published private(set) var hint: String?
    @Published private(set) var mode: Mode = .captions
    @Published private(set) var meeting: MeetingApp?

    private var reader: CaptionReader?
    /// Stops Wordbridge's own speech recognition, when it's running.
    private var stopListeners: [() -> Void] = []
    private var timer: Timer?
    private var inFlight = Set<UUID>()
    private var startedAt = Date()
    private var stopped = false

    func start() {
        stopped = false
        meeting = MeetingApp.current()
        startedAt = Date()
        switch MeetingSource.preferred {
        case .voice: use(.voice)
        case .captions, .automatic: use(.captions)
        }
    }

    func use(_ mode: Mode) {
        stopSources()
        self.mode = mode
        live = ""
        liveSelf = ""
        hint = nil
        startedAt = Date()
        if meeting == nil { meeting = MeetingApp.current() }
        switch mode {
        case .captions:
            guard let meeting else {
                status = "No meeting found"
                hint = "Open a Zoom meeting or Google Meet in Chrome, or switch to Voice."
                if MeetingSource.preferred == .automatic { use(.voice) }
                return
            }
            reader = CaptionReader(meeting: meeting)
            status = "Reading \(meeting.name) captions"
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            poll()
        case .voice:
            guard #available(macOS 26, *) else {
                status = "Voice recognition unavailable"
                hint = "Wordbridge's voice recognition needs macOS 26 or later. Use the meeting's captions instead."
                return
            }
            status = "Starting voice recognition…"
            let others = MeetingListener(input: .app(meeting), language: spoken) { [weak self] event in
                self?.handle(event, fromMicrophone: false)
            }
            stopListeners.append { others.stop() }
            Task { await others.start() }
            if includeMe {
                let me = MeetingListener(input: .microphone, language: spoken) { [weak self] event in
                    self?.handle(event, fromMicrophone: true)
                }
                stopListeners.append { me.stop() }
                Task { await me.start() }
            }
        }
    }

    func stop() {
        stopped = true
        stopSources()
    }

    func setLanguages(spoken: AppLanguage, target: AppLanguage) {
        // Only two languages for now: the other one is always the translation target.
        var target = target
        if spoken == target { target = AppLanguage.allCases.first { $0 != spoken } ?? target }
        let spokenChanged = spoken != self.spoken
        self.spoken = spoken
        self.target = target
        UserDefaults.standard.set(spoken.rawValue, forKey: "meetingSpoken")
        UserDefaults.standard.set(target.rawValue, forKey: "meetingTarget")
        if spokenChanged, mode == .voice { use(.voice) } // recognize the new language
    }

    func setIncludeMe(_ on: Bool) {
        includeMe = on
        UserDefaults.standard.set(on, forKey: "meetingIncludeMe")
        if mode == .voice { use(.voice) }
    }

    private static func saved(_ key: String) -> AppLanguage? {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "")
    }

    private func stopSources() {
        timer?.invalidate()
        timer = nil
        reader = nil
        stopListeners.forEach { $0() }
        stopListeners = []
    }

    // MARK: Captions

    private func poll() {
        guard let reader else { return }
        guard let lines = reader.read() else {
            if MeetingSource.preferred == .automatic, entries.isEmpty, Date().timeIntervalSince(startedAt) > 3 {
                use(.voice) // no captions on: listen ourselves
                return
            }
            hint = reader.meeting.kind == .zoom
                ? "In Zoom, open Captions › View full transcript. (Zoom's caption overlay can't be read.)"
                : "Turn on captions in Meet (CC button)."
            settleAndTranslate()
            return
        }
        hint = nil
        ingest(lines)
    }

    private func ingest(_ lines: [CaptionLine]) {
        let now = Date()
        var matched = Set<UUID>()
        for (position, line) in lines.enumerated() {
            let isTail = position == lines.count - 1
            if let index = matchIndex(for: line, excluding: matched) {
                matched.insert(entries[index].id)
                if entries[index].original != line.text {
                    entries[index].original = line.text
                    entries[index].changedAt = now
                }
                if entries[index].isTail != isTail { entries[index].isTail = isTail }
            } else {
                var entry = Entry(key: line.key, speaker: line.speaker, original: line.text)
                entry.isSelf = CaptionReader.isSelf(line.speaker)
                entry.isTail = isTail
                entries.append(entry)
                matched.insert(entry.id)
            }
        }
        // Lines that scrolled away are finished.
        for index in entries.indices where entries[index].isTail && !matched.contains(entries[index].id) {
            entries[index].isTail = false
        }
        trim()
        settleAndTranslate()
    }

    /// Finds the entry a caption line belongs to: same key, same text, or a recent line it grew from.
    private func matchIndex(for line: CaptionLine, excluding matched: Set<UUID>) -> Int? {
        let recent = entries.indices.suffix(40).reversed().filter { !matched.contains(entries[$0].id) }
        if let key = line.key {
            return recent.first { entries[$0].key == key }
        }
        if let exact = recent.first(where: { entries[$0].speaker == line.speaker && entries[$0].original == line.text }) {
            return exact
        }
        return recent.first { index in
            let entry = entries[index]
            guard entry.speaker == line.speaker, Date().timeIntervalSince(entry.changedAt) < 8 else { return false }
            let shared = zip(entry.original, line.text).prefix { $0 == $1 }.count
            return shared >= min(entry.original.count, line.text.count, 24) * 7 / 10 && shared >= 4
        }
    }

    // MARK: Voice

    @available(macOS 26, *)
    private func handle(_ event: MeetingListener.Event, fromMicrophone: Bool) {
        guard !stopped, mode == .voice else { return }
        switch event {
        case .status(let text):
            if !fromMicrophone { status = text }
        case .partial(let text):
            if fromMicrophone { liveSelf = text } else { live = text }
        case .final(let text):
            var entry = Entry(speaker: fromMicrophone ? "You" : "Them", original: text)
            entry.isSelf = fromMicrophone
            entries.append(entry)
            trim()
            settleAndTranslate()
        case .failed(let message):
            if fromMicrophone {
                hint = "Your microphone: " + message
            } else {
                status = "Voice recognition stopped"
                hint = message
            }
        }
    }

    // MARK: Translation

    private func trim() {
        if entries.count > 400 { entries.removeFirst(entries.count - 400) }
    }

    /// A line is finished when a newer one follows it, or it hasn't changed for a moment.
    private func isSettled(_ entry: Entry) -> Bool {
        !entry.isTail || Date().timeIntervalSince(entry.changedAt) >= 1.5
    }

    /// Translates finished lines, a few at a time so a slow answer doesn't hold up the next ones.
    private func settleAndTranslate() {
        while inFlight.count < 3,
              let index = entries.firstIndex(where: {
                  !$0.needsNoTranslation && !$0.failed && $0.translatedFrom != $0.original
                      && !inFlight.contains($0.id) && isSettled($0)
              }) {
            translate(entries[index], at: index)
        }
    }

    private func translate(_ entry: Entry, at index: Int) {
        let target = self.target
        if AppLanguage.direction(for: entry.original).source == target {
            entries[index].needsNoTranslation = true // already in the target language
            return
        }
        inFlight.insert(entry.id)
        let source = AppLanguage.allCases.first { $0 != target } ?? spoken
        let context = entries[..<index].suffix(3).map(\.original)
        Task {
            let translation = try? await Self.translate(entry.original, context: Array(context), from: source, to: target)
            inFlight.remove(entry.id)
            if let i = entries.firstIndex(where: { $0.id == entry.id }) {
                if let translation {
                    entries[i].translation = translation
                    entries[i].translatedFrom = entry.original
                    entries[i].target = target
                } else {
                    entries[i].failed = true
                }
            }
            settleAndTranslate()
        }
    }

    func retry(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].failed = false
        settleAndTranslate()
    }

    private static func translate(_ text: String, context: [String], from source: AppLanguage, to target: AppLanguage) async throws -> String {
        let system = """
            You translate live meeting captions from \(source.englishName) to \(target.englishName). \
            The captions come from speech recognition and may contain mistakes: translate what the \
            speaker most likely meant, naturally and briefly. Output only the translation of the new line.
            """
        let user = context.isEmpty
            ? text
            : "Earlier in the conversation (for context only, don't translate):\n"
                + context.joined(separator: "\n") + "\n\nNew line:\n" + text
        return try await AI.complete(system: system, user: user, maxTokens: max(160, text.count * 3))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Views

struct MeetingView: View {
    @ObservedObject var session: MeetingSession
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            transcript
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: session.mode == .voice ? "waveform" : "captions.bubble")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor.iterative, isActive: session.mode == .voice && !session.live.isEmpty)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Meeting Translation").font(.headline)
                    Text(session.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Picker("", selection: Binding(get: { session.mode }, set: { session.use($0) })) {
                    Text("Captions").tag(MeetingSession.Mode.captions)
                    Text("Voice").tag(MeetingSession.Mode.voice)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Captions: read Meet/Zoom's own captions. Voice: Wordbridge listens to the meeting's sound.")
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Stop and close")
            }
            languageRow
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var languageRow: some View {
        HStack(spacing: 6) {
            languagePicker("Spoken", selection: Binding(
                get: { session.spoken },
                set: { session.setLanguages(spoken: $0, target: session.target) }))
                .help("The language people speak in the meeting")
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
            languagePicker("Translate to", selection: Binding(
                get: { session.target },
                set: { session.setLanguages(spoken: session.spoken == $0 ? session.target : session.spoken, target: $0) }))
            Spacer(minLength: 8)
            if session.mode == .voice {
                Button {
                    session.setIncludeMe(!session.includeMe)
                } label: {
                    Label("Me", systemImage: session.includeMe ? "mic.fill" : "mic.slash")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(session.includeMe ? Color.accentColor : Color.secondary)
                        .background(
                            Capsule().fill(session.includeMe ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(session.includeMe
                      ? "Also showing what you say (your microphone). Click to stop."
                      : "Click to also show what you say (your microphone).")
            }
        }
    }

    private func languagePicker(_ title: String, selection: Binding<AppLanguage>) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(AppLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let hint = session.hint {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill").foregroundStyle(.orange)
                            Text(hint).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if session.entries.isEmpty && session.live.isEmpty && session.liveSelf.isEmpty && session.hint == nil {
                        Text("Waiting for someone to speak…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }
                    ForEach(session.entries) { entry in
                        EntryRow(entry: entry, previousSpeaker: speaker(before: entry)) { session.retry(entry.id) }
                            .id(entry.id)
                    }
                    liveLine(session.live, label: nil)
                    liveLine(session.liveSelf, label: "You")
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(14)
            }
            .onChange(of: session.entries.count) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: session.entries.last?.translation) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: session.live) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: session.liveSelf) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    /// Words being recognized right now, before the sentence is finished.
    @ViewBuilder
    private func liveLine(_ text: String, label: String?) -> some View {
        if !text.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let label {
                    Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                DirectionalText(string: text, language: AppLanguage.direction(for: text).source)
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func speaker(before entry: MeetingSession.Entry) -> String? {
        guard let index = session.entries.firstIndex(where: { $0.id == entry.id }), index > 0 else { return nil }
        return session.entries[index - 1].speaker
    }
}

private struct EntryRow: View {
    let entry: MeetingSession.Entry
    let previousSpeaker: String?
    let retry: () -> Void

    var body: some View {
        let source = AppLanguage.direction(for: entry.original).source
        VStack(alignment: .leading, spacing: 4) {
            if let speaker = entry.speaker, speaker != previousSpeaker {
                Text(entry.isSelf ? "You" : speaker)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entry.isSelf ? Color.secondary : Color.accentColor)
                    .padding(.top, 4)
            }
            if entry.needsNoTranslation {
                DirectionalText(string: entry.original, language: source)
                    .font(.system(size: 15, weight: .medium))
                    .textSelection(.enabled)
            } else {
                if let translation = entry.translation {
                    DirectionalText(string: translation, language: entry.target)
                        .font(.system(size: 15, weight: .medium))
                        .textSelection(.enabled)
                } else if entry.failed {
                    Button("Couldn't translate — try again", action: retry)
                        .buttonStyle(.link)
                        .font(.caption)
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 120, height: 10)
                        .padding(.vertical, 4)
                }
                DirectionalText(string: entry.original, language: source)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.leading, entry.isSelf ? 10 : 0)
        .overlay(alignment: .leading) {
            if entry.isSelf {
                RoundedRectangle(cornerRadius: 1).fill(Color.secondary.opacity(0.3)).frame(width: 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Window

private final class MeetingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class MeetingPanelController: NSObject, NSWindowDelegate {
    private var panel: MeetingPanel?
    private var session: MeetingSession?

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() {
        if isOpen { panel?.close() } else { show() }
    }

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let session = MeetingSession()
        self.session = session
        let hosting = NSHostingController(rootView: MeetingView(session: session) { [weak self] in self?.panel?.close() })
        hosting.sizingOptions = []

        let panel = MeetingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 340),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.contentViewController = hosting
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentMinSize = NSSize(width: 320, height: 160)
        panel.delegate = self
        panel.setContentSize(NSSize(width: 440, height: 340))
        if !panel.setFrameUsingName("MeetingPanel"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - panel.frame.width - 24, y: screen.minY + 24))
        }
        panel.setFrameAutosaveName("MeetingPanel")
        self.panel = panel
        panel.orderFrontRegardless()
        session.start()
    }

    func windowWillClose(_ notification: Notification) {
        session?.stop()
        session = nil
        panel = nil
    }
}
