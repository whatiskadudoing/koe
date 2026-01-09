import Foundation

/// AI quality tiers - determines which model/provider to use
public enum AITier: String, Codable, Sendable, CaseIterable {
    /// Best quality model - Qwen 2.5 3B with GPU acceleration (~2GB)
    case best = "best"

    /// Custom - use Ollama with any model (advanced users)
    case custom = "custom"

    /// Display name for UI
    public var displayName: String {
        switch self {
        case .best: return "Qwen 3B"
        case .custom: return "Custom"
        }
    }

    /// Short description
    public var description: String {
        switch self {
        case .best: return "GPU accelerated (~2GB)"
        case .custom: return "Use Ollama"
        }
    }

    /// Icon for UI
    public var icon: String {
        switch self {
        case .best: return "sparkles"
        case .custom: return "gearshape.fill"
        }
    }

    /// Approximate model size in bytes
    public var approximateSize: Int64 {
        switch self {
        case .best: return 2_000_000_000     // ~2GB
        case .custom: return 0               // Varies
        }
    }

    /// Human-readable size string
    public var sizeString: String {
        switch self {
        case .best: return "~2GB"
        case .custom: return "Varies"
        }
    }

    /// Whether this tier requires download
    public var requiresDownload: Bool {
        switch self {
        case .best: return true
        case .custom: return false  // Uses Ollama
        }
    }

    /// Whether this tier works offline
    public var worksOffline: Bool {
        switch self {
        case .best: return true   // After download
        case .custom: return true // Ollama is local
        }
    }

    /// Default tier
    public static var `default`: AITier {
        .best
    }
}
