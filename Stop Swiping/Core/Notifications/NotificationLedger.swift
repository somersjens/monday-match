import Foundation

/// The notification history kept on this phone: what was scheduled, what was
/// delivered, and what people did with it. It is how the planner prevents
/// duplicates and enforces cooldowns, and it doubles as the analytics log.
/// Nothing in it leaves the phone.
struct NotificationLedger: Codable, Equatable {
    enum State: String, Codable {
        case scheduled
        case delivered
        case cancelled
        /// Shown by the app itself (a match that arrived while it was open),
        /// so it must never be sent afterwards.
        case handled
    }

    struct Record: Codable, Equatable {
        let identifier: String
        let kind: NotificationKind
        let dedupeKey: String
        var variantID: String?
        var fireDate: Date
        var state: State
    }

    struct Event: Codable, Equatable {
        enum Name: String, Codable {
            case scheduled, delivered, cancelled, opened, actioned, dismissed
            case shownInApp = "shown_in_app"
            case optedOut = "opted_out"
            case optedIn = "opted_in"
            case permissionRevoked = "permission_revoked"
            case permissionGranted = "permission_granted"
        }
        let name: Name
        let at: Date
        var kind: NotificationKind?
        var variantID: String?
        /// For opt-outs: which switch.
        var detail: String?
    }

    private(set) var records: [Record] = []
    private(set) var events: [Event] = []

    static let recordLimit = 400
    static let eventLimit = 800

    // MARK: Reading

    func hasDelivered(_ dedupeKey: String) -> Bool {
        records.contains { $0.dedupeKey == dedupeKey && ($0.state == .delivered || $0.state == .handled) }
    }

    func deliveries(of kind: NotificationKind? = nil, since: Date = .distantPast) -> [Record] {
        records.filter { ($0.state == .delivered) && $0.fireDate >= since && (kind == nil || $0.kind == kind) }
    }

    func deliveries(withKeyPrefix prefix: String) -> [Record] {
        records.filter { $0.state == .delivered && $0.dedupeKey.hasPrefix(prefix) }
    }

    func lastDelivery(of kind: NotificationKind) -> Date? { deliveries(of: kind).map(\.fireDate).max() }

    func nudgeDeliveries(since: Date) -> [Date] {
        deliveries(since: since).filter { $0.kind.category.isNudge }.map(\.fireDate)
    }

    func deliveryCount(of kind: NotificationKind) -> Int { deliveries(of: kind).count }

    func scheduled() -> [Record] { records.filter { $0.state == .scheduled } }

    // MARK: Writing

    mutating func markScheduled(_ planned: PlannedNotification, at now: Date) {
        records.removeAll { $0.identifier == planned.identifier && $0.state == .scheduled }
        records.append(Record(identifier: planned.identifier, kind: planned.kind, dedupeKey: planned.dedupeKey,
                              variantID: planned.variantID, fireDate: planned.fireDate, state: .scheduled))
        log(.init(name: .scheduled, at: now, kind: planned.kind, variantID: planned.variantID))
        trim()
    }

    /// A scheduled notification whose time has passed and that was still
    /// pending at the last sync has been delivered.
    mutating func settle(pendingIdentifiers: Set<String>, deliveredIdentifiers: Set<String>, now: Date) {
        for index in records.indices where records[index].state == .scheduled {
            let record = records[index]
            if deliveredIdentifiers.contains(record.identifier)
                || (record.fireDate <= now && !pendingIdentifiers.contains(record.identifier)) {
                records[index].state = .delivered
                log(.init(name: .delivered, at: min(record.fireDate, now), kind: record.kind, variantID: record.variantID))
            }
        }
    }

    mutating func markCancelled(_ identifier: String, at now: Date) {
        for index in records.indices where records[index].identifier == identifier && records[index].state == .scheduled {
            records[index].state = .cancelled
            log(.init(name: .cancelled, at: now, kind: records[index].kind, variantID: records[index].variantID))
        }
    }

