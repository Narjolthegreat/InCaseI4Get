import SwiftUI

struct ReminderRowView: View {
    @Environment(AppSettings.self) private var settings

    let reminder: ReminderItem
    let onTap: () -> Void

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

            Text(reminder.fireDate, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain)
        .accessibilityHint(settings.language.text(.rowActionsHint))
        .accessibilityIdentifier("ReminderRow")
    }
}
