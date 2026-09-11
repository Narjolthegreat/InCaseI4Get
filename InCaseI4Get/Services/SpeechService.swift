import AVFoundation
import Combine

final class SpeechService: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, languageCode: String, volume: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)

        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        utterance.volume = Float(max(0.3, min(volume, 1)))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func playSound(at url: URL, volume: Double) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)

            synthesizer.stopSpeaking(at: .immediate)
            audioPlayer?.stop()

            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = Float(max(0.3, min(volume, 1)))
            player.prepareToPlay()
            audioPlayer = player
            isSpeaking = true
            return player.play()
        } catch {
            audioPlayer = nil
            isSpeaking = false
            return false
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
        }
    }

    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.audioPlayer = nil
            self?.isSpeaking = false
        }
    }

    func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.audioPlayer = nil
            self?.isSpeaking = false
        }
    }
}
