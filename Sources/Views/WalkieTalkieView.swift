import SwiftUI
import UIKit
import AVFoundation

/// Nothing-inspired split-screen walkie-talkie UI.
///
/// Two large tactile Push-to-Talk zones (Left Bud / Right Bud) with real-time
/// audio level bars, route telemetry, and haptic feedback on press/release.
struct WalkieTalkieView: View {

    @StateObject private var audioEngine = WalkieAudioEngine()
    @StateObject private var routeMonitor = RouteMonitor()
    @StateObject private var levelMeter = AudioLevelMeter()
    @StateObject private var toneGenerator = ToneGenerator()
    @StateObject private var greetingManager = GreetingVoiceManager()

    @State private var isSetUp = false
    @State private var showDiagnostics = false
    @State private var isInvertedLayout = false
    @State private var setupError: String?
    @State private var micPermission: AVAudioApplication.recordPermission = AVAudioApplication.shared.recordPermission

    // Haptic generators
    private let impactPress = UIImpactFeedbackGenerator(style: .rigid)
    private let impactRelease = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Status bar
                statusBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Error banner
                if let error = setupError {
                    errorBanner(error)
                }

                // Check microphone permission status
                if micPermission != .granted {
                    permissionRequiredView
                } else {
                    // Startup Greeting Banner
                    if greetingManager.isGreetingActive {
                        startupGreetingBanner
                    }

                    // HFP Warning
                    if routeMonitor.isHFPDetected {
                        hfpWarningBanner
                    }

                    // PTT Zones
                    if isInvertedLayout {
                        pttCard(channel: .right)
                        Divider().background(Color.white.opacity(0.15))
                        pttCard(channel: .left)
                            .rotationEffect(.degrees(180))
                    } else {
                        pttCard(channel: .left)
                        Divider().background(Color.white.opacity(0.15))
                        pttCard(channel: .right)
                    }
                }

