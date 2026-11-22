import Foundation

enum Translator {
    @MainActor
    static func translate(_ text: String, from source: AppLanguage, to target: AppLanguage) async throws -> String {
        let system = "You are a professional translator. Translate the user's text from \(source.englishName) "
            + "to \(target.englishName). Keep the meaning, tone and formatting. "
            + "Output only the translation, nothing else."
        return try await AI.complete(system: system, user: text, maxTokens: max(200, text.count * 3))
    }
}

/// One entry point for every AI request, whichever backend is selected (local model or Gemini).
@MainActor
enum AI {
    static func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        switch Backend.current {
        case .local: try await LLMEngine.shared.complete(system: system, user: user, maxTokens: maxTokens)
        case .gemini: try await GeminiEngine.complete(system: system, user: user, maxTokens: maxTokens)
        }
    }

    /// Asks for JSON and decodes it. Models sometimes wrap JSON in prose or code fences,
    /// so this decodes the outermost {...} or [...] in the reply.
    static func json<T: Decodable>(_ type: T.Type, system: String, user: String, maxTokens: Int) async throws -> T {
        let reply = try await complete(system: system, user: user, maxTokens: maxTokens)
        let open: Character = reply.firstIndex(of: "[").map { bracket in
            reply.firstIndex(of: "{").map { $0 < bracket ? "{" : "[" } ?? "["
        } ?? "{"
        let close: Character = open == "{" ? "}" : "]"
        guard let start = reply.firstIndex(of: open), let end = reply.lastIndex(of: close), start < end,
              let data = String(reply[start...end]).data(using: .utf8)
        else { throw AIError.notJSON(reply) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIError.notJSON(reply)
        }
    }

    enum AIError: LocalizedError {
        case notJSON(String)
        var errorDescription: String? {
            switch self {
            case .notJSON: "The AI's answer wasn't in the expected format. Try again."
            }
        }
    }
}
