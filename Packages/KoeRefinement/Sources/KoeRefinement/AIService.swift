import Foundation
import KoeCore
import KoeDomain

/// Manages AI providers and processing pipelines
/// This is the main entry point for all AI text processing in Koe
@MainActor
public final class AIService: ObservableObject {
    // MARK: - Singleton

    public static let shared = AIService()

    // MARK: - Published State

    @Published public private(set) var currentTier: AITier = .best
    @Published public private(set) var status: AIProviderStatus = .notReady
    @Published public private(set) var isReady: Bool = false

    /// Downloaded models (tier -> downloaded)
    @Published public private(set) var downloadedModels: Set<AITier> = []

    // MARK: - Private Properties

    private var providers: [AITier: any AIProvider] = [:]
    private var activeProvider: (any AIProvider)?
    private let logger = KoeLogger.refinement

    // MARK: - Initialization

    private init() {
        // Load saved preferences
        if let savedTier = UserDefaults.standard.string(forKey: "ai_tier"),
            let tier = AITier(rawValue: savedTier)
        {
            currentTier = tier
        }

        // Check which models are downloaded
        checkDownloadedModels()
    }

    // MARK: - Public API

    /// Set the AI quality tier
    public func setTier(_ tier: AITier) async {
        guard tier != currentTier else { return }

        logger.info("Switching AI tier from \(currentTier.displayName) to \(tier.displayName)")

        // Shutdown current provider
        if let provider = activeProvider {
            await provider.shutdown()
            activeProvider = nil
        }

        currentTier = tier
        UserDefaults.standard.set(tier.rawValue, forKey: "ai_tier")

        // Prepare new provider
        await prepare()
    }

    /// Prepare the current tier's provider
    public func prepare() async {
        status = .loading

        do {
            let provider = try await getOrCreateProvider(for: currentTier)
            try await provider.prepare()
            activeProvider = provider
            status = await provider.status
            isReady = await provider.isReady
            logger.info("AI provider ready: \(provider.name)")
        } catch {
            logger.error("Failed to prepare AI provider", error: error)
            status = .error(error.localizedDescription)
            isReady = false
        }
    }

    /// Shutdown the active provider
    public func shutdown() async {
        if let provider = activeProvider {
            await provider.shutdown()
            activeProvider = nil
        }
        status = .notReady
        isReady = false
    }

    /// Refine text using the current provider
    public func refine(
        text: String,
        mode: RefinementMode = .cleanup,
        customPrompt: String? = nil
    ) async throws -> String {
        guard let provider = activeProvider, await provider.isReady else {
            // Try to prepare first
            await prepare()
            guard let provider = activeProvider, await provider.isReady else {
                throw RefinementError.modelNotLoaded
            }
            return try await provider.refine(text: text, mode: mode, customPrompt: customPrompt)
        }

        return try await provider.refine(text: text, mode: mode, customPrompt: customPrompt)
    }

    /// Run a multi-step pipeline
    /// Each step can use a different mode and tier
    public func runPipeline(
        text: String,
        steps: [PipelineStep]
    ) async throws -> String {
        var currentText = text

        for (index, step) in steps.enumerated() {
            logger.info("Pipeline step \(index + 1)/\(steps.count): \(step.mode.displayName)")

            // Switch tier if different
            if step.tier != currentTier {
                await setTier(step.tier)
            }

            currentText = try await refine(
                text: currentText,
                mode: step.mode,
                customPrompt: step.customPrompt
            )
        }

        return currentText
    }

    // MARK: - Model Management

    /// Check if a tier's model is downloaded
    public func isModelDownloaded(for tier: AITier) -> Bool {
        if tier == .custom {
            return true  // External (Ollama)
        }
        return downloadedModels.contains(tier)
    }

    /// Download a model for a tier
    public func downloadModel(for tier: AITier, progress: @escaping (Double) -> Void) async throws {
        guard let modelInfo = AIModelRegistry.model(for: tier) else {
            throw RefinementError.modelNotFound
        }

        logger.info("Downloading model for tier: \(tier.displayName)")

        // Create provider which will handle download
        let provider = LlamaCppProvider(modelInfo: modelInfo)
        providers[tier] = provider

        // Prepare will download if needed
        try await provider.prepare()

        downloadedModels.insert(tier)
        saveDownloadedModels()
    }

