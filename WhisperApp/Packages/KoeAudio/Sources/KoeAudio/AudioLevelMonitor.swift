import Foundation

/// Monitors audio levels from samples and provides RMS-based level calculations
public final class AudioLevelMonitor: Sendable {
    public init() {}

    /// Calculate normalized audio level (0.0 - 1.0) from samples
    /// Uses RMS (Root Mean Square) for accurate level measurement
    public func calculateLevel(from samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }

        // Calculate RMS
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))

        // Convert to dB and normalize
        let db = 20 * log10(max(rms, 0.0001))

        // Normalize: -50dB = 0.0, 0dB = 1.0
        let normalizedLevel = max(0, min(1, (db + 50) / 50))

        return normalizedLevel
    }

    /// Calculate raw RMS value from samples
    public func calculateRMS(from samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}
