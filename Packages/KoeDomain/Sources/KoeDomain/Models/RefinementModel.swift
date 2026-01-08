import Foundation

/// Available LLM models for text refinement
public enum RefinementModel: String, Codable, Sendable, CaseIterable {
    case qwen25_3b = "qwen2.5-3b"

    /// Display name for the model
    public var displayName: String {
        switch self {
        case .qwen25_3b:
            return "Qwen 2.5 (3B)"
        }
    }

    /// Approximate model size in GB
    public var sizeGB: Double {
        switch self {
        case .qwen25_3b:
            return 2.0
        }
    }

    /// Default model for refinement
    public static var `default`: RefinementModel {
        .qwen25_3b
    }
}
