import AppKit
import SwiftUI
import Translation

// MARK: - Model

@MainActor
final class TranslationModel: ObservableObject {
    let text: String
    @Published private(set) var source: AppLanguage
    @Published private(set) var target: AppLanguage
    @Published var result: String?
    @Published var errorMessage: String?
    @Published var configuration: TranslationSession.Configuration?

    init(text: String) {
        self.text = text
        (source, target) = AppLanguage.direction(for: text)
        start()
    }

    func swapDirection() {
        (source, target) = (target, source)
        start()
    }

    private func start() {
        result = nil
        errorMessage = nil
        // A new configuration makes `.translationTask` run again.
        configuration = TranslationSession.Configuration(source: source.locale, target: target.locale)
    }

    func copyResult() {
        guard let result else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }
}

// MARK: - View

struct TranslationView: View {
    @ObservedObject var model: TranslationModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            directional(Text(model.text), language: model.source)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(6)
            Divider()
            resultArea
        }
        .padding(14)
        .frame(width: 400, alignment: .leading)
        .translationTask(model.configuration) { session in
            do {
                // Apple's on-device translation. The first time, macOS asks to download the language pack.
                let response = try await session.translate(model.text)
                await MainActor.run { model.result = response.targetText }
            } catch {
                await MainActor.run { model.errorMessage = error.localizedDescription }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("\(model.source.displayName)  →  \(model.target.displayName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: model.swapDirection) { Image(systemName: "arrow.left.arrow.right") }
                .help("Swap direction")
            Button(action: model.copyResult) { Image(systemName: "doc.on.doc") }
                .help("Copy translation")
                .disabled(model.result == nil)
            Button(action: onClose) { Image(systemName: "xmark") }
                .help("Close (Esc)")
                .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var resultArea: some View {
        if let result = model.result {
            directional(Text(result), language: model.target)
                .font(.title3)
                .textSelection(.enabled)
        } else if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Translating…").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func directional(_ text: Text, language: AppLanguage) -> some View {
        text
            .multilineTextAlignment(language.isRightToLeft ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: language.isRightToLeft ? .trailing : .leading)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
            .fixedSize(horizontal: false, vertical: true)
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
final class TranslationPanelController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?

    func show(text: String, near point: NSPoint) {
        panel?.close()

        let model = TranslationModel(text: text)
        let hosting = NSHostingController(rootView: TranslationView(model: model) { [weak self] in
            self?.panel?.close()
        })
        hosting.sizingOptions = [.preferredContentSize]

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
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

        panel.setContentSize(hosting.view.fittingSize)
        panel.setFrameOrigin(origin(for: panel.frame.size, near: point))
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
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

    func windowDidResignKey(_ notification: Notification) {
        panel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }
}
