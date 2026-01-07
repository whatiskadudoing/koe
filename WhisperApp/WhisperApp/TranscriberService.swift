import WhisperKit
import SwiftUI

// Import the logger from RecordingService
func transcribeLog(_ message: String) {
    let logPath = "/tmp/whisper_debug.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] [Transcriber] \(message)\n"

    if let data = logMessage.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath) {
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logPath, contents: data, attributes: nil)
        }
    }
}

@MainActor
class TranscriberService: ObservableObject {
    @Published var isLoaded: Bool = false
    @Published var loadingProgress: Double = 0.0
    @Published var currentModelName: String = ""

    private var whisperKit: WhisperKit?
    private var currentLoadingTask: Task<Void, Never>?
    private var currentLoadOperationId: UUID?

    var whisperKitInstance: WhisperKit? {
        return whisperKit
    }

    func loadModel(name: String) async {
        transcribeLog("Starting to load model: \(name)")

        // Generate new operation ID - this invalidates any previous loading operation
        let operationId = UUID()
        currentLoadOperationId = operationId
        transcribeLog("🆔 New load operation: \(operationId)")

        // Cancel any existing loading task
        if let existingTask = currentLoadingTask {
            transcribeLog("⏹️ Cancelling previous model load...")
            existingTask.cancel()
            currentLoadingTask = nil
        }

        guard !isLoaded || currentModelName != name else {
            transcribeLog("Model already loaded or same model requested")
            // Still notify that we're ready
            loadingProgress = 1.0
            NotificationCenter.default.post(name: .modelDownloadProgress, object: Float(1.0))
            NotificationCenter.default.post(name: .modelLoaded, object: nil)
            return
        }

        isLoaded = false
        loadingProgress = 0.0
        currentModelName = name
        NotificationCenter.default.post(name: .modelDownloadProgress, object: Float(0.01))  // Start with 1% instead of 0

        // Create cancellable task for loading
        currentLoadingTask = Task {
            await loadModelInternal(name: name, operationId: operationId)
        }

        // Wait for the loading to complete
        await currentLoadingTask?.value
    }

