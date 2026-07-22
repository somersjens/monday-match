import Foundation

struct DependencyContainer {
    let authService: AuthServicing

    static var live: DependencyContainer {
        FirebaseBootstrap.configureIfAvailable()

        #if canImport(FirebaseAuth)
        return DependencyContainer(
            authService: FirebaseAppleAuthService()
        )
        #else
        return DependencyContainer(
            authService: MockAuthService()
        )
        #endif
    }
}
