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
    for flag in ["--check", "--gloss"] {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { continue }
        let text = args[index + 1]
        Task { @MainActor in
            let started = Date()
            do {
                if flag == "--check" {
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

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
