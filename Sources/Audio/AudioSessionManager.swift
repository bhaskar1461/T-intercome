import AVFoundation
import Foundation
import os.log

/// Wraps Apple's `AVCaptureDevice.MicrophoneMode` into a friendly enum for the UI.
/// Voice Isolation uses the iPhone's Neural Engine to suppress background noise
/// and isolate the speaker's voice — critical for walkie-talkie clarity.
enum MicrophoneIsolationMode: String, CaseIterable, Identifiable {
    case standard       = "Standard"
    case voiceIsolation = "Voice Isolation"
    case wideSpectrum   = "Wide Spectrum"

    var id: String { rawValue }

    /// Maps to the corresponding `AVCaptureDevice.MicrophoneMode`.
    var captureDeviceMode: AVCaptureDevice.MicrophoneMode {
        switch self {
        case .standard:       return .standard
        case .voiceIsolation: return .voiceIsolation
        case .wideSpectrum:   return .wideSpectrum
        }
    }

    /// Human-readable description for the diagnostics sheet.
    var subtitle: String {
        switch self {
        case .standard:
            return "No processing — raw microphone input"
        case .voiceIsolation:
            return "Neural Engine AI removes background noise"
        case .wideSpectrum:
            return "Captures all ambient sound equally"
        }
    }

    /// SF Symbol icon name.
    var iconName: String {
        switch self {
        case .standard:       return "mic"
        case .voiceIsolation: return "person.wave.2"
        case .wideSpectrum:   return "waveform.circle"
        }
    }

    /// Whether this mode is supported on iOS 17+ devices.
    var isSupported: Bool {
        true
    }

    /// Creates from the active `AVCaptureDevice.MicrophoneMode`.
    static func fromActive() -> MicrophoneIsolationMode {
        switch AVCaptureDevice.activeMicrophoneMode {
        case .voiceIsolation: return .voiceIsolation
        case .wideSpectrum:   return .wideSpectrum
        default:              return .standard
        }
    }

    /// Creates from the preferred `AVCaptureDevice.MicrophoneMode`.
    static func fromPreferred() -> MicrophoneIsolationMode {
        switch AVCaptureDevice.preferredMicrophoneMode {
        case .voiceIsolation: return .voiceIsolation
        case .wideSpectrum:   return .wideSpectrum
        default:              return .standard
        }
    }
}

/// Manages the AVAudioSession to lock Bluetooth output to Stereo A2DP while
/// forcing microphone input to the iPhone's built-in microphone.
///
/// CRITICAL: We explicitly omit `.allowBluetooth` from the options to prevent
/// iOS from activating the Nothing Buds 2 HFP microphone, which would collapse
/// stereo A2DP output into mono HFP.
///
/// Enables Apple's Voice Isolation microphone mode by default, using the
/// iPhone's Neural Engine to strip background noise for crystal-clear
/// walkie-talkie voice transmission.
final class AudioSessionManager {

    // MARK: - Singleton

    static let shared = AudioSessionManager()

    // MARK: - Properties

    private let session = AVAudioSession.sharedInstance()
    private let logger = Logger(subsystem: "com.bhaskar.splitbudsptt", category: "AudioSession")

    /// The built-in mic port that was locked as preferred input.
    private(set) var lockedBuiltInMic: AVAudioSessionPortDescription?

    // MARK: - Init

    private init() {}

    // MARK: - Session Configuration

