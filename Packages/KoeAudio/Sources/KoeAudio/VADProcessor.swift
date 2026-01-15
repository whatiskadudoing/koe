import Accelerate
import Foundation

/// Result of VAD (Voice Activity Detection) analysis
public enum VADResult: Sendable, Equatable {
    /// Speech is currently detected
    case speaking

    /// Silence detected, with the time it started
    case silence(startedAt: Date)

    /// Speech segment has ended (silence duration exceeded threshold)
    case speechEnded(startSampleIndex: Int, endSampleIndex: Int)
}

/// Voice Activity Detection processor
/// Detects speech segments and silence periods in audio using multi-feature analysis
public struct VADProcessor: Sendable {
    /// VAD score threshold (0-1) - audio with score below this is considered silence
    public let silenceThreshold: Float

    /// Duration of silence required to trigger speech end (seconds)
    public let silenceDuration: TimeInterval

    /// Minimum speech duration to consider valid (seconds)
    public let minSpeechDuration: TimeInterval

    /// Sample rate for duration calculations
    public let sampleRate: Double

    /// FFT size for spectral analysis
    private let fftSize: Int = 512

    public init(
        silenceThreshold: Float = 0.15,  // Score threshold (0-1), not RMS
        silenceDuration: TimeInterval = 1.2,
        minSpeechDuration: TimeInterval = 0.5,
        sampleRate: Double = 16000
    ) {
        self.silenceThreshold = silenceThreshold
        self.silenceDuration = silenceDuration
        self.minSpeechDuration = minSpeechDuration
        self.sampleRate = sampleRate
    }

    /// Analyze audio samples for voice activity
    /// - Parameters:
    ///   - samples: Recent audio samples to analyze
    ///   - isSpeaking: Current speaking state
    ///   - speechStartIndex: Sample index where current speech started
    ///   - silenceStartTime: When silence started (nil if speaking)
    ///   - totalSamples: Total samples recorded so far
    /// - Returns: VAD result indicating speech state
    public func analyze(
        samples: [Float],
        isSpeaking: Bool,
        speechStartIndex: Int,
        silenceStartTime: Date?,
        totalSamples: Int
    ) -> VADResult {
        guard !samples.isEmpty else {
            return isSpeaking ? .speaking : .silence(startedAt: silenceStartTime ?? Date())
        }

        // Use multi-feature VAD score
        let vadScore = detectVoiceActivity(in: samples)
        let isSpeakingNow = vadScore >= silenceThreshold

        if isSpeakingNow {
            // Speech detected
            return .speaking
        } else {
            // Silence detected
            if isSpeaking {
                // Was speaking, now silent
                let silenceStart = silenceStartTime ?? Date()

                if let startTime = silenceStartTime,
                    Date().timeIntervalSince(startTime) >= silenceDuration
                {
                    // Silence has been long enough - check speech duration
                    let speechSamples = totalSamples - speechStartIndex
                    let speechDuration = Double(speechSamples) / sampleRate

                    if speechDuration >= minSpeechDuration {
                        // Valid speech segment ended
                        return .speechEnded(
                            startSampleIndex: speechStartIndex,
                            endSampleIndex: totalSamples
                        )
                    }
                }

                return .silence(startedAt: silenceStart)
            } else {
                return .silence(startedAt: silenceStartTime ?? Date())
            }
        }
    }

    /// Check if samples contain speech using multi-feature VAD
    public func containsSpeech(_ samples: [Float]) -> Bool {
        let score = detectVoiceActivity(in: samples)
        return score >= silenceThreshold
    }

    /// Detect voice activity using multiple features
    /// Returns a score between 0 and 1, where higher means more likely to be speech
    public func detectVoiceActivity(in samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }

        // Calculate RMS energy
        var sumSquares: Float = 0
        vDSP_svesq(samples, 1, &sumSquares, vDSP_Length(samples.count))
        let rms = sqrt(sumSquares / Float(samples.count))

        // Calculate zero crossing rate
        let zcr = calculateZeroCrossingRate(samples)

        // Energy score (normalized, speech typically has RMS > 0.01)
        // Using 0.03 as normalizer for better sensitivity
        let energyScore = min(rms / 0.03, 1.0)

        // ZCR score (speech typically has ZCR in 0.02-0.15 range)
        // Optimal around 0.08 for voiced speech
        let optimalZCR: Float = 0.08
        let zcrDeviation = abs(zcr - optimalZCR)
        let zcrScore = max(0, 1.0 - zcrDeviation / 0.1)

        // Spectral flatness score (lower = more tonal/speech-like)
        let spectralScore = calculateSpectralFlatnessScore(samples)

        // Combined VAD score
        // Weight energy higher since it's the most reliable indicator
        let vadScore = energyScore * 0.5 + zcrScore * 0.25 + spectralScore * 0.25

        return vadScore
    }

    /// Get the raw RMS value for debugging
    public func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sumSquares: Float = 0
        vDSP_svesq(samples, 1, &sumSquares, vDSP_Length(samples.count))
        return sqrt(sumSquares / Float(samples.count))
    }

    private func calculateZeroCrossingRate(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }

        var crossings = 0
        for i in 1..<samples.count {
            if (samples[i] >= 0 && samples[i - 1] < 0) || (samples[i] < 0 && samples[i - 1] >= 0) {
                crossings += 1
            }
        }

        return Float(crossings) / Float(samples.count)
    }

    /// Calculate spectral flatness score (1 = tonal/speech, 0 = noise)
    private func calculateSpectralFlatnessScore(_ samples: [Float]) -> Float {
        guard samples.count >= fftSize else { return 0.5 }

        let powerSpectrum = computePowerSpectrum(Array(samples.prefix(fftSize)))

        // Geometric mean / Arithmetic mean
        var logSum: Float = 0
        var linearSum: Float = 0
        var validCount = 0

        for power in powerSpectrum where power > 1e-10 {
            logSum += log(power)
            linearSum += power
            validCount += 1
        }

        guard validCount > 0, linearSum > 0 else { return 0.5 }

        let geometricMean = exp(logSum / Float(validCount))
        let arithmeticMean = linearSum / Float(validCount)

        let flatness = geometricMean / arithmeticMean

        // Invert: low flatness = tonal (speech), high flatness = noise
        // Speech typically has flatness < 0.3
        return max(0, 1.0 - flatness / 0.5)
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

        // Convert to split complex and perform FFT
        realp.withUnsafeMutableBufferPointer { realpPtr in
            imagp.withUnsafeMutableBufferPointer { imagpPtr in
                var splitComplex = DSPSplitComplex(realp: realpPtr.baseAddress!, imagp: imagpPtr.baseAddress!)

                // Convert to split complex
                paddedFrame.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                    }
                }

                // Perform FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }

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
}
