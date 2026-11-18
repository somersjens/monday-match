import UIKit

/// iOS loads the keyboard, its suggestion bar and the name suggestions from
/// the user's contact card the first time a text field in the app takes
/// focus, on the main thread. The first field here is the name card on the
/// finished profile, so that load used to stall the helix and the rest of the
/// screen as the keyboard came up. Warming it while the launch screen is still
/// up hides the stall where nothing moves.
@MainActor
enum KeyboardWarmup {
    private static var isDone = false

    static func run() {
        guard !isDone, let window = keyWindow else { return }
        isDone = true
        let field = UITextField(frame: CGRect(x: -10, y: -10, width: 1, height: 1))
        // Matches the name card, so its contact suggestions load too.
        field.textContentType = .givenName
        field.autocapitalizationType = .words
        field.autocorrectionType = .no
        field.alpha = 0
        field.isAccessibilityElement = false
        window.addSubview(field)
        // Focusing and releasing in the same pass loads the keyboard without
        // ever showing it.
        field.becomeFirstResponder()
        field.resignFirstResponder()
        field.removeFromSuperview()
    }

    private static var keyWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }
}
