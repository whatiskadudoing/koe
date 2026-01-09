public enum KoeModel: String, Codable, Sendable, CaseIterable {
    case fast = "large-v3-v20240930_turbo_632MB"
    case balanced = "large-v3_turbo_954MB"
    case best = "large-v3-v20240930_turbo"

    public var displayName: String {
        switch self {
        case .fast: return "Fast (632 MB)"
        case .balanced: return "Balanced (954 MB)"
        case .best: return "Best Quality (3.1 GB)"
        }
    }

    public var shortName: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .best: return "Best Quality"
        }
    }

    /// Icon for the model toggle UI
    public var icon: String {
        switch self {
        case .fast: return "hare"
        case .balanced: return "scalemass"
        case .best: return "star"
        }
    }

    /// All models for download during installation
    public static var allModelsForDownload: [KoeModel] {
        [.fast, .balanced, .best]
    }

    /// Models downloaded during installation (only Fast for quick setup)
    public static var installationModels: [KoeModel] {
        [.fast]
    }

    /// Models downloaded in background after app launch
    public static var backgroundModels: [KoeModel] {
        [.balanced, .best]
    }

    /// Estimated size in bytes for progress tracking
    public var estimatedBytes: Int64 {
        switch self {
        case .fast: return 632_000_000
        case .balanced: return 954_000_000
        case .best: return 3_100_000_000
        }
    }

    /// Human-readable size string
    public var sizeString: String {
        switch self {
        case .fast: return "632 MB"
        case .balanced: return "954 MB"
        case .best: return "3.1 GB"
        }
    }
}
