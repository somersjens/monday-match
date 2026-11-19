import UserNotifications

/// Puts the match's name on a message push when previews are on. The server
/// sends only "New message" (Apple can read every payload); the app leaves
/// the name and the copy in the shared app group. See `PushPreview`.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var original: UNNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        original = request.content
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        let snapshot = PushPreview.load(from: UserDefaults(suiteName: PushPreview.appGroup))
        if let preview = PushPreview.resolve(request.content.userInfo, snapshot: snapshot) {
            content.title = preview.title
            content.body = preview.body
        }
        contentHandler(content)
    }

    /// Out of time: the server's plain text is always safe to show.
    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let original { contentHandler(original) }
    }
}
