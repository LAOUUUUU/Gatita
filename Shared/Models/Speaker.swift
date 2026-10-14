//
//  Speaker.swift
//  Gatita
//

import AVFoundation
import Observation

/// Reads a reply aloud with the system voice. One reply at a time: starting another stops the first.
@Observable
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    /// The reply being read, or nil.
    private(set) var speakingID: UUID?
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    /// The utterance in progress, so a cancelled one finishing late does not clear a newer one.
    @ObservationIgnored private var current: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Reads the reply, or stops it when it is the one being read.
    func toggle(id: UUID, text: String) {
        if speakingID == id {
            stop()
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: SpeechText.plain(from: text))
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        current = ObjectIdentifier(utterance)
        speakingID = id
        synthesizer.speak(utterance)
    }

    func stop() {
        current = nil
        speakingID = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    nonisolated private func finished(_ utterance: ObjectIdentifier) {
        Task { @MainActor in
            if self.current == utterance {
                self.current = nil
                self.speakingID = nil
            }
        }
    }
}
