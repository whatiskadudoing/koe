import AVFoundation
import Foundation
import KoeDomain
import WhisperKit

/// WhisperKit-based transcription service
/// Implements TranscriptionService protocol for local on-device transcription
public final class WhisperKitTranscriber: TranscriptionService, @unchecked Sendable {
    private var whisperKit: WhisperKit?
    private var currentLoadingTask: Task<Void, Never>?
    private var currentLoadOperationId: UUID?
    private let lock = NSLock()

    private var _isReady = false
    private var _loadingProgress: Double = 0.0
    private var _currentModel: KoeModel?
    private var _currentModelName: String = ""

    private var progressContinuations: [UUID: AsyncStream<Double>.Continuation] = [:]

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

    public var currentModel: KoeModel? {
        lock.lock()
        defer { lock.unlock() }
        return _currentModel
    }

    /// Access to underlying WhisperKit instance (for compatibility)
    public var whisperKitInstance: WhisperKit? {
        lock.lock()
        defer { lock.unlock() }
        return whisperKit
    }

    public init() {}

    /// Load a transcription model
    public func loadModel(_ model: KoeModel) async throws {
        let modelName = model.rawValue

        // Generate new operation ID
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
        let alreadyLoaded = _isReady && _currentModelName == modelName
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
        _currentModelName = modelName
        _currentModel = model
        lock.unlock()

        notifyProgress(0.01)

        // Create loading task
        let task = Task {
            await loadModelInternal(name: modelName, operationId: operationId)
        }

        lock.lock()
        currentLoadingTask = task
        lock.unlock()

        await task.value
    }

