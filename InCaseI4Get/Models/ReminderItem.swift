import Foundation
import SwiftData

enum ReminderRepeat: String, CaseIterable, Identifiable {
    case once
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .once: "Once"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }
}

enum ReminderSource: String {
    case voice
    case text
}

@Model
final class ReminderItem: Identifiable {
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
    }

    var repeatRule: ReminderRepeat {
        get { ReminderRepeat(rawValue: repeatRaw) ?? .once }
        set { repeatRaw = newValue.rawValue }
    }

    var source: ReminderSource {
        get { ReminderSource(rawValue: sourceRaw) ?? .text }
        set { sourceRaw = newValue.rawValue }
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
            return now >= Self.endOfLocalDay(for: fireDate, calendar: calendar)
        }
        if let endDate = repeatEndDate {
            return now > Self.endOfLocalDay(for: endDate, calendar: calendar)
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

struct ReminderSentenceParser {
    struct Result {
        var title: String
        var fireDate: Date?
        var repeatRule: ReminderRepeat
    }

    private static let repeatExpressions: [ReminderRepeat: [String]] = [
        .daily: [
            "daily", "every day", "everyday", "each day",
            "毎日", "每日", "每天",
            "매일",
            "tous les jours", "quotidien", "chaque jour",
            "täglich", "jeden tag",
            "her gün", "günlük",
            "todos los días", "diario", "cada día",
            "todos os dias", "diário", "cada dia",
            "каждый день", "ежедневно"
        ],
        .weekly: [
            "weekly", "every week", "each week",
            "毎週", "每周",
            "매주",
            "chaque semaine", "hebdomadaire",
            "wöchentlich", "jede woche",
            "her hafta", "haftalık",
            "todas las semanas", "semanal",
            "todas as semanas", "semanal",
            "каждую неделю", "еженедельно"
        ],
        .monthly: [
            "monthly", "every month", "each month",
            "毎月", "每月",
            "매달", "매월",
            "chaque mois", "mensuel",
            "monatlich", "jeden monat",
            "her ay", "aylık",
            "todos los meses", "mensual",
            "todos os meses", "mensal",
            "каждый месяц", "ежемесячно"
        ]
    ]

    static func parse(_ input: String) -> Result {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var mutable = text as NSString
        var repeatRule: ReminderRepeat = .once
        var fireDate: Date?

        for (rule, expressions) in repeatExpressions {
            for expression in expressions where mutable.range(of: expression, options: .caseInsensitive).location != NSNotFound {
                let range = mutable.range(of: expression, options: .caseInsensitive)
                mutable = mutable.replacingCharacters(in: range, with: " ") as NSString
                repeatRule = rule
                break
            }
        }

        let dateResult = detectDate(in: text)
        if let matchedDate = dateResult.date {
            fireDate = matchedDate
            if let range = dateResult.range {
                mutable = mutable.replacingCharacters(in: range, with: " ") as NSString
            }
        }

        var title = mutable as String
        title = title
            .replacingOccurrences(of: " at ", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if title.isEmpty {
            title = text
        }

        return Result(title: title, fireDate: fireDate, repeatRule: repeatRule)
    }

    private static func detectDate(in text: String) -> (date: Date?, range: NSRange?) {
        let types: NSTextCheckingResult.CheckingType = [.date]
        guard let detector = try? NSDataDetector(types: types.rawValue) else {
            return (nil, nil)
        }

        let range = NSRange(location: 0, length: (text as NSString).length)
        let matches = detector.matches(in: text, options: [], range: range)
        guard let match = matches.first else {
            return (nil, nil)
        }
        return (match.date, match.range)
    }
}
