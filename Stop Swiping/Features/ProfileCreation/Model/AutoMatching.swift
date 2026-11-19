import Foundation

struct PartnerHeightRange: Codable, Equatable {
    var minimum: Int
    var maximum: Int

    /// The whole scale: height doesn't rule anyone out.
    static let any = PartnerHeightRange(minimum: PartnerHeightRules.lowerBound, maximum: PartnerHeightRules.upperBound)

    var isAny: Bool { self == .any }
}

enum PartnerHeightRules {
    static let lowerBound = HeightRules.range.lowerBound
    static let upperBound = HeightRules.range.upperBound

    static var bounds: ClosedRange<Int> { lowerBound...upperBound }

    static func clamped(minimum: Int, maximum: Int) -> PartnerHeightRange {
        let lower = min(max(minimum, lowerBound), upperBound)
        let upper = min(max(maximum, lower), upperBound)
        return PartnerHeightRange(minimum: lower, maximum: upper)
    }
}

/// Shared by both appearance answers, displayed from 10 down to 1.
enum AppearanceRating {
    static let range = 1...10
    static let descendingScores = Array(range.reversed())

    static func description(for score: Int) -> String {
        switch score {
        case 1: L10n("Thank God for personality")
        case 2: L10n("My mom thinks I'm cute")
        case 3: L10n("Looks aren't everything, right?")
        case 4: L10n("Better after a few drinks")
        case 5: L10n("Not bad, not great")
        case 6: L10n("Pretty decent, actually")
        case 7: L10n("A solid catch")
        case 8: L10n("Certified hottie")
        case 9: L10n("Ridiculously good-looking")
        case 10: L10n("Hollywood's finest")
        default: ""
        }
    }
}

/// Opting in to matches proposed automatically. A photo is optional; when
/// supplied, it is stored with the profile draft and verified before joining.
struct AutoMatchingSettings: Codable, Equatable {
    static let minimumScoreRange = 50...90
    static let minimumScoreStep = 5

    var privacyConsent: PrivacyConsentReceipt?
    var isEnabled = false
    /// Kept when switching off, so the saved setup can be resumed directly.
    var hasCompletedSetup = false
    /// The ID of the photo in `ProfileDraft.photos`.
    var photoID: UUID?
    /// 1–10: how attractive the user finds their own appearance.
    var ownAttractiveness: Int?
    /// 1–10: the lowest acceptable appearance score for a partner.
    var partnerMinimumAttractiveness: Int?
    /// The lowest overall match, in percent, that may be proposed.
    var minimumMatchPercent = 70
    /// Whether proposed partners must have verified their photo.
    var requiresVerifiedPartnerPhoto = true
    /// Also send this photo when profiles are exchanged by holding two
    /// phones together. Off until chosen.
    var sharesPhotoWithManualMatching = false

