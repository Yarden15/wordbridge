import AppKit
import Combine
import SwiftUI

// MARK: - Model

enum AssistantMode: String, CaseIterable {
    case translate
    case improve

    var title: String {
        switch self {
        case .translate: "Translate"
        case .improve: "Improve"
        }
    }
}

/// Everything the panel shows for one piece of selected text: its translation, suggestions
/// for improving it, and word-by-word meanings. Each is fetched only when it's first shown.
@MainActor
final class AssistantModel: ObservableObject {
    let text: String
    @Published var mode: AssistantMode {
        didSet { if mode != oldValue { startIfNeeded() } }
    }

    // Translate
    @Published private(set) var source: AppLanguage
    @Published private(set) var target: AppLanguage
    @Published private(set) var translation: String?
    @Published private(set) var translationError: String?
    private var translateTask: Task<Void, Never>?

    // Improve
    @Published private(set) var check: WritingCheck?
    @Published private(set) var checkError: String?
    private var checkTask: Task<Void, Never>?

    // Word by word
    @Published var wordByWord = false
    @Published private(set) var glosses: [String: [Int: WordGloss]] = [:]
    @Published private(set) var glossErrors: [String: String] = [:]
    @Published private(set) var glossLoading: Set<String> = []

    init(text: String, mode: AssistantMode) {
        self.text = text
        self.mode = mode
        (source, target) = AppLanguage.direction(for: text)
        startIfNeeded()
    }

    /// The current tab has its answer (or an error), so the panel may close on an outside click.
    var isDone: Bool {
        switch mode {
        case .translate: translation != nil || translationError != nil
        case .improve: check != nil || checkError != nil
        }
    }

    func startIfNeeded() {
        switch mode {
        case .translate where translateTask == nil: startTranslation()
        case .improve where checkTask == nil: startCheck()
        default: break
        }
    }

    func retry() {
        switch mode {
        case .translate: startTranslation()
        case .improve: startCheck()
        }
    }

    func swapDirection() {
        (source, target) = (target, source)
        startTranslation()
    }

    private func startTranslation() {
        translateTask?.cancel()
        translation = nil
        translationError = nil
        let (text, source, target) = (text, source, target)
        translateTask = Task {
            do {
                let result = try await Translator.translate(text, from: source, to: target)
                guard !Task.isCancelled else { return }
                translation = result
            } catch {
                guard !Task.isCancelled else { return } // the panel was closed
                translationError = error.localizedDescription
            }
        }
    }

    private func startCheck() {
        checkTask?.cancel()
        check = nil
        checkError = nil
        let text = text
        checkTask = Task {
            do {
                let result = try await WritingAssistant.check(text)
                guard !Task.isCancelled else { return }
                check = result
            } catch {
                guard !Task.isCancelled else { return }
                checkError = error.localizedDescription
            }
        }
    }

    func loadGloss(for text: String) {
        guard glosses[text] == nil, !glossLoading.contains(text) else { return }
        glossLoading.insert(text)
        glossErrors[text] = nil
        Task {
            do {
                glosses[text] = try await Glossary.gloss(text)
            } catch {
                glossErrors[text] = error.localizedDescription
            }
            glossLoading.remove(text)
        }
    }

    func cancel() {
        translateTask?.cancel()
        checkTask?.cancel()
    }

    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

/// The word under the mouse (or clicked to pin it). Kept apart from the model so hovering
/// doesn't re-render or re-measure the whole panel.
@MainActor
final class WordFocus: ObservableObject {
    struct Target: Equatable {
        let text: String
        let token: WordToken
    }

    @Published var hovered: Target?
    @Published var pinned: Target?
    var current: Target? { hovered ?? pinned }
}

// MARK: - Main view

struct AssistantView: View {
    @ObservedObject var model: AssistantModel
    let focus: WordFocus
    /// Lays out at natural height without scrolling — only used to measure the panel.
    var measuring = false
    let onClose: () -> Void
    let onReplace: (String) -> Void