    private func loadModelInternal(name: String, operationId: UUID) async {
        // Check for cancellation
        lock.lock()
        let isCancelled = Task.isCancelled || currentLoadOperationId != operationId
        lock.unlock()
        if isCancelled { return }

        do {
            // Use persistent location for model storage
            let modelFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Koe")
                .appendingPathComponent("Models")

            try? FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)

            // Check if ANE is already compiled (marker file exists)
            let aneMarkerPath = modelFolder.appendingPathComponent(".ane-compiled-\(name)")
            let isANECompiled = FileManager.default.fileExists(atPath: aneMarkerPath.path)

            // Use GPU+ANE for maximum performance
            // This gives the best speed (~72x real-time on high-end Macs)
            let computeOptions = ModelComputeOptions(
                audioEncoderCompute: .cpuAndGPU,
                textDecoderCompute: .cpuAndNeuralEngine
            )
            print("[WhisperKit] Using GPU+ANE (maximum performance)")

            // Check for bundled model first
            if let bundledPath = getBundledModelPath(for: name) {
                notifyProgress(-1)  // Animated loading

                let kit = try await WhisperKit(
                    modelFolder: bundledPath,
                    computeOptions: computeOptions,
                    verbose: false,
                    logLevel: .error,
                    prewarm: true,
                    load: true
                )

                lock.lock()
                whisperKit = kit
                _isReady = true
                _loadingProgress = 1.0
                lock.unlock()
                notifyProgress(1.0)

                // Schedule background ANE compilation if not yet compiled
                if !isANECompiled {
                    scheduleBackgroundANECompilation(modelPath: bundledPath, markerPath: aneMarkerPath)
                }
                return
            }

            // Check if model exists in cache
            let cachedModelPath = modelFolder.appendingPathComponent(
                "models/argmaxinc/whisperkit-coreml/openai_whisper-\(name)")
            let modelExists = FileManager.default.fileExists(atPath: cachedModelPath.path)

            if modelExists {
                notifyProgress(-1)  // Animated loading

                let kit = try await WhisperKit(
                    modelFolder: cachedModelPath.path,
                    computeOptions: computeOptions,
                    verbose: false,
                    logLevel: .error,
                    prewarm: false,  // Skip prewarm for faster startup
                    load: true
                )

                lock.lock()
                whisperKit = kit
                _isReady = true
                _loadingProgress = 1.0
                lock.unlock()
                notifyProgress(1.0)

                // Schedule background ANE compilation if not yet compiled
                if !isANECompiled {
                    scheduleBackgroundANECompilation(modelPath: cachedModelPath.path, markerPath: aneMarkerPath)
                }
                return
            }

            // Check for cancellation before download
            lock.lock()
            let isCancelledBeforeDownload = Task.isCancelled || currentLoadOperationId != operationId
            lock.unlock()
            if isCancelledBeforeDownload { return }

            // Download model with progress
            notifyProgress(0.01)

            let downloadedFolder = try await WhisperKit.download(
                variant: name,
                downloadBase: modelFolder,
                useBackgroundSession: false,
                from: "argmaxinc/whisperkit-coreml",
                progressCallback: { [weak self] progress in
                    guard let self = self else { return }

                    self.lock.lock()
                    let isCurrentOperation = self.currentLoadOperationId == operationId
                    self.lock.unlock()

                    guard isCurrentOperation else { return }

                    let fraction = Float(progress.fractionCompleted)
                    let displayProgress = Double(0.01 + fraction * 0.89)

                    self.lock.lock()
                    self._loadingProgress = displayProgress
                    self.lock.unlock()
                    self.notifyProgress(Float(displayProgress))
                }
            )

            // Check for cancellation after download
            lock.lock()
            let isCancelledAfterDownload = Task.isCancelled || currentLoadOperationId != operationId
            lock.unlock()
            if isCancelledAfterDownload { return }

            // Initialize WhisperKit
            lock.lock()
            _loadingProgress = 0.95
            lock.unlock()
            notifyProgress(-1)  // Animated loading

            let kit = try await WhisperKit(
                modelFolder: downloadedFolder.path,
                computeOptions: computeOptions,
                verbose: false,
                logLevel: .error,
                prewarm: false,  // Skip prewarm for faster startup
                load: true,
                useBackgroundDownloadSession: false
            )

            lock.lock()
            whisperKit = kit
            _isReady = true
            _loadingProgress = 1.0
            lock.unlock()
            notifyProgress(1.0)

        } catch {
            lock.lock()
            _isReady = false
            _loadingProgress = 0.0
            lock.unlock()
            print("[WhisperKitTranscriber] Model load failed: \(error)")
        }
    }

    private func notifyProgress(_ progress: Float) {
        lock.lock()
        let continuations = progressContinuations
        lock.unlock()

        for (_, continuation) in continuations {
            continuation.yield(Double(progress))
        }
    }

    /// Unload current model
    public func unloadModel() {
        lock.lock()
        currentLoadingTask?.cancel()
        currentLoadingTask = nil
        currentLoadOperationId = nil
        whisperKit = nil
        _isReady = false
        _loadingProgress = 0.0
        _currentModel = nil
        _currentModelName = ""
        lock.unlock()
    }

    /// Check if a model exists on disk (downloaded but not necessarily loaded)
    public func isModelDownloaded(_ model: KoeModel) -> Bool {
        let modelName = model.rawValue

        // Check bundled first
        if getBundledModelPath(for: modelName) != nil {
            return true
        }

        // Check downloaded
        let modelFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Koe")
            .appendingPathComponent("Models")
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelName)")

        return FileManager.default.fileExists(atPath: modelFolder.path)
    }

    /// Download a model without loading it into memory (for background preparation)
    /// Returns the download progress via callback
    public func downloadOnly(_ model: KoeModel, progressCallback: ((Double) -> Void)? = nil) async throws {
        let modelName = model.rawValue

        // Check if already downloaded
        if isModelDownloaded(model) {
            progressCallback?(1.0)
            return
        }

        // Use persistent location for model storage
        let modelFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Koe")
            .appendingPathComponent("Models")

        try? FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)

        // Download model with progress
        _ = try await WhisperKit.download(
            variant: modelName,
            downloadBase: modelFolder,
            useBackgroundSession: true,
            from: "argmaxinc/whisperkit-coreml",
            progressCallback: { progress in
                progressCallback?(progress.fractionCompleted)
            }
        )

        progressCallback?(1.0)
    }

    /// Transcribe audio data
    public func transcribe(audioData: Data, language: Language?) async throws -> Transcription {
        lock.lock()
        let kit = whisperKit
        let model = _currentModel
        lock.unlock()

        guard kit != nil else {
            throw TranscriptionError.modelNotLoaded
        }

        // Write data to temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("koe_\(UUID().uuidString).wav")

        try audioData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let startTime = Date()
        let text = try await transcribeFile(url: tempURL, language: language)
        let duration = Date().timeIntervalSince(startTime)

        return Transcription(
            text: text,
            duration: duration,
            language: language,
            model: model
        )
    }

    /// Transcribe audio from samples (for streaming)
    public func transcribe(samples: [Float], sampleRate: Double, language: Language?) async throws -> String {
        lock.lock()
        let kit = whisperKit
        lock.unlock()

        guard kit != nil else {
            throw TranscriptionError.modelNotLoaded
        }

        // Write samples to temp file
        let tempURL = try createTempWAVFile(samples: samples, sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        return try await transcribeFile(url: tempURL, language: language)
    }

    /// Transcribe audio file
    public func transcribeFile(url: URL, language: Language?) async throws -> String {
        lock.lock()
        let kit = whisperKit
        lock.unlock()

        guard let whisperKit = kit else {
            throw TranscriptionError.modelNotLoaded
        }

        let isAutoDetect = language?.isAuto ?? true
        let langCode = isAutoDetect ? nil : language?.code

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: langCode,
            temperature: 0.0,
            temperatureFallbackCount: 5,
            sampleLength: 224,
            topK: 5,
            usePrefillPrompt: !isAutoDetect,
            usePrefillCache: !isAutoDetect,
            detectLanguage: isAutoDetect,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            suppressBlank: true
        )

        let results = try await whisperKit.transcribe(
            audioPath: url.path,
            decodeOptions: options
        )

        return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Progress stream for model loading
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

    // MARK: - Private Helpers

    private func getBundledModelPath(for name: String) -> String? {
        if let resourcePath = Bundle.main.resourcePath {
            let bundledPath = "\(resourcePath)/Models/openai_whisper-\(name)"
            if FileManager.default.fileExists(atPath: bundledPath) {
                return bundledPath
            }
        }
        return nil
    }

    private func createTempWAVFile(samples: [Float], sampleRate: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("koe_\(UUID().uuidString).wav")

        guard
            let audioFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        else {
            throw TranscriptionError.transcriptionFailed(
                underlying: NSError(
                    domain: "KoeTranscription", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"]))
        }

        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFormat,
                frameCapacity: AVAudioFrameCount(samples.count)
            )
        else {
            throw TranscriptionError.transcriptionFailed(
                underlying: NSError(
                    domain: "KoeTranscription", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"]))
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)

        if let channelData = buffer.floatChannelData?[0] {
            for (index, sample) in samples.enumerated() {
                channelData[index] = sample
            }
        }

        let audioFile = try AVAudioFile(forWriting: url, settings: audioFormat.settings)
        try audioFile.write(from: buffer)

        return url
    }

    /// Schedule background ANE compilation for faster subsequent loads
    /// This runs with low priority and creates a marker file when complete
    private func scheduleBackgroundANECompilation(modelPath: String, markerPath: URL) {
        Task.detached(priority: .background) {
            // Wait a bit for app to finish launching
            try? await Task.sleep(for: .seconds(5))

            print("[WhisperKit] Starting background ANE compilation...")

            let aneComputeOptions = ModelComputeOptions(
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            )

            do {
                // Load with ANE to trigger compilation
                let _ = try await WhisperKit(
                    modelFolder: modelPath,
                    computeOptions: aneComputeOptions,
                    verbose: false,
                    logLevel: .error,
                    prewarm: false,
                    load: true
                )

                // Create marker file to indicate ANE compilation is complete
                try "".write(to: markerPath, atomically: true, encoding: .utf8)

                print("[WhisperKit] Background ANE compilation complete! Next launch will use ANE.")
            } catch {
                print("[WhisperKit] Background ANE compilation failed: \(error)")
            }
        }
    }
}
