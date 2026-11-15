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

extension PersonalityTest {
    /// A short introduction, shown from the info button.
    var about: String {
        switch self {
        case .mbti: L10n("The Myers-Briggs Type Indicator sorts preferences on four scales, building on Carl Jung’s types. Your four letters combine into one of 16 types.")
        case .disc: L10n("DISC describes behaviour on two axes: fast-paced or steady, and task- or people-oriented. That gives four styles, and most people mix two of them.")
        case .bigFive: L10n("The Big Five (OCEAN) is the most researched model in personality psychology. It scores five broad traits that everyone has to some degree.")
        case .enneagram: L10n("The Enneagram describes nine types, each driven by its own core motivation and fear. The lines in the figure show how the types connect.")
        case .sixteenPersonalities: L10n("16Personalities builds on the Myers-Briggs letters and adds a fifth scale: how self-assured you are under pressure.")
        case .insights: L10n("Insights Discovery uses four colour energies based on Jung: Fiery Red, Sunshine Yellow, Earth Green and Cool Blue. Everyone has all four, in their own mix.")
        case .hexaco: L10n("HEXACO extends the Big Five with a sixth dimension, Honesty-Humility, and is widely used in scientific research.")
        case .belbin: L10n("Meredith Belbin found nine roles people take on in teams. Most people have two or three preferred roles; strong teams cover all nine.")
        case .predictiveIndex: L10n("The Predictive Index measures four behavioural drives at work and matches the pattern to one of 17 reference profiles.")
        case .tma: L10n("The Talent Motivation Analysis, developed in the Netherlands, maps drives and talents. These are eight drives, read from your answers.")
        }
    }

    /// How to read a code that is more than a type name.
    var codeNote: String? {
        switch self {
        case .bigFive, .hexaco: L10n("Capital letter: high score · small letter: low score.")
        case .enneagram: L10n("4w5 means type 4 with wing 5: the neighbouring type that colours it most.")
        default: nil
        }
    }

    /// Where to read more, from the model's own publisher where it has one.
    var infoURL: URL {
        let address = switch self {
        case .mbti: "https://www.myersbriggs.org"
        case .disc: "https://en.wikipedia.org/wiki/DISC_assessment"
        case .bigFive: "https://en.wikipedia.org/wiki/Big_Five_personality_traits"
        case .enneagram: "https://www.enneagraminstitute.com/type-descriptions"
        case .sixteenPersonalities: "https://www.16personalities.com"
        case .insights: "https://www.insights.com/products/insights-discovery/"
        case .hexaco: "https://hexaco.org"
        case .belbin: "https://www.belbin.com/about/belbin-team-roles"
        case .predictiveIndex: "https://www.predictiveindex.com/assessments/behavioral-assessment/"
        case .tma:
            switch AppLanguageSettings.shared.language {
            case .dutch: "https://www.tma.nl"
            case .english: "https://www.tma.nl/en"
            }
        }
        return URL(string: address)!
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

    /// A number or capital abbreviation (O, IMP, 4) that needs spelling out.
    var isAbbreviated: Bool {
        Int(short) != nil || (short.count <= 3 && short == short.uppercased() && short != name)
    }
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

    /// What each letter, number or abbreviation in the chart stands for.
    /// Labels that already spell themselves out are left out.
    var legend: [(key: String, value: String)] {
        switch chart {
        case .spectrum(let dimensions):
            dimensions.map { dimension in
                let key = dimension.low.letter == dimension.high.letter
                    ? dimension.low.letter : "\(dimension.low.letter)/\(dimension.high.letter)"
                return (key, "\(dimension.low.name) ↔ \(dimension.high.name)")
            }
        case .radar(let traits), .wheel(let traits, _, _), .enneagram(let traits, _, _):
            traits.filter { $0.isAbbreviated }.map { ($0.short, $0.name) }
        }
    }
}
