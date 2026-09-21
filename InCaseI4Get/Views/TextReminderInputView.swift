import SwiftUI

struct TextReminderInputView: View {
    @Environment(AppSettings.self) private var settings

    @Binding var sentence: String
    let onParse: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    private var trimmedSentence: String {
        sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text(settings.language.text(.addWhatRemember))
                    .font(.headline)

                TextField(
                    settings.language.text(.addSpeakOrType),
                    text: $sentence,
                    axis: .vertical
                )
                .lineLimit(2...5)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit {
                    if !trimmedSentence.isEmpty {
                        onParse()
                    }
                }
                .accessibilityIdentifier("TextReminderSentenceField")

                HStack(spacing: 12) {
                    Button(settings.language.text(.commonCancel)) {
                        onCancel()
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("CancelTextReminderButton")

                    Button(settings.language.text(.addParseSentence)) {
                        onParse()
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedSentence.isEmpty)
                    .accessibilityIdentifier("ParseTextReminderButton")
                }
            }
            .padding(20)
            .frame(maxWidth: 420)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("TextReminderInput")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(settings.language.text(.commonDone)) {
                    isFocused = false
                }
                .accessibilityIdentifier("DismissTextReminderKeyboardButton")
            }
        }
        .onAppear {
            isFocused = true
        }
    }
}
