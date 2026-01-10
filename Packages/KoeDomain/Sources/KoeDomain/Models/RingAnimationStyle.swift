import Foundation

/// Available animation styles for the audio-reactive ring
public enum RingAnimationStyle: String, CaseIterable, Codable, Sendable {
    case wave = "wave"  // Smooth flowing sine waves (Siri-style)
    case blob = "blob"  // Organic morphing shape

    public var displayName: String {
        switch self {
        case .wave: return "Wave"
        case .blob: return "Blob"
        }
    }

    public var description: String {
        switch self {
        case .wave: return "Smooth flowing waves"
        case .blob: return "Organic morphing shape"
        }
    }

    public var icon: String {
        switch self {
        case .wave: return "waveform"
        case .blob: return "drop"
        }
    }
}
