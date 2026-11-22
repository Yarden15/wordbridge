import AppKit
import ApplicationServices
import Carbon

/// Reads the text the user has selected in whatever app is in front.
enum SelectionReader {
    /// Tries the Accessibility API first (clean, no side effects). Many apps (Chrome, Electron)
    /// don't expose selections that way, so it falls back to simulating ⌘C and restoring the clipboard.
    @MainActor
    static func selectedText() async -> String? {
        if let text = accessibilitySelectedText(), !text.isBlank { return text }
        guard Accessibility.isTrusted else { return nil } // posting ⌘C needs the permission too
        return await copySelectionViaPasteboard()
    }

    // MARK: - Accessibility

    private static func accessibilitySelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }

        let element = focused as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    // MARK: - Clipboard fallback

    @MainActor
    private static func copySelectionViaPasteboard() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let changeCountBefore = pasteboard.changeCount

        // The hotkey fires while ⌘⇧⌥ are still held; wait so they don't merge into our ⌘C.
        await waitForModifiersReleased()
        postCommandC()

        for _ in 0..<25 where pasteboard.changeCount == changeCountBefore {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        guard pasteboard.changeCount != changeCountBefore else { return nil }

        let text = pasteboard.string(forType: .string)
        restore(saved, to: pasteboard)
        return text
    }

    // MARK: - Replacing the selection

    /// Types `text` over the current selection in `app` by pasting it, then restores the clipboard.
    /// Pasting works in every kind of text field (native, web, Electron), unlike setting the
    /// selection through Accessibility, which many apps silently ignore.
    @MainActor
    static func replaceSelection(with text: String, in app: NSRunningApplication?) async -> Bool {
        guard Accessibility.isTrusted else { return false }
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        if let app, !app.isActive {
            app.activate()
            try? await Task.sleep(for: .milliseconds(150))
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        await waitForModifiersReleased()
        postCommand(key: kVK_ANSI_V)

        // Give the app time to read the clipboard before putting the old contents back.
        try? await Task.sleep(for: .milliseconds(400))
        restore(saved, to: pasteboard)
        return true
    }

    private static func waitForModifiersReleased() async {
        let held: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        for _ in 0..<50 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection(held).isEmpty { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private static func postCommandC() {
        postCommand(key: kVK_ANSI_C)
    }

    private static func postCommand(key: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
