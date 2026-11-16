import SwiftUI

@main
struct StopSwipingApp: App {
    @StateObject private var appState: AppState
    @StateObject private var lifetimeAccess = LifetimeAccessStore()
    @StateObject private var notifications: NotificationEngine
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    private let dependencies: DependencyContainer

    init() {
        let dependencies = DependencyContainer.live
        self.dependencies = dependencies
        _appState = StateObject(
            wrappedValue: AppState(
                authService: dependencies.authService
            )
        )
        let store = dependencies.profileCreationStore
        let notifications = NotificationEngine(loadProfile: { store.load() }, registrar: dependencies.pushRegistration)
        // Before launch finishes: a tap that opened the app is delivered then.
        notifications.start()
        PushAppDelegate.connect(notifications)
        _notifications = StateObject(wrappedValue: notifications)
    }

    var body: some Scene {
        WindowGroup {
            AppCoordinatorView(
                appState: appState,
                access: lifetimeAccess,
                notifications: notifications,
                dependencies: dependencies
            )
            .environment(\.locale, AppLanguageSettings.shared.language.locale)
        }
    }
}
