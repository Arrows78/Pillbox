import Foundation
import XCTest
@testable import Pillbox

/// The palette: fuzzy matching, recent commands and prefixes.
final class PaletteLogicTests: XCTestCase {
    func testLettersMustAllBeThereInOrder() {
        XCTAssertNotNil(FuzzyMatch.score("kbl", in: "Keyboard backlight"))
        XCTAssertNil(FuzzyMatch.score("snx", in: "Snap center"))
    }

    func testARunOfLettersBeatsScatteredOnes() {
        XCTAssertGreaterThan(FuzzyMatch.score("snap", in: "Snap center") ?? 0, FuzzyMatch.score("snap", in: "Sensor nominal active payload") ?? 0)
    }

    func testPrefixesSplitTheQuery() {
        if case .commands(let rest) = PalettePrefix(">mute") {
            XCTAssertEqual(rest, "mute")
        } else {
            XCTFail("> should keep commands")
        }
        if case .clipboard(let rest) = PalettePrefix("/code") {
            XCTAssertEqual(rest, "code")
        } else {
            XCTFail("/ should keep the clipboard")
        }
        if case .none = PalettePrefix("mute") {} else { XCTFail("no prefix means everything") }
    }

    func testRecentCommandsComeFirstOnceEach() {
        let key = PaletteRecents.key
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        PaletteRecents.record("Alpha")
        PaletteRecents.record("Beta")
        PaletteRecents.record("Alpha")
        XCTAssertEqual(PaletteRecents.titles, ["Alpha", "Beta"])
    }
}

/// The quiet hours of the islands, including the period that crosses midnight.
final class QuietHoursTests: XCTestCase {
    func testDaytimePeriod() {
        XCTAssertTrue(QuietHours.isQuiet(hour: 14, from: 13, to: 15))
        XCTAssertFalse(QuietHours.isQuiet(hour: 15, from: 13, to: 15))
    }

    func testPeriodOverMidnightHoldsLateAndEarly() {
        XCTAssertTrue(QuietHours.isQuiet(hour: 23, from: 22, to: 7))
        XCTAssertTrue(QuietHours.isQuiet(hour: 3, from: 22, to: 7))
        XCTAssertFalse(QuietHours.isQuiet(hour: 12, from: 22, to: 7))
    }

    func testOffWithoutAStart() {
        XCTAssertFalse(QuietHours.isQuiet(hour: 3, from: -1, to: 7))
    }
}

/// The pomodoro cycle and the timer's CSV export.
final class TimerLogicTests: XCTestCase {
    func testEveryFourthFocusSessionGivesTheLongBreak() {
        XCTAssertTrue(Pomodoro.longBreakDue(focusDone: 4, every: 4))
        XCTAssertFalse(Pomodoro.longBreakDue(focusDone: 3, every: 4))
        XCTAssertFalse(Pomodoro.longBreakDue(focusDone: 4, every: 0))
        XCTAssertFalse(Pomodoro.longBreakDue(focusDone: 0, every: 4))
    }

    func testCSVHasAHeaderAndOneSortedRowPerDay() {
        XCTAssertEqual(FocusExport.csv(["2026-11-02": 3, "2026-11-01": 1]), "date,focus_sessions\n2026-11-01,1\n2026-11-02,3\n")
        XCTAssertEqual(FocusExport.csv([:]), "date,focus_sessions\n")
    }

    func testTheEndSoundIsOneOfTheOfferedOnes() {
        XCTAssertTrue(FocusExport.sounds.contains(Preferences.timerSound.defaultValue))
    }
}

