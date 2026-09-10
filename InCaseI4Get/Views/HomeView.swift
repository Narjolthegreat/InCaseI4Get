import SwiftData
import SwiftUI
import UIKit

private enum VoiceCapturePhase {
    case listening
    case processing
    case summarizing(title: String, fireDate: Date)
    case completed(title: String, fireDate: Date)
    case failed(String)
}

private struct VoiceReminderDraft: Identifiable {
    let id = UUID()
    let title: String
    let fireDate: Date
    let repeatRule: ReminderRepeat
    let originalText: String
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Query(sort: \ReminderItem.fireDate) private var reminders: [ReminderItem]

    @State private var activeAddFlow: AddFlow?
    @State private var isShowingSettings = false
    @State private var presentedReminder: ReminderItem?
    @State private var voicePhase: VoiceCapturePhase?
    @State private var voiceDismissTask: Task<Void, Never>?
    @State private var pendingVoiceReminder: VoiceReminderDraft?
    @StateObject private var voiceRecorder = VoiceTranscriber()
    @StateObject private var purchaseManager = PurchaseManager()

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("HomeSettingsButton")
                }
            }
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
                if let pendingVoiceReminder {
                    VoiceReminderConfirmationOverlay(
                        draft: pendingVoiceReminder,
                        purchaseManager: purchaseManager,
                        onCancel: {
                            self.pendingVoiceReminder = nil
                        },
                        onConfirm: { title, fireDate, repeatRule in
                            confirmVoiceReminder(
                                pendingVoiceReminder,
                                title: title,
                                fireDate: fireDate,
                                repeatRule: repeatRule
                            )
                        }
                    )
                    .id(pendingVoiceReminder.id)
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
        HStack(spacing: 12) {
            Button {
                // Press-and-hold is handled by the gesture below.
            } label: {
                Label("Speak", systemImage: "mic.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityLabel("Create reminder by voice")
            .accessibilityIdentifier("HomeSpeakButton")
            .accessibilityHint("Press and hold to speak")
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
                activeAddFlow = AddFlow(source: .text)
            } label: {
                Label("Type", systemImage: "keyboard.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityLabel("Type a reminder")
            .accessibilityIdentifier("HomeTypeButton")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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
                showVoiceResult(.failed("没有听清，请按住 Speak 再说一次。"), duration: .seconds(2))
                return
            }

            let parsed = ReminderSentenceParser.parse(trimmed)
            guard let fireDate = parsed.fireDate else {
                showVoiceResult(
                    .failed("没有识别出明确的提醒时间，请说得具体一些。"),
                    duration: .seconds(2.5)
                )
                return
            }

            voiceDismissTask?.cancel()
            voicePhase = .processing
            try? await Task.sleep(for: .milliseconds(1_500))

            voicePhase = .summarizing(title: parsed.title, fireDate: fireDate)
            try? await Task.sleep(for: .milliseconds(1_500))

            voicePhase = nil
            pendingVoiceReminder = VoiceReminderDraft(
                title: parsed.title,
                fireDate: max(fireDate, Date().addingTimeInterval(60)),
                repeatRule: parsed.repeatRule,
                originalText: trimmed
            )
        }
    }

    private func handleVoiceFailure(_ message: String) {
        Task { @MainActor in
            showVoiceResult(.failed(message), duration: .seconds(2.5))
        }
    }

    private func confirmVoiceReminder(
        _ draft: VoiceReminderDraft,
        title: String,
        fireDate: Date,
        repeatRule: ReminderRepeat
    ) {
        pendingVoiceReminder = nil

        Task { @MainActor in
            let granted = await NotificationScheduler.ensureAuthorization()
            guard granted else {
                showVoiceResult(
                    .failed("需要通知权限才能创建提醒，请到系统设置中允许通知。"),
                    duration: .seconds(2.5)
                )
                return
            }

            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty else {
                showVoiceResult(
                    .failed("任务标题不能为空。"),
                    duration: .seconds(2)
                )
                return
            }

            let effectiveEndDate = repeatRule == .once
                ? nil
                : Calendar.current.date(byAdding: .day, value: 7, to: fireDate)
            let item = ReminderItem(
                title: cleanTitle,
                fireDate: fireDate,
                repeatRule: repeatRule,
                repeatEndDate: effectiveEndDate,
                source: .voice,
                languageCode: settings.language.rawValue,
                earlyMinutes: settings.earlyMinutes,
                strikeEnabled: settings.strikeEnabled
            )
            modelContext.insert(item)
            try? modelContext.save()
            await NotificationScheduler.schedule(item)

            showVoiceResult(
                .completed(title: cleanTitle, fireDate: fireDate),
                duration: .seconds(1.6)
            )
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

    private struct AddFlow: Identifiable {
        let id = UUID()
        let source: ReminderSource
    }
}

private struct VoiceReminderConfirmationOverlay: View {
    let draft: VoiceReminderDraft
    @ObservedObject var purchaseManager: PurchaseManager
    let onCancel: () -> Void
    let onConfirm: (String, Date, ReminderRepeat) -> Void

    @State private var title: String
    @State private var fireDate: Date
    @State private var repeatRule: ReminderRepeat
    @State private var selectedLockedRule: ReminderRepeat?
    @State private var showsPaywall = false

    init(
        draft: VoiceReminderDraft,
        purchaseManager: PurchaseManager,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (String, Date, ReminderRepeat) -> Void
    ) {
        self.draft = draft
        self.purchaseManager = purchaseManager
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _title = State(initialValue: draft.title)
        _fireDate = State(initialValue: max(draft.fireDate, Date().addingTimeInterval(60)))
        _repeatRule = State(initialValue: draft.repeatRule)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var repeatRequiresPro: Bool {
        repeatRule != .once && !purchaseManager.isPro
    }

    private var canCreate: Bool {
        !trimmedTitle.isEmpty && !repeatRequiresPro
    }

    var body: some View {
        GeometryReader { proxy in
            let minimumCardHeight = proxy.size.height * 0.46

            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Task")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Reminder title", text: $title, axis: .vertical)
                            .lineLimit(1...2)
                            .accessibilityIdentifier("VoiceReminderTitleField")
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 8)
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reminder time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            DatePicker(
                                "Reminder time",
                                selection: $fireDate,
                                in: Date()...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                            .accessibilityIdentifier("VoiceReminderDatePicker")

                            Text(
                                fireDate.formatted(
                                    .dateTime.weekday(.wide)
                                )
                            )
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("VoiceReminderWeekday")
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 8)
                    )

                    repeatBox

                    HStack(spacing: 20) {
                        Button("Cancel") {
                            onCancel()
                        }
                        .font(.headline.bold())
                        .frame(width: 132, height: 46)
                        .background(
                            Color.red,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .foregroundStyle(.white)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("CancelVoiceReminderButton")

                        Button("Create") {
                            onConfirm(trimmedTitle, fireDate, repeatRule)
                        }
                        .font(.headline.bold())
                        .frame(width: 132, height: 46)
                        .background(
                            Color.green,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .foregroundStyle(.white)
                        .buttonStyle(.plain)
                        .disabled(!canCreate)
                        .opacity(canCreate ? 1 : 0.5)
                        .accessibilityIdentifier("ConfirmCreateReminderButton")
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(18)
                .frame(width: min(proxy.size.width - 24, 420))
                .frame(minHeight: minimumCardHeight)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .position(
                    x: proxy.size.width / 2,
                    y: proxy.size.height * 0.58
                )

                if showsPaywall {
                    RepeatReminderProPaywallView(
                        purchaseManager: purchaseManager,
                        onPurchased: {
                            if let selectedLockedRule {
                                repeatRule = selectedLockedRule
                            }
                        },
                        onClose: {
                            showsPaywall = false
                        }
                    )
                    .transition(.opacity)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("VoiceReminderConfirmation")
        }
    }

    private var repeatBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repeat")
                .font(.caption)
                .foregroundStyle(.secondary)

            if purchaseManager.isPro {
                Menu {
                    ForEach(ReminderRepeat.allCases) { rule in
                        Button(rule.displayName) {
                            repeatRule = rule
                        }
                    }
                } label: {
                    HStack {
                        Text(repeatRule.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("VoiceReminderRepeatMenu")
            } else {
                Button {
                    selectedLockedRule = repeatRule == .once ? .daily : repeatRule
                    showsPaywall = true
                } label: {
                    HStack {
                        Text(repeatRule.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("VoiceReminderRepeatButton")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}

private struct RepeatReminderProPaywallView: View {
    @ObservedObject var purchaseManager: PurchaseManager
    let onPurchased: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "repeat.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Unlock Repeating Reminders")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("Pay once and keep daily, weekly and monthly reminders forever.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        if await purchaseManager.purchasePro() {
                            onPurchased()
                            onClose()
                        }
                    }
                } label: {
                    Text(purchaseLabel)
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(purchaseManager.isPurchasing)
                .accessibilityIdentifier("PurchaseRepeatProButton")

                Button("Restore Purchase") {
                    Task {
                        if await purchaseManager.restorePurchases() {
                            onPurchased()
                            onClose()
                        }
                    }
                }
                .disabled(purchaseManager.isPurchasing)
                .accessibilityIdentifier("RestoreRepeatProButton")

                if let errorMessage = purchaseManager.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button("Close") {
                    onClose()
                }
                .accessibilityIdentifier("ClosePaywallButton")
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("RepeatProPaywall")
    }

    private var purchaseLabel: String {
        if let product = purchaseManager.product {
            return "Unlock Forever · \(product.displayPrice)"
        }
        return "Unlock Forever"
    }
}

private struct VoiceCaptureOverlay: View {
    let phase: VoiceCapturePhase
    let transcript: String
    let audioLevel: Double

    private var isListening: Bool {
        switch phase {
        case .listening, .processing, .summarizing:
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
            "正在聆听"
        case .processing:
            "正在转成文字"
        case .summarizing:
            "正在概括任务"
        case .completed:
            "已创建提醒"
        case .failed:
            "没有完成"
        }
    }

    private var detail: String {
        switch phase {
        case .listening:
            transcript.isEmpty ? "请说出提醒内容，松开结束" : transcript
        case .processing:
            transcript.isEmpty ? "正在把语音转成文字" : transcript
        case .summarizing(let title, let fireDate):
            "\(title) · \(fireDate.formatted(date: .abbreviated, time: .shortened))"
        case .completed(let title, let fireDate):
            "\(title) · \(fireDate.formatted(date: .abbreviated, time: .shortened))"
        case .failed(let message):
            message
        }
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
