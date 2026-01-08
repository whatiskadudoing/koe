import Foundation
import KoeDomain
import KoeCore
import LocalLLMClient
import LocalLLMClientMLX

/// MLX-based text refinement service for grammar correction and cleanup
/// Uses LocalLLMClient with MLX backend for fast on-device inference
public final class MLXRefinementService: TextRefinementService, @unchecked Sendable {
    private var session: LLMSession?
    private var downloadModel: LLMSession.DownloadModel?
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

    public init() {}

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
        session = nil
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
            logger.info("Loading refinement model: \(model.displayName)")

            // Create MLX download model
            // Using Qwen3 1.7B as the default small model
            let modelId = getModelId(for: model)
            let dlModel = LLMSession.DownloadModel.mlx(id: modelId)

            lock.lock()
            downloadModel = dlModel
            lock.unlock()

            // Download model with progress tracking
            try await dlModel.downloadModel { [weak self] progress in
                guard let self = self else { return }

                self.lock.lock()
                let isCurrentOperation = self.currentLoadOperationId == operationId
                self.lock.unlock()

                guard isCurrentOperation else { return }

                let displayProgress = 0.01 + progress * 0.89

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

            // Create session
            lock.lock()
            _loadingProgress = 0.95
            lock.unlock()
            notifyProgress(0.95)

            let newSession = LLMSession(
                model: dlModel,
                messages: [.system(systemPrompt)]
            )

            lock.lock()
            session = newSession
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
        session = nil
        downloadModel = nil
        _isReady = false
        _loadingProgress = 0.0
        _currentModel = nil
        lock.unlock()

        logger.info("Refinement model unloaded")
    }

    // MARK: - Text Refinement

    public func refine(text: String) async throws -> String {
        lock.lock()
        let currentSession = session
        lock.unlock()

        guard let currentSession = currentSession else {
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

            var refinedText = ""

            let stream = currentSession.streamResponse(to: prompt, attachments: [])
            for try await chunk in stream {
                refinedText += chunk
            }

            // Clean up the response
            refinedText = refinedText.trimmingCharacters(in: .whitespacesAndNewlines)

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
