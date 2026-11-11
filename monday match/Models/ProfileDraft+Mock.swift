import Foundation

extension ProfileDraft {
    static var mockCompleted: ProfileDraft {
        var draft = ProfileDraft()
        draft.displayName = "Sam"
        draft.bio = "Curious, kind and always ready to try a new restaurant or walk somewhere without checking the route first."
        draft.gender = .woman
        draft.interestedIn = [.man, .nonBinary]
        draft.relationshipTypes = [.monogamous]
        draft.interests = [.music, .travel, .movies, .cooking]
        draft.preferredRadiusKilometers = 35
        return draft
    }
}
