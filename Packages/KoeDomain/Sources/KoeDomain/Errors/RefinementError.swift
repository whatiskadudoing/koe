import Foundation

public enum RefinementError: KoeError {
    case modelNotLoaded
    case modelLoadFailed(model: RefinementModel, underlying: Error)
    case refinementFailed(underlying: Error)
    case timeout
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Refinement model not loaded"
        case .modelLoadFailed(let model, let error):
            return "Failed to load \(model.displayName): \(error.localizedDescription)"
        case .refinementFailed(let error):
            return "Refinement failed: \(error.localizedDescription)"
        case .timeout:
            return "Refinement timed out"
        case .cancelled:
            return "Refinement cancelled"
        }
    }
}
