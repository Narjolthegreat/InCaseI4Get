import AVFoundation
import Foundation

enum ReminderVoiceKind: String {
    case main
    case early
    case snooze
}

enum ReminderVoiceStore {
    static func prepareSounds(for item: ReminderItem) async -> Bool {
        let language = AppLanguage.current
        let timeText = timeText(for: item.fireDate, language: language)
        let title = spokenTitle(from: item.title)
        let mainURL = soundURL(for: item.id, kind: .main)

        let mainText = language.format(
            .alertSpeech,
            timeText,
            title
        )
        let mainReady: Bool
        if FileManager.default.fileExists(atPath: mainURL.path) {
            mainReady = true
        } else {
            mainReady = await render(mainText, language: language, to: mainURL)
        }

        guard item.earlyMinutes > 0 else {
            return mainReady
        }

        let earlyText = language.format(
            .notificationEarlySpeech,
            timeText,
            item.earlyMinutes,
            title
        )
        let earlyURL = soundURL(for: item.id, kind: .early)
        let earlyReady: Bool
        if FileManager.default.fileExists(atPath: earlyURL.path) {
            earlyReady = true
        } else {
            earlyReady = await render(earlyText, language: language, to: earlyURL)
        }

        return mainReady && earlyReady
    }

    static func prepareSnoozeSound(
        for item: ReminderItem,
        at date: Date
    ) async -> String? {
        let language = AppLanguage.current
        let text = language.format(
            .alertSpeech,
            timeText(for: date, language: language),
            spokenTitle(from: item.title)
        )
        let url = soundURL(for: item.id, kind: .snooze)

        guard await render(text, language: language, to: url) else {
            return nil
        }

        return url.lastPathComponent
    }

    static func soundName(for id: UUID, kind: ReminderVoiceKind) -> String {
        soundURL(for: id, kind: kind).lastPathComponent
    }

    static func soundURL(for id: UUID, kind: ReminderVoiceKind) -> URL {
        soundsDirectory.appendingPathComponent(
            "reminder-\(id.uuidString)-\(kind.rawValue).caf"
        )
    }

    static func timeText(for date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func removeSounds(for item: ReminderItem) {
        removeSounds(for: item.id)
    }

    static func removeSounds(for id: UUID) {
        for kind in [ReminderVoiceKind.main, .early, .snooze] {
            try? FileManager.default.removeItem(at: soundURL(for: id, kind: kind))
        }
    }

    static func removeAllSounds() {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: soundsDirectory,
                includingPropertiesForKeys: nil
            )
        else {
            return
        }

        for file in files where file.lastPathComponent.hasPrefix("reminder-") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static var soundsDirectory: URL {
        let library = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        )[0]
        return library.appendingPathComponent("Sounds", isDirectory: true)
    }

    private static func render(
        _ text: String,
        language: AppLanguage,
        to url: URL
    ) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        do {
            try FileManager.default.createDirectory(
                at: soundsDirectory,
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: url)
        } catch {
            return false
        }

        let session = SpeechRenderSession(outputURL: url)
        return await session.render(text: trimmed, language: language)
    }

    private static func spokenTitle(from title: String) -> String {
        let collapsed = title
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > 160 else { return collapsed }
        return String(collapsed.prefix(157)) + "..."
    }
}

private final class SpeechRenderSession {
    private let outputURL: URL
    private let synthesizer = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var audioFile: AVAudioFile?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var hasFinished = false

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func render(text: String, language: AppLanguage) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(
                language: language.speechLocale
            )
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.preUtteranceDelay = 0
            utterance.postUtteranceDelay = 0

            synthesizer.write(utterance) { [weak self] buffer in
                self?.consume(buffer)
            }
        }
    }

    private func consume(_ buffer: AVAudioBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard !hasFinished, let pcmBuffer = buffer as? AVAudioPCMBuffer else {
            return
        }

        if pcmBuffer.frameLength == 0 {
            finish(success: FileManager.default.fileExists(atPath: outputURL.path))
            return
        }

        do {
            if audioFile == nil {
                audioFile = try AVAudioFile(
                    forWriting: outputURL,
                    settings: pcmBuffer.format.settings
                )
            }
            try audioFile?.write(from: pcmBuffer)
        } catch {
            finish(success: false)
        }
    }

    private func finish(success: Bool) {
        guard !hasFinished else { return }
        hasFinished = true
        audioFile = nil

        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: success)
    }
}
