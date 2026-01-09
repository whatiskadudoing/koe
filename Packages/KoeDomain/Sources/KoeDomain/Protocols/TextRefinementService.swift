import Foundation

/// Service for AI-powered text refinement (grammar, punctuation, filler word removal)
public protocol TextRefinementService: Sendable {
    /// Whether the model is loaded and ready for refinement
    var isReady: Bool { get async }

    /// Model loading progress (0.0 - 1.0)
    var loadingProgress: Double { get async }

    /// Currently loaded model
    var currentModel: RefinementModel? { get async }

    /// Load the refinement model
    func loadModel(_ model: RefinementModel) async throws

    /// Unload the current model
    func unloadModel() async

    /// Refine text by fixing grammar, punctuation, and removing filler words
    /// - Parameter text: The raw transcribed text
    /// - Returns: The refined text
    func refine(text: String) async throws -> String

    /// Progress stream for model loading
    func loadingProgressStream() -> AsyncStream<Double>
}
