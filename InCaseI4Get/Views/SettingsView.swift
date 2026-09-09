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
                    Picker("App language", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                } header: {
                    Text("Language")
                } footer: {
                    Text("Language follows system by default in this version.")
                }

                Section {
                    Toggle("Voice reading", isOn: $settings.ttsEnabled)
                    Toggle("Haptic pulse", isOn: $settings.hapticsEnabled)
                    Toggle("Screen flash", isOn: $settings.flashEnabled)
                    Toggle("Strike reminders", isOn: $settings.strikeEnabled)
                    Stepper(
                        "Early reminder \(settings.earlyMinutes) min",
                        value: $settings.earlyMinutes,
                        in: 0...30,
                        step: 5
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Voice volume")
                            Spacer()
                            Text("\(Int(settings.speechVolume * 100))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.speechVolume, in: 0.3...1, step: 0.05)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Alert style")
                }

                Section {
                    Button("Clear all local data", role: .destructive) {
                        showsClearConfirmation = true
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("This removes reminders, scheduled notifications and generated files. No account is used.")
                }

                Section {
                    LabeledContent("Version", value: "0.2.0")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Clear everything?", isPresented: $showsClearConfirmation) {
                Button("Delete all", role: .destructive) {
                    Task { @MainActor in await clearAllData() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All reminders will be permanently deleted from this device.")
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
        try? modelContext.save()
        dismiss()
    }
}
