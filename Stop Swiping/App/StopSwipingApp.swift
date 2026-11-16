import SwiftUI

@main
struct StopSwipingApp: App {
    @StateObject private var appState: AppState
    @StateObject private var lifetimeAccess = LifetimeAccessStore()
    private let dependencies: DependencyContainer

    init() {
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
                access: lifetimeAccess,
                dependencies: dependencies
            )
            .environment(\.locale, AppLanguageSettings.shared.language.locale)
        }
    }
}
