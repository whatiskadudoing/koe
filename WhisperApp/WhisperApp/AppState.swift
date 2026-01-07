import SwiftUI
import Combine

enum RecordingState {
    case idle
    case recording
    case processing
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var recordingState: RecordingState = .idle {
        didSet {
            NotificationCenter.default.post(name: .appStateChanged, object: nil)
        }
    }

    @Published var currentTranscription: String = ""
    @Published var transcriptionHistory: [TranscriptionEntry] = []
    @Published var isModelLoaded: Bool = false
    @Published var modelLoadingProgress: Double = 0.0
    @Published var errorMessage: String?

    // Settings - "tiny" is fastest by default, can change to better models in menu bar or settings
    @AppStorage("selectedModel") var selectedModel: String = "tiny"
    @AppStorage("selectedLanguage") var selectedLanguage: String = "auto"
    // Transcription mode: "realtime" = types while speaking, "vad" = waits for pauses
    @AppStorage("transcriptionMode") var transcriptionMode: String = "vad"

    private init() {
        loadHistory()
    }

    func addTranscription(_ text: String, duration: TimeInterval) {
        let entry = TranscriptionEntry(
            id: UUID(),
            text: text,
            duration: duration,
            timestamp: Date()
        )
        transcriptionHistory.insert(entry, at: 0)

        // Keep only last 50 entries
        if transcriptionHistory.count > 50 {
            transcriptionHistory = Array(transcriptionHistory.prefix(50))
        }

        saveHistory()
    }

    func clearHistory() {
        transcriptionHistory.removeAll()
        saveHistory()
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "transcriptionHistory"),
           let history = try? JSONDecoder().decode([TranscriptionEntry].self, from: data) {
            // Filter out entries older than 7 days
            let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            transcriptionHistory = history.filter { $0.timestamp > cutoff }
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(transcriptionHistory) {
            UserDefaults.standard.set(data, forKey: "transcriptionHistory")
        }
    }
}

struct TranscriptionEntry: Identifiable, Codable {
    let id: UUID
    let text: String
    let duration: TimeInterval
    let timestamp: Date
}
