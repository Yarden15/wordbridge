import Foundation
import Security

/// Where translations run: the local model, or Google Gemini online (optional, needs your own free API key).
enum Backend: String {
    case local
    case gemini

    private static let key = "backend"

    static var current: Backend {
        get { Backend(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .local }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// Google Gemini through its OpenAI-compatible endpoint.
/// Get a free key at https://aistudio.google.com/apikey. Note: on the free tier Google may use
/// what you send to improve its products, so only use it for text you're fine sharing.
@MainActor
enum GeminiEngine {
    static let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
    /// Fast with excellent Hebrew in testing (Nov 2026, ~1.2 s per sentence). The newest Flash
    /// models were often overloaded on the free tier, and "-latest" pointed at one of them.
    static let defaultModel = "gemini-3.5-flash"
    /// Used automatically when the main model is busy, missing or slow. "-latest" keeps it working
    /// as Google retires models.
    static let fallbackModel = "gemini-flash-lite-latest"
    private static let modelKey = "geminiModel"

    static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey).flatMap { $0.isEmpty ? nil : $0 } ?? defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    enum GeminiError: LocalizedError {
        case noKey
        case invalidKey
        case rateLimited
        case http(Int, String)
        case badResponse
        case busy

        var errorDescription: String? {
            switch self {
            case .noKey: "No Gemini API key. Add one from the menu: Choose Model › Gemini API Key…"
            case .invalidKey: "Gemini rejected the API key. Check it in Choose Model › Gemini API Key…"
            case .rateLimited: "Gemini's free limit was reached. Wait a minute, or switch to the local model."
            case .http(let code, let detail): "Gemini error \(code): \(detail)"
            case .badResponse: "Unexpected response from Gemini."
            case .busy: "Gemini is overloaded right now. Try again in a moment, or switch to the local model."
            }
        }
    }

    static var hasKey: Bool { Keychain.read() != nil }

    static func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        guard let apiKey = Keychain.read() else { throw GeminiError.noKey }
        let models = model == fallbackModel ? [model] : [model, fallbackModel]
        var lastError: Error = GeminiError.busy
        for candidate in models {
            do {
                return try await complete(model: candidate, apiKey: apiKey, system: system, user: user, maxTokens: maxTokens)
            } catch let error as GeminiError {
                switch error {
                case .noKey, .invalidKey: throw error
                case .rateLimited, .badResponse, .busy, .http: lastError = error // try the next model
                }
            } catch let error as URLError where error.code == .timedOut {
                lastError = GeminiError.busy
            }
        }
        throw lastError
    }

    private static func complete(model: String, apiKey: String, system: String, user: String, maxTokens: Int) async throws -> String {
        // Low "thinking" is ~3x faster than the default for translation. ("none" made some models hang.)
        // If a model rejects the option, retry without it.
        do {
            return try await send(model: model, apiKey: apiKey, system: system, user: user, maxTokens: maxTokens, lowThinking: true)
        } catch GeminiError.http(400, let detail) where !detail.localizedCaseInsensitiveContains("API key") {
            return try await send(model: model, apiKey: apiKey, system: system, user: user, maxTokens: maxTokens, lowThinking: false)
        }
    }

    private static func send(model: String, apiKey: String, system: String, user: String,
                             maxTokens: Int, lowThinking: Bool) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": 0.2,
        ]
        if lowThinking { body["reasoning_effort"] = "low" }
        // No max_tokens: Gemini counts "thinking" against it, so a cap can cut the answer short.
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: break
        case 401, 403: throw GeminiError.invalidKey
        case 429: throw GeminiError.rateLimited
        case 500...599: throw GeminiError.busy
        default: throw GeminiError.http(status, errorMessage(from: data))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw GeminiError.badResponse }
        return LLMEngine.clean(content)
    }

    /// Pulls the human-readable message out of an error body (Google wraps it as [{error:{message}}] or {error:{message}}).
    private static func errorMessage(from data: Data) -> String {
        let json = try? JSONSerialization.jsonObject(with: data)
        let object = (json as? [[String: Any]])?.first ?? (json as? [String: Any])
        if let error = object?["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return String(decoding: data.prefix(200), as: UTF8.self)
    }
}

/// Stores the Gemini API key in the macOS Keychain (never in plain-text preferences).
enum Keychain {
    private static let service = "io.github.wordbridge.gemini"
    private static let account = "api-key"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        SecItemDelete(baseQuery as CFDictionary)
        guard !key.isEmpty else { return true }
        var item = baseQuery
        item[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
