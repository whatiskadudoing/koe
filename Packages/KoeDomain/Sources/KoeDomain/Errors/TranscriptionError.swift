import Foundation

public enum TranscriptionError: KoeError {
    case modelNotLoaded
    case modelLoadFailed(model: KoeModel, underlying: Error)
    case transcriptionFailed(underlying: Error)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Transcription model not loaded"
        case .modelLoadFailed(let model, let error):
            return "Failed to load \(model.displayName): \(error.localizedDescription)"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .cancelled:
            return "Transcription cancelled"
        }
    }
}
