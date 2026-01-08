/// Represents the current state of the recording/transcription pipeline
public enum RecordingState: Equatable, Sendable {
    /// No recording in progress
    case idle

    /// Actively recording audio from microphone
    case recording

    /// Converting audio to text using Whisper
    case transcribing

    /// AI is refining/improving the transcribed text
    case refining

    /// Legacy alias for transcribing (backwards compatibility)
    public static var processing: RecordingState { .transcribing }

    /// Whether audio is currently being captured
    public var isRecording: Bool {
        self == .recording
    }

    /// Whether any processing is happening (transcribing or refining)
    public var isProcessing: Bool {
        self == .transcribing || self == .refining
    }

    /// Whether the system is busy (recording or processing)
    public var isBusy: Bool {
        self != .idle
    }
}
