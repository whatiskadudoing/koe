public enum TranscriptionMode: String, Codable, Sendable, CaseIterable {
    case vad = "vad"
    case realtime = "realtime"

    public var displayName: String {
        switch self {
        case .vad: return "on release"
        case .realtime: return "while speaking"
        }
    }

    public var description: String {
        switch self {
        case .vad: return "types after you release the key"
        case .realtime: return "types as you speak"
        }
    }
}
