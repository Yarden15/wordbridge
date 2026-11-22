import Foundation

/// Supported languages. Start with Hebrew ⇄ English; add more here later.
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case hebrew = "he"

    var locale: Locale.Language { Locale.Language(identifier: rawValue) }
    /// The locale used for speech recognition.
    var speechLocale: Locale {
        switch self {
        case .english: Locale(identifier: "en-US")
        case .hebrew: Locale(identifier: "he-IL")
        }
    }
    var isRightToLeft: Bool { self == .hebrew }

    /// Name used in prompts to the language model.
    var englishName: String {
        switch self {
        case .english: "English"
        case .hebrew: "Hebrew"
        }
    }

    var displayName: String {
        switch self {
        case .english: "English"
        case .hebrew: "עברית"
        }
    }

    /// Picks the translation direction from the text's script: Hebrew text → English, anything else → Hebrew.
    static func direction(for text: String) -> (source: AppLanguage, target: AppLanguage) {
        var hebrew = 0, latin = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0590...0x05FF: hebrew += 1
            case 0x0041...0x005A, 0x0061...0x007A: latin += 1
            default: break
            }
        }
        return hebrew > latin ? (.hebrew, .english) : (.english, .hebrew)
    }
}

extension String {
    var containsHebrew: Bool { unicodeScalars.contains { (0x0590...0x05FF).contains($0.value) } }
}
