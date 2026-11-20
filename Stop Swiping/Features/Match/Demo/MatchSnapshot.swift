import Combine
import CoreLocation
import Foundation

/// A match as it was decided, kept for good. The outcome is worked out once,
/// when the two profiles meet, and never again: later edits to either
/// profile, a new question catalog or a new formula leave it as it was.
///
/// The other person's answers to the 1–5 questions, what they look for and
/// how much each question matters to them are used for that one comparison
/// and then dropped. What stays is the outcome per category and what the
/// match screens show about them anyway.
struct MatchSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    let matchedAt: Date
    let you: ProfileCreationState
    /// Only what may be shown about the other person: name, age, area and
    /// their basic answers (`shownCopy`).
    let them: ProfileCreationState
    /// The scores and requirements as decided when matched.
    let result: MatchResult
    /// A local label; the original matched profiles remain unchanged.
    private(set) var customName: String?
    /// Set for a server match that was broken. Its conversation stays
    /// readable, but no more messages can be sent and the two never match again.
    var ended: Ended?
    /// Made up on this phone to show how matching works. Its photo card
    /// shows your own name, age and photo: how a match will see you.
    private var storedIsDemo: Bool?
    var isDemo: Bool {
        get { storedIsDemo ?? false }
        set { storedIsDemo = newValue ? true : nil }
    }

    /// Scores decided by the server for a match it made. The server only
    /// makes a match when every requirement is met both ways.
    struct FixedScores: Codable, Equatable {
        let yours: Int
        let theirs: Int
    }

    struct Ended: Codable, Equatable {
        let at: Date
        let reason: CloudChatMatch.EndReason?
        /// This person broke it.
        let byMe: Bool
    }

    /// Compares two whole profiles, once. `them` may hold everything the
    /// other person shared; only the outcome and `them.shownCopy()` are kept.
    init(id: UUID = UUID(), matchedAt: Date, you: ProfileCreationState, them: ProfileCreationState,
         fixedScores: FixedScores? = nil, isDemo: Bool = false) {
        var result = MatchResult(you: you, them: them,
                                 on: CalendarDate.today(calendar: BirthDateRules.calendar, now: matchedAt))
        if let fixedScores { result.useServerScores(yours: fixedScores.yours, theirs: fixedScores.theirs) }
        self.init(id: id, matchedAt: matchedAt, you: you, them: them, result: result, isDemo: isDemo)
    }

    /// A match whose outcome was decided earlier.
    init(id: UUID = UUID(), matchedAt: Date, you: ProfileCreationState, them: ProfileCreationState,
         result: MatchResult, isDemo: Bool = false) {
        self.id = id
        self.matchedAt = matchedAt
        self.you = you
        self.them = them.shownCopy()
        self.result = result
        self.isDemo = isDemo
    }

    /// The same match played again as a demo: a new identity, the same outcome.
    func replayedAsDemo() -> MatchSnapshot {
        MatchSnapshot(matchedAt: matchedAt, you: you, them: them, result: result, isDemo: true)
    }

    /// A match made by the server, with a conversation behind it.
    var isLive: Bool { result.isDecidedByServer }

    /// A server match that is no longer active, or a saved match that was
    /// deleted once and is kept as broken.
    var isBroken: Bool { ended != nil }

    var name: String { customName ?? them.displayName }

    /// How far apart the two live, rounded to whole kilometres, at least 1.
    var distanceKilometers: Int? {
        MatchResult.distanceKilometers(you.location, them.location).map { max(1, Int($0.rounded())) }
    }

    @discardableResult
    mutating func rename(to name: String) -> Bool {
        let name = ProfileNameRules.normalized(name)
        guard !name.isEmpty else { return false }
        customName = name == them.displayName ? nil : name
        return true
    }

    var report: MatchReport { MatchReport(result: result, name: name) }
}

