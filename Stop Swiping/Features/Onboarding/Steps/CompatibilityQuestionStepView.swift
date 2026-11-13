import SwiftUI

struct CompatibilityQuestionStepView: View {
    let question: CompatibilityQuestion
    let onAnswerChanged: (CompatibilityAnswer) -> Void

    @State private var answer: CompatibilityAnswer

    init(
        question: CompatibilityQuestion,
        answer: CompatibilityAnswer,
        onAnswerChanged: @escaping (CompatibilityAnswer) -> Void
    ) {
        self.question = question
        self.onAnswerChanged = onAnswerChanged
        _answer = State(initialValue: answer)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(question.title)
                        .font(AppTypography.title)

                    Text(question.subtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.secondaryForeground)
                }

                scoreCard

                desiredPartnerCard

                AppCard {
                    HStack(alignment: .top, spacing: AppSpacing.medium) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(AppColors.accent)

                        Text(
                            L10n("The ideal value can move independently, while the minimum and maximum define what you still consider acceptable.")
                        )
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryForeground)
                    }
                }
            }
            .padding(AppSpacing.large)
        }
        .onChange(of: answer) { _, newValue in
            onAnswerChanged(newValue)
        }
    }

    private var scoreCard: some View {
        AppCard {
            VStack(spacing: AppSpacing.large) {
                VStack(spacing: AppSpacing.xSmall) {
                    Text(L10n("Your answer"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryForeground)

                    Text("\(answer.ownValue)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                }

                Slider(
                    value: Binding(
                        get: { Double(answer.ownValue) },
                        set: { newValue in
                            answer.setOwnValue(
                                Int(newValue.rounded()),
                                question: question
                            )
                        }
                    ),
                    in: Double(question.minimumValue)...Double(question.maximumValue),
                    step: 1
                )
                .tint(AppColors.accent)

                scaleLabels

                Button(L10n("Set partner preference around my answer")) {
                    answer.resetDesiredRangeAroundOwnValue(
                        question: question
                    )
                }
                .font(AppTypography.caption.weight(.semibold))
            }
        }
    }

    private var desiredPartnerCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(L10n("Preferred partner answer"))
                        .font(AppTypography.headline)

                    Text(
                        L10n("\(answer.desiredMinimum) – \(answer.desiredMaximum), ideally \(answer.desiredIdeal)")
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                }

                preferenceSlider(
                    title: L10n("Minimum"),
                    value: answer.desiredMinimum,
                    allowedRange: question.minimumValue...answer.desiredIdeal
                ) { newValue in
                    answer.setDesiredRange(
                        minimum: newValue,
                        ideal: answer.desiredIdeal,
                        maximum: answer.desiredMaximum,
                        question: question
                    )
                }

                preferenceSlider(
                    title: L10n("Ideal"),
                    value: answer.desiredIdeal,
                    allowedRange: answer.desiredMinimum...answer.desiredMaximum
                ) { newValue in
                    answer.setDesiredRange(
                        minimum: answer.desiredMinimum,
                        ideal: newValue,
                        maximum: answer.desiredMaximum,
                        question: question
                    )
                }

                preferenceSlider(
                    title: L10n("Maximum"),
                    value: answer.desiredMaximum,
                    allowedRange: answer.desiredIdeal...question.maximumValue
                ) { newValue in
                    answer.setDesiredRange(
                        minimum: answer.desiredMinimum,
                        ideal: answer.desiredIdeal,
                        maximum: newValue,
                        question: question
                    )
                }
            }
        }
    }

    private var scaleLabels: some View {
        HStack {
            Text("\(question.minimumValue)")
            Spacer()
            Text("\(question.maximumValue)")
        }
        .font(AppTypography.caption)
        .foregroundStyle(AppColors.secondaryForeground)
    }

    private func preferenceSlider(
        title: String,
        value: Int,
        allowedRange: ClosedRange<Int>,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack {
                Text(title)
                    .font(AppTypography.body)

                Spacer()

                Text("\(value)")
                    .font(AppTypography.body.weight(.semibold))
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Int($0.rounded())) }
                ),
                in: Double(allowedRange.lowerBound)...Double(allowedRange.upperBound),
                step: 1
            )
            .tint(AppColors.accent)
        }
    }
}

#Preview {
    CompatibilityQuestionStepView(
        question: .likesChicken,
        answer: CompatibilityAnswer(
            questionID: CompatibilityQuestion.likesChicken.id
        ),
        onAnswerChanged: { _ in }
    )
}
