import Foundation

/// Supported languages. Start with Hebrew ⇄ English; add more here later.
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case hebrew = "he"

    var locale: Locale.Language { Locale.Language(identifier: rawValue) }
    var isRightToLeft: Bool { self == .hebrew }

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
