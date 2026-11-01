import AVFoundation
import Combine
import Foundation
import os.log

/// Manages personalized audio and visual startup greetings for Bhaskar and Tanmayee.
///
/// Routes "Hey Bhaskar" independently to the Left earbud (CH-L, pan: -1.0)
/// and "Hey Tanmayee" to the Right earbud (CH-R, pan: +1.0) using AVSpeechSynthesizer.
@MainActor
final class GreetingVoiceManager: ObservableObject {

    // MARK: - Published State

    @Published var leftUserName: String = "Bhaskar"
    @Published var rightUserName: String = "Tanmayee"
    @Published var isGreetingActive: Bool = false
    @Published var currentGreetingText: String = ""

    // MARK: - Private Properties

    private let synthesizer = AVSpeechSynthesizer()
    private weak var engine: AVAudioEngine?
    let playerNode = AVAudioPlayerNode()
    let greetingMixer = AVAudioMixerNode()
    private let logger = Logger(subsystem: "com.bhaskar.splitbudsptt", category: "GreetingVoice")

    private var isGraphAttached = false

    // MARK: - Setup

    /// Attaches the greeting player node to the engine's mainMixerNode.
    func attach(to engine: AVAudioEngine) {
        guard !isGraphAttached else { return }
        self.engine = engine

        engine.attach(playerNode)
        engine.attach(greetingMixer)

        // Wire player -> greetingMixer -> mainMixerNode
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000.0, channels: 2)
            ?? engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(playerNode, to: greetingMixer, format: format)
        engine.connect(greetingMixer, to: engine.mainMixerNode, format: nil)

        greetingMixer.outputVolume = 1.0
        isGraphAttached = true
        logger.info("GreetingVoiceManager attached to AVAudioEngine.")
    }

    /// Starts the player node after engine has started.
    func startPlayer() {
        if isGraphAttached && !playerNode.isPlaying {
            playerNode.play()
        }
    }

    // MARK: - Greeting Playback

    /// Plays the personalized startup greeting sequence:
    /// 1. "Hey Bhaskar" in Left Earbud (pan: -1.0)
    /// 2. "Hey Tanmayee" in Right Earbud (pan: +1.0)
    func playStartupGreetingSequence() {
        guard !isGreetingActive else { return }
        isGreetingActive = true
        logger.info("Starting personalized startup greeting sequence...")

        Task {
            // Short initial pause to let Bluetooth A2DP audio link settle
            try? await Task.sleep(for: .milliseconds(400))

            // 1. Greet Bhaskar (Left Earbud)
            currentGreetingText = "HEY BHASKAR"
            await speakToChannel(text: "Hey Bhaskar", pan: -1.0)

            // Small pause between greetings
            try? await Task.sleep(for: .milliseconds(300))

            // 2. Greet Tanmayee (Right Earbud)
            currentGreetingText = "HEY TANMAYEE"
            await speakToChannel(text: "Hey Tanmayee", pan: 1.0)

            // Conclude greeting
            try? await Task.sleep(for: .milliseconds(600))
            isGreetingActive = false
            currentGreetingText = ""
            logger.info("Startup greeting sequence finished.")
        }
    }

    // MARK: - Speech Synthesis

    /// Speaks the given text panned to a specific earbud channel (-1.0 Left / +1.0 Right).
    private func speakToChannel(text: String, pan: Float) async {
        greetingMixer.pan = pan

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95 // Crisp, clear pace
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Select high quality English voice
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }

        // Render speech to audio buffer if engine is running for true stereo isolation
        if let engine = engine, engine.isRunning {
            await withCheckedContinuation { continuation in
                var buffers: [AVAudioPCMBuffer] = []

                synthesizer.write(utterance) { [weak self] buffer in
                    guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }
                    if pcmBuffer.frameLength > 0 {
                        buffers.append(pcmBuffer)
                    } else {
                        // End of utterance synthesis
                        Task { @MainActor [weak self] in
                            self?.scheduleAndPlayBuffers(buffers) {
                                continuation.resume()
                            }
                        }
                    }
                }
            }
        } else {
            // Direct playback fallback if engine is not running
            await withCheckedContinuation { continuation in
                synthesizer.speak(utterance)
                Task {
                    try? await Task.sleep(for: .milliseconds(1100))
                    continuation.resume()
                }
            }
        }
    }

    /// Schedules and plays synthesized PCM buffers through playerNode with completion callback.
    private func scheduleAndPlayBuffers(_ buffers: [AVAudioPCMBuffer], completion: @escaping () -> Void) {
        guard !buffers.isEmpty else {
            completion()
            return
        }

        var remaining = buffers.count
        for buffer in buffers {
            playerNode.scheduleBuffer(buffer) {
                Task { @MainActor in
                    remaining -= 1
                    if remaining <= 0 {
                        completion()
                    }
                }
            }
        }
    }
}