    var isReady: Bool {
        guard let ownAttractiveness, let partnerMinimumAttractiveness else { return false }
        return AppearanceRating.range.contains(ownAttractiveness) && AppearanceRating.range.contains(partnerMinimumAttractiveness)
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case isEnabled, photoID, ownAttractiveness, partnerMinimumAttractiveness, minimumMatchPercent
        case appearanceScaleVersion, requiresVerifiedPartnerPhoto, hasCompletedSetup, privacyConsent
        case sharesPhotoWithManualMatching
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        requiresVerifiedPartnerPhoto = try values.decodeIfPresent(Bool.self, forKey: .requiresVerifiedPartnerPhoto) ?? true
        photoID = try values.decodeIfPresent(UUID.self, forKey: .photoID)
        sharesPhotoWithManualMatching = try values.decodeIfPresent(Bool.self, forKey: .sharesPhotoWithManualMatching) ?? false
        minimumMatchPercent = Self.clampedScore(try values.decodeIfPresent(Int.self, forKey: .minimumMatchPercent) ?? 70)
        // The previous 1–5 answers included importance, not a minimum score.
        // Keep the photo and match threshold, and ask for the new scores.
        if try values.decodeIfPresent(Int.self, forKey: .appearanceScaleVersion) == 1 {
            ownAttractiveness = try values.decodeIfPresent(Int.self, forKey: .ownAttractiveness)
                .flatMap { AppearanceRating.range.contains($0) ? $0 : nil }
            partnerMinimumAttractiveness = try values.decodeIfPresent(Int.self, forKey: .partnerMinimumAttractiveness)
                .flatMap { AppearanceRating.range.contains($0) ? $0 : nil }
        }
        privacyConsent = try values.decodeIfPresent(PrivacyConsentReceipt.self, forKey: .privacyConsent)
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) == true && isReady
            && privacyConsent?.isCurrent(for: .matching) == true
        hasCompletedSetup = try values.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup) ?? isEnabled
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(privacyConsent, forKey: .privacyConsent)
        try values.encode(isEnabled, forKey: .isEnabled)
        try values.encode(hasCompletedSetup, forKey: .hasCompletedSetup)
        try values.encode(requiresVerifiedPartnerPhoto, forKey: .requiresVerifiedPartnerPhoto)
        try values.encodeIfPresent(photoID, forKey: .photoID)
        try values.encode(sharesPhotoWithManualMatching, forKey: .sharesPhotoWithManualMatching)
        try values.encodeIfPresent(ownAttractiveness, forKey: .ownAttractiveness)
        try values.encodeIfPresent(partnerMinimumAttractiveness, forKey: .partnerMinimumAttractiveness)
        try values.encode(minimumMatchPercent, forKey: .minimumMatchPercent)
        try values.encode(1, forKey: .appearanceScaleVersion)
    }

    static func clampedScore(_ percent: Int) -> Int {
        let stepped = Int((Double(percent) / Double(minimumScoreStep)).rounded()) * minimumScoreStep
        return min(max(stepped, minimumScoreRange.lowerBound), minimumScoreRange.upperBound)
    }
}

/// The answers that rule a potential partner out regardless of personality,
/// in the order the questions are asked.
struct MatchDealbreakers: Equatable {
    enum Pronoun {
        case he
        case she
        case they

    }

    struct Entry: Equatable {
        let step: ProfileCreationStep
        let text: String
    }

    /// Include unrestricted preferences so they can also be tightened here.
    static let editableSteps: [ProfileCreationStep] = [
        .religion, .partnerAgeRange, .partnerHeightRange, .languages, .location,
        .partnerHasChildren, .futureChildren, .alcohol, .smoking, .drugs
    ]

    let pronoun: Pronoun
    let entries: [Entry]
    var lines: [String] { entries.map(\.text) }

    /// One full sentence per pronoun, so a translation never has to fit an
    /// English pronoun into its own grammar.
    var heading: String {
        switch pronoun {
        case .he: L10n("Even if your potential partner matches \(L10nPercent(100)) on personality, you will not be matched if he:")
        case .she: L10n("Even if your potential partner matches \(L10nPercent(100)) on personality, you will not be matched if she:")
        case .they: L10n("Even if your potential partner matches \(L10nPercent(100)) on personality, you will not be matched if they:")
        }
    }

