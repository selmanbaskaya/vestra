import SwiftData
import SwiftUI

@main
struct VestraApp: App {
    private let preferencesReady = LanguagePreferences.prepare()
    @AppStorage(AppPreferences.languageKey) private var language: AppLanguage = .english
    @AppStorage(AppPreferences.turkishEnabledKey) private var turkishEnabled = false
    @AppStorage(AppPreferences.appearanceKey) private var appearance: AppearanceMode = .system

    private let container: ModelContainer = {
        var configuration = ModelConfiguration()
        #if DEBUG
        if let debugConfiguration = DebugSupport.storeConfiguration() {
            configuration = debugConfiguration
        }
        #endif
        do {
            let container = try ModelContainer(for: Schema(VestraSchema.models), configurations: configuration)
            try? CategoryStore.ensureDefaults(in: ModelContext(container))
            return container
        } catch {
            fatalError("Unable to open the Vestra data store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, language.locale)
                .tint(Theme.accent)
                .onAppear {
                    _ = preferencesReady
                    appearance.apply()
                }
                .onChange(of: appearance) { _, newValue in newValue.apply() }
                .onChange(of: turkishEnabled) { _, enabled in
                    if !enabled && language == .turkish {
                        language = .english
                    }
                }
        }
        .modelContainer(container)
    }
}
