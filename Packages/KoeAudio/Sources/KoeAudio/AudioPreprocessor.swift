import Accelerate
import Foundation

/// Audio preprocessing utilities for improving transcription quality
/// Based on validated best practices from OpenAI Whisper community
public struct AudioPreprocessor: Sendable {
    /// Configuration for audio preprocessing
    public struct Config: Sendable {
        /// Silence threshold in decibels (samples below this are considered silence)
        /// Default: -30 dB (more conservative than -20 dB to avoid cutting speech)
        public let silenceThresholdDB: Float

        /// Minimum chunk size in milliseconds for silence detection
        public let chunkSizeMs: Int

        /// Sample rate of the audio
        public let sampleRate: Double

        /// Minimum audio duration to keep after trimming (seconds)
        /// Prevents trimming too aggressively
        public let minDurationAfterTrim: TimeInterval

        public init(
            silenceThresholdDB: Float = -30.0,
            chunkSizeMs: Int = 10,
            sampleRate: Double = 16000,
            minDurationAfterTrim: TimeInterval = 0.3
        ) {
            self.silenceThresholdDB = silenceThresholdDB
            self.chunkSizeMs = chunkSizeMs
            self.sampleRate = sampleRate
            self.minDurationAfterTrim = minDurationAfterTrim
        }
    }

    private let config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    /// Trim leading silence from audio samples
    /// This helps prevent Whisper hallucinations from long silences at the start
    ///
    /// - Parameter samples: Audio samples at configured sample rate
    /// - Returns: Samples with leading silence trimmed
    public func trimLeadingSilence(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        let chunkSize = Int(Double(config.chunkSizeMs) / 1000.0 * config.sampleRate)
        let minSamplesAfterTrim = Int(config.minDurationAfterTrim * config.sampleRate)

        var trimIndex = 0

        // Find first non-silent chunk
        for offset in stride(from: 0, to: samples.count - chunkSize, by: chunkSize) {
            let chunk = Array(samples[offset..<(offset + chunkSize)])
            let dB = calculateDBFS(chunk)

            if dB >= config.silenceThresholdDB {
                // Found non-silent audio - go back a bit to avoid cutting speech onset
                trimIndex = max(0, offset - chunkSize)
                break
            }
            trimIndex = offset + chunkSize
        }

        // Ensure we keep minimum duration
        let maxTrimIndex = max(0, samples.count - minSamplesAfterTrim)
        trimIndex = min(trimIndex, maxTrimIndex)

        if trimIndex > 0 {
            let trimmedDuration = Double(trimIndex) / config.sampleRate
            NSLog("[AudioPreprocessor] Trimmed %.2fs of leading silence", trimmedDuration)
            return Array(samples[trimIndex...])
        }

        return samples
    }

    /// Trim trailing silence from audio samples
    /// Helps reduce unnecessary processing and potential hallucinations
    ///
    /// - Parameter samples: Audio samples at configured sample rate
    /// - Returns: Samples with trailing silence trimmed
    public func trimTrailingSilence(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        let chunkSize = Int(Double(config.chunkSizeMs) / 1000.0 * config.sampleRate)
        let minSamplesAfterTrim = Int(config.minDurationAfterTrim * config.sampleRate)

        var trimEndIndex = samples.count

        // Find last non-silent chunk (search backwards)
        for offset in stride(from: samples.count - chunkSize, through: 0, by: -chunkSize) {
            let chunk = Array(samples[offset..<min(offset + chunkSize, samples.count)])
            let dB = calculateDBFS(chunk)

            if dB >= config.silenceThresholdDB {
                // Found non-silent audio - keep a bit more to avoid cutting speech end
                trimEndIndex = min(samples.count, offset + chunkSize * 2)
                break
            }
            trimEndIndex = offset
        }

        // Ensure we keep minimum duration
        trimEndIndex = max(trimEndIndex, minSamplesAfterTrim)

        if trimEndIndex < samples.count {
            let trimmedDuration = Double(samples.count - trimEndIndex) / config.sampleRate
            NSLog("[AudioPreprocessor] Trimmed %.2fs of trailing silence", trimmedDuration)
            return Array(samples[..<trimEndIndex])
        }

        return samples
    }

    /// Trim both leading and trailing silence
    ///
    /// - Parameter samples: Audio samples at configured sample rate
    /// - Returns: Samples with silence trimmed from both ends
    public func trimSilence(_ samples: [Float]) -> [Float] {
        let leadingTrimmed = trimLeadingSilence(samples)
        return trimTrailingSilence(leadingTrimmed)
    }

    /// Find the first sample index where speech begins
    /// Useful for applications that need the exact trim point
    ///
    /// - Parameter samples: Audio samples at configured sample rate
    /// - Returns: Index of first non-silent sample, or 0 if all non-silent
    public func findSpeechStart(_ samples: [Float]) -> Int {
        guard !samples.isEmpty else { return 0 }

        let chunkSize = Int(Double(config.chunkSizeMs) / 1000.0 * config.sampleRate)

        for offset in stride(from: 0, to: samples.count - chunkSize, by: chunkSize) {
            let chunk = Array(samples[offset..<(offset + chunkSize)])
            let dB = calculateDBFS(chunk)

            if dB >= config.silenceThresholdDB {
                return max(0, offset - chunkSize)
            }
        }

        return 0
    }

    /// Find the last sample index where speech ends
    ///
    /// - Parameter samples: Audio samples at configured sample rate
    /// - Returns: Index of last non-silent sample, or samples.count if all non-silent
    public func findSpeechEnd(_ samples: [Float]) -> Int {
        guard !samples.isEmpty else { return 0 }

        let chunkSize = Int(Double(config.chunkSizeMs) / 1000.0 * config.sampleRate)

        for offset in stride(from: samples.count - chunkSize, through: 0, by: -chunkSize) {
            let chunk = Array(samples[offset..<min(offset + chunkSize, samples.count)])
            let dB = calculateDBFS(chunk)

            if dB >= config.silenceThresholdDB {
                return min(samples.count, offset + chunkSize * 2)
            }
        }

        return samples.count
    }

    /// Calculate the dBFS (decibels relative to full scale) of audio samples
    ///
    /// - Parameter samples: Audio samples
    /// - Returns: dBFS value (0 dB = full scale, negative values = quieter)
    public func calculateDBFS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -Float.infinity }

        // Calculate RMS
        var sumSquares: Float = 0
        vDSP_svesq(samples, 1, &sumSquares, vDSP_Length(samples.count))
        let rms = sqrt(sumSquares / Float(samples.count))

        // Convert to dB (20 * log10(rms))
        // Add small value to avoid log(0)
        let dB = 20 * log10(max(rms, 1e-10))

        return dB
    }

    /// Check if audio chunk is essentially silent
    ///
    /// - Parameter samples: Audio samples to check
    /// - Returns: True if the chunk is below the silence threshold
    public func isSilent(_ samples: [Float]) -> Bool {
        let dB = calculateDBFS(samples)
        return dB < config.silenceThresholdDB
    }
}
