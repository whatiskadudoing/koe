import KoeCommands
import KoeDomain
import KoeRefinement
import KoeUI
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isTestingConnection = false
    @State private var availableModels: [OllamaModel] = []
    @State private var showVoiceTraining = false

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            KoeColors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Settings")
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(KoeColors.accent)
                            .tracking(2)
                    }
                    .padding(.top, 8)

                    // Hotkey section
                    HotkeySettingsSection(appState: appState)

                    // Appearance section
                    AppearanceSettingsSection(appState: appState)

                    // AI Refinement Model section (Global)
                    AIModelSettingsSection(
                        appState: appState,
                        availableModels: $availableModels,
                        isTestingConnection: $isTestingConnection,
                        testConnection: testConnection
                    )

                    // Voice Profile section (Global)
                    VoiceProfileSection(
                        appState: appState,
                        showVoiceTraining: $showVoiceTraining
                    )

                    // History section
                    HistorySection(appState: appState)

                    // About section
                    AboutSection()

                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .frame(width: 400, height: 680)
        .sheet(isPresented: $showVoiceTraining) {
            VoiceTrainingView { profile in
                appState.voiceProfile = profile
                NotificationCenter.default.post(name: .voiceProfileTrained, object: profile)
            }
        }
    }

    private func testConnection() {
        isTestingConnection = true
        Task {
            let service = OllamaRefinementService.shared
            service.setEndpoint(appState.ollamaEndpoint)

            let connected = await service.checkConnection()

            await MainActor.run {
                appState.isOllamaConnected = connected
                if connected {
                    availableModels = service.availableModels
                }
                isTestingConnection = false
            }
        }
    }
}

extension Notification.Name {
    static let reloadModel = Notification.Name("reloadModel")
}

// MARK: - Hotkey Settings Section

struct HotkeySettingsSection: View {
    @Bindable var appState: AppState

    private let presets: [(name: String, keyCode: UInt32, modifiers: Int)] = [
        ("⌥ Space", 49, 2),
        ("R-⌥", 61, 0),
        ("⌃ Space", 49, 4),
        ("F5", 96, 0),
        ("F6", 97, 0),
    ]

