import CoreLocation
import Foundation

enum ProfileCreationStep: Int, CaseIterable, Codable, Identifiable, Comparable {
    case dateOfBirth
    case partnerAgeRange
    case height
    case partnerHeightRange
    case gender
    case partnerGenders
    case sexualArrangement
    case languages
    case location
    case hasChildren
    case partnerHasChildren
    case futureChildren
    case alcohol
    case smoking
    case drugs
    case aloneTime

    /// A step saved by a build with a different set of steps reopens the
    /// birthday instead of failing to load every answer.
    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(Int.self)
        self = Self(rawValue: rawValue) ?? .dateOfBirth
    }

    var id: Int { rawValue }

    var next: ProfileCreationStep? { Self(rawValue: rawValue + 1) }
    var previous: ProfileCreationStep? { Self(rawValue: rawValue - 1) }
    var number: Int { rawValue + 1 }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .dateOfBirth: "When were you born?"
        case .partnerAgeRange: "What age range are you looking for?"
        case .height: "How tall are you?"
        case .partnerHeightRange: "What height range are you looking for?"
        case .gender: "What is your gender?"
        case .partnerGenders: "Who are you open to dating?"
        case .sexualArrangement: RelationshipPreferenceQuestion.sexualArrangement.prompt
        case .languages: "Which languages do you speak comfortably?"
        case .location: "Where would you like to meet people?"
        case .hasChildren: "Do you have children?"
        case .partnerHasChildren: "Are you open to a partner who already has children?"
        case .futureChildren: "Do you want children in the future with a new partner?"
        case .alcohol, .smoking, .drugs: substance?.ownPrompt ?? ""
        case .aloneTime: CompatibilityScaleQuestion.aloneTime.title
        }
    }

    /// A short name for the answer overview.
    var shortTitle: String {
        switch self {
        case .dateOfBirth: "Birthday"
        case .partnerAgeRange: "Age range"
        case .height: "Height"
        case .partnerHeightRange: "Partner height"
        case .gender: "Gender"
        case .partnerGenders: "Open to dating"
        case .sexualArrangement: "Arrangement"
        case .languages: "Languages"
        case .location: "Location"
        case .hasChildren: "Has children"
        case .partnerHasChildren: "Partner with children"
        case .futureChildren: "Future children"
        case .alcohol, .smoking, .drugs: substance?.name ?? ""
        case .aloneTime: CompatibilityScaleQuestion.aloneTime.title
        }
    }

    var substance: Substance? {
        switch self {
        case .alcohol: .alcohol
        case .smoking: .smoking
        case .drugs: .drugs
        default: nil
        }
    }

    var subtitle: String? {
        switch self {
        case .dateOfBirth: "Only your age appears on your profile."
        case .partnerAgeRange: "We suggested a range around your age. Adjust it freely."
        case .height: "Scroll the ruler to set your height."
        case .partnerHeightRange: "Leave it wide open if height doesn’t matter to you."
        case .gender: nil
        case .partnerGenders: "Select everyone you’re open to."
        case .sexualArrangement: "Choose the option that fits you best."
        case .languages: "Tap a language to change it."
        case .location: "Drop a pin on the map or use your location."
        case .hasChildren, .partnerHasChildren, .futureChildren: nil
        case .aloneTime: "From little to lots of time alone. 3 is right in the middle."
        case .alcohol, .smoking, .drugs: "And how often may a partner, at most? Less often is fine too."
        }
    }
}

/// A day on the user's local Gregorian calendar. Stored as components so a
/// birthday never shifts when it is converted between time zones.
struct CalendarDate: Codable, Hashable {
    var year: Int
    var month: Int
    var day: Int

    static func today(calendar: Calendar = BirthDateRules.calendar, now: Date = Date()) -> CalendarDate {
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        return CalendarDate(year: components.year ?? 2000, month: components.month ?? 1, day: components.day ?? 1)
    }

    /// Local noon avoids daylight-saving transitions moving the date.
    func date(in calendar: Calendar = BirthDateRules.calendar) -> Date? {
        guard BirthDateRules.exists(self, calendar: calendar) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
}

struct PartnerAgeRange: Codable, Equatable {
    var minimum: Int
    var maximum: Int
    /// Untouched defaults follow the user's age if they edit their birthday later.
    var isCustomized = false
}

struct SelectedLocation: Codable, Equatable {
    enum Source: String, Codable {
        case device
        case map
    }

    var latitude: Double
    var longitude: Double
    var source: Source
    var placeName: String?

    init(coordinate: CLLocationCoordinate2D, source: Source, placeName: String? = nil) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.source = source
        self.placeName = placeName
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Everything the profile-creation onboarding collects, plus its flow state.
struct ProfileCreationState: Codable, Equatable {
    var currentStep: ProfileCreationStep = .dateOfBirth

    /// The date the picker started on, used to tell which fields were changed.
    var birthDateBaseline: CalendarDate
    /// The picker's current value. It may be a nonexistent date such as 31 April.
    var birthDateSelection: CalendarDate
    /// Only set once a valid adult birthday has been submitted.
    var dateOfBirth: CalendarDate?

    var partnerAgeRange: PartnerAgeRange?
    var heightCentimeters = HeightRules.defaultCentimeters
    var hasAdjustedHeight = false
    var gender: GenderIdentity?
    var partnerGenders: Set<GenderIdentity> = []
    var relationshipPreferences = RelationshipPreferenceAnswers()
    var languages: [String]
    var location: SelectedLocation?
    var searchRadiusKilometers = SearchRadiusRules.defaultKilometers

    /// Optional in storage so states saved before these questions existed
    /// still decode.
    private var storedLifestyle: LifestyleAnswers?
    var lifestyle: LifestyleAnswers {
        get { storedLifestyle ?? LifestyleAnswers() }
        set { storedLifestyle = newValue }
    }

    private var storedPartnerHeightRange: PartnerHeightRange?
    var partnerHeightRange: PartnerHeightRange {
        get { storedPartnerHeightRange ?? .any }
        set { storedPartnerHeightRange = newValue }
    }

    private var storedAutoMatching: AutoMatchingSettings?
    var autoMatching: AutoMatchingSettings {
        get { storedAutoMatching ?? AutoMatchingSettings() }
        set { storedAutoMatching = newValue }
    }

    var isUnderageLocked = false
    var completedAt: Date?

    init(today: CalendarDate, applicationLanguage: String) {
        birthDateBaseline = today
        birthDateSelection = today
        languages = [applicationLanguage]
    }

    func age(on today: CalendarDate) -> Int? {
        dateOfBirth.map { BirthDateRules.age(of: $0, on: today) }
    }
}
