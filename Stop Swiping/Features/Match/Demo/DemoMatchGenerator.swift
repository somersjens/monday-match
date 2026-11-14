import CoreLocation
import Foundation

/// Invents another person for the demo, before the app has real users. A
/// match meets every requirement both ways and scores high; no match breaks
/// a few requirements on each side.
enum DemoMatchGenerator {
    static func makeMatch<R: RandomNumberGenerator>(
        for you: ProfileCreationState,
        shouldMatch: Bool,
        now: Date = Date(),
        calendar: Calendar = BirthDateRules.calendar,
        using rng: inout R
    ) -> MatchSnapshot {
        let today = CalendarDate.today(calendar: calendar, now: now)
        var them = compatibleProfile(for: you, today: today, now: now, calendar: calendar,
                                     spread: shouldMatch ? [0, 0, 0, 1, -1] : [-2, -1, -1, 0, 1, 1, 2], rng: &rng)
        if !shouldMatch {
            breakRequirements(of: &them, you: you, today: today, now: now, calendar: calendar, rng: &rng)
        }
        return MatchSnapshot(matchedAt: now, you: you, them: them)
    }

    /// The average the explanation's match ends on.
    static let exampleAverage = 80

    /// The match the explanation ends on: someone called Example who meets
    /// every requirement both ways. Their answers start out exactly as you
    /// hoped and are nudged apart, one step at a time, until both scores
    /// average `average`. The scores stay real, so the answers behind them
    /// can still be opened.
    static func makeExample<R: RandomNumberGenerator>(
        for you: ProfileCreationState,
        average: Int = exampleAverage,
        now: Date = Date(),
        calendar: Calendar = BirthDateRules.calendar,
        using rng: inout R
    ) -> MatchSnapshot {
        let today = CalendarDate.today(calendar: calendar, now: now)
        var best: (them: ProfileCreationState, miss: Int)?
        for _ in 0..<12 {
            var them = compatibleProfile(for: you, today: today, now: now, calendar: calendar, spread: [0], rng: &rng)
            them.displayName = L10n("Example")
            // Your score lands a little to one side; theirs makes up the difference.
            var yours = MatchReport.rows(seeker: you, candidate: them)
            let yourScore = tune(&yours, to: average + Int.random(in: -4...4, using: &rng), rng: &rng) { row, step in
                MatchReport.Row(step: row.step, value: row.value + step, wanted: row.wanted, importance: row.importance)
            }
            var theirs = MatchReport.rows(seeker: them, candidate: you)
            tune(&theirs, to: 2 * average - yourScore, rng: &rng) { row, step in
                MatchReport.Row(step: row.step, value: row.value, wanted: row.wanted + step, importance: row.importance)
            }
            for row in yours {
                guard let question = row.step.compatibilityQuestion else { continue }
                them.lifestyle[question].own = row.value
            }
            for row in theirs {
                guard let question = row.step.compatibilityQuestion else { continue }
                them.lifestyle[question].partner = row.wanted
            }
            let miss = abs(MatchReport(you: you, them: them, on: today).average - average)
            if miss < best?.miss ?? .max { best = (them, miss) }
            if miss == 0 { break }
        }
        return MatchSnapshot(matchedAt: now, you: you, them: best!.them)
    }

