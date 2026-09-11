import UIKit
import UserNotifications

extension Notification.Name {
    static let reminderWillPresent = Notification.Name("InCaseI4Get.reminderWillPresent")
    static let reminderConfirmRequested = Notification.Name("InCaseI4Get.reminderConfirmRequested")
    static let reminderSnoozeRequested = Notification.Name("InCaseI4Get.reminderSnoozeRequested")
}

enum ReminderActions {
    static let categoryIdentifier = "IN_CASE_I4_GET_REMINDER"
    static let confirmIdentifier = "GOT_IT"
    static let snoozeIdentifier = "SNOOZE_10"
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Self.configureNotificationCategories()
        return true
    }

    static func configureNotificationCategories() {
        UNUserNotificationCenter.current().setNotificationCategories(
            [reminderCategory]
        )
    }

    private static var reminderCategory: UNNotificationCategory {
        let confirm = UNNotificationAction(
            identifier: ReminderActions.confirmIdentifier,
            title: AppLanguage.current.text(.alertGotIt),
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: ReminderActions.snoozeIdentifier,
            title: AppLanguage.current.text(.alertSnoozeAction),
            options: []
        )
        return UNNotificationCategory(
            identifier: ReminderActions.categoryIdentifier,
            actions: [confirm, snooze],
            intentIdentifiers: [],
            options: []
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        postReminderEvent(name: .reminderWillPresent, userInfo: notification.request.content.userInfo)
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case ReminderActions.confirmIdentifier:
            postReminderEvent(name: .reminderConfirmRequested, userInfo: userInfo, storeKind: .confirm)
        case ReminderActions.snoozeIdentifier:
            postReminderEvent(name: .reminderSnoozeRequested, userInfo: userInfo, storeKind: .snooze)
        default:
            postReminderEvent(name: .reminderWillPresent, userInfo: userInfo, storeKind: .open)
        }
    }

    private func postReminderEvent(
        name: Notification.Name,
        userInfo: [AnyHashable: Any],
        storeKind: PendingActionKind? = nil
    ) {
        guard
            let rawID = userInfo[NotificationScheduler.reminderIDKey] as? String,
            let reminderID = UUID(uuidString: rawID)
        else {
            return
        }

        if let storeKind {
            PendingActionStore.enqueue(reminderID, kind: storeKind)
        }
        NotificationCenter.default.post(name: name, object: reminderID)
    }
}
