import Foundation

enum ReminderParseStatus: String, Equatable {
    case complete
    case partial
    case failed
}

struct ReminderDraft: Identifiable {
    let id: UUID
    var rawInput: String
    var source: ReminderSource
    var languageCode: String
    var title: String
    var note: String
    var fireDate: Date?
    var repeatRule: ReminderRepeat
    var repeatEndDate: Date?
    var earlyMinutes: Int
    var strikeEnabled: Bool
    var parseStatus: ReminderParseStatus

    init(
        id: UUID = UUID(),
        rawInput: String = "",
        source: ReminderSource,
        languageCode: String,
        title: String = "",
        note: String = "",
        fireDate: Date? = nil,
        repeatRule: ReminderRepeat = .once,
        repeatEndDate: Date? = nil,
        earlyMinutes: Int = 5,
        strikeEnabled: Bool = true,
        parseStatus: ReminderParseStatus = .partial
    ) {
        self.id = id
        self.rawInput = rawInput
        self.source = source
        self.languageCode = languageCode
        self.title = title
        self.note = note
        self.fireDate = fireDate
        self.repeatRule = repeatRule
        self.repeatEndDate = repeatEndDate
        self.earlyMinutes = earlyMinutes
        self.strikeEnabled = strikeEnabled
        self.parseStatus = parseStatus
    }

    init(reminder: ReminderItem) {
        self.init(
            id: reminder.id,
            rawInput: reminder.title,
            source: reminder.source,
            languageCode: reminder.languageCode,
            title: reminder.title,
            note: reminder.note,
            fireDate: reminder.fireDate,
            repeatRule: reminder.repeatRule,
            repeatEndDate: reminder.repeatEndDate,
            earlyMinutes: reminder.earlyMinutes,
            strikeEnabled: reminder.strikeEnabled,
            parseStatus: .complete
        )
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool {
        !trimmedTitle.isEmpty && fireDate != nil && parseStatus != .failed
    }
}