/// The reminder filters, with fixed dates so the test does not depend on today.
final class ReminderFilterTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func date(_ day: Int, _ hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    func testFilters() {
        let now = date(11, 12)
        let undated = ReminderItem(id: "u", title: "u", due: nil)
        let today = ReminderItem(id: "t", title: "t", due: date(11, 9))
        let late = ReminderItem(id: "l", title: "l", due: date(10, 9))
        let later = ReminderItem(id: "n", title: "n", due: date(12, 9))
        XCTAssertTrue([undated, today, late, later].allSatisfy { ReminderFilter.all.matches($0, now: now, calendar: cal) })
        XCTAssertTrue(ReminderFilter.today.matches(today, now: now, calendar: cal))
        XCTAssertFalse(ReminderFilter.today.matches(late, now: now, calendar: cal))
        XCTAssertFalse(ReminderFilter.today.matches(later, now: now, calendar: cal))
        XCTAssertTrue(ReminderFilter.overdue.matches(late, now: now, calendar: cal))
        XCTAssertFalse(ReminderFilter.overdue.matches(later, now: now, calendar: cal))
        XCTAssertFalse(ReminderFilter.today.matches(undated, now: now, calendar: cal))
        XCTAssertFalse(ReminderFilter.overdue.matches(undated, now: now, calendar: cal))
    }
}

/// Pull requests: GitHub's checks and review from gh's JSON, GitLab's merge requests from glab's.
final class PullRequestParsingTests: XCTestCase {
    private func state(_ json: String) -> (checks: PRChecks, review: PRReview)? {
        GitHubPRs.summarize(Data(json.utf8))
    }