    init(state: ProfileCreationState) {
        let genders = state.partnerGenders
        pronoun = genders == [.man] ? .he : (genders == [.woman] ? .she : .they)
        // Every line is a complete localized sentence. Gluing translated verbs
        // onto translated fragments breaks in languages with other word order.
        let singular = pronoun != .they
        func pick(_ one: String, _ many: String) -> String { singular ? one : many }

        var entries: [Entry] = []
        for step in ProfileCreationStep.allCases {
            // A sentence may start with a lowercased frequency ("dagelijks of vaker rookt").
            func append(_ text: String) {
                let capitalized = text.prefix(1).uppercased(with: AppLocale.current) + text.dropFirst()
                entries.append(Entry(step: step, text: capitalized))
            }
            switch step {
            case .religion:
                let accepted = state.religion.effectivePartnerReligions
                if accepted.count < Religion.allCases.count {
                    let titles = Religion.allCases.filter { accepted.contains($0) }.map(\.title).joined(separator: ", ")
                    append(pick(L10n("Has a religion or worldview outside your preferences (\(titles))"),
                                L10n("Have a religion or worldview outside your preferences (\(titles))")))
                }
            case .partnerAgeRange:
                // One sentence per combination of limits, so languages that put
                // the verb last (Dutch: "jonger is dan 25") read naturally.
                guard let range = state.partnerAgeRange else { continue }
                let low = range.minimum, high = range.maximum
                switch (low > PartnerAgeRules.lowerBound, high < PartnerAgeRules.upperBound) {
                case (true, true):
                    append(pick(L10n("Is younger than \(low) or older than \(high)"),
                                L10n("Are younger than \(low) or older than \(high)")))
                case (true, false): append(pick(L10n("Is younger than \(low)"), L10n("Are younger than \(low)")))
                case (false, true): append(pick(L10n("Is older than \(high)"), L10n("Are older than \(high)")))
                case (false, false): break
                }
            case .partnerHeightRange:
                let range = state.partnerHeightRange
                let low = range.minimum, high = range.maximum
                switch (low > PartnerHeightRules.lowerBound, high < PartnerHeightRules.upperBound) {
                case (true, true):
                    append(pick(L10n("Is shorter than \(low) cm or taller than \(high) cm"),
                                L10n("Are shorter than \(low) cm or taller than \(high) cm")))
                case (true, false): append(pick(L10n("Is shorter than \(low) cm"), L10n("Are shorter than \(low) cm")))
                case (false, true): append(pick(L10n("Is taller than \(high) cm"), L10n("Are taller than \(high) cm")))
                case (false, false): break
                }
            case .languages:
                let names = state.languages.map { LanguageCatalog.option(for: $0).name }
                if names.count == 1, let name = names.first {
                    append(singular ? L10n("Doesn’t speak \(name)") : L10n("Don’t speak \(name)"))
                } else if names.count == 2 {
                    append(pick(L10n("Speaks neither \(names[0]) nor \(names[1])"),
                                L10n("Speak neither \(names[0]) nor \(names[1])")))
                } else if !names.isEmpty {
                    let list = names.formatted(.list(type: .or).locale(AppLocale.current))
                    append(pick(L10n("Speaks none of \(list)"), L10n("Speak none of \(list)")))
                }
            case .location:
                if state.location != nil {
                    let radius = state.searchRadiusKilometers
                    append(pick(L10n("Lives more than \(radius) km away"), L10n("Live more than \(radius) km away")))
                }
            case .partnerHasChildren:
                if state.lifestyle.openToPartnerWithChildren == false {
                    append(pick(L10n("Has kids"), L10n("Have kids")))
                }
            case .futureChildren:
                switch state.lifestyle.futureChildren {
                case .yes: append(singular ? L10n("Doesn’t want kids") : L10n("Don’t want kids"))
                case .no: append(singular ? L10n("Wants kids") : L10n("Want kids"))
                case .notSure, nil: break
                }
            case .alcohol, .smoking, .drugs:
                guard let substance = step.substance,
                      let limit = state.lifestyle[substance].partnerMaximumLevel,
                      limit + 1 < substance.levels.count else { continue }
                let level = substance.levels[limit + 1].lowercased(with: AppLocale.current)
                // "Or more often" is redundant when only the top level is ruled out.
                let isTopLevel = limit + 2 == substance.levels.count
                switch (substance, isTopLevel) {
                case (.alcohol, false):
                    append(pick(L10n("Drinks alcohol \(level) or more often"), L10n("Drink alcohol \(level) or more often")))
                case (.alcohol, true):
                    append(pick(L10n("Drinks alcohol \(level)"), L10n("Drink alcohol \(level)")))
                case (.smoking, false):
                    append(pick(L10n("Smokes or vapes \(level) or more often"), L10n("Smoke or vape \(level) or more often")))
                case (.smoking, true):
                    append(pick(L10n("Smokes or vapes \(level)"), L10n("Smoke or vape \(level)")))
                case (.drugs, false):
                    append(pick(L10n("Uses cannabis or other drugs \(level) or more often"),
                                L10n("Use cannabis or other drugs \(level) or more often")))
                case (.drugs, true):
                    append(pick(L10n("Uses cannabis or other drugs \(level)"), L10n("Use cannabis or other drugs \(level)")))
                }
            default:
                continue
            }
        }
        self.entries = entries
    }
}
