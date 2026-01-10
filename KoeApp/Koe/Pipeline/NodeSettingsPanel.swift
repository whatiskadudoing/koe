import KoeDomain
import KoeUI
import SwiftUI

// MARK: - Node Settings Content (used inside modal)

/// Content view for node settings - used inside SettingsModal
struct NodeSettingsContent: View {
    let stage: PipelineStageInfo
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        switch stage {
        case .hotkeyTrigger:
            HotkeyTriggerSettings(appState: appState)
        case .voiceTrigger:
            VoiceTriggerSettings(appState: appState)
        case .recorder:
            RecorderSettings(appState: appState)
        case .transcribeApple:
            AppleSpeechSettings(appState: appState)
        case .transcribeWhisperKitBalanced:
            WhisperKitBalancedSettings(appState: appState)
        case .transcribeWhisperKitAccurate:
            WhisperKitAccurateSettings(appState: appState)
        case .aiFast:
            AIFastSettings(appState: appState)
        case .aiBalanced:
            AIBalancedSettings(appState: appState)
        case .aiReasoning:
            AIReasoningSettings(appState: appState)
        case .autoType:
            AutoTypeSettings(appState: appState)
        case .autoEnter:
            AutoEnterSettings(appState: appState)
        }
    }
}

// MARK: - Hotkey Trigger Settings

struct HotkeyTriggerSettings: View {
    @Bindable var appState: AppState

