import Foundation

/// Audio recording service - MUST run on client (hardware access)
public protocol AudioRecordingService: Sendable {
    /// Current audio level (0.0 - 1.0) for visualization
    var audioLevel: Float { get async }

    /// Whether currently recording
    var isRecording: Bool { get async }

    /// Start recording audio
    func startRecording() async throws

    /// Stop recording and return audio data
    func stopRecording() async throws -> Data

    /// Get accumulated audio samples (for streaming transcription)
    func getAudioSamples() async -> [Float]

    /// Audio level stream for real-time updates
    func audioLevelStream() -> AsyncStream<Float>
}
