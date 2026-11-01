import SwiftUI
import UIKit

/// SplitBuds PTT — A split-channel walkie-talkie for Bluetooth stereo earbuds.
///
/// Locks Bluetooth output to Stereo A2DP (panning Left/Right independently)
/// while forcing microphone input to the iPhone's built-in mic to prevent
/// HFP mono fallback.
/// Runs 24/7 in background with continuous audio keep-alive (like Spotify).
@main
struct SplitBudsApp: App {

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WalkieTalkieView()
                .onAppear {
                    // Keep the screen awake during active walkie-talkie session
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .statusBarHidden(false)
                .persistentSystemOverlays(.hidden)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
    }
}