    private let presets: [(name: String, keyCode: UInt32, modifiers: Int, display: String)] = [
        ("Option + Space", 49, 2, "⌥ Space"),
        ("Right Option", 61, 0, "R-⌥"),
        ("Ctrl + Space", 49, 4, "⌃ Space"),
        ("F5", 96, 0, "F5"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Press and hold to record")
                .font(.system(size: 12))
                .foregroundColor(KoeColors.textSecondary)

            // Current hotkey display
            HStack {
                Text("Current:")
                    .font(.system(size: 11))
                    .foregroundColor(KoeColors.textLight)

                Text(appState.hotkeyDisplayString)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(KoeColors.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(KoeColors.surface)
                    .cornerRadius(6)
            }

            // Preset shortcuts
            VStack(alignment: .leading, spacing: 6) {
                Text("Presets")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(KoeColors.textTertiary)

                HStack(spacing: 6) {
                    ForEach(presets, id: \.name) { preset in
                        Button(action: {
                            appState.hotkeyKeyCode = preset.keyCode
                            appState.hotkeyModifiers = preset.modifiers
                        }) {
                            Text(preset.display)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(isSelected(preset) ? .white : KoeColors.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(isSelected(preset) ? KoeColors.accent : KoeColors.surface)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func isSelected(_ preset: (name: String, keyCode: UInt32, modifiers: Int, display: String)) -> Bool {
        appState.hotkeyKeyCode == preset.keyCode && appState.hotkeyModifiers == preset.modifiers
    }
}

// MARK: - Voice Trigger Settings

struct VoiceTriggerSettings: View {
    @Bindable var appState: AppState
    @State private var showPhase1 = false
    @State private var showPhase2 = false
    @State private var showPhase3 = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Enable/disable toggle
            HStack {
                Toggle(isOn: $appState.isCommandListeningEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 12))
                            .foregroundColor(
                                appState.isCommandListeningEnabled ? KoeColors.accent : KoeColors.textLight)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Voice Activation")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(KoeColors.accent)

                            Text(
                                appState.voiceCommandSettings.useExtendedTrigger
                                    ? "Say \"hey koe\" to start" : "Say \"kon\" to start recording"
                            )
                            .font(.system(size: 10))
                            .foregroundColor(KoeColors.textLight)
                        }
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!appState.hasVoiceProfile)
            }

            // Voice profile status
            if appState.hasVoiceProfile {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.stateComplete)
                    Text("Voice trained")
                        .font(.system(size: 11))
                        .foregroundColor(KoeColors.textTertiary)

                    Spacer()

                    Button("Retrain") {
                        NotificationCenter.default.post(name: .showVoiceTraining, object: nil)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(KoeColors.accent)
                    .buttonStyle(.plain)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(KoeColors.stateTranscribing)
                        Text("Voice training required")
                            .font(.system(size: 11))
                            .foregroundColor(KoeColors.stateTranscribing)
                    }

                    Button(action: {
                        NotificationCenter.default.post(name: .showVoiceTraining, object: nil)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.wave.2")
                                .font(.system(size: 11))
                            Text("Train Your Voice")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(KoeColors.accent)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Status indicator when enabled
            if appState.isCommandListeningEnabled && appState.hasVoiceProfile {
                Divider()

                HStack(spacing: 6) {
                    Circle()
                        .fill(KoeColors.stateComplete)
                        .frame(width: 6, height: 6)
                    Text(
                        appState.voiceCommandSettings.useExtendedTrigger
                            ? "Listening for \"hey koe\"..." : "Listening for \"kon\"..."
                    )
                    .font(.system(size: 11))
                    .foregroundColor(KoeColors.textTertiary)
                }
            }

            // MARK: - Phase 1: Voice Activity Detection (Always On)
            Divider()

            VoiceTriggerPhase1Settings(appState: appState, isExpanded: $showPhase1)

            // MARK: - Phase 2: Optional Enhancements
            Divider()

            VoiceTriggerPhase2Settings(appState: appState, isExpanded: $showPhase2)

            // MARK: - Phase 3: Experimental (Neural)
            Divider()

            VoiceTriggerPhase3Settings(appState: appState, isExpanded: $showPhase3)
        }
    }
}

// MARK: - Phase 1: Voice Activity Detection (Always On)

struct VoiceTriggerPhase1Settings: View {
    @Bindable var appState: AppState
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.stateComplete)

                    Text("PHASE 1: VOICE DETECTION")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(KoeColors.textLight)
                        .tracking(0.5)

                    Text("Always On")
                        .font(.system(size: 9))
                        .foregroundColor(KoeColors.textLighter)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(KoeColors.stateComplete.opacity(0.2))
                        .cornerRadius(4)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(KoeColors.textLight)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(KoeColors.surface)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Filters out background noise to detect when you're speaking.")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                        .fixedSize(horizontal: false, vertical: true)

                    // VAD Enable toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Voice Activity Detection")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(KoeColors.accent)
                            Text("Skip processing when no speech is detected")
                                .font(.system(size: 9))
                                .foregroundColor(KoeColors.textLight)
                        }
                        Spacer()
                        Toggle("", isOn: $appState.voiceCommandSettings.vadEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .tint(KoeColors.accent)
                    }

                    if appState.voiceCommandSettings.vadEnabled {
                        // VAD Threshold slider
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Sensitivity")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(KoeColors.accent)
                                Spacer()
                                Text(String(format: "%.0f%%", appState.voiceCommandSettings.vadThreshold * 100))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(KoeColors.accent)
                            }
                            Slider(value: $appState.voiceCommandSettings.vadThreshold, in: 0.1...0.8, step: 0.05)
                                .tint(KoeColors.accent)
                            HStack {
                                Text("More sensitive")
                                    .font(.system(size: 9))
                                    .foregroundColor(KoeColors.textLighter)
                                Spacer()
                                Text("Less false triggers")
                                    .font(.system(size: 9))
                                    .foregroundColor(KoeColors.textLighter)
                            }
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 4)
            }
        }
        .onChange(of: appState.voiceCommandSettings) { _, newSettings in
            newSettings.save()
        }
    }
}

// MARK: - Phase 2: Optional Enhancements

struct VoiceTriggerPhase2Settings: View {
    @Bindable var appState: AppState
    @Binding var isExpanded: Bool

    private var isPhase2Enabled: Bool {
        appState.voiceCommandSettings.useExtendedTrigger || appState.voiceCommandSettings.useAdaptiveThreshold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.accent)

