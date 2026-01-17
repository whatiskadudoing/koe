import FluidAudio
import Foundation

/// Voice Activity Detection processor using Silero VAD model via FluidAudio
/// This is a more accurate replacement for the heuristic-based VADProcessor
public actor SileroVADProcessor {
    /// Configuration for Silero VAD
    public struct Config: Sendable {
        /// Probability threshold for voice detection (0-1)
        /// Default 0.5 is more sensitive than FluidAudio's 0.85 default
        public let threshold: Float

        /// Duration of silence required to trigger speech end (seconds)
        public let silenceDuration: TimeInterval

        /// Minimum speech duration to consider valid (seconds)
        public let minSpeechDuration: TimeInterval

        /// Sample rate for duration calculations
        public let sampleRate: Double

        public init(
            threshold: Float = 0.5,
            silenceDuration: TimeInterval = 1.2,
            minSpeechDuration: TimeInterval = 0.5,
            sampleRate: Double = 16000
        ) {
            self.threshold = threshold
            self.silenceDuration = silenceDuration
            self.minSpeechDuration = minSpeechDuration
            self.sampleRate = sampleRate
        }
    }

    /// Result of VAD analysis
    public enum Result: Sendable, Equatable {
        /// Speech is currently detected
        case speaking

        /// Silence detected, with the time it started
        case silence(startedAt: Date)

        /// Speech segment has ended (silence duration exceeded threshold)
        case speechEnded(startSampleIndex: Int, endSampleIndex: Int)
    }

    private let config: Config
    private var vadManager: VadManager?
    private var streamState: VadStreamState?
    private var isInitialized = false
    private var initializationError: Error?

    /// Track state for analyze() method
    private var lastProbability: Float = 0
    private var isSpeakingState: Bool = false
    private var silenceStartTime: Date?
    private var speechStartSample: Int = 0
    private var processedSamples: Int = 0

    public init(config: Config = Config()) {
        self.config = config
    }

    /// Initialize the Silero VAD model
    /// Call this before using other methods
    public func initialize() async throws {
        guard !isInitialized else { return }

        do {
            let vadConfig = VadConfig(
                defaultThreshold: config.threshold,
                debugMode: false,
                computeUnits: .cpuAndNeuralEngine
            )
            vadManager = try await VadManager(config: vadConfig)
            streamState = VadStreamState.initial()
            isInitialized = true
            NSLog("[SileroVAD] Initialized successfully with threshold=%.2f", config.threshold)
        } catch {
            initializationError = error
            NSLog("[SileroVAD] Initialization failed: %@", error.localizedDescription)
            throw error
        }
    }

    /// Check if the VAD is ready to use
    public var isReady: Bool {
        isInitialized && vadManager != nil
    }

    /// Analyze audio samples for voice activity (compatible with old VADProcessor API)
    /// - Parameters:
    ///   - samples: Recent audio samples to analyze (16kHz mono)
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
    ) async -> Result {
        guard isInitialized, let manager = vadManager else {
            // Fall back to simple RMS-based detection if not initialized
            return fallbackAnalyze(
                samples: samples,
                isSpeaking: isSpeaking,
                silenceStartTime: silenceStartTime,
                totalSamples: totalSamples
            )
        }

        guard !samples.isEmpty else {
            return isSpeaking ? .speaking : .silence(startedAt: silenceStartTime ?? Date())
        }

        do {
            // Process in chunks of 4096 samples (256ms) as expected by Silero
            let chunkSize = VadManager.chunkSize
            var maxProbability: Float = 0

            // Process multiple chunks if we have enough samples
            var offset = 0
            while offset < samples.count {
                let endIndex = min(offset + chunkSize, samples.count)
                let chunk = Array(samples[offset..<endIndex])

                // Pad with zeros if needed (standard approach for audio processing)
                let paddedChunk: [Float]
                if chunk.count < chunkSize {
                    paddedChunk = chunk + Array(repeating: 0, count: chunkSize - chunk.count)
                } else {
                    paddedChunk = chunk
                }

                let result = try await manager.processStreamingChunk(
                    paddedChunk,
                    state: streamState ?? VadStreamState.initial(),
                    config: VadSegmentationConfig(
                        minSpeechDuration: config.minSpeechDuration,
                        minSilenceDuration: config.silenceDuration
                    )
                )

                streamState = result.state
                maxProbability = max(maxProbability, result.probability)
                offset += chunkSize
            }

            lastProbability = maxProbability
            let isSpeakingNow = maxProbability >= config.threshold

            // Debug logging
            if maxProbability > 0.1 {
                NSLog(
                    "[SileroVAD] probability=%.3f threshold=%.2f speaking=%d", maxProbability, config.threshold,
                    isSpeakingNow ? 1 : 0)
            }

            if isSpeakingNow {
                return .speaking
            } else {
                if isSpeaking {
                    let silenceStart = silenceStartTime ?? Date()
                    if let startTime = silenceStartTime,
                        Date().timeIntervalSince(startTime) >= config.silenceDuration
                    {
                        let speechSamples = totalSamples - speechStartIndex
                        let speechDuration = Double(speechSamples) / config.sampleRate

                        if speechDuration >= config.minSpeechDuration {
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
        } catch {
            NSLog("[SileroVAD] Processing error: %@", error.localizedDescription)
            return fallbackAnalyze(
                samples: samples,
                isSpeaking: isSpeaking,
                silenceStartTime: silenceStartTime,
                totalSamples: totalSamples
            )
        }
    }

    /// Check if samples contain speech
    public func containsSpeech(_ samples: [Float]) async -> Bool {
        guard isInitialized, let manager = vadManager else {
            return fallbackContainsSpeech(samples)
        }

        guard samples.count >= VadManager.chunkSize else {
            // For small samples, pad with zeros and check
            let padded = samples + Array(repeating: 0, count: VadManager.chunkSize - samples.count)
            do {
                let result = try await manager.processStreamingChunk(
                    padded,
                    state: streamState ?? VadStreamState.initial()
                )
                streamState = result.state
                return result.probability >= config.threshold
            } catch {
                return fallbackContainsSpeech(samples)
            }
        }

        do {
            // Process the last chunk
            let chunk = Array(samples.suffix(VadManager.chunkSize))
            let result = try await manager.processStreamingChunk(
                chunk,
                state: streamState ?? VadStreamState.initial()
            )
            streamState = result.state
            return result.probability >= config.threshold
        } catch {
            return fallbackContainsSpeech(samples)
        }
    }

    /// Get the raw probability value for debugging
    public func detectVoiceActivity(in samples: [Float]) async -> Float {
        guard isInitialized, let manager = vadManager else {
            return fallbackDetectVoiceActivity(in: samples)
        }

        guard !samples.isEmpty else { return 0 }

        do {
            let chunkSize = VadManager.chunkSize
            let chunk: [Float]
            if samples.count < chunkSize {
                // Pad with zeros (standard approach for audio processing)
                chunk = samples + Array(repeating: 0, count: chunkSize - samples.count)
            } else {
                chunk = Array(samples.suffix(chunkSize))
            }

            let result = try await manager.processStreamingChunk(
                chunk,
                state: streamState ?? VadStreamState.initial()
            )
            streamState = result.state
            return result.probability
        } catch {
            return fallbackDetectVoiceActivity(in: samples)
        }
    }

    /// Reset the streaming state (call when starting a new recording)
    public func reset() {
        streamState = VadStreamState.initial()
        lastProbability = 0
        isSpeakingState = false
        silenceStartTime = nil
        speechStartSample = 0
        processedSamples = 0
    }

    // MARK: - Fallback methods (RMS-based, used when Silero not available)

    private func fallbackAnalyze(
        samples: [Float],
        isSpeaking: Bool,
        silenceStartTime: Date?,
        totalSamples: Int
    ) -> Result {
        let rms = calculateRMS(samples)
        let threshold: Float = 0.01  // Simple RMS threshold
        let isSpeakingNow = rms >= threshold

        if isSpeakingNow {
            return .speaking
        } else {
            if isSpeaking {
                let silenceStart = silenceStartTime ?? Date()
                if let startTime = silenceStartTime,
                    Date().timeIntervalSince(startTime) >= config.silenceDuration
                {
                    return .speechEnded(startSampleIndex: 0, endSampleIndex: totalSamples)
                }
                return .silence(startedAt: silenceStart)
            }
            return .silence(startedAt: silenceStartTime ?? Date())
        }
    }

    private func fallbackContainsSpeech(_ samples: [Float]) -> Bool {
        let rms = calculateRMS(samples)
        return rms >= 0.01
    }

    private func fallbackDetectVoiceActivity(in samples: [Float]) -> Float {
        let rms = calculateRMS(samples)
        return min(rms / 0.03, 1.0)
    }

    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sumSquares: Float = 0
        for sample in samples {
            sumSquares += sample * sample
        }
        return sqrt(sumSquares / Float(samples.count))
    }
}
