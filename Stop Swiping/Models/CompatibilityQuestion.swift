import Foundation

struct CompatibilityQuestion: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let minimumValue: Int
    let maximumValue: Int

    static var likesChicken: CompatibilityQuestion {
        CompatibilityQuestion(
            id: "likes_chicken",
            title: L10n("How much do you like chicken?"),
            subtitle: L10n("Choose 1 for not at all and 7 for very much."),
            minimumValue: 1,
            maximumValue: 7
        )
    }
}
