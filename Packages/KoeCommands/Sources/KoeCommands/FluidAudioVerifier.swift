import Accelerate
import CoreML
import FluidAudio
import Foundation
import os.log

private let logger = Logger(subsystem: "com.koe.voice", category: "FluidAudioVerifier")

/// Advanced speaker verifier using FluidAudio's WeSpeaker neural network embeddings
/// This provides 256-dimensional speaker embeddings for verification
public final class FluidAudioVerifier: @unchecked Sendable {
    // MARK: - Properties

    private let sampleRate: Double
    private var embeddingModel: MLModel?
    private var isModelLoaded = false
    private let lock = NSLock()

    /// Expected audio length: 10 seconds at 16kHz
    private let expectedSamples = 160_000

    /// User's enrolled embedding (256-dimensional from WeSpeaker)
    public var userEmbedding: [Float]? {
        didSet {
            logger.notice("[FluidAudioVerifier] User embedding set: \(self.userEmbedding?.count ?? 0) dimensions")
        }
    }

    /// Verification threshold (0.0 - 1.0)
    public var threshold: Float = 0.7

    // MARK: - Initialization

    public init(sampleRate: Double = 16000) {
        self.sampleRate = sampleRate
        // Don't load model at init - load lazily when needed
    }

    // MARK: - Model Loading

    /// Explicitly load the model (call this when ECAPA-TDNN is enabled)
    public func loadModelIfNeeded() async {
        lock.lock()
        let alreadyLoaded = isModelLoaded
        lock.unlock()

        if !alreadyLoaded {
            await loadModel()
        }
    }

    private func loadModel() async {
        do {
            logger.notice("[FluidAudioVerifier] Loading WeSpeaker embedding model...")
            let models = try await DiarizerModels.download()
            lock.lock()
            embeddingModel = models.embeddingModel
            isModelLoaded = true
            lock.unlock()
            logger.notice("[FluidAudioVerifier] Model loaded successfully (compilation: \(models.compilationDuration, privacy: .public)s)")
        } catch {
            logger.error("[FluidAudioVerifier] Failed to load model: \(error)")
            lock.lock()
            isModelLoaded = false
            lock.unlock()
        }
    }

