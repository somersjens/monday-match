import SwiftUI

@main
struct DatingApp: App {
    @StateObject private var appState: AppState
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
                dependencies: dependencies
            )
        }
    }
}