extension ProfileCreationState {
    /// What may stay on this phone about someone else: what the match
    /// screens show, nothing more. Their 1–5 answers, the partner they look
    /// for on those questions, their age and height ranges and search radius
    /// are left out.
    func shownCopy() -> ProfileCreationState {
        var copy = ProfileCreationState(today: birthDateBaseline, applicationLanguage: "")
        copy.displayName = displayName
        copy.dateOfBirth = dateOfBirth
        copy.birthDateBaseline = birthDateBaseline
        copy.birthDateSelection = birthDateSelection
        copy.completedAt = completedAt
        copy.heightCentimeters = heightCentimeters
        copy.hasAdjustedHeight = hasAdjustedHeight
        copy.gender = gender
        copy.partnerGenders = partnerGenders
        copy.relationshipPreferences = relationshipPreferences
        copy.religion = religion
        copy.languages = languages
        copy.location = location
        var lifestyle = LifestyleAnswers()
        lifestyle.hasChildren = self.lifestyle.hasChildren
        lifestyle.openToPartnerWithChildren = self.lifestyle.openToPartnerWithChildren
        lifestyle.futureChildren = self.lifestyle.futureChildren
        for substance in Substance.allCases { lifestyle[substance] = self.lifestyle[substance] }
        copy.lifestyle = lifestyle
        return copy
    }
}

// MARK: - Result

/// The outcome of comparing two profiles: both scores, per category how they
/// came about, and every requirement either side fails. Holds nothing from
/// which a single answer could be read back.
struct MatchResult: Codable, Equatable {
    /// One way of looking: how well the candidate fits what the seeker looks for.
    struct Direction: Codable, Equatable {
        /// 0–100.
        fileprivate(set) var score: Int
        /// In catalog order; a category without answered questions is left out.
        let categories: [CategoryFit]
    }

    /// One category's part in a score. Σ share × fit over the categories
    /// is the score.
    struct CategoryFit: Codable, Equatable, Identifiable {
        let category: CompatibilityCategory
        /// How close the answers came to what was looked for, 0…1. Nil when
        /// none of its questions matter at all, so it doesn't count.
        let fit: Double?
        /// How much it counts, 0…1: the importance of its questions as a
        /// part of all importance. The shares add up to 1.
        let share: Double

        var id: CompatibilityCategory { category }
        var fitPercentage: Int? { fit.map { Int(($0 * 100).rounded()) } }
        var sharePercentage: Int { Int((share * 100).rounded()) }
    }

    private(set) var yours: Direction
    private(set) var theirs: Direction
    /// Requirements of yours that they don't meet.
    private(set) var theirIssues: [MatchIssue]
    /// Requirements of theirs that you don't meet.
    private(set) var yourIssues: [MatchIssue]
    /// The server made this match and decided its scores.
    private(set) var isDecidedByServer = false

    init(yours: Direction, theirs: Direction, theirIssues: [MatchIssue] = [], yourIssues: [MatchIssue] = []) {
        self.yours = yours
        self.theirs = theirs
        self.theirIssues = theirIssues
        self.yourIssues = yourIssues
    }

    init(you: ProfileCreationState, them: ProfileCreationState, on day: CalendarDate) {
        let distance = Self.distanceKilometers(you.location, them.location)
        self.init(yours: Self.direction(MatchReport.rows(seeker: you, candidate: them)),
                  theirs: Self.direction(MatchReport.rows(seeker: them, candidate: you)),
                  theirIssues: Self.issues(seeker: you, candidate: them, distance: distance, on: day),
                  yourIssues: Self.issues(seeker: them, candidate: you, distance: distance, on: day))
    }

    /// The server already checked every requirement both ways, and its
    /// scores are the ones the match was made on.
    mutating func useServerScores(yours: Int, theirs: Int) {
        self.yours.score = yours
        self.theirs.score = theirs
        theirIssues = []
        yourIssues = []
        isDecidedByServer = true
    }

    func direction(_ perspective: MatchReport.Perspective) -> Direction {
        perspective == .yours ? yours : theirs
    }

    /// Both ways at once, per category: each counts by the average of its two
    /// shares, and its fit is the two fits weighed by those shares. Σ share ×
    /// fit is the average of the two scores.
    var together: [CategoryFit] {
        let mine = Dictionary(uniqueKeysWithValues: yours.categories.map { ($0.category, $0) })
        let other = Dictionary(uniqueKeysWithValues: theirs.categories.map { ($0.category, $0) })
        let total = yours.categories.reduce(0) { $0 + $1.share } + theirs.categories.reduce(0) { $0 + $1.share }
        guard total > 0 else { return [] }
        return CompatibilityCategory.allCases.compactMap { category in
            let a = mine[category], b = other[category]
            guard a != nil || b != nil else { return nil }
            // A side where the category doesn't count adds nothing to it.
            let shareA = a.flatMap { $0.fit == nil ? nil : $0.share } ?? 0
            let shareB = b.flatMap { $0.fit == nil ? nil : $0.share } ?? 0
            let weight = shareA + shareB
            let fit = weight > 0 ? (shareA * (a?.fit ?? 0) + shareB * (b?.fit ?? 0)) / weight : nil
            return CategoryFit(category: category, fit: fit, share: weight / total)
        }
    }

