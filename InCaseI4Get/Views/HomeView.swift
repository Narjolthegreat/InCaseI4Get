import SwiftData
import SwiftUI
import UIKit

private enum VoiceCapturePhase {
    case listening
    case processing
    case completed(title: String, fireDate: Date)
    case updated(title: String, fireDate: Date)
    case failed(String)
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Query(sort: \ReminderItem.fireDate) private var reminders: [ReminderItem]

    @State private var isShowingSettings = false
    @State private var presentedReminder: ReminderItem?
    @State private var voicePhase: VoiceCapturePhase?
    @State private var voiceDismissTask: Task<Void, Never>?
    @State private var isShowingTextEntry = false
    @State private var textInput = ""
    @State private var pendingReminderDraft: ReminderDraft?
    @State private var isSavingReminder = false
    @State private var saveErrorMessage: String?
    @State private var reminderActionTarget: ReminderItem?
    @State private var reminderBeingEdited: ReminderItem?
    @StateObject private var voiceRecorder = VoiceTranscriber()
    @StateObject private var purchaseManager = PurchaseManager()
    private let reminderParser = ReminderParser()

    private var activeReminders: [ReminderItem] {
        reminders.filter { !$0.isCompleted && !$0.shouldBeRemoved(at: Date()) }
    }

    private var todayReminders: [ReminderItem] {
        activeReminders.filter { Calendar.current.isDateInToday($0.fireDate) }
    }

    private var upcomingReminders: [ReminderItem] {
        activeReminders.filter { !Calendar.current.isDateInToday($0.fireDate) }
    }

    private var homeBackground: Color {
        let color: UIColor = activeReminders.isEmpty
            ? .systemBackground
            : .systemGroupedBackground
        return Color(uiColor: color)
    }

