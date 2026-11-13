import Combine
import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var state: DashboardState
    @Published private(set) var now = Date()

    private var timerTask: Task<Void, Never>?

    // Same reason as the other view models: `.mock()` is MainActor-isolated and
    // cannot be evaluated as a nonisolated default argument, so build it here.
    init(state: DashboardState? = nil) {
        self.state = state ?? .mock()
    }

    var canToggleOptIn: Bool {
        state.round.status == .open &&
        state.profileCompletion >= 1.0 &&
        !state.hasActiveMatch
    }

    var countdownTarget: Date {
        state.round.revealAt
    }

    var countdownText: String {
        remainingTimeString(to: countdownTarget)
    }

    var profileDeadlineText: String {
        state.round.profileDeadline.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLocale.current)
        )
    }

    var revealDateText: String {
        state.round.revealAt.formatted(
            Date.FormatStyle(date: .complete, time: .shortened).locale(AppLocale.current)
        )
    }

    var roundStatusTitle: String {
        switch state.round.status {
        case .open:
            return state.isOptedIn
                ? L10n("You're in this week's round")
                : L10n("Join this week's round")
        case .locked:
            return L10n("This round is locked")
        case .matching:
            return L10n("Matching is in progress")
        case .revealed:
            return L10n("Your result is ready")
        }
    }

    var roundStatusMessage: String {
        switch state.round.status {
        case .open:
            return state.isOptedIn
                ? L10n("Your profile will be considered when matching starts Saturday night.")
                : L10n("Opt in before the deadline to be considered for Sunday’s reveal.")
        case .locked:
            return L10n("Profiles can no longer be changed for this round.")
        case .matching:
            return L10n("Compatible participants are being compared privately.")
        case .revealed:
            return L10n("Open your match result to see what happened.")
        }
    }

    func startClock() {
        timerTask?.cancel()

        timerTask = Task {
            while !Task.isCancelled {
                now = Date()

                try? await Task.sleep(
                    for: .seconds(1)
                )
            }
        }
    }

    func stopClock() {
        timerTask?.cancel()
        timerTask = nil
    }

    func toggleOptIn() {
        guard canToggleOptIn else { return }
        state.isOptedIn.toggle()
    }

    func updateNotificationState(
        _ permissionState: NotificationPermissionState
    ) {
        state.notificationsEnabled = permissionState == .authorized
    }

    private func remainingTimeString(to target: Date) -> String {
        let interval = max(0, target.timeIntervalSince(now))
        let totalSeconds = Int(interval)

        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if days > 0 {
            return L10n("\(days)d \(hours)h \(minutes)m")
        }

        if hours > 0 {
            return L10n("\(hours)h \(minutes)m \(seconds)s")
        }

        return L10n("\(minutes)m \(seconds)s")
    }

    deinit {
        timerTask?.cancel()
    }
}
