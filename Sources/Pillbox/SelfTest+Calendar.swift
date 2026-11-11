import AppKit
import SwiftUI

extension SelfTest {
    /// The Calendar tab's day grouping, the default start of a new event, and the meeting alert rule.
    static func calendarWeek() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? Date()
        }
        func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> AgendaEvent {
            AgendaEvent(id: id, title: id, start: start, end: end, allDay: allDay, calendar: "Work", color: .red, join: nil)
        }
        let now = at(11, 10)
        let week = AgendaGrouping.days([], count: 7, now: now, calendar: cal)
        check("calendar week: seven days from today", week.count == 7 && week.first?.start == at(11, 0) && week.last?.offset == 6, "\(week.count) days")

        let timed = event("standup", at(13, 9), at(13, 9, 30))
        let days = AgendaGrouping.days([timed], count: 7, now: now, calendar: cal)
        check("calendar week: a timed event lands on its own day only", days.filter { !$0.events.isEmpty }.map(\.offset) == [2], "\(days.filter { !$0.events.isEmpty }.map(\.offset))")

        let endsAtMidnight = event("late", at(11, 22), at(12, 0))
        let midnight = AgendaGrouping.days([endsAtMidnight], count: 2, now: now, calendar: cal)
        check("calendar week: an event ending at midnight stays on its day", midnight[0].events.count == 1 && midnight[1].events.isEmpty)

        let running = event("overnight", at(10, 23), at(11, 1))
        let runningToday = AgendaGrouping.days([running], count: 2, now: now, calendar: cal)
        check("calendar week: an event still running counts as today", runningToday[0].events.map(\.id) == ["overnight"] && runningToday[1].events.isEmpty)

        let trip = event("trip", at(12, 0), at(14, 0), allDay: true)
        let spanning = AgendaGrouping.days([trip], count: 4, now: now, calendar: cal)
        check("calendar week: a multi-day all-day event shows on each day", spanning.map { $0.events.count } == [0, 1, 1, 0], "\(spanning.map { $0.events.count })")

        let allDayToday = event("holiday", at(11, 0), at(12, 0), allDay: true)
        let day11 = AgendaGrouping.days([event("late-timed", at(11, 15), at(11, 16)), event("early-timed", at(11, 8), at(11, 9)), allDayToday], count: 1, now: now, calendar: cal)
        check("calendar week: all-day events come first, then timed events in order", day11[0].events.map(\.id) == ["holiday", "early-timed", "late-timed"], "\(day11[0].events.map(\.id))")

        let combined = AgendaGrouping.combine(day: at(20, 0), time: at(3, 14, 45), calendar: cal)
        check("calendar week: the day of one date and the time of another", combined == at(20, 14, 45), "\(combined)")

        check("calendar week: the default start is the next full hour", AgendaGrouping.nextHour(after: at(11, 10, 20), calendar: cal) == at(11, 11))

        let soon = event("review", now.addingTimeInterval(4 * 60), now.addingTimeInterval(34 * 60))
        let later = event("planning", now.addingTimeInterval(9 * 60), now.addingTimeInterval(39 * 60))
        let pick = MeetingAlertRule.next(in: [later, soon], now: now, lead: 5, announced: [])
        check("meeting alert: the soonest event within the lead time", pick?.id == "review", "\(pick?.id ?? "nil")")
        check("meeting alert: nothing is announced when it is off", MeetingAlertRule.next(in: [soon], now: now, lead: 0, announced: []) == nil)
        check("meeting alert: an event beyond the lead time waits", MeetingAlertRule.next(in: [later], now: now, lead: 5, announced: []) == nil)
        check("meeting alert: an event is announced once", MeetingAlertRule.next(in: [soon], now: now, lead: 15, announced: ["review"]) == nil)
        let started = event("started", now.addingTimeInterval(-60), now.addingTimeInterval(1800))
        check("meeting alert: an event that already started is not announced", MeetingAlertRule.next(in: [started], now: now, lead: 15, announced: []) == nil)
        let allDay = event("offsite", now.addingTimeInterval(120), now.addingTimeInterval(3600), allDay: true)
        check("meeting alert: all-day events are not announced", MeetingAlertRule.next(in: [allDay], now: now, lead: 15, announced: []) == nil)
    }
}
