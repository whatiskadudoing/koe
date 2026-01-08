import Foundation

/// Audio input stage - captures or receives audio data
/// Must be the first element in any audio pipeline
public final class AudioInputStage: PipelineStage, @unchecked Sendable {
    public let stageTypeId = "audio-input"
    public var id: String { stageTypeId }
    public let displayName = "Audio Input"
    public let description = "Captures or receives audio data"
    public let icon = "mic.fill"

    public var constraints: ElementConstraints { .mustBeFirst }

    public var connectionRules: ConnectionRules {
        ConnectionRules(
            acceptsInput: [],  // No input - this is a source
            producesOutput: .audio
        )
    }

    public var isEnabled: Bool = true
    public var configuration: [String: Any] = [:]

    public init() {}

    public func process(_ context: PipelineContext) async throws {
        // Audio input is typically handled externally and provided via context
        // This stage validates that audio data exists
        guard context.audioSamples != nil || context.audioFilePath != nil else {
            throw StageError.missingInput("No audio data provided")
        }
    }
}

/// Voice Activity Detection stage
public final class VADStage: PipelineStage, @unchecked Sendable {
    public let stageTypeId = "vad"
    public var id: String { stageTypeId }
    public let displayName = "Voice Detection"
    public let description = "Detects speech in audio"
    public let icon = "waveform"

    public var constraints: ElementConstraints { [.cannotBeFirst, .cannotBeLast] }

    public var connectionRules: ConnectionRules {
        ConnectionRules(
            acceptsInput: [.audio],
            producesOutput: .audio,
            requiredPredecessors: ["audio-input"]
        )
    }

    public var isEnabled: Bool = true
    public var configuration: [String: Any] = [:]

    public init() {}

    public func process(_ context: PipelineContext) async throws {
        // VAD processing would happen here
        // For now, this is a pass-through that marks VAD as applied
        context.setCustomData(true, forKey: "vad_applied")
    }
}

/// Transcription stage - converts audio to text
public final class TranscriptionStage: PipelineStage, @unchecked Sendable {
    public let stageTypeId = "transcription"
    public var id: String { stageTypeId }
    public let displayName = "Transcription"
    public let description = "Converts speech to text"
    public let icon = "text.bubble"

    public var constraints: ElementConstraints { [.cannotBeFirst, .cannotBeLast] }

    public var connectionRules: ConnectionRules {
        ConnectionRules(
            acceptsInput: [.audio, .audioFile],
            producesOutput: .text,
            requiredPredecessors: ["audio-input"]
        )
    }

    public var isEnabled: Bool = true
    public var configuration: [String: Any] = [
        "model": "tiny",
        "language": "auto"
    ]

    /// Handler for transcription (injected from app)
    public var transcribeHandler: (([Float], Double, String?) async throws -> String)?

    public init() {}

    public func process(_ context: PipelineContext) async throws {
        // If text already provided, use it
        if !context.text.isEmpty {
            context.originalText = context.text
            return
        }

        // Otherwise transcribe audio
        guard let samples = context.audioSamples else {
            throw StageError.missingInput("No audio samples provided")
        }

        if let handler = transcribeHandler {
            let lang = configuration["language"] as? String
            context.text = try await handler(samples, context.sampleRate, lang == "auto" ? nil : lang)
            context.originalText = context.text
        } else {
            throw StageError.notImplemented("Transcription handler not configured")
        }
    }
}

/// Stage errors
public enum StageError: Error, LocalizedError {
    case missingInput(String)
    case processingFailed(String)
    case notImplemented(String)
    case configurationError(String)

    public var errorDescription: String? {
        switch self {
        case .missingInput(let msg): return "Missing input: \(msg)"
        case .processingFailed(let msg): return "Processing failed: \(msg)"
        case .notImplemented(let msg): return "Not implemented: \(msg)"
        case .configurationError(let msg): return "Configuration error: \(msg)"
        }
    }
}
