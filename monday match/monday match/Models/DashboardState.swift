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
                weekday: 7,
                hour: 23,
                minute: 59
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

        return DashboardState(
            round: MatchingRound(
                opensAt: opensAt,
                profileDeadline: profileDeadline,
                locksAt: nextSaturday,
                revealAt: revealAt,
                status: now < nextSaturday ? .open : .locked
            ),
            isOptedIn: false,
            profileCompletion: 1.0,
            notificationsEnabled: false,
            hasActiveMatch: false
        )
    }
}
