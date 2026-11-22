import AppKit
import Foundation

/// Runs the local language model in a separate `llama-server` process, only while it's needed.
///
/// - Nothing is loaded at app start. The first request starts the server.
/// - After an idle period the server is stopped and all its memory goes back to the OS
///   (5 min normally, 30 min when the model sits on an external drive, where loading is slow).
/// - Memory pressure or unmounting the model's drive stops it immediately.
@MainActor
final class LLMEngine: ObservableObject {
    static let shared = LLMEngine()

    enum State: Equatable {
        case unloaded
        case loading(started: Date)
        case ready
        case failed(String)
    }

    enum EngineError: LocalizedError {
        case modelNotFound
        case serverNotFound
        case serverExited
        case loadTimedOut
        case badResponse(String)
        case interrupted

        var errorDescription: String? {
            switch self {
            case .modelNotFound:
                "No language model found. Put a model (e.g. gemma-4-E4B-it-Q4_K_M.gguf) in "
                    + "~/Library/Application Support/Wordbridge/models or <drive>/Wordbridge/models, "
                    + "or choose one from the menu."
            case .serverNotFound:
                "llama-server not found. Put llama.cpp next to the models folder, or install it with Homebrew."
            case .serverExited: "The language model stopped unexpectedly."
            case .loadTimedOut: "Loading the language model took too long."
            case .badResponse(let detail): "Unexpected response from the language model: \(detail)"
            case .interrupted: "The language model was stopped before it finished. Try again."
            }
        }
    }

    @Published private(set) var state: State = .unloaded

    private var process: Process?
    private var port = 0
    private var loadTask: Task<Void, Error>?
    private var idleTimer: Timer?
    private var activeRequests = 0
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private static let pidKey = "llamaServerPID"
    /// Load time is remembered per model file, since models differ a lot in size.
    private static func lastLoadSecondsKey(for model: URL?) -> String {
        "lastModelLoadSeconds." + (model?.lastPathComponent ?? "")
    }

    private init() {
        killStaleServer()
        observeMemoryPressure()
        observeUnmount()
    }

    // MARK: - Public

    var modelName: String? { ModelLocator.modelURL.map(ModelLocator.displayName(for:)) }

    /// How long the last load took; used to show approximate progress.
    var expectedLoadSeconds: Double {
        let last = UserDefaults.standard.double(forKey: Self.lastLoadSecondsKey(for: ModelLocator.modelURL))
        return last > 0 ? last : 60
    }

    /// Starts loading in the background if needed (e.g. as soon as a panel opens).
    func warmUp() {
        Task { try? await ensureLoaded() }
    }