                    Text("PHASE 2: ENHANCEMENTS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(KoeColors.textLight)
                        .tracking(0.5)

                    Text("Optional")
                        .font(.system(size: 9))
                        .foregroundColor(KoeColors.textLighter)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(KoeColors.accent.opacity(0.15))
                        .cornerRadius(4)

                    Spacer()

                    if isPhase2Enabled {
                        Circle()
                            .fill(KoeColors.accent)
                            .frame(width: 6, height: 6)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(KoeColors.textLight)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(KoeColors.surface)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Improve trigger accuracy with extended phrases and adaptive thresholds.")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                        .fixedSize(horizontal: false, vertical: true)

                    // Extended trigger toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Extended Trigger Phrase")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(KoeColors.accent)
                            Text("Say \"hey koe\" instead of \"kon\" for better accuracy")
                                .font(.system(size: 9))
                                .foregroundColor(KoeColors.textLight)
                        }
                        Spacer()
                        Toggle("", isOn: $appState.voiceCommandSettings.useExtendedTrigger)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .tint(KoeColors.accent)
                    }

                    Divider()

                    // Adaptive threshold toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Adaptive Threshold")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(KoeColors.accent)
                            Text("Automatically adjust sensitivity based on noise level")
                                .font(.system(size: 9))
                                .foregroundColor(KoeColors.textLight)
                        }
                        Spacer()
                        Toggle("", isOn: $appState.voiceCommandSettings.useAdaptiveThreshold)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .tint(KoeColors.accent)
                    }

                    Divider()

                    // Confidence threshold slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Voice Match Confidence")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(KoeColors.accent)
                                Text("How closely your voice must match your profile")
                                    .font(.system(size: 9))
                                    .foregroundColor(KoeColors.textLight)
                            }
                            Spacer()
                            Text(String(format: "%.0f%%", appState.voiceCommandSettings.confidenceThreshold * 100))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(KoeColors.accent)
                        }
                        Slider(value: $appState.voiceCommandSettings.confidenceThreshold, in: 0.5...0.95, step: 0.05)
                            .tint(KoeColors.accent)
                        HStack {
                            Text("More triggers")
                                .font(.system(size: 9))
                                .foregroundColor(KoeColors.textLighter)
                            Spacer()
                            Text("Fewer false positives")
                                .font(.system(size: 9))
                                .foregroundColor(KoeColors.textLighter)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 4)
            }
        }
        .onChange(of: appState.voiceCommandSettings) { _, newSettings in
            newSettings.save()
        }
    }
}

// MARK: - Phase 3: Experimental (Neural Model)

struct VoiceTriggerPhase3Settings: View {
    @Bindable var appState: AppState
    @Binding var isExpanded: Bool

    private var isPhase3Enabled: Bool {
        appState.voiceCommandSettings.useECAPATDNN
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "brain")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.stateTranscribing)

                    Text("PHASE 3: NEURAL MODEL")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(KoeColors.textLight)
                        .tracking(0.5)

                    Text("Experimental")
                        .font(.system(size: 9))
                        .foregroundColor(KoeColors.stateTranscribing)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(KoeColors.stateTranscribing.opacity(0.15))
                        .cornerRadius(4)

                    Spacer()

                    if isPhase3Enabled {
                        Circle()
                            .fill(KoeColors.stateTranscribing)
                            .frame(width: 6, height: 6)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(KoeColors.textLight)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(KoeColors.surface)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Advanced speaker verification using neural networks. May use more resources.")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                        .fixedSize(horizontal: false, vertical: true)

                    // ECAPA-TDNN toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ECAPA-TDNN Model")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(KoeColors.accent)
                            Text("Use neural network for voice verification (more accurate)")
                                .font(.system(size: 9))
                                .foregroundColor(KoeColors.textLight)
                        }
                        Spacer()
                        Toggle("", isOn: $appState.voiceCommandSettings.useECAPATDNN)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .tint(KoeColors.accent)
                    }

                    Divider()

                    // Silence confirmation delay
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Confirmation Delay")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(KoeColors.accent)
                                Text("Wait time after trigger to confirm you stopped speaking")
                                    .font(.system(size: 9))
                                    .foregroundColor(KoeColors.textLight)
                            }
                            Spacer()
                            Text(String(format: "%.1fs", appState.voiceCommandSettings.silenceConfirmationDelay))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(KoeColors.accent)
                        }
                        Slider(value: $appState.voiceCommandSettings.silenceConfirmationDelay, in: 0.5...4.0, step: 0.5)
                            .tint(KoeColors.accent)
                        HStack {
                            Text("Faster response")
                                .font(.system(size: 9))
                                .foregroundColor(KoeColors.textLighter)
                            Spacer()
                            Text("More reliable")
                                .font(.system(size: 9))
                                .foregroundColor(KoeColors.textLighter)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 4)
            }
        }
        .onChange(of: appState.voiceCommandSettings) { _, newSettings in
            newSettings.save()
        }
    }
}

