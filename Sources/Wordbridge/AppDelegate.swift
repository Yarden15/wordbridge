import AppKit
import Carbon
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var translateHotKey: HotKey?
    private let translationPanel = TranslationPanelController()

    private let accessibilityItem = NSMenuItem()
    private let launchAtLoginItem = NSMenuItem()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        // ⌘⇧⌥T — translate the current selection.
        translateHotKey = HotKey(
            id: 1, keyCode: kVK_ANSI_T, modifiers: cmdKey | shiftKey | optionKey
        ) { [weak self] in
            self?.translateSelection()
        }

        Accessibility.requestIfNeeded()
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
    }

    // MARK: - Actions

    @objc private func translateSelection() {
        let mouse = NSEvent.mouseLocation
        Task { @MainActor in
            guard let text = await SelectionReader.selectedText(), !text.isBlank else {
                if Accessibility.isTrusted {
                    NSSound.beep() // nothing selected
                } else {
                    showAccessibilityAlert()
                }
                return
            }
            translationPanel.show(text: text.trimmingCharacters(in: .whitespacesAndNewlines), near: mouse)
        }
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
