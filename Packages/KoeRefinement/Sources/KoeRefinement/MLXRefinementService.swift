import Foundation
import KoeDomain
import KoeCore
import MLXLLM
import MLXLMCommon
import MLX

/// MLX-based text refinement service for grammar correction and cleanup
/// Uses Apple's mlx-swift-lm for fast on-device inference
public final class MLXRefinementService: TextRefinementService, @unchecked Sendable {
    private var modelContainer: ModelContainer?
    private var currentLoadingTask: Task<Void, Never>?
    private var currentLoadOperationId: UUID?
    private let lock = NSLock()

    private var _isReady = false
    private var _loadingProgress: Double = 0.0
    private var _currentModel: RefinementModel?

    private var progressContinuations: [UUID: AsyncStream<Double>.Continuation] = [:]

    private let logger = KoeLogger.refinement

    /// The system prompt for text refinement
    private let systemPrompt = """
        You are a text refinement assistant. Your task is to clean up transcribed speech.

        Rules:
        - Fix grammar and punctuation errors
        - Remove filler words (um, uh, like, you know, so, basically)
        - Remove false starts and repetitions
        - Keep the speaker's voice, tone, and intent
        - Don't change the meaning or add information
        - Don't over-correct casual speech
        - Return ONLY the refined text, no explanations

        If the input is already clean, return it unchanged.
        """

    public var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isReady
    }

    public var loadingProgress: Double {
        lock.lock()
        defer { lock.unlock() }
        return _loadingProgress
    }

    public var currentModel: RefinementModel? {
        lock.lock()
        defer { lock.unlock() }
        return _currentModel
    }

    public init() {
        // Note: GPU cache limit will be set when model is actually loaded
        // to avoid Metal initialization issues on app startup
    }

    // MARK: - Model Loading

    public func loadModel(_ model: RefinementModel) async throws {
        let operationId = UUID()

        lock.lock()
        currentLoadOperationId = operationId
        lock.unlock()

        // Cancel any existing loading task
        lock.lock()
        if let existingTask = currentLoadingTask {
            existingTask.cancel()
            currentLoadingTask = nil
        }
        lock.unlock()

        // Check if already loaded
        lock.lock()
        let alreadyLoaded = _isReady && _currentModel == model
        lock.unlock()

        if alreadyLoaded {
            lock.lock()
            _loadingProgress = 1.0
            lock.unlock()
            notifyProgress(1.0)
            return
        }

        lock.lock()
        _isReady = false
        _loadingProgress = 0.0
        _currentModel = model
        modelContainer = nil
        lock.unlock()

        notifyProgress(0.01)

        let task = Task {
            await loadModelInternal(model: model, operationId: operationId)
        }

        lock.lock()
        currentLoadingTask = task
        lock.unlock()

        await task.value
    }

    private func loadModelInternal(model: RefinementModel, operationId: UUID) async {
        lock.lock()
        let isCancelled = Task.isCancelled || currentLoadOperationId != operationId
        lock.unlock()
        if isCancelled { return }

        do {
            // Set GPU cache limit on first model load
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

            logger.info("Loading refinement model: \(model.displayName)")

            // Create model configuration
            let modelId = getModelId(for: model)
            let modelConfig = ModelConfiguration(id: modelId)

            // Load model with progress tracking
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: modelConfig
            ) { [weak self] progress in
                guard let self = self else { return }

                self.lock.lock()
                let isCurrentOperation = self.currentLoadOperationId == operationId
                self.lock.unlock()

                guard isCurrentOperation else { return }

                // Map progress to 0.01-0.95 range (leave room for final setup)
                let displayProgress = 0.01 + progress.fractionCompleted * 0.94

                self.lock.lock()
                self._loadingProgress = displayProgress
                self.lock.unlock()
                self.notifyProgress(displayProgress)
            }

            // Check for cancellation after download
            lock.lock()
            let isCancelledAfterDownload = Task.isCancelled || currentLoadOperationId != operationId
            lock.unlock()
            if isCancelledAfterDownload { return }

            lock.lock()
            modelContainer = container
            _isReady = true
            _loadingProgress = 1.0
            lock.unlock()

            notifyProgress(1.0)
            logger.info("Refinement model loaded successfully")

        } catch {
            lock.lock()
            _isReady = false
            _loadingProgress = 0.0
            lock.unlock()

            logger.error("Failed to load refinement model", error: error)
        }
    }

    private func getModelId(for model: RefinementModel) -> String {
        switch model {
        case .qwen25_3b:
            // Using a small, fast model optimized for text tasks
            return "mlx-community/Qwen3-1.7B-4bit"
        }
    }

    public func unloadModel() {
        lock.lock()
        currentLoadingTask?.cancel()
        currentLoadingTask = nil
        currentLoadOperationId = nil
        modelContainer = nil
        _isReady = false
        _loadingProgress = 0.0
        _currentModel = nil
        lock.unlock()

        logger.info("Refinement model unloaded")
    }

    // MARK: - Text Refinement

    public func refine(text: String) async throws -> String {
        lock.lock()
        let container = modelContainer
        lock.unlock()

        guard let container = container else {
            throw RefinementError.modelNotLoaded
        }

        // Skip refinement for very short text
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.count < 3 {
            return trimmedText
        }

        logger.debug("Refining text: \(trimmedText.prefix(50))...")

        do {
            let prompt = "Refine this transcribed speech:\n\n\(trimmedText)"

            // Build messages for the model
            let messages: [[String: String]] = [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ]

            var refinedText = ""

            // Use the container to generate response
            let result = try await container.perform { context in
                let input = try await context.processor.prepare(input: .init(messages: messages))
                return try MLXLMCommon.generate(
                    input: input,
                    parameters: .init(temperature: 0.3, topP: 0.9),
                    context: context
                ) { tokens in
                    // Collect tokens - return .more to continue generation
                    if tokens.count > 500 {
                        return .stop
                    }
                    return .more
                }
            }

            refinedText = result.output.trimmingCharacters(in: .whitespacesAndNewlines)

            // If the model returned something weird or empty, return original
            if refinedText.isEmpty || refinedText.count > trimmedText.count * 3 {
                logger.warning("Refinement produced unexpected output, using original")
                return trimmedText
            }

            logger.debug("Refined result: \(refinedText.prefix(50))...")
            return refinedText

        } catch {
            logger.error("Refinement failed", error: error)
            throw RefinementError.refinementFailed(underlying: error)
        }
    }

    // MARK: - Progress Stream

    public func loadingProgressStream() -> AsyncStream<Double> {
        AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            let id = UUID()
            self.lock.lock()
            self.progressContinuations[id] = continuation
            let progress = self._loadingProgress
            self.lock.unlock()

            continuation.yield(progress)

            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.progressContinuations.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    private func notifyProgress(_ progress: Double) {
        lock.lock()
        let continuations = progressContinuations
        lock.unlock()

        for (_, continuation) in continuations {
            continuation.yield(progress)
        }
    }
}