// MARK: - Recorder Settings

struct RecorderSettings: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Recording behavior info
            VStack(alignment: .leading, spacing: 8) {
                Text("Recording Behavior")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(KoeColors.textTertiary)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "command")
                            .font(.system(size: 10))
                            .foregroundColor(KoeColors.accent)
                        Text("Hotkey: Records while key is held")
                            .font(.system(size: 11))
                            .foregroundColor(KoeColors.textSecondary)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                            .foregroundColor(KoeColors.accent)
                        Text("Voice: Records until silence detected")
                            .font(.system(size: 11))
                            .foregroundColor(KoeColors.textSecondary)
                    }
                }
            }

            Divider()

            // Audio level indicator
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 10))
                    .foregroundColor(KoeColors.textLight)
                Text("Audio level: \(Int(appState.audioLevel * 100))%")
                    .font(.system(size: 11))
                    .foregroundColor(KoeColors.textTertiary)
            }

            // Note: VAD timeout is hardcoded for now
            // Future: add vadSilenceTimeout setting here
        }
    }
}

// MARK: - Transcribe Settings

struct TranscribeSettings: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Language (always auto-detect)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Language")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(KoeColors.accent)

                    Text("For transcription")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                }

                Spacer()

                Text("🌐 Auto-detect")
                    .font(.system(size: 12))
                    .foregroundColor(KoeColors.textLight)
            }

            Divider()

            // Model info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(KoeColors.accent)

                    HStack(spacing: 4) {
                        Text(appState.currentKoeModel.displayName)
                            .font(.system(size: 10))
                            .foregroundColor(KoeColors.textLight)
                        Text("(Global)")
                            .font(.system(size: 9))
                            .foregroundColor(KoeColors.textLighter)
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: appState.isModelLoaded ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 10))
                        .foregroundColor(appState.isModelLoaded ? KoeColors.stateComplete : KoeColors.textLight)
                    Text(appState.isModelLoaded ? "Ready" : "Loading...")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                }
            }

            Text("Change model in App Settings")
                .font(.system(size: 9))
                .foregroundColor(KoeColors.textLighter)
        }
    }
}

// MARK: - WhisperKit Balanced Settings

struct WhisperKitBalancedSettings: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Engine description
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .font(.system(size: 14))
                        .foregroundColor(KoeColors.stateTranscribing)
                    Text("Balanced Engine")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(KoeColors.accent)
                }

                Text("Best speed/accuracy balance using WhisperKit turbo model optimized for Apple Silicon.")
                    .font(.system(size: 11))
                    .foregroundColor(KoeColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Model info
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model Size")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(KoeColors.textTertiary)
                    Text("632 MB")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(KoeColors.stateComplete)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Performance")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(KoeColors.textTertiary)
                    Text("Excellent")
                        .font(.system(size: 11))
                        .foregroundColor(KoeColors.stateComplete)
                }
            }

            Divider()

            // Language
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Language")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(KoeColors.accent)
                }

                Spacer()

                Text("Auto-detect")
                    .font(.system(size: 12))
                    .foregroundColor(KoeColors.textLight)
            }
        }
    }
}

