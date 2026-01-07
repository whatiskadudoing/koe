import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var isLoadingModel = false

    private let models = [
        ("tiny", "Tiny (39 MB) - Fastest"),
        ("base", "Base (74 MB) - Fast"),
        ("small", "Small (244 MB) - Balanced"),
        ("medium", "Medium (769 MB) - Accurate"),
        ("large-v3", "Large V3 (1.5 GB) - Best Quality")
    ]

    private let languages = [
        ("auto", "Auto-detect (Recommended)"),
        ("en", "English"),
        ("es", "Spanish"),
        ("pt", "Portuguese"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese")
    ]

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Model", selection: $appState.selectedModel) {
                    ForEach(models, id: \.0) { model in
                        Text(model.1).tag(model.0)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: appState.selectedModel) { _, newModel in
                    reloadModel(newModel)
                }

                if isLoadingModel && !appState.isModelLoaded {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading model...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Picker("Language", selection: $appState.selectedLanguage) {
                    ForEach(languages, id: \.0) { lang in
                        Text(lang.1).tag(lang.0)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("History") {
                HStack {
                    Text("Entries: \(appState.transcriptionHistory.count)")
                    Spacer()
                    Button("Clear History") {
                        appState.clearHistory()
                    }
                    .foregroundColor(.red)
                }
            }

            Section("About") {
                Text("Whisper Voice-to-Text")
                    .font(.headline)
                Text("Powered by WhisperKit")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 320)
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

