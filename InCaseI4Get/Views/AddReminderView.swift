import SwiftData
import SwiftUI
import UIKit

struct AddReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    @State private var source: ReminderSource
    @State private var sentence = ""
    @State private var title = ""
    @State private var note = ""
    @State private var fireDate = Self.nextFiveMinutes
    @State private var repeatRule: ReminderRepeat = .once
    @State private var repeatEndDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())
    @State private var earlyMinutes = 5
    @State private var strikeEnabled = true
    @State private var isSaving = false
    @State private var showsPermissionAlert = false
    @State private var parseMessage: String?
    @State private var didAutoStartVoice = false

    @StateObject private var transcriber = VoiceTranscriber()
    @StateObject private var speaker = SpeechService()

    init(source: ReminderSource) {
        _source = State(initialValue: source)
    }

    private static var nextFiveMinutes: Date {
        Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                inputSection
                reminderSection
                repeatSection
                strikeSection
            }
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        save()
                    }
                    .disabled(trimmedTitle.isEmpty || isSaving)
                }
            }
            .alert("Notifications are required", isPresented: $showsPermissionAlert) {
                Button("Open Settings") {
                    openSystemSettings()
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Allow notifications so reminders can reach you at the right time.")
            }
            .onAppear {
                earlyMinutes = settings.earlyMinutes
                strikeEnabled = settings.strikeEnabled
                if source == .voice && !didAutoStartVoice {
                    didAutoStartVoice = true
                    startVoiceInput()
                }
            }
        }
    }

    private var inputSection: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                microphoneButton
                TextField("Speak or type…", text: $sentence, axis: .vertical)
                    .lineLimit(1...3)
                    .onSubmit(parseSentence)
                Button {
                    parseSentence()
                } label: {
                    Image(systemName: "text.magnifyingglass")
                }
                .disabled(sentence.isEmpty)
                .accessibilityLabel("Parse sentence")
            }

            if transcriber.isRecording {
                Text(transcriber.transcript.isEmpty ? "Listening…" : transcriber.transcript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let message = transcriber.permissionMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let parseMessage {
                Text(parseMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Reminder title", text: $title, axis: .vertical)
                .lineLimit(1...4)
            TextField("Note (optional)", text: $note, axis: .vertical)
                .lineLimit(1...3)
        } header: {
            Text("What should we remember?")
        }
    }

    private var reminderSection: some View {
        Section {
            DatePicker(
                "Remind at",
                selection: $fireDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
        } header: {
            Text("When")
        }
    }

    private var repeatSection: some View {
        Section {
            Picker("Repeat", selection: $repeatRule) {
                ForEach(ReminderRepeat.allCases) { rule in
                    Text(rule.displayName).tag(rule)
                }
            }
            if repeatRule != .once {
                DatePicker(
                    "End on",
                    selection: Binding(
                        get: { repeatEndDate ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date() },
                        set: { repeatEndDate = $0 }
                    ),
                    in: Calendar.current.startOfDay(for: fireDate)...,
                    displayedComponents: [.date]
                )
            }
        } header: {
            Text("Repeat")
        } footer: {
            Text(repeatRule == .once ? "One-time reminders clear after midnight." : "Use an end date for tasks like medication for 7 days.")
        }
    }

    private var strikeSection: some View {
        Section {
            Toggle("Strike again every 30 seconds", isOn: $strikeEnabled)
            Picker("Early reminder", selection: $earlyMinutes) {
                Text("None").tag(0)
                Text("5 minutes").tag(5)
                Text("10 minutes").tag(10)
                Text("15 minutes").tag(15)
            }
            Button {
                previewSpeech()
            } label: {
                Label("Preview voice", systemImage: "speaker.wave.2.fill")
            }
        } header: {
            Text("Alert style")
        }
    }

    private var microphoneButton: some View {
        Button {
            if transcriber.isRecording {
                transcriber.stop()
            } else {
                startVoiceInput()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(transcriber.isRecording ? Color.red : Color.accentColor)
                    .frame(width: 44, height: 44)
                Image(systemName: transcriber.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(transcriber.isRecording ? "Stop recording" : "Start voice input")
    }

    private func startVoiceInput() {
        transcriber.start(languageCode: settings.language.speechLocale) { spokenText in
            let trimmed = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            sentence = trimmed
            parseSentence()
        }
    }

    private func parseSentence() {
        let parsed = ReminderSentenceParser.parse(sentence)
        title = parsed.title
        if let parsedDate = parsed.fireDate {
            fireDate = parsedDate
        }
        if parsed.repeatRule != .once {
            repeatRule = parsed.repeatRule
        }
        parseMessage = "Parsed: \(parsed.title)"
    }

    private func previewSpeech() {
        let text = trimmedTitle.isEmpty ? "This is a reminder preview." : trimmedTitle
        speaker.speak(text, languageCode: settings.language.speechLocale, volume: settings.speechVolume)
    }

    private func save() {
        let cleanTitle = trimmedTitle
        guard !cleanTitle.isEmpty, !isSaving else { return }
        isSaving = true

        let effectiveEndDate = repeatRule == .once ? nil : repeatEndDate
        Task { @MainActor in
            let granted = await NotificationScheduler.ensureAuthorization()
            guard granted else {
                isSaving = false
                showsPermissionAlert = true
                return
            }

            let item = ReminderItem(
                title: cleanTitle,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                fireDate: fireDate,
                repeatRule: repeatRule,
                repeatEndDate: effectiveEndDate,
                source: source,
                languageCode: settings.language.rawValue,
                earlyMinutes: earlyMinutes,
                strikeEnabled: strikeEnabled
            )
            modelContext.insert(item)
            try? modelContext.save()
            await NotificationScheduler.schedule(item)
            dismiss()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
