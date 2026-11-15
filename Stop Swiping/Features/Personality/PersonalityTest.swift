import Foundation

/// The personality models a finished profile can be read as. Every result is
/// an estimate from the compatibility questions, never the official test.
enum PersonalityTest: String, CaseIterable, Identifiable, Hashable {
    case mbti
    case disc
    case bigFive
    case enneagram
    case sixteenPersonalities
    case insights
    case hexaco
    case belbin
    case predictiveIndex
    case tma

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mbti: "MBTI (Myers-Briggs)"
        case .disc: "DISC"
        case .bigFive: "Big Five (OCEAN)"
        case .enneagram: "Enneagram"
        case .sixteenPersonalities: "16Personalities"
        case .insights: "Insights Discovery"
        case .hexaco: "HEXACO"
        case .belbin: L10n("Belbin team roles")
        case .predictiveIndex: "Predictive Index (PI)"
        case .tma: L10n("TMA (Talent Motivation Analysis)")
        }
    }

    /// What the model describes, in a few words.
    var measures: String {
        switch self {
        case .mbti: L10n("16 personality types")
        case .disc: L10n("4 behavioural styles")
        case .bigFive: L10n("5 personality dimensions")
        case .enneagram: L10n("9 types with core motivations")
        case .sixteenPersonalities: L10n("16 types with an identity trait")
        case .insights: L10n("4 colour energies")
        case .hexaco: L10n("6 basic dimensions")
        case .belbin: L10n("9 roles within a team")
        case .predictiveIndex: L10n("4 behavioural drives at work")
        case .tma: L10n("Drives and talents")
        }
    }
}

/// One axis of a chart, labelled for the overlay and the panel.
struct PersonalityDimension: Equatable {
    /// The left pole of a spectrum.
    let low: PersonalityPole
    /// The right pole of a spectrum.
    let high: PersonalityPole
    /// −1…1, negative toward `low`.
    let value: Double

    var leansHigh: Bool { value >= 0 }
    var dominant: PersonalityPole { leansHigh ? high : low }
    /// How strongly the dominant pole wins, 50…100.
    var percent: Int { Int((50 + 50 * min(abs(value), 1)).rounded()) }
}

struct PersonalityPole: Equatable {
    /// One or two letters, such as E or I.
    let letter: String
    let name: String
}

/// One corner of a radar, quarter of a wheel or point of the enneagram.
struct PersonalityTrait: Equatable {
    let name: String
    /// A letter, number or short word for the chart.
    let short: String
    /// 0…1.
    let value: Double

    var percent: Int { Int((min(max(value, 0), 1) * 100).rounded()) }
}

/// How a result is drawn in the light.
enum PersonalityChart: Equatable {
    /// Rows with two poles.
    case spectrum([PersonalityDimension])
    /// A polygon, one corner per trait, the first at the top.
    case radar([PersonalityTrait])
    /// Nine types, the main type and its wing (both 1…9).
    case enneagram([PersonalityTrait], type: Int, wing: Int)
    /// Top left, top right, bottom right and bottom left, and the user's
    /// position in −1…1 of the radius (y downward).
    case wheel([PersonalityTrait], x: Double, y: Double)

    var visual: WelcomeLightPersonality.Visual {
        switch self {
        case .spectrum(let dimensions):
            WelcomeLightPersonality.Visual(kind: .spectrum, values: dimensions.map(\.value))
        case .radar(let traits):
            WelcomeLightPersonality.Visual(kind: .radar, values: traits.map(\.value))
        case .enneagram(let traits, let type, let wing):
            WelcomeLightPersonality.Visual(kind: .enneagram,
                                           values: traits.map(\.value) + [Double(type), Double(wing)])
        case .wheel(let quarters, let x, let y):
            WelcomeLightPersonality.Visual(kind: .wheel, values: [x, y] + quarters.map(\.value))
        }
    }
}

/// An estimated result, ready for the panel and the light.
struct PersonalityResult: Equatable {
    let test: PersonalityTest
    /// The type itself, such as INTJ.
    let headline: String
    /// The headline spelled out.
    let name: String
    let summary: String
    let chart: PersonalityChart

    var visual: WelcomeLightPersonality.Visual { chart.visual }
}