    /// Delete a downloaded model
    public func deleteModel(for tier: AITier) throws {
        guard let modelInfo = AIModelRegistry.model(for: tier),
            !modelInfo.isBundled
        else {
            return  // Can't delete bundled models
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelPath =
            appSupport
            .appendingPathComponent("Koe/Models", isDirectory: true)
            .appendingPathComponent(modelInfo.filename ?? "\(modelInfo.name).gguf")

        try FileManager.default.removeItem(at: modelPath)
        downloadedModels.remove(tier)
        saveDownloadedModels()

        logger.info("Deleted model for tier: \(tier.displayName)")
    }

    // MARK: - Private Methods

    private func getOrCreateProvider(for tier: AITier) async throws -> any AIProvider {
        if let existing = providers[tier] {
            return existing
        }

        let provider: any AIProvider

        switch tier {
        case .best:
            guard let modelInfo = AIModelRegistry.model(for: tier) else {
                throw RefinementError.modelNotFound
            }
            provider = LlamaCppProvider(modelInfo: modelInfo)

        case .custom:
            // Use Ollama for custom tier
            provider = OllamaProvider()
        }

        providers[tier] = provider
        return provider
    }

    private func checkDownloadedModels() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent("Koe/Models", isDirectory: true)

        // Check if best model is downloaded
        if let modelInfo = AIModelRegistry.model(for: .best),
            let filename = modelInfo.filename
        {
            let path = modelsDir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: path.path) {
                downloadedModels.insert(.best)
            }
        }

        // Load saved state
        if let saved = UserDefaults.standard.array(forKey: "downloaded_models") as? [String] {
            for rawValue in saved {
                if let tier = AITier(rawValue: rawValue) {
                    downloadedModels.insert(tier)
                }
            }
        }
    }

    private func saveDownloadedModels() {
        let values = downloadedModels.map { $0.rawValue }
        UserDefaults.standard.set(values, forKey: "downloaded_models")
    }
}

// MARK: - Pipeline Step

/// A step in the AI processing pipeline
public struct PipelineStep: Sendable {
    public let tier: AITier
    public let mode: RefinementMode
    public let customPrompt: String?

    public init(
        tier: AITier = .best,
        mode: RefinementMode = .cleanup,
        customPrompt: String? = nil
    ) {
        self.tier = tier
        self.mode = mode
        self.customPrompt = customPrompt
    }

    /// Cleanup step
    public static let cleanup = PipelineStep(tier: .best, mode: .cleanup)

    /// Prompt improvement step
    public static let improvePrompt = PipelineStep(tier: .best, mode: .promptImprover)

    /// Formalize text step
    public static let formalize = PipelineStep(tier: .best, mode: .formal)

    /// Casual text step
    public static let casual = PipelineStep(tier: .best, mode: .casual)
}

// MARK: - Ollama Provider Wrapper

/// Wrapper to make OllamaRefinementService conform to AIProvider
public actor OllamaProvider: AIProvider {
    public nonisolated let id = "ollama"
    public nonisolated let name = "Ollama (Custom)"

    private let service = OllamaRefinementService.shared

    public var status: AIProviderStatus {
        if service.isReady {
            return .ready
        } else if service.isConnected {
            return .loading
        } else {
            return .notReady
        }
    }

    public var isReady: Bool {
        service.isReady
    }

    public func prepare() async throws {
        let connected = await service.checkConnection()
        if !connected {
            throw RefinementError.connectionFailed("Cannot connect to Ollama")
        }
    }

    public func refine(text: String, mode: RefinementMode, customPrompt: String?) async throws -> String {
        service.setMode(mode)
        if let prompt = customPrompt {
            service.setCustomPrompt(prompt)
        }
        return try await service.refine(text: text)
    }

    public func shutdown() async {
        // Ollama manages its own lifecycle
    }
}

// MARK: - Convenience Extensions

extension AIService {
    /// Quick cleanup
    public func quickCleanup(_ text: String) async throws -> String {
        return try await refine(text: text, mode: .cleanup)
    }

    /// Standard transcription pipeline: cleanup + (optional) prompt improvement
    public func processTranscription(
        _ text: String,
        improveAsPrompt: Bool = false
    ) async throws -> String {
        var steps = [PipelineStep.cleanup]

        if improveAsPrompt {
            steps.append(.improvePrompt)
        }

        return try await runPipeline(text: text, steps: steps)
    }
}
