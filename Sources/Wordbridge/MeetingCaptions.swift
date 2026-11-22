import AppKit
import ApplicationServices

/// A meeting app Wordbridge knows how to follow.
struct MeetingApp {
    enum Kind { case zoom, meet }
    let kind: Kind
    let app: NSRunningApplication

    var name: String { kind == .zoom ? "Zoom" : "Google Meet" }

    /// Bundle-ID prefixes of the processes that play this app's sound.
    var audioBundlePrefixes: [String] {
        switch kind {
        case .zoom: ["us.zoom"]
        case .meet: [app.bundleIdentifier ?? "com.google.Chrome"]
        }
    }

    static let browsers = ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser"]

    /// The meeting in progress: a Zoom meeting window, or a browser window showing Google Meet.
    @MainActor
    static func current() -> MeetingApp? {
        if let zoom = NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos").first,
           AXTree.windows(of: zoom).contains(where: { AXTree.title($0)?.hasPrefix("Zoom Meeting") == true }) {
            return MeetingApp(kind: .zoom, app: zoom)
        }
        for id in browsers {
            for browser in NSRunningApplication.runningApplications(withBundleIdentifier: id) {
                if AXTree.windows(of: browser).contains(where: { AXTree.title($0)?.hasPrefix("Meet") == true }) {
                    return MeetingApp(kind: .meet, app: browser)
                }
            }
        }
        return nil
    }
}

/// One line of the meeting's own captions or transcript.
struct CaptionLine: Equatable {
    /// Something that stays the same while the line grows (Zoom's timestamp), when there is one.
    let key: String?
    let speaker: String?
    let text: String
}

/// Reads the captions a meeting app shows, through the Accessibility API.
/// - Google Meet: the "Captions" region of the page (turn on captions in Meet).
/// - Zoom: the "Transcript" panel (Captions › View full transcript). Zoom's caption overlay
///   is drawn as an image and can't be read.
@MainActor
final class CaptionReader {
    let meeting: MeetingApp
    private let root: AXUIElement
    private var container: AXUIElement?

    init(meeting: MeetingApp) {
        self.meeting = meeting
        root = AXUIElementCreateApplication(meeting.app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        if meeting.kind == .meet {
            // Chromium builds the web page's accessibility tree only when asked to.
            AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
    }

    /// The lines currently shown, oldest first; nil when the captions aren't on screen.
    func read() -> [CaptionLine]? {
        if container == nil || AXTree.role(container!) == nil {
            container = find()
        }
        guard let container else { return nil }
        switch meeting.kind {
        case .meet: return Self.meetLines(in: container)
        case .zoom: return Self.zoomLines(in: container)
        }
    }

    private func find() -> AXUIElement? {
        switch meeting.kind {
        case .meet:
            return AXTree.first(in: root, maxDepth: 40) { element in
                guard AXTree.string(element, kAXSubroleAttribute) == "AXLandmarkRegion" else { return false }
                let title = AXTree.title(element) ?? ""
                let classes = AXTree.string(element, "AXDOMClassList") ?? ""
                return Self.meetCaptionTitles.contains(title) || classes.contains("vNKgIf")
            }
        case .zoom:
            // The transcript table: rows that start with a time like 21:21:05.
            return AXTree.first(in: root, maxDepth: 12) { element in
                guard AXTree.role(element) == kAXTableRole as String else { return false }
                return AXTree.children(element).prefix(6).contains { row in
                    AXTree.descendants(of: row, maxDepth: 3).contains { Self.isTime(AXTree.string($0, kAXValueAttribute)) }
                }
            }
        }
    }

    // Meet: region › one group per speaker turn › [speaker name group, text group › one static text per sentence]
    private static let meetCaptionTitles: Set<String> = ["Captions", "כתוביות", "Subtitles", "Untertitel", "Sous-titres", "Subtítulos"]

    private static func meetLines(in region: AXUIElement) -> [CaptionLine] {
        var lines: [CaptionLine] = []
        for block in AXTree.children(region) {
            let parts = AXTree.children(block)
            guard parts.count >= 2 else { continue }
            let speaker = staticTexts(in: parts[0]).joined(separator: " ")
            for part in parts.dropFirst() {
                for text in staticTexts(in: part) where !text.isBlank {
                    lines.append(CaptionLine(key: nil, speaker: speaker.isEmpty ? nil : speaker, text: text))
                }
            }
        }
        return lines
    }

    // Zoom: table › rows. A row is either [avatar, name] (a new speaker) or [time, text].
    private static func zoomLines(in table: AXUIElement) -> [CaptionLine] {
        var lines: [CaptionLine] = []
        var speaker: String?
        for row in AXTree.children(table) where AXTree.role(row) == kAXRowRole as String {
            let values = AXTree.descendants(of: row, maxDepth: 3)
                .filter { AXTree.role($0) == kAXTextAreaRole as String || AXTree.role($0) == kAXStaticTextRole as String }
                .compactMap { AXTree.string($0, kAXValueAttribute) }
                .filter { !$0.isBlank }
            if values.count >= 2, isTime(values[0]) {
                let text = values.dropFirst().joined(separator: " ")
                lines.append(CaptionLine(key: "\(speaker ?? "")|\(values[0])", speaker: speaker, text: text))
            } else if let name = values.first, !isTime(name) {
                speaker = name
            }
        }
        return lines
    }

    private static func staticTexts(in element: AXUIElement) -> [String] {
        AXTree.descendants(of: element, maxDepth: 4)
            .filter { AXTree.role($0) == kAXStaticTextRole as String }
            .compactMap { AXTree.string($0, kAXValueAttribute) }
    }

    private static func isTime(_ text: String?) -> Bool {
        guard let text else { return false }
        return text.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil
    }

    /// How Meet labels your own captions.
    static func isSelf(_ speaker: String?) -> Bool {
        guard let speaker else { return false }
        return ["You", "את/ה", "אתה", "את", "Du", "Vous", "Tú"].contains(speaker)
    }
}

/// Small helpers over the Accessibility C API.
@MainActor
enum AXTree {
    static func windows(of app: NSRunningApplication) -> [AXUIElement] {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        return elements(root, kAXWindowsAttribute)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        elements(element, kAXChildrenAttribute).filter { !CFEqual($0, element) }
    }

    static func role(_ element: AXUIElement) -> String? { string(element, kAXRoleAttribute) }
    static func title(_ element: AXUIElement) -> String? { string(element, kAXTitleAttribute) }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        if let text = value as? String { return text }
        if let list = value as? [String] { return list.joined(separator: ".") }
        return nil
    }

    static func descendants(of element: AXUIElement, maxDepth: Int) -> [AXUIElement] {
        var result: [AXUIElement] = []
        func walk(_ element: AXUIElement, _ depth: Int) {
            guard depth < maxDepth else { return }
            for child in children(element) {
                result.append(child)
                walk(child, depth + 1)
            }
        }
        walk(element, 0)
        return result
    }

    /// Breadth-first search, so shallow matches are found without walking the whole tree.
    static func first(in root: AXUIElement, maxDepth: Int, where match: (AXUIElement) -> Bool) -> AXUIElement? {
        var level = [root]
        var visited = 0
        for _ in 0..<maxDepth {
            var next: [AXUIElement] = []
            for element in level {
                if match(element) { return element }
                next.append(contentsOf: children(element))
                visited += 1
                if visited > 20_000 { return nil }
            }
            if next.isEmpty { return nil }
            level = next
        }
        return nil
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list
    }
}
