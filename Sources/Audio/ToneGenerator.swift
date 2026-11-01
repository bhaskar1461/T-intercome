import AVFoundation
import Foundation
import os.log

/// Procedural tone synthesizer for walkie-talkie squelch beeps and stereo calibration tones.
///
/// All tones are generated mathematically — no external audio assets required.
/// Each tone is panned hard Left (-1.0) or Right (+1.0) to verify true stereo separation.
@MainActor
final class ToneGenerator: ObservableObject {

    // MARK: - Properties

    private weak var engine: AVAudioEngine?
    private let tonePlayerNode = AVAudioSourceNode? .none  // replaced by per-call source nodes
    private let logger = Logger(subsystem: "com.bhaskar.splitbudsptt", category: "ToneGenerator")

    /// Mixer to pan generated tones to a specific earbud.
    private let toneMixerNode = AVAudioMixerNode()

    /// Currently active source node (if any).
    private var activeSourceNode: AVAudioSourceNode?

    @Published private(set) var isPlayingTone = false

    // MARK: - Constants

    private let sampleRate: Double = 48_000.0
    private let rogerBeepFrequency: Float = 1200.0
    private let rogerBeepDuration: Double = 0.12           // 120ms burst
    private let leftTestFrequency: Float = 440.0           // A4
    private let rightTestFrequency: Float = 660.0          // E5
    private let testToneDuration: Double = 0.6             // 600ms pulse

    // MARK: - Setup

    /// Attaches the tone mixer to the given engine. Call once during graph build.
    func attach(to engine: AVAudioEngine) {
        self.engine = engine
        engine.attach(toneMixerNode)
        engine.connect(toneMixerNode, to: engine.mainMixerNode, format: nil)
        toneMixerNode.outputVolume = 0.8
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

    /// Generates a sine wave (optionally mixed with white noise) and routes it through `toneMixerNode`.
    private func playTone(frequency: Float, duration: Double, pan: Float, mixNoise: Bool) {
        guard let engine = engine, engine.isRunning else {
            logger.warning("Engine not running — cannot play tone.")
            return
        }

        // Remove any prior source node
        stopCurrentTone()

        let sr = Float(sampleRate)
        let totalSamples = Int(duration * sampleRate)
        var sampleIndex: Int = 0
        let noiseAmplitude: Float = mixNoise ? 0.15 : 0.0
        let toneAmplitude: Float = 0.7

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        let sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let count = Int(frameCount)

            for bufferIndex in 0..<bufferList.count {
                guard let samples = bufferList[bufferIndex].mData?.assumingMemoryBound(to: Float.self) else {
                    continue
                }

                for frame in 0..<count {
                    if sampleIndex >= totalSamples {
                        samples[frame] = 0.0
                    } else {
                        let phase = 2.0 * Float.pi * frequency * Float(sampleIndex) / sr
                        let sine = sinf(phase) * toneAmplitude

                        // White noise: random values in [-1, 1]
                        let noise = noiseAmplitude * Float.random(in: -1.0...1.0)

                        // Envelope: quick fade-in (2ms) and fade-out (10ms) to avoid clicks
                        let fadeInSamples = Int(0.002 * Double(sr))
                        let fadeOutSamples = Int(0.010 * Double(sr))
                        var envelope: Float = 1.0

                        if sampleIndex < fadeInSamples {
                            envelope = Float(sampleIndex) / Float(fadeInSamples)
                        } else if sampleIndex > totalSamples - fadeOutSamples {
                            let remaining = totalSamples - sampleIndex
                            envelope = Float(remaining) / Float(fadeOutSamples)
                        }

                        samples[frame] = (sine + noise) * envelope
                    }
                    sampleIndex += 1
                }
            }
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: toneMixerNode, format: format)
        toneMixerNode.pan = pan

        activeSourceNode = sourceNode
        isPlayingTone = true

        // Schedule cleanup after the tone duration
        let cleanupDelay = duration + 0.05
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(cleanupDelay))
            self?.stopCurrentTone()
        }

        logger.info("Playing tone: \(frequency)Hz, pan=\(pan), duration=\(duration)s, noise=\(mixNoise)")
    }

    /// Removes the active source node from the engine.
    private func stopCurrentTone() {
        if let node = activeSourceNode {
            engine?.disconnectNodeOutput(node)
            engine?.detach(node)
            activeSourceNode = nil
        }
        isPlayingTone = false
    }
}
