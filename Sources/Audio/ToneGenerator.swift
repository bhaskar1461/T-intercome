import AVFoundation
import Foundation
import os.log

final class ToneRenderState: @unchecked Sendable {
    var sampleIndex: Int = 0
}

/// Procedural tone synthesizer for walkie-talkie squelch beeps and stereo calibration tones.
///
/// Uses an `AVAudioPlayerNode` with pre-rendered PCM buffers to prevent dynamic graph mutations
/// while the engine is running, eliminating CoreAudio graph crashes.
/// Each tone is panned hard Left (-1.0) or Right (+1.0) to verify true stereo separation.
@MainActor
final class ToneGenerator: ObservableObject {

    // MARK: - Properties

    private weak var engine: AVAudioEngine?
    private let logger = Logger(subsystem: "com.bhaskar.splitbudsptt", category: "ToneGenerator")

    /// Mixer to pan generated tones to a specific earbud.
    let toneMixerNode = AVAudioMixerNode()

    /// Player node to schedule pre-rendered tone buffers safely without graph modification.
    let playerNode = AVAudioPlayerNode()

    @Published private(set) var isPlayingTone = false

    private var isAttached = false

    // MARK: - Constants

    let sampleRate: Double = 48_000.0
    let rogerBeepFrequency: Float = 1200.0
    let rogerBeepDuration: Double = 0.12           // 120ms burst
    let leftTestFrequency: Float = 440.0           // A4
    let rightTestFrequency: Float = 660.0          // E5
    let testToneDuration: Double = 0.6             // 600ms pulse

    // MARK: - Setup

    /// Attaches the tone mixer and player node to the engine. Call during graph build.
    func attach(to engine: AVAudioEngine) {
        guard !isAttached else { return }
        self.engine = engine

        engine.attach(toneMixerNode)
        engine.attach(playerNode)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.connect(playerNode, to: toneMixerNode, format: format)
        engine.connect(toneMixerNode, to: engine.mainMixerNode, format: nil)

        toneMixerNode.outputVolume = 0.8
        isAttached = true
        logger.info("ToneGenerator attached to AVAudioEngine.")
    }

    /// Starts the tone player node after engine is running.
    func startPlayer() {
        if isAttached && !playerNode.isPlaying {
            playerNode.play()
        }
    }

    // MARK: - Roger Beep / Squelch

    /// Plays a short 1200Hz + white-noise burst in the target earbud.
    /// Used at PTT press (onset) and release (tail).
    func playRogerBeep(channel: EarbudChannel) {
        let frequency = rogerBeepFrequency
        let duration = rogerBeepDuration
        playTone(frequency: frequency, duration: duration, pan: channel.panValue, mixNoise: true)
    }

    // MARK: - Stereo Calibration Test Tones

    /// Plays a 440Hz sine pulse in the Left earbud only.
    func playTestToneLeft() {
        playTone(frequency: leftTestFrequency, duration: testToneDuration, pan: -1.0, mixNoise: false)
    }

    /// Plays a 660Hz sine pulse in the Right earbud only.
    func playTestToneRight() {
        playTone(frequency: rightTestFrequency, duration: testToneDuration, pan: 1.0, mixNoise: false)
    }

    // MARK: - Core Synthesis

    /// Synthesizes a PCM buffer and schedules it through `playerNode`.
    /// Zero dynamic audio graph reconnection — completely crash-proof.
    private func playTone(frequency: Float, duration: Double, pan: Float, mixNoise: Bool) {
        guard let engine = engine, engine.isRunning else {
            logger.warning("Engine not running — cannot play tone.")
            return
        }

        toneMixerNode.pan = pan

        guard let buffer = generatePCMBuffer(frequency: frequency, duration: duration, mixNoise: mixNoise) else {
            return
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }

        isPlayingTone = true
        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts) { [weak self] in
            Task { @MainActor [weak self] in
                self?.isPlayingTone = false
            }
        }
    }

    /// Procedurally renders a sine wave buffer with smooth envelope tapering.
    private func generatePCMBuffer(frequency: Float, duration: Double, mixNoise: Bool) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else {
            return nil
        }

        let sr = Float(sampleRate)
        let totalSamples = Int(frameCount)
        let noiseAmplitude: Float = mixNoise ? 0.15 : 0.0
        let toneAmplitude: Float = 0.7

        for i in 0..<totalSamples {
            let t = Float(i) / sr
            let sineVal = sin(2.0 * .pi * frequency * t)

            let noiseVal: Float
            if mixNoise {
                noiseVal = (Float.random(in: -1.0...1.0)) * noiseAmplitude
            } else {
                noiseVal = 0.0
            }

            // Apply quick attack and release envelope (first/last 200 samples) to prevent clicks
            let envelope: Float
            let rampLength = 200
            if i < rampLength {
                envelope = Float(i) / Float(rampLength)
            } else if i > totalSamples - rampLength {
                envelope = Float(totalSamples - i) / Float(rampLength)
            } else {
                envelope = 1.0
            }

            channelData[i] = (sineVal * toneAmplitude + noiseVal) * envelope
        }

        return buffer
    }
}
