import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @StateObject private var notificationService = NotificationPermissionService()

    init(
        state: DashboardState? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: DashboardViewModel(state: state)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                    header
                    countdownCard
                    participationCard
                    deadlineCard
                    notificationCard
                }
                .padding(AppSpacing.large)
            }
            .background(AppColors.background)
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .task {
                viewModel.startClock()
                await notificationService.refresh()
                viewModel.updateNotificationState(
                    notificationService.state
                )
            }
            .onDisappear {
                viewModel.stopClock()
            }
            .onChange(of: notificationService.state) { _, newState in
                viewModel.updateNotificationState(newState)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Your next weekly round")
                .font(AppTypography.title)

            Text(viewModel.roundStatusMessage)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.secondaryForeground)
                .lineSpacing(4)
        }
    }

    private var countdownCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                HStack {
                    Label(
                        "Reveal countdown",
                        systemImage: "clock"
                    )
                    .font(AppTypography.headline)

                    Spacer()

                    Text("SUNDAY")
                        .font(AppTypography.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppColors.accent.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(viewModel.countdownText)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text(viewModel.revealDateText)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryForeground)
            }
        }
    }

    private var participationCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(viewModel.roundStatusTitle)
                        .font(AppTypography.headline)

                    Text(
                        viewModel.state.isOptedIn
                            ? "You can leave the round until Saturday’s deadline."
                            : "You will not be matched unless you actively opt in."
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                }

                Toggle(
                    viewModel.state.isOptedIn
                        ? "Participating"
                        : "Not participating",
                    isOn: Binding(
                        get: { viewModel.state.isOptedIn },
                        set: { _ in viewModel.toggleOptIn() }
                    )
                )
                .tint(AppColors.accent)
                .disabled(!viewModel.canToggleOptIn)

                if !viewModel.canToggleOptIn {
                    Text(optInDisabledReason)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryForeground)
                }
            }
        }
    }

    private var deadlineCard: some View {
        AppCard {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppColors.accent)

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text("Profile edit deadline")
                        .font(AppTypography.headline)

                    Text(viewModel.profileDeadlineText)
                        .font(AppTypography.body.weight(.semibold))

                    Text(
                        "Changes made after this time apply to the next weekly round."
                    )
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryForeground)
                }
            }
        }
    }

    private var notificationCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                HStack(alignment: .top, spacing: AppSpacing.medium) {
                    Image(systemName: notificationSymbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppColors.accent)

                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        Text(notificationTitle)
                            .font(AppTypography.headline)

                        Text(notificationMessage)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.secondaryForeground)
                    }
                }

                if notificationService.state != .authorized {
                    PrimaryButton(
                        title: notificationButtonTitle,
                        isLoading: notificationService.isRequesting,
                        action: {
                            Task {
                                await notificationService.requestAuthorization()
                            }
                        }
                    )
                }
            }
        }
    }

    private var optInDisabledReason: String {
        if viewModel.state.hasActiveMatch {
            return "You already have an active match."
        }

        if viewModel.state.profileCompletion < 1.0 {
            return "Complete your profile before joining."
        }

        return "This round is no longer open."
    }

    private var notificationTitle: String {
        switch notificationService.state {
        case .authorized:
            return "Notifications are on"
        case .denied:
            return "Notifications are off"
        case .notDetermined:
            return "Never miss your reveal"
        }
    }

    private var notificationMessage: String {
        switch notificationService.state {
        case .authorized:
            return "We can alert you about deadlines, reveals and new messages."
        case .denied:
            return "Enable notifications in Settings so you do not miss a reveal or message."
        case .notDetermined:
            return "Allow notifications for Saturday reminders, Sunday reveals and chat messages."
        }
    }

    private var notificationButtonTitle: String {
        switch notificationService.state {
        case .authorized:
            return "Notifications enabled"
        case .denied:
            return "Request again"
        case .notDetermined:
            return "Allow notifications"
        }
    }

    private var notificationSymbol: String {
        switch notificationService.state {
        case .authorized:
            return "bell.badge.fill"
        case .denied:
            return "bell.slash"
        case .notDetermined:
            return "bell"
        }
    }
}

#Preview {
    DashboardView()
}
