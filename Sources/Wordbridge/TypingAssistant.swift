import AppKit
import ApplicationServices
import SwiftUI

/// Fix as you type: watches the text field you're typing in (any app), and when you pause after
/// an English sentence, checks it. If something should be fixed, a small badge appears next to the
/// field; clicking it selects the sentence and opens the Improve window with the suggestions.
///
/// Reads text through Accessibility only while this is turned on, never in password fields,
/// and not in terminals or code editors.
@MainActor
final class TypingAssistant {
    static let enabledKey = "checkWhileTyping"
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Opens the Improve window for a sentence that was just selected in `app`.
    var onOpen: (_ sentence: String, _ check: WritingCheck, _ point: NSPoint, _ app: NSRunningApplication) -> Void = { _, _, _, _ in }

    private var timer: Timer?
    private var element: AXUIElement?
    private var app: NSRunningApplication?
    private var lastValue: String?
    private var lastChange = Date()
    private var checkedValue: String?
    private var checkTask: Task<Void, Never>?
    private var cache: [String: WritingCheck] = [:]
    private var preparedApps = Set<pid_t>()
    private let badge = TypingBadge()

    private static let excludedApps: [String] = [
        "io.github.wordbridge", "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "com.microsoft.VSCode", "com.apple.dt.Xcode", "com.jetbrains", "com.sublimetext", "com.todesktop.230313mzl4w4u92", // Cursor
        "com.1password", "com.agilebits", "com.apple.keychainaccess", "com.bitwarden",
    ]

    func refresh() {
        if Self.isEnabled { start() } else { stop() }
    }

