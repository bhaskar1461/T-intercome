import AVFoundation
import Accelerate
import Combine
import Foundation
import os.log

/// Real-time RMS audio level metering using vDSP (Accelerate framework).
///
/// Installs a tap on the mic node and publishes smoothed Left/Right channel
/// power levels for the UI visualizers.
@MainActor
final class AudioLevelMeter: ObservableObject {

    // MARK: - Published Levels

    /// Normalized RMS power level for the Left channel (0.0 – 1.0).
    @Published var leftLevel: Float = 0.0

    /// Normalized RMS power level for the Right channel (0.0 – 1.0).
    @Published var rightLevel: Float = 0.0

    /// Raw mono RMS level from the microphone before panning.
    @Published var rawMicLevel: Float = 0.0

    // MARK: - Properties

    private weak var engine: AVAudioEngine?
    private weak var pttMixer: AVAudioMixerNode?
    private let logger = Logger(subsystem: "com.bhaskar.splitbudsptt", category: "LevelMeter")

    /// Exponential smoothing factor (0 = no smoothing, 1 = frozen).
    private let smoothingFactor: Float = 0.3

    private var isTapInstalled = false

    // MARK: - Setup

    /// Installs a tap on the engine's input node to capture RMS levels.
    ///
    /// - Parameters:
    ///   - engine: The active `AVAudioEngine`.
    ///   - pttMixer: The PTT mixer node whose `pan` determines which channel is active.
    func startMetering(engine: AVAudioEngine, pttMixer: AVAudioMixerNode) {
        guard !isTapInstalled else { return }

        self.engine = engine
        self.pttMixer = pttMixer

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self, weak pttMixer] buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            let samples = channelData[0]
            var rms: Float = 0.0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameLength))
            let normalizedRMS = min(rms * 5.0, 1.0)
            let pan = pttMixer?.pan ?? 0.0
            let volume = pttMixer?.outputVolume ?? 0.0

            Task { @MainActor [weak self] in
                self?.applyLevel(normalizedRMS, pan: pan, volume: volume)
            }
        }

        isTapInstalled = true
        logger.info("Audio level tap installed (bufferSize=512).")
    }

    /// Removes the tap from the input node and resets levels to zero.
    func stopMetering() {
        if isTapInstalled, let engine = engine {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        leftLevel = 0.0
        rightLevel = 0.0
        rawMicLevel = 0.0
        logger.info("Audio level tap removed.")
    }

    // MARK: - Level Smoothing

    /// Updates smoothed levels on the main actor.
    private func applyLevel(_ normalizedRMS: Float, pan: Float, volume: Float) {
        rawMicLevel = rawMicLevel * smoothingFactor + normalizedRMS * (1.0 - smoothingFactor)

        if volume > 0.01 {
            if pan < -0.5 {
                leftLevel = leftLevel * smoothingFactor + normalizedRMS * (1.0 - smoothingFactor)
                rightLevel = rightLevel * smoothingFactor
            } else if pan > 0.5 {
                rightLevel = rightLevel * smoothingFactor + normalizedRMS * (1.0 - smoothingFactor)
                leftLevel = leftLevel * smoothingFactor
            }
        } else {
            leftLevel *= smoothingFactor
            rightLevel *= smoothingFactor
        }
    }
}
