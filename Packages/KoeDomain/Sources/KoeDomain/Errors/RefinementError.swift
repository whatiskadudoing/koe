import Foundation

public enum RefinementError: KoeError {
    case modelNotLoaded
    case modelNotFound
    case modelLoadFailed(model: RefinementModel, underlying: Error)
    case refinementFailed(underlying: Error)
    case processingFailed(String)
    case connectionFailed(String)
    case downloadFailed(String)
    case timeout
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Refinement model not loaded"
        case .modelNotFound:
            return "Refinement model not found"
        case .modelLoadFailed(let model, let error):
            return "Failed to load \(model.displayName): \(error.localizedDescription)"
        case .refinementFailed(let error):
            return "Refinement failed: \(error.localizedDescription)"
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .timeout:
            return "Refinement timed out"
        case .cancelled:
            return "Refinement cancelled"
        }
    }
}
