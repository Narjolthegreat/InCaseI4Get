import SwiftUI

struct ReminderReviewView: View {
    enum Mode {
        case create
        case edit

        var accessibilityIdentifier: String {
            switch self {
            case .create:
                "ConfirmCreateReminderButton"
            case .edit:
                "SaveEditedReminderButton"
            }
        }
    }

    @Environment(AppSettings.self) private var settings

    let draft: ReminderDraft
    @ObservedObject var purchaseManager: PurchaseManager
    let mode: Mode
    let isSaving: Bool
    let saveErrorMessage: String?
    let onCancel: () -> Void
    let onConfirm: (ReminderDraft) -> Void

    @State private var title: String
    @State private var fireDate: Date
    @State private var hasTime: Bool
    @State private var repeatRule: ReminderRepeat
    @State private var selectedLockedRule: ReminderRepeat?
    @State private var showsPaywall = false
    @FocusState private var isTitleFocused: Bool

    init(
        draft: ReminderDraft,
        purchaseManager: PurchaseManager,
        mode: Mode,
        isSaving: Bool,
        saveErrorMessage: String?,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (ReminderDraft) -> Void
    ) {
        self.draft = draft
        self.purchaseManager = purchaseManager
        self.mode = mode
        self.isSaving = isSaving
        self.saveErrorMessage = saveErrorMessage
        self.onCancel = onCancel
        self.onConfirm = onConfirm

        let initialDate = max(
            draft.fireDate ?? Date().addingTimeInterval(300),
            Date().addingTimeInterval(60)
        )
        _title = State(initialValue: draft.title)
        _fireDate = State(initialValue: initialDate)
        _hasTime = State(initialValue: draft.fireDate != nil)
        _repeatRule = State(initialValue: draft.repeatRule)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var repeatRequiresPro: Bool {
        repeatRule != .once && !purchaseManager.isPro
    }

    private var canConfirm: Bool {
        !trimmedTitle.isEmpty
            && hasTime
            && !repeatRequiresPro
            && !isSaving
    }

    var body: some View {
        GeometryReader { proxy in
            let minimumCardHeight = proxy.size.height * 0.46

            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    taskBox
                    timeBox
                    repeatBox

                    if let saveErrorMessage {
                        Text(saveErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    actionButtons
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
            .accessibilityIdentifier("ReminderReview")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(settings.language.text(.commonDone)) {
                        isTitleFocused = false
                    }
                    .accessibilityIdentifier("DismissReminderKeyboardButton")
                }
            }
            .onAppear {
                if draft.title.isEmpty {
                    isTitleFocused = true
                }
            }
        }
    }

    private var taskBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(settings.language.text(.confirmationTask))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                settings.language.text(.confirmationTitlePlaceholder),
                text: $title,
                axis: .vertical
            )
            .lineLimit(1...2)
            .focused($isTitleFocused)
            .accessibilityIdentifier("VoiceReminderTitleField")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var timeBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(settings.language.text(.confirmationReminderTime))
                .font(.caption)
                .foregroundStyle(.secondary)

            if hasTime {
                HStack(spacing: 8) {
                    DatePicker(
                        settings.language.text(.confirmationReminderTime),
                        selection: $fireDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .accessibilityIdentifier("VoiceReminderDatePicker")

                    Text(fireDate.formatted(.dateTime.weekday(.wide)))
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("VoiceReminderWeekday")
                }
            } else {
                Button {
                    fireDate = max(
                        Date().addingTimeInterval(300),
                        Date().addingTimeInterval(60)
                    )
                    hasTime = true
                } label: {
                    Label(
                        settings.language.text(.voiceErrorNoTime),
                        systemImage: "clock.badge.exclamationmark"
                    )
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ChooseReminderTimeButton")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var repeatBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(settings.language.text(.confirmationRepeat))
                .font(.caption)
                .foregroundStyle(.secondary)

            if purchaseManager.isPro {
                Menu {
                    ForEach(ReminderRepeat.allCases) { rule in
                        Button(settings.language.text(rule.localizationKey)) {
                            repeatRule = rule
                        }
                    }
                } label: {
                    HStack {
                        Text(settings.language.text(repeatRule.localizationKey))
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
                        Text(settings.language.text(repeatRule.localizationKey))
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

    private var actionButtons: some View {
        HStack(spacing: 20) {
            Button(settings.language.text(.commonCancel)) {
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
            .disabled(isSaving)
            .accessibilityIdentifier("CancelVoiceReminderButton")

            Button(confirmButtonTitle) {
                var updatedDraft = draft
                updatedDraft.title = trimmedTitle
                updatedDraft.fireDate = fireDate
                updatedDraft.repeatRule = repeatRule
                updatedDraft.parseStatus = hasTime ? .complete : .partial
                onConfirm(updatedDraft)
            }
            .font(.headline.bold())
            .frame(width: 132, height: 46)
            .background(
                Color.green,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .disabled(!canConfirm)
            .opacity(canConfirm ? 1 : 0.5)
            .accessibilityIdentifier(mode.accessibilityIdentifier)
        }
        .frame(maxWidth: .infinity)
    }

    private var confirmButtonTitle: String {
        if isSaving {
            return settings.language.text(.addSaving)
        }
        return mode == .create
            ? settings.language.text(.commonCreate)
            : settings.language.text(.commonSave)
    }
}

private struct RepeatReminderProPaywallView: View {
    @Environment(AppSettings.self) private var settings

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

                Text(settings.language.text(.paywallTitle))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(settings.language.text(.paywallDescription))
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

                Button(settings.language.text(.paywallRestore)) {
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

                Button(settings.language.text(.paywallClose)) {
                    onClose()
                }
                .accessibilityIdentifier("ClosePaywallButton")
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("RepeatProPaywall")
    }

    private var purchaseLabel: String {
        if let product = purchaseManager.product {
            return settings.language.format(
                .paywallUnlockPrice,
                product.displayPrice
            )
        }
        return settings.language.text(.paywallUnlockForever)
    }
}
