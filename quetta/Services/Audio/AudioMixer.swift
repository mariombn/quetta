//
//  AudioMixer.swift
//  quetta
//
//  Converts incoming PCM buffers from both sources to a single canonical mono
//  format and forwards them, in memory only, to the recognizer sink. No audio is
//  ever written to disk (spec §7.1, §14).
//

import Foundation
import AVFoundation
import Accelerate

/// The audio source a buffer originated from.
enum AudioSource: Sendable {
    case microphone
    case systemAudio
}

nonisolated final class AudioMixer: @unchecked Sendable {

    /// Canonical format fed to the recognizer: 16 kHz mono float, non-interleaved.
    static let canonicalFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private let lock = NSLock()
    private var converters: [String: AVAudioConverter] = [:]
    private var sink: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var _micGain: Float = 1.0

    /// Amplification factor applied to every microphone buffer (1.0 = no boost).
    var micGain: Float {
        get { lock.withLock { _micGain } }
        set { lock.withLock { _micGain = newValue } }
    }

    /// Sets the destination for converted canonical buffers.
    func setSink(_ sink: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        lock.lock()
        self.sink = sink
        lock.unlock()
    }

    private func deliver(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let sink = self.sink
        lock.unlock()
        sink?(buffer)
    }

    func reset() {
        lock.lock()
        converters.removeAll()
        lock.unlock()
    }

    /// Converts and forwards a buffer. Safe to call from any capture thread.
    func process(_ buffer: AVAudioPCMBuffer, from source: AudioSource) {
        guard buffer.frameLength > 0 else { return }
        let inputFormat = buffer.format
        let gain: Float
        switch source {
        case .microphone: gain = micGain
        case .systemAudio: gain = 1.0
        }

        if inputFormat == Self.canonicalFormat {
            if gain != 1.0 { applyGain(gain, to: buffer) }
            deliver(buffer)
            return
        }

        let converter = converter(for: inputFormat)
        guard let converter else { return }

        // Estimate output capacity based on the sample-rate ratio.
        let ratio = Self.canonicalFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(
            pcmFormat: Self.canonicalFormat,
            frameCapacity: capacity
        ) else { return }

        var consumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        var error: NSError?
        let status = converter.convert(to: output, error: &error, withInputFrom: inputBlock)
        guard status != .error, error == nil, output.frameLength > 0 else { return }

        if gain != 1.0 { applyGain(gain, to: output) }
        deliver(output)
    }

    /// Multiplies each sample by `gain` and clips to [-1, 1] in place.
    private func applyGain(_ gain: Float, to buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let length = vDSP_Length(buffer.frameLength)
        var g = gain
        var lo: Float = -1.0
        var hi: Float = 1.0
        for ch in 0..<Int(buffer.format.channelCount) {
            vDSP_vsmul(data[ch], 1, &g, data[ch], 1, length)
            vDSP_vclip(data[ch], 1, &lo, &hi, data[ch], 1, length)
        }
    }

    private func converter(for inputFormat: AVAudioFormat) -> AVAudioConverter? {
        let key = inputFormat.description
        lock.lock()
        defer { lock.unlock() }
        if let existing = converters[key] { return existing }
        guard let converter = AVAudioConverter(from: inputFormat, to: Self.canonicalFormat) else {
            return nil
        }
        converters[key] = converter
        return converter
    }
}
