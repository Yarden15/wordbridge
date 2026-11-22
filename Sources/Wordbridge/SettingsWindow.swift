import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    /// Meeting settings changed in the Settings window; an open meeting window picks them up.
    static let meetingSettingsChanged = Notification.Name("io.github.wordbridge.meetingSettingsChanged")
}

/// Everything the Settings window shows and changes. Values live in UserDefaults / the Keychain,
/// so the rest of the app reads them as before.
@MainActor
final class SettingsModel: ObservableObject {
    // General
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var accessibilityGranted = Accessibility.isTrusted
    @Published var launchError: String?

    // Model
    @Published var backend = Backend.current
    @Published var models = ModelLocator.availableModels
    @Published var localModel = ModelLocator.modelURL?.standardizedFileURL
    @Published var geminiKey = Keychain.read() ?? ""
    @Published var geminiModel = GeminiEngine.model == GeminiEngine.defaultModel ? "" : GeminiEngine.model
    @Published var keySaved = false

    // Meetings
    @Published var meetingSource = MeetingSource.preferred
    @Published var spoken = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "meetingSpoken") ?? "") ?? .english
    @Published var target = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "meetingTarget") ?? "") ?? .hebrew
    @Published var includeMe = UserDefaults.standard.object(forKey: "meetingIncludeMe") as? Bool ?? true

    func refresh() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        accessibilityGranted = Accessibility.isTrusted
        backend = Backend.current
        models = ModelLocator.availableModels
        localModel = ModelLocator.modelURL?.standardizedFileURL
        meetingSource = MeetingSource.preferred
        spoken = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "meetingSpoken") ?? "") ?? .english
        target = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "meetingTarget") ?? "") ?? .hebrew
        includeMe = UserDefaults.standard.object(forKey: "meetingIncludeMe") as? Bool ?? true
    }

    // MARK: General

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch {
            launchError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Model

    func useGemini() {
        guard !geminiKey.isBlank else { return }
        saveGeminiKey()
        Backend.current = .gemini
        backend = .gemini
        LLMEngine.shared.unload() // free the local model's memory
    }

    func useLocal(_ model: URL) {
        let changed = Backend.current != .local || model.standardizedFileURL != ModelLocator.modelURL?.standardizedFileURL
        Backend.current = .local
        backend = .local
        ModelLocator.select(model)
        localModel = model.standardizedFileURL
        if changed { LLMEngine.shared.unload() } // the next request loads the chosen model
    }

    func chooseModelFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a GGUF language model"
        panel.allowedContentTypes = [UTType(filenameExtension: "gguf") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        useLocal(url)
        models = ModelLocator.availableModels
    }

    func saveGeminiKey() {
        let key = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = Keychain.save(key)
        GeminiEngine.model = geminiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty, Backend.current == .gemini {
            Backend.current = .local
            backend = .local
        }
        keySaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.keySaved = false }
    }

    // MARK: Meetings

    func setMeetingSource(_ source: MeetingSource) {
        MeetingSource.preferred = source
        meetingSource = source
    }

    func setLanguages(spoken: AppLanguage, target: AppLanguage) {
        var target = target
        if spoken == target { target = AppLanguage.allCases.first { $0 != spoken } ?? target }
        self.spoken = spoken
        self.target = target
        UserDefaults.standard.set(spoken.rawValue, forKey: "meetingSpoken")
        UserDefaults.standard.set(target.rawValue, forKey: "meetingTarget")
        NotificationCenter.default.post(name: .meetingSettingsChanged, object: nil)
    }

    func setIncludeMe(_ on: Bool) {
        includeMe = on
        UserDefaults.standard.set(on, forKey: "meetingIncludeMe")
        NotificationCenter.default.post(name: .meetingSettingsChanged, object: nil)
    }
}

