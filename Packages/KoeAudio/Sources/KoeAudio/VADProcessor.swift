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
/// Detects speech segments and silence periods in audio
public struct VADProcessor: Sendable {
    /// RMS threshold below which audio is considered silence
    public let silenceThreshold: Float

    /// Duration of silence required to trigger speech end (seconds)
    public let silenceDuration: TimeInterval

    /// Minimum speech duration to consider valid (seconds)
    public let minSpeechDuration: TimeInterval

    /// Sample rate for duration calculations
    public let sampleRate: Double

    public init(
        silenceThreshold: Float = 0.012,
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

        // Calculate RMS for voice activity detection
        let rms = calculateRMS(samples)
        let isSpeakingNow = rms > silenceThreshold

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

    /// Check if samples contain speech (simple threshold check)
    public func containsSpeech(_ samples: [Float]) -> Bool {
        let rms = calculateRMS(samples)
        return rms > silenceThreshold
    }

    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}
