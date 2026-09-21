import AVFoundation
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

    func testSentenceParserRemovesRepeatBeforeDateWithoutCorruptingText() {
        let result = ReminderSentenceParser.parse(
            "Take medicine every day at 8:00 PM"
        )

        XCTAssertEqual(result.repeatRule, .daily)
        XCTAssertEqual(result.title, "Take medicine")
        XCTAssertNotNil(result.fireDate)
    }

    func testTextAndVoiceDraftsUseTheSameParsingResult() {
        let parser = ReminderParser()
        let input = "Take medicine on January 1, 2030 at 8:00 PM"
        let textDraft = parser.makeDraft(
            from: input,
            source: .text,
            language: .english,
            earlyMinutes: 5,
            strikeEnabled: true
        )
        let voiceDraft = parser.makeDraft(
            from: input,
            source: .voice,
            language: .english,
            earlyMinutes: 5,
            strikeEnabled: true
        )

        XCTAssertEqual(textDraft.title, voiceDraft.title)
        XCTAssertEqual(textDraft.fireDate, voiceDraft.fireDate)
        XCTAssertEqual(textDraft.repeatRule, voiceDraft.repeatRule)
        XCTAssertEqual(textDraft.parseStatus, voiceDraft.parseStatus)
        XCTAssertEqual(textDraft.source, .text)
        XCTAssertEqual(voiceDraft.source, .voice)
    }

    func testDraftWithoutTimeIsPartialInsteadOfGuessing() {
        let draft = ReminderParser().makeDraft(
            from: "Buy milk",
            source: .text,
            language: .english,
            earlyMinutes: 5,
            strikeEnabled: true
        )

        XCTAssertEqual(draft.title, "Buy milk")
        XCTAssertNil(draft.fireDate)
        XCTAssertEqual(draft.parseStatus, .partial)
        XCTAssertFalse(draft.canSave)
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

    func testReminderSpeechUsesExactTime() {
        let fireDate = Calendar.current.date(
            from: DateComponents(
                year: 2026,
                month: 1,
                day: 1,
                hour: 15,
                minute: 0
            )
        )!
        let timeText = ReminderVoiceStore.timeText(
            for: fireDate,
            language: .english
        )
        let speech = AppLanguage.english.format(
            .alertSpeech,
            timeText,
            "Take medicine"
        )

        XCTAssertTrue(speech.contains("3:00"))
        XCTAssertTrue(speech.contains("Take medicine"))
        XCTAssertFalse(speech.contains("It's time"))
    }

    func testReminderSoundNamesAreStable() {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        XCTAssertEqual(
            ReminderVoiceStore.soundName(for: id, kind: .main),
            "reminder-11111111-1111-1111-1111-111111111111-main.caf"
        )
        XCTAssertEqual(
            ReminderVoiceStore.soundName(for: id, kind: .early),
            "reminder-11111111-1111-1111-1111-111111111111-early.caf"
        )
    }

    func testReminderVoiceRendersAudioFile() async throws {
        guard ProcessInfo.processInfo.environment["RUN_VOICE_RENDER_TEST"] == "1" else {
            throw XCTSkip("Voice rendering probe is disabled.")
        }
        guard AVSpeechSynthesisVoice(
            language: AppLanguage.english.speechLocale
        ) != nil else {
            throw XCTSkip("CI runner has no usable English TTS voice.")
        }

        let id = UUID()
        let item = ReminderItem(
            id: id,
            title: "Take medicine",
            fireDate: Date().addingTimeInterval(60 * 60),
            repeatRule: .daily,
            source: .text,
            languageCode: AppLanguage.english.rawValue,
            earlyMinutes: 0,
            strikeEnabled: false
        )
        defer {
            ReminderVoiceStore.removeSounds(for: id)
        }

        let rendered = await ReminderVoiceStore.prepareSounds(for: item)
        let soundURL = ReminderVoiceStore.soundURL(for: id, kind: .main)

        XCTAssertTrue(rendered)
        XCTAssertTrue(FileManager.default.fileExists(atPath: soundURL.path))

        let attributes = try FileManager.default.attributesOfItem(
            atPath: soundURL.path
        )
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(fileSize, 0)

        let audioFile = try AVAudioFile(forReading: soundURL)
        XCTAssertGreaterThan(audioFile.length, 0)
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
