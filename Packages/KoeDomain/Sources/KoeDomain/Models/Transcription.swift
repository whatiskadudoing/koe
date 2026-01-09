import Foundation

/// Stores the refinement options that were active during transcription
public struct RefinementSettings: Codable, Sendable, Equatable {
    public let cleanup: Bool
    public let tone: String  // "none", "formal", "casual"
    public let promptMode: Bool
    public let customInstructions: String?
    public let aiTier: String?  // "fast", "smart", "best", "custom"
    public let durationSeconds: Double?  // How long refinement took

    public init(
        cleanup: Bool = false,
        tone: String = "none",
        promptMode: Bool = false,
        customInstructions: String? = nil,
        aiTier: String? = nil,
        durationSeconds: Double? = nil
    ) {
        self.cleanup = cleanup
        self.tone = tone
        self.promptMode = promptMode
        self.customInstructions = customInstructions
        self.aiTier = aiTier
        self.durationSeconds = durationSeconds
    }

    /// Human-readable summary of settings
    public var summary: String {
        var parts: [String] = []
        if cleanup { parts.append("cleanup") }
        if promptMode {
            parts.append("prompt")
        } else if tone != "none" {
            parts.append(tone)
        }
        if let custom = customInstructions, !custom.isEmpty {
            parts.append("custom")
        }
        return parts.isEmpty ? "none" : parts.joined(separator: " + ")
    }

    /// Duration formatted as string
    public var durationFormatted: String? {
        guard let seconds = durationSeconds else { return nil }
        return String(format: "%.1fs", seconds)
    }
}

public struct Transcription: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let duration: TimeInterval
    public let timestamp: Date
    public let language: Language?
    public let model: KoeModel?
    public let wasRefined: Bool
    public let originalText: String?
    public let refinementSettings: RefinementSettings?
    /// ID linking to the PipelineExecutionRecord for detailed metrics
    public let pipelineRunId: UUID?

    public init(
        id: UUID = UUID(),
        text: String,
        duration: TimeInterval,
        timestamp: Date = Date(),
        language: Language? = nil,
        model: KoeModel? = nil,
        wasRefined: Bool = false,
        originalText: String? = nil,
        refinementSettings: RefinementSettings? = nil,
        pipelineRunId: UUID? = nil
    ) {
        self.id = id
        self.text = text
        self.duration = duration
        self.timestamp = timestamp
        self.language = language
        self.model = model
        self.wasRefined = wasRefined
        self.originalText = originalText
        self.refinementSettings = refinementSettings
        self.pipelineRunId = pipelineRunId
    }
}
