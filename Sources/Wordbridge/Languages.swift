import Foundation
import NaturalLanguage

/// Supported languages. Add more here: the prompts, speech recognition and pickers all follow.
enum AppLanguage: String, CaseIterable, Codable {
    case english = "en"
    case hebrew = "he"
    case arabic = "ar"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case polish = "pl"
    case russian = "ru"
    case ukrainian = "uk"
    case turkish = "tr"
    case hindi = "hi"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"

    var locale: Locale.Language { Locale.Language(identifier: rawValue) }
    var isRightToLeft: Bool { self == .hebrew || self == .arabic }

    /// The locale used for speech recognition.
    var speechLocale: Locale {
        let identifier = switch self {
        case .english: "en-US"
        case .hebrew: "he-IL"
        case .arabic: "ar-SA"
        case .german: "de-DE"
        case .french: "fr-FR"
        case .spanish: "es-ES"
        case .italian: "it-IT"
        case .portuguese: "pt-BR"
        case .dutch: "nl-NL"
        case .polish: "pl-PL"
        case .russian: "ru-RU"
        case .ukrainian: "uk-UA"
        case .turkish: "tr-TR"
        case .hindi: "hi-IN"
        case .chinese: "zh-CN"
        case .japanese: "ja-JP"
        case .korean: "ko-KR"
        }
        return Locale(identifier: identifier)
    }

    /// Name used in prompts to the language model.
    var englishName: String {
        switch self {
        case .english: "English"
        case .hebrew: "Hebrew"
        case .arabic: "Arabic"
        case .german: "German"
        case .french: "French"
        case .spanish: "Spanish"
        case .italian: "Italian"
        case .portuguese: "Portuguese"
        case .dutch: "Dutch"
        case .polish: "Polish"
        case .russian: "Russian"
        case .ukrainian: "Ukrainian"
        case .turkish: "Turkish"
        case .hindi: "Hindi"
        case .chinese: "Chinese (Simplified)"
        case .japanese: "Japanese"
        case .korean: "Korean"
        }
    }

    /// The language's own name, shown in pickers.
    var displayName: String {
        switch self {
        case .english: "English"
        case .hebrew: "עברית"
        case .arabic: "العربية"
        case .german: "Deutsch"
        case .french: "Français"
        case .spanish: "Español"
        case .italian: "Italiano"
        case .portuguese: "Português"
        case .dutch: "Nederlands"
        case .polish: "Polski"
        case .russian: "Русский"
        case .ukrainian: "Українська"
        case .turkish: "Türkçe"
        case .hindi: "हिन्दी"
        case .chinese: "中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }

    private var nlLanguage: NLLanguage {
        self == .chinese ? .simplifiedChinese : NLLanguage(rawValue: rawValue)
    }

    private static let byNLLanguage: [NLLanguage: AppLanguage] = {
        var map = Dictionary(uniqueKeysWithValues: allCases.map { ($0.nlLanguage, $0) })
        map[.traditionalChinese] = .chinese
        return map
    }()

    // MARK: Your languages

    /// Your own language: translations, meanings and explanations are written in it.
    static var native: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: "nativeLanguage") ?? "") ?? .hebrew }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "nativeLanguage") }
    }

    /// The language you're learning: your own language is translated into it.
    static var learning: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: "learningLanguage") ?? "") ?? .english }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "learningLanguage") }
    }

    /// The language of a text, among the supported ones. Short or ambiguous text leans towards
    /// your own language and the one you're learning.
    static func detect(_ text: String) -> AppLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = allCases.map(\.nlLanguage)
        var hints = Dictionary(uniqueKeysWithValues: allCases.map { ($0.nlLanguage, 0.02) })
        hints[native.nlLanguage] = 0.4
        hints[learning.nlLanguage] = 0.4
        recognizer.languageHints = hints
        recognizer.processString(text)
        if let language = recognizer.dominantLanguage, let match = byNLLanguage[language] {
            return match
        }
        return learning
    }

    /// Text in your own language goes to the language you're learning; anything else to your own.
    static func direction(for text: String) -> (source: AppLanguage, target: AppLanguage) {
        let source = detect(text)
        return (source, source == native ? learning : native)
    }

    /// For two pickers that must not show the same language: when `changed` now equals `other`,
    /// `other` moves to a sensible different language.
    static func distinct(_ changed: AppLanguage, from other: AppLanguage) -> AppLanguage {
        guard changed == other else { return other }
        return changed == native ? learning : native
    }
}

/// The two languages of a saved word: the word's own and its meaning's.
struct LanguagePair: Hashable, Codable {
    let term: AppLanguage
    let meaning: AppLanguage

    var title: String { "\(term.displayName) → \(meaning.displayName)" }
}

extension String {
    var containsHebrew: Bool { unicodeScalars.contains { (0x0590...0x05FF).contains($0.value) } }
}