    /// Splits a score into its categories. Uses the same rows, weights and
    /// closeness as `MatchReport.score`, so the parts add up to the score.
    static func direction(_ rows: [MatchReport.Row]) -> Direction {
        let total = rows.reduce(0) { $0 + $1.weight }
        var categories: [CategoryFit] = []
        for category in CompatibilityCategory.allCases {
            let inside = rows.filter { CompatibilityScaleQuestion.category(for: $0.step) == category }
            guard !inside.isEmpty else { continue }
            if total > 0 {
                let weight = inside.reduce(0) { $0 + $1.weight }
                let fit = weight > 0 ? inside.reduce(0) { $0 + $1.weight * $1.closeness } / weight : nil
                categories.append(CategoryFit(category: category, fit: fit, share: weight / total))
            } else {
                // Nothing matters to the seeker, which scores 100: every
                // category fits fully and counts by its number of questions.
                categories.append(CategoryFit(category: category, fit: 1,
                                              share: Double(inside.count) / Double(rows.count)))
            }
        }
        return Direction(score: MatchReport.score(rows), categories: categories)
    }

    static func distanceKilometers(_ a: SelectedLocation?, _ b: SelectedLocation?) -> Double? {
        guard let a, let b else { return nil }
        let from = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let to = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return from.distance(from: to) / 1000
    }

    /// The seeker's requirements the candidate fails.
    private static func issues(
        seeker: ProfileCreationState,
        candidate: ProfileCreationState,
        distance: Double?,
        on day: CalendarDate
    ) -> [MatchIssue] {
        var issues: [MatchIssue] = []
        if let gender = candidate.gender, !seeker.partnerGenders.isEmpty, !seeker.partnerGenders.contains(gender) {
            issues.append(.gender)
        }
        if let range = seeker.partnerAgeRange, let age = candidate.age(on: day),
           !(range.minimum...max(range.minimum, range.maximum)).contains(age) {
            issues.append(.age(age))
        }
        let heights = seeker.partnerHeightRange
        if !(heights.minimum...max(heights.minimum, heights.maximum)).contains(candidate.heightCentimeters) {
            issues.append(.height(candidate.heightCentimeters))
        }
        if !seeker.religion.effectivePartnerReligions.contains(candidate.religion.matchingReligion) {
            issues.append(.religion(candidate.religion.own))
        }
        if !seeker.languages.isEmpty, Set(seeker.languages).isDisjoint(with: candidate.languages) {
            issues.append(.languages(seeker.languages))
        }
        if let distance, distance > Double(seeker.searchRadiusKilometers) {
            issues.append(.distance(radius: seeker.searchRadiusKilometers))
        }
        if seeker.lifestyle.openToPartnerWithChildren == false, candidate.lifestyle.hasChildren == true {
            issues.append(.hasKids)
        }
        switch (seeker.lifestyle.futureChildren, candidate.lifestyle.futureChildren) {
        case (.yes, .no): issues.append(.doesNotWantKids)
        case (.no, .yes): issues.append(.wantsKids)
        default: break
        }
        for substance in Substance.allCases {
            guard let limit = seeker.lifestyle[substance].partnerMaximumLevel,
                  let level = candidate.lifestyle[substance].ownLevel, level > limit else { continue }
            issues.append(.substance(substance, level: level))
        }
        return issues
    }
}

/// A requirement one side fails, kept without wording so the text follows
/// the app's language and a renamed match.
enum MatchIssue: Codable, Equatable {
    case gender
    case age(Int)
    case height(Int)
    /// The candidate's own religion or worldview.
    case religion(Religion?)
    /// The languages the seeker speaks.
    case languages([String])
    case distance(radius: Int)
    case hasKids
    case doesNotWantKids
    case wantsKids
    case substance(Substance, level: Int)

