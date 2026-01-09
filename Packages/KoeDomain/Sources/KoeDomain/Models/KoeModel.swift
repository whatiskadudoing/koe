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
}
