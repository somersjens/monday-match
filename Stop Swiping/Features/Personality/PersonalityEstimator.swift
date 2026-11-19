import Foundation

/// The user's own positions on the compatibility questions, centred so that
/// −1 is the low end of a scale, 0 the middle and 1 the high end.
struct PersonalityAnswers {
    private let values: [ProfileCreationStep: Double]

    init(state: ProfileCreationState) {
        var values: [ProfileCreationStep: Double] = [:]
        for question in CompatibilityScaleQuestion.all {
            guard let own = state.lifestyle[question].own else { continue }
            values[question.step] = Double(own - 3) / 2
        }
        self.values = values
    }

    init(values: [ProfileCreationStep: Double]) {
        self.values = values
    }

    /// Share of the questions that were answered.
    var coverage: Double {
        Double(values.count) / Double(max(CompatibilityScaleQuestion.orderedSteps.count, 1))
    }

    /// The weighted mean of the answered questions, −1…1, pulled slightly
    /// toward the middle when little evidence was answered, so a single
    /// question never decides a dimension on its own. It is never stretched:
    /// only answers that all point the same way reach the ends.
    func score(_ weights: KeyValuePairs<ProfileCreationStep, Double>) -> Double {
        var total = 0.0, weight = 0.0
        for (step, w) in weights {
            guard let value = values[step] else { continue }
            total += value * w
            weight += abs(w)
        }
        guard weight > 0 else { return 0 }
        return total / (weight + Self.evidencePrior)
    }

    /// Answered weight that counts as missing evidence, pulling thin scores
    /// toward the middle.
    static let evidencePrior = 0.6
}

/// Reads the compatibility answers as personality models. The questions were
/// never written for these tests, so each dimension combines the answers that
/// describe the same behaviour.
enum PersonalityEstimator {
    static func result(for test: PersonalityTest, state: ProfileCreationState) -> PersonalityResult? {
        result(for: test, answers: PersonalityAnswers(state: state))
    }

    static func result(for test: PersonalityTest, answers a: PersonalityAnswers) -> PersonalityResult? {
        switch test {
        case .mbti: mbti(a)
        case .disc: disc(a)
        case .bigFive: bigFive(a)
        case .enneagram: enneagram(a)
        case .sixteenPersonalities: sixteenPersonalities(a)
        case .insights: insights(a)
        case .hexaco: hexaco(a)
        case .belbin: belbin(a)
        case .predictiveIndex: predictiveIndex(a)
        case .tma: tma(a)
        }
    }

    // MARK: - Helpers

    /// −1…1 as 0…1, for models that compare a person with everyone else
    /// (Big Five, HEXACO): 50% is the middle of every scale.
    nonisolated static func absolute(_ score: Double) -> Double { (score + 1) / 2 }

    /// For models that rank a person's own preferences (Belbin, TMA,
    /// Enneagram): each score against the person's own average, in standard
    /// deviations, around 50%. A typical strongest preference lands near
    /// 85–90% and never at 100%; nearly equal scores stay near 50%.
    static func relative(_ scores: [Double]) -> [Double] {
        let count = Double(max(scores.count, 1))
        let mean = scores.reduce(0, +) / count
        let variance = scores.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / count
        let spread = max(variance.squareRoot(), 0.12)
        return scores.map { min(max(0.5 + 0.22 * ($0 - mean) / spread, 0.06), 0.96) }
    }

    /// The four quarters of a two-axis model (top left, top right, bottom
    /// right, bottom left) as shares that add up to 1. `up` and `right` are
    /// −1…1; each quarter is the mean of its two axis directions.
    static func quarterShares(up: Double, right: Double) -> [Double] {
        let quarters = [(up - right) / 2, (up + right) / 2, (right - up) / 2, (-up - right) / 2].map(absolute)
        let total = quarters.reduce(0, +)
        return quarters.map { $0 / total }
    }

    /// The user's point on a wheel, y downward, at most 85% of the radius.
    static func wheelPoint(up: Double, right: Double) -> (Double, Double) {
        var x = right * 0.85, y = -up * 0.85
        let length = hypot(x, y)
        if length > 0.85 { x *= 0.85 / length; y *= 0.85 / length }
        return (x, y)
    }

    static func ranked(_ values: [Double]) -> [Int] {
        values.indices.sorted { values[$0] > values[$1] }
    }

    /// Upper case for the high half of a scale, lower case for the low half.
    static func code(_ letters: [String], _ values: [Double]) -> String {
        zip(letters, values).map { $1 >= 0.5 ? $0.uppercased() : $0.lowercased() }.joined()
    }

    // MARK: - MBTI

    /// Extraversion against introversion: where energy comes from.
    static func extraversion(_ a: PersonalityAnswers) -> Double {
        a.score([.talkativeness: 1.0, .socialPlans: 1.0, .aloneTime: -0.8, .nightlife: 0.8, .hostingGuests: 0.6,
                 .celebrations: 0.4, .humor: 0.4, .emotionalExpression: 0.4, .partnerSocializing: 0.3,
                 .pride: 0.3, .publicAffection: 0.2, .texting: 0.2])
    }

