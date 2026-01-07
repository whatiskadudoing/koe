import Foundation

public enum AudioError: KoeError {
    case microphoneAccessDenied
    case engineStartFailed(underlying: Error)
    case recordingFailed(underlying: Error)
    case noAudioData
    case audioTooShort(duration: TimeInterval, minimum: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied:
            return "Microphone access denied. Please enable in System Settings."
        case .engineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .recordingFailed(let error):
            return "Recording failed: \(error.localizedDescription)"
        case .noAudioData:
            return "No audio data recorded"
        case .audioTooShort(let duration, let minimum):
            return "Audio too short (\(String(format: "%.1f", duration))s). Minimum: \(String(format: "%.1f", minimum))s"
        }
    }
}
