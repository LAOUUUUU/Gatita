//
//  VoiceInput.swift
//  Gatita
//

import AVFoundation
import Observation
import Speech

/// Types what you say into the prompt box, with Apple's speech recognition. The first time, the system asks for
/// microphone and speech recognition permission. Press the mic again to stop.
@Observable
@MainActor
final class VoiceInput {
    private(set) var isListening = false
    /// Why listening could not start, in words for the chat.
    private(set) var problem: String?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognition: SFSpeechRecognitionTask?
    /// True while permission is being asked, so a second press does not start a second microphone.
    @ObservationIgnored private var isStarting = false
    /// Bumped by each start and stop. The recognizer can call back after it was stopped, and an old session's
    /// last words must not land in, or stop, a newer one.
    @ObservationIgnored private var generation = 0

    /// Starts listening, or stops when already listening. `update` gets the prompt text as it should read now:
    /// what was typed before, then what has been heard so far.
    func toggle(draft: String, update: @escaping (String) -> Void) {
        if isListening {
            stop()
            return
        }
        guard !isStarting else { return }
        isStarting = true
        problem = nil
        Task {
            defer { isStarting = false }
            guard await Self.authorize() else {
                problem = "Gatita needs microphone and speech recognition permission. Turn them on in System Settings, Privacy & Security."
                return
            }
            start(draft: draft, update: update)
        }
    }

    func stop() {
        generation += 1
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognition?.finish()
        engine = nil
        request = nil
        recognition = nil
        isListening = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func start(draft: String, update: @escaping (String) -> Void) {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            problem = "Speech recognition is not available right now."
            return
        }
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif
            let engine = AVAudioEngine()
            let format = engine.inputNode.outputFormat(forBus: 0)
            // With no microphone the format is empty, and tapping it would crash the app.
            guard Self.canRecord(sampleRate: format.sampleRate, channels: format.channelCount) else {
                problem = "No microphone was found. Connect one, or pick one in System Settings, Sound."
                return
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            Self.feed(engine.inputNode, into: request)
            engine.prepare()
            try engine.start()
            let before = draft.isEmpty || draft.hasSuffix(" ") || draft.hasSuffix("\n") ? draft : draft + " "
            generation += 1
            let current = generation
            recognition = Self.recognize(request, with: recognizer) { [weak self] heard, done in
                guard let self else { return }
                Task { @MainActor in
                    guard self.isListening, self.generation == current else { return }
                    if let heard { update(before + heard) }
                    if done { self.stop() }
                }
            }
            self.engine = engine
            self.request = request
            isListening = true
        } catch {
            problem = "The microphone could not start: \(error.localizedDescription)"
            stop()
        }
    }

    /// Whether the input can be recorded: a Mac with no microphone reports 0 Hz and no channels.
    nonisolated static func canRecord(sampleRate: Double, channels: AVAudioChannelCount) -> Bool {
        sampleRate > 0 && channels > 0
    }

    // The audio tap and the recognizer call back on their own threads, so their closures are made outside the
    // main actor.

    nonisolated private static func feed(_ input: AVAudioInputNode, into request: SFSpeechAudioBufferRecognitionRequest) {
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func recognize(_ request: SFSpeechAudioBufferRecognitionRequest, with recognizer: SFSpeechRecognizer,
                                              handler: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, error != nil || result?.isFinal == true)
        }
    }

    nonisolated private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        #if os(macOS)
        return await AVCaptureDevice.requestAccess(for: .audio)
        #else
        return await AVAudioApplication.requestRecordPermission()
        #endif
    }
}
