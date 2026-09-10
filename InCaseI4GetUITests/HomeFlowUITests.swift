import XCTest

final class HomeFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetData"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func test01HomeEmptyState() {
        XCTAssertTrue(
            app.navigationBars["InCaseI4Get"].waitForExistence(timeout: 5),
            "Home screen did not appear."
        )
        XCTAssertTrue(app.buttons["HomeTypeButton"].exists)
        XCTAssertTrue(app.buttons["HomeSpeakButton"].exists)

        keepScreenshot(named: "01-home-empty")
    }

    func test02OpenSettings() {
        let settingsButton = app.buttons["HomeSettingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 5),
            "Settings screen did not appear."
        )

        keepScreenshot(named: "02-settings")
    }

    func test03OpenTextEntry() {
        let typeButton = app.buttons["HomeTypeButton"]
        XCTAssertTrue(typeButton.waitForExistence(timeout: 5))
        typeButton.tap()

        XCTAssertTrue(
            app.navigationBars["New Reminder"].waitForExistence(timeout: 5),
            "Text reminder screen did not appear."
        )

        keepScreenshot(named: "03-add-text")
    }

    func test04VoiceFlowScreenshotsAndConfirmation() {
        let speakButton = app.buttons["HomeSpeakButton"]
        XCTAssertTrue(speakButton.waitForExistence(timeout: 5))
        speakButton.press(forDuration: 0.8)

        XCTAssertTrue(
            app.staticTexts["正在转成文字"].waitForExistence(timeout: 3),
            "Voice transcription stage did not appear."
        )
        keepScreenshot(named: "05-voice-transcript")

        XCTAssertTrue(
            app.staticTexts["正在概括任务"].waitForExistence(timeout: 4),
            "Voice summary stage did not appear."
        )
        keepScreenshot(named: "06-voice-summary")

        let confirmButton = app.buttons["ConfirmCreateReminderButton"]
        XCTAssertTrue(
            confirmButton.waitForExistence(timeout: 5),
            "Voice reminder confirmation did not appear."
        )
        XCTAssertTrue(app.buttons["CancelVoiceReminderButton"].exists)

        keepScreenshot(named: "07-voice-confirmation")

        let repeatButton = app.buttons["VoiceReminderRepeatButton"]
        XCTAssertTrue(repeatButton.exists)

        XCTAssertFalse(
            app.otherElements["ReminderRow"].exists,
            "Reminder should not be created before confirmation."
        )

        confirmButton.tap()

        XCTAssertTrue(
            app.otherElements["ReminderRow"].waitForExistence(timeout: 6),
            "Voice reminder was not created."
        )
    }

    func test05ProUserCanChooseRepeatRule() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetData", "-proUnlocked"]
        app.launch()

        let speakButton = app.buttons["HomeSpeakButton"]
        XCTAssertTrue(speakButton.waitForExistence(timeout: 5))
        speakButton.press(forDuration: 0.8)

        let confirmButton = app.buttons["ConfirmCreateReminderButton"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 8))

        let repeatMenu = app.buttons["VoiceReminderRepeatMenu"]
        XCTAssertTrue(repeatMenu.exists)
        repeatMenu.tap()
        app.buttons["Weekly"].tap()

        keepScreenshot(named: "09-voice-repeat-unlocked")

        confirmButton.tap()
        XCTAssertTrue(
            app.otherElements["ReminderRow"].waitForExistence(timeout: 6),
            "Pro repeating reminder was not created."
        )
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
