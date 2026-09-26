import Foundation
import SwiftData

enum ReminderRepeat: String, CaseIterable, Identifiable {
    case once
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var localizationKey: L10n.Key {
        switch self {
        case .once: .repeatOnce
        case .daily: .repeatDaily
        case .weekly: .repeatWeekly
        case .monthly: .repeatMonthly
        }
    }
}

enum ReminderSource: String, Equatable {
    case voice
    case text
}

enum ReminderNotificationState: String, Equatable {
    case pending
    case scheduledWithVoice
    case scheduledWithDefaultSound
}

@Model
final class ReminderItem: Identifiable {
    static let expiredRetention: TimeInterval = 24 * 60 * 60

    @Attribute(.unique) var id: UUID
    var title: String
    var note: String
    var fireDate: Date
    var repeatRaw: String
    var repeatEndDate: Date?
    var sourceRaw: String
    var languageCode: String
    var earlyMinutes: Int
    var strikeEnabled: Bool
    var isCompleted: Bool
    var completedAt: Date?
    var acknowledgedAt: Date?
    var createdAt: Date
    var notificationStateRaw: String?

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        fireDate: Date,
        repeatRule: ReminderRepeat = .once,
        repeatEndDate: Date? = nil,
        source: ReminderSource,
        languageCode: String,
        earlyMinutes: Int = 5,
        strikeEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.fireDate = fireDate
        self.repeatRaw = repeatRule.rawValue
        self.repeatEndDate = repeatEndDate
        self.sourceRaw = source.rawValue
        self.languageCode = languageCode
        self.earlyMinutes = earlyMinutes
        self.strikeEnabled = strikeEnabled
        self.isCompleted = false
        self.completedAt = nil
        self.acknowledgedAt = nil
        self.createdAt = Date()
        self.notificationStateRaw = ReminderNotificationState.pending.rawValue
    }

    var repeatRule: ReminderRepeat {
        get { ReminderRepeat(rawValue: repeatRaw) ?? .once }
        set { repeatRaw = newValue.rawValue }
    }

    var source: ReminderSource {
        get { ReminderSource(rawValue: sourceRaw) ?? .text }
        set { sourceRaw = newValue.rawValue }
    }

    var notificationState: ReminderNotificationState {
        get {
            notificationStateRaw.flatMap {
                ReminderNotificationState(rawValue: $0)
            }
                ?? .scheduledWithVoice
        }
        set {
            notificationStateRaw = newValue.rawValue
        }
    }

    var displayTime: Date {
        fireDate
    }

    static func endOfLocalDay(for date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date
    }

    func shouldBeRemoved(at now: Date, calendar: Calendar = .current) -> Bool {
        if isCompleted {
            return true
        }
        if repeatRule == .once {
            return now >= fireDate.addingTimeInterval(Self.expiredRetention)
        }
        if let endDate = repeatEndDate {
            return now >= Self.endOfLocalDay(
                for: endDate,
                calendar: calendar
            ).addingTimeInterval(Self.expiredRetention)
        }
        return false
    }

    func advanceAfterAcknowledgment(now: Date = Date(), calendar: Calendar = .current) {
        acknowledgedAt = now

        if repeatRule == .once {
            complete(now: now)
            return
        }

        guard let next = nextOccurrence(after: now, calendar: calendar) else {
            complete(now: now)
            return
        }

        if let endDate = repeatEndDate, next > Self.endOfLocalDay(for: endDate, calendar: calendar) {
            complete(now: now)
        } else {
            fireDate = next
            isCompleted = false
            completedAt = nil
        }
    }

    func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date? {
        let components = calendar.dateComponents([.hour, .minute], from: fireDate)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0

        switch repeatRule {
        case .once:
            return fireDate > date ? fireDate : nil
        case .daily:
            var candidate = calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: date
            ) ?? date
            if candidate <= date {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            return candidate
        case .weekly:
            let weekday = calendar.component(.weekday, from: fireDate)
            let matching = DateComponents(hour: hour, minute: minute, weekday: weekday)
            return calendar.nextDate(
                after: date,
                matching: matching,
                matchingPolicy: .nextTime,
                direction: .forward
            )
        case .monthly:
            return nextMonthlyOccurrence(
                after: date,
                hour: hour,
                minute: minute,
                calendar: calendar
            )
        }
    }

    private func nextMonthlyOccurrence(
        after date: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date? {
        let requestedDay = calendar.component(.day, from: fireDate)
        let monthAnchor = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        ) ?? date

        for offset in 0..<24 {
            guard let candidateMonth = calendar.date(
                byAdding: .month,
                value: offset,
                to: monthAnchor
            ) else {
                continue
            }
            guard let dayRange = calendar.range(of: .day, in: .month, for: candidateMonth) else {
                continue
            }
            let safeDay = min(requestedDay, dayRange.count)
            var components = calendar.dateComponents([.year, .month], from: candidateMonth)
            components.day = safeDay
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let candidate = calendar.date(from: components) else { continue }
            if candidate > date {
                return candidate
            }
        }
        return nil
    }

    private func complete(now: Date) {
        isCompleted = true
        completedAt = now
    }
}