    private func loadModelInternal(name: String, operationId: UUID) async {
        do {
            // Check for cancellation
            if Task.isCancelled || currentLoadOperationId != operationId {
                transcribeLog("❌ Model load cancelled (operation \(operationId))")
                return
            }

            transcribeLog("Initializing WhisperKit...")

            // Check for bundled model first (in app Resources)
            let bundledModelPath = getBundledModelPath(for: name)
            if let bundledPath = bundledModelPath {
                transcribeLog("📦 Found bundled model at: \(bundledPath)")

                // Show loading progress with animation
                await showLoadingProgress(message: "Loading bundled model...")

                // Initialize WhisperKit with bundled model
                transcribeLog("🔧 Initializing bundled model...")
                whisperKit = try await WhisperKit(
                    modelFolder: bundledPath,
                    verbose: false,
                    logLevel: .error,
                    prewarm: true,
                    load: true
                )

                isLoaded = true
                loadingProgress = 1.0
                NotificationCenter.default.post(name: .modelDownloadProgress, object: Float(1.0))
                transcribeLog("✅ Bundled model \(name) loaded successfully!")
                return
            }

            // Use a persistent location for model storage
            let modelFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("WhisperApp")
                .appendingPathComponent("Models")

            // Create directory if needed
            try? FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)
            transcribeLog("Model folder: \(modelFolder.path)")

            // Check if model already exists locally (cached)
            let cachedModelPath = modelFolder.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(name)")
            let modelExists = FileManager.default.fileExists(atPath: cachedModelPath.path)
            transcribeLog("Model exists in cache: \(modelExists)")

            if modelExists {
                transcribeLog("📦 Loading cached model...")

                // Show loading progress with animation
                await showLoadingProgress(message: "Loading cached model...")

                whisperKit = try await WhisperKit(
                    modelFolder: cachedModelPath.path,
                    verbose: false,
                    logLevel: .error,
                    prewarm: true,
                    load: true
                )

                isLoaded = true
                loadingProgress = 1.0
                NotificationCenter.default.post(name: .modelDownloadProgress, object: Float(1.0))
                transcribeLog("✅ Cached model \(name) loaded successfully!")
                return
            }

            // Check for cancellation before download
            if Task.isCancelled || currentLoadOperationId != operationId {
                transcribeLog("❌ Model load cancelled before download (operation \(operationId))")
                return
            }

            // Download model with progress callback
            transcribeLog("📥 Downloading model \(name)...")
            NotificationCenter.default.post(name: .modelDownloadProgress, object: Float(0.01))  // Show 1% to indicate download started

            let downloadedFolder = try await WhisperKit.download(
                variant: name,
                downloadBase: modelFolder,
                useBackgroundSession: false,
                from: "argmaxinc/whisperkit-coreml",
                progressCallback: { [weak self] progress in
                    // Check if this operation is still current
                    guard self?.currentLoadOperationId == operationId else {
                        transcribeLog("📥 Ignoring progress for cancelled operation")
                        return
                    }

                    let fraction = Float(progress.fractionCompleted)
                    // Ensure progress is always > 0 (1% to 90% range)
                    let displayProgress = 0.01 + fraction * 0.89
                    transcribeLog("📥 Download: \(Int(fraction * 100))% (display: \(Int(displayProgress * 100))%)")
                    Task { @MainActor in
                        // Double-check operation is still current before updating UI
                        guard self?.currentLoadOperationId == operationId else { return }
                        self?.loadingProgress = Double(displayProgress)
                        NotificationCenter.default.post(name: .modelDownloadProgress, object: displayProgress)
                    }
                }
            )

            transcribeLog("📦 Model downloaded to: \(downloadedFolder)")

            // Check for cancellation after download
            if Task.isCancelled || currentLoadOperationId != operationId {
                transcribeLog("❌ Model load cancelled after download (operation \(operationId))")
                return
            }

            // Show animated dots during model initialization (post -1)
            loadingProgress = 0.95
            NotificationCenter.default.post(name: .modelDownloadProgress, object: Float(-1))

            // Initialize WhisperKit with the downloaded model
            transcribeLog("🔧 Initializing model...")
            whisperKit = try await WhisperKit(
                modelFolder: downloadedFolder.path,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true
            )

            isLoaded = true
            loadingProgress = 1.0
            NotificationCenter.default.post(name: .modelDownloadProgress, object: Float(1.0))
            transcribeLog("✅ Model \(name) loaded successfully!")

        } catch {
            transcribeLog("❌ Failed to load model: \(error)")
            isLoaded = false
            loadingProgress = 0.0
        }
    }

    /// Check for bundled model in app Resources
    private func getBundledModelPath(for name: String) -> String? {
        // Check in app bundle Resources/Models
        if let resourcePath = Bundle.main.resourcePath {
            let bundledPath = "\(resourcePath)/Models/openai_whisper-\(name)"
            if FileManager.default.fileExists(atPath: bundledPath) {
                return bundledPath
            }
        }
        return nil
    }

    /// Show loading state (no percentage, just indicates loading)
    private func showLoadingProgress(message: String) async {
        transcribeLog("⏳ \(message)")
        // Post -1 to indicate "loading without percentage"
        NotificationCenter.default.post(name: .modelDownloadProgress, object: Float(-1))
    }

    func transcribe(audioURL: URL, language: String? = nil) async throws -> String {
        guard let whisperKit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        // Configure transcription options based on language setting
        // When language is nil (auto), enable detectLanguage and disable prefill for natural detection
        let isAutoDetect = language == nil

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: isAutoDetect ? nil : language,  // nil lets Whisper detect language
            temperature: 0.0,
            temperatureFallbackCount: 5,
            sampleLength: 224,
            topK: 5,
            usePrefillPrompt: !isAutoDetect,  // Disable prefill for auto detection
            usePrefillCache: !isAutoDetect,
            detectLanguage: isAutoDetect,  // Enable language detection when auto
            skipSpecialTokens: true,
            withoutTimestamps: true,
            suppressBlank: true
        )

        transcribeLog("🌐 Transcribing with language: \(language ?? "auto-detect"), detectLanguage: \(isAutoDetect)")

        // Perform transcription
        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )

        // Log detected language if available
        if isAutoDetect, let firstResult = results.first {
            transcribeLog("🌐 Detected language: \(firstResult.language)")
        }

        // Combine all segments
        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        return text
    }

    func getDecodingOptions(language: String? = nil) -> DecodingOptions {
        return DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperature: 0.0,
            temperatureFallbackCount: 5,
            sampleLength: 224,
            topK: 5,
            usePrefillPrompt: true,
            usePrefillCache: true,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            suppressBlank: true
        )
    }

    func unloadModel() {
        whisperKit = nil
        isLoaded = false
        currentModelName = ""
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model not loaded"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
