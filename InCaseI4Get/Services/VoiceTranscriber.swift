import AVFoundation
import Combine
import Speech

final class VoiceTranscriber: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published private(set) var permissionMessage: String?
    @Published private(set) var audioLevel: Double = 0

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var completionHandler: ((String) -> Void)?
    private var failureHandler: ((String) -> Void)?
    private var hasFinished = false
    private var stopRequested = false

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    func start(
        languageCode: String,
        completion: @escaping (String) -> Void,
        failure: @escaping (String) -> Void = { _ in }
    ) {
        guard !isRecording else { return }

        completionHandler = completion
        failureHandler = failure
        hasFinished = false
        stopRequested = false
        transcript = ""
        permissionMessage = nil
        audioLevel = 0

        if isUITesting {
            isRecording = true
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let micGranted = await requestMicrophoneAccess()
            let speechGranted = await requestSpeechAccess()

            guard micGranted, speechGranted else {
                fail(AppLanguage.current.text(.voiceErrorPermissions))
                return
            }

            guard
                let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode)),
                recognizer.isAvailable
            else {
                fail(AppLanguage.current.text(.voiceErrorUnavailable))
                return
            }

            guard !stopRequested else {
                fail(AppLanguage.current.text(.voiceErrorNoSpeech))
                return
            }

            beginRecording(with: recognizer)
        }
    }

    func stop() {
        guard isRecording else {
            stopRequested = true
            return
        }
        if isUITesting {
            transcript = "Take medicine on January 1, 2030 at 8:00 PM"
        }
        finish()
    }

    private func beginRecording(with recognizer: SFSpeechRecognizer) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)
            self.publishAudioLevel(Self.normalizedRMS(from: buffer))
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            permissionMessage = nil
        } catch {
            fail(AppLanguage.current.text(.voiceErrorMicrophone))
            cleanup()
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self.finish()
                }
            }
        }
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        isRecording = false

        let spokenText = transcript
        cleanup()
        transcript = ""
        audioLevel = 0

        let handler = completionHandler
        completionHandler = nil
        failureHandler = nil
        handler?(spokenText)
    }

    private func publishAudioLevel(_ rawLevel: Double) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let clamped = min(max(rawLevel, 0), 1)
            let currentLevel = self.audioLevel
            let smoothed = clamped > currentLevel
                ? clamped
                : currentLevel * 0.72 + clamped * 0.28
            self.audioLevel = smoothed
        }
    }

    private static func normalizedRMS(from buffer: AVAudioPCMBuffer) -> Double {
        guard
            let channelData = buffer.floatChannelData,
            buffer.frameLength > 0
        else {
            return 0
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        var sumSquares = 0.0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameCount {
                let sample = Double(samples[frame])
                sumSquares += sample * sample
            }
        }

        let sampleCount = Double(frameCount * channelCount)
        let rms = sqrt(sumSquares / sampleCount)
        let decibels = 20 * log10(max(rms, 0.000_001))
        let normalized = (decibels + 60) / 60
        return min(max(normalized, 0), 1)
    }

    private func fail(_ message: String) {
        permissionMessage = message
        isRecording = false
        audioLevel = 0

        let handler = failureHandler
        completionHandler = nil
        failureHandler = nil
        handler?(message)
    }

    private func cleanup() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    private func requestSpeechAccess() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }
}