                // Bottom toolbar
                bottomToolbar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsSheetView(
                audioEngine: audioEngine,
                routeMonitor: routeMonitor,
                toneGenerator: toneGenerator,
                greetingManager: greetingManager
            )
        }
        .task {
            await setupAudio()
        }
        .onDisappear {
            teardownAudio()
        }
    }

    // MARK: - Setup

    private func setupAudio() async {
        guard !isSetUp else { return }

        let permission = AVAudioApplication.shared.recordPermission
        micPermission = permission

        if permission == .undetermined {
            let granted = await AVAudioApplication.requestRecordPermission()
            micPermission = AVAudioApplication.shared.recordPermission
            guard granted else { return }
        } else if permission == .denied {
            return
        }

        do {
            try AudioSessionManager.shared.configure()
            try audioEngine.buildGraph(toneGenerator: toneGenerator, greetingManager: greetingManager)
            levelMeter.startMetering(engine: audioEngine.engine, pttMixer: audioEngine.pttMixerNode)
            routeMonitor.startMonitoring()
            isSetUp = true
            setupError = nil
            greetingManager.playStartupGreetingSequence()
        } catch {
            setupError = error.localizedDescription
        }
    }

    private func teardownAudio() {
        levelMeter.stopMetering()
        routeMonitor.stopMonitoring()
        audioEngine.stopEngine()
        AudioSessionManager.shared.deactivate()
    }

    // MARK: - Permission View

    private var permissionRequiredView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.red.opacity(0.3), lineWidth: 2)
                    .frame(width: 80, height: 80)
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.red)
            }

            VStack(spacing: 8) {
                Text("MICROPHONE ACCESS")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text(micPermission == .denied
                     ? "Access was denied in iOS Settings. SplitBuds requires microphone input to route walkie-talkie audio to your earbuds."
                     : "SplitBuds requires direct iPhone microphone access to stream stereo audio to Left & Right earbuds independently.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Task {
                    if micPermission == .denied {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        let granted = await AVAudioApplication.requestRecordPermission()
                        micPermission = AVAudioApplication.shared.recordPermission
                        if granted {
                            await setupAudio()
                        }
                    }
                }
            } label: {
                Text(micPermission == .denied ? "OPEN SETTINGS" : "GRANT PERMISSION")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(8)
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            // App title
            VStack(alignment: .leading, spacing: 2) {
                Text("SPLITBUDS")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("PTT")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.red)
            }

            Spacer()

            // Voice Isolation chip (tap to configure via Apple System UI)
            Button {
                routeMonitor.showMicrophoneModePicker()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: routeMonitor.isVoiceIsolationActive ? "person.wave.2.fill" : "person.wave.2")
                        .font(.system(size: 8))
                    Text(routeMonitor.isVoiceIsolationActive ? "VOICE ISO" : "ISO OFF")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundColor(routeMonitor.isVoiceIsolationActive ? .green : .white.opacity(0.4))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(routeMonitor.isVoiceIsolationActive ? Color.green.opacity(0.12) : Color.white.opacity(0.06))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(routeMonitor.isVoiceIsolationActive ? Color.green.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                )
            }

            // Route status dot
            HStack(spacing: 6) {
                Circle()
                    .fill(routeMonitor.isTrueStereoA2DP ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: routeMonitor.isTrueStereoA2DP ? .green : .red, radius: 4)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(routeMonitor.currentOutputName)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                    Text(routeMonitor.isTrueStereoA2DP ? "STEREO A2DP" : "NOT STEREO")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(routeMonitor.isTrueStereoA2DP ? .green : .red)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - PTT Card

    private func pttCard(channel: EarbudChannel) -> some View {
        let isActive = audioEngine.activeChannel == channel

        return GeometryReader { geo in
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 16)
                    .fill(isActive ? Color.red.opacity(0.15) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isActive ? Color.red : Color.white.opacity(0.1),
                                lineWidth: isActive ? 2 : 1
                            )
                    )

                VStack(spacing: 12) {
                    Spacer()

                    // Channel & User label
                    Text("TALK TO \(channel.userName.uppercased())")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))

                    // User Name & Channel ID
                    VStack(spacing: 2) {
                        Text(channel.userName.uppercased())
                            .font(.system(size: 36, weight: .heavy, design: .monospaced))
                            .foregroundColor(isActive ? .red : .white)
                        Text("\(channel.rawValue) · \(channel == .left ? "LEFT BUD" : "RIGHT BUD")")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                    }

                    // Level meter bar
                    levelBar(
                        level: channel == .left ? levelMeter.leftLevel : levelMeter.rightLevel,
                        isActive: isActive
                    )
                    .frame(height: 6)
                    .padding(.horizontal, 40)

                    // Status text
                    Text(isActive ? "● TRANSMITTING" : "HOLD TO TALK")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(isActive ? .red : .white.opacity(0.3))
                        .animation(.easeInOut(duration: 0.2), value: isActive)

                    Spacer()
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !audioEngine.isTransmitting || audioEngine.activeChannel != channel {
                            beginTransmission(channel: channel)
                        }
                    }
                    .onEnded { _ in
                        if audioEngine.activeChannel == channel {
                            endTransmission(channel: channel)
                        }
                    }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Level Bar

    private func levelBar(level: Float, isActive: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))

                // Fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(isActive ? Color.red : Color.white.opacity(0.2))
                    .frame(width: geo.size.width * CGFloat(level))
                    .animation(.linear(duration: 0.05), value: level)
            }
        }
    }

    // MARK: - HFP Warning

    private var hfpWarningBanner: some View {
        Button {
            routeMonitor.forceRelockA2DP()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.black)
                Text("HFP MONO DETECTED — TAP TO RE-LOCK A2DP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.yellow)
            .cornerRadius(8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: - Startup Greeting Banner

    private var startupGreetingBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .shadow(color: .red, radius: 4)

            Text("GREETING // \(greetingManager.currentGreetingText)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Spacer()

            Text("STEREO")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.15))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.white)
            Text(message)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.red.opacity(0.8))
        .cornerRadius(8)
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 20) {
            // Mic input name
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                Text(routeMonitor.currentInputName)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            // Invert layout toggle
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isInvertedLayout.toggle()
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Diagnostics button
            Button {
                showDiagnostics = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - PTT Actions

    private func beginTransmission(channel: EarbudChannel) {
        impactPress.impactOccurred()
        toneGenerator.playRogerBeep(channel: channel)
        audioEngine.startTransmitting(to: channel)
    }

    private func endTransmission(channel: EarbudChannel) {
        impactRelease.impactOccurred()
        audioEngine.stopTransmitting()
        toneGenerator.playRogerBeep(channel: channel)
    }
}

#Preview {
    WalkieTalkieView()
}
