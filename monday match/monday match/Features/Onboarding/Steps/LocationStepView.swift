import SwiftUI
import CoreLocation

struct LocationStepView: View {
    let location: MatchLocation?
    @ObservedObject var locationService: LocationService
    let errorMessage: String?
    let onLocationReceived: (CLLocation) -> Void
    let onError: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("Use your current location")
                        .font(AppTypography.title)

                    Text(
                        "We only use your location to find people within your chosen radius. Exact coordinates are never shown on your profile."
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                    .lineSpacing(4)
                }

                AppCard {
                    VStack(spacing: AppSpacing.large) {
                        ZStack {
                            Circle()
                                .fill(AppColors.accent.opacity(0.12))
                                .frame(width: 120, height: 120)

                            Image(systemName: "location.fill")
                                .font(.system(size: 44, weight: .semibold))
                                .foregroundStyle(AppColors.accent)
                        }

                        if let location {
                            VStack(spacing: AppSpacing.xSmall) {
                                Label(
                                    "Location added",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .font(AppTypography.headline)
                                .foregroundStyle(AppColors.foreground)

                                Text(
                                    "Stored approximately as \(location.coarseLatitude, specifier: "%.2f"), \(location.coarseLongitude, specifier: "%.2f")."
                                )
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.secondaryForeground)
                                .multilineTextAlignment(.center)
                            }
                        } else {
                            Text(
                                "Your permission is requested only after you tap the button below."
                            )
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.secondaryForeground)
                            .multilineTextAlignment(.center)
                        }

                        PrimaryButton(
                            title: location == nil
                                ? "Use current location"
                                : "Refresh location",
                            isLoading: locationService.isRequestingLocation,
                            action: requestLocation
                        )
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(AppTypography.caption)
                        .foregroundStyle(.red)
                }

                AppCard {
                    HStack(alignment: .top, spacing: AppSpacing.medium) {
                        Image(systemName: "eye.slash")
                            .foregroundStyle(AppColors.accent)

                        Text(
                            "Matches will see an approximate distance or area, never your exact coordinates."
                        )
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryForeground)
                    }
                }
            }
            .padding(AppSpacing.large)
        }
    }

    private func requestLocation() {
        Task {
            do {
                let location = try await locationService.requestCurrentLocation()
                onLocationReceived(location)
            } catch {
                onError(error.localizedDescription)
            }
        }
    }
}

#Preview {
    LocationStepView(
        location: nil,
        locationService: LocationService(),
        errorMessage: nil,
        onLocationReceived: { _ in },
        onError: { _ in }
    )
}