    func complete(system: String, user: String, maxTokens: Int = 400) async throws -> String {
        activeRequests += 1
        defer { activeRequests -= 1 }
        do {
            try await ensureLoaded()
        } catch is CancellationError where !Task.isCancelled {
            // The load was stopped by someone else (unload, drive unplugged), not by this caller.
            throw EngineError.interrupted
        }
        resetIdleTimer()
        defer { resetIdleTimer() }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": 0.2,
            "max_tokens": maxTokens,
            "chat_template_kwargs": ["enable_thinking": false],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw EngineError.badResponse("HTTP \(status)") }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw EngineError.badResponse("missing content") }

        return Self.clean(content)
    }

    func unload() {
        idleTimer?.invalidate()
        idleTimer = nil
        loadTask?.cancel()
        loadTask = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        UserDefaults.standard.removeObject(forKey: Self.pidKey)
        state = .unloaded
    }

    // MARK: - Loading

    private func ensureLoaded() async throws {
        if state == .ready, process?.isRunning == true { return }
        if let loadTask { return try await loadTask.value }

        let task = Task { try await self.load() }
        loadTask = task
        defer { loadTask = nil }
        try await task.value
    }

    private func load() async throws {
        guard let model = ModelLocator.modelURL else {
            state = .failed(EngineError.modelNotFound.localizedDescription)
            throw EngineError.modelNotFound
        }
        guard let server = ModelLocator.serverURL(forModel: model) else {
            state = .failed(EngineError.serverNotFound.localizedDescription)
            throw EngineError.serverNotFound
        }

        if let process, process.isRunning { process.terminate() }
        port = Self.freePort()

        let proc = Process()
        proc.executableURL = server
        proc.arguments = [
            "-m", model.path,
            "--host", "127.0.0.1", "--port", String(port),
            "-ngl", "99",      // run on the GPU (Metal)
            "-c", "4096",      // context size; plenty for sentences
            "--no-webui", "--log-disable",
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.terminationHandler = { [weak self] exited in
            Task { @MainActor in self?.processDidExit(exited) }
        }
        try proc.run()
        process = proc
        UserDefaults.standard.set(Int(proc.processIdentifier), forKey: Self.pidKey)

        let started = Date()
        state = .loading(started: started)

        while true {
            try Task.checkCancellation()
            guard proc.isRunning else {
                state = .failed(EngineError.serverExited.localizedDescription)
                throw EngineError.serverExited
            }
            if await isHealthy() { break }
            if Date().timeIntervalSince(started) > 900 {
                unload()
                throw EngineError.loadTimedOut
            }
            try await Task.sleep(for: .milliseconds(500))
        }

        UserDefaults.standard.set(Date().timeIntervalSince(started), forKey: Self.lastLoadSecondsKey(for: model))
        state = .ready
        resetIdleTimer()
    }

    private func isHealthy() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/health")!)
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private func processDidExit(_ exited: Process) {
        guard exited === process else { return }
        process = nil
        UserDefaults.standard.removeObject(forKey: Self.pidKey)
        if case .failed = state { return }
        state = .unloaded
    }

    // MARK: - Staying light

    private var idleTimeout: TimeInterval {
        let onExternalDrive = ModelLocator.modelURL?.path.hasPrefix("/Volumes/") ?? false
        return onExternalDrive ? 30 * 60 : 5 * 60
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) { _ in
            Task { @MainActor in LLMEngine.shared.unload() }
        }
    }

    private func observeMemoryPressure() {
        // Only on *critical* pressure, and never in the middle of a load or a request:
        // loading a multi-GB model triggers a "warning" by itself.
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.critical], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                let engine = LLMEngine.shared
                guard engine.loadTask == nil, engine.activeRequests == 0 else { return }
                engine.unload()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func observeUnmount() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main
        ) { note in
            guard let volume = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated {
                let engine = LLMEngine.shared
                guard engine.process != nil || engine.loadTask != nil else { return }
                guard let model = engine.process?.arguments?[1], model.hasPrefix(volume.path) else { return }
                engine.unload()
                engine.state = .failed("The drive with the language model was disconnected.")
            }
        }
    }

    /// If the app crashed last time, its llama-server may still be running. Stop it —
    /// but only if it's orphaned (parent gone), so we never kill a server that another
    /// running Wordbridge instance owns.
    private func killStaleServer() {
        let pid = UserDefaults.standard.integer(forKey: Self.pidKey)
        guard pid > 0 else { return }

        let ps = Process()
        ps.executableURL = URL(filePath: "/bin/ps")
        ps.arguments = ["-p", String(pid), "-o", "ppid=,comm="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        try? ps.run()
        ps.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.pidKey) // already gone
            return
        }
        let parent = Int(output.split(separator: " ").first ?? "") ?? 0
        guard output.contains("llama-server"), parent == 1 else { return }
        UserDefaults.standard.removeObject(forKey: Self.pidKey)
        kill(pid_t(pid), SIGTERM)
    }

    // MARK: - Helpers

    /// Asks the OS for a free localhost port.
    private static func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = bind(fd, $0, length)
                _ = getsockname(fd, $0, &length)
            }
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }

    /// Removes ``` fences some models wrap around their answer.
    static func clean(_ text: String) -> String {
        var lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
        if lines.last?.hasPrefix("```") == true { lines.removeLast() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
