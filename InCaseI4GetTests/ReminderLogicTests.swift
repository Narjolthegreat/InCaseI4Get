import XCTest
@testable import InCaseI4Get

final class ReminderLogicTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testSentenceParserExtractsDailyRepeatRule() {
        let result = ReminderSentenceParser.parse("Take medicine every day at 8:00 PM")

        XCTAssertEqual(result.repeatRule, .daily)
        XCTAssertTrue(result.title.localizedCaseInsensitiveContains("medicine"))
    }

    func testSentenceParserExtractsWeeklyRepeatRule() {
        let result = ReminderSentenceParser.parse("Take out the trash every week")

        XCTAssertEqual(result.repeatRule, .weekly)
        XCTAssertTrue(result.title.localizedCaseInsensitiveContains("trash"))
    }

    func testSentenceParserRemovesPrepositionBeforeDate() {
        let result = ReminderSentenceParser.parse(
            "Take medicine on January 1, 2030 at 8:00 PM"
        )

        XCTAssertEqual(result.title, "Take medicine")
        XCTAssertNotNil(result.fireDate)
    }

    func testDailyReminderAdvancesToNextDay() {
        let start = makeDate(year: 2026, month: 1, day: 1, hour: 9, minute: 0)
        let now = makeDate(year: 2026, month: 1, day: 1, hour: 9, minute: 1)
        let item = makeReminder(fireDate: start, repeatRule: .daily)

        let next = item.nextOccurrence(after: now, calendar: calendar)

        XCTAssertEqual(next, makeDate(year: 2026, month: 1, day: 2, hour: 9, minute: 0))
    }

    func testWeeklyReminderAdvancesToNextWeek() {
        let start = makeDate(year: 2026, month: 1, day: 7, hour: 9, minute: 0)
        let now = makeDate(year: 2026, month: 1, day: 7, hour: 9, minute: 1)
        let item = makeReminder(fireDate: start, repeatRule: .weekly)

        let next = item.nextOccurrence(after: now, calendar: calendar)

        XCTAssertEqual(next, makeDate(year: 2026, month: 1, day: 14, hour: 9, minute: 0))
    }

    func testMonthlyReminderClampsToLastValidDay() {
        let start = makeDate(year: 2026, month: 1, day: 31, hour: 9, minute: 0)
        let now = makeDate(year: 2026, month: 1, day: 31, hour: 9, minute: 1)
        let item = makeReminder(fireDate: start, repeatRule: .monthly)

        let next = item.nextOccurrence(after: now, calendar: calendar)

        XCTAssertEqual(next, makeDate(year: 2026, month: 2, day: 28, hour: 9, minute: 0))
    }

    func testOneTimeReminderExpiresAfterLocalDay() {
        let fireDate = makeDate(year: 2026, month: 1, day: 1, hour: 10, minute: 0)
        let nextDay = makeDate(year: 2026, month: 1, day: 2, hour: 0, minute: 0)
        let item = makeReminder(fireDate: fireDate, repeatRule: .once)

        XCTAssertTrue(item.shouldBeRemoved(at: nextDay, calendar: calendar))
    }

    func testReminderUrgencyMovesFromRedToGreen() {
        let now = makeDate(year: 2026, month: 1, day: 1, hour: 9, minute: 0)
        let imminent = now.addingTimeInterval(60)
        let distant = now.addingTimeInterval(ReminderUrgencyScale.horizon)

        XCTAssertEqual(
            ReminderUrgencyScale.hue(fireDate: imminent, relativeTo: now),
            0,
            accuracy: 0.01
        )
        XCTAssertEqual(
            ReminderUrgencyScale.hue(fireDate: distant, relativeTo: now),
            0.33,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ReminderUrgencyScale.progress(
                fireDate: now.addingTimeInterval(-60),
                relativeTo: now
            ),
            0
        )
    }

    func testAllLanguagesHaveCompleteLocalization() {
        for language in AppLanguage.allCases {
            XCTAssertTrue(
                L10n.isComplete(for: language),
                "\(language.rawValue) is missing localization entries."
            )
        }
    }

    func testActionPromptUsesSelectedLanguage() {
        XCTAssertEqual(AppLanguage.english.text(.commonEdit), "Edit")
        XCTAssertEqual(AppLanguage.english.text(.commonOr), "or")
        XCTAssertEqual(AppLanguage.english.text(.commonDelete), "Delete")
        XCTAssertEqual(AppLanguage.chinese.text(.commonEdit), "重编辑")
        XCTAssertEqual(AppLanguage.chinese.text(.commonOr), "or")
        XCTAssertEqual(AppLanguage.chinese.text(.commonDelete), "删除")
    }

    private func makeReminder(
        fireDate: Date,
        repeatRule: ReminderRepeat
    ) -> ReminderItem {
        ReminderItem(
            title: "Test reminder",
            fireDate: fireDate,
            repeatRule: repeatRule,
            source: .text,
            languageCode: "en"
        )
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}
