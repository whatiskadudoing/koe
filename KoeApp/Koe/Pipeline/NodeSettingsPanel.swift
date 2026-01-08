import SwiftUI
import KoeUI
import KoeDomain

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
        case .transcribe:
            TranscribeSettings(appState: appState)
        case .improve:
            ImproveSettings(appState: appState)
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
    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Enable/disable toggle
            HStack {
                Toggle(isOn: $appState.isCommandListeningEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 12))
                            .foregroundColor(appState.isCommandListeningEnabled ? KoeColors.accent : KoeColors.textLight)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Voice Activation")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(KoeColors.accent)

                            Text("Say \"kon\" to start recording")
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
                        .foregroundColor(.green)
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
                            .foregroundColor(.orange)
                        Text("Voice training required")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
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
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Listening for \"kon\"...")
                        .font(.system(size: 11))
                        .foregroundColor(KoeColors.textTertiary)
                }
            }

            // Experimental settings toggle
            Divider()

            Button(action: { withAnimation { showAdvanced.toggle() } }) {
                HStack {
                    Image(systemName: "flask")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)

                    Text("Experimental")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(KoeColors.textLight)

                    Spacer()

                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(KoeColors.textLight)
                }
            }
            .buttonStyle(.plain)

            if showAdvanced {
                VoiceTriggerAdvancedSettings(appState: appState)
            }
        }
    }
}

// MARK: - Voice Trigger Advanced Settings

struct VoiceTriggerAdvancedSettings: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Confidence threshold
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Confidence")
                        .font(.system(size: 11))
                        .foregroundColor(KoeColors.accent)
                    Spacer()
                    Text(String(format: "%.0f%%", appState.voiceCommandSettings.confidenceThreshold * 100))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(KoeColors.textLight)
                }
                Slider(value: $appState.voiceCommandSettings.confidenceThreshold, in: 0.5...0.95, step: 0.05)
                    .tint(KoeColors.accent)
                Text("Higher = fewer false triggers")
                    .font(.system(size: 9))
                    .foregroundColor(KoeColors.textLighter)
            }

            // Silence delay
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Silence Delay")
                        .font(.system(size: 11))
                        .foregroundColor(KoeColors.accent)
                    Spacer()
                    Text(String(format: "%.1fs", appState.voiceCommandSettings.silenceConfirmationDelay))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(KoeColors.textLight)
                }
                Slider(value: $appState.voiceCommandSettings.silenceConfirmationDelay, in: 0.5...4.0, step: 0.5)
                    .tint(KoeColors.accent)
                Text("Wait before executing trigger")
                    .font(.system(size: 9))
                    .foregroundColor(KoeColors.textLighter)
            }

            // Extended trigger
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Extended Trigger")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(KoeColors.accent)
                    Text("\"hey koe\" instead of \"kon\"")
                        .font(.system(size: 9))
                        .foregroundColor(KoeColors.textLight)
                }
                Spacer()
                Toggle("", isOn: $appState.voiceCommandSettings.useExtendedTrigger)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
                    .tint(KoeColors.accent)
            }
        }
        .padding(.top, 8)
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
            // Language selector
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

                Picker("", selection: $appState.selectedLanguage) {
                    ForEach(Language.all, id: \.code) { lang in
                        Text("\(lang.flag) \(lang.name)").tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)
            }

            Divider()

            // Model info (uses global setting)
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
                        .foregroundColor(appState.isModelLoaded ? .green : KoeColors.textLight)
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

// MARK: - Improve Settings (Module-specific refinement options)

struct ImproveSettings: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Enable toggle
            HStack {
                Toggle(isOn: $appState.isRefinementEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                            .foregroundColor(appState.isRefinementEnabled ? KoeColors.stateRefining : KoeColors.textLight)

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
                                .foregroundColor(appState.isCleanupEnabled ? KoeColors.stateRefining : KoeColors.textLight)

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
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                                .foregroundColor(appState.isPromptImproverEnabled ? .orange : KoeColors.textLight)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Prompt Mode")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(KoeColors.accent)

                                Text("Optimize for AI prompts")
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
            title: "Improve Settings",
            icon: "sparkles",
            iconColor: KoeColors.stateRefining,
            onClose: {}
        ) {
            NodeSettingsContent(stage: .improve)
                .environment(AppState.shared)
        }
    }
    .padding()
    .background(KoeColors.background)
}
