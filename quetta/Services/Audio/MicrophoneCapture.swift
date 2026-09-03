//
//  MicrophoneCapture.swift
//  quetta
//
//  Captures the default input device using AVCaptureSession + audio data output.
//  Buffers are forwarded in memory and never persisted (spec §7.1).
//

import Foundation
import AVFoundation

nonisolated final class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {

    /// Delivers converted PCM buffers to the owner.
    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    /// Reports a fatal capture error for this source.
    var onError: (@Sendable (Error) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "com.quetta.mic.capture")

    private(set) var isRunning = false

    func start() throws {
        guard !isRunning else { return }

        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw AudioCaptureError.noMicrophoneDevice
        }

        let input = try AVCaptureDeviceInput(device: device)

        // Configure synchronously on the capture queue so we can never overlap a
        // begin/commitConfiguration window with a queued start/stopRunning.
        var configured = false
        queue.sync { [session, output] in
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            guard session.canAddInput(input) else { return }
            session.addInput(input)
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else {
                session.removeInput(input)
                return
            }
            session.addOutput(output)
            configured = true
        }
        guard configured else { throw AudioCaptureError.cannotConfigureMicrophone }

        queue.async { [session] in
            session.startRunning()
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        // Everything must happen in order on the capture queue: stopping while a
        // begin/commitConfiguration window is open on another thread raises
        // NSGenericException inside AVCaptureSession.
        queue.async { [session] in
            session.stopRunning()
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            for output in session.outputs { session.removeOutput(output) }
            session.commitConfiguration()
        }
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pcm = sampleBuffer.makePCMBuffer() else { return }
        onBuffer?(pcm)
    }
}

enum AudioCaptureError: LocalizedError {
    case noMicrophoneDevice
    case cannotConfigureMicrophone
    case noDisplayForSystemAudio
    case systemAudioSetupFailed(String)

    var errorDescription: String? {
        switch self {
        case .noMicrophoneDevice:
            return String(localized: "error.audio.noMicrophone")
        case .cannotConfigureMicrophone:
            return String(localized: "error.audio.micConfig")
        case .noDisplayForSystemAudio:
            return String(localized: "error.audio.noDisplay")
        case .systemAudioSetupFailed(let detail):
            return detail
        }
    }
}