    private func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        checkTask?.cancel()
        badge.hide()
        element = nil
    }

    // MARK: Watching

    private func tick() {
        guard Accessibility.isTrusted,
              let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              !Self.excludedApps.contains(where: { bundleID.hasPrefix($0) })
        else { return reset() }

        prepare(app)
        guard let field = focusedTextField(), let value = AXTree.string(field, kAXValueAttribute) else {
            return reset()
        }
        if element == nil || !CFEqual(element!, field) {
            reset()
            element = field
            self.app = app
            lastValue = value
            checkedValue = value // don't check what was already there when you clicked in
            return
        }
        if value != lastValue {
            lastValue = value
            lastChange = Date()
            if badge.isVisible, !value.contains(badge.sentence) { badge.hide() }
            return
        }
        if checkedValue != value, Date().timeIntervalSince(lastChange) > 1.3 {
            checkedValue = value
            check(value, in: field, app: app)
        }
    }

    private func reset() {
        element = nil
        lastValue = nil
        checkTask?.cancel()
        badge.hide()
    }

    /// Chromium and Electron apps (Slack, Teams, browsers) only expose their text when asked.
    private func prepare(_ app: NSRunningApplication) {
        guard preparedApps.insert(app.processIdentifier).inserted else { return }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private func focusedTextField() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.3)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement
        guard AXTree.string(element, kAXSubroleAttribute) != kAXSecureTextFieldSubrole as String else { return nil }
        let role = AXTree.role(element)
        guard role == kAXTextAreaRole as String || role == kAXTextFieldRole as String || role == kAXComboBoxRole as String
        else { return nil }
        return element
    }

    // MARK: Checking

    private func check(_ value: String, in field: AXUIElement, app: NSRunningApplication) {
        guard let caret = selectedRange(of: field)?.location,
              let (sentence, range) = Self.sentence(in: value, around: caret),
              Self.worthChecking(sentence)
        else { return }

        if let cached = cache[sentence] {
            show(cached, sentence: sentence, range: range, in: field, app: app)
            return
        }
        checkTask?.cancel()
        checkTask = Task {
            guard let result = try? await WritingAssistant.check(sentence), !Task.isCancelled else { return }
            if cache.count > 300 { cache.removeAll() }
            cache[sentence] = result
            // Still the same field and the sentence is still there?
            guard let element, CFEqual(element, field), lastValue?.contains(sentence) == true else { return }
            show(result, sentence: sentence, range: range, in: field, app: app)
        }
    }

    private func show(_ check: WritingCheck, sentence: String, range: NSRange, in field: AXUIElement, app: NSRunningApplication) {
        // Only real mistakes: "already fine, here's a nicer way" isn't worth interrupting for.
        guard !check.ok, let first = check.suggestions.first else { return badge.hide() }
        let changes = WordTokens.diff(original: sentence, revised: first.text).filter(\.changed).count
        let point = badgePoint(for: range, in: field)
        badge.show(count: max(changes, 1), sentence: sentence, at: point) { [weak self] in
            self?.open(sentence: sentence, range: range, check: check, field: field, app: app, point: point)
        }
    }

    private func open(sentence: String, range: NSRange, check: WritingCheck, field: AXUIElement, app: NSRunningApplication, point: NSPoint) {
        badge.hide()
        // Select the sentence so "Replace" pastes over exactly it.
        var cfRange = CFRange(location: range.location, length: range.length)
        if let value = AXValueCreate(.cfRange, &cfRange) {
            AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, value)
        }
        onOpen(sentence, check, point, app)
    }

    // MARK: Text helpers

    private func selectedRange(of field: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    /// The sentence the caret is in (or just after), in UTF-16 offsets like Accessibility uses.
    static func sentence(in text: String, around caret: Int) -> (String, NSRange)? {
        let string = text as NSString
        let caret = min(max(caret, 0), string.length)
        var found: (String, NSRange)?
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .bySentences) { sentence, range, _, stop in
            if range.location <= max(caret - 1, 0), caret <= NSMaxRange(range), let sentence {
                found = (sentence, range)
                stop.pointee = true
            }
        }
        guard var (sentence, range) = found else { return nil }
        // Don't include trailing spaces and newlines in what gets replaced.
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let leading = (sentence as NSString).range(of: trimmed).location
        range = NSRange(location: range.location + leading, length: (trimmed as NSString).length)
        sentence = trimmed
        return (sentence, range)
    }

    /// Not in your own language, at least a few words, and not huge.
    static func worthChecking(_ sentence: String) -> Bool {
        guard sentence.count <= 600, AppLanguage.detect(sentence) != AppLanguage.native else { return false }
        let words = sentence.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: \.isLetter) }
        return words.count >= 3 && sentence.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 10
    }

    /// Just below the end of the sentence when the app can tell where it is, else the field's corner.
    private func badgePoint(for range: NSRange, in field: AXUIElement) -> NSPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var cfRange = CFRange(location: max(NSMaxRange(range) - 1, 0), length: 1)
        if let rangeValue = AXValueCreate(.cfRange, &cfRange) {
            var bounds: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(field, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &bounds) == .success,
               let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() {
                var rect = CGRect.zero
                if AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 {
                    return NSPoint(x: rect.maxX + 4, y: primaryHeight - rect.maxY - 2)
                }
            }
        }
        var position: CFTypeRef?
        var size: CFTypeRef?
        var origin = CGPoint.zero
        var extent = CGSize.zero
        if AXUIElementCopyAttributeValue(field, kAXPositionAttribute as CFString, &position) == .success, let position,
           AXUIElementCopyAttributeValue(field, kAXSizeAttribute as CFString, &size) == .success, let size {
            AXValueGetValue(position as! AXValue, .cgPoint, &origin)
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
        }
        return NSPoint(x: origin.x + extent.width - 28, y: primaryHeight - origin.y - extent.height + 4)
    }
}

// MARK: - Badge

/// The small "N fixes" circle shown next to the text you're typing.
@MainActor
private final class TypingBadge {
    private var panel: NSPanel?
    private(set) var sentence = ""
    private var action: () -> Void = {}

    var isVisible: Bool { panel?.isVisible == true }

    func show(count: Int, sentence: String, at point: NSPoint, action: @escaping () -> Void) {
        self.sentence = sentence
        self.action = action
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: BadgeView(count: count) { [weak self] in self?.action() })
        panel.setFrame(NSRect(x: point.x, y: point.y - 24, width: 26, height: 24), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        sentence = ""
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 26, height: 24),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        return panel
    }
}

private struct BadgeView: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.orange))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help("Wordbridge has a suggestion for this sentence — click to see it")
        .frame(width: 26, height: 24)
    }
}
