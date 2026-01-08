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
        case .hotkey:
            HotkeySettings(appState: appState)
        case .transcription:
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

// MARK: - Hotkey Settings

struct HotkeySettings: View {
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
            title: "Improve Settings",
            icon: "sparkles",
            iconColor: KoeColors.stateRefining,
            onClose: {}
        ) {
            NodeSettingsContent(stage: .improve)
                .environment(AppState.shared)
        }

        SettingsModal(
            title: "Hotkey Settings",
            icon: "command",
            iconColor: KoeColors.accent,
            onClose: {}
        ) {
            NodeSettingsContent(stage: .hotkey)
                .environment(AppState.shared)
        }
    }
    .padding()
    .background(KoeColors.background)
}
