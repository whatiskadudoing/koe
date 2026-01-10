import Foundation

/// Central registry of all models used by Koe
public enum ModelRegistry {

    // MARK: - WhisperKit Models

    /// WhisperKit large-v3-turbo model for transcription (default)
    /// Note: WhisperKit handles its own download flow, so this is not marked as required for ModelManager
    public static let whisperLargeV3Turbo = ModelDefinition(
        id: "whisperkit-large-v3-turbo",
        name: "Whisper Large V3 Turbo",
        description: "High-quality speech transcription model",
        category: .transcription,
        source: .huggingFace(
            repo: "argmaxinc/whisperkit-coreml",
            files: ["openai_whisper-large-v3-turbo"]
        ),
        sizeBytes: 1_600_000_000,  // ~1.6 GB
        isRequired: false  // WhisperKit manages its own downloads
    )

    /// WhisperKit base model (smaller, faster)
    public static let whisperBase = ModelDefinition(
        id: "whisperkit-base",
        name: "Whisper Base",
        description: "Smaller, faster transcription model",
        category: .transcription,
        source: .huggingFace(
            repo: "argmaxinc/whisperkit-coreml",
            files: ["openai_whisper-base"]
        ),
        sizeBytes: 150_000_000,  // ~150 MB
        isRequired: false
    )

    // MARK: - FluidAudio Models (Speaker Verification)

    /// FluidAudio speaker diarization models (WeSpeaker embeddings)
    public static let fluidAudioDiarization = ModelDefinition(
        id: "fluidaudio-diarization",
        name: "Speaker Verification",
        description: "WeSpeaker neural network for voice identification",
        category: .speakerVerification,
        source: .huggingFace(
            repo: "FluidInference/speaker-diarization-coreml",
            files: [
                "wespeaker_v2.mlmodelc",
                "pyannote_segmentation.mlmodelc",
            ]
        ),
        sizeBytes: 129_000_000,  // ~129 MB
        isRequired: false  // Optional - ECAPA-TDNN feature
    )

    // MARK: - LLM Models (Text Refinement)

    /// Llama model for text refinement
    public static let llamaRefinement = ModelDefinition(
        id: "llama-refinement",
        name: "Text Refinement",
        description: "Local LLM for grammar and style improvements",
        category: .textRefinement,
        source: .huggingFace(
            repo: "bartowski/Llama-3.2-1B-Instruct-GGUF",
            files: ["Llama-3.2-1B-Instruct-Q4_K_M.gguf"]
        ),
        sizeBytes: 800_000_000,  // ~800 MB
        isRequired: false
    )

    // MARK: - All Models

    /// All registered models
    public static let allModels: [ModelDefinition] = [
        whisperLargeV3Turbo,
        whisperBase,
        fluidAudioDiarization,
        llamaRefinement,
    ]

    /// Required models that must be downloaded
    public static var requiredModels: [ModelDefinition] {
        allModels.filter { $0.isRequired }
    }

    /// Optional models
    public static var optionalModels: [ModelDefinition] {
        allModels.filter { !$0.isRequired }
    }

    /// Total size of required models
    public static var requiredModelsSize: Int64 {
        requiredModels.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Total size of all models
    public static var totalModelsSize: Int64 {
        allModels.reduce(0) { $0 + $1.sizeBytes }
    }
}
