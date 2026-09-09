import AVFoundation
import Combine
import Speech

final class VoiceTranscriber: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published private(set) var permissionMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var completionHandler: ((String) -> Void)?
    private var hasFinished = false

    func start(languageCode: String, completion: @escaping (String) -> Void) {
        guard !isRecording else { return }

        completionHandler = completion
        hasFinished = false
        transcript = ""
        permissionMessage = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            let micGranted = await requestMicrophoneAccess()
            let speechGranted = await requestSpeechAccess()

            guard micGranted, speechGranted else {
                permissionMessage = "Microphone and speech recognition permission are required."
                return
            }

            guard
                let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode)),
                recognizer.isAvailable
            else {
                permissionMessage = "Speech recognition is unavailable for this language. You can still type."
                return
            }

            if recognizer.supportsOnDeviceRecognition {
                recognizer.requiresOnDeviceRecognition = true
            }
            beginRecording(with: recognizer)
        }
    }

    func stop() {
        guard isRecording else { return }
        finish()
    }

    private func beginRecording(with recognizer: SFSpeechRecognizer) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            permissionMessage = nil
        } catch {
            permissionMessage = "Unable to start the microphone."
            cleanup()
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    transcript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    finish()
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

        let handler = completionHandler
        completionHandler = nil
        handler?(spokenText)
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
