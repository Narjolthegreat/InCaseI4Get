import Foundation
import SwiftData

enum ReminderStoreError: Error {
    case notificationPermissionDenied
    case notificationSchedulingFailed(Error)
    case emptyTitle
    case missingDate
    case persistenceFailed(Error)
}

struct ReminderMutationOutcome {
    let item: ReminderItem
    let notificationWarning: Bool
}

@MainActor
enum ReminderStore {
    static func create(
        from draft: ReminderDraft,
        in modelContext: ModelContext
    ) async throws -> ReminderMutationOutcome {
        let item = try makeItem(from: draft)
        guard await NotificationScheduler.ensureAuthorization() else {
            throw ReminderStoreError.notificationPermissionDenied
        }

        modelContext.insert(item)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(item)
            throw ReminderStoreError.persistenceFailed(error)
        }

        return try await finalizePendingCreation(item, in: modelContext)
    }

    static func finalizePendingCreation(
        _ item: ReminderItem,
        in modelContext: ModelContext
    ) async throws -> ReminderMutationOutcome {
        do {
            item.notificationState = try await schedule(item)
            try modelContext.save()
        } catch {
            await NotificationScheduler.cancel(item)
            modelContext.delete(item)
            try? modelContext.save()
            throw ReminderStoreError.notificationSchedulingFailed(error)
        }

        return ReminderMutationOutcome(
            item: item,
            notificationWarning: false
        )
    }

    static func update(
        _ item: ReminderItem,
        from draft: ReminderDraft,
        in modelContext: ModelContext
    ) async throws -> ReminderMutationOutcome {
        guard !draft.trimmedTitle.isEmpty else {
            throw ReminderStoreError.emptyTitle
        }
        guard draft.fireDate != nil else {
            throw ReminderStoreError.missingDate
        }

        let snapshot = ReminderSnapshot(item)
        apply(draft, to: item)

        do {
            try modelContext.save()
        } catch {
            snapshot.restore(item)
            throw ReminderStoreError.persistenceFailed(error)
        }

        await NotificationScheduler.cancel(item)
        let notificationWarning: Bool
        do {
            item.notificationState = try await schedule(item)
            try modelContext.save()
            notificationWarning = false
        } catch {
            notificationWarning = true
        }

        return ReminderMutationOutcome(
            item: item,
            notificationWarning: notificationWarning
        )
    }

    private static func makeItem(
        from draft: ReminderDraft
    ) throws -> ReminderItem {
        let title = draft.trimmedTitle
        guard !title.isEmpty else {
            throw ReminderStoreError.emptyTitle
        }
        guard let fireDate = draft.fireDate else {
            throw ReminderStoreError.missingDate
        }

        return ReminderItem(
            id: draft.id,
            title: title,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
            fireDate: fireDate,
            repeatRule: draft.repeatRule,
            repeatEndDate: resolvedEndDate(for: draft, fireDate: fireDate),
            source: draft.source,
            languageCode: draft.languageCode,
            earlyMinutes: draft.earlyMinutes,
            strikeEnabled: draft.strikeEnabled
        )
    }

    private static func apply(
        _ draft: ReminderDraft,
        to item: ReminderItem
    ) {
        item.title = draft.trimmedTitle
        item.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        item.fireDate = draft.fireDate ?? item.fireDate
        item.repeatRule = draft.repeatRule
        item.repeatEndDate = resolvedEndDate(
            for: draft,
            fireDate: item.fireDate
        )
        item.source = draft.source
        item.languageCode = draft.languageCode
        item.earlyMinutes = draft.earlyMinutes
        item.strikeEnabled = draft.strikeEnabled
    }

    private static func resolvedEndDate(
        for draft: ReminderDraft,
        fireDate: Date
    ) -> Date? {
        guard draft.repeatRule != .once else { return nil }
        if let endDate = draft.repeatEndDate {
            return endDate
        }
        return Calendar.current.date(
            byAdding: .day,
            value: 7,
            to: fireDate
        )
    }

    private static func schedule(
        _ item: ReminderItem
    ) async throws -> ReminderNotificationState {
        let usesCustomSound = try await NotificationScheduler.schedule(item)
        return usesCustomSound
            ? .scheduledWithVoice
            : .scheduledWithDefaultSound
    }
}

private struct ReminderSnapshot {
    let title: String
    let note: String
    let fireDate: Date
    let repeatRule: ReminderRepeat
    let repeatEndDate: Date?
    let source: ReminderSource
    let languageCode: String
    let earlyMinutes: Int
    let strikeEnabled: Bool

    init(_ item: ReminderItem) {
        title = item.title
        note = item.note
        fireDate = item.fireDate
        repeatRule = item.repeatRule
        repeatEndDate = item.repeatEndDate
        source = item.source
        languageCode = item.languageCode
        earlyMinutes = item.earlyMinutes
        strikeEnabled = item.strikeEnabled
    }

    func restore(_ item: ReminderItem) {
        item.title = title
        item.note = note
        item.fireDate = fireDate
        item.repeatRule = repeatRule
        item.repeatEndDate = repeatEndDate
        item.source = source
        item.languageCode = languageCode
        item.earlyMinutes = earlyMinutes
        item.strikeEnabled = strikeEnabled
    }
}
