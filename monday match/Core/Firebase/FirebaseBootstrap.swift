import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

enum FirebaseBootstrap {
    static var isAvailable: Bool {
        #if canImport(FirebaseCore)
        return true
        #else
        return false
        #endif
    }

    static func configureIfAvailable() {
        #if canImport(FirebaseCore)
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
        #endif
    }
}
