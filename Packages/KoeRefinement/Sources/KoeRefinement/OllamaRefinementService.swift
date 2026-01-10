import Foundation
import KoeCore
import KoeDomain

/// Text refinement service using Ollama
public final class OllamaRefinementService: @unchecked Sendable {
    // MARK: - Properties

    private var client: OllamaClient
    private var modelName: String
    private var mode: RefinementMode
    private var customPrompt: String?

    private let lock = NSLock()
    private var _isReady: Bool = false
    private var _isConnected: Bool = false
    private var _availableModels: [OllamaModel] = []

    private let logger = KoeLogger.refinement

    // MARK: - Initialization

    public init(
        endpoint: String = "http://localhost:11434",
        model: String = "mistral:7b-instruct",
        mode: RefinementMode = .cleanup
    ) {
        self.client = OllamaClient(endpointString: endpoint)
        self.modelName = model
        self.mode = mode
    }

    // MARK: - Public Properties

    /// Whether Ollama is connected and model is available
    public var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isReady
    }

    /// Whether connected to Ollama server
    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }

    /// Available models on the Ollama server
    public var availableModels: [OllamaModel] {
        lock.lock()
        defer { lock.unlock() }
        return _availableModels
    }

    /// Current model name
    public var currentModelName: String {
        lock.lock()
        defer { lock.unlock() }
        return modelName
    }

    /// Current refinement mode
    public var currentMode: RefinementMode {
        lock.lock()
        defer { lock.unlock() }
        return mode
    }

    // MARK: - Configuration

    /// Update the Ollama endpoint
    public func setEndpoint(_ endpoint: String) {
        lock.lock()
        client = OllamaClient(endpointString: endpoint)
        _isReady = false
        _isConnected = false
        lock.unlock()
    }

    /// Update the model to use
    public func setModel(_ model: String) {
        lock.lock()
        modelName = model
        lock.unlock()
    }

    /// Update the refinement mode
    public func setMode(_ newMode: RefinementMode) {
        lock.lock()
        mode = newMode
        lock.unlock()
    }

    /// Set custom prompt for custom mode
    public func setCustomPrompt(_ prompt: String?) {
        lock.lock()
        customPrompt = prompt
        lock.unlock()
    }

    // MARK: - Connection

    /// Check connection to Ollama and verify model availability
    public func checkConnection() async -> Bool {
        logger.info("Checking Ollama connection...")

        let connected = await client.checkConnection()

        lock.lock()
        _isConnected = connected
        lock.unlock()

        if connected {
            logger.info("Connected to Ollama")
            await refreshModels()
            return await verifyModelAvailable()
        } else {
            logger.warning("Cannot connect to Ollama")
            lock.lock()
            _isReady = false
            lock.unlock()
            return false
        }
    }

    /// Refresh the list of available models
    public func refreshModels() async {
        do {
            let models = try await client.listModels()
            lock.lock()
            _availableModels = models
            lock.unlock()
            logger.info("Found \(models.count) models")
        } catch {
            logger.error("Failed to list models", error: error)
            lock.lock()
            _availableModels = []
            lock.unlock()
        }
    }

    /// Verify the current model is available
    private func verifyModelAvailable() async -> Bool {
        let available = await client.isModelAvailable(modelName)

        lock.lock()
        _isReady = available
        lock.unlock()

        if available {
            logger.info("Model '\(modelName)' is ready")
        } else {
            logger.warning("Model '\(modelName)' not found")
        }

        return available
    }

    // MARK: - Refinement

    /// Refine text using the configured mode and model
    public func refine(text: String) async throws -> String {
        if !isReady {
            // Try to reconnect
            let connected = await checkConnection()
            if !connected {
                throw OllamaError.connectionRefused
            }
        }

        let currentMode: RefinementMode
        let currentCustomPrompt: String?
        let currentModel: String

        lock.lock()
        currentMode = mode
        currentCustomPrompt = customPrompt
        currentModel = modelName
        lock.unlock()

        // Get the system prompt
        let systemPrompt: String
        if currentMode == .custom {
            systemPrompt = currentCustomPrompt ?? RefinementMode.cleanup.systemPrompt
        } else {
            systemPrompt = currentMode.systemPrompt
        }

        logger.info("Refining text with mode: \(currentMode.displayName)")

        do {
            let refined = try await client.generate(
                model: currentModel,
                prompt: text,
                system: systemPrompt,
                temperature: 0.0,  // Zero temperature for literal text editing
                timeout: 30
            )

            logger.info("Refinement complete: \(text.count) chars → \(refined.count) chars")
            return refined
        } catch {
            logger.error("Refinement failed", error: error)
            throw error
        }
    }

    /// Refine text with a specific mode (one-off)
    public func refine(text: String, mode: RefinementMode, customPrompt: String? = nil) async throws -> String {
        if !isConnected {
            let connected = await checkConnection()
            if !connected {
                throw OllamaError.connectionRefused
            }
        }

        let systemPrompt: String
        if mode == .custom {
            systemPrompt = customPrompt ?? RefinementMode.cleanup.systemPrompt
        } else {
            systemPrompt = mode.systemPrompt
        }

        let currentModel: String
        lock.lock()
        currentModel = modelName
        lock.unlock()

        return try await client.generate(
            model: currentModel,
            prompt: text,
            system: systemPrompt,
            temperature: 0.0,
            timeout: 30
        )
    }
}

// MARK: - Shared Instance

extension OllamaRefinementService {
    /// Shared instance for app-wide use
    public static let shared = OllamaRefinementService()
}
