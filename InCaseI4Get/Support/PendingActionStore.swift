import Foundation

enum PendingActionKind: String {
    case confirm
    case snooze
    case open
}

enum PendingActionStore {
    private static func key(for kind: PendingActionKind) -> String {
        "pendingAction.\(kind.rawValue)"
    }

    static func enqueue(_ reminderID: UUID, kind: PendingActionKind) {
        let defaults = UserDefaults.standard
        let key = key(for: kind)
        var values = defaults.stringArray(forKey: key) ?? []
        let raw = reminderID.uuidString
        if !values.contains(raw) {
            values.append(raw)
            defaults.set(values, forKey: key)
        }
    }

    static func drain(kind: PendingActionKind) -> [UUID] {
        let defaults = UserDefaults.standard
        let key = key(for: kind)
        let rawValues = defaults.stringArray(forKey: key) ?? []
        defaults.removeObject(forKey: key)
        return rawValues.compactMap(UUID.init(uuidString:))
    }
}
