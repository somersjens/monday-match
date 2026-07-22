import SwiftUI

struct DateOfBirthStepView: View {
    @Binding var draft: ProfileDraft

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("When were you born?")
                        .font(AppTypography.title)

                    Text(
                        "We use your date of birth to calculate your age automatically. Your exact birth date will stay private."
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                    .lineSpacing(4)
                }

                AppCard {
                    DatePicker(
                        "Date of birth",
                        selection: $draft.dateOfBirth,
                        in: allowedDateRange,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                AppCard {
                    HStack {
                        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                            Text("Your current age")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.secondaryForeground)

                            Text("\(draft.age())")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                        }

                        Spacer()

                        Image(systemName: "birthday.cake")
                            .font(.system(size: 34))
                            .foregroundStyle(AppColors.accent)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(AppSpacing.large)
        }
    }

    private var allowedDateRange: ClosedRange<Date> {
        let today = Date()
        let oldestDate = calendar.date(
            byAdding: .year,
            value: -100,
            to: today
        ) ?? today

        return oldestDate...today
    }
}

#Preview {
    DateOfBirthStepView(
        draft: .constant(ProfileDraft())
    )
}
