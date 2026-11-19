import Combine
import Foundation
import UIKit
import UserNotifications

/// A message the app shows on screen instead of as a system notification.
struct InAppNotice: Equatable, Identifiable {
    let id = UUID()
    let kind: NotificationKind
    let title: String
    let body: String
    var destination: NotificationDestination?
}

/// The system notification center, behind a protocol so tests can count
/// what would be scheduled.
@MainActor
protocol NotificationCentering: AnyObject {
    func authorization() async -> NotificationPermissionState
    func requestAuthorization() async -> Bool
    func pendingIdentifiers() async -> Set<String>
    /// Delivered notifications still in Notification Center, with their payloads.
    func delivered() async -> [(identifier: String, userInfo: [String: String])]
    func add(_ planned: PlannedNotification, calendar: Calendar) async throws
    func removePending(_ identifiers: [String])
    func removeDelivered(_ identifiers: [String])
    func registerCategories()
}

/// The one place notification events go. It keeps the signals nothing else
/// stores, asks the planner what should be pending, and makes the system's
/// pending requests match: new ones are added, stale ones are cancelled. It
/// also shows in-app notices, routes taps to their screens, records
/// analytics and keeps the push device registration current.
@MainActor
final class NotificationEngine: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    /// Everything on: there are no notification switches in the app.
    let preferences = NotificationPreferences.standard
    @Published private(set) var permission: NotificationPermissionState = .notDetermined
    @Published var notice: InAppNotice?
    /// A screen a notification asked to open, waiting for the home screen.
    @Published var pendingDestination: NotificationDestination?

    /// The conversation on screen; its message pushes aren't shown as banners.
    var isChatOpen = false

    private let center: NotificationCentering
    private let loadProfile: () -> ProfileCreationState?
    private let ledgerStore: NotificationLedgerStore
    private let signalStore: NotificationSignalStore
    private let registrar: PushDeviceRegistering?
    private let now: () -> Date
    /// Read at every use, so switching the app's language rewrites what is pending.
    private let language: () -> AppLanguage
    private let calendar: Calendar
    private let policy: NotificationPolicy

    private(set) var ledger: NotificationLedger
    private(set) var signals: NotificationSignals

    private var hasAccount = false
    private var isSuspended = false
    private var earlyAccessReminderAt: Date?
    private var conversation: NotificationContext.Conversation?
    private var lastMatchAt: Date?
    private var knownActiveMatch: UUID?
    /// The active match's name, for the Notification Service Extension.
    private var activeMatchName: String?
    /// The app group the extension reads (`PushPreview`); nil in tests.
    private let previewDefaults: UserDefaults?
    private var pushToken: String?
    private var registeredFingerprint: String?

    private var isSyncing = false
    private var needsAnotherSync = false
    private var debouncedSync: Task<Void, Never>?

    init(center: NotificationCentering? = nil,
         loadProfile: @escaping () -> ProfileCreationState?,
         defaults: UserDefaults = .standard,
         registrar: PushDeviceRegistering? = nil,
         policy: NotificationPolicy? = nil,
         calendar: Calendar = .autoupdatingCurrent,
         language: (() -> AppLanguage)? = nil,
         previewDefaults: UserDefaults? = nil,
         now: @escaping () -> Date = Date.init) {
        self.previewDefaults = previewDefaults
            ?? (defaults === UserDefaults.standard ? UserDefaults(suiteName: PushPreview.appGroup) : nil)
        self.language = language ?? { AppLanguageSettings.shared.language }
        self.center = center ?? SystemNotificationCenter()
        self.loadProfile = loadProfile
        ledgerStore = NotificationLedgerStore(defaults: defaults)
        signalStore = NotificationSignalStore(defaults: defaults)
        self.registrar = registrar
        self.policy = policy ?? .standard
        self.calendar = calendar
        self.now = now
        // Switches from before notifications became all or nothing.
        defaults.removeObject(forKey: Self.legacyPreferencesKey)
        ledger = ledgerStore.load()
        signals = signalStore.load()
        super.init()
    }

    // MARK: - Lifecycle

    /// Becomes the notification center's delegate, so taps reach the app.
    func start() {
        UNUserNotificationCenter.current().delegate = self
        center.registerCategories()
    }

    func appBecameActive() async {
        let time = now()
        if let last = signals.lastActiveAt, time.timeIntervalSince(last) >= policy.welcomeBackAfter,
           let copy = NotificationCopy.variant(for: .init(.welcomeBack), installID: signals.installID,
                                               sendIndex: ledger.records.filter { $0.kind == .welcomeBack }.count,
                                               language: language()) {
            show(InAppNotice(kind: .welcomeBack, title: copy.title, body: copy.body),
                 dedupeKey: "welcome_back.\(Int(time.timeIntervalSince1970))", variantID: copy.template.id)
        }
        signals.previousActiveAt = signals.lastActiveAt
        signals.lastActiveAt = time
        signalStore.save(signals)
        await refreshPermission()
        await sync()
    }

    /// The moment that matters most: what is pending now is what fires
    /// while the app is closed.
    func appWillResignActive() async {
        signals.lastActiveAt = now()
        signalStore.save(signals)
        await sync()
    }

    // MARK: - Events from the app

    func update(hasAccount: Bool, earlyAccessReminderAt: Date?) {
        guard hasAccount != self.hasAccount || earlyAccessReminderAt != self.earlyAccessReminderAt else { return }
        self.hasAccount = hasAccount
        self.earlyAccessReminderAt = earlyAccessReminderAt
        if !hasAccount { conversation = nil; knownActiveMatch = nil; activeMatchName = nil }
        scheduleSync()
    }

    /// The live match as the home screen sees it, every time it changes.
    func updateLiveMatch(_ match: CloudChatMatch?, messages: [ChatMessage], lastReadAt: Date?, unsentIDs: [UUID],
                         isConversationLoaded: Bool, history: [CloudChatMatch], isSuspended: Bool) {
        self.isSuspended = isSuspended
        let time = now()
        lastMatchAt = (history.compactMap(\.matchedAt) + [match?.matchedAt].compactMap { $0 }).max()

        if let match {
            // Seen with the app open: the app shows the match itself.
            let key = Self.matchKey(match.id)
            if !ledger.hasDelivered(key) {
                ledger.markHandled(kind: .matchNew, dedupeKey: key, at: time)
                ledgerStore.save(ledger)
            }
            knownActiveMatch = match.id
            activeMatchName = match.partnerName
            let fromPartner = messages.filter { $0.sender == .match }
            let fromMe = messages.filter { $0.sender == .currentUser }
            let last = messages.filter { $0.sender != .system }.max { $0.sentAt < $1.sentAt }
            let unread = fromPartner.filter { $0.sentAt > (lastReadAt ?? .distantPast) }
            conversation = .init(matchID: match.id, matchedAt: match.matchedAt ?? time,
                                 messagesFromMe: fromMe.count, messagesFromPartner: fromPartner.count,
                                 lastMessageAt: last?.sentAt ?? match.lastMessageAt,
                                 lastMessageFromPartner: last?.sender == .match,
                                 oldestUnreadAt: unread.map(\.sentAt).min(),
                                 unsentCount: unsentIDs.count,
                                 unsentKey: String(NotificationCopy.fnv1a(unsentIDs.map(\.uuidString).sorted().joined())),
                                 isLoaded: isConversationLoaded)
        } else {
            if let ended = knownActiveMatch, let record = history.first(where: { $0.id == ended }) {
                matchEnded(record)
            }
            knownActiveMatch = nil
            activeMatchName = nil
            conversation = nil
        }
        scheduleSync()
    }

    /// A server push reached the app in the background. Its own copy of the
    /// conversation is stale, so the push's facts are applied before replanning.
    func handleBackgroundPush(_ userInfo: [String: String]) async {
        let kind = userInfo["kind"].flatMap(NotificationKind.init(rawValue:))
        let matchID = userInfo["match_id"].flatMap(UUID.init(uuidString:))
        let time = now()
        switch kind {
        case .messageNew?:
            if var chat = conversation, chat.matchID == matchID {
                chat.oldestUnreadAt = chat.oldestUnreadAt ?? time
                chat.messagesFromPartner += 1
                chat.lastMessageAt = time
                chat.lastMessageFromPartner = true
                conversation = chat
            }
        case .matchEnded?:
            // Reminders for it stop now; the notice waits for the next open.
            if conversation?.matchID == matchID { conversation = nil }
        case .matchNew?, .firstMatch?:
            if let matchID { conversation = .init(matchID: matchID, matchedAt: time) }
        default:
            break
        }
        await sync()
    }

    /// Profiles were compared in person (phones together or a scanned code).
    func recordCompatibilityCheck() {
        signals.lastCompatibilityCheckAt = now()
        signalStore.save(signals)
        scheduleSync()
    }

    /// The profile changed: consent, onboarding, auto-matching.
    func profileChanged() { scheduleSync() }

    private func matchEnded(_ match: CloudChatMatch) {
        // Your own break needs no announcement, and a suspended user hears
        // about it from the moderation notice instead.
        guard !match.endedByMe, !isSuspended else { return }
        let key = "match_ended.\(match.id.uuidString.lowercased())"
        guard !ledger.hasDelivered(key),
              let copy = NotificationCopy.variant(for: .init(.matchEnded), installID: signals.installID,
                                                  sendIndex: ledger.records.filter { $0.kind == .matchEnded }.count,
                                                  language: language())
        else { return }
        show(InAppNotice(kind: .matchEnded, title: copy.title, body: copy.body, destination: .myMatches),
             dedupeKey: key, variantID: copy.template.id)
    }

    private func show(_ notice: InAppNotice, dedupeKey: String, variantID: String) {
        self.notice = notice
        ledger.markHandled(kind: notice.kind, dedupeKey: dedupeKey, at: now())
        ledger.log(.init(name: .shownInApp, at: now(), kind: notice.kind, variantID: variantID))
        ledgerStore.save(ledger)
    }

    func openNotice(_ notice: InAppNotice) {
        ledger.log(.init(name: .opened, at: now(), kind: notice.kind))
        ledgerStore.save(ledger)
        pendingDestination = notice.destination
        self.notice = nil
    }

    // MARK: - Permission

    func requestPermission() async {
        _ = await center.requestAuthorization()
        await refreshPermission()
        await sync()
    }

    func refreshPermission() async {
        let previous = permission
        permission = await center.authorization()
        if previous == .authorized, permission != .authorized {
            ledger.log(.init(name: .permissionRevoked, at: now()))
            ledgerStore.save(ledger)
            await unregisterPushDevice()
        } else if previous != .authorized, permission == .authorized {
            ledger.log(.init(name: .permissionGranted, at: now()))
            ledgerStore.save(ledger)
        }
        if permission == .authorized, hasAccount, registrar != nil {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - Push

    func didRegister(deviceToken: Data) {
        pushToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await syncPushDevice() }
    }

    private func syncPushDevice() async {
        guard let registrar, let pushToken, hasAccount, permission == .authorized else { return }
        let zone = calendar.timeZone.identifier
        let fingerprint = "\(pushToken)|\(zone)|\(language().rawValue)|\(String(describing: preferences))"
        guard fingerprint != registeredFingerprint else { return }
        // Claimed before the call, so overlapping syncs register only once.
        registeredFingerprint = fingerprint
        do {
            try await registrar.register(deviceID: signals.deviceID, token: pushToken, timeZone: zone,
                                         language: language(), preferences: preferences)
        } catch {
            // Tried again at the next sync.
            if registeredFingerprint == fingerprint { registeredFingerprint = nil }
        }
    }

    /// Before signing out, so this phone stops receiving the account's pushes.
    func unregisterPushDevice() async {
        guard let registrar else { return }
        try? await registrar.unregister(deviceID: signals.deviceID)
        registeredFingerprint = nil
    }

    // MARK: - Sync

    private func scheduleSync(after delay: Duration = .milliseconds(500)) {
        debouncedSync?.cancel()
        debouncedSync = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    /// Makes the pending system requests equal to the plan.
    func sync() async {
        guard !isSyncing else { needsAnotherSync = true; return }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            needsAnotherSync = false
            await syncOnce()
        } while needsAnotherSync
        PushPreview.save(pushPreviewSnapshot(), to: previewDefaults)
        await syncPushDevice()
    }

    /// What the Notification Service Extension may put on the lock screen:
    /// the active match's name, only with an account and previews on.
    func pushPreviewSnapshot() -> PushPreview.Snapshot? {
        guard hasAccount, preferences.messagePreviews, let match = knownActiveMatch,
              let name = activeMatchName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return nil }
        func templates(_ flavor: String) -> [PushPreview.Template] {
            NotificationCopy.templates(for: .init(.messageNew, flavor), language: language())
                .map { PushPreview.Template(id: $0.id, title: $0.title, body: $0.body) }
        }
        return PushPreview.Snapshot(names: [match.uuidString.lowercased(): name],
                                    single: templates("preview"), batch: templates("preview_batch"))
    }

    private func syncOnce() async {
        let time = now()
        observeSignals(time)
        let pending = await center.pendingIdentifiers().filter(Self.isOurs)
        let delivered = await center.delivered()
        recordServerDeliveries(delivered, at: time)
        ledger.settle(pendingIdentifiers: pending, deliveredIdentifiers: Set(delivered.map(\.identifier)), now: time)

        let plan = NotificationPlanner(policy: policy, calendar: calendar, installID: signals.installID,
                                       language: language())
            .plan(context: context(now: time), ledger: ledger, preferences: preferences, now: time)
        let planned = Dictionary(plan.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })

        let stale = pending.filter { planned[$0] == nil }
        if !stale.isEmpty {
            center.removePending(Array(stale))
            for identifier in stale { ledger.markCancelled(identifier, at: time) }
        }
        let scheduled = Dictionary(ledger.scheduled().map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        for notification in plan {
            if pending.contains(notification.identifier), let existing = scheduled[notification.identifier],
               existing.fireDate == notification.fireDate, existing.variantID == notification.variantID { continue }
            do {
                try await center.add(notification, calendar: calendar)
                ledger.markScheduled(notification, at: time)
            } catch {
                // The next sync tries again.
            }
        }
        ledgerStore.save(ledger)
    }

    /// What the planner sees right now.
    func context(now time: Date) -> NotificationContext {
        var context = NotificationContext(profile: loadProfile(), hasAccount: hasAccount, permission: permission)
        context.isSuspended = isSuspended
        context.conversation = conversation
        context.lastMatchAt = lastMatchAt
        context.lastActiveAt = signals.lastActiveAt ?? time
        context.autoMatchingEnabledSince = signals.autoMatchingEnabledSince
        context.lastCompatibilityCheckAt = signals.lastCompatibilityCheckAt
        context.privacyIssueNoticedAt = signals.privacyIssueNoticedAt
        context.setupIssueNoticedAt = signals.setupIssueNoticedAt
        context.earlyAccessReminderAt = earlyAccessReminderAt
        return context
    }

    /// Keeps the "since when" facts that start several timers.
    private func observeSignals(_ time: Date) {
        let context = NotificationContext(profile: loadProfile(), hasAccount: hasAccount, permission: permission)
        var updated = signals
        if context.autoMatchingEnabled {
            if updated.autoMatchingEnabledSince == nil { updated.autoMatchingEnabledSince = time }
        } else {
            updated.autoMatchingEnabledSince = nil
        }
        let issue: String? = switch (context.profileConsent, context.matchingConsent) {
        case (.missing, _): context.onboardingCompleted ? "profile.missing" : nil
        case (.outdated, _): "profile.outdated.\(PrivacyConsentKind.profile.version)"
        case (.current, .outdated): "matching.outdated.\(PrivacyConsentKind.matching.version)"
        default: nil
        }
        if issue != updated.privacyIssue {
            updated.privacyIssue = issue
            updated.privacyIssueNoticedAt = issue == nil ? nil : time
        }
        if context.matchingSetupNeedsAttention {
            if updated.setupIssueNoticedAt == nil { updated.setupIssueNoticedAt = time }
        } else {
            updated.setupIssueNoticedAt = nil
        }
        if context.hasEverCheckedCompatibility, updated.lastCompatibilityCheckAt == nil {
            // Exchanged before this version recorded when; the month starts now.
            updated.lastCompatibilityCheckAt = time
        }
        if updated != signals {
            signals = updated
            signalStore.save(updated)
        }
    }

    /// Server pushes the user already saw, so the app doesn't repeat them.
    private func recordServerDeliveries(_ delivered: [(identifier: String, userInfo: [String: String])], at time: Date) {
        for item in delivered {
            guard let raw = item.userInfo["kind"], let kind = NotificationKind(rawValue: raw),
                  kind.isServerSent, let key = item.userInfo["dedupe"], !ledger.hasDelivered(key) else { continue }
            ledger.markDelivered(identifier: item.identifier, kind: kind, dedupeKey: key,
                                 variantID: item.userInfo["variant"], at: time)
        }
    }

    // MARK: - Clearing

    /// Signing out: nothing of this account should fire on this phone.
    func accountSignedOut() async {
        await unregisterPushDevice()
        hasAccount = false
        conversation = nil
        knownActiveMatch = nil
        await sync()
    }

    /// Deleting the profile: pending notifications and local history go.
    static func clearLocalData(defaults: UserDefaults = .standard) {
        NotificationLedgerStore(defaults: defaults).clear()
        NotificationSignalStore(defaults: defaults).clear()
        defaults.removeObject(forKey: legacyPreferencesKey)
        let center = UNUserNotificationCenter.current()
        Task {
            let requests = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter(isOurs))
            center.removeAllDeliveredNotifications()
        }
    }

    private static let legacyPreferencesKey = "notifications.preferences.v1"

    nonisolated static func isOurs(_ identifier: String) -> Bool { identifier.hasPrefix("stopswiping.") }
    static func matchKey(_ id: UUID) -> String { "match_new.\(id.uuidString.lowercased())" }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        let userInfo = Self.strings(notification.request.content.userInfo)
        return await MainActor.run { presentationOptions(identifier: identifier, userInfo: userInfo) }
    }

    /// The payload's string values, which is all the app puts in one.
    nonisolated static func strings(_ userInfo: [AnyHashable: Any]) -> [String: String] {
        userInfo.reduce(into: [:]) { result, item in
            if let key = item.key as? String, let value = item.value as? String { result[key] = value }
        }
    }

    func presentationOptions(identifier: String, userInfo: [String: String]) -> UNNotificationPresentationOptions {
        let kind = userInfo["kind"].flatMap(NotificationKind.init(rawValue:))
        if let kind, let key = userInfo["dedupe"] {
            ledger.markDelivered(identifier: identifier, kind: kind, dedupeKey: key,
                                 variantID: userInfo["variant"], at: now())
            ledgerStore.save(ledger)
        }
        // The open conversation already shows its new messages.
        if kind == .messageNew, isChatOpen { return [] }
        // A match while the app is open plays its own arrival.
        if kind == .matchNew || kind == .firstMatch { return [.list] }
        return [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let userInfo = Self.strings(response.notification.request.content.userInfo)
        let action = response.actionIdentifier
        await MainActor.run { handleResponse(action: action, userInfo: userInfo) }
    }

    func handleResponse(action: String, userInfo: [String: String]) {
        let kind = userInfo["kind"].flatMap(NotificationKind.init(rawValue:))
        let variant = userInfo["variant"]
        switch action {
        case UNNotificationDismissActionIdentifier:
            ledger.log(.init(name: .dismissed, at: now(), kind: kind, variantID: variant))
        case UNNotificationDefaultActionIdentifier:
            ledger.log(.init(name: .opened, at: now(), kind: kind, variantID: variant))
            pendingDestination = userInfo["destination"].flatMap(URL.init(string:))
                .flatMap(NotificationDestination.init(url:))
        default:
            ledger.log(.init(name: .actioned, at: now(), kind: kind, variantID: variant, detail: action))
        }
        ledgerStore.save(ledger)
    }
}

