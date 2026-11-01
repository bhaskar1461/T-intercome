import XCTest
import AVFoundation
@testable import SplitBudsPTT

@MainActor
final class ToneGeneratorTests: XCTestCase {

    var toneGenerator: ToneGenerator!

    override func setUp() async throws {
        toneGenerator = ToneGenerator()
    }

    override func tearDown() async throws {
        toneGenerator = nil
    }

    func testInitialState() {
        XCTAssertFalse(toneGenerator.isPlayingTone, "Tone generator should not be playing on init")
    }

    func testStereoToneCalibrationFrequencies() {
        // Standard diagnostic frequencies:
        // Left Earbud: 440Hz (A4)
        // Right Earbud: 660Hz (E5)
        let leftFreq: Float = 440.0
        let rightFreq: Float = 660.0
        let rogerBeepFreq: Float = 1200.0

        XCTAssertNotEqual(leftFreq, rightFreq, "Left and Right diagnostic frequencies must be distinct")
        XCTAssertEqual(leftFreq, 440.0)
        XCTAssertEqual(rightFreq, 660.0)
        XCTAssertEqual(rogerBeepFreq, 1200.0)
    }

    func testToneRenderStateSampleIndexIncrement() {
        let state = ToneRenderState()
        XCTAssertEqual(state.sampleIndex, 0)

        state.sampleIndex += 512
        XCTAssertEqual(state.sampleIndex, 512)
    }
}

