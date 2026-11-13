import Foundation

enum FutureChildrenWish: String, Codable, CaseIterable, Hashable {
    case yes
    case no
    case notSure

    var title: String {
        switch self {
        case .yes: L10n("Yes")
        case .no: L10n("No")
        case .notSure: L10n("Not sure yet")
        }
    }
}

/// Behaviour asked as a frequency for the user and as an acceptance limit for
/// a partner. Levels are ordered from never to most often, so every level at
/// or below a partner limit is acceptable.
enum Substance: String, Codable, CaseIterable, Hashable {
    case alcohol
    case smoking
    case drugs

    var levels: [String] {
        switch self {
        case .alcohol:
            [L10n("Never"), L10n("Less than once a month"), L10n("1–3 times a month"), L10n("About once a week"), L10n("2–3 times a week"), L10n("4+ days a week")]
        case .smoking:
            [L10n("Never"), L10n("Less than once a month"), L10n("A few times a month"), L10n("A few times a week"), L10n("Daily"), L10n("Several times a day")]
        case .drugs:
            [L10n("Never"), L10n("About once a year"), L10n("About once every 3 months"), L10n("About once a month"), L10n("About once a week"), L10n("Several times a week")]
        }
    }

    var name: String {
        switch self {
        case .alcohol: L10n("Alcohol")
        case .smoking: L10n("Smoking & vaping")
        case .drugs: L10n("Cannabis & drugs")
        }
    }

    var ownPrompt: String {
        switch self {
        case .alcohol: L10n("How often do you drink alcohol?")
        case .smoking: L10n("How often do you smoke or vape?")
        case .drugs: L10n("How often do you use cannabis or other recreational drugs?")
        }
    }
}

struct SubstanceAnswer: Codable, Equatable {
    /// Index into `Substance.levels`.
    var ownLevel: Int?
    /// The highest acceptable index into `Substance.levels`.
    var partnerMaximumLevel: Int?

    func accepts(partnerLevel level: Int) -> Bool {
        guard let partnerMaximumLevel else { return false }
        return level <= partnerMaximumLevel
    }
}

/// A 1–5 compatibility question: the user's own position, the position they
/// look for in a partner, and how much a match on it matters to them.
struct CompatibilityScaleAnswer: Codable, Equatable {
    static let range = 1...5
    static let defaultImportance = 3

    var own: Int?
    var partner: Int?
    /// Until the partner value is changed by hand it follows `own`.
    var isPartnerCustomized = false
    var importance: Int? = defaultImportance

    var isComplete: Bool { own != nil && partner != nil && importance != nil }

    /// Prefilled partner and importance values alone never trigger navigation.
    var hasCustomValuesForAutoAdvance: Bool {
        isComplete && isPartnerCustomized && own != partner && importance != Self.defaultImportance
    }

    static func importanceTitle(_ value: Int) -> String {
        switch value {
        case 1: L10n("Not important at all")
        case 2: L10n("Slightly important")
        case 3: L10n("Fairly important")
        case 4: L10n("Important")
        default: L10n("Very important")
        }
    }
}

extension CompatibilityScaleAnswer {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        own = try values.decodeIfPresent(Int.self, forKey: .own)
        partner = try values.decodeIfPresent(Int.self, forKey: .partner)
        isPartnerCustomized = try values.decodeIfPresent(Bool.self, forKey: .isPartnerCustomized) ?? false
        importance = try values.decodeIfPresent(Int.self, forKey: .importance) ?? Self.defaultImportance
    }
}

struct CompatibilityScaleQuestion: Hashable {
    let id: String
    let title: String
    let lowLabel: String
    let highLabel: String

    static var aloneTime: CompatibilityScaleQuestion {
        CompatibilityScaleQuestion(
            id: "aloneTime",
            title: L10n("Time for yourself"),
            lowLabel: L10n("Little time alone"),
            highLabel: L10n("Lots of time alone")
        )
    }
}

struct LifestyleAnswers: Codable, Equatable {
    var hasChildren: Bool?
    var openToPartnerWithChildren: Bool?
    var futureChildren: FutureChildrenWish?
    private var substances: [String: SubstanceAnswer] = [:]
    var aloneTime = CompatibilityScaleAnswer()

    /// Levels that no longer exist on a revised scale read as unanswered.
    subscript(substance: Substance) -> SubstanceAnswer {
        get {
            var answer = substances[substance.rawValue] ?? SubstanceAnswer()
            let levels = substance.levels.indices
            if let level = answer.ownLevel, !levels.contains(level) { answer.ownLevel = nil }
            if let level = answer.partnerMaximumLevel, !levels.contains(level) { answer.partnerMaximumLevel = nil }
            return answer
        }
        set { substances[substance.rawValue] = newValue }
    }
}