    var body: some View {
        SettingsSectionContainer(title: "Keyboard Shortcut") {
            VStack(spacing: 0) {
                // Current shortcut display
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Push-to-Talk Shortcut")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(KoeColors.accent)

                        Text("Hold to record, release to transcribe")
                            .font(.system(size: 12))
                            .foregroundColor(KoeColors.textLight)
                    }

                    Spacer()

                    Text(appState.hotkeyDisplayString)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(KoeColors.accent)
                        .cornerRadius(8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()
                    .padding(.horizontal, 16)

                // Preset shortcuts
                VStack(alignment: .leading, spacing: 10) {
                    Text("Quick Presets")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(KoeColors.accent)

                    HStack(spacing: 8) {
                        ForEach(presets, id: \.name) { preset in
                            SettingsChip(
                                label: preset.name,
                                isSelected: isPresetSelected(preset)
                            ) {
                                appState.hotkeyKeyCode = preset.keyCode
                                appState.hotkeyModifiers = preset.modifiers
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    private func isPresetSelected(_ preset: (name: String, keyCode: UInt32, modifiers: Int)) -> Bool {
        appState.hotkeyKeyCode == preset.keyCode && appState.hotkeyModifiers == preset.modifiers
    }
}

// MARK: - Appearance Settings Section

struct AppearanceSettingsSection: View {
    @Bindable var appState: AppState

    var body: some View {
        SettingsSectionContainer(title: "Appearance") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ring Animation")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(KoeColors.accent)

                    Text(appState.currentRingAnimationStyle.description)
                        .font(.system(size: 12))
                        .foregroundColor(KoeColors.textLight)
                }

                Spacer()

                Picker("", selection: $appState.ringAnimationStyleRaw) {
                    ForEach(RingAnimationStyle.allCases, id: \.rawValue) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 100)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - AI Model Settings Section (Global)

struct AIModelSettingsSection: View {
    @Bindable var appState: AppState
    @Binding var availableModels: [OllamaModel]
    @Binding var isTestingConnection: Bool
    let testConnection: () -> Void

    var body: some View {
        SettingsSectionContainer(title: "AI Refinement Model") {
            VStack(spacing: 0) {
                // Quality Tier picker
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Provider")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(KoeColors.accent)

                        Text(tierDescription)
                            .font(.system(size: 12))
                            .foregroundColor(KoeColors.textLight)
                    }

                    Spacer()

                    Picker("", selection: $appState.aiTierRaw) {
                        ForEach(AITier.allCases, id: \.rawValue) { tier in
                            Text(tier.displayName).tag(tier.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 100)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                // Ollama settings (only shown for Custom tier)
                if appState.currentAITier == .custom {
                    Divider()
                        .padding(.horizontal, 16)

                    ollamaSettingsView
                }

                // Model status
                Divider()
                    .padding(.horizontal, 16)

                HStack(spacing: 6) {
                    Image(systemName: appState.isRefinementModelLoaded ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 12))
                        .foregroundColor(appState.isRefinementModelLoaded ? .green : KoeColors.textLight)
                    Text(appState.isRefinementModelLoaded ? "AI model ready" : "Loading AI model...")
                        .font(.system(size: 12))
                        .foregroundColor(KoeColors.textLight)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private var tierDescription: String {
        switch appState.currentAITier {
        case .best:
            return "Qwen 2.5 3B • GPU accelerated • ~2GB"
        case .custom:
            return "Ollama with custom model"
        }
    }

    private var ollamaSettingsView: some View {
        VStack(spacing: 0) {
            // Endpoint
            HStack {
                Text("Server")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(KoeColors.accent)

                Spacer()

                TextField("http://localhost:11434", text: $appState.ollamaEndpoint)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(KoeColors.accent)
                    .frame(width: 160)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(KoeColors.background)
                    .cornerRadius(6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Model picker
            HStack {
                Text("Model")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(KoeColors.accent)

                Spacer()

                if availableModels.isEmpty {
                    TextField("llama3.2:3b", text: $appState.ollamaModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(KoeColors.accent)
                        .frame(width: 160)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(KoeColors.background)
                        .cornerRadius(6)
                } else {
                    Picker("", selection: $appState.ollamaModel) {
                        ForEach(availableModels, id: \.name) { model in
                            Text(model.name).tag(model.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(KoeColors.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .padding(.horizontal, 16)

            // Connection status and test button
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isOllamaConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Text(appState.isOllamaConnected ? "Connected" : "Not connected")
                        .font(.system(size: 12))
                        .foregroundColor(KoeColors.textLight)
                }

                Spacer()

                Button(action: testConnection) {
                    HStack(spacing: 6) {
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 11))
                        }
                        Text("Test")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(KoeColors.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(KoeColors.accent.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(isTestingConnection)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Voice Profile Section (Global)

struct VoiceProfileSection: View {
    @Bindable var appState: AppState
    @Binding var showVoiceTraining: Bool

    var body: some View {
        SettingsSectionContainer(title: "Voice Profile") {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Voice")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(KoeColors.accent)

                        if appState.hasVoiceProfile {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Trained and ready")
                                    .font(.system(size: 12))
                                    .foregroundColor(KoeColors.textLight)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 8, height: 8)
                                Text("Not trained")
                                    .font(.system(size: 12))
                                    .foregroundColor(KoeColors.textLight)
                            }
                        }
                    }

                    Spacer()

                    // Only show Train button if not trained yet
                    if !appState.hasVoiceProfile {
                        Button(action: { showVoiceTraining = true }) {
                            Text("Train Voice")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(KoeColors.accent)
                                .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if !appState.hasVoiceProfile {
                    Divider()
                        .padding(.horizontal, 16)

                    Text("Train your voice to enable hands-free activation. Retrain from On Voice node settings.")
                        .font(.system(size: 11))
                        .foregroundColor(KoeColors.textLight)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
        }
    }
}

// MARK: - History Section

struct HistorySection: View {
    @Bindable var appState: AppState

    var body: some View {
        SettingsSectionContainer(title: "History") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transcription entries")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(KoeColors.accent)

                    Text("\(appState.transcriptionHistory.count) items stored")
                        .font(.system(size: 12))
                        .foregroundColor(KoeColors.textLight)
                }

                Spacer()

                Button(action: {
                    appState.clearHistory()
                }) {
                    Text("Clear")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(KoeColors.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(KoeColors.accent.opacity(0.1))
                        .cornerRadius(16)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
    }
}

// MARK: - About Section

struct AboutSection: View {
    var body: some View {
        SettingsSectionContainer(title: "About") {
            VStack(spacing: 12) {
                Text("声")
                    .font(.system(size: 32, weight: .thin))
                    .foregroundColor(KoeColors.accent.opacity(0.7))

                Text("koe")
                    .font(.system(size: 18, weight: .light, design: .rounded))
                    .foregroundColor(KoeColors.accent)
                    .tracking(4)

                Text("Voice to Text")
                    .font(.system(size: 12))
                    .foregroundColor(KoeColors.textLight)
                    .padding(.top, 4)

                Divider()
                    .padding(.vertical, 8)

                Text("Powered by WhisperKit")
                    .font(.system(size: 11))
                    .foregroundColor(KoeColors.textLight.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(20)
        }
    }
}

// MARK: - Reusable Components

/// Container for settings sections with consistent styling
struct SettingsSectionContainer<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(KoeColors.textLight)
                .textCase(.uppercase)
                .tracking(1)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
    }
}

/// Reusable chip button for settings
struct SettingsChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .rounded))
                .foregroundColor(isSelected ? .white : KoeColors.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? KoeColors.accent : KoeColors.accent.opacity(0.1))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
