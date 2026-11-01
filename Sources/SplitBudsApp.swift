import SwiftUI
import UIKit

/// SplitBuds PTT — A split-channel walkie-talkie for Bluetooth stereo earbuds.
///
/// Locks Bluetooth output to Stereo A2DP (panning Left/Right independently)
/// while forcing microphone input to the iPhone's built-in mic to prevent
/// HFP mono fallback.
@main
struct SplitBudsApp: App {

    var body: some Scene {
        WindowGroup {
            WalkieTalkieView()
                .onAppear {
                    // Keep the screen awake during walkie-talkie use
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .onDisappear {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
                .statusBarHidden(false)
                .persistentSystemOverlays(.hidden)
        }
    }
}