    var body: some View {
        if measuring {
            VStack(alignment: .leading, spacing: 14) {
                header
                content
                footer
            }
            .padding(16)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                header
                ScrollView { content.padding(.trailing, 6) }
                footer
            }
            .padding(16)
            .frame(minWidth: 340, maxWidth: .infinity, minHeight: 120, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("Mode", selection: $model.mode) {
                ForEach(AssistantMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer(minLength: 0)

            PillToggle(title: "Word by word", systemImage: "character.cursor.ibeam", isOn: $model.wordByWord)
                .help("Point at a word to see what it means here")

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(title: model.mode == .translate ? "Original" : "You wrote", systemImage: "text.quote")
                TextBlock(text: model.text, language: model.source, secondary: true, model: model, focus: focus)
            }
            switch model.mode {
            case .translate: translateContent
            case .improve: improveContent
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.wordByWord {
            WordInfoBar(model: model, focus: focus)
        }
    }

    // MARK: Translate

    private var translateContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SectionLabel(title: model.source.displayName, systemImage: "character.bubble")
                Button(action: model.swapDirection) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Swap direction")
                SectionLabel(title: model.target.displayName)
                Spacer()
                if let translation = model.translation {
                    SmallIconButton(systemImage: "doc.on.doc", help: "Copy the translation") {
                        AssistantModel.copy(translation)
                    }
                }
            }

            if let translation = model.translation {
                TextBlock(text: translation, language: model.target, model: model, focus: focus)
            } else if let error = model.translationError {
                ErrorView(message: error, retry: model.retry)
            } else {
                WaitingView(label: "Translating…")
            }
        }
    }

    // MARK: Improve

    @ViewBuilder
    private var improveContent: some View {
        if let check = model.check {
            if check.suggestions.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Looks good").font(.headline)
                        Text("No mistakes found.").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if check.ok {
                        Label("Already correct — here's a more natural option", systemImage: "checkmark.seal.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
                    ForEach(Array(check.suggestions.enumerated()), id: \.offset) { index, suggestion in
                        SuggestionCard(
                            index: index,
                            kind: kind(ofSuggestion: index, ok: check.ok),
                            suggestion: suggestion,
                            language: model.source,
                            model: model,
                            focus: focus,
                            onReplace: onReplace
                        )
                    }
                }
            }
        } else if let error = model.checkError {
            ErrorView(message: error, retry: model.retry)
        } else {
            WaitingView(label: "Checking your writing…")
        }
    }

    private func kind(ofSuggestion index: Int, ok: Bool) -> SuggestionCard.Kind {
        ok || index == 1 ? .natural : .corrected
    }
}

// MARK: - Small building blocks

/// View-local on/off state. (Used instead of @State, whose macro isn't available
/// when building with Command Line Tools only.)
private final class Flag: ObservableObject {
    @Published var value = false
}

/// A small all-caps caption that names a section.
private struct SectionLabel: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title.uppercased()).tracking(0.6)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