    func testAFailedCheckWinsOverTheOthers() {
        let s = state(#"{"reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS","status":"COMPLETED"},{"conclusion":"FAILURE","status":"COMPLETED"}]}"#)
        XCTAssertEqual(s?.checks, .failing)
        XCTAssertEqual(s?.review, .approved)
    }

    func testARunningCheckIsPendingAndAReviewAskedIsRequired() {
        let s = state(#"{"reviewDecision":"REVIEW_REQUIRED","statusCheckRollup":[{"conclusion":"","status":"IN_PROGRESS"},{"conclusion":"SUCCESS","status":"COMPLETED"}]}"#)
        XCTAssertEqual(s?.checks, .pending)
        XCTAssertEqual(s?.review, .required)
    }

    func testACommitStatusCountsAndNoDecisionIsNone() {
        let s = state(#"{"reviewDecision":"","statusCheckRollup":[{"state":"SUCCESS"}]}"#)
        XCTAssertEqual(s?.checks, .passing)
        XCTAssertEqual(s?.review, PRReview.none)
    }

    func testNoChecksAtAllIsNone() {
        XCTAssertEqual(state(#"{"reviewDecision":"CHANGES_REQUESTED","statusCheckRollup":[]}"#)?.checks, PRChecks.none)
    }

    func testGitLabMergeRequestKeepsProjectNumberAndDraft() {
        let json = #"[{"title":"Fix login","web_url":"https://gitlab.example.com/team/app/-/merge_requests/12","iid":12,"draft":true,"references":{"short":"!12","full":"team/app!12"}},{"title":"Bad","web_url":"http://insecure","iid":1,"references":{"full":"x!1"}}]"#
        let prs = GitLabMRs.parse(Data(json.utf8))
        XCTAssertEqual(prs.count, 1)
        XCTAssertEqual(prs.first?.repo, "team/app")
        XCTAssertEqual(prs.first?.number, 12)
        XCTAssertEqual(prs.first?.draft, true)
    }
}

/// Weather: the hourly forecast and the rain rule.
final class WeatherLogicTests: XCTestCase {
    func testEachCompleteHourIsKeptInOrder() {
        let json = #"{"hourly":{"time":["2026-11-11T14:00","2026-11-11T15:00","2026-11-11T16:00"],"temperature_2m":[12.4,11.6,10.2],"precipitation_probability":[10,70,90]}}"#
        let hours = WeatherService.parseHourly(Data(json.utf8), status: 200)
        XCTAssertEqual(hours.count, 3)
        XCTAssertEqual(hours.first?.temperature, 12)
        XCTAssertEqual(hours[1].rainChance, 70)
        XCTAssertTrue(WeatherService.parseHourly(Data(json.utf8), status: 500).isEmpty)
        let now = hours[0].hour
        XCTAssertEqual(WeatherService.rainSoon(hours, now: now, threshold: 60)?.rainChance, 70)
        XCTAssertNil(WeatherService.rainSoon(hours, now: now, threshold: 95))
    }
}

/// The shelf, notifications, the menu bar calendar, music volume, the keyboard backlight and the browser's media.
final class MiscLogicTests: XCTestCase {
    func testShelfEntriesAgeOutAfterTheDaysChosen() {
        let now = Date()
        XCTAssertNil(ShelfService.cutoff(keepDays: 0, now: now))
        XCTAssertEqual(ShelfService.cutoff(keepDays: 7, now: now).map { now.timeIntervalSince($0) }, 7 * 86400)
    }

    func testAShelfEntryFromBeforeDatesStillLoads() throws {
        let old = Data(#"{"id":"6B6F2C1E-0000-4000-8000-000000000001","path":"/tmp/a.txt"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(ShelfItem.self, from: old).path, "/tmp/a.txt")
    }

    func testNotificationMuteIsPerApp() {
        let key = NotificationMute.key
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        NotificationMute.setMuted("com.apple.mail", true)
        XCTAssertTrue(NotificationMute.isMuted("com.apple.mail"))
        XCTAssertFalse(NotificationMute.isMuted("com.apple.Notes"))
        NotificationMute.setMuted("com.apple.mail", false)
        XCTAssertFalse(NotificationMute.isMuted("com.apple.mail"))
    }

    func testMenuBarCalendarShowsWithinTheHoursChosen() {
        let now = Date()
        XCTAssertTrue(MenuBarCalendar.showsEvent(starting: now.addingTimeInterval(9 * 3600), within: 0, now: now))
        XCTAssertTrue(MenuBarCalendar.showsEvent(starting: now.addingTimeInterval(3600), within: 1, now: now))
        XCTAssertFalse(MenuBarCalendar.showsEvent(starting: now.addingTimeInterval(4 * 3600), within: 3, now: now))
    }

    func testMusicVolumeIsKeptBetweenZeroAndOneHundred() {
        XCTAssertEqual(MusicService.clampVolume(-5), 0)
        XCTAssertEqual(MusicService.clampVolume(130), 100)
        XCTAssertEqual(MusicService.clampVolume(40), 40)
    }

    func testKeyboardBacklightShowsOnlyChangesMadeOutsideTheApp() {
        XCTAssertTrue(KeyboardBacklight.shouldShow(previous: 0.25, current: 0.5, appliedByApp: nil))
        XCTAssertFalse(KeyboardBacklight.shouldShow(previous: 0.25, current: 0.5, appliedByApp: 0.5))
        XCTAssertFalse(KeyboardBacklight.shouldShow(previous: 0.5, current: 0.5, appliedByApp: nil))
        XCTAssertFalse(KeyboardBacklight.shouldShow(previous: nil, current: 0.5, appliedByApp: nil))
    }

    func testBrowserMediaAnswerIsReadFromTheEnd() {
        let now = BrowserMusic.parse("Song | Live|0|12.5|200", bundleID: "com.google.Chrome", browser: "Chrome")
        XCTAssertEqual(now?.title, "Song | Live")
        XCTAssertEqual(now?.playing, true)
        XCTAssertEqual(now?.position, 12.5)
        XCTAssertEqual(now?.duration, 200)
        XCTAssertEqual(BrowserMusic.parse("T|1|0|0", bundleID: "x", browser: "x")?.playing, false)
        XCTAssertNil(BrowserMusic.parse("none", bundleID: "x", browser: "x"))
        XCTAssertNotNil(BrowserMusic.script(bundleID: "com.google.Chrome", js: "1"))
        XCTAssertNil(BrowserMusic.script(bundleID: "org.mozilla.firefox", js: "1"))
    }
}
