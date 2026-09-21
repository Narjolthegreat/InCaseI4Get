import Foundation
import UserNotifications

enum NotificationScheduler {
    static let reminderIDKey = "reminderID"

    static func ensureAuthorization() async -> Bool {
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            return true
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    static func schedule(_ item: ReminderItem) async throws {
        guard !item.isCompleted, !item.shouldBeRemoved(at: Date()) else { return }

        let customSoundsAvailable = await ReminderVoiceStore.prepareSounds(for: item)

        let center = UNUserNotificationCenter.current()
        let requests = makeRequests(
            for: item,
            useCustomSounds: customSoundsAvailable
        )
        let basePrefix = item.id.uuidString
        let pending = await center.pendingNotificationRequests()
        let staleIdentifiers = pending
            .map(\.identifier)
            .filter {
                $0.hasPrefix(basePrefix)
                    && !$0.hasSuffix(".snooze")
            }

        if !staleIdentifiers.isEmpty {
            center.removePendingNotificationRequests(
                withIdentifiers: staleIdentifiers
            )
        }

        for request in requests {
            try await center.add(request)
        }
    }

    static func cancel(_ item: ReminderItem) async {
        let center = UNUserNotificationCenter.current()
        let basePrefix = item.id.uuidString
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(basePrefix) }
        let delivered = await center.deliveredNotifications()
        let deliveredIdentifiers = delivered
            .map(\.request.identifier)
            .filter { $0.hasPrefix(basePrefix) }

        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        if !deliveredIdentifiers.isEmpty {
            center.removeDeliveredNotifications(
                withIdentifiers: deliveredIdentifiers
            )
        }
        ReminderVoiceStore.removeSounds(for: item)
    }

    static func completeCurrent(_ item: ReminderItem) async {
        await cancel(item)
        item.advanceAfterAcknowledgment()
        if !item.isCompleted {
            try? await schedule(item)
        }
    }

