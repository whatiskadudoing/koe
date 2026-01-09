import Foundation

/// Tone style options for text refinement (mutually exclusive)
public enum ToneStyle: String, Codable, Sendable, CaseIterable {
    case none = "none"
    case formal = "formal"
    case casual = "casual"

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .formal: return "Formal"
        case .casual: return "Casual"
        }
    }

    public var description: String {
        switch self {
        case .none: return "Keep original tone"
        case .formal: return "Professional, formal tone"
        case .casual: return "Friendly, conversational"
        }
    }

    public var promptFragment: String? {
        switch self {
        case .none:
            return nil
        case .formal:
            return "Rewrite in a professional, formal tone. Use proper grammar and remove casual language."
        case .casual:
            return "Rewrite in a friendly, casual tone. Keep it conversational and natural."
        }
    }
}
