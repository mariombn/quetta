//
//  AudioCaptureService.swift
//  quetta
//
//  Controls the two independent capture sources and mixes them, in memory, into
//  a single canonical stream delivered to the recognizer (spec §7.1).
//

import Foundation
import AVFoundation

@MainActor
@Observable
final class AudioCaptureService {

    private let microphone = MicrophoneCapture()
    private let systemAudio = SystemAudioCapture()
    private let mixer = AudioMixer()

    // Observable state for the UI.
    private(set) var microphoneActive = false
    private(set) var systemAudioActive = false
    var microphoneError: String?
    var systemAudioError: String?

    init() {
        let mixer = self.mixer
        microphone.onBuffer = { [mixer] buffer in
            mixer.process(buffer, from: .microphone)
        }
        systemAudio.onBuffer = { [mixer] buffer in
            mixer.process(buffer, from: .systemAudio)
        }
        microphone.onError = { [weak self] error in
            Task { @MainActor in self?.microphoneError = error.localizedDescription; self?.microphoneActive = false }
        }
        systemAudio.onError = { [weak self] error in
            Task { @MainActor in self?.systemAudioError = error.localizedDescription; self?.systemAudioActive = false }
        }
    }

    /// Sets the destination for mixed canonical buffers (the recognizer).
    func setBufferSink(_ sink: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        mixer.setSink(sink)
    }

    /// Starts the requested sources. At least one must be requested by the caller.
    func start(microphone micEnabled: Bool, systemAudio sysEnabled: Bool) async {
        mixer.reset()
        if micEnabled { await setMicrophone(enabled: true) }
        if sysEnabled { await setSystemAudio(enabled: true) }
    }

    func setMicrophone(enabled: Bool) async {
        microphoneError = nil
        if enabled {
            do {
                try microphone.start()
                microphoneActive = true
            } catch {
                microphoneError = error.localizedDescription
                microphoneActive = false
            }
        } else {
            microphone.stop()
            microphoneActive = false
        }
    }

    func setSystemAudio(enabled: Bool) async {
        systemAudioError = nil
        if enabled {
            do {
                try await systemAudio.start()
                systemAudioActive = true
            } catch {
                systemAudioError = error.localizedDescription
                systemAudioActive = false
            }
        } else {
            systemAudio.stop()
            systemAudioActive = false
        }
    }

    /// Stops both sources and clears the in-memory mixer.
    func stopAll() {
        microphone.stop()
        systemAudio.stop()
        mixer.reset()
        microphoneActive = false
        systemAudioActive = false
    }
}
