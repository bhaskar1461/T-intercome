import AVFoundation
import Combine
import Foundation
import UIKit
import os.log

/// Continuously monitors iOS audio route changes and publishes live telemetry
/// about input/output ports, stereo A2DP status, and Voice Isolation mic mode.
///
/// Warns the user if Bluetooth drops from Stereo A2DP into Mono HFP, providing
/// a one-tap recovery action via `forceRelockA2DP()`.
@MainActor
final class RouteMonitor: ObservableObject {

    // MARK: - Published State

    @Published var currentInputName: String = "Unknown"
    @Published var currentOutputName: String = "Unknown"
    @Published var isTrueStereoA2DP: Bool = false
    @Published var isHFPDetected: Bool = false
    @Published var lastRouteChangeReason: String = ""

    /// The currently active microphone processing mode (Standard / Voice Isolation / Wide Spectrum).
    @Published var activeMicMode: MicrophoneIsolationMode = .standard

    /// The user's preferred (requested) microphone mode.
    @Published var preferredMicMode: MicrophoneIsolationMode = .voiceIsolation

    // MARK: - Private

    private let session = AVAudioSession.sharedInstance()
    private let logger = Logger(subsystem: "com.bhaskar.splitbudsptt", category: "RouteMonitor")
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        // Safe default init — avoid querying hardware before session activation
    }

    // MARK: - Observation

    /// Starts observing audio route change and interruption notifications.
    func startMonitoring() {
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleRouteChange(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleInterruption(notification)
            }
            .store(in: &cancellables)

        // Observe app becoming active (e.g. after user dismisses system Mic Mode interface)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateRouteInfo()
            }
            .store(in: &cancellables)

        logger.info("Route monitoring started.")
        updateRouteInfo()
    }

    /// Stops observing notifications.
    func stopMonitoring() {
        cancellables.removeAll()
        logger.info("Route monitoring stopped.")
    }

    // MARK: - Route Change Handler

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            updateRouteInfo()
            return
        }

        let reasonString: String
        switch reason {
        case .newDeviceAvailable:      reasonString = "New device connected"
        case .oldDeviceUnavailable:    reasonString = "Device disconnected"
        case .categoryChange:          reasonString = "Category changed"
        case .override:                reasonString = "Route override"
        case .wakeFromSleep:           reasonString = "Wake from sleep"
        case .noSuitableRouteForCategory: reasonString = "No suitable route"
        case .routeConfigurationChange: reasonString = "Route config changed"
        default:                       reasonString = "Unknown (\(reasonValue))"
        }

        lastRouteChangeReason = reasonString
        logger.info("Route changed: \(reasonString)")
        updateRouteInfo()
    }

    // MARK: - Interruption Handler

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            logger.warning("Audio session interrupted — another app took audio.")
        case .ended:
            logger.info("Audio interruption ended — attempting re-lock.")
            let options = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                try? AudioSessionManager.shared.forceRelockA2DP()
            }
        @unknown default:
            break
        }

        updateRouteInfo()
    }

    // MARK: - Route Inspection

    /// Reads the current audio route and updates all published properties.
    func updateRouteInfo() {
        let route = session.currentRoute

        // Input
        if let input = route.inputs.first {
            currentInputName = "\(input.portName)"
        } else {
            currentInputName = "No Input"
        }

        // Output
        if let output = route.outputs.first {
            currentOutputName = "\(output.portName)"
        } else {
            currentOutputName = "No Output"
        }

        // Stereo A2DP detection
        let hasA2DP = route.outputs.contains {
            $0.portType == .bluetoothA2DP || $0.portType == .headphones
        }
        let hasHFP = route.outputs.contains { $0.portType == .bluetoothHFP }

        isTrueStereoA2DP = hasA2DP && !hasHFP
        isHFPDetected = hasHFP

        if hasHFP {
            logger.warning("⚠️ HFP DETECTED — stereo output collapsed to mono!")
        }

        // Microphone processing mode
        activeMicMode = AudioSessionManager.shared.activeMicrophoneMode
        preferredMicMode = AudioSessionManager.shared.preferredMicrophoneMode

        logger.info("Route: in=\(self.currentInputName), out=\(self.currentOutputName), A2DP=\(self.isTrueStereoA2DP), micMode=\(self.activeMicMode.rawValue)")
    }

    // MARK: - Recovery

    /// Attempts to force the session back to A2DP stereo by re-configuring the audio session.
    func forceRelockA2DP() {
        do {
            try AudioSessionManager.shared.forceRelockA2DP()
            updateRouteInfo()
            logger.info("A2DP re-lock successful.")
        } catch {
            logger.error("A2DP re-lock failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Voice Isolation Controls

    /// Presents Apple's native system interface for Voice Isolation selection.
    func showMicrophoneModePicker() {
        AudioSessionManager.shared.showSystemMicrophoneModeUI()
    }

    /// Whether Apple's Neural Engine Voice Isolation is actively running.
    var isVoiceIsolationActive: Bool {
        activeMicMode == .voiceIsolation
    }
}
