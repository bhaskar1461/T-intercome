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

        inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        isTapInstalled = true
        logger.info("Audio level tap installed (bufferSize=512).")
    }

    /// Removes the tap from the input node.
    func stopMetering() {
        guard isTapInstalled, let engine = engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        isTapInstalled = false

        // Reset levels
        Task { @MainActor in
            self.leftLevel = 0.0
            self.rightLevel = 0.0
            self.rawMicLevel = 0.0
        }
        logger.info("Audio level tap removed.")
    }

    // MARK: - Buffer Processing

    /// Computes normalized RMS power from the audio buffer using vDSP.
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // Compute RMS of channel 0 (mono mic input)
        let samples = channelData[0]
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameLength))

        // Normalize to 0.0–1.0 range (clamp values above 1.0)
        // Typical voice RMS is 0.01–0.2; scale up for visual responsiveness
        let normalizedRMS = min(rms * 5.0, 1.0)

        // Determine which channel is active based on PTT mixer pan
        let currentPan = pttMixer?.pan ?? 0.0
        let currentVolume = pttMixer?.outputVolume ?? 0.0

        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Smooth the raw mic level
            self.rawMicLevel = self.rawMicLevel * self.smoothingFactor +
                               normalizedRMS * (1.0 - self.smoothingFactor)

            if currentVolume > 0.01 {
                // PTT is active — route level to the active channel
                if currentPan < -0.5 {
                    // Transmitting to Left
                    self.leftLevel = self.leftLevel * self.smoothingFactor +
                                     normalizedRMS * (1.0 - self.smoothingFactor)
                    self.rightLevel = self.rightLevel * self.smoothingFactor  // decay
                } else if currentPan > 0.5 {
                    // Transmitting to Right
                    self.rightLevel = self.rightLevel * self.smoothingFactor +
                                      normalizedRMS * (1.0 - self.smoothingFactor)
                    self.leftLevel = self.leftLevel * self.smoothingFactor   // decay
                }
            } else {
                // PTT is off — decay both channels
                self.leftLevel  *= self.smoothingFactor
                self.rightLevel *= self.smoothingFactor
            }
        }
    }
}