// MARK: - Views

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var engine = LLMEngine.shared

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            modelTab.tabItem { Label("Model", systemImage: "cpu") }
            meetings.tabItem { Label("Meetings", systemImage: "person.2.wave.2") }
        }
        .frame(width: 520, height: 430)
    }

    // MARK: General

    private var general: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                if let error = model.launchError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Accessibility access") {
                    if model.accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") { Accessibility.openSystemSettings() }
                    }
                }
            } footer: {
                Text("Accessibility lets Wordbridge read the text you select, paste suggestions back and read meeting captions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Shortcuts") {
                LabeledContent("Translate selection", value: "⌘⇧⌥T")
                LabeledContent("Improve writing", value: "⌘⇧⌥F")
                LabeledContent("Translate meeting", value: "⌘⇧⌥M")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Model

    private var modelTab: some View {
        Form {
            Section {
                Picker("Use", selection: Binding(
                    get: { model.backend },
                    set: { backend in
                        if backend == .gemini {
                            model.useGemini()
                        } else if let first = model.localModel ?? model.models.first {
                            model.useLocal(first)
                        }
                    })) {
                    Text("Google Gemini (online)").tag(Backend.gemini)
                    Text("A model on this Mac").tag(Backend.local)
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text(model.backend == .gemini
                     ? "Fast and uses no memory. Your text — including meeting sentences — is sent to Google, which may use it on the free tier."
                     : "Private: nothing leaves your Mac. Uses memory while loaded and is slower.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Google Gemini") {
                SecureField("API key", text: $model.geminiKey)
                TextField("Model", text: $model.geminiModel, prompt: Text(GeminiEngine.defaultModel))
                HStack {
                    Button("Get a Free Key…") { NSWorkspace.shared.open(URL(string: "https://aistudio.google.com/apikey")!) }
                    Spacer()
                    if model.keySaved {
                        Label("Saved", systemImage: "checkmark").foregroundStyle(.green).font(.caption)
                    }
                    Button("Save") { model.saveGeminiKey() }
                        .keyboardShortcut(.defaultAction)
                }
                if model.backend != .gemini && !model.geminiKey.isBlank {
                    Button("Use Gemini") { model.useGemini() }
                }
            }

            Section {
                if model.models.isEmpty {
                    Text("No model files found.").foregroundStyle(.secondary)
                }
                ForEach(model.models, id: \.self) { url in
                    modelRow(url)
                }
                HStack {
                    Button("Other Model File…") { model.chooseModelFile() }
                    Spacer()
                    Text(engineStatus).font(.caption).foregroundStyle(.secondary)
                    Button("Unload Now") { engine.unload() }
                        .disabled(engine.state == .unloaded)
                }
            } header: {
                Text("On this Mac")
            }
        }
        .formStyle(.grouped)
    }

    private func modelRow(_ url: URL) -> some View {
        let selected = model.backend == .local && model.localModel == url.standardizedFileURL
        return Button {
            model.useLocal(url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ModelLocator.displayName(for: url))
                    if let note = ModelLocator.note(for: url) {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(url.path)
    }

    private var engineStatus: String {
        switch engine.state {
        case .unloaded: "Not loaded"
        case .loading: "Loading…"
        case .ready: "Loaded"
        case .failed: "Error"
        }
    }

    // MARK: Meetings

    private var meetings: some View {
        Form {
            Section {
                Picker("Meeting text from", selection: Binding(get: { model.meetingSource }, set: { model.setMeetingSource($0) })) {
                    Text("Automatic").tag(MeetingSource.automatic)
                    Text("Meeting captions").tag(MeetingSource.captions)
                    Text("Wordbridge voice recognition").tag(MeetingSource.voice)
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text(sourceExplanation).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Languages") {
                Picker("People speak", selection: Binding(
                    get: { model.spoken }, set: { model.setLanguages(spoken: $0, target: model.target) })) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Translate to", selection: Binding(
                    get: { model.target },
                    set: { model.setLanguages(spoken: model.spoken == $0 ? model.target : model.spoken, target: $0) })) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }

            Section {
                Toggle("Also show what I say (microphone)", isOn: Binding(get: { model.includeMe }, set: { model.setIncludeMe($0) }))
            } footer: {
                Text("Voice mode only. With speakers instead of headphones, your microphone may also pick up the other side.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var sourceExplanation: String {
        switch model.meetingSource {
        case .automatic:
            "Uses the meeting's captions when they're on, otherwise listens to the meeting's sound."
        case .captions:
            "Google Meet: turn on captions (CC). Zoom: open Captions › View full transcript."
        case .voice:
            "Listens to the sound the meeting app plays and transcribes it on this Mac. Needs no captions."
        }
    }
}

// MARK: - Window

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let model = SettingsModel()

    func show() {
        model.refresh()
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Wordbridge Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
