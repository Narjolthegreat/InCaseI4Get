import XCTest

final class HomeFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func test01HomeEmptyState() {
        launchApp()

        let typeButton = app.buttons["HomeTypeButton"]
        XCTAssertTrue(
            typeButton.waitForExistence(timeout: 5),
            "Home screen did not appear."
        )
        XCTAssertTrue(app.buttons["HomeSpeakButton"].exists)

        keepScreenshot(named: "01-home-empty")
    }

    func test02OpenSettings() {
        launchApp()

        let settingsButton = app.buttons["HomeSettingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 5),
            "Settings screen did not appear."
        )

        keepScreenshot(named: "02-settings")
    }

    func test03TypeFlowCreatesReminder() {
        launchApp()

        let typeButton = app.buttons["HomeTypeButton"]
        XCTAssertTrue(typeButton.waitForExistence(timeout: 5))
        typeButton.tap()

        let sentenceField = app.textFields["TextReminderSentenceField"]
        let parseButton = app.buttons["ParseTextReminderButton"]
        XCTAssertTrue(
            sentenceField.waitForExistence(timeout: 5),
            "Text reminder sentence entry did not appear."
        )
        XCTAssertTrue(app.buttons["CancelTextReminderButton"].exists)
        XCTAssertFalse(parseButton.isEnabled)

        keepScreenshot(named: "03-manual-entry")

        sentenceField.tap()
        sentenceField.typeText(
            "Buy milk on January 1, 2030 at 8:00 PM"
        )
        dismissKeyboardIfNeeded()
        XCTAssertTrue(parseButton.isEnabled)
        parseButton.tap()

        let titleField = app.textFields["VoiceReminderTitleField"]
        let confirmButton = app.buttons["ConfirmCreateReminderButton"]
        XCTAssertTrue(
            confirmButton.waitForExistence(timeout: 5),
            "Parsed reminder confirmation did not appear."
        )
        XCTAssertEqual(titleField.value as? String, "Buy milk")
        XCTAssertTrue(confirmButton.isEnabled)
        keepScreenshot(named: "04-manual-filled")
        confirmButton.tap()

        XCTAssertTrue(
            app.staticTexts["Buy milk"].waitForExistence(timeout: 6),
            "Manual reminder was not created."
        )
        keepScreenshot(named: "05-manual-created")
    }

    func test04VoiceFlowScreenshotsAndConfirmation() {
        launchApp()

        let speakButton = app.buttons["HomeSpeakButton"]
        XCTAssertTrue(speakButton.waitForExistence(timeout: 5))
        speakButton.press(forDuration: 0.8)

        let confirmButton = app.buttons["ConfirmCreateReminderButton"]
        XCTAssertTrue(
            confirmButton.waitForExistence(timeout: 5),
            "Voice reminder confirmation did not appear."
        )
        XCTAssertTrue(app.buttons["CancelVoiceReminderButton"].exists)
        XCTAssertTrue(app.staticTexts["VoiceReminderWeekday"].exists)

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
        XCTAssertTrue(
            app.staticTexts["Take medicine"].exists,
            "Voice reminder title was not preserved."
        )
        keepScreenshot(named: "10-voice-created")
    }

    func test05ProUserCanChooseRepeatRule() {
        launchApp(arguments: ["-proUnlocked"])

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

    func test06TapReminderCanEditAndDelete() {
        launchApp()

        app.buttons["HomeTypeButton"].tap()

        let sentenceField = app.textFields["TextReminderSentenceField"]
        XCTAssertTrue(sentenceField.waitForExistence(timeout: 5))
        sentenceField.tap()
        sentenceField.typeText(
            "Call mom on January 1, 2030 at 8:00 PM"
        )
        dismissKeyboardIfNeeded()

        let parseButton = app.buttons["ParseTextReminderButton"]
        XCTAssertTrue(parseButton.isEnabled)
        parseButton.tap()

        let titleField = app.textFields["VoiceReminderTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        XCTAssertEqual(titleField.value as? String, "Call mom")

        let createButton = app.buttons["ConfirmCreateReminderButton"]
        XCTAssertTrue(createButton.isEnabled)
        createButton.tap()

        let row = app.otherElements["ReminderRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        waitForVoiceOverlayToDismiss()
        waitUntilHittable(row, timeout: 5)

        row.tap()

        let editButton = app.buttons["EditReminderActionButton"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["or"].exists)
        XCTAssertTrue(app.buttons["DeleteReminderActionButton"].exists)
        keepScreenshot(named: "11-reminder-actions")

        editButton.tap()

        let editTitleField = app.textFields["VoiceReminderTitleField"]
        XCTAssertTrue(editTitleField.waitForExistence(timeout: 3))
        XCTAssertEqual(editTitleField.value as? String, "Call mom")
        replaceText(in: editTitleField, with: "Call mom tomorrow")
        dismissKeyboardIfNeeded()

        let saveButton = app.buttons["SaveEditedReminderButton"]
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(
            app.staticTexts["Call mom tomorrow"].waitForExistence(timeout: 6),
            "Edited reminder title was not saved."
        )
        waitForVoiceOverlayToDismiss()

        app.otherElements["ReminderRow"].firstMatch.tap()
        let deleteButton = app.buttons["DeleteReminderActionButton"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()

        waitForDisappearance(app.otherElements["ReminderRow"].firstMatch, timeout: 4)
    }

    func test07MissingTimeFallsBackToManualSelection() {
        launchApp()

        app.buttons["HomeTypeButton"].tap()

        let sentenceField = app.textFields["TextReminderSentenceField"]
        XCTAssertTrue(sentenceField.waitForExistence(timeout: 5))
        sentenceField.tap()
        sentenceField.typeText("Buy milk")
        dismissKeyboardIfNeeded()

        let parseButton = app.buttons["ParseTextReminderButton"]
        XCTAssertTrue(parseButton.isEnabled)
        parseButton.tap()

        let confirmButton = app.buttons["ConfirmCreateReminderButton"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        XCTAssertFalse(confirmButton.isEnabled)

        let chooseTimeButton = app.buttons["ChooseReminderTimeButton"]
        XCTAssertTrue(chooseTimeButton.exists)
        chooseTimeButton.tap()

        XCTAssertTrue(confirmButton.isEnabled)
        keepScreenshot(named: "12-missing-time-selection")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dismissKeyboardIfNeeded() {
        guard app.keyboards.count > 0 else { return }

        let dismissButton = app.buttons["DismissReminderKeyboardButton"]
        if dismissButton.exists {
            tapCenter(of: dismissButton)
            return
        }

        let textDismissButton = app.buttons["DismissTextReminderKeyboardButton"]
        XCTAssertTrue(textDismissButton.waitForExistence(timeout: 2))
        tapCenter(of: textDismissButton)
    }

    private func tapCenter(of element: XCUIElement) {
        element
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .tap()
    }

    private func replaceText(in element: XCUIElement, with text: String) {
        element.tap()
        element.press(forDuration: 1.0)

        let selectAll = app.menuItems["Select All"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 2))
        selectAll.tap()
        element.typeText(text)
    }

    private func waitForDisappearance(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed
        )
    }

    private func waitForVoiceOverlayToDismiss() {
        let createdTitle = app.staticTexts["Reminder created"]
        if createdTitle.exists {
            waitForDisappearance(createdTitle, timeout: 4)
        }

        let updatedTitle = app.staticTexts["Changes saved"]
        if updatedTitle.exists {
            waitForDisappearance(updatedTitle, timeout: 4)
        }
    }

    private func waitUntilHittable(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed
        )
    }

    private func launchApp(arguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetData"] + arguments
        app.launch()
    }
}
