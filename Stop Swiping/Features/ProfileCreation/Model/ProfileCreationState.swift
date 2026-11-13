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
    // Append storage IDs so older saved steps retain their meaning.
    case religion
    case timeTogether
    case dailyContact
    case physicalAffection
    case sharedHobbies
    case futurePlanning
    case texting
    case calling
    case conversationHumor
    case communicationStyle
    case discussingFeelings
    case expressingAppreciation
    case relationshipConversations
    case disagreements
    case stressContact
    case listeningAndSolutions
    case dailyRhythm
    case weeklyPlanning
    case leisureTime
    case exercise
    case foodChoices
    case travel
    case newExperiences
    case socialCircle
    case meetingNewPeople
    case socialPlans
    case familyRole
    case partnerSocializing
    case exPartnerContact
    case relationshipPrivacy
    case socialMediaSharing
    case punctuality
    case keepingPlans
    case homeTidiness
    case spendingMoney
    case workAmbition
    case decisionMaking
    case changePreference
    case sharedResponsibilities

    static let allCases: [Self] = [
        .dateOfBirth, .partnerAgeRange, .height, .partnerHeightRange,
        .gender, .partnerGenders, .sexualArrangement, .religion, .languages,
        .location, .hasChildren, .partnerHasChildren, .futureChildren,
        .alcohol, .smoking, .drugs
    ] + CompatibilityScaleQuestion.orderedSteps

    /// A step saved by a build with a different set of steps reopens the
    /// birthday instead of failing to load every answer.
    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(Int.self)
        self = Self(rawValue: rawValue) ?? .dateOfBirth
    }

    var id: Int { rawValue }

    var next: ProfileCreationStep? { Self.allCases.dropFirst(number).first }
    var previous: ProfileCreationStep? { Self.allCases.prefix(number - 1).last }
    private static let positions = Dictionary(uniqueKeysWithValues: allCases.enumerated().map { ($0.element, $0.offset + 1) })
    var number: Int { Self.positions[self]! }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.number < rhs.number }

    var title: String {
        switch self {
        case .dateOfBirth: L10n("When were you born?")
        case .partnerAgeRange: L10n("What age range are you looking for?")
        case .height: L10n("How tall are you?")
        case .partnerHeightRange: L10n("What height range are you looking for?")
        case .gender: L10n("What is your gender?")
        case .partnerGenders: L10n("Who are you open to dating?")
        case .sexualArrangement: RelationshipPreferenceQuestion.sexualArrangement.prompt
        case .religion: ReligionQuestionPhase.own.title
        case .languages: L10n("Which languages do you speak comfortably?")
        case .location: L10n("Where would you like to meet people?")
        case .hasChildren: L10n("Do you have children?")
        case .partnerHasChildren: L10n("Are you open to a partner who already has children?")
        case .futureChildren: L10n("Do you want children in the future with a new partner?")
        case .alcohol, .smoking, .drugs: substance?.ownPrompt ?? ""
        default: compatibilityQuestion?.title ?? ""
        }
    }

    /// A short name for the answer overview.
    var shortTitle: String {
        switch self {
        case .dateOfBirth: L10n("Birthday")
        case .partnerAgeRange: L10n("Age range")
        case .height: L10n("Height")
        case .partnerHeightRange: L10n("Partner height")
        case .gender: L10n("Gender")
        case .partnerGenders: L10n("Open to dating")
        case .sexualArrangement: L10n("Arrangement")
        case .religion: L10n("Religion / worldview")
        case .languages: L10n("Languages")
        case .location: L10n("Location")
        case .hasChildren: L10n("Has children")
        case .partnerHasChildren: L10n("Partner with children")
        case .futureChildren: L10n("Future children")
        case .alcohol, .smoking, .drugs: substance?.name ?? ""
        default: compatibilityQuestion?.title ?? ""
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
        case .dateOfBirth: L10n("Only your age appears on your profile.")
        case .partnerAgeRange: L10n("We suggested a range around your age. Adjust it freely.")
        case .height: L10n("Scroll the ruler to set your height.")
        case .partnerHeightRange: L10n("Leave it wide open if height doesn’t matter to you.")
        case .gender: nil
        case .partnerGenders: L10n("Select everyone you’re open to.")
        case .sexualArrangement: L10n("Choose the option that fits you best.")
        case .religion: ReligionQuestionPhase.own.subtitle
        case .languages: L10n("Tap a language to change it.")
        case .location: L10n("Drop a pin on the map or use your location.")
        case .hasChildren, .partnerHasChildren, .futureChildren: nil
        case .alcohol, .smoking, .drugs: L10n("And how often may a partner, at most? Less often is fine too.")
        default: compatibilityQuestion?.subtitle
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
    private var storedReligion: ReligionAnswers?
    var religion: ReligionAnswers {
        get { storedReligion ?? ReligionAnswers() }
        set { storedReligion = newValue }
    }
    private var storedReligionPhase: ReligionQuestionPhase?
    var religionPhase: ReligionQuestionPhase {
        get { storedReligionPhase ?? .own }
        set { storedReligionPhase = newValue }
    }
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
