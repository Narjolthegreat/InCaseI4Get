import SwiftUI

struct ReminderRowView: View {
    let reminder: ReminderItem
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 32, height: 32)
            .accessibilityLabel("Mark as done")

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.body)
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

            Spacer(minLength: 8)

            Text(reminder.fireDate, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
