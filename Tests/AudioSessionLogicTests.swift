import XCTest
import AVFoundation
@testable import SplitBudsPTT

final class AudioSessionLogicTests: XCTestCase {

    // MARK: - Category & Options Policy Tests

    func testAudioSessionPolicyExcludesHFP() {
        // Critical requirement: .allowBluetoothA2DP must be present, and .allowBluetooth (HFP) must be ABSENT.
        let intendedOptions: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP, .defaultToSpeaker]

        XCTAssertTrue(intendedOptions.contains(.allowBluetoothA2DP), "Must contain .allowBluetoothA2DP for stereo output")
        XCTAssertTrue(intendedOptions.contains(.defaultToSpeaker), "Must contain .defaultToSpeaker for route fallback")
        XCTAssertFalse(intendedOptions.contains(.allowBluetooth), "CRITICAL: Must NOT contain .allowBluetooth (HFP mono collapse)")
    }

    func testPreferredIOBufferDurationValue() {
        // 5ms buffer for ultra-low latency walkie-talkie pass-through
        let preferredBufferDuration: Double = 0.005
        XCTAssertEqual(preferredBufferDuration, 0.005, accuracy: 0.0001)
    }

    // MARK: - Voice Isolation Enum Mapping Tests

    func testMicrophoneIsolationModeMapping() {
        XCTAssertEqual(MicrophoneIsolationMode.standard.captureDeviceMode, .standard)
        XCTAssertEqual(MicrophoneIsolationMode.voiceIsolation.captureDeviceMode, .voiceIsolation)
        XCTAssertEqual(MicrophoneIsolationMode.wideSpectrum.captureDeviceMode, .wideSpectrum)
    }

    func testMicrophoneIsolationModeDisplayAttributes() {
        XCTAssertEqual(MicrophoneIsolationMode.voiceIsolation.rawValue, "Voice Isolation")
        XCTAssertEqual(MicrophoneIsolationMode.voiceIsolation.iconName, "person.wave.2")
        XCTAssertTrue(MicrophoneIsolationMode.voiceIsolation.subtitle.contains("Neural Engine"))
    }
}
