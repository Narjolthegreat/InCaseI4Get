import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    @State private var showsClearConfirmation = false
    @State private var clearErrorMessage: String?

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    Picker(
                        settings.language.text(.settingsAppLanguage),
                        selection: $settings.language
                    ) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                } header: {
                    Text(settings.language.text(.settingsLanguage))
                } footer: {
                    Text(settings.language.text(.settingsLanguageFooter))
                }

                Section {
                    Toggle(
                        settings.language.text(.settingsVoiceReading),
                        isOn: $settings.ttsEnabled
                    )
                    Toggle(
                        settings.language.text(.settingsHapticPulse),
                        isOn: $settings.hapticsEnabled
                    )
                    Toggle(
                        settings.language.text(.settingsScreenFlash),
                        isOn: $settings.flashEnabled
                    )
                    Toggle(
                        settings.language.text(.settingsStrike),
                        isOn: $settings.strikeEnabled
                    )
                    Stepper(
                        value: $settings.earlyMinutes,
                        in: 0...30,
                        step: 5
                    ) {
                        Text(
                            settings.language.format(
                                .settingsEarlyMinutes,
                                settings.earlyMinutes
                            )
                        )
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(settings.language.text(.settingsVoiceVolume))
                            Spacer()
                            Text(
                                settings.speechVolume,
                                format: .percent.precision(.fractionLength(0))
                            )
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.speechVolume, in: 0.3...1, step: 0.05)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(settings.language.text(.settingsAlertStyle))
                }

                Section {
                    Button(
                        settings.language.text(.settingsClearAll),
                        role: .destructive
                    ) {
                        showsClearConfirmation = true
                    }
                } header: {
                    Text(settings.language.text(.settingsPrivacy))
                } footer: {
                    Text(settings.language.text(.settingsPrivacyFooter))
                }

                Section {
                    LabeledContent(
                        settings.language.text(.settingsVersion),
                        value: "0.2.0"
                    )
                }
            }
            .navigationTitle(settings.language.text(.settingsTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.language.text(.commonDone)) {
                        dismiss()
                    }
                }
            }
            .alert(
                settings.language.text(.settingsClearTitle),
                isPresented: $showsClearConfirmation
            ) {
                Button(
                    settings.language.text(.settingsDeleteAll),
                    role: .destructive
                ) {
                    Task { @MainActor in await clearAllData() }
                }
                Button(
                    settings.language.text(.commonCancel),
                    role: .cancel
                ) {}
            } message: {
                Text(settings.language.text(.settingsClearMessage))
            }
        }
    }

    private func clearAllData() async {
        let descriptor = FetchDescriptor<ReminderItem>()
        let reminders = (try? modelContext.fetch(descriptor)) ?? []
        for item in reminders {
            await NotificationScheduler.cancel(item)
            modelContext.delete(item)
        }
        ReminderVoiceStore.removeAllSounds()
        try? modelContext.save()
        dismiss()
    }
}
