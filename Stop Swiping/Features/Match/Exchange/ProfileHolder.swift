import Foundation

/// Who sealed a profile: six random bytes made once on each phone and sent
/// inside every seal, never readable outside it. Lets a phone recognise
/// someone it already compared itself with, so a second scan shows the first
/// outcome again instead of a new one (`ScannedMatchMemory`). Deleting the
/// profile makes a new one.
struct ProfileHolder: Codable, Hashable {
    static let byteCount = 6
    nonisolated static let storageKey = "profileCode.holder.v1"

    let bytes: Data

    init(bytes: Data) {
        self.bytes = Data(bytes.prefix(Self.byteCount))
    }

    static func random() -> ProfileHolder {
        var generator = SystemRandomNumberGenerator()
        return ProfileHolder(bytes: Data((0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    /// This phone's own, made the first time it is asked for.
    static var current: ProfileHolder { current(defaults: .standard) }

    static func current(defaults: UserDefaults) -> ProfileHolder {
        if let data = defaults.data(forKey: storageKey), data.count == byteCount {
            return ProfileHolder(bytes: data)
        }
        let holder = random()
        defaults.set(holder.bytes, forKey: storageKey)
        return holder
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    var hex: String { bytes.map { String(format: "%02x", $0) }.joined() }
}

/// The outcome of every person this phone compared itself with in the last
/// day, by who they are. Scanning the same person again, from the same code
/// or a fresh one, brings back the first outcome: changing your own answers
/// and scanning again can't reveal what they look for. Holds frozen
/// snapshots only, never anyone's answers.
struct ScannedMatchMemory {
    static let lifetime: TimeInterval = 24 * 60 * 60
    nonisolated static let storageKey = "scannedMatches.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private struct Entry: Codable {
        let holder: ProfileHolder
        let snapshot: MatchSnapshot
    }

    /// The outcome kept for this person, when they were compared within the day.
    func snapshot(for holder: ProfileHolder, now: Date = Date()) -> MatchSnapshot? {
        entries(now: now).first { $0.holder == holder }?.snapshot
    }

    func remember(_ snapshot: MatchSnapshot, for holder: ProfileHolder, now: Date = Date()) {
        var entries = entries(now: now).filter { $0.holder != holder }
        entries.append(Entry(holder: holder, snapshot: snapshot))
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// The remembered outcome for this person, or the new one, which is then
    /// remembered. Either way the outcome the screen shows.
    func resolve(_ snapshot: MatchSnapshot, for holder: ProfileHolder, now: Date = Date()) -> MatchSnapshot {
        if let known = self.snapshot(for: holder, now: now) { return known }
        remember(snapshot, for: holder, now: now)
        return snapshot
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    private func entries(now: Date) -> [Entry] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.filter { now.timeIntervalSince($0.snapshot.matchedAt) < Self.lifetime }
    }
}