// MARK: - WhisperKit Accurate Settings

struct WhisperKitAccurateSettings: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Engine description
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.system(size: 14))
                        .foregroundColor(KoeColors.stateTranscribing)
                    Text("Accurate Engine")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(KoeColors.accent)
                }

                Text("Highest accuracy using WhisperKit large-v3 model. Best for critical transcriptions.")
                    .font(.system(size: 11))
                    .foregroundColor(KoeColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Model info
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model Size")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(KoeColors.textTertiary)
                    Text("947 MB")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(KoeColors.accent)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Accuracy")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(KoeColors.textTertiary)
                    Text("Best")
                        .font(.system(size: 11))
                        .foregroundColor(KoeColors.stateComplete)
                }
            }

            Divider()

            // Language
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Language")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(KoeColors.accent)
                }

                Spacer()

                Text("Auto-detect")
                    .font(.system(size: 12))
                    .foregroundColor(KoeColors.textLight)
            }
        }
    }
}

// MARK: - WhisperKit Settings (Legacy)

struct WhisperKitSettings: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Engine description
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.circle")
                        .font(.system(size: 14))
                        .foregroundColor(KoeColors.stateTranscribing)
                    Text("WhisperKit Engine")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(KoeColors.accent)
                }

                Text("High accuracy transcription using OpenAI Whisper model optimized for Apple Silicon.")
                    .font(.system(size: 11))
                    .foregroundColor(KoeColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Accuracy info
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accuracy")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(KoeColors.textTertiary)
                    Text("~7.75% WER")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(KoeColors.stateComplete)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Startup")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(KoeColors.textTertiary)
                    Text("Requires download")
                        .font(.system(size: 11))
                        .foregroundColor(KoeColors.textLight)
                }
            }

            Divider()

            // Model status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(KoeColors.accent)

                    Text(appState.currentKoeModel.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: appState.isModelLoaded ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 10))
                        .foregroundColor(appState.isModelLoaded ? KoeColors.stateComplete : KoeColors.textLight)
                    Text(appState.isModelLoaded ? "Ready" : "Loading...")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                }
            }

            Divider()

            // Language (always auto-detect)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Language")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(KoeColors.accent)
                }

                Spacer()

                Text("🌐 Auto-detect")
                    .font(.system(size: 12))
                    .foregroundColor(KoeColors.textLight)
            }
        }
    }
}

// MARK: - Apple Speech Settings

struct AppleSpeechSettings: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Engine description
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 14))
                        .foregroundColor(KoeColors.stateTranscribing)
                    Text("Apple Speech Engine")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(KoeColors.accent)
                }

                Text("Native macOS speech recognition using SFSpeechRecognizer. No download required.")
                    .font(.system(size: 11))
                    .foregroundColor(KoeColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Accuracy info
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accuracy")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(KoeColors.textTertiary)
                    Text("~14% WER")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(KoeColors.stateTranscribing)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Startup")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(KoeColors.textTertiary)
                    Text("Instant")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(KoeColors.stateComplete)
                }
            }

            Divider()

            // Status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Status")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(KoeColors.accent)

                    Text("Built into macOS")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.stateComplete)
                    Text("Always ready")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                }
            }

            Divider()

            // Language (always auto-detect)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Language")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(KoeColors.accent)
                }

                Spacer()

                Text("🌐 Auto-detect")
                    .font(.system(size: 12))
                    .foregroundColor(KoeColors.textLight)
            }

            Divider()

            // Note about trade-offs
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundColor(KoeColors.textLight)
                Text("Faster but less accurate than WhisperKit")
                    .font(.system(size: 10))
                    .foregroundColor(KoeColors.textTertiary)
            }
        }
    }
}

