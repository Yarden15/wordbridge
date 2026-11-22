import AppKit
import SwiftUI

// MARK: - Translator

enum Translator {
    static func translate(_ text: String, from source: AppLanguage, to target: AppLanguage) async throws -> String {
        let system = "You are a professional translator. Translate the user's text from \(source.englishName) "
            + "to \(target.englishName). Keep the meaning, tone and formatting. "
            + "Output only the translation, nothing else."
        let maxTokens = max(200, text.count * 3)
        switch await Backend.current {
        case .local: return try await LLMEngine.shared.complete(system: system, user: text, maxTokens: maxTokens)
        case .gemini: return try await GeminiEngine.complete(system: system, user: text, maxTokens: maxTokens)
        }
    }
}

// MARK: - Model

@MainActor
final class TranslationModel: ObservableObject {
    let text: String
    @Published private(set) var source: AppLanguage
    @Published private(set) var target: AppLanguage
    @Published var result: String?
    @Published var errorMessage: String?
    private var task: Task<Void, Never>?

    init(text: String) {
        self.text = text
        (source, target) = AppLanguage.direction(for: text)
        start()
    }

    func swapDirection() {
        (source, target) = (target, source)
        start()
    }

    func cancel() {
        task?.cancel()
    }

    private func start() {
        task?.cancel()
        result = nil
        errorMessage = nil
        let (text, source, target) = (text, source, target)
        task = Task {
            do {
                let translation = try await Translator.translate(text, from: source, to: target)
                guard !Task.isCancelled else { return }
                result = translation
            } catch {
                guard !Task.isCancelled else { return } // the panel was closed

                errorMessage = error.localizedDescription
            }
        }
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
    @ObservedObject var engine = LLMEngine.shared
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
                .fixedSize(horizontal: false, vertical: true)
        } else if case .loading(let started) = engine.state {
            loadingProgress(started: started)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Translating…").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// The model can take a while to load (minutes from a slow external drive), so show real progress.
    private func loadingProgress(started: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = context.date.timeIntervalSince(started)
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: min(elapsed / engine.expectedLoadSeconds, 0.97))
                Text("Loading language model… \(Int(elapsed))s of ~\(Int(engine.expectedLoadSeconds))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    private var outsideClickMonitor: Any?
    private var model: TranslationModel?

    func show(text: String, near point: NSPoint) {
        panel?.close()

        let model = TranslationModel(text: text)
        self.model = model
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
        startOutsideClickMonitor(for: model)
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

    /// Closes the panel when the user clicks in another app — but only once the translation is done.
    /// While it's still loading, macOS may show its own language-download prompt, and clicking
    /// that must not close us. (We don't close on resign-key for the same reason.)
    private func startOutsideClickMonitor(for model: TranslationModel) {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak model] _ in
            MainActor.assumeIsolated {
                guard let model, model.result != nil || model.errorMessage != nil else { return }
                self?.panel?.close()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    func windowWillClose(_ notification: Notification) {
        stopOutsideClickMonitor()
        model?.cancel()
        model = nil
        panel = nil
    }
}
