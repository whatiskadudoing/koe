import Foundation

/// Transcription service - CAN run locally or remotely
public protocol TranscriptionService: Sendable {
    /// Whether model is loaded and ready
    var isReady: Bool { get async }

    /// Model loading progress (0.0 - 1.0)
    var loadingProgress: Double { get async }

    /// Currently loaded model name
    var currentModel: KoeModel? { get async }

    /// Load a transcription model
    func loadModel(_ model: KoeModel) async throws

    /// Unload current model
    func unloadModel() async

    /// Transcribe audio data
    func transcribe(
        audioData: Data,
        language: Language?
    ) async throws -> Transcription

    /// Transcribe audio from samples (for streaming)
    func transcribe(
        samples: [Float],
        sampleRate: Double,
        language: Language?
    ) async throws -> String

    /// Progress stream for model loading
    func loadingProgressStream() -> AsyncStream<Double>
}