/// An on/off switch drawn as a small capsule, tinted when on.
private struct PillToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct SmallIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @StateObject private var done = Flag()

    var body: some View {
        Button {
            action()
            withAnimation { done.value = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { done.value = false } }
        } label: {
            Image(systemName: done.value ? "checkmark" : systemImage)
                .font(.caption.weight(.medium))
                .frame(width: 16, height: 16)
                .foregroundStyle(done.value ? Color.green : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Suggestion card

private struct SuggestionCard: View {
    enum Kind {
        case corrected, natural

        var title: String { self == .corrected ? "Corrected" : "More natural" }
        var systemImage: String { self == .corrected ? "checkmark.circle.fill" : "sparkles" }
        var tint: Color { self == .corrected ? .green : .purple }
    }

    let index: Int
    let kind: Kind
    let suggestion: Suggestion
    let language: AppLanguage
    @ObservedObject var model: AssistantModel
    let focus: WordFocus
    let onReplace: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: kind.systemImage).foregroundStyle(kind.tint)
                Text(kind.title).font(.subheadline.weight(.semibold))
                Spacer()
                SmallIconButton(systemImage: "doc.on.doc", help: "Copy") {
                    AssistantModel.copy(suggestion.text)
                }
                replaceButton
            }

            TextBlock(
                text: suggestion.text,
                language: language,
                tokens: WordTokens.diff(original: model.text, revised: suggestion.text),
                model: model,
                focus: focus
            )

            if let explanation = suggestion.explanation, !explanation.isBlank {
                // Explanations are written in Hebrew but quote English words, so any Hebrew means right-to-left.
                let explanationLanguage: AppLanguage = explanation.containsHebrew ? .hebrew : .english
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    DirectionalText(string: explanation, language: explanationLanguage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .environment(\.layoutDirection, explanationLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
    }

    @ViewBuilder
    private var replaceButton: some View {
        let button = Button {
            onReplace(suggestion.text)
        } label: {
            HStack(spacing: 5) {
                Text("Replace")
                Text(index == 0 ? "↩" : "⌘2").opacity(0.65)
            }
            .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .tint(kind.tint)
        .controlSize(.small)

        if index == 0 {
            button.keyboardShortcut(.defaultAction).help("Replace your selected text with this (Return)")
        } else {
            button.keyboardShortcut("2", modifiers: .command).help("Replace your selected text with this (⌘2)")
        }
    }
}

// MARK: - Text blocks

/// Shows text as a paragraph, or as hoverable words when "word by word" is on.
/// Words that differ from the user's original (in suggestions) are highlighted.
private struct TextBlock: View {
    let text: String
    let language: AppLanguage
    var tokens: [WordToken]?
    var secondary = false
    @ObservedObject var model: AssistantModel
    let focus: WordFocus

    private var font: Font { secondary ? .body : .title3 }

    var body: some View {
        if model.wordByWord {
            words
                .task(id: text) { model.loadGloss(for: text) }
        } else {
            paragraph
        }
    }

    private var resolvedTokens: [WordToken] { tokens ?? WordTokens.split(text) }

    private var paragraph: some View {
        let mark = language.isRightToLeft ? "\u{200F}" : "\u{200E}"
        var attributed = AttributedString(mark)
        for token in resolvedTokens {
            var word = AttributedString(token.text)
            if token.changed {
                word.foregroundColor = .green
                word.backgroundColor = Color.green.opacity(0.14)
            }
            attributed += word
            // Restart the direction at each new line (see DirectionalText).
            attributed += AttributedString(token.trailing.replacingOccurrences(of: "\n", with: "\n" + mark))
        }
        return Text(attributed)
            .font(font)
            .foregroundStyle(secondary ? .secondary : .primary)
            .lineSpacing(3)
            .textSelection(.enabled)
            .multilineTextAlignment(language.isRightToLeft ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: language.isRightToLeft ? .trailing : .leading)
            .environment(\.layoutDirection, .leftToRight)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var words: some View {
        FlowLayout(spacing: 1, lineSpacing: 3) {
            ForEach(resolvedTokens) { token in
                WordChip(token: token, textKey: text, font: font, secondary: secondary, model: model, focus: focus)
            }
        }
        .frame(maxWidth: .infinity, alignment: language.isRightToLeft ? .trailing : .leading)
        .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}

private struct WordChip: View {
    let token: WordToken
    let textKey: String
    let font: Font
    let secondary: Bool
    @ObservedObject var model: AssistantModel
    @ObservedObject var focus: WordFocus

    var body: some View {
        let target = WordFocus.Target(text: textKey, token: token)
        let isFocused = focus.current == target
        let isPinned = focus.pinned == target
        Text(token.text)
            .font(font)
            .foregroundStyle(color(focused: isFocused))
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(fill(focused: isFocused))
            )
            .overlay(alignment: .bottom) {
                // A dotted underline hints that every word can be pointed at.
                if token.isWord && !isFocused {
                    Line()
                        .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [1.5, 2]))
                        .frame(height: 1)
                        .padding(.horizontal, 3)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.accentColor.opacity(isPinned ? 0.7 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.1), value: isFocused)
            .onHover { inside in
                if inside {
                    focus.hovered = target
                } else if focus.hovered == target {
                    focus.hovered = nil
                }
            }
            .onTapGesture { focus.pinned = isPinned ? nil : target }
    }

    private func color(focused: Bool) -> AnyShapeStyle {
        if focused { return AnyShapeStyle(Color.accentColor) }
        if token.changed { return AnyShapeStyle(Color.green) }
        return secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
    }

    private func fill(focused: Bool) -> Color {
        if focused { return Color.accentColor.opacity(0.18) }
        if inFocusedPhrase { return Color.accentColor.opacity(0.09) }
        if token.changed { return Color.green.opacity(0.14) }
        return .clear
    }

    /// Lightly highlights the other words of the idiom the focused word belongs to.
    private var inFocusedPhrase: Bool {
        guard let current = focus.current, current.text == textKey,
              let glosses = model.glosses[textKey],
              let phrase = glosses[current.token.id]?.phrase
        else { return false }
        return glosses[token.id]?.phrase == phrase
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// Shows the meaning of the word under the mouse.
private struct WordInfoBar: View {
    @ObservedObject var model: AssistantModel
    @ObservedObject var focus: WordFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            info
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var info: some View {
        if let target = focus.current {
            if let gloss = model.glosses[target.text]?[target.token.id] {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(target.token.bare).font(.headline)
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        Text(gloss.meaning)
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                    }
                    if let phrase = gloss.phrase, let phraseMeaning = gloss.phraseMeaning {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "quote.opening").font(.caption2)
                            Text(phrase).italic()
                            Text("·")
                            Text(phraseMeaning)
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            } else if let error = model.glossErrors[target.text] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if model.glossLoading.contains(target.text) {
                loading
            } else {
                hint("No meaning for “\(target.token.text)”.")
            }
        } else if !model.glossLoading.isEmpty {
            loading
        } else {
            hint("Point at a word to see what it means here. Click to keep it.")
        }
    }

    private func hint(_ text: String) -> some View {
        Label(text, systemImage: "hand.point.up.left")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private var loading: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Looking up the words…").font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// Text laid out in its language's direction, even when it mixes Hebrew and English.
///
/// macOS picks each paragraph's direction from its first letter, so a Hebrew sentence that starts
/// with an English word ("Gemini עובד עכשיו…") would be laid out left-to-right and come out scrambled.
/// Starting every paragraph with an invisible direction mark (RLM/LRM) fixes the order.
struct DirectionalText: View {
    let string: String
    let language: AppLanguage

    var body: some View {
        let mark = language.isRightToLeft ? "\u{200F}" : "\u{200E}"
        let marked = string.components(separatedBy: "\n").map { mark + $0 }.joined(separator: "\n")
        Text(verbatim: marked)
            .multilineTextAlignment(language.isRightToLeft ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: language.isRightToLeft ? .trailing : .leading)
            .environment(\.layoutDirection, .leftToRight)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Status views

private struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again", action: retry).controlSize(.small)
            }
        }
    }
}

/// Placeholder lines while waiting — or, while the local model loads (minutes from a slow drive),
/// real progress.
private struct WaitingView: View {
    let label: String
    @ObservedObject private var engine = LLMEngine.shared
    @StateObject private var pulse = Flag()

    var body: some View {
        if case .loading(let started) = engine.state {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let elapsed = context.date.timeIntervalSince(started)
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: min(elapsed / engine.expectedLoadSeconds, 0.97))
                    Text("Loading language model… \(Int(elapsed))s of ~\(Int(engine.expectedLoadSeconds))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(label).font(.callout).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 7) {
                    placeholderLine.padding(.trailing, 0)
                    placeholderLine.padding(.trailing, 50)
                    placeholderLine.padding(.trailing, 140)
                }
                .opacity(pulse.value ? 0.45 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse.value)
                .onAppear { pulse.value = true }
            }
        }
    }

    private var placeholderLine: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.primary.opacity(0.08))
            .frame(maxWidth: .infinity)
            .frame(height: 11)
    }
}

// MARK: - Panel

/// A floating panel that takes keyboard focus without activating the app,
/// so the app you were working in stays in front.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
}

