import SwiftUI
import KoeDomain

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isLoadingModel = false

    // Japanese-inspired color palette
    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let pageBackground = Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))
    private let cardBackground = Color.white

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

                    // AI Refinement section
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
                                    Text("Text Improvement")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(accentColor.opacity(0.5))

                                    Text("Fix grammar and remove filler words")
                                        .font(.system(size: 12))
                                        .foregroundColor(lightGray.opacity(0.7))
                                }

                                Spacer()

                                Toggle("", isOn: $appState.isRefinementEnabled)
                                    .toggleStyle(.switch)
                                    .tint(accentColor)
                                    .disabled(true)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider()
                                .padding(.horizontal, 16)

                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 12))
                                Text("Temporarily unavailable on macOS 26")
                                    .font(.system(size: 12))
                                    .foregroundColor(lightGray)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .background(cardBackground)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                    }

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
        .frame(width: 400, height: 540)
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