    /// Phrased about the candidate: their name, or "you".
    func text(name: String, aboutYou you: Bool) -> String {
        switch self {
        case .gender:
            return you ? L10n("Your gender is outside \(name)’s preferences")
                       : L10n("\(name)’s gender is outside your preferences")
        case .age(let age):
            return you ? L10n("You are \(age), outside \(name)’s age range")
                       : L10n("\(name) is \(age), outside your age range")
        case .height(let height):
            return you ? L10n("You are \(height) cm, outside \(name)’s height range")
                       : L10n("\(name) is \(height) cm, outside your height range")
        case .religion(let own):
            let religion = ReligionAnswers(own: own, acceptedPartnerReligions: []).ownSummary
            return you ? L10n("Your religion or worldview (\(religion)) is outside \(name)’s preferences")
                       : L10n("\(name)’s religion or worldview (\(religion)) is outside your preferences")
        case .languages(let codes):
            let languages = codes.map { LanguageCatalog.option(for: $0).name }
                .formatted(.list(type: .or).locale(AppLocale.current))
            return you ? L10n("You don’t speak \(languages)")
                       : L10n("\(name) doesn’t speak \(languages)")
        case .distance(let radius):
            return you ? L10n("You live more than \(radius) km away from \(name)")
                       : L10n("\(name) lives more than \(radius) km away")
        case .hasKids:
            return you ? L10n("You have kids") : L10n("\(name) has kids")
        case .doesNotWantKids:
            return you ? L10n("You don’t want kids") : L10n("\(name) doesn’t want kids")
        case .wantsKids:
            return you ? L10n("You want kids") : L10n("\(name) wants kids")
        case .substance(let substance, let level):
            let levels = substance.levels
            let often = levels.indices.contains(level) ? levels[level].lowercased() : ""
            switch substance {
            case .alcohol:
                return you ? L10n("You drink alcohol \(often)") : L10n("\(name) drinks alcohol \(often)")
            case .smoking:
                return you ? L10n("You smoke or vape \(often)") : L10n("\(name) smokes or vapes \(often)")
            case .drugs:
                return you ? L10n("You use cannabis or other drugs \(often)")
                           : L10n("\(name) uses cannabis or other drugs \(often)")
            }
        }
    }
}

// MARK: - Report

/// What the match screens read: a frozen `MatchResult`, worded for a name.
struct MatchReport: Equatable {
    enum Perspective: String, Identifiable {
        /// How well they fit what you look for.
        case yours
        /// How well you fit what they look for.
        case theirs

        var id: String { rawValue }
    }

    /// One weighed 1–5 question, seen by whoever is looking for a partner.
    /// Only lives while two profiles are being compared; never stored.
    /// Alcohol, smoking and drugs never count towards a score: they are only
    /// hard limits.
    struct Row: Identifiable, Equatable {
        let step: ProfileCreationStep
        /// The other person's own answer.
        let value: Int
        /// What the seeker looks for.
        let wanted: Int
        /// How much it matters to the seeker, 1–5.
        let importance: Int

        var id: Int { step.rawValue }

        /// 1 for the answer that was looked for, falling evenly to 0 at the
        /// far end of the scale.
        var closeness: Double {
            let span = MatchWeighting.scaleSpan
            guard span > 0 else { return 1 }
            return 1 - Double(min(abs(value - wanted), span)) / Double(span)
        }

        var weight: Double { MatchWeighting.weight(importance: importance) }
    }

    let result: MatchResult
    let name: String

    init(result: MatchResult, name: String) {
        self.result = result
        self.name = name
    }

    /// Compares two profiles on the spot, as `MatchSnapshot` does once.
    init(you: ProfileCreationState, them: ProfileCreationState, on day: CalendarDate, name: String? = nil) {
        self.init(result: MatchResult(you: you, them: them, on: day), name: name ?? them.displayName)
    }

    var yourScore: Int { result.yours.score }
    var theirScore: Int { result.theirs.score }
    var average: Int { Int((Double(yourScore + theirScore) / 2).rounded()) }
    /// Requirements of yours that they don't meet.
    var theirIssues: [String] { result.theirIssues.map { $0.text(name: name, aboutYou: false) } }
    /// Requirements of theirs that you don't meet.
    var yourIssues: [String] { result.yourIssues.map { $0.text(name: name, aboutYou: true) } }
    var isMatch: Bool { result.theirIssues.isEmpty && result.yourIssues.isEmpty }
    var issues: [String] { theirIssues + yourIssues }

    func score(_ perspective: Perspective) -> Int {
        perspective == .yours ? yourScore : theirScore
    }

    func categories(_ perspective: Perspective) -> [MatchResult.CategoryFit] {
        result.direction(perspective).categories
    }

    // MARK: - Scores