    /// Moves random 1–5 answers a step at a time while that brings the
    /// rows' score closer to `target` without passing it, then takes the
    /// single step that lands closest. Returns the score it reached.
    @discardableResult
    private static func tune<R: RandomNumberGenerator>(
        _ rows: inout [MatchReport.Row],
        to target: Int,
        rng: inout R,
        step: (MatchReport.Row, Int) -> MatchReport.Row
    ) -> Int {
        /// The score before rounding: one step often moves it by less than a point.
        func exact(_ rows: [MatchReport.Row]) -> Double {
            let weight = rows.reduce(0) { $0 + $1.weight }
            return weight > 0 ? rows.reduce(0) { $0 + $1.weight * $1.closeness } / weight * 100 : 100
        }
        func stepped(_ index: Int, by amount: Int) -> [MatchReport.Row]? {
            let row = step(rows[index], amount)
            guard CompatibilityScaleAnswer.range.contains(row.value),
                  CompatibilityScaleAnswer.range.contains(row.wanted) else { return nil }
            var changed = rows
            changed[index] = row
            return changed
        }
        // Alcohol, smoking and drugs stay as they are; only 1–5 answers move.
        let questions = rows.indices.filter { rows[$0].step.compatibilityQuestion != nil && rows[$0].weight > 0 }
        var current = MatchReport.score(rows)
        for _ in 0..<600 where current != target {
            guard let index = questions.randomElement(using: &rng),
                  let changed = stepped(index, by: Bool.random(using: &rng) ? 1 : -1) else { continue }
            let result = MatchReport.score(changed)
            let closer = current > target ? exact(changed) < exact(rows) && result >= target
                                          : exact(changed) > exact(rows) && result <= target
            if closer {
                rows = changed
                current = result
            }
        }
        guard current != target else { return current }
        var closest: (rows: [MatchReport.Row], score: Int)?
        for index in questions {
            for amount in [-1, 1] {
                guard let changed = stepped(index, by: amount) else { continue }
                let result = MatchReport.score(changed)
                if abs(result - target) < abs((closest?.score ?? current) - target) { closest = (changed, result) }
            }
        }
        if let closest {
            rows = closest.rows
            current = closest.score
        }
        return current
    }

    private static let names: [GenderIdentity: [String]] = [
        .woman: ["Emma", "Sophie", "Julia", "Lotte", "Mila", "Noor", "Sara", "Eva", "Anna", "Lisa", "Fleur", "Iris"],
        .man: ["Daan", "Lucas", "Sem", "Milan", "Noah", "Thomas", "Jesse", "Ruben", "Bram", "Lars", "Finn", "Jasper"],
        .nonBinary: ["Robin", "Sam", "Kai", "Alex", "Charlie", "Jip", "Noa", "Quinn"]
    ]

    // MARK: - A profile that meets everything

