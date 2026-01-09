import Foundation

/// Status of an AI provider
public enum AIProviderStatus: Sendable, Equatable {
    case notReady
    case downloading(progress: Double, description: String)
    case loading
    case ready
    case error(String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var displayText: String {
        switch self {
        case .notReady: return "Not ready"
        case .downloading(let progress, let desc):
            let percent = Int(progress * 100)
            return desc.isEmpty ? "Downloading \(percent)%" : desc
        case .loading: return "Loading..."
        case .ready: return "Ready"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

/// Protocol for AI text refinement providers
/// Implement this protocol to add new AI backends (Ollama, llama.cpp, MLX, etc.)
public protocol AIProvider: Sendable {
    /// Unique identifier for this provider
    var id: String { get }

    /// Display name for UI
    var name: String { get }

    /// Current status
    var status: AIProviderStatus { get async }

    /// Whether this provider is ready to process text
    var isReady: Bool { get async }

    /// Initialize/prepare the provider (download model, load weights, etc.)
    func prepare() async throws

    /// Refine text using the specified mode
    /// - Parameters:
    ///   - text: The text to refine
    ///   - mode: The refinement mode (cleanup, formal, casual, etc.)
    ///   - customPrompt: Custom prompt (used when mode is .custom)
    /// - Returns: The refined text
    func refine(text: String, mode: RefinementMode, customPrompt: String?) async throws -> String

    /// Release resources (unload model, etc.)
    func shutdown() async
}

/// Default implementations
public extension AIProvider {
    /// Convenience method without custom prompt
    func refine(text: String, mode: RefinementMode) async throws -> String {
        try await refine(text: text, mode: mode, customPrompt: nil)
    }
}

/// Information about an AI model
public struct AIModelInfo: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }

    /// Model name/identifier
    public let name: String

    /// Display name for UI
    public let displayName: String

    /// Model description
    public let description: String

    /// Size in bytes (0 if unknown)
    public let sizeBytes: Int64

    /// Hugging Face repository ID (for downloading)
    public let huggingFaceRepo: String?

    /// Filename within the repo
    public let filename: String?

    /// Which tier this model belongs to
    public let tier: AITier

    /// Whether this model is bundled with the app
    public let isBundled: Bool

    public init(
        name: String,
        displayName: String,
        description: String,
        sizeBytes: Int64,
        huggingFaceRepo: String? = nil,
        filename: String? = nil,
        tier: AITier,
        isBundled: Bool = false
    ) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.sizeBytes = sizeBytes
        self.huggingFaceRepo = huggingFaceRepo
        self.filename = filename
        self.tier = tier
        self.isBundled = isBundled
    }

    /// Human-readable size
    public var sizeString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }
}

/// Registry of available AI models
public struct AIModelRegistry {
    /// Best tier model - Qwen2.5 3B (highest quality, GPU accelerated, ~2GB)
    public static let bestModel = AIModelInfo(
        name: "qwen2.5-3b-instruct",
        displayName: "Qwen 2.5 3B",
        description: "Best quality with GPU acceleration (~2GB)",
        sizeBytes: 2_000_000_000,
        huggingFaceRepo: "Qwen/Qwen2.5-3B-Instruct-GGUF",
        filename: "qwen2.5-3b-instruct-q4_k_m.gguf",
        tier: .best,
        isBundled: false
    )

    /// Get model info for a tier
    public static func model(for tier: AITier) -> AIModelInfo? {
        switch tier {
        case .best: return bestModel
        case .custom: return nil  // Custom uses Ollama
        }
    }

    /// All available models
    public static let allModels: [AIModelInfo] = [
        bestModel
    ]
}