    /// Every answered 1–5 question; alcohol, smoking and drugs are left out.
    static func rows(seeker: ProfileCreationState, candidate: ProfileCreationState) -> [Row] {
        CompatibilityScaleQuestion.orderedSteps.compactMap { step in
            guard let question = step.compatibilityQuestion else { return nil }
            let wish = seeker.lifestyle[question]
            guard let wanted = wish.partner, let value = candidate.lifestyle[question].own else { return nil }
            return Row(step: step, value: value, wanted: wanted,
                       importance: wish.importance ?? CompatibilityScaleAnswer.defaultImportance)
        }
    }

    /// The weighted average of how close each answer is to what was looked
    /// for: Σ weight × closeness ÷ Σ weight, as a percentage.
    static func score(_ rows: [Row]) -> Int {
        var total = 0.0
        var weight = 0.0
        for row in rows {
            total += row.weight * row.closeness
            weight += row.weight
        }
        // Nothing to compare scores nothing; answers that all don't matter
        // to the seeker can't count against anyone.
        guard weight > 0 else { return rows.isEmpty ? 0 : 100 }
        return Int((total / weight * 100).rounded())
    }

    static func distanceKilometers(_ a: SelectedLocation?, _ b: SelectedLocation?) -> Double? {
        MatchResult.distanceKilometers(a, b)
    }
}

// MARK: - Weighting

/// How much each answer counts towards a score.
enum MatchWeighting {
    /// The distance between the ends of a 1–5 question.
    static let scaleSpan = CompatibilityScaleAnswer.range.upperBound - CompatibilityScaleAnswer.range.lowerBound

    /// "Not important at all" doesn't count; from there every step up in
    /// importance counts twice as much as the one below it.
    static let weights: [Double] = [0, 1, 2, 4, 8]

    static func weight(importance: Int) -> Double {
        weights[min(max(importance, 1), weights.count) - 1]
    }
}

// MARK: - Saved matches

@MainActor
/// The demo match whose conversation is open. Like a live match with a
/// started chat, the app reopens straight into it.
struct OpenDemoChat: Codable, Equatable {
    let match: MatchSnapshot
    var conversation: ChatConversation

    nonisolated static let storageKey = "openDemoChat.v2"
    /// Held the other person's whole profile; removed wherever it is found.
    nonisolated static let legacyStorageKey = "openDemoChat.v1"

    static func load(defaults: UserDefaults = .standard) -> OpenDemoChat? {
        defaults.removeObject(forKey: legacyStorageKey)
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(OpenDemoChat.self, from: data)
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: legacyStorageKey)
    }
}

final class SavedMatchStore: ObservableObject {
    /// Newest first.
    @Published private(set) var matches: [MatchSnapshot] = []

    private let defaults: UserDefaults
    private let key: String

    nonisolated static let storageKey = "savedMatches.v2"
    /// Held the other person's whole profile; removed wherever it is found.
    nonisolated static let legacyStorageKey = "savedMatches.v1"

    /// Removes every saved match from the phone.
    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: legacyStorageKey)
    }

    init(defaults: UserDefaults = .standard, key: String = SavedMatchStore.storageKey) {
        self.defaults = defaults
        self.key = key
        defaults.removeObject(forKey: Self.legacyStorageKey)
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode([MatchSnapshot].self, from: data) {
            matches = stored.sorted { $0.matchedAt > $1.matchedAt }
        }
    }

    func contains(_ id: UUID) -> Bool { matches.contains { $0.id == id } }

    func save(_ match: MatchSnapshot) {
        guard !contains(match.id) else { return }
        matches.append(match)
        matches.sort { $0.matchedAt > $1.matchedAt }
        write()
    }

    func delete(_ id: UUID) {
        matches.removeAll { $0.id == id }
        write()
        MatchPhotoStore.shared.delete(id)
    }

    /// A deleted match stays in the list as broken; deleting it from there
    /// removes it for good.
    func markBroken(_ id: UUID, at date: Date = Date()) {
        guard let index = matches.firstIndex(where: { $0.id == id }), !matches[index].isBroken else { return }
        matches[index].ended = .init(at: date, reason: nil, byMe: true)
        write()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = matches.firstIndex(where: { $0.id == id }) else { return }
        var match = matches[index]
        guard match.rename(to: name) else { return }
        matches[index] = match
        write()
    }

    private func write() {
        guard let data = try? JSONEncoder().encode(matches) else { return }
        defaults.set(data, forKey: key)
    }
}