    /// Intuition against sensing: possibilities and meaning over the concrete.
    static func intuition(_ a: PersonalityAnswers) -> Double {
        a.score([.newExperiences: 1.0, .spirituality: 0.7, .rules: 0.6, .currentAffairs: 0.4, .headOrHeart: 0.2,
                 .personalStyle: -0.2, .exercise: -0.2, .travelStyle: -0.2])
    }

    /// Feeling against thinking: harmony and values over logic and directness.
    static func feeling(_ a: PersonalityAnswers) -> Double {
        a.score([.headOrHeart: 1.0, .listeningAndSolutions: 0.9, .communicationStyle: -0.8, .debating: -0.7,
                 .romanticGestures: 0.5, .emotionalExpression: 0.4, .competitiveness: -0.4, .makingUp: 0.3,
                 .physicalAffection: 0.2, .workAmbition: -0.2])
    }

    /// Judging against perceiving: structure and plans over keeping options open.
    static func judging(_ a: PersonalityAnswers) -> Double {
        a.score([.weeklyPlanning: 1.0, .punctuality: 0.9, .perfectionism: 0.6, .homeTidiness: 0.6,
                 .spendingMoney: 0.6, .rules: -0.5, .decisionMaking: 0.3])
    }

    static func mbtiType(_ a: PersonalityAnswers) -> String {
        (extraversion(a) >= 0 ? "E" : "I") + (intuition(a) >= 0 ? "N" : "S")
            + (feeling(a) >= 0 ? "F" : "T") + (judging(a) >= 0 ? "J" : "P")
    }

    static func mbti(_ a: PersonalityAnswers) -> PersonalityResult {
        let dimensions = [
            PersonalityDimension(low: PersonalityPole(letter: "E", name: L10n("Extravert")),
                                 high: PersonalityPole(letter: "I", name: L10n("Introvert")),
                                 value: -extraversion(a)),
            PersonalityDimension(low: PersonalityPole(letter: "S", name: L10n("Sensing")),
                                 high: PersonalityPole(letter: "N", name: L10n("Intuitive")),
                                 value: intuition(a)),
            PersonalityDimension(low: PersonalityPole(letter: "T", name: L10n("Thinking")),
                                 high: PersonalityPole(letter: "F", name: L10n("Feeling")),
                                 value: feeling(a)),
            PersonalityDimension(low: PersonalityPole(letter: "J", name: L10n("Judging")),
                                 high: PersonalityPole(letter: "P", name: L10n("Perceiving")),
                                 value: -judging(a)),
        ]
        let type = mbtiType(a)
        return PersonalityResult(
            test: .mbti, headline: type,
            name: dimensions.map(\.dominant.name).joined(separator: " · "),
            summary: mbtiSummary(type), chart: .spectrum(dimensions))
    }

    static func mbtiSummary(_ type: String) -> String {
        switch type {
        case "INTJ": L10n("Strategic and independent. You think in systems and long-term plans, and prefer depth over small talk.")
        case "INTP": L10n("Curious and analytical. You love ideas, take your time to think and keep your options open.")
        case "ENTJ": L10n("Decisive and driven. You take the lead, set clear goals and like to see things move.")
        case "ENTP": L10n("Quick and inventive. You enjoy a good debate, new possibilities and a bit of chaos.")
        case "INFJ": L10n("Thoughtful and idealistic. You read people well and look for meaning and depth in connection.")
        case "INFP": L10n("Warm and imaginative. You follow your values, feel deeply and need room to be yourself.")
        case "ENFJ": L10n("Warm and inspiring. You bring people together and care a lot about the people around you.")
        case "ENFP": L10n("Enthusiastic and open. You see possibilities everywhere and connect easily with others.")
        case "ISTJ": L10n("Reliable and structured. You keep your word, value order and like things done properly.")
        case "ISFJ": L10n("Caring and loyal. You quietly look after others and value stability and familiar routines.")
        case "ESTJ": L10n("Practical and organised. You like clear agreements, structure and getting things done.")
        case "ESFJ": L10n("Sociable and helpful. You create harmony, remember the details and like being there for others.")
        case "ISTP": L10n("Calm and practical. You solve problems hands-on and like the freedom to do things your own way.")
        case "ISFP": L10n("Gentle and spontaneous. You live in the moment, have an eye for beauty and follow your feelings.")
        case "ESTP": L10n("Energetic and bold. You love action, act quickly and like being where things happen.")
        default: L10n("Lively and spontaneous. You enjoy people, fun and the moment, and bring energy wherever you go.")
        }
    }

    // MARK: - 16Personalities

