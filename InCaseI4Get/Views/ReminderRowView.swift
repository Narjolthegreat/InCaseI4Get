import Foundation
import SwiftUI

enum ReminderTimeBucket: Equatable {
    case today
    case upcoming
    case expired
}

enum ReminderTimeUrgency: Equatable {
    case normal
    case approaching
    case urgent

    var color: Color {
        switch self {
        case .normal:
            .primary
        case .approaching:
            .orange
        case .urgent:
            .red
        }
    }
}

struct ReminderTimePresentation {
    let primaryText: String
    let secondaryText: String?
    let bucket: ReminderTimeBucket
    let urgency: ReminderTimeUrgency
}

struct ReminderRowView: View {
    @Environment(AppSettings.self) private var settings

    let reminder: ReminderItem
    let now: Date
    let onTap: () -> Void

    var body: some View {
        let time = reminder.timePresentation(
            at: now,
            language: settings.language
        )

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if !reminder.note.isEmpty {
                    Text(reminder.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if reminder.repeatRule != .once {
                        Label(
                            settings.language.text(reminder.repeatRule.localizationKey),
                            systemImage: "repeat"
                        )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if reminder.earlyMinutes > 0 {
                        Text(
                            settings.language.format(
                                .rowEarlyMinutes,
                                reminder.earlyMinutes
                            )
                        )
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(time.primaryText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(time.urgency.color)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)

                if let secondaryText = time.secondaryText {
                    Text(secondaryText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain)
        .accessibilityHint(settings.language.text(.rowActionsHint))
        .accessibilityIdentifier("ReminderRow")
    }
}

extension ReminderItem {
    func timePresentation(
        at now: Date,
        language: AppLanguage,
        calendar: Calendar = .current
    ) -> ReminderTimePresentation {
        let secondsUntilDue = fireDate.timeIntervalSince(now)

        if secondsUntilDue <= 0 {
            let secondsOverdue = -secondsUntilDue

            if secondsOverdue < 60 {
                return ReminderTimePresentation(
                    primaryText: L10n.text(.rowDueNow, language: language),
                    secondaryText: clockTimeText(
                        for: fireDate,
                        language: language,
                        calendar: calendar
                    ),
                    bucket: .today,
                    urgency: .urgent
                )
            }

            let totalMinutes = Int(floor(secondsOverdue / 60))
            let primaryText: String

            if totalMinutes < 60 {
                primaryText = L10n.format(
                    .rowOverdueMinutes,
                    language: language,
                    arguments: [totalMinutes]
                )
            } else {
                let hours = totalMinutes / 60
                let minutes = totalMinutes % 60
                primaryText = minutes == 0
                    ? L10n.format(
                        .rowOverdueHours,
                        language: language,
                        arguments: [hours]
                    )
                    : L10n.format(
                        .rowOverdueHoursMinutes,
                        language: language,
                        arguments: [hours, minutes]
                    )
            }

            let secondaryText: String?
            if repeatRule == .once {
                secondaryText = clockTimeText(
                    for: fireDate,
                    language: language,
                    calendar: calendar
                )
            } else if let next = nextOccurrence(after: now, calendar: calendar),
                      nextOccurrenceIsAllowed(next, calendar: calendar) {
                secondaryText = L10n.format(
                    .rowNextOccurrence,
                    language: language,
                    arguments: [
                        semanticTimeText(
                            for: next,
                            relativeTo: now,
                            language: language,
                            calendar: calendar
                        )
                    ]
                )
            } else {
                secondaryText = nil
            }

            return ReminderTimePresentation(
                primaryText: primaryText,
                secondaryText: secondaryText,
                bucket: .expired,
                urgency: .urgent
            )
        }

        if secondsUntilDue <= 60 * 60 {
            let totalMinutes = Int(floor(secondsUntilDue / 60))
            let primaryText = totalMinutes == 0
                ? L10n.text(.rowLessThanMinute, language: language)
                : L10n.format(
                    .rowInMinutes,
                    language: language,
                    arguments: [totalMinutes]
                )

            return ReminderTimePresentation(
                primaryText: primaryText,
                secondaryText: clockTimeText(
                    for: fireDate,
                    language: language,
                    calendar: calendar
                ),
                bucket: calendar.isDate(fireDate, inSameDayAs: now)
                    ? .today
                    : .upcoming,
                urgency: .approaching
            )
        }

        return ReminderTimePresentation(
            primaryText: semanticTimeText(
                for: fireDate,
                relativeTo: now,
                language: language,
                calendar: calendar
            ),
            secondaryText: nil,
            bucket: calendar.isDate(fireDate, inSameDayAs: now)
                ? .today
                : .upcoming,
            urgency: .normal
        )
    }

    private func nextOccurrenceIsAllowed(
        _ next: Date,
        calendar: Calendar
    ) -> Bool {
        guard let repeatEndDate else { return true }
        return next <= Self.endOfLocalDay(
            for: repeatEndDate,
            calendar: calendar
        )
    }
}

private func semanticTimeText(
    for date: Date,
    relativeTo now: Date,
    language: AppLanguage,
    calendar: Calendar
) -> String {
    let dayText = dayRelationText(
        for: date,
        relativeTo: now,
        language: language,
        calendar: calendar
    )
    let exactTime = clockTimeText(
        for: date,
        language: language,
        calendar: calendar
    )

    guard language == .chinese else {
        return L10n.format(
            .rowDayAndTime,
            language: language,
            arguments: [dayText, exactTime]
        )
    }

    let hour = calendar.component(.hour, from: date)
    return "\(dayText)\(chinesePeriodText(for: hour))\(exactTime)"
}

private func dayRelationText(
    for date: Date,
    relativeTo now: Date,
    language: AppLanguage,
    calendar: Calendar
) -> String {
    let today = calendar.startOfDay(for: now)
    let target = calendar.startOfDay(for: date)
    let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0

    switch days {
    case 0:
        return L10n.text(.homeToday, language: language)
    case 1:
        return L10n.text(.homeTomorrow, language: language)
    case 2:
        return L10n.text(.homeDayAfterTomorrow, language: language)
    default:
        return formattedDateText(
            for: date,
            dayDistance: days,
            relativeTo: now,
            language: language,
            calendar: calendar
        )
    }
}

private func formattedDateText(
    for date: Date,
    dayDistance: Int,
    relativeTo now: Date,
    language: AppLanguage,
    calendar: Calendar
) -> String {
    let formatter = DateFormatter()
    formatter.locale = language.locale
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone

    if (3...6).contains(dayDistance) {
        formatter.setLocalizedDateFormatFromTemplate("EEE")
    } else if calendar.component(.year, from: date)
        == calendar.component(.year, from: now) {
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
    } else {
        formatter.setLocalizedDateFormatFromTemplate("y MMM d")
    }

    return formatter.string(from: date)
}

private func clockTimeText(
    for date: Date,
    language: AppLanguage,
    calendar: Calendar
) -> String {
    let formatter = DateFormatter()
    formatter.locale = language.locale
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateStyle = .none

    if language == .chinese {
        formatter.dateFormat = "h:mm"
    } else {
        formatter.timeStyle = .short
    }

    return formatter.string(from: date)
}

private func chinesePeriodText(for hour: Int) -> String {
    switch hour {
    case 0..<5:
        "凌晨"
    case 5..<8:
        "早上"
    case 8..<11:
        "上午"
    case 11..<13:
        "中午"
    case 13..<18:
        "下午"
    default:
        "晚上"
    }
}
