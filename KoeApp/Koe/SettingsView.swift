import SwiftUI
import KoeDomain
import KoeRefinement

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isLoadingModel = false
    @State private var isTestingConnection = false
    @State private var availableModels: [OllamaModel] = []

    // Japanese-inspired color palette
    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let pageBackground = Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))
    private let cardBackground = Color.white
    private let purpleColor = Color(nsColor: NSColor(red: 0.58, green: 0.44, blue: 0.86, alpha: 1.0))

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Settings")
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(accentColor)
                            .tracking(2)
                    }
                    .padding(.top, 8)

                    // Transcription section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Transcription")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(lightGray)
                            .textCase(.uppercase)
                            .tracking(1)

                        VStack(spacing: 0) {
                            // Model picker
                            HStack {
                                Text("Model")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(accentColor)

                                Spacer()

                                Picker("", selection: $appState.selectedModel) {
                                    ForEach(KoeModel.allCases, id: \.rawValue) { model in
                                        Text(model.displayName).tag(model.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(accentColor)
                                .onChange(of: appState.selectedModel) { _, newModel in
                                    reloadModel(newModel)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            if isLoadingModel && !appState.isModelLoaded {
                                Divider()
                                    .padding(.horizontal, 16)

                                HStack(spacing: 10) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Loading model...")
                                        .font(.system(size: 12))
                                        .foregroundColor(lightGray)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }

                            Divider()
                                .padding(.horizontal, 16)

                            // Language picker
                            HStack {
                                Text("Language")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(accentColor)

                                Spacer()

                                Picker("", selection: $appState.selectedLanguage) {
                                    ForEach(Language.all, id: \.code) { lang in
                                        Text("\(lang.flag) \(lang.name)").tag(lang.code)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(accentColor)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .background(cardBackground)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                    }

                    // Hotkey section
                    HotkeySettingsSection(
                        appState: appState,
                        accentColor: accentColor,
                        lightGray: lightGray,
                        pageBackground: pageBackground,
                        cardBackground: cardBackground
                    )

                    // AI Refinement section
                    AIRefinementSettingsSection(
                        appState: appState,
                        accentColor: accentColor,
                        lightGray: lightGray,
                        purpleColor: purpleColor,
                        pageBackground: pageBackground,
                        cardBackground: cardBackground,
                        availableModels: $availableModels,
                        isTestingConnection: $isTestingConnection,
                        testConnection: testConnection
                    )

                    // History section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("History")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(lightGray)
                            .textCase(.uppercase)
                            .tracking(1)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Transcription entries")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(accentColor)

                                Text("\(appState.transcriptionHistory.count) items stored")
                                    .font(.system(size: 12))
                                    .foregroundColor(lightGray)
                            }

                            Spacer()

                            Button(action: {
                                appState.clearHistory()
                            }) {
                                Text("Clear")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(accentColor)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(accentColor.opacity(0.1))
                                    .cornerRadius(16)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                        .background(cardBackground)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                    }

                    // About section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("About")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(lightGray)
                            .textCase(.uppercase)
                            .tracking(1)

                        VStack(spacing: 12) {
                            Text("声")
                                .font(.system(size: 32, weight: .thin))
                                .foregroundColor(accentColor.opacity(0.7))

                            Text("koe")
                                .font(.system(size: 18, weight: .light, design: .rounded))
                                .foregroundColor(accentColor)
                                .tracking(4)

                            Text("Voice to Text")
                                .font(.system(size: 12))
                                .foregroundColor(lightGray)
                                .padding(.top, 4)

                            Divider()
                                .padding(.vertical, 8)

                            Text("Powered by WhisperKit")
                                .font(.system(size: 11))
                                .foregroundColor(lightGray.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .background(cardBackground)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                    }

                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .frame(width: 400, height: 680)
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

    private func reloadModel(_ modelName: String) {
        isLoadingModel = true
        appState.isModelLoaded = false

        // Post notification to reload model
        NotificationCenter.default.post(name: .reloadModel, object: modelName)

        // The loading state will be updated when the model finishes loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // Check if still loading after a delay
            if !appState.isModelLoaded {
                // Model is still loading, keep showing indicator
            }
        }
    }
}

extension Notification.Name {
    static let reloadModel = Notification.Name("reloadModel")
}

// MARK: - AI Refinement Settings Section

struct AIRefinementSettingsSection: View {
    @Bindable var appState: AppState
    let accentColor: Color
    let lightGray: Color
    let purpleColor: Color
    let pageBackground: Color
    let cardBackground: Color
    @Binding var availableModels: [OllamaModel]
    @Binding var isTestingConnection: Bool
    let testConnection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Refinement")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(lightGray)
                .textCase(.uppercase)
                .tracking(1)

            VStack(spacing: 0) {
                // Enable toggle
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable AI Refinement")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(accentColor)

                        Text("Clean up transcribed text with AI")
                            .font(.system(size: 12))
                            .foregroundColor(lightGray)
                    }

                    Spacer()

                    Toggle("", isOn: $appState.isRefinementEnabled)
                        .toggleStyle(.switch)
                        .tint(purpleColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()
                    .padding(.horizontal, 16)

                // Quality Tier picker
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quality")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(accentColor)

                        Text(tierDescription)
                            .font(.system(size: 11))
                            .foregroundColor(lightGray)
                    }

                    Spacer()

                    Picker("", selection: $appState.aiTierRaw) {
                        ForEach(AITier.allCases, id: \.rawValue) { tier in
                            HStack {
                                Image(systemName: tier.icon)
                                Text(tier.displayName)
                            }
                            .tag(tier.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()
                    .padding(.horizontal, 16)

                // Refinement Options - Toggles
                VStack(alignment: .leading, spacing: 12) {
                    Text("Options")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(accentColor)

                    // Option chips in a flow layout
                    VStack(alignment: .leading, spacing: 8) {
                        // Row 1: Clean Up toggle
                        RefinementOptionChip(
                            label: "Clean Up",
                            icon: "wand.and.stars",
                            isSelected: $appState.isCleanupEnabled,
                            description: "Remove filler words, fix grammar",
                            accentColor: accentColor,
                            selectedColor: purpleColor
                        )

                        // Row 2: Tone options (mutually exclusive)
                        HStack(spacing: 8) {
                            Text("Tone:")
                                .font(.system(size: 11))
                                .foregroundColor(lightGray)

                            ToneOptionChip(
                                label: "None",
                                isSelected: appState.toneStyle == "none",
                                isDisabled: appState.isPromptImproverEnabled,
                                accentColor: accentColor
                            ) {
                                appState.toneStyle = "none"
                            }

                            ToneOptionChip(
                                label: "Formal",
                                isSelected: appState.toneStyle == "formal",
                                isDisabled: appState.isPromptImproverEnabled,
                                accentColor: accentColor
                            ) {
                                appState.toneStyle = "formal"
                            }

                            ToneOptionChip(
                                label: "Casual",
                                isSelected: appState.toneStyle == "casual",
                                isDisabled: appState.isPromptImproverEnabled,
                                accentColor: accentColor
                            ) {
                                appState.toneStyle = "casual"
                            }
                        }
                        .opacity(appState.isPromptImproverEnabled ? 0.5 : 1.0)

                        // Row 3: Prompt Improver toggle
                        RefinementOptionChip(
                            label: "Prompt Mode",
                            icon: "sparkles",
                            isSelected: $appState.isPromptImproverEnabled,
                            description: "Optimize as AI prompt (ignores tone)",
                            accentColor: accentColor,
                            selectedColor: Color.orange
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                // Custom instructions (always available)
                Divider()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Instructions (optional)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(accentColor)

                    TextField("Add extra instructions...", text: $appState.customRefinementPrompt)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(10)
                        .background(pageBackground)
                        .cornerRadius(8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Ollama settings (only shown for Custom tier)
                if appState.currentAITier == .custom {
                    Divider()
                        .padding(.horizontal, 16)

                    ollamaSettingsView
                }
            }
            .background(cardBackground)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
    }

    private var tierDescription: String {
        switch appState.currentAITier {
        case .best:
            return "Qwen 2.5 3B • GPU accelerated • ~2GB"
        case .custom:
            return "Use Ollama with any model"
        }
    }

    private var ollamaSettingsView: some View {
        VStack(spacing: 0) {
            // Ollama settings header
            HStack {
                Text("Ollama Server")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(lightGray)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Endpoint
            HStack {
                Text("Endpoint")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(accentColor)

                Spacer()

                TextField("http://localhost:11434", text: $appState.ollamaEndpoint)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(accentColor)
                    .frame(width: 160)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(pageBackground)
                    .cornerRadius(6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Model picker
            HStack {
                Text("Model")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(accentColor)

                Spacer()

                if availableModels.isEmpty {
                    TextField("llama3.2:3b", text: $appState.ollamaModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(accentColor)
                        .frame(width: 160)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(pageBackground)
                        .cornerRadius(6)
                } else {
                    Picker("", selection: $appState.ollamaModel) {
                        ForEach(availableModels, id: \.name) { model in
                            Text(model.name).tag(model.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(accentColor)
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
                        .foregroundColor(lightGray)
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
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(accentColor.opacity(0.1))
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

// MARK: - Refinement Option Chip

struct RefinementOptionChip: View {
    let label: String
    let icon: String
    @Binding var isSelected: Bool
    let description: String
    let accentColor: Color
    let selectedColor: Color

    var body: some View {
        Button(action: { isSelected.toggle() }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white : accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isSelected ? .white : accentColor)

                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : accentColor.opacity(0.6))
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? .white : accentColor.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? selectedColor : accentColor.opacity(0.08))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tone Option Chip (Radio button style)

struct ToneOptionChip: View {
    let label: String
    let isSelected: Bool
    let isDisabled: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? accentColor : accentColor.opacity(0.1))
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - Hotkey Settings Section

struct HotkeySettingsSection: View {
    @Bindable var appState: AppState
    let accentColor: Color
    let lightGray: Color
    let pageBackground: Color
    let cardBackground: Color

    // Preset shortcuts
    private let presets: [(name: String, keyCode: UInt32, modifiers: Int)] = [
        ("⌥ Space", 49, 2),          // Option + Space (default)
        ("R-⌥", 61, 0),              // Right Option key
        ("⌃ Space", 49, 4),          // Control + Space
        ("F5", 96, 0),               // F5
        ("F6", 97, 0),               // F6
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcut")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(lightGray)
                .textCase(.uppercase)
                .tracking(1)

            VStack(spacing: 0) {
                // Current shortcut display
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Push-to-Talk Shortcut")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(accentColor)

                        Text("Hold to record, release to transcribe")
                            .font(.system(size: 12))
                            .foregroundColor(lightGray)
                    }

                    Spacer()

                    Text(appState.hotkeyDisplayString)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(accentColor)
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
                        .foregroundColor(accentColor)

                    HStack(spacing: 8) {
                        ForEach(presets, id: \.name) { preset in
                            ShortcutPresetChip(
                                label: preset.name,
                                isSelected: isPresetSelected(preset),
                                accentColor: accentColor
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
            .background(cardBackground)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
    }

    private func isPresetSelected(_ preset: (name: String, keyCode: UInt32, modifiers: Int)) -> Bool {
        appState.hotkeyKeyCode == preset.keyCode && appState.hotkeyModifiers == preset.modifiers
    }
}

// MARK: - Shortcut Preset Chip

struct ShortcutPresetChip: View {
    let label: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .rounded))
                .foregroundColor(isSelected ? .white : accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? accentColor : accentColor.opacity(0.1))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