    /// Assertive against turbulent: calm self-assurance against self-critical drive.
    static func assertiveness(_ a: PersonalityAnswers) -> Double {
        a.score([.setbacks: -0.9, .optimism: 0.8, .othersOpinion: -0.7, .boundaries: 0.5,
                 .takingInitiative: 0.4, .stressContact: -0.3, .decisionMaking: -0.2, .texting: -0.2])
    }

    static func sixteenPersonalities(_ a: PersonalityAnswers) -> PersonalityResult {
        let assertive = assertiveness(a)
        let dimensions = [
            PersonalityDimension(low: PersonalityPole(letter: "E", name: L10n("Extraverted")),
                                 high: PersonalityPole(letter: "I", name: L10n("Introverted")),
                                 value: -extraversion(a)),
            PersonalityDimension(low: PersonalityPole(letter: "N", name: L10n("Intuitive")),
                                 high: PersonalityPole(letter: "S", name: L10n("Observant")),
                                 value: -intuition(a)),
            PersonalityDimension(low: PersonalityPole(letter: "T", name: L10n("Thinking")),
                                 high: PersonalityPole(letter: "F", name: L10n("Feeling")),
                                 value: feeling(a)),
            PersonalityDimension(low: PersonalityPole(letter: "J", name: L10n("Judging")),
                                 high: PersonalityPole(letter: "P", name: L10n("Prospecting")),
                                 value: -judging(a)),
            PersonalityDimension(low: PersonalityPole(letter: "A", name: L10n("Assertive")),
                                 high: PersonalityPole(letter: "T", name: L10n("Turbulent")),
                                 value: -assertive),
        ]
        let type = mbtiType(a)
        let identity = assertive >= 0 ? "A" : "T"
        let n = type.contains("N"), f = type.contains("F"), j = type.hasSuffix("J")
        let role = n ? (f ? L10n("Diplomat") : L10n("Analyst")) : (j ? L10n("Sentinel") : L10n("Explorer"))
        let identityLine = assertive >= 0
            ? L10n("You are self-assured and stay calm under stress.")
            : L10n("You are self-critical and driven to keep improving.")
        return PersonalityResult(
            test: .sixteenPersonalities, headline: "\(type)-\(identity)",
            name: "\(sixteenPersonalitiesName(type)) · \(role)",
            summary: mbtiSummary(type) + " " + identityLine, chart: .spectrum(dimensions))
    }

    static func sixteenPersonalitiesName(_ type: String) -> String {
        switch type {
        case "INTJ": L10n("Architect")
        case "INTP": L10n("Logician")
        case "ENTJ": L10n("Commander")
        case "ENTP": L10n("Debater")
        case "INFJ": L10n("Advocate")
        case "INFP": L10n("Mediator")
        case "ENFJ": L10n("Protagonist")
        case "ENFP": L10n("Campaigner")
        case "ISTJ": L10n("Logistician")
        case "ISFJ": L10n("Defender")
        case "ESTJ": L10n("Executive")
        case "ESFJ": L10n("Consul")
        case "ISTP": L10n("Virtuoso")
        case "ISFP": L10n("Adventurer")
        case "ESTP": L10n("Entrepreneur")
        default: L10n("Entertainer")
        }
    }

    // MARK: - DISC

    /// DISC's vertical axis: outgoing, assertive and fast-paced against
    /// reserved and deliberate.
    static func discPace(_ a: PersonalityAnswers) -> Double {
        a.score([.takingInitiative: 0.8, .talkativeness: 0.8, .decisionMaking: -0.6, .competitiveness: 0.6,
                 .patience: 0.5, .debating: 0.5, .communicationStyle: 0.4, .newExperiences: 0.3,
                 .socialPlans: 0.3])
    }

    /// DISC's horizontal axis: people-oriented against task-oriented.
    static func discPeople(_ a: PersonalityAnswers) -> Double {
        a.score([.listeningAndSolutions: 0.8, .headOrHeart: 0.6, .workAmbition: -0.5, .emotionalExpression: 0.4,
                 .competitiveness: -0.4, .perfectionism: -0.4, .communicationStyle: -0.3, .familyRole: 0.3,
                 .punctuality: -0.2, .homeTidiness: -0.2])
    }

    static func disc(_ a: PersonalityAnswers) -> PersonalityResult {
        let up = discPace(a), right = discPeople(a)
        let names = [L10n("Dominance"), L10n("Influence"), L10n("Steadiness"), L10n("Conscientiousness")]
        let letters = ["D", "I", "S", "C"]
        let summaries = [
            L10n("Direct and results-driven. You decide quickly, like a challenge and take charge when things need to move."),
            L10n("Enthusiastic and persuasive. You energise people, like to talk things through and bring optimism."),
            L10n("Calm and dependable. You are patient and supportive, and value harmony and a steady pace."),
            L10n("Precise and thoughtful. You value quality and accuracy, and like doing things well considered."),
        ]
        let share = quarterShares(up: up, right: right)
        let order = ranked(share)
        let first = order[0], second = order[1]
        let blended = share[second] >= share[first] * 0.85
        let headline = letters[first] + (blended ? letters[second].lowercased() : "")
        let (x, y) = wheelPoint(up: up, right: right)
        let peak = share.max() ?? 1
        let quarters = share.indices.map {
            PersonalityTrait(name: names[$0], short: letters[$0], value: share[$0] / peak)
        }
        return PersonalityResult(
            test: .disc, headline: headline,
            name: blended ? "\(names[first]) · \(names[second])" : names[first],
            summary: summaries[first], chart: .wheel(quarters, x: x, y: y))
    }

