import Foundation

/// A user's voice profile for speaker verification
public struct VoiceProfile: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let embedding: [Float]
    public let trainingCommandSamples: Int
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        embedding: [Float],
        trainingCommandSamples: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.embedding = embedding
        self.trainingCommandSamples = trainingCommandSamples
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Audio features extracted from voice samples for speaker verification
/// Uses simple acoustic features that don't require an ML model
public struct VoiceFeatures: Codable, Sendable {
    /// Average pitch (fundamental frequency) in Hz
    public let averagePitch: Float

    /// Pitch variance
    public let pitchVariance: Float

    /// Average energy/loudness
    public let averageEnergy: Float

    /// Energy variance
    public let energyVariance: Float

    /// Zero crossing rate (related to voice quality)
    public let zeroCrossingRate: Float

    /// Spectral centroid (brightness of voice)
    public let spectralCentroid: Float

    /// Spectral rolloff (frequency below which 85% of energy is contained)
    public let spectralRolloff: Float

    /// Speaking rate estimate (syllables per second approximation)
    public let speakingRate: Float

    public init(
        averagePitch: Float,
        pitchVariance: Float,
        averageEnergy: Float,
        energyVariance: Float,
        zeroCrossingRate: Float,
        spectralCentroid: Float,
        spectralRolloff: Float,
        speakingRate: Float
    ) {
        self.averagePitch = averagePitch
        self.pitchVariance = pitchVariance
        self.averageEnergy = averageEnergy
        self.energyVariance = energyVariance
        self.zeroCrossingRate = zeroCrossingRate
        self.spectralCentroid = spectralCentroid
        self.spectralRolloff = spectralRolloff
        self.speakingRate = speakingRate
    }

    /// Convert features to a normalized embedding vector
    public func toEmbedding() -> [Float] {
        [
            averagePitch / 500.0,        // Normalize pitch (typically 80-300 Hz)
            pitchVariance / 100.0,       // Normalize variance
            averageEnergy,               // Already 0-1
            energyVariance,              // Already small
            zeroCrossingRate,            // Already normalized
            spectralCentroid / 8000.0,   // Normalize (typically 1000-4000 Hz)
            spectralRolloff / 16000.0,   // Normalize to sample rate
            speakingRate / 10.0          // Normalize (typically 2-6 syllables/sec)
        ]
    }

    /// Calculate similarity between two feature sets (0.0 to 1.0)
    public func similarity(to other: VoiceFeatures) -> Float {
        let embedding1 = self.toEmbedding()
        let embedding2 = other.toEmbedding()
        return VoiceFeatures.cosineSimilarity(embedding1, embedding2)
    }

    /// Cosine similarity between two vectors
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }
}

/// Training state for voice enrollment
public enum VoiceTrainingState: Sendable, Equatable {
    case notStarted
    case intro
    case recording(sampleIndex: Int, totalSamples: Int)
    case processing
    case complete(VoiceProfile)
    case error(String)

    public var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }
}
