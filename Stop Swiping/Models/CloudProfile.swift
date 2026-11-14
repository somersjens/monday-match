import Foundation

struct CloudProfile: Codable, Equatable {
    var displayName: String
    var bio: String
    var dateOfBirth: Date
    var gender: String?
    var selfDescribedGender: String
    var interestedIn: [String]
    var relationshipTypes: [String]
    var interests: [String]
    var compatibilityAnswers: [String: CompatibilityAnswer]
    var photoURLs: [String]
    var coarseLatitude: Double?
    var coarseLongitude: Double?
    var preferredRadiusKilometers: Int
    var heightCentimeters: Int?
    var preferredPartnerMinimumAge: Int?
    var preferredPartnerMaximumAge: Int?
    var preferredPartnerMinimumHeight: Int?
    var preferredPartnerMaximumHeight: Int?
    var relationshipPreferences: [String: [String]]
    /// Optional for decoding older cloud profiles. New writes always include
    /// the normalized matching values, including Other for a skipped answer.
    var religion: Religion?
    var acceptedPartnerReligions: [Religion]?
    var languages: [String]
    var lifestyle: LifestyleAnswers
    /// Older cloud records omit this field; treat absence as enabled.
    var requiresVerifiedPartnerPhoto: Bool?
    var autoMatchingEnabled: Bool
    var ownAttractiveness: Int?
    var partnerMinimumAttractiveness: Int?
    var minimumMatchPercent: Int
    var profileComplete: Bool
    var updatedAt: Date

    init(
        draft: ProfileDraft,
        photoURLs: [URL],
        updatedAt: Date = Date()
    ) {
        displayName = draft.displayName
        bio = draft.bio
        dateOfBirth = draft.dateOfBirth
        gender = draft.gender?.rawValue
        selfDescribedGender = draft.selfDescribedGender
        interestedIn = draft.interestedIn.map(\.rawValue).sorted()
        relationshipTypes = draft.relationshipTypes.map(\.rawValue).sorted()
        interests = draft.interests.map(\.rawValue).sorted()
        compatibilityAnswers = draft.compatibilityAnswers
        self.photoURLs = photoURLs.map(\.absoluteString)
        coarseLatitude = draft.matchLocation?.coarseLatitude
        coarseLongitude = draft.matchLocation?.coarseLongitude
        preferredRadiusKilometers = draft.preferredRadiusKilometers
        heightCentimeters = draft.heightCentimeters
        preferredPartnerMinimumAge = draft.preferredPartnerMinimumAge
        preferredPartnerMaximumAge = draft.preferredPartnerMaximumAge
        preferredPartnerMinimumHeight = draft.preferredPartnerMinimumHeight
        preferredPartnerMaximumHeight = draft.preferredPartnerMaximumHeight
        relationshipPreferences = draft.relationshipPreferences.selections
        religion = draft.religion.matchingReligion
        acceptedPartnerReligions = Religion.allCases.filter { draft.religion.effectivePartnerReligions.contains($0) }
        languages = draft.languages
        lifestyle = draft.lifestyle
        requiresVerifiedPartnerPhoto = draft.autoMatching.requiresVerifiedPartnerPhoto
        autoMatchingEnabled = draft.autoMatching.isEnabled
        ownAttractiveness = draft.autoMatching.ownAttractiveness
        partnerMinimumAttractiveness = draft.autoMatching.partnerMinimumAttractiveness
        minimumMatchPercent = draft.autoMatching.minimumMatchPercent
        profileComplete = draft.hasCompletedProfileCreation && !draft.displayName.isEmpty
        self.updatedAt = updatedAt
    }

    func isReligionCompatible(with partner: CloudProfile) -> Bool {
        let ownAnswers = ReligionAnswers(own: religion, acceptedPartnerReligions: Set(acceptedPartnerReligions ?? Religion.allCases))
        let partnerAnswers = ReligionAnswers(own: partner.religion, acceptedPartnerReligions: Set(partner.acceptedPartnerReligions ?? Religion.allCases))
        return ownAnswers.isMutuallyCompatible(with: partnerAnswers)
    }
}
