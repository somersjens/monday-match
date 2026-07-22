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
        profileComplete = !draft.displayName.isEmpty &&
            !draft.bio.isEmpty &&
            !photoURLs.isEmpty
        self.updatedAt = updatedAt
    }
}