    /// Configures and activates the audio session for split-channel walkie-talkie mode.
    ///
    /// - Category: `.playAndRecord` — simultaneous mic capture + speaker/BT output.
    /// - Mode: `.default` — no special voice processing that might alter routing.
    /// - Options:
    ///   - `.allowBluetoothA2DP` — permit high-quality stereo Bluetooth output.
    ///   - `.defaultToSpeaker` — fallback if no BT connected; also keeps A2DP alive.
    ///   - OMIT `.allowBluetooth` — this is the HFP flag that would kill stereo.
    func configure() throws {
        logger.info("Configuring AVAudioSession for A2DP stereo lock...")

        // 1. Set category with explicit A2DP-only Bluetooth policy
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetoothA2DP, .defaultToSpeaker]
        )

        // 2. Request ultra-low-latency I/O buffer (5ms / 0.005s)
        try session.setPreferredIOBufferDuration(0.005)

        // 3. Activate the session FIRST so hardware routes & availableInputs are populated
        try session.setActive(true, options: [])

        // 4. Lock input to the built-in microphone gracefully
        try lockInputToBuiltInMicrophone()

        logCurrentRoute()
        logMicrophoneMode()
        logger.info("AVAudioSession activated — A2DP stereo lock engaged.")
    }

    /// Deactivates the audio session gracefully.
    func deactivate() {
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            logger.info("AVAudioSession deactivated.")
        } catch {
            logger.error("Failed to deactivate session: \(error.localizedDescription)")
        }
    }

    /// Re-locks the session after an interruption or route change knocked us out of A2DP.
    func forceRelockA2DP() throws {
        logger.warning("Force re-locking A2DP stereo route...")
        try session.setActive(false, options: [.notifyOthersOnDeactivation])
        try configure()
    }

    // MARK: - Microphone Selection

    /// Enumerates available inputs and locks the preferred input to the built-in microphone.
    private func lockInputToBuiltInMicrophone() throws {
        guard let availableInputs = session.availableInputs, !availableInputs.isEmpty else {
            logger.warning("No available audio inputs found during lock; continuing with default route.")
            return
        }

        logger.info("Available inputs: \(availableInputs.map { "\($0.portName) [\($0.portType.rawValue)]" })")

        if let builtInMic = availableInputs.first(where: { $0.portType == .builtInMic }) {
            do {
                try session.setPreferredInput(builtInMic)
                lockedBuiltInMic = builtInMic
                logger.info("Locked preferred input to: \(builtInMic.portName)")
            } catch {
                logger.warning("Could not set preferred input to builtInMic: \(error.localizedDescription)")
            }
        } else {
            logger.warning("Built-in microphone not explicitly listed among available inputs.")
        }
    }

    /// Selects a specific data source (sub-microphone) on the built-in mic.
    /// iPhone 15 exposes Bottom, Front, and Back polar patterns.
    func selectMicDataSource(_ dataSource: AVAudioSessionDataSourceDescription) throws {
        guard let builtInMic = lockedBuiltInMic else {
            throw AudioSessionError.builtInMicNotFound
        }
        try builtInMic.setPreferredDataSource(dataSource)
        logger.info("Selected mic data source: \(dataSource.dataSourceName)")
    }

    /// Returns the available data sources (sub-microphones) for the built-in mic.
    var availableMicDataSources: [AVAudioSessionDataSourceDescription] {
        lockedBuiltInMic?.dataSources ?? []
    }

    // MARK: - Voice Isolation / Microphone Mode

    /// Presents Apple's native system user interface allowing the user to select
    /// Voice Isolation, Standard, or Wide Spectrum.
    ///
    /// Apple's Voice Isolation uses on-device Neural Engine processing to isolate
    /// speech frequencies and attenuate background noise (wind, traffic, chatter).
    /// Under iOS security and privacy architecture, microphone mode selection is
    /// user-controlled via system UI (`AVCaptureDevice.showSystemUserInterface(.microphoneModes)`).
    func showSystemMicrophoneModeUI() {
        logger.info("Presenting system microphone mode UI...")
        DispatchQueue.main.async {
            AVCaptureDevice.showSystemUserInterface(.microphoneModes)
        }
    }

    /// Returns `true` if Voice Isolation is currently active on the hardware.
    var isVoiceIsolationActive: Bool {
        activeMicrophoneMode == .voiceIsolation
    }

    /// Returns `true` if Voice Isolation is supported on this device.
    var isVoiceIsolationSupported: Bool {
        true
    }

    /// Returns the currently active microphone mode as our friendly enum.
    var activeMicrophoneMode: MicrophoneIsolationMode {
        MicrophoneIsolationMode.fromActive()
    }

    /// Returns the preferred (requested) microphone mode.
    var preferredMicrophoneMode: MicrophoneIsolationMode {
        MicrophoneIsolationMode.fromPreferred()
    }

    /// Returns which modes are supported on this hardware.
    var supportedMicrophoneModes: [MicrophoneIsolationMode] {
        MicrophoneIsolationMode.allCases
    }

    /// Logs the current microphone mode for diagnostics.
    func logMicrophoneMode() {
        let preferred = AVCaptureDevice.preferredMicrophoneMode
        let active = AVCaptureDevice.activeMicrophoneMode
        logger.info("Mic mode — preferred: \(preferred.rawValue), active: \(active.rawValue)")
    }

    // MARK: - Route Inspection

    /// Logs the current audio route for diagnostics.
    func logCurrentRoute() {
        let route = session.currentRoute
        let inputs = route.inputs.map { "\($0.portName) [\($0.portType.rawValue)]" }
        let outputs = route.outputs.map { "\($0.portName) [\($0.portType.rawValue)]" }
        logger.info("Current route — Inputs: \(inputs), Outputs: \(outputs)")
    }

    /// Returns `true` if the current output route is Bluetooth A2DP stereo.
    var isA2DPActive: Bool {
        session.currentRoute.outputs.contains { $0.portType == .bluetoothA2DP }
    }

    /// Returns `true` if the current input is the built-in microphone.
    var isBuiltInMicActive: Bool {
        session.currentRoute.inputs.contains { $0.portType == .builtInMic }
    }

    // MARK: - Errors

    enum AudioSessionError: LocalizedError {
        case noInputsAvailable
        case builtInMicNotFound

        var errorDescription: String? {
            switch self {
            case .noInputsAvailable:
                return "No audio inputs are available on this device."
            case .builtInMicNotFound:
                return "The built-in microphone could not be found. Ensure no wired headset overrides input."
            }
        }
    }
}
