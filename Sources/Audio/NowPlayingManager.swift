import Foundation
import MediaPlayer
import UIKit
import os.log

/// Manages Lock Screen, Control Center, and Dynamic Island Now Playing controls.
///
/// Communicating with `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` informs
/// the iOS watchdog that SplitBuds PTT is an active audio/media application (like Spotify),
/// preventing the system from suspending or killing the process in the background.
@MainActor
final class NowPlayingManager {

    static let shared = NowPlayingManager()

    private let logger = Logger(subsystem: "com.bhaskar.splitbudsptt", category: "NowPlaying")
    private var isConfigured = false

    private init() {}

    /// Configures remote command center event handlers for background audio priority.
    func setupRemoteCommands() {
        guard !isConfigured else { return }

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.updateNowPlaying(isTransmitting: false, channel: nil)
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            return .success
        }

        isConfigured = true
        updateNowPlaying(isTransmitting: false, channel: nil)
        logger.info("MPRemoteCommandCenter and NowPlaying initialized.")
    }

    /// Updates the metadata shown on the iOS Lock Screen and Control Center.
    func updateNowPlaying(isTransmitting: Bool, channel: EarbudChannel?) {
        var info = [String: Any]()

        info[MPMediaItemPropertyTitle] = "SPLITBUDS PTT"

        if isTransmitting, let channel = channel {
            info[MPMediaItemPropertyArtist] = "TALKING TO \(channel.userName.uppercased()) [\(channel.displayName.uppercased())]"
        } else {
            info[MPMediaItemPropertyArtist] = "READY · BHASKAR (L) · TANMAYEE (R)"
        }

        info[MPMediaItemPropertyAlbumTitle] = "Stereo Earbud Walkie-Talkie"
        // 1.0 tells iOS audio is actively rendering, keeping background priority alive
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        info[MPNowPlayingInfoPropertyIsLiveStream] = true

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
