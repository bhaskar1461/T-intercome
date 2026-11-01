import AVFoundation
import Foundation
import os.log

/// Identifies which earbud receives the transmission.
enum EarbudChannel: String, CaseIterable, Identifiable {
    case left  = "CH-L"
    case right = "CH-R"

    var id: String { rawValue }

    /// AVAudioMixerNode pan value: -1.0 = full left, +1.0 = full right.
    var panValue: Float {
        switch self {
        case .left:  return -1.0
        case .right: return  1.0
        }
    }

    var displayName: String {
        switch self {
        case .left:  return "Left Bud"
        case .right: return "Right Bud"
        }
    }

    /// The user assigned to this earbud channel.
    var userName: String {
        switch self {
        case .left:  return "Bhaskar"
        case .right: return "Tanmayee"
        }
    }

    /// The personalized startup greeting for this user.
    var greetingText: String {
        "Hey \(userName)"
    }
}

/// Builds the low-latency AVAudioEngine graph that routes the iPhone mic
/// to either the Left (-1.0) or Right (+1.0) earbud with optional
/// walkie-talkie bandpass EQ filtering.
///
/// Graph topology:
/// ```
/// inputNode -> gainMixerNode -> bandpassEQ -> pttMixer -> mainMixerNode -> outputNode
///                                                ^
///                                          pan = -1 / +1
/// ```
@MainActor
final class WalkieAudioEngine: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isTransmitting = false
    @Published private(set) var activeChannel: EarbudChannel?
    @Published var isRadioFilterEnabled = true
    @Published var micGain: Float = 1.0 {       // 0.5x … 3.0x
        didSet { applyGain() }
    }

    // MARK: - Audio Nodes

    let engine = AVAudioEngine()

    /// Bandpass EQ for walkie-talkie RF voice profile (300Hz–3000Hz).
    private let bandpassEQ = AVAudioUnitEQ(numberOfBands: 2)

    /// Mixer node whose `pan` property steers audio to Left or Right earbud.
    let pttMixerNode = AVAudioMixerNode()

    /// Gain node for mic boost.
    private let gainMixerNode = AVAudioMixerNode()

    private let logger = Logger(subsystem: "com.bhaskar.splitbudsptt", category: "AudioEngine")

    // MARK: - Init

    init() {
        configureBandpassEQ()
    }

    // MARK: - Engine Setup

    /// Builds and prepares the audio graph. Call after `AudioSessionManager.configure()`.
    /// Attaches auxiliary generators (tones, greeting voices) BEFORE starting the engine
    /// to avoid CoreAudio graph re-connection crashes while running.
    func buildGraph(toneGenerator: ToneGenerator? = nil, greetingManager: GreetingVoiceManager? = nil) throws {
        // Stop engine cleanly if previously running
        if engine.isRunning {
            engine.stop()
        }

        let inputNode = engine.inputNode
        var inputFormat = inputNode.outputFormat(forBus: 0)

        // Validate hardware format; fall back if sample rate or channel count is 0
        if inputFormat.sampleRate == 0 || inputFormat.channelCount == 0 {
            logger.warning("Hardware input format invalid (sampleRate=0). Using standard 48kHz mono format.")
            inputFormat = AVAudioFormat(standardFormatWithSampleRate: 48000.0, channels: 1)
                ?? AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100.0, channels: 1, interleaved: false)!
        }

        logger.info("Input format: \(inputFormat.description)")

        // Attach core PTT nodes
        engine.attach(gainMixerNode)
        engine.attach(bandpassEQ)
        engine.attach(pttMixerNode)

        // Attach auxiliary subsystems BEFORE preparing engine
        toneGenerator?.attach(to: engine)
        greetingManager?.attach(to: engine)

        // Wire core mic path: input -> gain -> bandpass -> pttMixer -> mainMixer
        engine.connect(inputNode,      to: gainMixerNode, format: inputFormat)
        engine.connect(gainMixerNode,  to: bandpassEQ,    format: inputFormat)
        engine.connect(bandpassEQ,     to: pttMixerNode,  format: inputFormat)
        engine.connect(pttMixerNode,   to: engine.mainMixerNode, format: nil)

        // Start silent — gate closed
        pttMixerNode.outputVolume = 0.0
        pttMixerNode.pan = 0.0
        applyGain()

        engine.prepare()
        try engine.start()
        logger.info("AVAudioEngine successfully started.")

        // Start greeting player node now that engine is running
        greetingManager?.startPlayer()
    }

    /// Tears down the engine cleanly.
    func stopEngine() {
        engine.stop()
        logger.info("AVAudioEngine stopped.")
    }

    // MARK: - PTT Transmission Control

    /// Opens the mic gate and routes audio to the specified earbud channel.
    /// Thread-safe: all mutations happen on `@MainActor`.
    func startTransmitting(to channel: EarbudChannel) {
        logger.info("PTT ON → \(channel.rawValue) (pan: \(channel.panValue))")

        pttMixerNode.pan = channel.panValue
        // Instant gate-open (no ramp needed — squelch tone masks the onset)
        pttMixerNode.outputVolume = 1.0

        activeChannel = channel
        isTransmitting = true
    }

    /// Closes the mic gate.
    func stopTransmitting() {
        logger.info("PTT OFF")

        pttMixerNode.outputVolume = 0.0
        activeChannel = nil
        isTransmitting = false
    }

    // MARK: - EQ Configuration

    /// Configures the 2-band EQ as a bandpass filter: high-pass at 300Hz, low-pass at 3000Hz.
    /// This simulates the characteristic walkie-talkie / RF radio voice profile.
    private func configureBandpassEQ() {
        guard bandpassEQ.bands.count >= 2 else { return }

        // Band 0: High-pass at 300Hz — removes low-frequency rumble
        let hpBand = bandpassEQ.bands[0]
        hpBand.filterType = .highPass
        hpBand.frequency = 300.0
        hpBand.bandwidth = 1.0
        hpBand.gain = 0.0
        hpBand.bypass = false

        // Band 1: Low-pass at 3000Hz — removes high-frequency hiss
        let lpBand = bandpassEQ.bands[1]
        lpBand.filterType = .lowPass
        lpBand.frequency = 3000.0
        lpBand.bandwidth = 1.0
        lpBand.gain = 0.0
        lpBand.bypass = false
    }

    /// Toggles the radio bandpass filter on/off for raw vs. walkie-talkie voice.
    func setRadioFilter(enabled: Bool) {
        isRadioFilterEnabled = enabled
        bandpassEQ.bypass = !enabled
        logger.info("Radio EQ filter: \(enabled ? "ON" : "OFF")")
    }

    // MARK: - Gain

    /// Applies the current mic gain to the gain mixer node.
    private func applyGain() {
        gainMixerNode.outputVolume = micGain
    }
}