    // MARK: - Insights Discovery

    static func insights(_ a: PersonalityAnswers) -> PersonalityResult {
        let e = extraversion(a), f = feeling(a)
        let names = [L10n("Fiery Red"), L10n("Sunshine Yellow"), L10n("Earth Green"), L10n("Cool Blue")]
        let short = [L10n("Red"), L10n("Yellow"), L10n("Green"), L10n("Blue")]
        let summaries = [
            L10n("Action-oriented and determined. You are direct and competitive, and want results."),
            L10n("Sociable and dynamic. You are enthusiastic and expressive, and love working with people."),
            L10n("Caring and patient. You are loyal and encouraging, and value relationships and values."),
            L10n("Analytical and precise. You are cautious, think things through and want to understand first."),
        ]
        let share = quarterShares(up: e, right: f)
        let order = ranked(share)
        let (x, y) = wheelPoint(up: e, right: f)
        let peak = share.max() ?? 1
        let quarters = share.indices.map {
            PersonalityTrait(name: names[$0], short: short[$0], value: share[$0] / peak)
        }
        return PersonalityResult(
            test: .insights, headline: names[order[0]],
            name: L10n("Second colour: \(names[order[1]])"),
            summary: summaries[order[0]], chart: .wheel(quarters, x: x, y: y))
    }

    // MARK: - Big Five and HEXACO

    static func openness(_ a: PersonalityAnswers) -> Double {
        a.score([.newExperiences: 1.0, .rules: 0.6, .currentAffairs: 0.5, .spirituality: 0.4, .headOrHeart: 0.2,
                 .travelStyle: -0.3])
    }

    static func conscientiousness(_ a: PersonalityAnswers) -> Double {
        a.score([.punctuality: 1.0, .weeklyPlanning: 0.8, .perfectionism: 0.8, .homeTidiness: 0.7,
                 .spendingMoney: 0.6, .decisionMaking: 0.4, .workAmbition: 0.4, .rules: -0.4, .screenTime: -0.4,
                 .foodChoices: 0.3, .exercise: 0.3])
    }

    static func agreeableness(_ a: PersonalityAnswers) -> Double {
        a.score([.debating: -0.7, .listeningAndSolutions: 0.6, .communicationStyle: -0.6, .patience: -0.5,
                 .makingUp: 0.5, .competitiveness: -0.5, .boundaries: -0.3, .pride: -0.2, .familyRole: 0.2,
                 .hostingGuests: 0.2])
    }

    /// Setbacks, optimism and caring what others think measure it directly;
    /// the need for reassurance in relationships adds to it.
    static func neuroticism(_ a: PersonalityAnswers) -> Double {
        a.score([.setbacks: 1.0, .optimism: -0.8, .othersOpinion: 0.6, .stressContact: 0.3, .texting: 0.3,
                 .relationshipPrivacy: 0.2, .patience: 0.2, .boundaries: -0.2])
    }

    struct TraitText {
        let name: String
        let letter: String
        let high: String
        let low: String
    }

    static var opennessText: TraitText {
        TraitText(name: L10n("Openness"), letter: "O",
                  high: L10n("You are curious and open to new ideas, experiences and depth."),
                  low: L10n("You like the familiar and prefer practical, proven ways."))
    }

    static var conscientiousnessText: TraitText {
        TraitText(name: L10n("Conscientiousness"), letter: "C",
                  high: L10n("You are organised and reliable, and like to plan ahead."),
                  low: L10n("You are flexible and spontaneous, and don’t need everything planned."))
    }

    static var extraversionText: TraitText {
        TraitText(name: L10n("Extraversion"), letter: "E",
                  high: L10n("You get energy from people and like being social and active."),
                  low: L10n("You recharge on your own and prefer calm and small circles."))
    }

    static var agreeablenessText: TraitText {
        TraitText(name: L10n("Agreeableness"), letter: "A",
                  high: L10n("You are warm and cooperative, and seek harmony with others."),
                  low: L10n("You are direct and critical, and don’t shy away from a debate."))
    }

    /// Strongest and weakest trait, spelled out.
    static func traitResult(_ test: PersonalityTest, texts: [TraitText], values: [Double]) -> PersonalityResult {
        let order = ranked(values)
        let strongest = order[0], lowest = order[order.count - 1]
        return PersonalityResult(
            test: test, headline: code(texts.map(\.letter), values),
            name: L10n("Strongest: \(texts[strongest].name) · Lowest: \(texts[lowest].name)"),
            summary: texts[strongest].high + " " + texts[lowest].low,
            chart: .radar(zip(texts, values).map { PersonalityTrait(name: $0.name, short: $0.letter, value: $1) }))
    }

