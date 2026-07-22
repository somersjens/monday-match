import Foundation

struct MatchedProfile: Equatable, Identifiable {
    let id: UUID
    let displayName: String
    let age: Int
    let bio: String
    let distanceKilometers: Int
    let interests: [ProfileInterest]
    let relationshipTypes: [RelationshipType]
    let imageData: Data?

    init(
        id: UUID = UUID(),
        displayName: String,
        age: Int,
        bio: String,
        distanceKilometers: Int,
        interests: [ProfileInterest],
        relationshipTypes: [RelationshipType],
        imageData: Data?
    ) {
        self.id = id
        self.displayName = displayName
        self.age = age
        self.bio = bio
        self.distanceKilometers = distanceKilometers
        self.interests = interests
        self.relationshipTypes = relationshipTypes
        self.imageData = imageData
    }

    static let mock = MatchedProfile(
        displayName: "Alex",
        age: 29,
        bio: "I like long walks, cooking for friends and finding small places with surprisingly good coffee.",
        distanceKilometers: 12,
        interests: [.cooking, .music, .nature, .travel],
        relationshipTypes: [.monogamous],
        imageData: nil
    )
}
