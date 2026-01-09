import Foundation
import AVFoundation
import WhisperMetal
import KoeDomain

/// whisper.cpp Metal-based transcription service
/// Uses GPU (Metal) instead of ANE - instant startup, no 4-minute CoreML compilation
public final class WhisperMetalTranscriber: TranscriptionService, @unchecked Sendable {
    private var whisper: Whisper?
    private var currentLoadingTask: Task<Void, Never>?
    internal var currentLoadOperationId: UUID?
    internal let lock = NSLock()

    private var _isReady = false
    internal var _loadingProgress: Double = 0.0
    private var _currentModel: KoeModel?
    private var _currentModelName: String = ""

    private var progressContinuations: [UUID: AsyncStream<Double>.Continuation] = [:]

    // Model download base URL (ggerganov's ggml models)
    private static let modelBaseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

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
            await loadModelInternal(model: model, operationId: operationId)
        }

        lock.lock()
        currentLoadingTask = task
        lock.unlock()

        await task.value
    }

    private func loadModelInternal(model: KoeModel, operationId: UUID) async {
        // Check for cancellation
        lock.lock()
        let isCancelled = Task.isCancelled || currentLoadOperationId != operationId
        lock.unlock()
        if isCancelled { return }

        do {
            // Get model file path
            let modelPath = try await ensureModelDownloaded(model: model, operationId: operationId)

            // Check for cancellation after download
            lock.lock()
            let isCancelledAfterDownload = Task.isCancelled || currentLoadOperationId != operationId
            lock.unlock()
            if isCancelledAfterDownload { return }

            // Load the model - this is instant with Metal, no compilation needed!
            lock.lock()
            _loadingProgress = 0.95
            lock.unlock()
            notifyProgress(0.95)

            let whisperInstance = Whisper(fromFileURL: modelPath, useGPU: true)

            lock.lock()
            whisper = whisperInstance
            _isReady = true
            _loadingProgress = 1.0
            lock.unlock()
            notifyProgress(1.0)

        } catch {
            lock.lock()
            _isReady = false
            _loadingProgress = 0.0
            lock.unlock()
            print("[WhisperMetalTranscriber] Model load failed: \(error)")
        }
    }

    private func ensureModelDownloaded(model: KoeModel, operationId: UUID) async throws -> URL {
        let modelFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Koe")
            .appendingPathComponent("Models")
            .appendingPathComponent("ggml")

        try? FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)

        let ggmlFileName = model.ggmlFileName
        let modelPath = modelFolder.appendingPathComponent(ggmlFileName)

        // Check if model exists
        if FileManager.default.fileExists(atPath: modelPath.path) {
            notifyProgress(0.9)
            return modelPath
        }

        // Download model
        let downloadURL = URL(string: "\(Self.modelBaseURL)/\(ggmlFileName)")!

        notifyProgress(0.05)

        // Download with progress using URLSessionDownloadTask
        let tempURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let sessionConfig = URLSessionConfiguration.default
            let delegate = ProgressTrackingDelegate(
                operationId: operationId,
                transcriber: self,
                continuation: continuation
            )
            let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: downloadURL)
            task.resume()
        }

        // Move to final location
        try FileManager.default.moveItem(at: tempURL, to: modelPath)

        notifyProgress(0.9)
        return modelPath
    }

    internal func notifyProgress(_ progress: Float) {
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
        whisper = nil
        _isReady = false
        _loadingProgress = 0.0
        _currentModel = nil
        _currentModelName = ""
        lock.unlock()
    }

    /// Transcribe audio data
    public func transcribe(audioData: Data, language: Language?) async throws -> Transcription {
        lock.lock()
        let whisperInstance = whisper
        let model = _currentModel
        lock.unlock()

        guard whisperInstance != nil else {
            throw TranscriptionError.modelNotLoaded
        }

        // Convert audio data to samples
        let samples = try extractSamples(from: audioData)

        let startTime = Date()
        let text = try await transcribe(samples: samples, sampleRate: 16000, language: language)
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
        let whisperInstance = whisper
        lock.unlock()

        guard let whisper = whisperInstance else {
            throw TranscriptionError.modelNotLoaded
        }

        // Resample to 16kHz if needed
        let resampledSamples: [Float]
        if abs(sampleRate - 16000) > 1 {
            resampledSamples = resample(samples: samples, from: sampleRate, to: 16000)
        } else {
            resampledSamples = samples
        }

        // Configure parameters
        let params = WhisperParams(strategy: .greedy)

        // Set language if specified
        if let language = language, !language.isAuto, let whisperLang = WhisperLanguage(rawValue: language.code) {
            params.language = whisperLang
        } else {
            params.language = .auto
        }

        // Run transcription
        let segments = try await whisper.transcribe(audioFrames: resampledSamples)

        return segments.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// Transcribe audio file
    public func transcribeFile(url: URL, language: Language?) async throws -> String {
        lock.lock()
        let whisperInstance = whisper
        lock.unlock()

        guard whisperInstance != nil else {
            throw TranscriptionError.modelNotLoaded
        }

        // Read audio file and extract samples
        let samples = try extractSamplesFromFile(url: url)

        return try await transcribe(samples: samples, sampleRate: 16000, language: language)
    }

    // MARK: - Private Helpers

    private func extractSamples(from audioData: Data) throws -> [Float] {
        // Write to temp file and read back as samples
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("koe_\(UUID().uuidString).wav")

        try audioData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let audioFile = try AVAudioFile(forReading: tempURL)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

        let frameCount = AVAudioFrameCount(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw TranscriptionError.transcriptionFailed(underlying: NSError(domain: "WhisperMetal", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"]))
        }

        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData?[0] else {
            throw TranscriptionError.transcriptionFailed(underlying: NSError(domain: "WhisperMetal", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to get channel data"]))
        }

        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
    }

    private func extractSamplesFromFile(url: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)

        // Get the file's processing format and convert to 16kHz mono
        let processingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

        // Read at native sample rate first
        let nativeFormat = audioFile.processingFormat
        let nativeFrameCount = AVAudioFrameCount(audioFile.length)
        guard let nativeBuffer = AVAudioPCMBuffer(pcmFormat: nativeFormat, frameCapacity: nativeFrameCount) else {
            throw TranscriptionError.transcriptionFailed(underlying: NSError(domain: "WhisperMetal", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create native buffer"]))
        }

        try audioFile.read(into: nativeBuffer)

        // Convert to mono 16kHz
        let converter = AVAudioConverter(from: nativeFormat, to: processingFormat)!
        let outputFrameCapacity = AVAudioFrameCount(ceil(Double(nativeFrameCount) * 16000.0 / nativeFormat.sampleRate))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: outputFrameCapacity) else {
            throw TranscriptionError.transcriptionFailed(underlying: NSError(domain: "WhisperMetal", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"]))
        }

        var conversionError: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return nativeBuffer
        }

        converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)

        if let error = conversionError {
            throw TranscriptionError.transcriptionFailed(underlying: error)
        }

        guard let channelData = outputBuffer.floatChannelData?[0] else {
            throw TranscriptionError.transcriptionFailed(underlying: NSError(domain: "WhisperMetal", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to get channel data"]))
        }

        return Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
    }

    private func resample(samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) -> [Float] {
        let ratio = targetSampleRate / sourceSampleRate
        let outputLength = Int(Double(samples.count) * ratio)
        var output = [Float](repeating: 0, count: outputLength)

        for i in 0..<outputLength {
            let srcIndex = Double(i) / ratio
            let srcIndexInt = Int(srcIndex)
            let frac = Float(srcIndex - Double(srcIndexInt))

            if srcIndexInt + 1 < samples.count {
                output[i] = samples[srcIndexInt] * (1 - frac) + samples[srcIndexInt + 1] * frac
            } else if srcIndexInt < samples.count {
                output[i] = samples[srcIndexInt]
            }
        }

        return output
    }
}

// MARK: - Download Progress Delegate

private class ProgressTrackingDelegate: NSObject, URLSessionDownloadDelegate {
    let operationId: UUID
    weak var transcriber: WhisperMetalTranscriber?
    var continuation: CheckedContinuation<URL, Error>?
    var tempFileURL: URL?

    init(operationId: UUID, transcriber: WhisperMetalTranscriber, continuation: CheckedContinuation<URL, Error>) {
        self.operationId = operationId
        self.transcriber = transcriber
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let transcriber = transcriber else { return }

        transcriber.lock.lock()
        let isCurrentOperation = transcriber.currentLoadOperationId == operationId
        transcriber.lock.unlock()

        guard isCurrentOperation else { return }

        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            // Map download progress to 0.05 - 0.85
            let displayProgress = 0.05 + progress * 0.8

            transcriber.lock.lock()
            transcriber._loadingProgress = displayProgress
            transcriber.lock.unlock()
            transcriber.notifyProgress(Float(displayProgress))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Copy to temp location before the system deletes it
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.copyItem(at: location, to: tempURL)
            tempFileURL = tempURL
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation?.resume(throwing: error)
        } else if let tempURL = tempFileURL {
            continuation?.resume(returning: tempURL)
        } else {
            continuation?.resume(throwing: NSError(domain: "WhisperMetal", code: 2, userInfo: [NSLocalizedDescriptionKey: "Download completed but no file found"]))
        }
        continuation = nil
    }
}

// MARK: - KoeModel Extension

private extension KoeModel {
    /// Get the ggml model filename for this model
    var ggmlFileName: String {
        // Map KoeModel to ggml model files
        // These models use Metal for GPU acceleration - no CoreML compilation needed
        switch self {
        case .fast:
            // Fast model - use turbo for speed
            return "ggml-large-v3-turbo.bin"
        case .balanced:
            // Balanced model - use large-v3-turbo
            return "ggml-large-v3-turbo.bin"
        case .best:
            // Best quality - use large-v3 (full, not turbo)
            return "ggml-large-v3.bin"
        }
    }
}