    static func snooze(_ item: ReminderItem, minutes: Int = 10) async {
        let center = UNUserNotificationCenter.current()
        let fireDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let soundName = await ReminderVoiceStore.prepareSnoozeSound(
            for: item,
            at: fireDate
        )
        let content = makeContent(
            for: item,
            body: item.title,
            soundName: soundName
        )
        let request = UNNotificationRequest(
            identifier: "\(item.id.uuidString).snooze",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, fireDate.timeIntervalSinceNow),
                repeats: false
            )
        )
        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        try? await center.add(request)
    }

    @discardableResult
    static func reschedule(_ reminders: [ReminderItem]) async -> [Error] {
        var failures: [Error] = []
        for item in reminders where !item.isCompleted {
            do {
                try await schedule(item)
            } catch {
                failures.append(error)
            }
        }
        return failures
    }

    private static func makeRequests(
        for item: ReminderItem,
        useCustomSounds: Bool
    ) -> [UNNotificationRequest] {
        let now = Date()
        let baseID = item.id.uuidString

        if item.repeatRule == .once {
            return oneTimeRequests(
                for: item,
                baseID: baseID,
                useCustomSounds: useCustomSounds
            )
        }

        if let endDate = item.repeatEndDate {
            return finiteRepeatRequests(
                for: item,
                endDate: endDate,
                baseID: baseID,
                now: now,
                useCustomSounds: useCustomSounds
            )
        }

        return openRepeatRequests(
            for: item,
            baseID: baseID,
            now: now,
            useCustomSounds: useCustomSounds
        )
    }

    private static func oneTimeRequests(
        for item: ReminderItem,
        baseID: String,
        useCustomSounds: Bool
    ) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        let now = Date()
        let mainSoundName: String? = useCustomSounds
            ? ReminderVoiceStore.soundName(for: item.id, kind: .main)
            : nil

        if item.earlyMinutes > 0 {
            let earlyDate = item.fireDate.addingTimeInterval(TimeInterval(-item.earlyMinutes * 60))
            if earlyDate > now {
                requests.append(
                    makeRequest(
                        identifier: "\(baseID).early",
                        body: AppLanguage.current.format(
                            .notificationEarlyBody,
                            item.title,
                            item.earlyMinutes
                        ),
                        userInfo: reminderUserInfo(for: item),
                        fireDate: earlyDate,
                        soundName: useCustomSounds
                            ? ReminderVoiceStore.soundName(
                                for: item.id,
                                kind: .early
                            )
                            : nil
                    )
                )
            }
        }

        if item.fireDate > now {
            requests.append(
                makeRequest(
                    identifier: baseID,
                    body: item.title,
                    userInfo: reminderUserInfo(for: item),
                    fireDate: item.fireDate,
                    soundName: mainSoundName
                )
            )
        }

        if item.strikeEnabled {
            let strikeOne = item.fireDate.addingTimeInterval(30)
            let strikeTwo = item.fireDate.addingTimeInterval(60)
            if strikeOne > now {
                requests.append(
                    makeRequest(
                        identifier: "\(baseID).strike-1",
                        body: item.title,
                        userInfo: reminderUserInfo(for: item),
                        fireDate: strikeOne,
                        soundName: mainSoundName
                    )
                )
            }
            if strikeTwo > now {
                requests.append(
                    makeRequest(
                        identifier: "\(baseID).strike-2",
                        body: item.title,
                        userInfo: reminderUserInfo(for: item),
                        fireDate: strikeTwo,
                        soundName: mainSoundName
                    )
                )
            }
        }

        return requests
    }

    private static func finiteRepeatRequests(
        for item: ReminderItem,
        endDate: Date,
        baseID: String,
        now: Date,
        useCustomSounds: Bool
    ) -> [UNNotificationRequest] {
        let endBoundary = ReminderItem.endOfLocalDay(for: endDate)
        var occurrences: [Date] = []
        var cursor = item.fireDate
        let soundName: String? = useCustomSounds
            ? ReminderVoiceStore.soundName(for: item.id, kind: .main)
            : nil

        while occurrences.count < 60 {
            if cursor > endBoundary {
                break
            }
            if cursor >= now {
                occurrences.append(cursor)
            }
            guard let next = item.nextOccurrence(after: cursor) else { break }
            cursor = next
        }

        return occurrences.map { date in
            makeRequest(
                identifier: "\(baseID).occ.\(Int(date.timeIntervalSince1970))",
                body: item.title,
                userInfo: reminderUserInfo(for: item),
                fireDate: date,
                soundName: soundName
            )
        }
    }

    private static func openRepeatRequests(
        for item: ReminderItem,
        baseID: String,
        now: Date,
        useCustomSounds: Bool
    ) -> [UNNotificationRequest] {
        var baseDate = item.fireDate
        if baseDate < now {
            baseDate = item.nextOccurrence(after: now) ?? baseDate
        }

        guard let components = repeatingComponents(for: item, referenceDate: baseDate) else {
            return []
        }

        let content = makeContent(
            for: item,
            body: item.title,
            soundName: useCustomSounds
                ? ReminderVoiceStore.soundName(for: item.id, kind: .main)
                : nil
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: baseID, content: content, trigger: trigger)
        return [request]
    }

    private static func repeatingComponents(
        for item: ReminderItem,
        referenceDate: Date
    ) -> DateComponents? {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: referenceDate)
        let minute = calendar.component(.minute, from: referenceDate)

        switch item.repeatRule {
        case .once:
            return nil
        case .daily:
            return DateComponents(hour: hour, minute: minute)
        case .weekly:
            let weekday = calendar.component(.weekday, from: referenceDate)
            return DateComponents(hour: hour, minute: minute, weekday: weekday)
        case .monthly:
            let day = calendar.component(.day, from: referenceDate)
            return DateComponents(day: day, hour: hour, minute: minute)
        }
    }

    private static func makeRequest(
        identifier: String,
        body: String,
        userInfo: [String: Any],
        fireDate: Date,
        soundName: String?
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "InCaseI4Get"
        content.body = body
        content.sound = soundName.map {
            UNNotificationSound(named: UNNotificationSoundName($0))
        } ?? .default
        content.categoryIdentifier = ReminderActions.categoryIdentifier
        content.userInfo = userInfo

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private static func makeContent(
        for item: ReminderItem,
        body: String,
        soundName: String?
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "InCaseI4Get"
        content.body = body
        content.sound = soundName.map {
            UNNotificationSound(named: UNNotificationSoundName($0))
        } ?? .default
        content.categoryIdentifier = ReminderActions.categoryIdentifier
        content.userInfo = reminderUserInfo(for: item)
        return content
    }

    private static func reminderUserInfo(for item: ReminderItem) -> [String: Any] {
        [reminderIDKey: item.id.uuidString]
    }
}
