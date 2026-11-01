import XCTest
import AVFoundation
@testable import SplitBudsPTT

@MainActor
final class AudioEngineTests: XCTestCase {

    var engine: WalkieAudioEngine!

    override func setUp() async throws {
        engine = WalkieAudioEngine()
    }

    override func tearDown() async throws {
        engine = nil
    }

    // MARK: - Channel Enum Tests

    func testEarbudChannelPanValues() {
        XCTAssertEqual(EarbudChannel.left.panValue, -1.0, "Left channel pan must be -1.0 (100% Left)")
        XCTAssertEqual(EarbudChannel.right.panValue, 1.0, "Right channel pan must be +1.0 (100% Right)")
    }

    func testEarbudChannelIdentifiers() {
        XCTAssertEqual(EarbudChannel.left.rawValue, "CH-L")
        XCTAssertEqual(EarbudChannel.right.rawValue, "CH-R")
        XCTAssertEqual(EarbudChannel.left.displayName, "Left Bud")
        XCTAssertEqual(EarbudChannel.right.displayName, "Right Bud")
    }

    // MARK: - PTT Transmission Control Tests

    func testStartTransmittingToLeftChannel() {
        engine.startTransmitting(to: .left)

        XCTAssertTrue(engine.isTransmitting, "Engine should report isTransmitting = true")
        XCTAssertEqual(engine.activeChannel, .left, "Active channel should be .left")
        XCTAssertEqual(engine.pttMixerNode.pan, -1.0, "pttMixerNode pan must be -1.0 for left bud")
        XCTAssertEqual(engine.pttMixerNode.outputVolume, 1.0, "pttMixerNode volume must be 1.0 during transmission")
    }

    func testStartTransmittingToRightChannel() {
        engine.startTransmitting(to: .right)

        XCTAssertTrue(engine.isTransmitting, "Engine should report isTransmitting = true")
        XCTAssertEqual(engine.activeChannel, .right, "Active channel should be .right")
        XCTAssertEqual(engine.pttMixerNode.pan, 1.0, "pttMixerNode pan must be +1.0 for right bud")
        XCTAssertEqual(engine.pttMixerNode.outputVolume, 1.0, "pttMixerNode volume must be 1.0 during transmission")
    }

    func testStopTransmitting() {
        engine.startTransmitting(to: .left)
        XCTAssertTrue(engine.isTransmitting)

        engine.stopTransmitting()

        XCTAssertFalse(engine.isTransmitting, "Engine should report isTransmitting = false")
        XCTAssertNil(engine.activeChannel, "Active channel should be nil after stopping")
        XCTAssertEqual(engine.pttMixerNode.outputVolume, 0.0, "pttMixerNode volume must be 0.0 to mute pass-through")
    }

    // MARK: - Mic Gain Tests

    func testMicGainAdjustment() {
        engine.micGain = 2.0
        XCTAssertEqual(engine.micGain, 2.0, "Mic gain should update to 2.0x")

        engine.micGain = 0.5
        XCTAssertEqual(engine.micGain, 0.5, "Mic gain should update to 0.5x minimum")

        engine.micGain = 3.0
        XCTAssertEqual(engine.micGain, 3.0, "Mic gain should update to 3.0x maximum")
    }

    // MARK: - Radio Filter Toggle Tests

    func testRadioFilterToggle() {
        XCTAssertTrue(engine.isRadioFilterEnabled, "Radio filter should be enabled by default")

        engine.setRadioFilter(enabled: false)
        XCTAssertFalse(engine.isRadioFilterEnabled, "Radio filter should be bypassed")

        engine.setRadioFilter(enabled: true)
        XCTAssertTrue(engine.isRadioFilterEnabled, "Radio filter should be re-enabled")
    }
}