    /// The app showed this itself; never send it later.
    mutating func markHandled(kind: NotificationKind, dedupeKey: String, at now: Date) {
        guard !hasDelivered(dedupeKey) else { return }
        records.append(Record(identifier: "handled.\(dedupeKey)", kind: kind, dedupeKey: dedupeKey,
                              variantID: nil, fireDate: now, state: .handled))
        trim()
    }

    /// A delivery the system reported directly (shown while the app was open).
    mutating func markDelivered(identifier: String, kind: NotificationKind, dedupeKey: String,
                                variantID: String?, at now: Date) {
        if let index = records.firstIndex(where: { $0.identifier == identifier && $0.state == .scheduled }) {
            records[index].state = .delivered
            records[index].fireDate = now
        } else if !hasDelivered(dedupeKey) {
            records.append(Record(identifier: identifier, kind: kind, dedupeKey: dedupeKey,
                                  variantID: variantID, fireDate: now, state: .delivered))
        } else { return }
        log(.init(name: .delivered, at: now, kind: kind, variantID: variantID))
        trim()
    }

    mutating func log(_ event: Event) {
        events.append(event)
        if events.count > Self.eventLimit { events.removeFirst(events.count - Self.eventLimit) }
    }

    private mutating func trim() {
        guard records.count > Self.recordLimit else { return }
        // Pending ones are always kept; the oldest settled ones go first.
        let settled = records.enumerated().filter { $0.element.state != .scheduled }
        let surplus = records.count - Self.recordLimit
        let drop = Set(settled.sorted { $0.element.fireDate < $1.element.fireDate }.prefix(surplus).map(\.offset))
        records = records.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
    }

    // MARK: Analytics

    struct VariantStats: Equatable {
        var delivered = 0
        var opened = 0
        var dismissed = 0
        var openRate: Double { delivered == 0 ? 0 : Double(opened) / Double(delivered) }
    }

    /// Delivered, opened and dismissed counts per copy variant, for A/B tests.
    func variantSummary() -> [String: VariantStats] {
        var summary: [String: VariantStats] = [:]
        for event in events {
            guard let variant = event.variantID else { continue }
            switch event.name {
            case .delivered: summary[variant, default: .init()].delivered += 1
            case .opened, .actioned: summary[variant, default: .init()].opened += 1
            case .dismissed: summary[variant, default: .init()].dismissed += 1
            default: break
            }
        }
        return summary
    }
}

@MainActor
final class NotificationLedgerStore {
    private let defaults: UserDefaults
    private let key = "notifications.ledger.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> NotificationLedger {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(NotificationLedger.self, from: $0) } ?? NotificationLedger()
    }

    func save(_ ledger: NotificationLedger) {
        if let data = try? JSONEncoder().encode(ledger) { defaults.set(data, forKey: key) }
    }

    func clear() { defaults.removeObject(forKey: key) }
}

/// Facts nothing else in the app stores: when the user was last here, when
/// auto-matching was switched on, when they last compared profiles.
struct NotificationSignals: Codable, Equatable {
    var lastActiveAt: Date?
    var previousActiveAt: Date?
    var autoMatchingEnabledSince: Date?
    var lastCompatibilityCheckAt: Date?
    /// When the current consent problem was first noticed, and which one.
    var privacyIssue: String?
    var privacyIssueNoticedAt: Date?
    var setupIssueNoticedAt: Date?
    /// A stable, random ID for A/B buckets. Not linked to the account.
    var installID: String = UUID().uuidString
    /// For push registration.
    var deviceID: UUID = UUID()
}

@MainActor
final class NotificationSignalStore {
    private let defaults: UserDefaults
    private let key = "notifications.signals.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> NotificationSignals {
        if let data = defaults.data(forKey: key), let signals = try? JSONDecoder().decode(NotificationSignals.self, from: data) {
            return signals
        }
        let fresh = NotificationSignals()
        save(fresh)
        return fresh
    }

    func save(_ signals: NotificationSignals) {
        if let data = try? JSONEncoder().encode(signals) { defaults.set(data, forKey: key) }
    }

    func clear() { defaults.removeObject(forKey: key) }
}