    private static func compatibleProfile<R: RandomNumberGenerator>(
        for you: ProfileCreationState, today: CalendarDate, now: Date, calendar: Calendar,
        spread: [Int], rng: inout R
    ) -> ProfileCreationState {
        var them = ProfileCreationState(today: today, applicationLanguage: you.languages.first ?? "en")

        let open = GenderIdentity.onboardingOptions.filter { you.partnerGenders.contains($0) }
        let gender = open.randomElement(using: &rng) ?? .woman
        them.gender = gender
        them.displayName = names[gender]?.randomElement(using: &rng) ?? "Robin"
        them.partnerGenders = [you.gender ?? .man]
        if Bool.random(using: &rng), let other = GenderIdentity.onboardingOptions.randomElement(using: &rng) {
            them.partnerGenders.insert(other)
        }

        let yourAge = you.age(on: today) ?? 30
        let yourRange = you.partnerAgeRange ?? PartnerAgeRules.suggestedRange(forAge: yourAge)
        let lowest = max(yourRange.minimum, PartnerAgeRules.lowerBound)
        let age = Int.random(in: lowest...max(lowest, min(yourRange.maximum, 80)), using: &rng)
        them.dateOfBirth = birthday(age: age, now: now, calendar: calendar, rng: &rng)
        them.partnerAgeRange = PartnerAgeRange(
            minimum: max(PartnerAgeRules.lowerBound, min(age, yourAge) - Int.random(in: 1...5, using: &rng)),
            maximum: min(PartnerAgeRules.upperBound, max(age, yourAge) + Int.random(in: 1...6, using: &rng)),
            isCustomized: true
        )

        let heights = you.partnerHeightRange
        let shortest = max(heights.minimum, 152), tallest = min(heights.maximum, 198)
        them.heightCentimeters = shortest <= tallest ? Int.random(in: shortest...tallest, using: &rng) : heights.minimum
        them.hasAdjustedHeight = true
        them.partnerHeightRange = Bool.random(using: &rng) ? .any : PartnerHeightRules.clamped(
            minimum: min(you.heightCentimeters, 165) - Int.random(in: 0...15, using: &rng),
            maximum: max(you.heightCentimeters, 180) + Int.random(in: 0...15, using: &rng)
        )

        var religion = ReligionAnswers()
        religion.own = Religion.allCases.filter { you.religion.effectivePartnerReligions.contains($0) }
            .randomElement(using: &rng) ?? you.religion.matchingReligion
        them.religion = religion

        var languages = [you.languages.randomElement(using: &rng) ?? "en"]
        if !languages.contains("en"), Bool.random(using: &rng) { languages.append("en") }
        them.languages = languages

        if let location = you.location {
            let radius = [15, 25, 30, 40, 50].randomElement(using: &rng) ?? 25
            let limit = Double(min(you.searchRadiusKilometers, radius))
            them.searchRadiusKilometers = radius
            them.location = moved(location, kilometers: Double.random(in: 0.5...max(0.6, limit * 0.8), using: &rng), rng: &rng)
        }

        var lifestyle = them.lifestyle
        lifestyle.hasChildren = you.lifestyle.openToPartnerWithChildren == false ? false : Bool.random(using: &rng)
        lifestyle.openToPartnerWithChildren = you.lifestyle.hasChildren == true ? true : Bool.random(using: &rng)
        let wishes: [FutureChildrenWish] = switch you.lifestyle.futureChildren {
        case .yes: [.yes, .notSure]
        case .no: [.no, .notSure]
        default: FutureChildrenWish.allCases
        }
        lifestyle.futureChildren = wishes.randomElement(using: &rng)
        for substance in Substance.allCases {
            let top = substance.levels.count - 1
            let limit = you.lifestyle[substance].partnerMaximumLevel ?? top
            let yours = you.lifestyle[substance].ownLevel ?? 0
            lifestyle[substance] = SubstanceAnswer(
                ownLevel: Int.random(in: 0...min(limit, 3), using: &rng),
                partnerMaximumLevel: Int.random(in: min(yours, top)...top, using: &rng)
            )
        }
        for question in CompatibilityScaleQuestion.all {
            let yours = you.lifestyle[question]
            func near(_ value: Int?) -> Int {
                let range = CompatibilityScaleAnswer.range
                let shifted = (value ?? 3) + (spread.randomElement(using: &rng) ?? 0)
                return min(max(shifted, range.lowerBound), range.upperBound)
            }
            lifestyle[question] = CompatibilityScaleAnswer(
                own: near(yours.partner), partner: near(yours.own), isPartnerCustomized: true,
                importance: Int.random(in: CompatibilityScaleAnswer.range, using: &rng)
            )
        }
        them.lifestyle = lifestyle
        them.completedAt = now
        return them
    }

    // MARK: - Breaking requirements

