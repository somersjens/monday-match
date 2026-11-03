import Foundation

struct DashboardState: Equatable {
    var round: MatchingRound
    var isOptedIn: Bool
    var profileCompletion: Double
    var notificationsEnabled: Bool
    var hasActiveMatch: Bool

    static func mock(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DashboardState {
        let nextSaturday = calendar.nextDate(
            after: now,
            matching: DateComponents(
                hour: 23,
                minute: 59,
                weekday: 7
            ),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(3 * 24 * 60 * 60)

        let revealAt = calendar.date(
            byAdding: .hour,
            value: 10,
            to: calendar.startOfDay(
                for: calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: nextSaturday
                ) ?? nextSaturday
            )
        ) ?? nextSaturday.addingTimeInterval(10 * 60 * 60)

        let opensAt = calendar.date(
            byAdding: .day,
            value: -6,
            to: nextSaturday
        ) ?? now

        let profileDeadline = nextSaturday

        // `nextSaturday` is by definition in the future, so comparing against it
        // always produced `.open`. Derive the status from the full timeline.
        let status: MatchingRound.Status
        if now >= revealAt {
            status = .revealed
        } else if now >= nextSaturday {
            status = .matching
        } else if now >= opensAt {
            status = .open
        } else {
            status = .locked
        }

        return DashboardState(
            round: MatchingRound(
                opensAt: opensAt,
                profileDeadline: profileDeadline,
                locksAt: nextSaturday,
                revealAt: revealAt,
                status: status
            ),
            isOptedIn: false,
            profileCompletion: 1.0,
            notificationsEnabled: false,
            hasActiveMatch: false
        )
    }
}
