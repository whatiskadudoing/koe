import Foundation
import KoeDomain
import KoeCore
import LLM

/// AI Provider using LLM.swift (llama.cpp wrapper) for local inference
/// Supports bundled models (Fast tier) and downloaded models (Smart/Best tiers)
public actor LlamaCppProvider: AIProvider {
    // MARK: - Properties

    public nonisolated let id: String
    public nonisolated let name: String

    private var llm: LLM?
    private var _status: AIProviderStatus = .notReady
    private let modelInfo: AIModelInfo
    private let logger = KoeLogger.refinement

    // MARK: - AIProvider Protocol

    public var status: AIProviderStatus {
        _status
    }

    public var isReady: Bool {
        if case .ready = _status { return true }
        return false
    }

    // MARK: - Initialization

    public init(modelInfo: AIModelInfo) {
        self.id = "llama-cpp-\(modelInfo.tier.rawValue)"
        self.name = "LlamaCpp (\(modelInfo.displayName))"
        self.modelInfo = modelInfo
    }

    /// Create provider for a specific tier
    public static func provider(for tier: AITier) -> LlamaCppProvider? {
        guard let modelInfo = AIModelRegistry.model(for: tier) else {
            return nil
        }
        return LlamaCppProvider(modelInfo: modelInfo)
    }

    // MARK: - Model Management

    public func prepare() async throws {
        guard llm == nil else {
            _status = .ready
            return
        }

        _status = .loading
        logger.info("Preparing LlamaCpp provider for \(modelInfo.displayName)")
        print("[LlamaCpp] prepare() called for \(modelInfo.displayName)")

        // Get model path
        print("[LlamaCpp] Getting model path...")
        let modelPath = try await getModelPath()
        print("[LlamaCpp] Model path: \(modelPath)")

        // Load the model using LLM.swift
        print("[LlamaCpp] Loading model...")
        try await loadModel(at: modelPath)

        _status = .ready
        print("[LlamaCpp] Provider ready!")
        logger.info("LlamaCpp provider ready")
    }

    public func shutdown() async {
        llm = nil
        _status = .notReady
        logger.info("LlamaCpp provider shut down")
    }

    // MARK: - Refinement

    public func refine(text: String, mode: RefinementMode, customPrompt: String?) async throws -> String {
        // Get model path for potential reload
        let modelPath = try await getModelPath()

        // Build system prompt
        let systemPrompt = mode == .custom ? (customPrompt ?? mode.systemPrompt) : mode.systemPrompt

        // Reload model with proper chatML template (includes stop sequence)
        // This ensures clean state and proper formatting for each refinement
        llm = nil
        llm = LLM(
            from: URL(fileURLWithPath: modelPath),
            template: .chatML(systemPrompt),
            maxTokenCount: 2048
        )

        guard let model = llm else {
            throw RefinementError.modelNotLoaded
        }

        // Lower temperature for more deterministic output
        model.temp = 0.3

        logger.info("Refining text (\(text.count) chars) with mode: \(mode.displayName)")
        print("[LlamaCpp] System prompt: \(systemPrompt.prefix(100))...")
        print("[LlamaCpp] User text: \(text.prefix(100))...")

        // Format input to match few-shot pattern: "Input: [text]\nOutput:"
        // This helps small models understand they should complete the pattern
        let formattedInput = "Input: \(text)\nOutput:"

        // Use the template's preprocess to format correctly
        let processedInput = model.preprocess(formattedInput, [])
        print("[LlamaCpp] Processed prompt: \(processedInput.prefix(300))...")

        // Generate response using LLM.swift API
        print("[LlamaCpp] Starting completion...")
        let result = await model.getCompletion(from: processedInput)
        print("[LlamaCpp] Raw result: \(result.prefix(300))...")

        // Clean up the result
        var cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove any trailing stop tokens that might have leaked
        if let stopRange = cleaned.range(of: "<|im_end|>") {
            cleaned = String(cleaned[..<stopRange.lowerBound])
        }
        if let stopRange = cleaned.range(of: "<|im_start|>") {
            cleaned = String(cleaned[..<stopRange.lowerBound])
        }

        // Stop at "Input:" if model tries to continue with more examples
        if let inputRange = cleaned.range(of: "\nInput:") {
            cleaned = String(cleaned[..<inputRange.lowerBound])
        }
        if let inputRange = cleaned.range(of: "\n\nInput:") {
            cleaned = String(cleaned[..<inputRange.lowerBound])
        }

        // Remove "Output:" prefix if model included it
        if cleaned.hasPrefix("Output:") {
            cleaned = String(cleaned.dropFirst(7))
        }

        // Remove quotes if model wrapped the output
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count > 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Refinement complete: \(cleaned.count) chars")
        print("[LlamaCpp] Cleaned result: \(cleaned.prefix(200))...")
        return cleaned
    }

    // MARK: - Private Methods

    private func getModelPath() async throws -> String {
        if modelInfo.isBundled {
            // Look in app bundle
            let filename = modelInfo.filename ?? "model.gguf"
            let baseName = filename.replacingOccurrences(of: ".gguf", with: "")

            if let bundlePath = Bundle.main.path(forResource: baseName, ofType: "gguf") {
                return bundlePath
            }

            // Fallback: check in Resources folder
            let resourcePath = Bundle.main.resourcePath ?? ""
            let modelPath = (resourcePath as NSString).appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: modelPath) {
                return modelPath
            }

            throw RefinementError.modelNotFound
        } else {
            // Downloaded model - check in Application Support
            let modelPath = try getDownloadedModelPath()
            if FileManager.default.fileExists(atPath: modelPath) {
                return modelPath
            }

            // Need to download
            _status = .downloading(progress: 0, description: "Starting download...")
            try await downloadModel(to: modelPath)
            return modelPath
        }
    }

    private func getDownloadedModelPath() throws -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent("Koe/Models", isDirectory: true)

        // Create directory if needed
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        return modelsDir.appendingPathComponent(modelInfo.filename ?? "\(modelInfo.name).gguf").path
    }

    private func downloadModel(to path: String) async throws {
        guard let repo = modelInfo.huggingFaceRepo,
              let filename = modelInfo.filename else {
            throw RefinementError.modelNotFound
        }

        let urlString = "https://huggingface.co/\(repo)/resolve/main/\(filename)"
        guard let url = URL(string: urlString) else {
            throw RefinementError.processingFailed("Invalid download URL")
        }

        logger.info("Downloading model from: \(urlString)")
        print("[LlamaCpp] Starting download from: \(urlString)")

        // Simple download without delegate for now
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 600 // 10 minutes for large files
        let session = URLSession(configuration: config)

        _status = .downloading(progress: 0.1, description: "Connecting...")

        let (tempURL, response) = try await session.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RefinementError.downloadFailed("Invalid response")
        }

        print("[LlamaCpp] Download response status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            throw RefinementError.downloadFailed("HTTP \(httpResponse.statusCode)")
        }

        _status = .downloading(progress: 0.9, description: "Saving...")

        // Move to final location
        let destURL = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: tempURL, to: destURL)

        print("[LlamaCpp] Model saved to: \(path)")
        logger.info("Model downloaded to: \(path)")
    }

    private func loadModel(at path: String) async throws {
        logger.info("Loading model from: \(path)")

        // LLM.swift makes this simple
        llm = LLM(from: URL(fileURLWithPath: path))

        guard llm != nil else {
            throw RefinementError.processingFailed("Failed to load model")
        }

        logger.info("Model loaded successfully")
    }
}

// MARK: - Download Delegate

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progressHandler: (Double) -> Void

    init(progressHandler: @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled by async/await
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progressHandler(progress)
        }
    }
}
