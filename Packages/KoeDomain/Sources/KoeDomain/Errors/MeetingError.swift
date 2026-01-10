import Foundation

public enum MeetingError: KoeError {
    case detectionFailed(underlying: Error)
    case recordingFailed(underlying: Error)
    case screenRecordingPermissionDenied
    case audioDeviceNotFound
    case storageFailed(underlying: Error)
    case meetingNotFound(id: UUID)
    case transcriptionFailed(underlying: Error)
    case alreadyRecording
    case notRecording

    public var errorDescription: String? {
        switch self {
        case .detectionFailed(let error):
            return "Meeting detection failed: \(error.localizedDescription)"
        case .recordingFailed(let error):
            return "Meeting recording failed: \(error.localizedDescription)"
        case .screenRecordingPermissionDenied:
            return
                "Screen Recording permission denied. Please enable in System Settings > Privacy & Security > Screen Recording."
        case .audioDeviceNotFound:
            return "Audio device not found"
        case .storageFailed(let error):
            return "Failed to save meeting: \(error.localizedDescription)"
        case .meetingNotFound(let id):
            return "Meeting not found: \(id)"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .alreadyRecording:
            return "Already recording a meeting"
        case .notRecording:
            return "No meeting is being recorded"
        }
    }
}
