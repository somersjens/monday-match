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
    // Explicit numbers follow retired questions, so the remaining saved
    // steps keep their meaning. Never reuse 17, 18, 20, 21, 23, 24, 26, 27, 28,
    // 29, 34, 37, 39, 40, 44, 46, 48, 53, 54, 59, 60, 61, 65, 66, 67, 69, 74 or 82.
    case physicalAffection = 19
    case texting = 22
    case communicationStyle = 25
    case stressContact = 30
    case listeningAndSolutions
    case dailyRhythm
    case weeklyPlanning
    case exercise = 35
    case foodChoices
    case newExperiences = 38
    case socialPlans = 41
    case familyRole
    case partnerSocializing
    case relationshipPrivacy = 45
    case punctuality = 47
    case homeTidiness = 49
    case spendingMoney
    case workAmbition
    case decisionMaking
    case romanticGestures = 55
    case publicAffection
    case sexualIntimacy
    case talkativeness
    case nightlife = 62
    case takingInitiative
    case spirituality
    case pets = 68
    case debating = 70
    case travelStyle
    case celebrations
    case hostingGuests
    case personalStyle = 75
    case currentAffairs
    case screenTime
    case cityOrNature
    case humor
    case setbacks
    case othersOpinion
    case cooking = 83
    case competitiveness
    case headOrHeart
    case optimism
    case patience
    case rules
    case boundaries
    case pride
    case perfectionism
    case emotionalExpression
    case makingUp

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

    /// The share of the questionnaire answered before this screen. Each screen
    /// counts equally, including questions with several parts.
    var progressBefore: Double { Double(number - 1) / Double(Self.allCases.count) }

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
        case .partnerHasChildren: L10n("Open to a partner with children?")
        case .futureChildren: L10n("Do you want children with a new partner?")
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
        case .partnerAgeRange: L10n("A range around your age. Drag the white dots to adjust it.")
        case .height: L10n("Scroll the ruler to set your height.")
        case .partnerHeightRange: L10n("Drag the white dots, or leave it wide open if height doesn’t matter.")
        case .gender: nil
        case .partnerGenders: L10n("Select every option you’re open to.")
        case .sexualArrangement: nil
        case .religion: nil
        case .languages: L10n("Tap a language to change it.")
        case .location: L10n("Drop a pin on the map or use your location.")
        case .hasChildren, .partnerHasChildren, .futureChildren: nil
        case .alcohol, .smoking, .drugs: L10n("And how often may a partner, at most?")
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

    /// The furthest question reached. Progress follows it, so going back to
    /// an earlier question never lowers it. Optional in storage so states
    /// saved before it existed still decode.
    private var storedFurthestStep: ProfileCreationStep?
    var furthestStep: ProfileCreationStep {
        get { max(storedFurthestStep ?? currentStep, currentStep) }
        set { storedFurthestStep = newValue }
    }

    /// The questionnaire's share answered: every screen before the furthest
    /// one reached counts, each equally.
    var progress: Double { furthestStep.progressBefore }

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

    /// The first name matches see. Optional in storage so states saved
    /// before names existed still decode.
    private var storedDisplayName: String?
    var displayName: String {
        get { storedDisplayName ?? "" }
        set { storedDisplayName = newValue }
    }

    var profilePrivacyConsent: PrivacyConsentReceipt?
    var hasUnderstoodExplanation: Bool?
    var hasCompletedDemo: Bool?
    var hasUsedProfileExchange: Bool?

    var isUnderageLocked = false
    var completedAt: Date?
    /// Set while a finished profile answers questions an app update added.
    var isAnsweringNewQuestions: Bool?

    init(today: CalendarDate, applicationLanguage: String) {
        birthDateBaseline = today
        birthDateSelection = today
        languages = [applicationLanguage]
    }

    func age(on today: CalendarDate) -> Int? {
        dateOfBirth.map { BirthDateRules.age(of: $0, on: today) }
    }

    /// A profile finished before an app update added questions has no
    /// answers for them, so the server leaves it out of matching. It reopens
    /// at the first new question; finishing it again completes the profile.
    /// Returns whether anything changed.
    mutating func reopenForNewQuestions() -> Bool {
        guard completedAt != nil, !isUnderageLocked,
              let first = CompatibilityScaleQuestion.all.first(where: { !lifestyle[$0].isComplete }) else {
            return false
        }
        completedAt = nil
        isAnsweringNewQuestions = true
        currentStep = first.step
        return true
    }
}
