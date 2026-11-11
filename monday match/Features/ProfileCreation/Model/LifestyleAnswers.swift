import Foundation

enum FutureChildrenWish: String, Codable, CaseIterable, Hashable {
    case yes
    case no
    case notSure

    var title: String {
        switch self {
        case .yes: "Yes"
        case .no: "No"
        case .notSure: "Not sure yet"
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
            ["Never", "Less than once a month", "1–3 times a month", "About once a week", "2–3 times a week", "4+ days a week"]
        case .smoking:
            ["Never", "Less than once a month", "A few times a month", "A few times a week", "Daily", "Several times a day"]
        case .drugs:
            ["Never", "About once a year", "About once every 3 months", "About once a month", "About once a week", "Several times a week"]
        }
    }

    var name: String {
        switch self {
        case .alcohol: "Alcohol"
        case .smoking: "Smoking & vaping"
        case .drugs: "Cannabis & drugs"
        }
    }

    var ownPrompt: String {
        switch self {
        case .alcohol: "How often do you drink alcohol?"
        case .smoking: "How often do you smoke or vape?"
        case .drugs: "How often do you use cannabis or other recreational drugs?"
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

    var own: Int?
    var partner: Int?
    /// Until the partner value is changed by hand it follows `own`.
    var isPartnerCustomized = false
    var importance: Int?

    var isComplete: Bool { own != nil && partner != nil && importance != nil }

    static func importanceTitle(_ value: Int) -> String {
        switch value {
        case 1: "Not important at all"
        case 2: "Slightly important"
        case 3: "Fairly important"
        case 4: "Important"
        default: "Very important"
        }
    }
}

struct CompatibilityScaleQuestion: Hashable {
    let id: String
    let title: String
    let lowLabel: String
    let highLabel: String

    static let aloneTime = CompatibilityScaleQuestion(
        id: "aloneTime",
        title: "Time for yourself",
        lowLabel: "Little time alone",
        highLabel: "Lots of time alone"
    )
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
