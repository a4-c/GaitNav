import AVFoundation

// speak() = skip if busy, speakInterrupting() = cut current speech immediately
class SpeechManager: NSObject {
    
    private let synthesizer = AVSpeechSynthesizer()
    private let voiceLanguage = "en-US"
    private let speechRate: Float = 0.5
    private let speechPitch: Float = 1.0
    private(set) var isSpeaking: Bool = false
    
    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback so speech works even in silent mode
            // .duckOthers lowers other audio (e.g music) while speaking
            try session.setCategory(.playback, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    // normal: skip if already speaking
    func speak(_ text: String) {
        guard !synthesizer.isSpeaking else { return }
        performSpeech(text)
    }
    
    // urgent: cut current speech, speak immediately
    func speakInterrupting(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        performSpeech(text)
    }
    
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    private func performSpeech(_ text: String) {
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
        utterance.rate = speechRate
        utterance.pitchMultiplier = speechPitch
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        synthesizer.speak(utterance)
    }
}

extension SpeechManager: AVSpeechSynthesizerDelegate {
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}
