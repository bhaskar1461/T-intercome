import AVFoundation
import SwiftUI

/// Slide-up diagnostics drawer with manual overrides for mic gain,
/// radio EQ filtering, stereo calibration, and iPhone mic sub-microphone selection.
struct DiagnosticsSheetView: View {

    @ObservedObject var audioEngine: WalkieAudioEngine
    @ObservedObject var routeMonitor: RouteMonitor
    @ObservedObject var toneGenerator: ToneGenerator

    @State private var availableDataSources: [AVAudioSessionDataSourceDescription] = []
    @State private var selectedDataSourceID: Int = 0

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // MARK: - Stereo Calibration
                        sectionCard(title: "STEREO CALIBRATION") {
                            VStack(spacing: 12) {
                                Text("Verify true Left/Right isolation")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))

                                HStack(spacing: 16) {
                                    calibrationButton(
                                        label: "TEST LEFT",
                                        sublabel: "440Hz · pan -1.0",
                                        color: .cyan
                                    ) {
                                        toneGenerator.playTestToneLeft()
                                    }

                                    calibrationButton(
                                        label: "TEST RIGHT",
                                        sublabel: "660Hz · pan +1.0",
                                        color: .orange
                                    ) {
                                        toneGenerator.playTestToneRight()
                                    }
                                }
                            }
                        }

                        // MARK: - Voice Isolation Mode
                        sectionCard(title: "VOICE ISOLATION (NEURAL ENGINE)") {
                            VStack(spacing: 14) {
                                Text("Isolates voice and cancels ambient noise using iPhone's Neural Engine.")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))

                                // Active mode banner
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(routeMonitor.isVoiceIsolationActive ? Color.green : Color.yellow)
                                        .frame(width: 8, height: 8)
                                        .shadow(color: routeMonitor.isVoiceIsolationActive ? .green : .yellow, radius: 4)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(routeMonitor.activeMicMode.rawValue.uppercased())
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(routeMonitor.isVoiceIsolationActive ? .green : .yellow)
                                        Text(routeMonitor.activeMicMode.subtitle)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.4))
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(
                                    (routeMonitor.isVoiceIsolationActive ? Color.green : Color.yellow)
                                        .opacity(0.08)
                                )
                                .cornerRadius(8)

                                // System UI Trigger Button
                                Button {
                                    AudioSessionManager.shared.showSystemMicrophoneModeUI()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "person.wave.2.fill")
                                            .font(.system(size: 12, weight: .bold))
                                        Text("CHANGE MIC MODE (SYSTEM UI)")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        Spacer()
                                        Image(systemName: "arrow.up.forward.app")
                                            .font(.system(size: 11))
                                    }
                                    .foregroundColor(.black)
                                    .padding(.vertical, 11)
                                    .padding(.horizontal, 12)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                }

                                // Supported modes breakdown
                                VStack(spacing: 6) {
                                    ForEach(MicrophoneIsolationMode.allCases) { mode in
                                        micModeRow(mode)
                                    }
                                }
                            }
                        }

                        // MARK: - Radio EQ Filter
                        sectionCard(title: "VOICE FILTER") {
                            VStack(spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(audioEngine.isRadioFilterEnabled ? "WALKIE-TALKIE RF" : "RAW STUDIO")
                                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                        Text(audioEngine.isRadioFilterEnabled
                                             ? "Bandpass 300Hz–3000Hz"
                                             : "Full spectrum pass-through")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.4))
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { audioEngine.isRadioFilterEnabled },
                                        set: { audioEngine.setRadioFilter(enabled: $0) }
                                    ))
                                    .tint(.red)
                                    .labelsHidden()
                                }
                            }
                        }

                        // MARK: - Mic Gain
                        sectionCard(title: "MIC BOOST") {
                            VStack(spacing: 12) {
                                HStack {
                                    Text(String(format: "%.1fx", audioEngine.micGain))
                                        .font(.system(size: 24, weight: .heavy, design: .monospaced))
                                        .foregroundColor(.white)
                                        .frame(width: 70, alignment: .leading)

                                    Slider(value: $audioEngine.micGain, in: 0.5...3.0, step: 0.1)
                                        .tint(.red)
                                }
                                HStack {
                                    Text("0.5x")
                                    Spacer()
                                    Text("3.0x")
                                }
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                            }
                        }

                        // MARK: - Mic DataSource Picker
                        sectionCard(title: "iPHONE MIC SELECTOR") {
                            VStack(spacing: 12) {
                                Text("Select sub-microphone polar pattern")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.4))

                                if availableDataSources.isEmpty {
                                    Text("No sub-microphones available")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.3))
                                        .padding(.vertical, 8)
                                } else {
                                    ForEach(availableDataSources, id: \.dataSourceID) { source in
                                        micSourceButton(source)
                                    }
                                }
                            }
                        }

                        // MARK: - Route Telemetry
                        sectionCard(title: "HARDWARE TELEMETRY") {
                            VStack(spacing: 8) {
                                telemetryRow(label: "INPUT", value: routeMonitor.currentInputName)
                                telemetryRow(label: "OUTPUT", value: routeMonitor.currentOutputName)
                                telemetryRow(
                                    label: "MODE",
                                    value: routeMonitor.isTrueStereoA2DP ? "STEREO A2DP ✓" : "NOT STEREO ✗",
                                    valueColor: routeMonitor.isTrueStereoA2DP ? .green : .red
                                )
                                telemetryRow(
                                    label: "VOICE ISO",
                                    value: routeMonitor.isVoiceIsolationActive ? "ACTIVE (NEURAL) ✓" : "\(routeMonitor.activeMicMode.rawValue.uppercased())",
                                    valueColor: routeMonitor.isVoiceIsolationActive ? .green : .yellow
                                )
                                if !routeMonitor.lastRouteChangeReason.isEmpty {
                                    telemetryRow(label: "LAST EVENT", value: routeMonitor.lastRouteChangeReason)
                                }

                                if routeMonitor.isHFPDetected {
                                    Button {
                                        routeMonitor.forceRelockA2DP()
                                    } label: {
                                        HStack {
                                            Image(systemName: "arrow.clockwise")
                                            Text("FORCE RE-LOCK A2DP")
                                        }
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.yellow)
                                        .cornerRadius(8)
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("DIAGNOSTICS")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            loadDataSources()
        }
    }

    // MARK: - Data Sources

    private func loadDataSources() {
        availableDataSources = AudioSessionManager.shared.availableMicDataSources
        if let current = AudioSessionManager.shared.lockedBuiltInMic?.selectedDataSource {
            selectedDataSourceID = current.dataSourceID.intValue
        }
    }

    // MARK: - Components

    private func sectionCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.red)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func calibrationButton(label: String, sublabel: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text(sublabel)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(0.15))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(color.opacity(0.3), lineWidth: 1)
            )
        }
        .disabled(toneGenerator.isPlayingTone)
        .opacity(toneGenerator.isPlayingTone ? 0.5 : 1.0)
    }

    private func micSourceButton(_ source: AVAudioSessionDataSourceDescription) -> some View {
        let isSelected = source.dataSourceID.intValue == selectedDataSourceID

        return Button {
            do {
                try AudioSessionManager.shared.selectMicDataSource(source)
                selectedDataSourceID = source.dataSourceID.intValue
            } catch {
                // Silently fail — diagnostics view
            }
        } label: {
            HStack {
                Image(systemName: isSelected ? "mic.circle.fill" : "mic.circle")
                    .foregroundColor(isSelected ? .red : .white.opacity(0.4))
                Text(source.dataSourceName)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.red.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
    }

    private func telemetryRow(label: String, value: String, valueColor: Color = .white) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: 70, alignment: .leading)

            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(valueColor)
                .lineLimit(1)

            Spacer()
        }
    }

    private func micModeRow(_ mode: MicrophoneIsolationMode) -> some View {
        let isActive = routeMonitor.activeMicMode == mode
        let isSupported = mode.isSupported

        return Button {
            AudioSessionManager.shared.showSystemMicrophoneModeUI()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 14))
                    .foregroundColor(
                        !isSupported ? .white.opacity(0.2) :
                        isActive ? (mode == .voiceIsolation ? .green : .white) :
                        .white.opacity(0.4)
                    )
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.rawValue.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(isSupported ? .white : .white.opacity(0.3))
                    Text(mode.subtitle)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer()

                if !isSupported {
                    Text("N/A")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                } else if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(mode == .voiceIsolation ? .green : .white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                isActive && isSupported
                    ? (mode == .voiceIsolation ? Color.green.opacity(0.12) : Color.white.opacity(0.08))
                    : Color.white.opacity(0.02)
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isActive && isSupported
                            ? (mode == .voiceIsolation ? Color.green.opacity(0.35) : Color.white.opacity(0.2))
                            : Color.white.opacity(0.05),
                        lineWidth: 1
                    )
            )
        }
        .disabled(!isSupported)
    }
}
