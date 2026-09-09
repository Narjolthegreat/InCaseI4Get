import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case turkish = "tr"
    case chinese = "zh-Hans"
    case spanish = "es"
    case portuguese = "pt"
    case russian = "ru"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .french: "Français"
        case .german: "Deutsch"
        case .turkish: "Türkçe"
        case .chinese: "中文"
        case .spanish: "Español"
        case .portuguese: "Português"
        case .russian: "Русский"
        }
    }

    var speechLocale: String {
        switch self {
        case .english: "en-US"
        case .japanese: "ja-JP"
        case .korean: "ko-KR"
        case .french: "fr-FR"
        case .german: "de-DE"
        case .turkish: "tr-TR"
        case .chinese: "zh-CN"
        case .spanish: "es-ES"
        case .portuguese: "pt-BR"
        case .russian: "ru-RU"
        }
    }
}

@Observable
final class AppSettings {
    private enum Key {
        static let ttsEnabled = "settings.ttsEnabled"
        static let strikeEnabled = "settings.strikeEnabled"
        static let hapticsEnabled = "settings.hapticsEnabled"
        static let flashEnabled = "settings.flashEnabled"
        static let earlyMinutes = "settings.earlyMinutes"
        static let speechVolume = "settings.speechVolume"
        static let languageCode = "settings.languageCode"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.languageCode) }
    }

    var ttsEnabled: Bool {
        didSet { defaults.set(ttsEnabled, forKey: Key.ttsEnabled) }
    }

    var strikeEnabled: Bool {
        didSet { defaults.set(strikeEnabled, forKey: Key.strikeEnabled) }
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }

    var flashEnabled: Bool {
        didSet { defaults.set(flashEnabled, forKey: Key.flashEnabled) }
    }

    var earlyMinutes: Int {
        didSet { defaults.set(earlyMinutes, forKey: Key.earlyMinutes) }
    }

    var speechVolume: Double {
        didSet { defaults.set(speechVolume, forKey: Key.speechVolume) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let languageCode = defaults.string(forKey: Key.languageCode)
        language = AppLanguage(rawValue: languageCode ?? "") ?? .english
        ttsEnabled = defaults.object(forKey: Key.ttsEnabled) as? Bool ?? true
        strikeEnabled = defaults.object(forKey: Key.strikeEnabled) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true
        flashEnabled = defaults.object(forKey: Key.flashEnabled) as? Bool ?? true
        earlyMinutes = defaults.object(forKey: Key.earlyMinutes) as? Int ?? 5
        speechVolume = defaults.object(forKey: Key.speechVolume) as? Double ?? 0.8
    }
}
