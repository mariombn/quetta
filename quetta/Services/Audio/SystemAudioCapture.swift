//
//  SystemAudioCapture.swift
//  quetta
//
//  Captures desktop (system) audio via ScreenCaptureKit, audio-only, excluding
//  this process's own audio to avoid feedback (spec §7.1). No video is consumed
//  and no audio is persisted.
//

import Foundation
import AVFoundation
@preconcurrency import ScreenCaptureKit

nonisolated final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {

    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "com.quetta.systemaudio.capture")

    private(set) var isRunning = false

    func start() async throws {
        guard !isRunning else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplayForSystemAudio
        }

        // Exclude our own app's windows/audio to prevent feedback.
        let ownApps = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApps,
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // Minimize video overhead — we never read screen frames.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 6

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()

        self.stream = stream
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        let stream = self.stream
        self.stream = nil
        stream?.stopCapture { _ in }
    }

    // MARK: - SCStreamOutput

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let pcm = sampleBuffer.makePCMBuffer() else { return }
        onBuffer?(pcm)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isRunning = false
        onError?(error)
    }
}
