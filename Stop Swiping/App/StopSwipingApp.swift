import SwiftUI

@main
struct StopSwipingApp: App {
    @StateObject private var appState: AppState
    private let dependencies: DependencyContainer

    init() {
        // Warm up the welcome light's shaders after this initializer finishes,
        // on the main actor that owns the renderer resources.
        Task(priority: .userInitiated) { @MainActor in
            _ = WelcomeLightMetalRenderer.resources
        }
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
