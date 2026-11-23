import SwiftUI
import UIKit

enum AppPreferences {
    static let languageKey = "appLanguage"
    static let turkishEnabledKey = "turkishEnabled"
    static let appearanceKey = "appearance"
}

/// Selected language and whether Turkish is available are stored separately.
/// A missing language key means the user never chose one, so English is selected and Turkish stays off.
enum LanguagePreferences {
    static func prepare(defaults: UserDefaults = .standard) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-VestraResetLanguage") {
            defaults.removeObject(forKey: AppPreferences.languageKey)
            defaults.removeObject(forKey: AppPreferences.turkishEnabledKey)
        }
        #endif
        migrate(defaults: defaults)
        normalize(defaults: defaults)
    }

    static func migrate(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: AppPreferences.turkishEnabledKey) == nil else { return }
        let stored = defaults.string(forKey: AppPreferences.languageKey)
        if stored == nil {
            defaults.set(AppLanguage.english.rawValue, forKey: AppPreferences.languageKey)
            defaults.set(false, forKey: AppPreferences.turkishEnabledKey)
        } else if stored == AppLanguage.turkish.rawValue {
            defaults.set(true, forKey: AppPreferences.turkishEnabledKey)
        } else {
            defaults.set(false, forKey: AppPreferences.turkishEnabledKey)
        }
    }

    /// Turkish cannot stay selected after it has been turned off.
    static func normalize(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: AppPreferences.turkishEnabledKey) != nil else { return }
        guard !defaults.bool(forKey: AppPreferences.turkishEnabledKey),
              defaults.string(forKey: AppPreferences.languageKey) == AppLanguage.turkish.rawValue
        else { return }
        defaults.set(AppLanguage.english.rawValue, forKey: AppPreferences.languageKey)
    }

    static func setTurkishEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: AppPreferences.turkishEnabledKey)
        normalize(defaults: defaults)
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case turkish = "tr"

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: self == .turkish ? "tr_TR" : "en_US")
    }

    /// Always shown in its own language so it stays recognisable after switching.
    var nativeName: String {
        self == .turkish ? "Türkçe" : "English"
    }

    init(locale: Locale) {
        self = locale.language.languageCode?.identifier == "en" ? .english : .turkish
    }

    private static let bundles: [AppLanguage: Bundle] = Dictionary(
        uniqueKeysWithValues: allCases.compactMap { language in
            Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
                .flatMap(Bundle.init(path:))
                .map { (language, $0) }
        }
    )

    var bundle: Bundle? { Self.bundles[self] }
}

extension Locale {
    /// Looks up a string in the app's selected language (SwiftUI `Text` does this automatically from
    /// the `\.locale` environment; this covers strings built in code, such as chart labels).
    func localized(_ key: String) -> String {
        guard let bundle = AppLanguage(locale: self).bundle else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: "System Default"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    private var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Applied at the window level so sheets follow too and "System Default" reliably reverts.
    @MainActor
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}
