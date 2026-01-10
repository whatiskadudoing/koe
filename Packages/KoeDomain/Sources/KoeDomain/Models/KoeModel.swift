/// WhisperKit transcription models
/// Each model offers different speed/accuracy tradeoffs
public enum KoeModel: String, Codable, Sendable, CaseIterable {
    /// Balanced model - good speed and accuracy (default)
    case balanced = "large-v3-v20240930_turbo_632MB"

    /// Accurate model - best accuracy, slower
    case accurate = "large-v3_947MB"

    public var displayName: String {
        switch self {
        case .balanced: return "Balanced (632 MB)"
        case .accurate: return "Accurate (947 MB)"
        }
    }

    public var shortName: String {
        switch self {
        case .balanced: return "Balanced"
        case .accurate: return "Accurate"
        }
    }

    /// Icon for the model toggle UI
    public var icon: String {
        switch self {
        case .balanced: return "gauge.with.dots.needle.50percent"
        case .accurate: return "target"
        }
    }

    /// Description of the model's characteristics
    public var modelDescription: String {
        switch self {
        case .balanced: return "Best speed/accuracy balance"
        case .accurate: return "Highest accuracy, slower"
        }
    }

    /// Models downloaded during installation (none - download on demand)
    public static var installationModels: [KoeModel] {
        []
    }

    /// Models downloaded in background after app launch
    public static var backgroundModels: [KoeModel] {
        []  // No background models - download on demand
    }

    /// Estimated size in bytes for progress tracking
    public var estimatedBytes: Int64 {
        switch self {
        case .balanced: return 632_000_000
        case .accurate: return 947_000_000
        }
    }

    /// Human-readable size string
    public var sizeString: String {
        switch self {
        case .balanced: return "632 MB"
        case .accurate: return "947 MB"
        }
    }

    /// Whether this model uses GPU+ANE for maximum performance
    public var usesGPUAndANE: Bool {
        true  // All models use GPU+ANE for best performance
    }
}
