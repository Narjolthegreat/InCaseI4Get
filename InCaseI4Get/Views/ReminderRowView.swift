import SwiftUI

enum ReminderUrgencyScale {
    static let horizon: TimeInterval = 30 * 24 * 60 * 60

    static func progress(fireDate: Date, relativeTo now: Date) -> Double {
        let secondsUntilDue = fireDate.timeIntervalSince(now)
        guard secondsUntilDue > 0 else { return 0 }

        let daysUntilDue = secondsUntilDue / (24 * 60 * 60)
        let normalized = log1p(daysUntilDue) / log1p(horizon / (24 * 60 * 60))
        return min(max(normalized, 0), 1)
    }

    static func hue(fireDate: Date, relativeTo now: Date) -> Double {
        progress(fireDate: fireDate, relativeTo: now) * 0.33
    }
}

struct ReminderRowView: View {
    let reminder: ReminderItem
    let now: Date

    var body: some View {
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
                        Label(reminder.repeatRule.displayName, systemImage: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if reminder.earlyMinutes > 0 {
                        Text("Early \(reminder.earlyMinutes) min")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            Text(reminder.fireDate, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: false)

            ReminderUrgencySphere(
                fireDate: reminder.fireDate,
                referenceDate: now
            )
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ReminderRow")
    }
}

private struct ReminderUrgencySphere: View {
    let fireDate: Date
    let referenceDate: Date

    private var progress: Double {
        ReminderUrgencyScale.progress(
            fireDate: fireDate,
            relativeTo: referenceDate
        )
    }

    private var sphereColor: Color {
        Color(
            hue: progress * 0.33,
            saturation: 0.82,
            brightness: 0.92
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.92),
                            sphereColor.opacity(0.96),
                            sphereColor
                        ],
                        center: UnitPoint(x: 0.3, y: 0.24),
                        startRadius: 0,
                        endRadius: 18
                    )
                )

            Circle()
                .strokeBorder(.white.opacity(0.38), lineWidth: 0.8)

            Ellipse()
                .fill(.white.opacity(0.5))
                .frame(width: 6, height: 4)
                .blur(radius: 0.4)
                .offset(x: -4, y: -5)
        }
        .frame(width: 20, height: 20)
        .shadow(color: sphereColor.opacity(0.42), radius: 3, x: 0, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time until reminder")
        .accessibilityValue(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let seconds = fireDate.timeIntervalSince(referenceDate)
        if seconds <= 0 {
            return "Due now or overdue"
        }
        if seconds < 60 * 60 {
            return "Due within an hour"
        }
        if seconds < 24 * 60 * 60 {
            return "Due today"
        }
        if seconds < 7 * 24 * 60 * 60 {
            return "Due this week"
        }
        if seconds < 30 * 24 * 60 * 60 {
            return "Due within a month"
        }
        return "More than a month away"
    }
}
