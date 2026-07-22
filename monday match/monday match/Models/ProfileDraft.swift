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

    func compatibilityAnswer(
        for question: CompatibilityQuestion
    ) -> CompatibilityAnswer {
        compatibilityAnswers[question.id]
            ?? CompatibilityAnswer(questionID: question.id)
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
