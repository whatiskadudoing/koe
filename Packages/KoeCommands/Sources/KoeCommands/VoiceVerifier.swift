import Accelerate
import Foundation

/// Verifies speaker identity using advanced audio features including MFCCs
public final class VoiceVerifier: @unchecked Sendable {
    // MARK: - Properties

    private let lock = NSLock()
    private var _userEmbedding: [Float]?
    private let sampleRate: Double

    // MFCC parameters
    private let numMFCCs = 13
    private let numMelFilters = 26
    private let fftSize = 512
    private let hopSize = 160  // 10ms at 16kHz
    private let frameSize = 400  // 25ms at 16kHz

    /// Default similarity threshold for verification
    public var threshold: Float = 0.6

    /// The user's trained voice embedding
    public var userEmbedding: [Float]? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _userEmbedding
        }
        set {
            lock.lock()
            _userEmbedding = newValue
            lock.unlock()
        }
    }

    // Pre-computed mel filterbank
    private lazy var melFilterbank: [[Float]] = {
        createMelFilterbank()
    }()

    // MARK: - Initialization

    public init(sampleRate: Double = 16000) {
        self.sampleRate = sampleRate
    }

    // MARK: - Public Methods

    /// Train the verifier with multiple audio samples
    public func train(samples: [[Float]]) -> [Float] {
        guard !samples.isEmpty else { return [] }

        // Extract features from each sample
        var allEmbeddings: [[Float]] = []

        for sample in samples {
            let embedding = extractFullEmbedding(from: sample)
            if !embedding.isEmpty {
                allEmbeddings.append(embedding)
            }
        }

        guard !allEmbeddings.isEmpty else { return [] }

        // Average the embeddings
        let averagedEmbedding = averageEmbeddings(allEmbeddings)

        lock.lock()
        _userEmbedding = averagedEmbedding
        lock.unlock()

        return averagedEmbedding
    }

    /// Verify if the audio matches the trained voice
    public func verify(samples: [Float]) -> (isMatch: Bool, confidence: Float) {
        guard let userEmbedding = userEmbedding, !userEmbedding.isEmpty else {
            return (false, 0)
        }

        let inputEmbedding = extractFullEmbedding(from: samples)
        guard !inputEmbedding.isEmpty else {
            return (false, 0)
        }

        // Ensure embeddings are same size (in case of version mismatch)
        let minSize = min(userEmbedding.count, inputEmbedding.count)
        let user = Array(userEmbedding.prefix(minSize))
        let input = Array(inputEmbedding.prefix(minSize))

        let similarity = cosineSimilarity(user, input)

        return (similarity >= threshold, similarity)
    }

    // MARK: - Full Embedding Extraction

    /// Extract a comprehensive embedding combining MFCCs and acoustic features
    private func extractFullEmbedding(from samples: [Float]) -> [Float] {
        guard samples.count >= frameSize else { return [] }

        // 1. Extract MFCCs (averaged over frames)
        let mfccs = extractMFCCs(from: samples)

        // 2. Extract delta MFCCs
        let deltaMFCCs = computeDeltas(mfccs)

        // 3. Extract acoustic features
        let acousticFeatures = extractAcousticFeatures(from: samples)

        // Combine all features into embedding
        var embedding: [Float] = []

        // Add mean and std of each MFCC coefficient across frames
        for i in 0..<numMFCCs {
            let coeffValues = mfccs.map { $0[i] }
            embedding.append(mean(coeffValues))
            embedding.append(standardDeviation(coeffValues))
        }

        // Add mean of delta MFCCs
        for i in 0..<numMFCCs {
            let deltaValues = deltaMFCCs.map { $0[i] }
            embedding.append(mean(deltaValues))
        }

        // Add acoustic features
        embedding.append(contentsOf: acousticFeatures)

        // Normalize embedding
        return normalizeEmbedding(embedding)
    }

    // MARK: - MFCC Extraction

    /// Extract MFCCs from audio samples
    private func extractMFCCs(from samples: [Float]) -> [[Float]] {
        var mfccFrames: [[Float]] = []

        // Pre-emphasis filter
        var emphasized = preEmphasis(samples)

        // Process frames
        var frameStart = 0
        while frameStart + frameSize <= emphasized.count {
            let frame = Array(emphasized[frameStart..<frameStart + frameSize])

            // Apply Hamming window
            let windowedFrame = applyHammingWindow(frame)

            // Compute power spectrum
            let powerSpectrum = computePowerSpectrum(windowedFrame)

            // Apply mel filterbank
            let melEnergies = applyMelFilterbank(powerSpectrum)

            // Take log
            let logMelEnergies = melEnergies.map { log(max($0, 1e-10)) }

            // Apply DCT to get MFCCs
            let mfcc = applyDCT(logMelEnergies)

            mfccFrames.append(Array(mfcc.prefix(numMFCCs)))

            frameStart += hopSize
        }

        return mfccFrames
    }

    /// Pre-emphasis filter to boost high frequencies
    private func preEmphasis(_ samples: [Float], coefficient: Float = 0.97) -> [Float] {
        guard samples.count > 1 else { return samples }

        var result = [Float](repeating: 0, count: samples.count)
        result[0] = samples[0]

        for i in 1..<samples.count {
            result[i] = samples[i] - coefficient * samples[i - 1]
        }

        return result
    }

    /// Apply Hamming window to frame
    private func applyHammingWindow(_ frame: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: frame.count)
        let n = Float(frame.count)

        for i in 0..<frame.count {
            let window = 0.54 - 0.46 * cos(2 * Float.pi * Float(i) / (n - 1))
            result[i] = frame[i] * window
        }

        return result
    }

    /// Compute power spectrum using FFT
    private func computePowerSpectrum(_ frame: [Float]) -> [Float] {
        // Pad to FFT size
        var paddedFrame = frame
        if paddedFrame.count < fftSize {
            paddedFrame.append(contentsOf: [Float](repeating: 0, count: fftSize - paddedFrame.count))
        }

        // Use vDSP for FFT
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return [Float](repeating: 0, count: fftSize / 2 + 1)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Prepare split complex arrays
        var realp = [Float](repeating: 0, count: fftSize / 2)
        var imagp = [Float](repeating: 0, count: fftSize / 2)

        // Convert to split complex
        paddedFrame.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                var splitComplex = DSPSplitComplex(realp: &realp, imagp: &imagp)
                vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
            }
        }

        // Perform FFT
        var splitComplex = DSPSplitComplex(realp: &realp, imagp: &imagp)
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

        // Compute power spectrum
        var powerSpectrum = [Float](repeating: 0, count: fftSize / 2 + 1)

        // DC component
        powerSpectrum[0] = realp[0] * realp[0]

        // Other components
        for i in 1..<fftSize / 2 {
            powerSpectrum[i] = realp[i] * realp[i] + imagp[i] * imagp[i]
        }

        // Nyquist component
        powerSpectrum[fftSize / 2] = imagp[0] * imagp[0]

        return powerSpectrum
    }

    /// Create mel filterbank
    private func createMelFilterbank() -> [[Float]] {
        let lowFreq: Float = 0
        let highFreq = Float(sampleRate / 2)

        // Convert to mel scale
        let lowMel = hzToMel(lowFreq)
        let highMel = hzToMel(highFreq)

        // Create equally spaced points in mel scale
        let melPoints = (0...numMelFilters + 1).map { i in
            lowMel + Float(i) * (highMel - lowMel) / Float(numMelFilters + 1)
        }

        // Convert back to Hz
        let hzPoints = melPoints.map { melToHz($0) }

        // Convert to FFT bin numbers
        let binPoints = hzPoints.map { Int(floor(($0 / Float(sampleRate)) * Float(fftSize + 1))) }

        // Create filterbank
        var filterbank: [[Float]] = []

        for m in 1...numMelFilters {
            var filter = [Float](repeating: 0, count: fftSize / 2 + 1)

            for k in binPoints[m - 1]..<binPoints[m] {
                if k < filter.count {
                    filter[k] = Float(k - binPoints[m - 1]) / Float(binPoints[m] - binPoints[m - 1])
                }
            }

            for k in binPoints[m]..<binPoints[m + 1] {
                if k < filter.count {
                    filter[k] = Float(binPoints[m + 1] - k) / Float(binPoints[m + 1] - binPoints[m])
                }
            }

            filterbank.append(filter)
        }

        return filterbank
    }

    /// Apply mel filterbank to power spectrum
    private func applyMelFilterbank(_ powerSpectrum: [Float]) -> [Float] {
        var melEnergies = [Float](repeating: 0, count: numMelFilters)

        for (i, filter) in melFilterbank.enumerated() {
            var energy: Float = 0
            let minLen = min(powerSpectrum.count, filter.count)
            for j in 0..<minLen {
                energy += powerSpectrum[j] * filter[j]
            }
            melEnergies[i] = energy
        }

        return melEnergies
    }

    /// Apply DCT to get MFCCs from log mel energies
    private func applyDCT(_ logMelEnergies: [Float]) -> [Float] {
        var mfccs = [Float](repeating: 0, count: numMFCCs)
        let n = Float(logMelEnergies.count)

        for i in 0..<numMFCCs {
            var sum: Float = 0
            for j in 0..<logMelEnergies.count {
                sum += logMelEnergies[j] * cos(Float.pi * Float(i) * (Float(j) + 0.5) / n)
            }
            mfccs[i] = sum
        }

        return mfccs
    }

    /// Compute delta (first derivative) of MFCCs
    private func computeDeltas(_ mfccs: [[Float]], windowSize: Int = 2) -> [[Float]] {
        guard mfccs.count > 2 * windowSize else { return mfccs }

        var deltas: [[Float]] = []

        for t in windowSize..<mfccs.count - windowSize {
            var delta = [Float](repeating: 0, count: numMFCCs)
            var denominator: Float = 0

            for n in 1...windowSize {
                for i in 0..<numMFCCs {
                    delta[i] += Float(n) * (mfccs[t + n][i] - mfccs[t - n][i])
                }
                denominator += Float(n * n)
            }

            for i in 0..<numMFCCs {
                delta[i] /= (2 * denominator)
            }

            deltas.append(delta)
        }

        return deltas
    }

    // MARK: - Acoustic Features

    /// Extract additional acoustic features
    private func extractAcousticFeatures(from samples: [Float]) -> [Float] {
        var features: [Float] = []

        // Energy features
        let (avgEnergy, energyVar) = calculateEnergy(samples)
        features.append(avgEnergy)
        features.append(sqrt(energyVar))

        // Zero crossing rate
        let zcr = calculateZeroCrossingRate(samples)
        features.append(zcr)

        // Pitch features
        let (avgPitch, pitchVar) = estimatePitch(samples)
        features.append(avgPitch / 500.0)  // Normalize
        features.append(sqrt(pitchVar) / 100.0)

        // Spectral features
        let (centroid, rolloff) = calculateSpectralFeatures(samples)
        features.append(centroid / 8000.0)
        features.append(rolloff / 8000.0)

        // Speaking rate
        let rate = estimateSpeakingRate(samples)
        features.append(rate / 10.0)

        return features
    }

    private func calculateEnergy(_ samples: [Float]) -> (average: Float, variance: Float) {
        guard !samples.isEmpty else { return (0, 0) }

        let chunkSize = Int(sampleRate * 0.025)
        var energies: [Float] = []

        for i in stride(from: 0, to: samples.count - chunkSize, by: chunkSize / 2) {
            let chunk = Array(samples[i..<min(i + chunkSize, samples.count)])
            var sumSquares: Float = 0
            vDSP_svesq(chunk, 1, &sumSquares, vDSP_Length(chunk.count))
            let rms = sqrt(sumSquares / Float(chunk.count))
            energies.append(rms)
        }

        guard !energies.isEmpty else { return (0, 0) }

        let avg = mean(energies)
        let variance = energies.reduce(0) { $0 + ($1 - avg) * ($1 - avg) } / Float(energies.count)

        return (avg, variance)
    }

    private func calculateZeroCrossingRate(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }

        var crossings = 0
        for i in 1..<samples.count {
            if (samples[i] >= 0 && samples[i - 1] < 0) ||
                (samples[i] < 0 && samples[i - 1] >= 0) {
                crossings += 1
            }
        }

        return Float(crossings) / Float(samples.count)
    }

    private func estimatePitch(_ samples: [Float]) -> (average: Float, variance: Float) {
        let frameSize = Int(sampleRate * 0.03)
        let minPeriod = Int(sampleRate / 500)
        let maxPeriod = Int(sampleRate / 50)

        var pitches: [Float] = []

        for i in stride(from: 0, to: samples.count - frameSize, by: frameSize / 2) {
            let frame = Array(samples[i..<i + frameSize])
            if let pitch = autocorrelationPitch(frame, minPeriod: minPeriod, maxPeriod: maxPeriod) {
                pitches.append(pitch)
            }
        }

        guard !pitches.isEmpty else { return (150, 0) }

        let avg = mean(pitches)
        let variance = pitches.reduce(0) { $0 + ($1 - avg) * ($1 - avg) } / Float(pitches.count)

        return (avg, variance)
    }

    private func autocorrelationPitch(_ frame: [Float], minPeriod: Int, maxPeriod: Int) -> Float? {
        let n = frame.count
        guard maxPeriod < n else { return nil }

        var maxCorrelation: Float = 0
        var bestPeriod = minPeriod

        for lag in minPeriod..<min(maxPeriod, n) {
            var correlation: Float = 0
            for i in 0..<(n - lag) {
                correlation += frame[i] * frame[i + lag]
            }

            if correlation > maxCorrelation {
                maxCorrelation = correlation
                bestPeriod = lag
            }
        }

        return Float(sampleRate) / Float(bestPeriod)
    }

    private func calculateSpectralFeatures(_ samples: [Float]) -> (centroid: Float, rolloff: Float) {
        guard samples.count >= fftSize else {
            return (2000, 4000)
        }

        let powerSpectrum = computePowerSpectrum(Array(samples.prefix(fftSize)))

        var weightedSum: Float = 0
        var totalMagnitude: Float = 0

        for k in 0..<powerSpectrum.count {
            let frequency = Float(k) * Float(sampleRate) / Float(fftSize)
            let magnitude = sqrt(powerSpectrum[k])
            weightedSum += frequency * magnitude
            totalMagnitude += magnitude
        }

        let centroid = totalMagnitude > 0 ? weightedSum / totalMagnitude : 2000

        let threshold = totalMagnitude * 0.85
        var cumulative: Float = 0
        var rolloff: Float = 4000

        for k in 0..<powerSpectrum.count {
            cumulative += sqrt(powerSpectrum[k])
            if cumulative >= threshold {
                rolloff = Float(k) * Float(sampleRate) / Float(fftSize)
                break
            }
        }

        return (centroid, rolloff)
    }

    private func estimateSpeakingRate(_ samples: [Float]) -> Float {
        let frameSize = Int(sampleRate * 0.02)
        var energyEnvelope: [Float] = []

        for i in stride(from: 0, to: samples.count - frameSize, by: frameSize) {
            let chunk = Array(samples[i..<i + frameSize])
            var sumSquares: Float = 0
            vDSP_svesq(chunk, 1, &sumSquares, vDSP_Length(chunk.count))
            energyEnvelope.append(sqrt(sumSquares / Float(chunk.count)))
        }

        var peaks = 0
        let threshold: Float = 0.05

        for i in 1..<energyEnvelope.count - 1 {
            if energyEnvelope[i] > threshold
                && energyEnvelope[i] > energyEnvelope[i - 1]
                && energyEnvelope[i] > energyEnvelope[i + 1] {
                peaks += 1
            }
        }

        let duration = Double(samples.count) / sampleRate
        return duration > 0 ? Float(Double(peaks) / duration) : 3.0
    }

    // MARK: - Utility Functions

    private func hzToMel(_ hz: Float) -> Float {
        return 2595 * log10(1 + hz / 700)
    }

    private func melToHz(_ mel: Float) -> Float {
        return 700 * (pow(10, mel / 2595) - 1)
    }

    private func mean(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }

    private func standardDeviation(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        let avg = mean(values)
        let variance = values.reduce(0) { $0 + ($1 - avg) * ($1 - avg) } / Float(values.count)
        return sqrt(variance)
    }

    private func normalizeEmbedding(_ embedding: [Float]) -> [Float] {
        guard !embedding.isEmpty else { return [] }

        // L2 normalization
        var norm: Float = 0
        vDSP_svesq(embedding, 1, &norm, vDSP_Length(embedding.count))
        norm = sqrt(norm)

        guard norm > 0 else { return embedding }

        return embedding.map { $0 / norm }
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }

    private func averageEmbeddings(_ embeddings: [[Float]]) -> [Float] {
        guard !embeddings.isEmpty else { return [] }
        guard let first = embeddings.first else { return [] }

        var result = [Float](repeating: 0, count: first.count)

        for embedding in embeddings {
            for i in 0..<min(result.count, embedding.count) {
                result[i] += embedding[i]
            }
        }

        let count = Float(embeddings.count)
        for i in 0..<result.count {
            result[i] /= count
        }

        return result
    }

    // MARK: - Legacy Public Methods (for compatibility)

    /// Extract voice features from audio samples (legacy interface)
    public func extractFeatures(from samples: [Float]) -> VoiceFeatures {
        guard !samples.isEmpty else {
            return VoiceFeatures(
                averagePitch: 0, pitchVariance: 0,
                averageEnergy: 0, energyVariance: 0,
                zeroCrossingRate: 0, spectralCentroid: 0,
                spectralRolloff: 0, speakingRate: 0
            )
        }

        let (avgEnergy, energyVar) = calculateEnergy(samples)
        let zcr = calculateZeroCrossingRate(samples)
        let (avgPitch, pitchVar) = estimatePitch(samples)
        let (centroid, rolloff) = calculateSpectralFeatures(samples)
        let speakingRate = estimateSpeakingRate(samples)

        return VoiceFeatures(
            averagePitch: avgPitch,
            pitchVariance: pitchVar,
            averageEnergy: avgEnergy,
            energyVariance: energyVar,
            zeroCrossingRate: zcr,
            spectralCentroid: centroid,
            spectralRolloff: rolloff,
            speakingRate: speakingRate
        )
    }
}