// MARK: - Improve Settings (Module-specific refinement options)

struct ImproveSettings: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Enable toggle
            HStack {
                Toggle(isOn: $appState.isRefinementEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: "flask")
                            .font(.system(size: 12))
                            .foregroundColor(
                                appState.isRefinementEnabled ? KoeColors.stateRefining : KoeColors.textLight)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Refinement")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(KoeColors.accent)

                            Text("Clean up transcribed text")
                                .font(.system(size: 10))
                                .foregroundColor(KoeColors.textLight)
                        }
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if appState.isRefinementEnabled {
                Divider()

                // Cleanup toggle
                HStack {
                    Toggle(isOn: $appState.isCleanupEnabled) {
                        HStack(spacing: 8) {
                            Image(systemName: "text.badge.checkmark")
                                .font(.system(size: 12))
                                .foregroundColor(
                                    appState.isCleanupEnabled ? KoeColors.stateRefining : KoeColors.textLight)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Clean Up")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(KoeColors.accent)

                                Text("Fix grammar, remove filler words")
                                    .font(.system(size: 10))
                                    .foregroundColor(KoeColors.textLight)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                Divider()

                // Tone selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tone")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(KoeColors.textTertiary)

                    HStack(spacing: 8) {
                        NodeSettingsToneChip(label: "None", isSelected: appState.toneStyle == "none") {
                            appState.toneStyle = "none"
                        }
                        NodeSettingsToneChip(label: "Formal", isSelected: appState.toneStyle == "formal") {
                            appState.toneStyle = "formal"
                        }
                        NodeSettingsToneChip(label: "Casual", isSelected: appState.toneStyle == "casual") {
                            appState.toneStyle = "casual"
                        }
                    }
                }

                Divider()

                // Prompt mode toggle
                HStack {
                    Toggle(isOn: $appState.isPromptImproverEnabled) {
                        HStack(spacing: 8) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 12))
                                .foregroundColor(
                                    appState.isPromptImproverEnabled ? KoeColors.stateRefining : KoeColors.textLight)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Prompt Mode")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(KoeColors.accent)

                                Text("Optimize text as AI prompt")
                                    .font(.system(size: 10))
                                    .foregroundColor(KoeColors.textLight)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                Divider()

                // Custom instructions
                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom Instructions")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(KoeColors.textTertiary)

                    TextField("Add extra instructions...", text: $appState.customRefinementPrompt)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(8)
                        .background(KoeColors.surface)
                        .cornerRadius(6)
                }

                // Model info
                Divider()

                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                    Text("\(appState.currentAITier.displayName)")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textTertiary)
                    Text("(Global)")
                        .font(.system(size: 9))
                        .foregroundColor(KoeColors.textLighter)
                }
            }
        }
    }
}

// MARK: - AI Fast Settings (Mistral 7B)

struct AIFastSettings: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Enable toggle
            HStack {
                Toggle(isOn: $appState.isAIFastEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: "hare")
                            .font(.system(size: 12))
                            .foregroundColor(
                                appState.isAIFastEnabled ? KoeColors.stateRefining : KoeColors.textLight)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fast AI")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(KoeColors.accent)

                            Text("Quick cleanup with minimal latency")
                                .font(.system(size: 10))
                                .foregroundColor(KoeColors.textLight)
                        }
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Divider()

            // Model info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                    Text("Mistral 7B")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textTertiary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                    Text("~4 GB download")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textTertiary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "bolt")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                    Text("~30-40 tokens/sec")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textTertiary)
                }
            }
        }
    }
}

// MARK: - AI Balanced Settings (Qwen 2.5 7B)

