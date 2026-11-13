import Foundation

struct ProfileDraft: Codable, Equatable {
    var displayName = ""
    var bio = ""
    var dateOfBirth: Date
    var gender: GenderIdentity?
    var selfDescribedGender = ""
    var interestedIn: Set<GenderIdentity> = []
    var relationshipTypes: Set<RelationshipType> = []
    var interests: Set<ProfileInterest> = []
    var compatibilityAnswers: [String: CompatibilityAnswer]
    var photos: [ProfilePhoto] = []
    var matchLocation: MatchLocation?
    var preferredRadiusKilometers = 25
    var heightCentimeters: Int?
    var preferredPartnerMinimumAge: Int?
    var preferredPartnerMaximumAge: Int?
    var preferredPartnerMinimumHeight: Int?
    var preferredPartnerMaximumHeight: Int?
    var relationshipPreferences = RelationshipPreferenceAnswers()
    var religion = ReligionAnswers()
    var languages: [String] = []
    var lifestyle = LifestyleAnswers()
    var autoMatching = AutoMatchingSettings()
    var profileCreationCompletedAt: Date?

    init(calendar: Calendar = .current) {
        let today = Date()
        self.dateOfBirth = calendar.date(
            byAdding: .year,
            value: -25,
            to: today
        ) ?? today

        let chickenAnswer = CompatibilityAnswer(
            questionID: CompatibilityQuestion.likesChicken.id
        )

        self.compatibilityAnswers = [
            CompatibilityQuestion.likesChicken.id: chickenAnswer
        ]
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, bio, dateOfBirth, gender, selfDescribedGender
        case interestedIn, relationshipTypes, interests, compatibilityAnswers
        case photos, matchLocation, preferredRadiusKilometers
        case heightCentimeters, preferredPartnerMinimumAge, preferredPartnerMaximumAge
        case preferredPartnerMinimumHeight, preferredPartnerMaximumHeight
        case relationshipPreferences, languages, lifestyle, autoMatching, profileCreationCompletedAt
        case religion
    }

    /// Fields added after the first release are optional in stored drafts,
    /// so profiles saved by earlier builds keep loading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decode(String.self, forKey: .displayName)
        bio = try container.decode(String.self, forKey: .bio)
        dateOfBirth = try container.decode(Date.self, forKey: .dateOfBirth)
        gender = try container.decodeIfPresent(GenderIdentity.self, forKey: .gender)
        selfDescribedGender = try container.decode(String.self, forKey: .selfDescribedGender)
        interestedIn = try container.decode(Set<GenderIdentity>.self, forKey: .interestedIn)
        relationshipTypes = try container.decode(Set<RelationshipType>.self, forKey: .relationshipTypes)
        interests = try container.decode(Set<ProfileInterest>.self, forKey: .interests)
        compatibilityAnswers = try container.decode([String: CompatibilityAnswer].self, forKey: .compatibilityAnswers)
        photos = try container.decode([ProfilePhoto].self, forKey: .photos)
        matchLocation = try container.decodeIfPresent(MatchLocation.self, forKey: .matchLocation)
        preferredRadiusKilometers = try container.decode(Int.self, forKey: .preferredRadiusKilometers)
        heightCentimeters = try container.decodeIfPresent(Int.self, forKey: .heightCentimeters)
        preferredPartnerMinimumAge = try container.decodeIfPresent(Int.self, forKey: .preferredPartnerMinimumAge)
        preferredPartnerMaximumAge = try container.decodeIfPresent(Int.self, forKey: .preferredPartnerMaximumAge)
        preferredPartnerMinimumHeight = try container.decodeIfPresent(Int.self, forKey: .preferredPartnerMinimumHeight)
        preferredPartnerMaximumHeight = try container.decodeIfPresent(Int.self, forKey: .preferredPartnerMaximumHeight)
        relationshipPreferences = try container.decodeIfPresent(RelationshipPreferenceAnswers.self, forKey: .relationshipPreferences) ?? RelationshipPreferenceAnswers()
        religion = try container.decodeIfPresent(ReligionAnswers.self, forKey: .religion) ?? ReligionAnswers()
        languages = try container.decodeIfPresent([String].self, forKey: .languages) ?? []
        lifestyle = try container.decodeIfPresent(LifestyleAnswers.self, forKey: .lifestyle) ?? LifestyleAnswers()
        autoMatching = try container.decodeIfPresent(AutoMatchingSettings.self, forKey: .autoMatching) ?? AutoMatchingSettings()
        profileCreationCompletedAt = try container.decodeIfPresent(Date.self, forKey: .profileCreationCompletedAt)
    }

    func age(
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        calendar.dateComponents(
            [.year],
            from: dateOfBirth,
            to: date
        ).year ?? 0
    }

    func isAtLeast(
        age minimumAge: Int,
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        age(on: date, calendar: calendar) >= minimumAge
    }

    /// Profile creation must be finished, and the stored birthday must still be
    /// adult, before the rest of onboarding may be completed.
    var hasCompletedProfileCreation: Bool {
        profileCreationCompletedAt != nil && isAtLeast(age: BirthDateRules.minimumAge)
    }

    func compatibilityAnswer(
        for question: CompatibilityQuestion
    ) -> CompatibilityAnswer {
        compatibilityAnswers[question.id]
            ?? CompatibilityAnswer(questionID: question.id)
    }

    /// A hard, reciprocal filter, independent of the personality score.
    func isReligionCompatible(with partner: ProfileDraft) -> Bool {
        religion.isMutuallyCompatible(with: partner.religion)
    }

    mutating func normalizePhotoOrder() {
        photos = photos
            .sorted { $0.order < $1.order }
            .enumerated()
            .map { index, photo in
                ProfilePhoto(
                    id: photo.id,
                    imageData: photo.imageData,
                    order: index
                )
            }
    }
}