/// `UNUserNotificationCenter`, limited to what the engine needs.
@MainActor
final class SystemNotificationCenter: NotificationCentering {
    private let center = UNUserNotificationCenter.current()

    func authorization() async -> NotificationPermissionState {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    func pendingIdentifiers() async -> Set<String> {
        Set(await center.pendingNotificationRequests().map(\.identifier))
    }

    func delivered() async -> [(identifier: String, userInfo: [String: String])] {
        await center.deliveredNotifications().map {
            ($0.request.identifier, NotificationEngine.strings($0.request.content.userInfo))
        }
    }

    func add(_ planned: PlannedNotification, calendar: Calendar) async throws {
        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.sound = planned.interruption == .passive ? nil : AppSound.notificationSound
        content.interruptionLevel = planned.interruption == .passive ? .passive : .active
        content.threadIdentifier = planned.threadID
        content.categoryIdentifier = planned.kind.category.identifier
        content.userInfo = ["kind": planned.kind.rawValue, "dedupe": planned.dedupeKey,
                            "variant": planned.variantID, "destination": planned.destination.url.absoluteString]
        // Without a time zone the trigger follows the phone's: a trip abroad
        // still delivers at local wall-clock time.
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: planned.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: planned.identifier, content: content, trigger: trigger))
    }

    func removePending(_ identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func removeDelivered(_ identifiers: [String]) { center.removeDeliveredNotifications(withIdentifiers: identifiers) }

    /// Each category reports dismissals, so analytics can tell ignored
    /// notifications from dismissed ones.
    func registerCategories() {
        center.setNotificationCategories(Set(NotificationCategory.allCases.map {
            UNNotificationCategory(identifier: $0.identifier, actions: [], intentIdentifiers: [],
                                   options: [.customDismissAction])
        }))
    }
}
