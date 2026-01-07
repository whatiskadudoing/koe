public enum KoeModel: String, Codable, Sendable, CaseIterable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case largeV3 = "large-v3"

    public var displayName: String {
        switch self {
        case .tiny: return "Tiny (39 MB) - Fastest"
        case .base: return "Base (74 MB) - Fast"
        case .small: return "Small (244 MB) - Balanced"
        case .medium: return "Medium (769 MB) - Accurate"
        case .largeV3: return "Large V3 (1.5 GB) - Best Quality"
        }
    }

    public var shortName: String {
        switch self {
        case .tiny: return "Tiny - Fastest"
        case .base: return "Base - Fast"
        case .small: return "Small - Balanced"
        case .medium: return "Medium - Accurate"
        case .largeV3: return "Large - Best"
        }
    }
}
