import SwiftData
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Query(sort: \ReminderItem.fireDate) private var reminders: [ReminderItem]

    @State private var activeAddFlow: AddFlow?
    @State private var isShowingSettings = false
    @State private var presentedReminder: ReminderItem?

    private var activeReminders: [ReminderItem] {
        reminders.filter { !$0.isCompleted && !$0.shouldBeRemoved(at: Date()) }
    }

    private var todayReminders: [ReminderItem] {
        activeReminders.filter { Calendar.current.isDateInToday($0.fireDate) }
    }

    private var upcomingReminders: [ReminderItem] {
        activeReminders.filter { !Calendar.current.isDateInToday($0.fireDate) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeReminders.isEmpty {
                    ContentUnavailableView(
                        "Nothing scheduled",
                        systemImage: "bell.badge",
                        description: Text("Speak or type a one-line reminder.")
                    )
                } else {
                    reminderList
                }
            }
            .navigationTitle("InCaseI4Get")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
            .sheet(item: $activeAddFlow) { flow in
                AddReminderView(source: flow.source)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .fullScreenCover(item: $presentedReminder) { reminder in
                ReminderAlertView(
                    reminder: reminder,
                    onConfirm: {
                        presentedReminder = nil
                        completeCurrentReminder(id: reminder.id)
                    },
                    onSnooze: {
                        presentedReminder = nil
                        snoozeReminder(id: reminder.id)
                    }
                )
            }
            .task {
                await handleLaunchTasks()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { @MainActor in
                        await handleForegroundTasks()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .reminderWillPresent)) { note in
                guard let id = note.object as? UUID else { return }
                presentReminder(id: id)
            }
            .onReceive(NotificationCenter.default.publisher(for: .reminderConfirmRequested)) { note in
                guard let id = note.object as? UUID else { return }
                completeCurrentReminder(id: id)
            }
            .onReceive(NotificationCenter.default.publisher(for: .reminderSnoozeRequested)) { note in
                guard let id = note.object as? UUID else { return }
                snoozeReminder(id: id)
            }
        }
    }

    private var reminderList: some View {
        List {
            Section("Today") {
                if todayReminders.isEmpty {
                    Text("Nothing today")
                        .foregroundStyle(.secondary)
                } else {
                    rows(for: todayReminders)
                }
            }
            Section("Upcoming") {
                if upcomingReminders.isEmpty {
                    Text("Nothing later")
                        .foregroundStyle(.secondary)
                } else {
                    rows(for: upcomingReminders)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func rows(for items: [ReminderItem]) -> some View {
        ForEach(items) { item in
            ReminderRowView(reminder: item) {
                completeCurrentReminder(id: item.id)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    deleteReminder(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    completeCurrentReminder(id: item.id)
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
    }

    private var bottomBar: some View {
        ZStack {
            HStack {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray6), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")

                Spacer()

                Button {
                    activeAddFlow = AddFlow(source: .text)
                } label: {
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray6), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Type a reminder")
            }

            Button {
                activeAddFlow = AddFlow(source: .voice)
            } label: {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 68, height: 68)
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 27, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text("Speak")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create reminder by voice")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func handleLaunchTasks() async {
        await handleForegroundTasks()

        for id in PendingActionStore.drain(kind: .open) {
            presentReminder(id: id)
        }
        for id in PendingActionStore.drain(kind: .confirm) {
            completeCurrentReminder(id: id)
        }
        for id in PendingActionStore.drain(kind: .snooze) {
            snoozeReminder(id: id)
        }
    }

    private func handleForegroundTasks() async {
        cleanupExpiredReminders()
        rollForwardRecurringReminders()
        await NotificationScheduler.reschedule(activeReminders)
    }

    private func cleanupExpiredReminders() {
        for item in reminders where item.shouldBeRemoved(at: Date()) {
            modelContext.delete(item)
        }
        try? modelContext.save()
    }

    private func rollForwardRecurringReminders() {
        let calendar = Calendar.current
        let now = Date()
        for item in reminders where !item.isCompleted && item.repeatRule != .once {
            if let endDate = item.repeatEndDate,
               now > ReminderItem.endOfLocalDay(for: endDate, calendar: calendar) {
                modelContext.delete(item)
                continue
            }
            if item.fireDate < now {
                item.fireDate = item.nextOccurrence(after: now, calendar: calendar) ?? item.fireDate
            }
        }
        try? modelContext.save()
    }

    private func presentReminder(id: UUID) {
        guard presentedReminder == nil, let item = find(id: id) else { return }
        presentedReminder = item
    }

    private func completeCurrentReminder(id: UUID) {
        guard let item = find(id: id) else { return }

        Task { @MainActor in
            await NotificationScheduler.completeCurrent(item)
            try? modelContext.save()
            if item.shouldBeRemoved(at: Date()) {
                modelContext.delete(item)
                try? modelContext.save()
            }
        }
    }

    private func snoozeReminder(id: UUID) {
        guard let item = find(id: id) else { return }
        Task { @MainActor in
            await NotificationScheduler.snooze(item)
            try? modelContext.save()
        }
    }

    private func deleteReminder(_ item: ReminderItem) {
        Task { @MainActor in
            await NotificationScheduler.cancel(item)
            modelContext.delete(item)
            try? modelContext.save()
        }
    }

    private func find(id: UUID) -> ReminderItem? {
        reminders.first { $0.id == id }
    }

    private struct AddFlow: Identifiable {
        let id = UUID()
        let source: ReminderSource
    }
}

struct ReminderAlertView: View {
    let reminder: ReminderItem
    let onConfirm: () -> Void
    let onSnooze: () -> Void

    @Environment(AppSettings.self) private var settings
    @StateObject private var speaker = SpeechService()
    @State private var flashOn = false

    private var speechLocale: String {
        AppLanguage(rawValue: reminder.languageCode)?.speechLocale ?? "en-US"
    }

    private var reminderDateText: String {
        reminder.fireDate.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            if settings.flashEnabled {
                Color.orange
                    .opacity(flashOn ? 0.55 : 0)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.25), value: flashOn)
            }

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "exclamationmark.bell.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text("Reminder")
                        .font(.headline)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(reminder.title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                    Text(reminderDateText)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    if reminder.repeatRule != .once {
                        Label(reminder.repeatRule.displayName, systemImage: "repeat")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    Button(action: onConfirm) {
                        Label("Got it", systemImage: "checkmark.circle.fill")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: onSnooze) {
                        Label("Snooze 10 min", systemImage: "clock.arrow.circlepath")
                            .font(.body.bold())
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
        .task {
            startMultimodalAlert()
        }
    }

    private func startMultimodalAlert() {
        if settings.ttsEnabled {
            speaker.speak(
                "It's time. \(reminder.title). Don't forget.",
                languageCode: speechLocale,
                volume: settings.speechVolume
            )
        }

        let generator = UINotificationFeedbackGenerator()
        generator.prepare()

        Task {
            while !Task.isCancelled {
                if settings.hapticsEnabled {
                    generator.notificationOccurred(.warning)
                }
                if settings.flashEnabled {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        flashOn.toggle()
                    }
                }
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }
}