    static func bigFive(_ a: PersonalityAnswers) -> PersonalityResult {
        let texts = [
            opennessText, conscientiousnessText, extraversionText, agreeablenessText,
            TraitText(name: L10n("Neuroticism"), letter: "N",
                      high: L10n("You feel things intensely and look for reassurance and closeness under stress."),
                      low: L10n("You stay calm under pressure and are emotionally steady.")),
        ]
        let values = [openness(a), conscientiousness(a), extraversion(a), agreeableness(a), neuroticism(a)]
            .map(absolute)
        return traitResult(.bigFive, texts: texts, values: values)
    }

    static func hexaco(_ a: PersonalityAnswers) -> PersonalityResult {
        let texts = [
            TraitText(name: L10n("Honesty-Humility"), letter: "H",
                      high: L10n("You are modest and sincere, and status or luxury matter little to you."),
                      low: L10n("You enjoy status, style and the good things in life.")),
            TraitText(name: L10n("Emotionality"), letter: "E",
                      high: L10n("You are sensitive and empathetic, and like support when things get tough."),
                      low: L10n("You are independent and stay level-headed when things get tough.")),
            TraitText(name: L10n("Extraversion"), letter: "X", high: extraversionText.high, low: extraversionText.low),
            agreeablenessText, conscientiousnessText, opennessText,
        ]
        let honesty = a.score([.pride: -0.8, .personalStyle: -0.6, .travelStyle: -0.6, .othersOpinion: -0.5,
                               .rules: -0.4, .celebrations: -0.3, .workAmbition: -0.3, .relationshipPrivacy: 0.2])
        let emotionality = a.score([.stressContact: 0.6, .setbacks: 0.6, .emotionalExpression: 0.4,
                                    .familyRole: 0.4, .othersOpinion: 0.3, .physicalAffection: 0.3,
                                    .texting: 0.3, .optimism: -0.3, .newExperiences: -0.3])
        let patience = a.score([.patience: -0.8, .debating: -0.7, .communicationStyle: -0.5, .makingUp: 0.5,
                                .competitiveness: -0.4, .setbacks: -0.3, .listeningAndSolutions: 0.3])
        let values = [honesty, emotionality, extraversion(a), patience, conscientiousness(a), openness(a)]
            .map(absolute)
        return traitResult(.hexaco, texts: texts, values: values)
    }

    // MARK: - Enneagram

    static func enneagram(_ a: PersonalityAnswers) -> PersonalityResult {
        let scores = [
            a.score([.perfectionism: 1.0, .homeTidiness: 0.8, .punctuality: 0.8, .rules: -0.6,
                     .weeklyPlanning: 0.5, .communicationStyle: 0.4, .foodChoices: 0.3, .spendingMoney: 0.3]),
            a.score([.listeningAndSolutions: 0.8, .boundaries: -0.7, .romanticGestures: 0.5, .familyRole: 0.5,
                     .hostingGuests: 0.5, .aloneTime: -0.4, .cooking: 0.3, .physicalAffection: 0.3,
                     .makingUp: 0.3]),
            a.score([.workAmbition: 1.0, .pride: 0.7, .personalStyle: 0.6, .competitiveness: 0.6,
                     .othersOpinion: 0.5, .takingInitiative: 0.4, .exercise: 0.3]),
            a.score([.headOrHeart: 0.7, .emotionalExpression: 0.6, .setbacks: 0.6, .spirituality: 0.5,
                     .romanticGestures: 0.4, .aloneTime: 0.4, .rules: 0.3, .personalStyle: 0.3]),
            a.score([.aloneTime: 0.9, .headOrHeart: -0.6, .currentAffairs: 0.6, .decisionMaking: 0.6,
                     .talkativeness: -0.6, .socialPlans: -0.6, .emotionalExpression: -0.3]),
            a.score([.optimism: -0.7, .newExperiences: -0.6, .spendingMoney: 0.6, .rules: -0.5,
                     .familyRole: 0.5, .stressContact: 0.5, .punctuality: 0.3]),
            a.score([.newExperiences: 1.0, .optimism: 0.7, .nightlife: 0.7, .weeklyPlanning: -0.6,
                     .socialPlans: 0.5, .humor: 0.4, .patience: 0.4, .decisionMaking: -0.3]),
            a.score([.takingInitiative: 1.0, .communicationStyle: 0.8, .debating: 0.7, .boundaries: 0.6,
                     .competitiveness: 0.6, .workAmbition: 0.4, .emotionalExpression: -0.2]),
            a.score([.debating: -0.9, .communicationStyle: -0.6, .makingUp: 0.5, .competitiveness: -0.5,
                     .boundaries: -0.5, .listeningAndSolutions: 0.4, .takingInitiative: -0.4, .patience: -0.3]),
        ]
        let names = [
            L10n("Reformer"), L10n("Helper"), L10n("Achiever"), L10n("Individualist"), L10n("Investigator"),
            L10n("Loyalist"), L10n("Enthusiast"), L10n("Challenger"), L10n("Peacemaker"),
        ]
        let summaries = [
            L10n("Principled and conscientious. You want to do things right and make things better, and fear being wrong or careless."),
            L10n("Caring and generous. You want to be loved and needed, and fear being unwanted."),
            L10n("Ambitious and adaptable. You want to succeed and be valued, and fear being worthless."),
            L10n("Expressive and sensitive. You want to be authentic and understood, and fear having no identity of your own."),
            L10n("Perceptive and independent. You want to understand the world, and fear being overwhelmed or incapable."),
            L10n("Loyal and responsible. You want security and support, and fear being left without guidance."),
            L10n("Spontaneous and versatile. You want freedom and new experiences, and fear missing out or being limited."),
            L10n("Strong and decisive. You want to be in control of your own life, and fear being controlled or hurt."),
            L10n("Easygoing and supportive. You want inner peace and harmony, and fear conflict and disconnection."),
        ]
        let type = (ranked(scores).first ?? 8) + 1
        let left = type == 1 ? 9 : type - 1, right = type == 9 ? 1 : type + 1
        let wing = scores[left - 1] >= scores[right - 1] ? left : right
        let values = relative(scores)
        return PersonalityResult(
            test: .enneagram, headline: "\(type)w\(wing)",
            name: "\(names[type - 1]) · " + L10n("wing \(wing)"),
            summary: summaries[type - 1],
            chart: .enneagram(values.indices.map { PersonalityTrait(name: names[$0], short: "\($0 + 1)", value: values[$0]) },
                              type: type, wing: wing))
    }

