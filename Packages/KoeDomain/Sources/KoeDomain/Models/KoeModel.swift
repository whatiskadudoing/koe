public enum KoeModel: String, Codable, Sendable, CaseIterable {
    case turbo = "large-v3_turbo_954MB"
    case large = "large-v3-v20240930_turbo"

    public var displayName: String {
        switch self {
        case .turbo: return "Turbo (954 MB)"
        case .large: return "Large (3.1 GB)"
        }
    }

    public var shortName: String {
        switch self {
        case .turbo: return "Turbo"
        case .large: return "Large"
        }
    }

    /// Icon for the model toggle UI
    public var icon: String {
        switch self {
        case .turbo: return "bolt"
        case .large: return "star"
        }
    }

    /// Models downloaded during installation
    public static var installationModels: [KoeModel] {
        [.turbo]
    }

    /// Models downloaded in background after app launch
    public static var backgroundModels: [KoeModel] {
        [.large]
    }

    /// Estimated size in bytes for progress tracking
    public var estimatedBytes: Int64 {
        switch self {
        case .turbo: return 954_000_000
        case .large: return 3_100_000_000
        }
    }

    /// Human-readable size string
    public var sizeString: String {
        switch self {
        case .turbo: return "954 MB"
        case .large: return "3.1 GB"
        }
    }
}
