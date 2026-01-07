import SwiftUI
import KoeDomain

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isLoadingModel = false

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    var body: some View {
        @Bindable var appState = appState

        Form {
            Section("Transcription") {
                Picker("Model", selection: $appState.selectedModel) {
                    ForEach(KoeModel.allCases, id: \.rawValue) { model in
                        Text(model.displayName).tag(model.rawValue)
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
                    ForEach(Language.all, id: \.code) { lang in
                        Text("\(lang.flag) \(lang.name)").tag(lang.code)
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
                Text("Koe 声 - Voice to Text")
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