    // MARK: - Belbin

    static func belbin(_ a: PersonalityAnswers) -> PersonalityResult {
        let scores = [
            a.score([.newExperiences: 0.8, .rules: 0.6, .weeklyPlanning: -0.5, .spirituality: 0.4,
                     .aloneTime: 0.4, .punctuality: -0.3, .talkativeness: -0.2]),
            a.score([.talkativeness: 0.8, .socialPlans: 0.8, .newExperiences: 0.5, .optimism: 0.5, .humor: 0.4,
                     .nightlife: 0.3, .weeklyPlanning: -0.3]),
            a.score([.takingInitiative: 0.5, .listeningAndSolutions: 0.5, .makingUp: 0.4, .setbacks: -0.4,
                     .debating: -0.4, .decisionMaking: 0.3, .patience: -0.3]),
            a.score([.takingInitiative: 0.9, .communicationStyle: 0.8, .debating: 0.8, .workAmbition: 0.6,
                     .competitiveness: 0.6, .patience: 0.4, .listeningAndSolutions: -0.4]),
            a.score([.decisionMaking: 1.0, .headOrHeart: -0.7, .currentAffairs: 0.5, .spirituality: -0.4,
                     .romanticGestures: -0.3, .talkativeness: -0.3, .emotionalExpression: -0.3]),
            a.score([.debating: -0.9, .listeningAndSolutions: 0.8, .communicationStyle: -0.6, .makingUp: 0.4,
                     .patience: -0.4, .boundaries: -0.3, .familyRole: 0.3, .takingInitiative: -0.3]),
            a.score([.weeklyPlanning: 0.9, .punctuality: 0.8, .spendingMoney: 0.6, .newExperiences: -0.5,
                     .rules: -0.4, .homeTidiness: 0.3, .spirituality: -0.3]),
            a.score([.perfectionism: 1.0, .homeTidiness: 0.8, .punctuality: 0.7, .decisionMaking: 0.6,
                     .foodChoices: 0.3, .personalStyle: 0.3]),
            a.score([.workAmbition: 0.7, .aloneTime: 0.6, .perfectionism: 0.5, .socialPlans: -0.5,
                     .currentAffairs: 0.4]),
        ]
        let names = [
            L10n("Plant"), L10n("Resource Investigator"), L10n("Co-ordinator"), L10n("Shaper"),
            L10n("Monitor Evaluator"), L10n("Teamworker"), L10n("Implementer"), L10n("Completer Finisher"),
            L10n("Specialist"),
        ]
        let short = ["PL", "RI", "CO", "SH", "ME", "TW", "IMP", "CF", "SP"]
        let summaries = [
            L10n("Creative and imaginative. You come up with original ideas and solve difficult problems in your own way."),
            L10n("Outgoing and enthusiastic. You explore opportunities, build contacts and bring in new ideas from outside."),
            L10n("Calm and confident. You clarify goals, bring out the best in others and keep the group together."),
            L10n("Challenging and dynamic. You keep the pace up and have the drive to overcome obstacles."),
            L10n("Sober and strategic. You weigh up all the options and judge them carefully."),
            L10n("Cooperative and diplomatic. You listen, build bridges and keep the atmosphere in the team good."),
            L10n("Practical and reliable. You turn ideas into concrete actions and get them done efficiently."),
            L10n("Precise and conscientious. You spot the mistakes others miss and finish things properly."),
            L10n("Dedicated and knowledgeable. You bring deep expertise and like to master your subject."),
        ]
        let order = ranked(scores)
        let values = relative(scores)
        return PersonalityResult(
            test: .belbin, headline: names[order[0]],
            name: L10n("Also: \(names[order[1]]), \(names[order[2]])"),
            summary: summaries[order[0]],
            chart: .radar(values.indices.map { PersonalityTrait(name: names[$0], short: short[$0], value: values[$0]) }))
    }

