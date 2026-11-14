import Combine
import CoreLocation
import Foundation

/// Both profiles exactly as they were when matched. A saved match keeps its
/// scores even after either profile changes.
struct MatchSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    let matchedAt: Date
    let you: ProfileCreationState
    let them: ProfileCreationState
    /// A local label; the original matched profiles remain unchanged.
    private(set) var customName: String?

    init(id: UUID = UUID(), matchedAt: Date, you: ProfileCreationState, them: ProfileCreationState) {
        self.id = id
        self.matchedAt = matchedAt
        self.you = you
        self.them = them
    }

    var name: String { customName ?? them.displayName }

    @discardableResult
    mutating func rename(to name: String) -> Bool {
        let name = ProfileNameRules.normalized(name)
        guard !name.isEmpty else { return false }
        customName = name == them.displayName ? nil : name
        return true
    }

    var report: MatchReport {
        MatchReport(you: you, them: them, on: CalendarDate.today(calendar: BirthDateRules.calendar, now: matchedAt), name: name)
    }
}

/// Scores both ways and every requirement either side fails. Meeting every
/// requirement both ways is what makes a match; the scores say how good.
struct MatchReport: Equatable {
    enum Perspective: String, Identifiable {
        /// How well they fit what you look for.
        case yours
        /// How well you fit what they look for.
        case theirs

        var id: String { rawValue }
    }

    /// One weighed 1–5 question, seen by whoever is looking for a partner.
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

    let yourScore: Int
    let theirScore: Int
    /// Requirements of yours that they don't meet.
    let theirIssues: [String]
    /// Requirements of theirs that you don't meet.
    let yourIssues: [String]
    private let yourRows: [Row]
    private let theirRows: [Row]

    var average: Int { Int((Double(yourScore + theirScore) / 2).rounded()) }
    var isMatch: Bool { theirIssues.isEmpty && yourIssues.isEmpty }
    var issues: [String] { theirIssues + yourIssues }

    init(you: ProfileCreationState, them: ProfileCreationState, on day: CalendarDate, name: String? = nil) {
        yourRows = Self.rows(seeker: you, candidate: them)
        theirRows = Self.rows(seeker: them, candidate: you)
        yourScore = Self.score(yourRows)
        theirScore = Self.score(theirRows)
        let distance = Self.distanceKilometers(you.location, them.location)
        theirIssues = Self.issues(seeker: you, candidate: them, name: name ?? them.displayName,
                                  isCandidateYou: false, distance: distance, on: day)
        yourIssues = Self.issues(seeker: them, candidate: you, name: name ?? them.displayName,
                                 isCandidateYou: true, distance: distance, on: day)
    }

    func score(_ perspective: Perspective) -> Int {
        perspective == .yours ? yourScore : theirScore
    }

    func rows(_ perspective: Perspective) -> [Row] {
        perspective == .yours ? yourRows : theirRows
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
        guard let a, let b else { return nil }
        let from = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let to = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return from.distance(from: to) / 1000
    }

    // MARK: - Requirements

    /// The seeker's requirements the candidate fails, phrased about the
    /// candidate: their name, or "you".
    private static func issues(
        seeker: ProfileCreationState,
        candidate: ProfileCreationState,
        name: String,
        isCandidateYou you: Bool,
        distance: Double?,
        on day: CalendarDate
    ) -> [String] {
        var issues: [String] = []
        if let gender = candidate.gender, !seeker.partnerGenders.isEmpty, !seeker.partnerGenders.contains(gender) {
            issues.append(you ? L10n("Your gender is outside \(name)’s preferences")
                              : L10n("\(name)’s gender is outside your preferences"))
        }
        if let range = seeker.partnerAgeRange, let age = candidate.age(on: day),
           !(range.minimum...max(range.minimum, range.maximum)).contains(age) {
            issues.append(you ? L10n("You are \(age), outside \(name)’s age range")
                              : L10n("\(name) is \(age), outside your age range"))
        }
        let heights = seeker.partnerHeightRange
        if !(heights.minimum...max(heights.minimum, heights.maximum)).contains(candidate.heightCentimeters) {
            let height = candidate.heightCentimeters
            issues.append(you ? L10n("You are \(height) cm, outside \(name)’s height range")
                              : L10n("\(name) is \(height) cm, outside your height range"))
        }
        if !seeker.religion.effectivePartnerReligions.contains(candidate.religion.matchingReligion) {
            let religion = candidate.religion.ownSummary
            issues.append(you ? L10n("Your religion or worldview (\(religion)) is outside \(name)’s preferences")
                              : L10n("\(name)’s religion or worldview (\(religion)) is outside your preferences"))
        }
        if !seeker.languages.isEmpty, Set(seeker.languages).isDisjoint(with: candidate.languages) {
            let languages = seeker.languages.map { LanguageCatalog.option(for: $0).name }
                .formatted(.list(type: .or).locale(AppLocale.current))
            issues.append(you ? L10n("You don’t speak \(languages)")
                              : L10n("\(name) doesn’t speak \(languages)"))
        }
        if let distance, distance > Double(seeker.searchRadiusKilometers) {
            let radius = seeker.searchRadiusKilometers
            issues.append(you ? L10n("You live more than \(radius) km away from \(name)")
                              : L10n("\(name) lives more than \(radius) km away"))
        }
        if seeker.lifestyle.openToPartnerWithChildren == false, candidate.lifestyle.hasChildren == true {
            issues.append(you ? L10n("You have kids") : L10n("\(name) has kids"))
        }
        switch (seeker.lifestyle.futureChildren, candidate.lifestyle.futureChildren) {
        case (.yes, .no):
            issues.append(you ? L10n("You don’t want kids") : L10n("\(name) doesn’t want kids"))
        case (.no, .yes):
            issues.append(you ? L10n("You want kids") : L10n("\(name) wants kids"))
        default:
            break
        }
        for substance in Substance.allCases {
            guard let limit = seeker.lifestyle[substance].partnerMaximumLevel,
                  let level = candidate.lifestyle[substance].ownLevel, level > limit else { continue }
            let often = substance.levels[level].lowercased()
            switch substance {
            case .alcohol:
                issues.append(you ? L10n("You drink alcohol \(often)") : L10n("\(name) drinks alcohol \(often)"))
            case .smoking:
                issues.append(you ? L10n("You smoke or vape \(often)") : L10n("\(name) smokes or vapes \(often)"))
            case .drugs:
                issues.append(you ? L10n("You use cannabis or other drugs \(often)")
                                  : L10n("\(name) uses cannabis or other drugs \(often)"))
            }
        }
        return issues
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
final class SavedMatchStore: ObservableObject {
    /// Newest first.
    @Published private(set) var matches: [MatchSnapshot] = []

    private let defaults: UserDefaults
    private let key: String

    nonisolated static let storageKey = "savedMatches.v1"

    /// Removes every saved match from the phone.
    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    init(defaults: UserDefaults = .standard, key: String = SavedMatchStore.storageKey) {
        self.defaults = defaults
        self.key = key
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
