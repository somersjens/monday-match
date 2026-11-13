import SwiftUI

@main
struct StopSwipingApp: App {
    @StateObject private var appState: AppState
    private let dependencies: DependencyContainer

    init() {
        // The welcome light's shaders compile from source on first use. Start
        // that off the main thread now, so the light is ready to draw as soon
        // as its screen appears instead of costing the first frames.
        Task.detached(priority: .userInitiated) { _ = WelcomeLightMetalRenderer.resources }
        let dependencies = DependencyContainer.live
        self.dependencies = dependencies
        _appState = StateObject(
            wrappedValue: AppState(
                authService: dependencies.authService
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            AppCoordinatorView(
                appState: appState,
                dependencies: dependencies
            )
            .environment(\.locale, AppLanguageSettings.shared.language.locale)
        }
    }
}
