import AppKit
import ApplicationServices

/// Developer tool: writes the accessibility tree of a running app to a file, so we can see
/// where an app (Zoom, Chrome) puts its live captions.
/// Usage: `open Wordbridge.app --args --ax-dump <bundle-id> <output-file>`
/// (launch with `open` so the app's own Accessibility permission applies).
@MainActor
enum AXDump {
    static func run(bundleID: String, output: String) {
        var lines: [String] = []
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !apps.isEmpty else {
            write(["no running app with bundle id \(bundleID)"], to: output)
            return
        }
        lines.append("trusted: \(AXIsProcessTrusted())")
        for app in apps {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            // Chromium builds its web accessibility tree only when asked to.
            AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(root, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        // Give Chromium a moment to build the tree.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            for app in apps {
                lines.append("=== pid \(app.processIdentifier) \(app.localizedName ?? "")")
                var count = 0
                walk(AXUIElementCreateApplication(app.processIdentifier), depth: 0, count: &count, into: &lines)
                lines.append("=== \(count) elements")
            }
            write(lines, to: output)
            exit(0)
        }
    }

    private static func walk(_ element: AXUIElement, depth: Int, count: inout Int, into lines: inout [String]) {
        guard depth < 60, count < 40_000 else { return }
        count += 1
        let role = string(element, kAXRoleAttribute) ?? "?"
        var parts = [role]
        if let subrole = string(element, kAXSubroleAttribute) { parts.append("sub=\(subrole)") }
        if let id = string(element, kAXIdentifierAttribute), !id.isEmpty { parts.append("id=\(id)") }
        for (label, attribute) in [("title", kAXTitleAttribute), ("value", kAXValueAttribute),
                                   ("desc", kAXDescriptionAttribute), ("help", kAXHelpAttribute)] {
            if let text = string(element, attribute), !text.isEmpty {
                parts.append("\(label)=\"\(text.prefix(300).replacingOccurrences(of: "\n", with: "⏎"))\"")
            }
        }
        if let dom = string(element, "AXDOMClassList" as String) { parts.append("class=\(dom)") }
        if role == "AXWindow" {
            var names: CFArray?
            if AXUIElementCopyAttributeNames(element, &names) == .success, let names = names as? [String] {
                parts.append("attrs=[\(names.joined(separator: ","))]")
            }
        }
        lines.append(String(repeating: "  ", count: depth) + parts.joined(separator: " "))

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return }
        // Some Zoom buttons list themselves as their own child.
        for child in children where !CFEqual(child, element) {
            walk(child, depth: depth + 1, count: &count, into: &lines)
        }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        if let text = value as? String { return text }
        if let list = value as? [String] { return list.joined(separator: ".") }
        if let number = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { return number.stringValue }
        return nil
    }

    private static func write(_ lines: [String], to path: String) {
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
