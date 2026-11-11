import Foundation

enum BirthDateField: CaseIterable {
    case day
    case month
    case year
}

enum BirthDateEvaluation: Equatable {
    /// The selection still equals today's date.
    case today
    case nonexistent(daysInMonth: Int)
    case future
    case minor(age: Int)
    case adult(age: Int)

    var age: Int? {
        switch self {
        case .minor(let age), .adult(let age): age
        default: nil
        }
    }
}

enum BirthDateRules {
    static let minimumAge = 18
    static let oldestSelectableAge = 110

    /// Birthdays are Gregorian dates in the user's own time zone, regardless of
    /// the device's display calendar, so ages match the legal definition.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = AppLocale.current
        return calendar
    }

    static func daysInMonth(month: Int, year: Int, calendar: Calendar = calendar) -> Int {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)),
              let range = calendar.range(of: .day, in: .month, for: date) else { return 31 }
        return range.count
    }

    static func exists(_ date: CalendarDate, calendar: Calendar = calendar) -> Bool {
        (1...12).contains(date.month)
            && date.day >= 1
            && date.day <= daysInMonth(month: date.month, year: date.year, calendar: calendar)
    }

    /// Completed years on the local calendar. Someone born on 29 February has
    /// their birthday on 1 March in common years, never earlier.
    static func age(of birth: CalendarDate, on today: CalendarDate) -> Int {
        var age = today.year - birth.year
        if (today.month, today.day) < (birth.month, birth.day) {
            age -= 1
        }
        return age
    }

    static func evaluate(_ selection: CalendarDate, today: CalendarDate, calendar: Calendar = calendar) -> BirthDateEvaluation {
        guard exists(selection, calendar: calendar) else {
            return .nonexistent(daysInMonth: daysInMonth(month: selection.month, year: selection.year, calendar: calendar))
        }
        if selection == today { return .today }
        if (selection.year, selection.month, selection.day) > (today.year, today.month, today.day) {
            return .future
        }
        let age = age(of: selection, on: today)
        return age >= minimumAge ? .adult(age: age) : .minor(age: age)
    }

    static func changedFields(_ selection: CalendarDate, from baseline: CalendarDate) -> Set<BirthDateField> {
        var fields: Set<BirthDateField> = []
        if selection.day != baseline.day { fields.insert(.day) }
        if selection.month != baseline.month { fields.insert(.month) }
        if selection.year != baseline.year { fields.insert(.year) }
        return fields
    }

    static func selectableYears(today: CalendarDate) -> [Int] {
        Array((today.year - oldestSelectableAge)...today.year)
    }
}

enum PartnerAgeRules {
    static let lowerBound = 18
    /// Configurable ceiling for the slider; not tied to the suggested range.
    static let upperBound = 99
    static let suggestedSpread = 5

    static var bounds: ClosedRange<Int> { lowerBound...upperBound }

    static func suggestedRange(forAge age: Int) -> PartnerAgeRange {
        let minimum = min(max(lowerBound, age - suggestedSpread), upperBound)
        let maximum = min(upperBound, max(minimum, age + suggestedSpread))
        return PartnerAgeRange(minimum: minimum, maximum: maximum)
    }

    static func clamped(minimum: Int, maximum: Int) -> (minimum: Int, maximum: Int) {
        let lower = min(max(minimum, lowerBound), upperBound)
        let upper = min(max(maximum, lower), upperBound)
        return (lower, upper)
    }
}

enum HeightRules {
    static let defaultCentimeters = 175
    static let range = 100...240

    static func clamped(_ centimeters: Int) -> Int {
        min(max(centimeters, range.lowerBound), range.upperBound)
    }

    static func imperialDescription(centimeters: Int) -> String {
        let totalInches = (Double(centimeters) / 2.54).rounded()
        let feet = Int(totalInches) / 12
        let inches = Int(totalInches) % 12
        return "\(feet)′ \(inches)″"
    }
}

enum SearchRadiusRules {
    static let defaultKilometers = 25
    static let range = 1...200

    static func clamped(_ kilometers: Int) -> Int {
        min(max(kilometers, range.lowerBound), range.upperBound)
    }
}

enum AppLocale {
    /// The language the app UI is actually displayed in, which can differ
    /// from the device language when the app lacks that localization.
    static var languageCode: String {
        let identifier = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        return Locale(identifier: identifier).language.languageCode?.identifier ?? "en"
    }

    static var current: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier)
    }
}
