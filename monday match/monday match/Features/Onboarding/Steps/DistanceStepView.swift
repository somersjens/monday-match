import SwiftUI

struct DistanceStepView: View {
    let radiusKilometers: Int
    let onRadiusChanged: (Int) -> Void

    private let minimumRadius = 5
    private let maximumRadius = 250
    private let step = 5

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("How far are you willing to travel?")
                        .font(AppTypography.title)

                    Text(
                        "This is a maximum distance. Smaller ranges can improve relevance but may reduce the number of possible matches."
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                    .lineSpacing(4)
                }

                AppCard {
                    VStack(spacing: AppSpacing.xLarge) {
                        VStack(spacing: AppSpacing.xSmall) {
                            Text("\(radiusKilometers) km")
                                .font(.system(size: 48, weight: .bold, design: .rounded))

                            Text(distanceLabel)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.secondaryForeground)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(radiusKilometers) },
                                set: {
                                    let rounded = Int($0 / Double(step)) * step
                                    onRadiusChanged(rounded)
                                }
                            ),
                            in: Double(minimumRadius)...Double(maximumRadius),
                            step: Double(step)
                        )
                        .tint(AppColors.accent)

                        HStack {
                            Text("\(minimumRadius) km")
                            Spacer()
                            Text("\(maximumRadius) km")
                        }
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryForeground)
                    }
                }

                AppCard {
                    HStack(alignment: .top, spacing: AppSpacing.medium) {
                        Image(systemName: "map")
                            .foregroundStyle(AppColors.accent)

                        Text(
                            "The matching service will compare real distances privately. Your profile will only show an approximate distance."
                        )
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryForeground)
                    }
                }
            }
            .padding(AppSpacing.large)
        }
    }

    private var distanceLabel: String {
        switch radiusKilometers {
        case ...15:
            return "Very local"
        case ...50:
            return "Nearby"
        case ...100:
            return "Regional"
        default:
            return "Broad search"
        }
    }
}

#Preview {
    DistanceStepView(
        radiusKilometers: 25,
        onRadiusChanged: { _ in }
    )
}