@MainActor
final class AssistantPanelController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private var outsideClickMonitor: Any?
    private var model: AssistantModel?
    private var focus = WordFocus()
    private var sourceApp: NSRunningApplication?
    private var changeObservers: [AnyCancellable] = []
    /// Until the user resizes the panel, its height follows the content. After that, the user's size wins.
    private var userSized = false
    private static let sizeKey = "assistantPanelSize"
    private static let defaultWidth: CGFloat = 460

    /// - Parameter sourceApp: the app the text was selected in, so "Replace" can paste back into it.
    func show(text: String, mode: AssistantMode, near point: NSPoint, sourceApp: NSRunningApplication?) {
        panel?.close()

        let model = AssistantModel(text: text, mode: mode)
        let focus = WordFocus()
        self.model = model
        self.focus = focus
        self.sourceApp = sourceApp

        let hosting = NSHostingController(rootView: AssistantView(
            model: model, focus: focus,
            onClose: { [weak self] in self?.panel?.close() },
            onReplace: { [weak self] text in self?.replace(with: text) }
        ))
        hosting.sizingOptions = [] // we size the window ourselves, so it stays resizable

        let savedSize = NSSizeFromString(UserDefaults.standard.string(forKey: Self.sizeKey) ?? "")
        userSized = savedSize.width >= 340 && savedSize.height >= 120

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.defaultWidth, height: 200),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentMinSize = NSSize(width: 340, height: 120)

        self.panel = panel
        panel.setContentSize(userSized ? savedSize : fittingSize(width: Self.defaultWidth, near: point))
        panel.setFrameOrigin(origin(for: panel.frame.size, near: point))
        panel.makeKeyAndOrderFront(nil)
        startOutsideClickMonitor(for: model)

        // Grow or shrink to fit as answers arrive (until the user picks a size).
        changeObservers = [model.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.fitToContent() }]
    }

    private func replace(with text: String) {
        let app = sourceApp
        panel?.close()
        Task { @MainActor in
            if await !SelectionReader.replaceSelection(with: text, in: app) {
                AssistantModel.copy(text) // no permission to paste: at least it's on the clipboard
                NSSound.beep()
            }
        }
    }

    /// The height the panel needs to show everything at a given width, capped to most of the screen.
    private func fittingSize(width: CGFloat, near point: NSPoint) -> NSSize {
        guard let model else { return NSSize(width: width, height: 200) }
        let measure = NSHostingView(rootView: AssistantView(
            model: model, focus: WordFocus(), measuring: true, onClose: {}, onReplace: { _ in }))
        measure.frame.size.width = width
        let natural = measure.fittingSize.height
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let maxHeight = (screen?.visibleFrame.height ?? 800) * 0.7
        return NSSize(width: width, height: min(max(natural, 120), maxHeight))
    }

    private func fitToContent() {
        guard !userSized, let panel, !panel.inLiveResize else { return }
        let current = panel.contentRect(forFrameRect: panel.frame)
        let size = fittingSize(width: current.width, near: NSPoint(x: panel.frame.midX, y: panel.frame.midY))
        guard abs(size.height - current.height) > 1 else { return }
        var frame = panel.frameRect(forContentRect: NSRect(origin: current.origin, size: size))
        frame.origin.y = panel.frame.maxY - frame.height // keep the top edge in place
        if let visible = panel.screen?.visibleFrame, frame.minY < visible.minY + 8 {
            frame.origin.y = visible.minY + 8 // grew past the bottom of the screen: move up
        }
        panel.setFrame(frame, display: true, animate: false)
    }

    /// Places the panel just below-right of the cursor, kept fully on screen.
    private func origin(for size: NSSize, near point: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(x: point.x + 8, y: point.y - size.height - 16)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        if origin.y < visible.minY + 8 { origin.y = point.y + 16 } // no room below → show above
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        return origin
    }

    /// Closes the panel when the user clicks in another app — but only once there's an answer,
    /// so a click elsewhere while waiting doesn't throw the request away.
    private func startOutsideClickMonitor(for model: AssistantModel) {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak model] _ in
            MainActor.assumeIsolated {
                guard let model, model.isDone else { return }
                self?.panel?.close()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    /// Once the user resizes the panel, stop auto-fitting and keep their size.
    func windowWillStartLiveResize(_ notification: Notification) {
        userSized = true
    }

    /// Remembers the size, so the next panel opens the same size.
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel else { return }
        let size = panel.contentRect(forFrameRect: panel.frame).size
        UserDefaults.standard.set(NSStringFromSize(size), forKey: Self.sizeKey)
    }

    func windowWillClose(_ notification: Notification) {
        stopOutsideClickMonitor()
        changeObservers = []
        model?.cancel()
        model = nil
        panel = nil
    }
}
