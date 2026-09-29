import Foundation

enum AppLanguage: String, CaseIterable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
}

final class Localization {
    static let shared = Localization()
    static let preferenceKey = "appLanguage"
    private let defaults: UserDefaults
    private let bundle: Bundle
    private let preferredLanguages: () -> [String]
    private(set) var language: AppLanguage

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main,
         preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }) {
        self.defaults = defaults
        self.bundle = bundle
        self.preferredLanguages = preferredLanguages
        language = AppLanguage(rawValue: defaults.string(forKey: Self.preferenceKey) ?? "") ?? .system
    }

    var resolvedLanguage: AppLanguage {
        guard language == .system else { return language }
        // Let macOS match its ordered language preferences against our translations.
        let match = Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: preferredLanguages()).first
        return match == "zh-Hans" ? .simplifiedChinese : .english
    }

    func select(_ language: AppLanguage, persist: Bool = true) {
        self.language = language
        if persist { defaults.set(language.rawValue, forKey: Self.preferenceKey) }
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        let path = bundle.path(forResource: resolvedLanguage.rawValue, ofType: "lproj")
        let localized = path.flatMap(Bundle.init(path:)) ?? bundle
        let value = localized.localizedString(forKey: key, value: nil, table: nil)
        return arguments.isEmpty ? value : String(format: value, locale: Locale(identifier: resolvedLanguage.rawValue), arguments: arguments)
    }
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    // Preserve argument forwarding for format strings rather than nesting the array.
    if arguments.isEmpty { return Localization.shared.text(key) }
    return String(format: Localization.shared.text(key), locale: Locale(identifier: Localization.shared.resolvedLanguage.rawValue), arguments: arguments)
}
