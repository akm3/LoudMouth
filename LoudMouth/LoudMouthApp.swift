import SwiftUI

@MainActor
final class AppDependencies {
    static let shared = AppDependencies()

    let settings: AppSettings
    let model: AppModel

    private init() {
        let settings = AppSettings()
        self.settings = settings
        model = AppModel(settings: settings)
    }
}

#if !SNAPSHOT
@main
#endif
struct LoudMouthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var model: AppModel

    init() {
        let dependencies = AppDependencies.shared
        _settings = StateObject(wrappedValue: dependencies.settings)
        _model = StateObject(wrappedValue: dependencies.model)
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(settings)
        }
        .windowResizability(.contentSize)
    }
}