    // MARK: - Predictive Index

    static func predictiveIndex(_ a: PersonalityAnswers) -> PersonalityResult {
        let factors = [
            a.score([.takingInitiative: 1.0, .communicationStyle: 0.7, .debating: 0.6, .workAmbition: 0.5,
                     .boundaries: 0.4, .listeningAndSolutions: -0.3, .decisionMaking: -0.3]),
            extraversion(a),
            a.score([.patience: -0.7, .decisionMaking: 0.6, .newExperiences: -0.6, .familyRole: 0.3]),
            a.score([.punctuality: 1.0, .perfectionism: 0.7, .weeklyPlanning: 0.7, .homeTidiness: 0.6,
                     .spendingMoney: 0.4, .decisionMaking: 0.4, .rules: -0.4, .personalStyle: 0.3]),
        ]
        let dimensions = [
            PersonalityDimension(low: PersonalityPole(letter: "A", name: L10n("Collaborative")),
                                 high: PersonalityPole(letter: "A", name: L10n("Independent")), value: factors[0]),
            PersonalityDimension(low: PersonalityPole(letter: "B", name: L10n("Reserved")),
                                 high: PersonalityPole(letter: "B", name: L10n("Social")), value: factors[1]),
            PersonalityDimension(low: PersonalityPole(letter: "C", name: L10n("Fast-paced")),
                                 high: PersonalityPole(letter: "C", name: L10n("Steady")), value: factors[2]),
            PersonalityDimension(low: PersonalityPole(letter: "D", name: L10n("Informal")),
                                 high: PersonalityPole(letter: "D", name: L10n("Precise")), value: factors[3]),
        ]
        let profile = PredictiveIndexProfile.closest(to: factors)
        return PersonalityResult(
            test: .predictiveIndex, headline: profile.rawValue,
            name: dimensions.map(\.dominant.name).joined(separator: " · "),
            summary: profile.summary, chart: .spectrum(dimensions))
    }

    // MARK: - TMA

    static func tma(_ a: PersonalityAnswers) -> PersonalityResult {
        let scores = [
            a.score([.workAmbition: 1.0, .competitiveness: 0.6, .takingInitiative: 0.4, .perfectionism: 0.3,
                     .exercise: 0.3]),
            a.score([.personalStyle: 1.0, .pride: 0.7, .travelStyle: 0.6, .othersOpinion: 0.5,
                     .celebrations: 0.4]),
            a.score([.takingInitiative: 1.0, .communicationStyle: 0.6, .debating: 0.5, .boundaries: 0.4,
                     .workAmbition: 0.3]),
            a.score([.socialPlans: 1.0, .talkativeness: 0.8, .hostingGuests: 0.6, .aloneTime: -0.6,
                     .nightlife: 0.5]),
            a.score([.listeningAndSolutions: 0.9, .familyRole: 0.6, .boundaries: -0.4, .cooking: 0.3,
                     .hostingGuests: 0.3, .makingUp: 0.3, .workAmbition: -0.2]),
            a.score([.weeklyPlanning: 1.0, .punctuality: 0.8, .homeTidiness: 0.7, .rules: -0.6,
                     .spendingMoney: 0.5]),
            a.score([.newExperiences: 1.0, .rules: 0.5, .weeklyPlanning: -0.5, .travelStyle: -0.3,
                     .nightlife: 0.3]),
            a.score([.aloneTime: 0.8, .relationshipPrivacy: -0.7, .boundaries: 0.5, .partnerSocializing: -0.4,
                     .takingInitiative: 0.2]),
        ]
        let names = [
            L10n("Achievement"), L10n("Status"), L10n("Leadership"), L10n("Social contact"),
            L10n("Helping others"), L10n("Structure"), L10n("Change"), L10n("Autonomy"),
        ]
        let lines = [
            L10n("You are motivated by goals, growth and doing well."),
            L10n("Recognition and appearance matter to you; you like to be seen."),
            L10n("You like to take the lead and influence decisions."),
            L10n("You get energy from being around people and sharing things."),
            L10n("You are driven to support others and make a difference for them."),
            L10n("You like clarity and order, and knowing where you stand."),
            L10n("You look for variety, new experiences and change."),
            L10n("You want the freedom to make your own choices and work your own way."),
        ]
        let order = ranked(scores)
        let values = relative(scores)
        return PersonalityResult(
            test: .tma, headline: names[order[0]],
            name: L10n("Also: \(names[order[1]]), \(names[order[2]])"),
            summary: lines[order[0]] + " " + lines[order[1]],
            chart: .radar(values.indices.map { PersonalityTrait(name: names[$0], short: names[$0], value: values[$0]) }))
    }
}

