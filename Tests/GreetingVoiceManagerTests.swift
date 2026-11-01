import XCTest
import AVFoundation
@testable import SplitBudsPTT

@MainActor
final class GreetingVoiceManagerTests: XCTestCase {

    var greetingManager: GreetingVoiceManager!

    override func setUp() async throws {
        greetingManager = GreetingVoiceManager()
    }

    override func tearDown() async throws {
        greetingManager = nil
    }

    func testDefaultPartnerUserNames() {
        XCTAssertEqual(greetingManager.leftUserName, "Bhaskar", "Left channel user must be Bhaskar")
        XCTAssertEqual(greetingManager.rightUserName, "Tanmayee", "Right channel user must be Tanmayee")
    }

    func testEarbudChannelUserNames() {
        XCTAssertEqual(EarbudChannel.left.userName, "Bhaskar")
        XCTAssertEqual(EarbudChannel.right.userName, "Tanmayee")
        XCTAssertEqual(EarbudChannel.left.greetingText, "Hey Bhaskar")
        XCTAssertEqual(EarbudChannel.right.greetingText, "Hey Tanmayee")
    }

    func testChannelPanSeparationForPartners() {
        // Bhaskar must route strictly to Left earbud (-1.0)
        XCTAssertEqual(EarbudChannel.left.panValue, -1.0)

        // Tanmayee must route strictly to Right earbud (+1.0)
        XCTAssertEqual(EarbudChannel.right.panValue, 1.0)
    }
}

