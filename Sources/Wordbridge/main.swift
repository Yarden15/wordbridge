import AppKit

MainActor.assumeIsolated {
    // Developer self-test: `Wordbridge.app/Contents/MacOS/Wordbridge --translate "some text"`
    // runs the same model path the panel uses and prints the result.
    let args = CommandLine.arguments
    if let flag = args.firstIndex(of: "--translate"), flag + 1 < args.count {
        let text = args[flag + 1]
        Task { @MainActor in
            let (source, target) = AppLanguage.direction(for: text)
            let started = Date()
            do {
                let result = try await Translator.translate(text, from: source, to: target)
                print("[\(source.rawValue)→\(target.rawValue)] \(result)")
                print(String(format: "took %.1fs", Date().timeIntervalSince(started)))
                LLMEngine.shared.unload()
                exit(0)
            } catch {
                print("error: \(error.localizedDescription)")
                LLMEngine.shared.unload()
                exit(1)
            }
        }
        RunLoop.main.run()
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
