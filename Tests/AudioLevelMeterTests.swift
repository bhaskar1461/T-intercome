import XCTest
import AVFoundation
@testable import SplitBudsPTT

@MainActor
final class AudioLevelMeterTests: XCTestCase {

    var meter: AudioLevelMeter!

    override func setUp() async throws {
        meter = AudioLevelMeter()
    }

    override func tearDown() async throws {
        meter = nil
    }

    func testInitialLevelsAreZero() {
        XCTAssertEqual(meter.leftLevel, 0.0)
        XCTAssertEqual(meter.rightLevel, 0.0)
        XCTAssertEqual(meter.rawMicLevel, 0.0)
    }

    func testStopMeteringResetsLevels() {
        meter.leftLevel = 0.8
        meter.rightLevel = 0.5
        meter.rawMicLevel = 0.9

        meter.stopMetering()

        XCTAssertEqual(meter.leftLevel, 0.0)
        XCTAssertEqual(meter.rightLevel, 0.0)
        XCTAssertEqual(meter.rawMicLevel, 0.0)
    }
}