/// The Predictive Index's reference profiles, each a typical pattern of the
/// four factors (dominance, extraversion, patience, formality).
enum PredictiveIndexProfile: String, CaseIterable {
    case analyzer = "Analyzer", strategist = "Strategist", controller = "Controller", venturer = "Venturer"
    case captain = "Captain", maverick = "Maverick", persuader = "Persuader", promoter = "Promoter"
    case individualist = "Individualist", altruist = "Altruist", collaborator = "Collaborator"
    case `operator` = "Operator", specialist = "Specialist", craftsman = "Craftsman", guardian = "Guardian"
    case scholar = "Scholar", adapter = "Adapter"

    var pattern: [Double] {
        switch self {
        case .analyzer: [0.7, -0.8, -0.3, 0.7]
        case .strategist: [0.8, 0.1, -0.6, 0.8]
        case .controller: [0.6, -0.6, 0.0, 1.0]
        case .venturer: [1.0, -0.3, -0.7, -0.7]
        case .captain: [1.0, 0.3, -0.8, -0.3]
        case .maverick: [0.8, 0.6, -0.6, -1.0]
        case .persuader: [0.6, 1.0, -0.6, -0.2]
        case .promoter: [-0.2, 1.0, -0.6, -0.8]
        case .individualist: [0.7, -1.0, 0.0, -0.6]
        case .altruist: [-0.5, 0.9, 0.3, 0.6]
        case .collaborator: [-0.8, 0.7, 0.7, 0.0]
        case .`operator`: [-0.8, -0.3, 1.0, 0.1]
        case .specialist: [-0.3, -0.5, 0.8, 0.9]
        case .craftsman: [-0.6, -0.9, 0.8, 0.5]
        case .guardian: [-0.8, -0.5, 0.3, 1.0]
        case .scholar: [0.3, -0.8, 0.5, 1.0]
        case .adapter: [0, 0, 0, 0]
        }
    }

    /// The profile whose pattern points the same way as the factors; a
    /// profile without strong factors adapts.
    static func closest(to factors: [Double]) -> Self {
        guard factors.map(abs).max() ?? 0 >= 0.15 else { return .adapter }
        return allCases.filter { $0 != .adapter }.max { lhs, rhs in
            similarity(lhs.pattern, factors) < similarity(rhs.pattern, factors)
        } ?? .adapter
    }

    private static func similarity(_ pattern: [Double], _ factors: [Double]) -> Double {
        let dot = zip(pattern, factors).map(*).reduce(0, +)
        let length = sqrt(pattern.map { $0 * $0 }.reduce(0, +))
        return dot / max(length, 1e-6)
    }

    var summary: String {
        switch self {
        case .analyzer: L10n("Analytical and disciplined. You work precisely and independently and want to get the facts right.")
        case .strategist: L10n("Analytical and assertive. You think ahead, solve problems and like to steer by the facts.")
        case .controller: L10n("Precise and in control. You set high standards and keep a firm grip on the details.")
        case .venturer: L10n("Independent and bold. You take risks, move fast and like to work your own way.")
        case .captain: L10n("Driven and decisive. You take charge, move fast and like to set the direction.")
        case .maverick: L10n("Innovative and daring. You look past the rules for new ways and bring others along.")
        case .persuader: L10n("Persuasive and energetic. You enjoy convincing people and taking on new challenges.")
        case .promoter: L10n("Sociable and informal. You build relationships easily and like variety and people.")
        case .individualist: L10n("Independent and self-assured. You follow your own judgement and like freedom.")
        case .altruist: L10n("Friendly and considerate. You like helping others and doing things properly.")
        case .collaborator: L10n("Warm and cooperative. You enjoy working with others and building a good team.")
        case .`operator`: L10n("Patient and steady. You work calmly and consistently and like a stable environment.")
        case .specialist: L10n("Steady and precise. You build deep expertise and take care to get things right.")
        case .craftsman: L10n("Patient and thorough. You work carefully and steadily and take pride in quality.")
        case .guardian: L10n("Careful and conscientious. You follow the rules and make sure everything is correct.")
        case .scholar: L10n("Thoughtful and analytical. You like to dig deep and become an expert in your field.")
        case .adapter: L10n("Flexible and versatile. You adapt easily to what a situation asks of you.")
        }
    }
}