struct AIBalancedSettings: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Enable toggle
            HStack {
                Toggle(isOn: $appState.isAIBalancedEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                            .font(.system(size: 12))
                            .foregroundColor(
                                appState.isAIBalancedEnabled ? KoeColors.stateRefining : KoeColors.textLight)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Balanced AI")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(KoeColors.accent)

                            Text("Good balance of speed and quality")
                                .font(.system(size: 10))
                                .foregroundColor(KoeColors.textLight)
                        }
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Divider()

            // Model info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                    Text("Qwen 2.5 7B")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textTertiary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                    Text("~4.5 GB download")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textTertiary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "bolt")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                    Text("~25-35 tokens/sec")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textTertiary)
                }
            }
        }
    }
}

// MARK: - AI Reasoning Settings (DeepSeek-R1 8B)

struct AIReasoningSettings: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Enable toggle
            HStack {
                Toggle(isOn: $appState.isAIReasoningEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: "brain")
                            .font(.system(size: 12))
                            .foregroundColor(
                                appState.isAIReasoningEnabled ? KoeColors.stateRefining : KoeColors.textLight)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reasoning AI")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(KoeColors.accent)

                            Text("Complex reasoning and prompt optimization")
                                .font(.system(size: 10))
                                .foregroundColor(KoeColors.textLight)
                        }
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Divider()

            // Experimental badge
            HStack(spacing: 4) {
                Image(systemName: "flask")
                    .font(.system(size: 9))
                Text("Experimental")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(4)

            // Model info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                    Text("DeepSeek-R1 8B")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textTertiary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                    Text("~5 GB download")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textTertiary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "bolt")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                    Text("~15-25 tokens/sec (with reasoning)")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textTertiary)
                }
            }
        }
    }
}

// MARK: - Auto Type Settings

struct AutoTypeSettings: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Types the transcribed text into the active app")
                .font(.system(size: 12))
                .foregroundColor(KoeColors.textSecondary)

            Divider()

            // Typing info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.accent)
                    Text("Instant insertion")
                        .font(.system(size: 11))
                        .foregroundColor(KoeColors.textSecondary)
                }

                Text("Text is inserted at cursor position")
                    .font(.system(size: 10))
                    .foregroundColor(KoeColors.textLight)
            }

            // Future settings:
            // - Typing speed (instant / natural / slow)
            // - Delay before typing
        }
    }
}

// MARK: - Auto Enter Settings

struct AutoEnterSettings: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Enable toggle
            HStack {
                Toggle(isOn: $appState.isAutoEnterEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: "return")
                            .font(.system(size: 12))
                            .foregroundColor(appState.isAutoEnterEnabled ? KoeColors.accent : KoeColors.textLight)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto Enter")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(KoeColors.accent)

                            Text("Press Enter after typing")
                                .font(.system(size: 10))
                                .foregroundColor(KoeColors.textLight)
                        }
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundColor(KoeColors.textLight)
                Text("Great for chat apps and terminals")
                    .font(.system(size: 11))
                    .foregroundColor(KoeColors.textTertiary)
            }

            // Future settings:
            // - Number of enters (1, 2, 3)
            // - Delay after typing
        }
    }
}

// MARK: - Node Settings Tone Chip

struct NodeSettingsToneChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : KoeColors.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? KoeColors.accent : KoeColors.surface)
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 20) {
        SettingsModal(
            title: "Hotkey Settings",
            icon: "command",
            iconColor: KoeColors.accent,
            onClose: {}
        ) {
            NodeSettingsContent(stage: .hotkeyTrigger)
                .environment(AppState.shared)
        }

        SettingsModal(
            title: "Recorder Settings",
            icon: "mic",
            iconColor: KoeColors.stateRecording,
            onClose: {}
        ) {
            NodeSettingsContent(stage: .recorder)
                .environment(AppState.shared)
        }

        SettingsModal(
            title: "AI Fast Settings",
            icon: "hare",
            iconColor: KoeColors.stateRefining,
            onClose: {}
        ) {
            NodeSettingsContent(stage: .aiFast)
                .environment(AppState.shared)
        }
    }
    .padding()
    .background(KoeColors.background)
}
