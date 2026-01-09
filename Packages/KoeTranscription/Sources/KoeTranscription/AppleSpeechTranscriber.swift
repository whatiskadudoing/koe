import Foundation
import Speech
import KoeDomain

/// Apple Speech-based transcription service using SFSpeechRecognizer
/// Instant startup - no model download required
public final class AppleSpeechTranscriber: TranscriptionService, @unchecked Sendable {
    private let lock = NSLock()
    private var speechRecognizer: SFSpeechRecognizer?
    private var _isReady = false

    public var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isReady
    }

    public var loadingProgress: Double {
        // Apple Speech is instant - always 100%
        return 1.0
    }

    public var currentModel: KoeModel? {
        // Apple Speech doesn't use KoeModel
        return nil
    }

    public init() {
        // Initialize with default locale
        setupRecognizer(locale: Locale.current)
    }

    private func setupRecognizer(locale: Locale) {
        lock.lock()
        defer { lock.unlock() }

        speechRecognizer = SFSpeechRecognizer(locale: locale)
        _isReady = speechRecognizer?.isAvailable ?? false
    }

    // MARK: - TranscriptionService Protocol

    public func loadModel(_ model: KoeModel) async throws {
        // Apple Speech doesn't need to load models - it's always ready
        lock.lock()
        _isReady = speechRecognizer?.isAvailable ?? false
        lock.unlock()
    }

    public func unloadModel() async {
        // Nothing to unload for Apple Speech
    }

    public func transcribe(
        audioData: Data,
        language: Language?
    ) async throws -> Transcription {
        // Update recognizer locale if language specified
        if let lang = language, lang != .auto {
            let locale = Locale(identifier: lang.code)
            setupRecognizer(locale: locale)
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriptionError.modelNotLoaded
        }

        // Write audio data to temporary file (SFSpeechRecognizer requires a URL)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        try audioData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let request = SFSpeechURLRecognitionRequest(url: tempURL)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result = result, result.isFinal else {
                    return
                }

                let text = result.bestTranscription.formattedString
                let transcription = Transcription(
                    id: UUID(),
                    text: text,
                    duration: 0,
                    timestamp: Date(),
                    wasRefined: false
                )
                continuation.resume(returning: transcription)
            }
        }
    }

    public func transcribe(
        samples: [Float],
        sampleRate: Double,
        language: Language?
    ) async throws -> String {
        // Update recognizer locale if language specified
        if let lang = language, lang != .auto {
            let locale = Locale(identifier: lang.code)
            setupRecognizer(locale: locale)
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriptionError.modelNotLoaded
        }

        // Convert Float samples to PCM audio data
        let audioData = samplesToWavData(samples: samples, sampleRate: sampleRate)

        // Write to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        try audioData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let request = SFSpeechURLRecognitionRequest(url: tempURL)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result = result, result.isFinal else {
                    return
                }

                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }

    public func loadingProgressStream() -> AsyncStream<Double> {
        // Apple Speech is instant - emit 1.0 immediately
        AsyncStream { continuation in
            continuation.yield(1.0)
            continuation.finish()
        }
    }

    // MARK: - Audio Conversion

    private func samplesToWavData(samples: [Float], sampleRate: Double) -> Data {
        // Convert Float samples to 16-bit PCM WAV format
        let numSamples = samples.count
        let bytesPerSample = 2
        let dataSize = numSamples * bytesPerSample

        var wavData = Data()

        // WAV Header (44 bytes)
        // RIFF chunk
        wavData.append(contentsOf: "RIFF".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(36 + dataSize).littleEndian) { Array($0) })
        wavData.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wavData.append(contentsOf: "fmt ".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // Subchunk1Size
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // AudioFormat (PCM)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // NumChannels (mono)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) }) // SampleRate
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * Double(bytesPerSample)).littleEndian) { Array($0) }) // ByteRate
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(bytesPerSample).littleEndian) { Array($0) }) // BlockAlign
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) }) // BitsPerSample

        // data chunk
        wavData.append(contentsOf: "data".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

        // Convert samples to 16-bit PCM
        for sample in samples {
            let clampedSample = max(-1.0, min(1.0, sample))
            let int16Sample = Int16(clampedSample * Float(Int16.max))
            wavData.append(contentsOf: withUnsafeBytes(of: int16Sample.littleEndian) { Array($0) })
        }

        return wavData
    }
}
