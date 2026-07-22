import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var state: DashboardState
    @Published private(set) var now = Date()

    private var timerTask: Task<Void, Never>?

    init(state: DashboardState = .mock()) {
        self.state = state
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
            date: .abbreviated,
            time: .shortened
        )
    }

    var revealDateText: String {
        state.round.revealAt.formatted(
            date: .complete,
            time: .shortened
        )
    }

    var roundStatusTitle: String {
        switch state.round.status {
        case .open:
            return state.isOptedIn
                ? "You're in this week's round"
                : "Join this week's round"
        case .locked:
            return "This round is locked"
        case .matching:
            return "Matching is in progress"
        case .revealed:
            return "Your result is ready"
        }
    }

    var roundStatusMessage: String {
        switch state.round.status {
        case .open:
            return state.isOptedIn
                ? "Your profile will be considered when matching starts Saturday night."
                : "Opt in before the deadline to be considered for Sunday’s reveal."
        case .locked:
            return "Profiles can no longer be changed for this round."
        case .matching:
            return "Compatible participants are being compared privately."
        case .revealed:
            return "Open your match result to see what happened."
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
            return "\(days)d \(hours)h \(minutes)m"
        }

        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        }

        return "\(minutes)m \(seconds)s"
    }

    deinit {
        timerTask?.cancel()
    }
}
