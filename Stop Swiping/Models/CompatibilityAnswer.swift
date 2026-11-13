import Foundation

struct CompatibilityAnswer: Codable, Equatable {
    let questionID: String
    var ownValue: Int
    var desiredMinimum: Int
    var desiredIdeal: Int
    var desiredMaximum: Int

    init(
        questionID: String,
        ownValue: Int = 4,
        desiredMinimum: Int = 3,
        desiredIdeal: Int = 4,
        desiredMaximum: Int = 5
    ) {
        self.questionID = questionID
        self.ownValue = ownValue
        self.desiredMinimum = desiredMinimum
        self.desiredIdeal = desiredIdeal
        self.desiredMaximum = desiredMaximum
        normalize()
    }

    mutating func setOwnValue(
        _ value: Int,
        question: CompatibilityQuestion
    ) {
        ownValue = clamp(
            value,
            minimum: question.minimumValue,
            maximum: question.maximumValue
        )
    }

    mutating func setDesiredRange(
        minimum: Int,
        ideal: Int,
        maximum: Int,
        question: CompatibilityQuestion
    ) {
        desiredMinimum = clamp(
            minimum,
            minimum: question.minimumValue,
            maximum: question.maximumValue
        )
        desiredMaximum = clamp(
            maximum,
            minimum: question.minimumValue,
            maximum: question.maximumValue
        )

        if desiredMinimum > desiredMaximum {
            swap(&desiredMinimum, &desiredMaximum)
        }

        desiredIdeal = clamp(
            ideal,
            minimum: desiredMinimum,
            maximum: desiredMaximum
        )
    }

    mutating func resetDesiredRangeAroundOwnValue(
        question: CompatibilityQuestion
    ) {
        desiredMinimum = max(question.minimumValue, ownValue - 1)
        desiredIdeal = ownValue
        desiredMaximum = min(question.maximumValue, ownValue + 1)
    }

    private mutating func normalize() {
        if desiredMinimum > desiredMaximum {
            swap(&desiredMinimum, &desiredMaximum)
        }

        desiredIdeal = clamp(
            desiredIdeal,
            minimum: desiredMinimum,
            maximum: desiredMaximum
        )
    }

    private func clamp(
        _ value: Int,
        minimum: Int,
        maximum: Int
    ) -> Int {
        Swift.max(minimum, Swift.min(maximum, value))
    }
}
