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
            HotkeyTriggerContent(appState: appState)
        case .voiceTrigger:
            VoiceCommandTriggerContent(appState: appState)
        case .recorder:
            RecorderSettings(appState: appState)
        case .transcribe:
            TranscribeSettings(appState: appState)
        case .improve:
            ImproveSettings(appState: appState)
        case .autoEnter:
            AutoEnterSettings()
        default:
            Text("No settings available")
                .font(.system(size: 12))
                .foregroundColor(KoeColors.textLight)
        }
    }
}

// MARK: - Transcribe Settings

struct TranscribeSettings: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Language selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Language")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(KoeColors.textTertiary)

                Picker("", selection: $appState.selectedLanguage) {
                    ForEach(Language.all, id: \.code) { lang in
                        Text("\(lang.flag) \(lang.name)").tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Divider()

            // Model selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Model")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(KoeColors.textTertiary)

                Picker("", selection: $appState.selectedModel) {
                    ForEach(KoeModel.allCases, id: \.rawValue) { model in
                        Text(model.displayName).tag(model.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: appState.selectedModel) { _, newModel in
                    // Reload model when changed
                    Task {
                        await RecordingCoordinator.shared.loadModel(name: newModel)
                    }
                }
            }

            // Info about current model
            HStack(spacing: 6) {
                Image(systemName: appState.isModelLoaded ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 10))
                    .foregroundColor(appState.isModelLoaded ? .green : KoeColors.textLight)
                Text(appState.isModelLoaded ? "Model loaded" : "Loading model...")
                    .font(.system(size: 11))
                    .foregroundColor(KoeColors.textTertiary)
            }
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
        }
    }
}

// MARK: - Improve Settings (Combined cleanup, tone, and prompt mode)

struct ImproveSettings: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    SettingsToneChip(label: "None", isSelected: appState.toneStyle == "none") {
                        appState.toneStyle = "none"
                    }
                    SettingsToneChip(label: "Formal", isSelected: appState.toneStyle == "formal") {
                        appState.toneStyle = "formal"
                    }
                    SettingsToneChip(label: "Casual", isSelected: appState.toneStyle == "casual") {
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

                            Text("Optimize for AI assistant prompts")
                                .font(.system(size: 10))
                                .foregroundColor(KoeColors.textLight)
                        }
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Auto Enter Settings

struct AutoEnterSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Automatically presses Enter after typing")
                .font(.system(size: 12))
                .foregroundColor(KoeColors.textSecondary)

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundColor(KoeColors.textLight)
                Text("Great for chat apps and terminals")
                    .font(.system(size: 11))
                    .foregroundColor(KoeColors.textTertiary)
            }
        }
    }
}

// MARK: - Unified Trigger Settings

struct TriggerSettings: View {
    @Bindable var appState: AppState
    @State private var selectedTab: TriggerTab = .hotkey

    enum TriggerTab: String, CaseIterable {
        case hotkey = "Hotkey"
        case voice = "Voice"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tab selector
            HStack(spacing: 4) {
                ForEach(TriggerTab.allCases, id: \.self) { tab in
                    TriggerTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        isEnabled: tab == .hotkey ? true : appState.hasVoiceProfile
                    ) {
                        selectedTab = tab
                    }
                }
            }
            .padding(3)
            .background(KoeColors.surface)
            .cornerRadius(8)

            Divider()

            // Tab content
            switch selectedTab {
            case .hotkey:
                HotkeyTriggerContent(appState: appState)
            case .voice:
                VoiceCommandTriggerContent(appState: appState)
            }
        }
    }
}

struct TriggerTabButton: View {
    let tab: TriggerSettings.TriggerTab
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: tab == .hotkey ? "command" : "waveform")
                    .font(.system(size: 10))
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                if !isEnabled {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                }
            }
            .foregroundColor(isSelected ? .white : KoeColors.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? KoeColors.accent : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hotkey Trigger Content

struct HotkeyTriggerContent: View {
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

// MARK: - Voice Command Trigger Content

struct VoiceCommandTriggerContent: View {
    @Bindable var appState: AppState

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
                // Training required message
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
        }
    }
}

// Keep for backwards compatibility
struct HotkeySettings: View {
    @Bindable var appState: AppState

    var body: some View {
        HotkeyTriggerContent(appState: appState)
    }
}

// MARK: - Settings Tone Chip

struct SettingsToneChip: View {
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
