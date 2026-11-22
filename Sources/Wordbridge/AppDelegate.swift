import AppKit
import Carbon
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var translateHotKey: HotKey?
    private var improveHotKey: HotKey?
    private var meetingHotKey: HotKey?
    private let assistantPanel = AssistantPanelController()
    private let meetingPanel = MeetingPanelController()
    private let meetingItem = NSMenuItem()
    private let meetingSourceItem = NSMenuItem()

    private let accessibilityItem = NSMenuItem()
    private let launchAtLoginItem = NSMenuItem()
    private let modelStatusItem = NSMenuItem()
    private let unloadModelItem = NSMenuItem()
    private let modelMenuItem = NSMenuItem()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        // ⌘⇧⌥T — translate the current selection.
        translateHotKey = HotKey(
            id: 1, keyCode: kVK_ANSI_T, modifiers: cmdKey | shiftKey | optionKey
        ) { [weak self] in
            self?.translateSelection()
        }
        // ⌘⇧⌥F — check and fix ("improve") the text you selected.
        improveHotKey = HotKey(
            id: 2, keyCode: kVK_ANSI_F, modifiers: cmdKey | shiftKey | optionKey
        ) { [weak self] in
            self?.improveSelection()
        }

        // ⌘⇧⌥M — live translation of the meeting you're in.
        meetingHotKey = HotKey(
            id: 3, keyCode: kVK_ANSI_M, modifiers: cmdKey | shiftKey | optionKey
        ) { [weak self] in
            self?.toggleMeeting()
        }

        Accessibility.requestIfNeeded()

        // Developer aid: `open Wordbridge.app --args --show "text"` (or `--improve "text"`) opens the panel directly;
        // `--meeting` opens meeting translation.
        let args = CommandLine.arguments
        if args.contains("--meeting") { meetingPanel.show() }
        for (flag, mode) in [("--show", AssistantMode.translate), ("--improve", .improve)] {
            if let index = args.firstIndex(of: flag), index + 1 < args.count, let screen = NSScreen.main {
                let center = NSPoint(x: screen.visibleFrame.midX - 230, y: screen.visibleFrame.midY + 200)
                assistantPanel.show(text: args[index + 1], mode: mode, near: center, sourceApp: nil)
            }
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Wordbridge")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self

        let translate = NSMenuItem(title: "Translate Selection", action: #selector(translateSelection), keyEquivalent: "t")
        translate.keyEquivalentModifierMask = [.command, .shift, .option]
        translate.target = self
        menu.addItem(translate)

        let improve = NSMenuItem(title: "Improve Writing", action: #selector(improveSelection), keyEquivalent: "f")
        improve.keyEquivalentModifierMask = [.command, .shift, .option]
        improve.target = self
        menu.addItem(improve)

        meetingItem.title = "Translate Meeting"
        meetingItem.action = #selector(toggleMeeting)
        meetingItem.keyEquivalent = "m"
        meetingItem.keyEquivalentModifierMask = [.command, .shift, .option]
        meetingItem.target = self
        menu.addItem(meetingItem)

        meetingSourceItem.title = "Meeting Text From"
        meetingSourceItem.submenu = NSMenu()
        menu.addItem(meetingSourceItem)

        menu.addItem(.separator())

        modelStatusItem.isEnabled = false
        menu.addItem(modelStatusItem)

        unloadModelItem.title = "Unload Model Now"
        unloadModelItem.target = self
        unloadModelItem.action = #selector(unloadModel)
        menu.addItem(unloadModelItem)

        modelMenuItem.title = "Choose Model"
        modelMenuItem.submenu = NSMenu()
        menu.addItem(modelMenuItem)

        menu.addItem(.separator())

        accessibilityItem.target = self
        accessibilityItem.action = #selector(openAccessibilitySettings)
        menu.addItem(accessibilityItem)

        launchAtLoginItem.title = "Launch at Login"
        launchAtLoginItem.target = self
        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Wordbridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        accessibilityItem.title = Accessibility.isTrusted
            ? "Accessibility Access: Granted"
            : "Grant Accessibility Access…"
        accessibilityItem.state = Accessibility.isTrusted ? .on : .off
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        let engine = LLMEngine.shared
        let name = engine.modelName ?? "none found"
        let status: String
        switch engine.state {
        case .unloaded: status = "not loaded"
        case .loading: status = "loading…"
        case .ready: status = "ready"
        case .failed: status = "error"
        }
        modelStatusItem.title = Backend.current == .gemini
            ? "Model: Google Gemini (online)"
            : "Model: \(name) — \(status)"
        unloadModelItem.isEnabled = engine.state != .unloaded
        rebuildModelMenu()

        meetingItem.title = meetingPanel.isOpen ? "Stop Meeting Translation" : "Translate Meeting"
        if let submenu = meetingSourceItem.submenu {
            submenu.removeAllItems()
            for source in MeetingSource.allCases {
                let item = NSMenuItem(title: source.menuTitle, action: #selector(selectMeetingSource(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = source.rawValue
                item.state = MeetingSource.preferred == source ? .on : .off
                switch source {
                case .automatic: item.subtitle = "Captions when they're on, otherwise voice recognition"
                case .captions: item.subtitle = "Meet captions, or Zoom's transcript panel"
                case .voice: item.subtitle = "Listens to the meeting's sound on this Mac"
                }
                submenu.addItem(item)
            }
        }
    }

    /// Lists the models found on this Mac and on connected drives, with the current one checked.
    private func rebuildModelMenu() {
        guard let submenu = modelMenuItem.submenu else { return }
        submenu.removeAllItems()
        let usingGemini = Backend.current == .gemini
        let current = usingGemini ? nil : ModelLocator.modelURL?.standardizedFileURL.path
        let models = ModelLocator.availableModels

        submenu.addItem(.sectionHeader(title: "Online"))
        let gemini = NSMenuItem(title: "Google Gemini", action: #selector(selectGemini), keyEquivalent: "")
        gemini.target = self
        gemini.state = usingGemini ? .on : .off
        gemini.subtitle = "Fast, no memory use · your text is sent to Google"
        submenu.addItem(gemini)
        let geminiKey = NSMenuItem(
            title: GeminiEngine.hasKey ? "Gemini API Key…" : "Add Gemini API Key…",
            action: #selector(editGeminiKey), keyEquivalent: "")
        geminiKey.target = self
        geminiKey.indentationLevel = 1
        submenu.addItem(geminiKey)

        submenu.addItem(.separator())
        submenu.addItem(.sectionHeader(title: "On this Mac"))
        if models.isEmpty {
            let none = NSMenuItem(title: "No models found", action: nil, keyEquivalent: "")
            none.isEnabled = false
            submenu.addItem(none)
        }
        for model in models {
            let item = NSMenuItem(title: ModelLocator.displayName(for: model), action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model
            item.state = model.standardizedFileURL.path == current ? .on : .off
            item.subtitle = ModelLocator.note(for: model)
            item.toolTip = model.path
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        let chooseFile = NSMenuItem(title: "Other Model File…", action: #selector(chooseModelFile), keyEquivalent: "")
        chooseFile.target = self
        submenu.addItem(chooseFile)
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? URL else { return }
        let wasLocal = Backend.current == .local
        Backend.current = .local
        guard !wasLocal || model.standardizedFileURL.path != ModelLocator.modelURL?.standardizedFileURL.path else { return }
        ModelLocator.select(model)
        LLMEngine.shared.unload() // the next request loads the new model
    }

    @objc private func selectGemini() {
        if !GeminiEngine.hasKey {
            guard askForGeminiKey() else { return }
        }
        Backend.current = .gemini
        LLMEngine.shared.unload() // free the local model's memory
    }

    @objc private func editGeminiKey() {
        if askForGeminiKey(), Backend.current == .local {
            Backend.current = .gemini
            LLMEngine.shared.unload()
        }
    }

    /// Asks for the Gemini API key (and optionally the model name). Returns true if a key was saved.
    private func askForGeminiKey() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Google Gemini API Key"
        alert.informativeText = """
            Get a free key at aistudio.google.com/apikey and paste it here. \
            It's stored in your Keychain.

            On the free tier, Google may use the text you translate to improve its products. \
            Switch back to a local model for anything private.
            """

        let keyField = NSSecureTextField(frame: NSRect(x: 0, y: 30, width: 320, height: 24))
        keyField.placeholderString = "API key"
        keyField.stringValue = Keychain.read() ?? ""
        let modelField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        modelField.placeholderString = "Model (default: \(GeminiEngine.defaultModel))"
        modelField.stringValue = GeminiEngine.model == GeminiEngine.defaultModel ? "" : GeminiEngine.model
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 54))
        fields.addSubview(keyField)
        fields.addSubview(modelField)
        alert.accessoryView = fields
        alert.window.initialFirstResponder = keyField

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Get a Key…")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            Keychain.save(key)
            GeminiEngine.model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty, Backend.current == .gemini { Backend.current = .local }
            return !key.isEmpty
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(URL(string: "https://aistudio.google.com/apikey")!)
            return false
        default:
            return false
        }
    }

    // MARK: - Actions

    @objc private func translateSelection() {
        showAssistant(.translate)
    }

    @objc private func improveSelection() {
        showAssistant(.improve)
    }

    private func showAssistant(_ mode: AssistantMode) {
        let mouse = NSEvent.mouseLocation
        let sourceApp = NSWorkspace.shared.frontmostApplication
        Task { @MainActor in
            guard let text = await SelectionReader.selectedText(), !text.isBlank else {
                if Accessibility.isTrusted {
                    NSSound.beep() // nothing selected
                } else {
                    showAccessibilityAlert()
                }
                return
            }
            assistantPanel.show(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                mode: mode, near: mouse, sourceApp: sourceApp
            )
        }
    }

    @objc private func toggleMeeting() {
        meetingPanel.toggle()
    }

    @objc private func selectMeetingSource(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let source = MeetingSource(rawValue: raw) else { return }
        MeetingSource.preferred = source
    }

    @objc private func unloadModel() {
        LLMEngine.shared.unload()
    }

    @objc private func chooseModelFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a GGUF language model"
        panel.allowedContentTypes = [UTType(filenameExtension: "gguf") ?? .data]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ModelLocator.select(url)
        LLMEngine.shared.unload() // the next request loads the new model
    }

    func applicationWillTerminate(_ notification: Notification) {
        LLMEngine.shared.unload()
    }

    @objc private func openAccessibilitySettings() {
        Accessibility.openSystemSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Wordbridge needs Accessibility access"
        alert.informativeText = "To read the text you select in other apps, allow Wordbridge in System Settings › Privacy & Security › Accessibility."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            Accessibility.openSystemSettings()
        }
    }
}
