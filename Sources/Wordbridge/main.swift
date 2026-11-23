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

    // Developer self-tests for the writing check and word meanings:
    //   Wordbridge --check "text"    Wordbridge --gloss "text"
    //   Wordbridge --sayit "text"    Wordbridge --summarize "Dana: …⏎Tom: …"
    for flag in ["--check", "--gloss", "--sayit", "--summarize"] {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { continue }
        let text = args[index + 1]
        Task { @MainActor in
            let started = Date()
            do {
                if flag == "--sayit" {
                    for option in try await SayIt.phrasings(for: text) {
                        print("• \(option.text)\n  \(option.note ?? "")")
                    }
                } else if flag == "--summarize" {
                    let summary = try await MeetingSummarizer.summarize(transcript: text, in: AppLanguage.native)
                    print(summary.asText(title: "Summary"))
                } else if flag == "--check" {
                    let check = try await WritingAssistant.check(text)
                    print("ok: \(check.ok)")
                    for suggestion in check.suggestions {
                        let marked = WordTokens.diff(original: text, revised: suggestion.text)
                            .map { ($0.changed ? "[\($0.text)]" : $0.text) + $0.trailing }.joined()
                        print("• \(marked)\n  \(suggestion.explanation ?? "")")
                    }
                } else {
                    let glosses = try await Glossary.gloss(text)
                    for token in WordTokens.split(text) {
                        guard let gloss = glosses[token.id] else { print("\(token.text) → ?"); continue }
                        let phrase = gloss.phrase.map { "   [\($0) = \(gloss.phraseMeaning ?? "")]" } ?? ""
                        print("\(token.text) → \(gloss.meaning)\(phrase)")
                    }
                }
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

    // Developer self-test for voice recognition: listens to all sound on the Mac (or, with `mic`,
    // the microphone) for N seconds and writes what it heard to a file.
    //   open Wordbridge.app --args --listen 30 /tmp/heard.txt [en|he] [mic]
    // Launch with `open` so the app's own permissions apply.
    if let flag = args.firstIndex(of: "--listen"), flag + 2 < args.count, #available(macOS 26, *) {
        let seconds = Double(args[flag + 1]) ?? 20
        let output = args[flag + 2]
        var log: [String] = []
        let language = AppLanguage(rawValue: args.dropFirst(flag + 3).first ?? "") ?? .english
        let input: MeetingListener.Input = args.contains("mic") ? .microphone : .app(nil)
        let listener = MeetingListener(input: input, language: language) { event in
            switch event {
            case .status(let text): log.append("status: \(text)")
            case .partial: break
            case .final(let text): log.append("heard: \(text)")
            case .failed(let text): log.append("failed: \(text)")
            }
            try? log.joined(separator: "\n").write(toFile: output, atomically: true, encoding: .utf8)
        }
        Task { @MainActor in
            await listener.start()
            try? await Task.sleep(for: .seconds(seconds))
            listener.stop()
            log.append("done")
            try? log.joined(separator: "\n").write(toFile: output, atomically: true, encoding: .utf8)
            exit(0)
        }
        RunLoop.main.run()
    }

    if let flag = args.firstIndex(of: "--ax-dump"), flag + 2 < args.count {
        AXDump.run(bundleID: args[flag + 1], output: args[flag + 2])
        RunLoop.main.run()
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