    private var homeActionColor: Color {
        Color(
            red: 0,
            green: 122.0 / 255.0,
            blue: 1
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeReminders.isEmpty {
                    ContentUnavailableView(
                        settings.language.text(.homeEmptyTitle),
                        systemImage: "bell.badge",
                        description: Text(
                            settings.language.text(.homeEmptyDescription)
                        )
                    )
                } else {
                    reminderList
                }
            }
            .background(homeBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HomeHeaderTitle(
                        title: settings.language.text(.appTitle),
                        accentColor: homeActionColor
                    )
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel(settings.language.text(.homeSettings))
                    .accessibilityIdentifier("HomeSettingsButton")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
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
            .overlay {
                if let voicePhase {
                    VoiceCaptureOverlay(
                        phase: voicePhase,
                        transcript: voiceRecorder.transcript,
                        audioLevel: voiceRecorder.audioLevel
                    )
                    .transition(.opacity)
                }
            }
            .overlay {
                if isShowingTextEntry {
                    TextReminderInputView(
                        sentence: $textInput,
                        onParse: parseTextReminder,
                        onCancel: cancelTextReminder
                    )
                    .transition(.opacity)
                }
            }
            .overlay {
                if let pendingReminderDraft {
                    ReminderReviewView(
                        draft: pendingReminderDraft,
                        purchaseManager: purchaseManager,
                        mode: .create,
                        isSaving: isSavingReminder,
                        saveErrorMessage: saveErrorMessage,
                        onCancel: {
                            cancelReminderCreation()
                        },
                        onConfirm: { draft in
                            saveReminder(draft)
                        }
                    )
                    .id(pendingReminderDraft.id)
                    .transition(.opacity)
                }
            }
            .overlay {
                if let reminderActionTarget {
                    ReminderActionPrompt(
                        onEdit: {
                            self.reminderActionTarget = nil
                            saveErrorMessage = nil
                            reminderBeingEdited = reminderActionTarget
                        },
                        onDelete: {
                            self.reminderActionTarget = nil
                            deleteReminder(reminderActionTarget)
                        },
                        onDismiss: {
                            self.reminderActionTarget = nil
                        }
                    )
                    .transition(.opacity)
                }
            }
            .overlay {
                if let reminderBeingEdited {
                    ReminderReviewView(
                        draft: ReminderDraft(reminder: reminderBeingEdited),
                        purchaseManager: purchaseManager,
                        mode: .edit,
                        isSaving: isSavingReminder,
                        saveErrorMessage: saveErrorMessage,
                        onCancel: {
                            cancelReminderEdit()
                        },
                        onConfirm: { draft in
                            saveEditedReminder(
                                reminderBeingEdited,
                                draft: draft
                            )
                        }
                    )
                    .id(reminderBeingEdited.id)
                    .transition(.opacity)
                }
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
            .onChange(of: settings.language) { _, _ in
                AppDelegate.configureNotificationCategories()
                Task { @MainActor in
                    for item in activeReminders {
                        await NotificationScheduler.cancel(item)
                    }
                    await NotificationScheduler.reschedule(activeReminders)
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
        TimelineView(.periodic(from: .now, by: 60)) { context in
            List {
                Section(settings.language.text(.homeToday)) {
                    if todayReminders.isEmpty {
                        Text(settings.language.text(.homeNothingToday))
                            .foregroundStyle(.secondary)
                    } else {
                        rows(for: todayReminders, now: context.date)
                    }
                }
                Section(settings.language.text(.homeUpcoming)) {
                    if upcomingReminders.isEmpty {
                        Text(settings.language.text(.homeNothingLater))
                            .foregroundStyle(.secondary)
                    } else {
                        rows(for: upcomingReminders, now: context.date)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func rows(for items: [ReminderItem], now: Date) -> some View {
        ForEach(items) { item in
            ReminderRowView(reminder: item, now: now) {
                reminderActionTarget = item
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 18) {
            Button {
                // Press-and-hold is handled by the gesture below.
            } label: {
                Label(settings.language.text(.homeSpeak), systemImage: "mic.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(homeActionColor)
            .controlSize(.regular)
            .accessibilityLabel(settings.language.text(.homeVoiceA11y))
            .accessibilityIdentifier("HomeSpeakButton")
            .accessibilityHint(settings.language.text(.homeVoiceHint))
            .onLongPressGesture(
                minimumDuration: 0.1,
                maximumDistance: 60,
                pressing: { isPressing in
                    if isPressing {
                        startVoiceCapture()
                    } else {
                        stopVoiceCapture()
                    }
                },
                perform: {}
            )

            Button {
                showTextEntry()
            } label: {
                Label(settings.language.text(.homeType), systemImage: "keyboard.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(homeActionColor)
            .controlSize(.regular)
            .accessibilityLabel(settings.language.text(.homeTypeA11y))
            .accessibilityIdentifier("HomeTypeButton")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(homeBackground.ignoresSafeArea(edges: .bottom))
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

    private func saveEditedReminder(
        _ item: ReminderItem,
        draft: ReminderDraft
    ) {
        guard !isSavingReminder else { return }
        isSavingReminder = true
        saveErrorMessage = nil

        Task { @MainActor in
            do {
                _ = try await ReminderStore.update(
                    item,
                    from: draft,
                    in: modelContext
                )
                reminderBeingEdited = nil
                isSavingReminder = false
                showVoiceResult(
                    .updated(
                        title: draft.trimmedTitle,
                        fireDate: draft.fireDate ?? item.fireDate
                    ),
                    duration: .seconds(1.6)
                )
            } catch {
                isSavingReminder = false
                saveErrorMessage = message(for: error)
            }
        }
    }

    private func find(id: UUID) -> ReminderItem? {
        reminders.first { $0.id == id }
    }

    private func startVoiceCapture() {
        guard voicePhase == nil else { return }
        voiceDismissTask?.cancel()
        voicePhase = .listening
        voiceRecorder.start(
            languageCode: settings.language.speechLocale,
            completion: handleVoiceTranscript,
            failure: handleVoiceFailure
        )
    }

    private func stopVoiceCapture() {
        guard case .listening = voicePhase else { return }
        voicePhase = .processing
        voiceRecorder.stop()
    }

    private func handleVoiceTranscript(_ text: String) {
        Task { @MainActor in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                showVoiceResult(
                    .failed(settings.language.text(.voiceErrorNoTranscript)),
                    duration: .seconds(2)
                )
                return
            }

            voiceDismissTask?.cancel()
            voicePhase = nil
            pendingReminderDraft = reminderParser.makeDraft(
                from: trimmed,
                source: .voice,
                language: settings.language,
                earlyMinutes: settings.earlyMinutes,
                strikeEnabled: settings.strikeEnabled
            )
            saveErrorMessage = nil
        }
    }

    private func handleVoiceFailure(_ message: String) {
        Task { @MainActor in
            showVoiceResult(.failed(message), duration: .seconds(2.5))
        }
    }

    private func showTextEntry() {
        voiceDismissTask?.cancel()
        voicePhase = nil
        textInput = ""
        isShowingTextEntry = true
        saveErrorMessage = nil
    }

    private func parseTextReminder() {
        let trimmed = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        pendingReminderDraft = reminderParser.makeDraft(
            from: trimmed,
            source: .text,
            language: settings.language,
            earlyMinutes: settings.earlyMinutes,
            strikeEnabled: settings.strikeEnabled
        )
        textInput = ""
        isShowingTextEntry = false
        saveErrorMessage = nil
    }

    private func cancelTextReminder() {
        textInput = ""
        isShowingTextEntry = false
    }

    private func saveReminder(_ draft: ReminderDraft) {
        guard !isSavingReminder else { return }
        isSavingReminder = true
        saveErrorMessage = nil

        Task { @MainActor in
            do {
                _ = try await ReminderStore.create(
                    from: draft,
                    in: modelContext
                )
                pendingReminderDraft = nil
                isSavingReminder = false
                showVoiceResult(
                    .completed(
                        title: draft.trimmedTitle,
                        fireDate: draft.fireDate ?? Date()
                    ),
                    duration: .seconds(1.6)
                )
            } catch {
                isSavingReminder = false
                saveErrorMessage = message(for: error)
            }
        }
    }

    private func cancelReminderCreation() {
        guard !isSavingReminder else { return }
        pendingReminderDraft = nil
        saveErrorMessage = nil
    }

    private func cancelReminderEdit() {
        guard !isSavingReminder else { return }
        reminderBeingEdited = nil
        saveErrorMessage = nil
    }

    private func message(for error: Error) -> String {
        guard let storeError = error as? ReminderStoreError else {
            return settings.language.text(.voiceFailed)
        }

        switch storeError {
        case .notificationPermissionDenied:
            return settings.language.text(.voiceErrorPermission)
        case .emptyTitle:
            return settings.language.text(.voiceErrorEmptyTitle)
        case .missingDate:
            return settings.language.text(.voiceErrorNoTime)
        case .persistenceFailed:
            return settings.language.text(.voiceFailed)
        }
    }

    private func showVoiceResult(_ phase: VoiceCapturePhase, duration: Duration) {
        voiceDismissTask?.cancel()
        voicePhase = phase
        voiceDismissTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                voicePhase = nil
            }
        }
    }

}

private struct HomeHeaderTitle: View {
    let title: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            AnimatedBellBadge(accentColor: accentColor)

            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct AnimatedBellBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let accentColor: Color

    @State private var shakeTrigger = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accentColor)

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .phaseAnimator(
                    [0.0, -7.0, 7.0, -5.0, 4.0, 0.0],
                    trigger: shakeTrigger
                ) { content, angle in
                    content.rotationEffect(.degrees(angle), anchor: .top)
                } animation: { _ in
                    .easeInOut(duration: 0.08)
                }
        }
        .frame(width: 28, height: 28)
        .shadow(color: accentColor.opacity(0.22), radius: 5, y: 2)
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }

            try? await Task.sleep(for: .milliseconds(450))
            while !Task.isCancelled {
                shakeTrigger += 1
                try? await Task.sleep(for: .seconds(7))
            }
        }
    }
}

private struct VoiceCaptureOverlay: View {
    @Environment(AppSettings.self) private var settings

    let phase: VoiceCapturePhase
    let transcript: String
    let audioLevel: Double

    private var isListening: Bool {
        switch phase {
        case .listening, .processing:
            return true
        default:
            return false
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                VoiceWaveformView(
                    level: audioLevel,
                    isActive: isListening
                )

                Text(title)
                    .font(.headline)

                Text(detail)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("VoiceCaptureOverlay")
    }

    private var title: String {
        switch phase {
        case .listening:
            settings.language.text(.voiceListening)
        case .processing:
            settings.language.text(.voiceProcessing)
        case .completed:
            settings.language.text(.voiceCreated)
        case .updated:
            settings.language.text(.voiceUpdated)
        case .failed:
            settings.language.text(.voiceFailed)
        }
    }

    private var detail: String {
        switch phase {
        case .listening:
            transcript.isEmpty
                ? settings.language.text(.voiceListeningHint)
                : transcript
        case .processing:
            transcript.isEmpty
                ? settings.language.text(.voiceProcessingHint)
                : transcript
        case .completed(let title, let fireDate):
            "\(title) · \(fireDate.formatted(date: .abbreviated, time: .shortened))"
        case .updated(let title, let fireDate):
            "\(title) · \(fireDate.formatted(date: .abbreviated, time: .shortened))"
        case .failed(let message):
            message
        }
    }
}

private struct ReminderActionPrompt: View {
    @Environment(AppSettings.self) private var settings

    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            HStack(spacing: 10) {
                Button(action: onEdit) {
                    Text(settings.language.text(.commonEdit))
                        .font(.title3.bold())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("EditReminderActionButton")

                Text(settings.language.text(.commonOr))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)

                Button(role: .destructive, action: onDelete) {
                    Text(settings.language.text(.commonDelete))
                        .font(.title3.bold())
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("DeleteReminderActionButton")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minWidth: 220)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ReminderActionPrompt")
    }
}

private struct VoiceWaveformView: View {
    let level: Double
    let isActive: Bool

    var body: some View {
        let visibleLevel = isActive ? min(max(level, 0), 1) : 0

        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<24, id: \.self) { index in
                let arch = sin(
                    (Double(index) + 0.5) / 24 * Double.pi
                )
                let height = 8 + visibleLevel * (10 + arch * 36)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: height)
            }
        }
        .frame(height: 52)
        .animation(.easeOut(duration: 0.14), value: visibleLevel)
    }
}

struct ReminderAlertView: View {
    let reminder: ReminderItem
    let onConfirm: () -> Void
    let onSnooze: () -> Void

    @Environment(AppSettings.self) private var settings
    @StateObject private var speaker = SpeechService()
    @State private var flashOn = false

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
                    Text(settings.language.text(.alertReminder))
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
                        Label(
                            settings.language.text(reminder.repeatRule.localizationKey),
                            systemImage: "repeat"
                        )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    Button(action: onConfirm) {
                        Label(
                            settings.language.text(.alertGotIt),
                            systemImage: "checkmark.circle.fill"
                        )
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: onSnooze) {
                        Label(
                            settings.language.text(.alertSnooze),
                            systemImage: "clock.arrow.circlepath"
                        )
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
            let timeText = ReminderVoiceStore.timeText(
                for: reminder.fireDate,
                language: settings.language
            )
            let sentSoundURL = ReminderVoiceStore.soundURL(
                for: reminder.id,
                kind: .main
            )

            if !speaker.playSound(
                at: sentSoundURL,
                volume: settings.speechVolume
            ) {
                speaker.speak(
                    settings.language.format(
                        .alertSpeech,
                        timeText,
                        reminder.title
                    ),
                    languageCode: settings.language.speechLocale,
                    volume: settings.speechVolume
                )
            }
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