    /// Check if the model is ready for use
    public var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isModelLoaded && embeddingModel != nil
    }

    // MARK: - Public Methods

    /// Train the verifier with multiple audio samples
    /// Returns the averaged embedding from all samples
    public func train(samples: [[Float]]) async -> [Float] {
        if !isReady {
            logger.warning("[FluidAudioVerifier] Model not ready, waiting...")
            // Wait for model to load
            for _ in 0..<50 {  // 5 seconds max
                try? await Task.sleep(nanoseconds: 100_000_000)
                if isReady { break }
            }
        }

        guard isReady else {
            logger.error("[FluidAudioVerifier] Model failed to load")
            return []
        }

        guard !samples.isEmpty else { return [] }

        logger.notice("[FluidAudioVerifier] Training with \(samples.count) samples")

        var allEmbeddings: [[Float]] = []

        for (index, sample) in samples.enumerated() {
            if let embedding = extractEmbedding(from: sample) {
                allEmbeddings.append(embedding)
                logger.notice("[FluidAudioVerifier] Sample \(index + 1): extracted \(embedding.count)-dim embedding")
            }
        }

        guard !allEmbeddings.isEmpty else {
            logger.error("[FluidAudioVerifier] No embeddings extracted")
            return []
        }

        // Average all embeddings
        let averaged = averageEmbeddings(allEmbeddings)
        logger.notice("[FluidAudioVerifier] Created averaged embedding: \(averaged.count) dimensions")

        return averaged
    }

    /// Verify if audio samples match the enrolled user
    /// Returns (isMatch, confidence)
    public func verify(samples: [Float]) async -> (Bool, Float) {
        guard isReady else {
            logger.warning("[FluidAudioVerifier] Model not ready")
            return (false, 0.0)
        }

        guard let userEmb = userEmbedding, !userEmb.isEmpty else {
            logger.warning("[FluidAudioVerifier] No user embedding enrolled")
            return (false, 0.0)
        }

        guard let testEmbedding = extractEmbedding(from: samples) else {
            logger.warning("[FluidAudioVerifier] Failed to extract test embedding")
            return (false, 0.0)
        }

        let similarity = cosineSimilarity(userEmb, testEmbedding)
        let isMatch = similarity >= threshold

        logger.notice("[FluidAudioVerifier] Verification: similarity=\(similarity), threshold=\(self.threshold), match=\(isMatch)")

        return (isMatch, similarity)
    }

    // MARK: - Private Methods

    /// Extract speaker embedding from audio samples using WeSpeaker model
    private func extractEmbedding(from samples: [Float]) -> [Float]? {
        lock.lock()
        guard let model = embeddingModel else {
            lock.unlock()
            return nil
        }
        lock.unlock()

        do {
            // Prepare audio input (pad/truncate to expected length)
            let waveform = prepareWaveform(samples)

            // Create a uniform mask (all 1s, indicating speech throughout)
            // The model expects mask shape to match frame count
            let maskFrameCount = 589  // Standard frame count for 10s audio
            let mask = [Float](repeating: 1.0, count: maskFrameCount)

            // Create MLMultiArray inputs
            let waveformArray = try createMultiArray(
                from: waveform,
                shape: [3, NSNumber(value: expectedSamples)]
            )

            let maskArray = try createMultiArray(
                from: mask,
                shape: [3, NSNumber(value: maskFrameCount)]
            )

            // Create feature provider
            let features: [String: MLFeatureValue] = [
                "waveform": MLFeatureValue(multiArray: waveformArray),
                "mask": MLFeatureValue(multiArray: maskArray)
            ]
            let provider = try MLDictionaryFeatureProvider(dictionary: features)

            // Run inference
            let output = try model.prediction(from: provider)

            // Extract embedding
            guard let embeddingValue = output.featureValue(for: "embedding"),
                  let embeddingArray = embeddingValue.multiArrayValue else {
                logger.error("[FluidAudioVerifier] No embedding output from model")
                return nil
            }

            // Convert to Float array
            let embedding = extractFloatArray(from: embeddingArray, count: 256)
            return l2Normalize(embedding)

        } catch {
            logger.error("[FluidAudioVerifier] Embedding extraction failed: \(error)")
            return nil
        }
    }

    /// Prepare waveform by padding or truncating to expected length
    private func prepareWaveform(_ samples: [Float]) -> [Float] {
        var waveform = [Float](repeating: 0, count: expectedSamples)

        if samples.count >= expectedSamples {
            // Truncate
            for i in 0..<expectedSamples {
                waveform[i] = samples[i]
            }
        } else {
            // Copy and loop-pad
            for i in 0..<samples.count {
                waveform[i] = samples[i]
            }

            // Loop padding
            guard samples.count > 0 else { return waveform }
            var idx = samples.count
            while idx < expectedSamples {
                let copyCount = min(samples.count, expectedSamples - idx)
                for i in 0..<copyCount {
                    waveform[idx + i] = samples[i]
                }
                idx += copyCount
            }
        }

        return waveform
    }

    /// Create MLMultiArray from Float array
    private func createMultiArray(from data: [Float], shape: [NSNumber]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape, dataType: .float32)
        let ptr = array.dataPointer.assumingMemoryBound(to: Float.self)

        // Clear the array first
        memset(ptr, 0, array.count * MemoryLayout<Float>.size)

        // Copy data to first "batch" slot
        let copyCount = min(data.count, array.count)
        data.withUnsafeBufferPointer { buffer in
            memcpy(ptr, buffer.baseAddress!, copyCount * MemoryLayout<Float>.size)
        }

        return array
    }

    /// Extract Float array from MLMultiArray
    private func extractFloatArray(from array: MLMultiArray, count: Int) -> [Float] {
        let ptr = array.dataPointer.assumingMemoryBound(to: Float.self)
        var result = [Float](repeating: 0, count: count)
        for i in 0..<min(count, array.count) {
            result[i] = ptr[i]
        }
        return result
    }

    /// Average multiple embeddings
    private func averageEmbeddings(_ embeddings: [[Float]]) -> [Float] {
        guard let first = embeddings.first else { return [] }
        let dimensions = first.count

        var averaged = [Float](repeating: 0, count: dimensions)

        for embedding in embeddings {
            guard embedding.count == dimensions else { continue }
            for i in 0..<dimensions {
                averaged[i] += embedding[i]
            }
        }

        let count = Float(embeddings.count)
        for i in 0..<dimensions {
            averaged[i] /= count
        }

        // L2 normalize the result
        return l2Normalize(averaged)
    }

    /// L2 normalize a vector
    private func l2Normalize(_ vector: [Float]) -> [Float] {
        var sumSquares: Float = 0
        vDSP_svesq(vector, 1, &sumSquares, vDSP_Length(vector.count))
        let norm = sqrt(sumSquares)

        guard norm > 0 else { return vector }

        var normalized = [Float](repeating: 0, count: vector.count)
        var normValue = norm
        vDSP_vsdiv(vector, 1, &normValue, &normalized, 1, vDSP_Length(vector.count))

        return normalized
    }

    /// Cosine similarity between two vectors
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }

        var dotProduct: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))

        // If vectors are already normalized, dotProduct is the cosine similarity
        // Otherwise, we need to compute magnitudes
        var aMagSquared: Float = 0
        var bMagSquared: Float = 0
        vDSP_svesq(a, 1, &aMagSquared, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &bMagSquared, vDSP_Length(b.count))

        let denominator = sqrt(aMagSquared * bMagSquared)
        guard denominator > 0 else { return 0.0 }

        return dotProduct / denominator
    }
}
