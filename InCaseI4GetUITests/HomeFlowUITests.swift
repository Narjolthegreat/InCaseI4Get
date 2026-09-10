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

    func test04VoiceHoldRequiresConfirmation() {
        let speakButton = app.buttons["HomeSpeakButton"]
        XCTAssertTrue(speakButton.waitForExistence(timeout: 5))
        speakButton.press(forDuration: 0.8)

        let confirmButton = app.buttons["ConfirmCreateReminderButton"]
        XCTAssertTrue(
            confirmButton.waitForExistence(timeout: 5),
            "Voice reminder confirmation did not appear."
        )
        XCTAssertTrue(app.buttons["CancelVoiceReminderButton"].exists)

        keepScreenshot(named: "04-voice-confirmation")

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

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