    /// Breaks two of your requirements and one or two of theirs, always
    /// choosing from what your answers make possible.
    private static func breakRequirements<R: RandomNumberGenerator>(
        of them: inout ProfileCreationState, you: ProfileCreationState,
        today: CalendarDate, now: Date, calendar: Calendar, rng: inout R
    ) {
        typealias Change = (inout ProfileCreationState, inout R) -> Void
        var yours: [Change] = []
        var theirs: [Change] = []
        let yourAge = you.age(on: today) ?? 30

        if you.lifestyle.openToPartnerWithChildren == false {
            yours.append { them, _ in them.lifestyle.hasChildren = true }
        }
        for substance in Substance.allCases {
            let top = substance.levels.count - 1
            if let limit = you.lifestyle[substance].partnerMaximumLevel, limit < top {
                yours.append { them, rng in
                    them.lifestyle[substance].ownLevel = Int.random(in: (limit + 1)...top, using: &rng)
                }
            }
            if let level = you.lifestyle[substance].ownLevel, level > 0 {
                theirs.append { them, rng in
                    them.lifestyle[substance].partnerMaximumLevel = Int.random(in: 0..<level, using: &rng)
                }
            }
        }
        switch you.lifestyle.futureChildren {
        case .yes: yours.append { them, _ in them.lifestyle.futureChildren = .no }
        case .no: yours.append { them, _ in them.lifestyle.futureChildren = .yes }
        default: break
        }
        if let range = you.partnerAgeRange, range.maximum + 1 <= 80 {
            yours.append { them, rng in
                let age = Int.random(in: (range.maximum + 1)...min(range.maximum + 8, 85), using: &rng)
                them.dateOfBirth = birthday(age: age, now: now, calendar: calendar, rng: &rng)
                them.partnerAgeRange = PartnerAgeRange(minimum: max(18, min(age, yourAge) - 3),
                                                       maximum: min(99, max(age, yourAge) + 3), isCustomized: true)
            }
        }
        if let location = you.location {
            yours.append { them, rng in
                let far = Double(you.searchRadiusKilometers) + Double.random(in: 8...60, using: &rng)
                them.searchRadiusKilometers = max(them.searchRadiusKilometers, Int(far) + 10)
                them.location = moved(location, kilometers: far, rng: &rng)
            }
            theirs.append { them, rng in
                let radius = [10, 15, 25].randomElement(using: &rng) ?? 25
                let distance = min(Double(radius) + Double.random(in: 4...20, using: &rng),
                                   max(Double(radius) + 1, Double(you.searchRadiusKilometers) - 1))
                them.searchRadiusKilometers = radius
                them.location = moved(location, kilometers: distance, rng: &rng)
            }
        }
        if you.lifestyle.hasChildren == true {
            theirs.append { them, _ in them.lifestyle.openToPartnerWithChildren = false }
        }
        theirs.append { them, rng in
            let foreign = ["en", "de", "fr", "es", "it"].filter { !you.languages.contains($0) }
            them.languages = [foreign.randomElement(using: &rng) ?? "fr"]
        }
        theirs.append { them, rng in
            // A range that ends below your age, or starts above it.
            if yourAge > 24 {
                let top = yourAge - Int.random(in: 1...4, using: &rng)
                them.partnerAgeRange = PartnerAgeRange(minimum: max(18, top - 8), maximum: top, isCustomized: true)
            } else {
                let bottom = yourAge + Int.random(in: 2...5, using: &rng)
                them.partnerAgeRange = PartnerAgeRange(minimum: bottom, maximum: bottom + 8, isCustomized: true)
            }
        }

        // The demo always has something to show, even for an open profile.
        if yours.isEmpty { yours = Array(theirs.suffix(1)) }

        yours.shuffle(using: &rng)
        theirs.shuffle(using: &rng)
        for change in yours.prefix(2) { change(&them, &rng) }
        for change in theirs.prefix(Int.random(in: 1...2, using: &rng)) { change(&them, &rng) }
    }

    // MARK: - Helpers

    private static func birthday<R: RandomNumberGenerator>(age: Int, now: Date, calendar: Calendar, rng: inout R) -> CalendarDate {
        let anniversary = calendar.date(byAdding: .year, value: -age, to: now) ?? now
        let date = calendar.date(byAdding: .day, value: -Int.random(in: 1...300, using: &rng), to: anniversary) ?? anniversary
        return CalendarDate.today(calendar: calendar, now: date)
    }

    private static func moved<R: RandomNumberGenerator>(_ location: SelectedLocation, kilometers: Double, rng: inout R) -> SelectedLocation {
        let bearing = Double.random(in: 0..<(2 * .pi), using: &rng)
        let latitude = location.latitude + kilometers / 111.32 * cos(bearing)
        let longitude = location.longitude
            + kilometers / (111.32 * max(cos(location.latitude * .pi / 180), 0.05)) * sin(bearing)
        return SelectedLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), source: .map)
    }
}
