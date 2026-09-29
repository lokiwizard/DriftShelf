import Foundation

let bundle = Bundle(path: CommandLine.arguments[1])!
let suite = "DriftShelf.localization-tests." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let english = Localization(defaults: defaults, bundle: bundle, preferredLanguages: { ["en-US"] })
precondition(english.language == .system && english.resolvedLanguage == .english)
precondition(english.text("app.name") == "DriftShelf")
let chinese = Localization(defaults: defaults, bundle: bundle, preferredLanguages: { ["zh-Hans-CN", "en-US"] })
precondition(chinese.resolvedLanguage == .simplifiedChinese && chinese.text("app.name") == "轻放")
let unsupported = Localization(defaults: defaults, bundle: bundle, preferredLanguages: { ["fr-FR"] })
precondition(unsupported.resolvedLanguage == .english)
chinese.select(.english)
precondition(chinese.text("shelf.subtitle.one") == "1 file · Ready to drag")
precondition(chinese.text("shelf.subtitle.many", 2) == "2 files · Ready to drag")
let restored = Localization(defaults: defaults, bundle: bundle, preferredLanguages: { ["zh-Hans"] })
precondition(restored.language == .english && restored.text("app.name") == "DriftShelf", "explicit choice survives relaunch")
chinese.select(.simplifiedChinese)
precondition(chinese.text("shelf.subtitle.many", 12) == "12 个文件 · 随时拖走")
precondition(chinese.text("file.accessibility", "test.txt") == "test.txt，拖出以传递文件")
chinese.select(.system)
precondition(chinese.resolvedLanguage == .simplifiedChinese)
defaults.set("invalid-language", forKey: Localization.preferenceKey)
precondition(Localization(defaults: defaults, bundle: bundle).language == .system)

func table(_ language: String) -> [String: String] {
    let url = bundle.resourceURL!.appendingPathComponent("\(language).lproj/Localizable.strings")
    return try! PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as! [String: String]
}
let en = table("en")
let zh = table("zh-Hans")
precondition(Set(en.keys) == Set(zh.keys), "both languages must provide all keys")
for (key, value) in en {
    precondition(!value.isEmpty && !zh[key]!.isEmpty)
    precondition(value.components(separatedBy: "%@").count == zh[key]!.components(separatedBy: "%@").count)
    precondition(value.components(separatedBy: "%ld").count == zh[key]!.components(separatedBy: "%ld").count)
}
print("PASS: system language, English fallback, explicit switching, persisted choice, plural counts, translation completeness")
