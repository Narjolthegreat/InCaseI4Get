import Foundation
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
            .navigationTitle(settings.language.text(.addTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.language.text(.commonCancel)) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        isSaving
                            ? settings.language.text(.addSaving)
                            : settings.language.text(.commonSave)
                    ) {
                        save()
                    }
                    .disabled(trimmedTitle.isEmpty || isSaving)
                }
            }
            .alert(
                settings.language.text(.addNotificationsRequired),
                isPresented: $showsPermissionAlert
            ) {
                Button(settings.language.text(.addOpenSettings)) {
                    openSystemSettings()
                }
                Button(settings.language.text(.commonOK), role: .cancel) {}
            } message: {
                Text(settings.language.text(.addNotificationMessage))
            }
            .onAppear {
                earlyMinutes = settings.earlyMinutes
                strikeEnabled = settings.strikeEnabled
                if source == .voice && !didAutoStartVoice {
                    didAutoStartVoice = true
                    if !ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                        startVoiceInput()
                    }
                }
            }
        }
    }

    private var inputSection: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                microphoneButton
                TextField(
                    settings.language.text(.addSpeakOrType),
                    text: $sentence,
                    axis: .vertical
                )
                    .lineLimit(1...3)
                    .onSubmit(parseSentence)
                Button {
                    parseSentence()
                } label: {
                    Image(systemName: "text.magnifyingglass")
                }
                .disabled(sentence.isEmpty)
                .accessibilityLabel(settings.language.text(.addParseSentence))
            }

            if transcriber.isRecording {
                Text(
                    transcriber.transcript.isEmpty
                        ? settings.language.text(.addListening)
                        : transcriber.transcript
                )
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

            TextField(
                settings.language.text(.addReminderTitle),
                text: $title,
                axis: .vertical
            )
                .lineLimit(1...4)
            TextField(
                settings.language.text(.addNoteOptional),
                text: $note,
                axis: .vertical
            )
                .lineLimit(1...3)
        } header: {
            Text(settings.language.text(.addWhatRemember))
        }
    }

    private var reminderSection: some View {
        Section {
            DatePicker(
                settings.language.text(.addRemindAt),
                selection: $fireDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
        } header: {
            Text(settings.language.text(.addWhen))
        }
    }

    private var repeatSection: some View {
        Section {
            Picker(
                settings.language.text(.confirmationRepeat),
                selection: $repeatRule
            ) {
                ForEach(ReminderRepeat.allCases) { rule in
                    Text(settings.language.text(rule.localizationKey)).tag(rule)
                }
            }
            if repeatRule != .once {
                DatePicker(
                    settings.language.text(.addEndOn),
                    selection: Binding(
                        get: { repeatEndDate ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date() },
                        set: { repeatEndDate = $0 }
                    ),
                    in: Calendar.current.startOfDay(for: fireDate)...,
                    displayedComponents: [.date]
                )
            }
        } header: {
            Text(settings.language.text(.confirmationRepeat))
        } footer: {
            Text(
                repeatRule == .once
                    ? settings.language.text(.addRepeatOnceFooter)
                    : settings.language.text(.addRepeatFooter)
            )
        }
    }

    private var strikeSection: some View {
        Section {
            Toggle(
                settings.language.text(.addStrikeEvery),
                isOn: $strikeEnabled
            )
            Picker(
                settings.language.text(.addEarlyReminder),
                selection: $earlyMinutes
            ) {
                Text(settings.language.text(.commonNone)).tag(0)
                Text(settings.language.text(.addMinutes5)).tag(5)
                Text(settings.language.text(.addMinutes10)).tag(10)
                Text(settings.language.text(.addMinutes15)).tag(15)
            }
            Button {
                previewSpeech()
            } label: {
                Label(
                    settings.language.text(.addPreviewVoice),
                    systemImage: "speaker.wave.2.fill"
                )
            }
        } header: {
            Text(settings.language.text(.settingsAlertStyle))
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
        .accessibilityLabel(
            transcriber.isRecording
                ? settings.language.text(.addStopRecording)
                : settings.language.text(.addStartVoiceInput)
        )
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
        parseMessage = settings.language.format(.addParsed, parsed.title)
    }

    private func previewSpeech() {
        let text = trimmedTitle.isEmpty
            ? settings.language.text(.addPreviewSentence)
            : trimmedTitle
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
