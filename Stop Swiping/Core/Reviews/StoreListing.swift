import Foundation

/// The app's own page in each store, for the "Rate Stop Swiping" row.
/// A button may never call the review sheet itself (both stores may show
/// nothing, so the tap would seem broken): it opens the store page instead.
enum StoreListing {
    /// App Store Connect app id.
    static let appStoreID = "6830641479"
    /// The Android package name, permanent once on Google Play. Not chosen
    /// yet (see docs/android-readiness.md); the row hides on Android until it is.
    static let playPackageName: String? = nil

    enum Store: Equatable {
        case appStore, googlePlay
    }

    static var current: Store {
        #if os(Android) || SKIP
        .googlePlay
        #else
        .appStore
        #endif
    }

    /// Where someone writes a review. Apple opens straight on the review
    /// form; Google Play has no such link, so its page opens on the reviews.
    static func reviewURL(for store: Store = current) -> URL? {
        switch store {
        case .appStore:
            URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
        case .googlePlay:
            playPackageName.flatMap { URL(string: "https://play.google.com/store/apps/details?id=\($0)&showAllReviews=true") }
        }
    }
}
