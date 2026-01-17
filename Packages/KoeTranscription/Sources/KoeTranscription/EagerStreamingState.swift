import Foundation
import WhisperKit

/// State management for eager mode streaming transcription
/// Tracks confirmed vs hypothesis words across multiple transcription runs
public final class EagerStreamingState: @unchecked Sendable {
    private let lock = NSLock()

    // MARK: - State

    /// Words that have been confirmed by appearing in multiple consecutive runs
    private var _confirmedWords: [WordTiming] = []

    /// The last set of words that matched between two consecutive runs
    private var _lastAgreedWords: [WordTiming] = []

    /// The timestamp (in seconds) where the last agreed word starts
    private var _lastAgreedSeconds: Float = 0

    /// The previous transcription result for comparison
    private var _prevResult: TranscriptionResult?

    /// The previous adjusted words (with offset applied) for comparison
    private var _prevAdjustedWords: [WordTiming]?

    /// Number of token confirmations needed before a word is considered "confirmed"
    /// Higher = more accurate but slower to confirm
    public var tokenConfirmationsNeeded: Int = 2

    // MARK: - Public Accessors

    public var confirmedWords: [WordTiming] {
        lock.lock()
        defer { lock.unlock() }
        return _confirmedWords
    }

    public var lastAgreedWords: [WordTiming] {
        lock.lock()
        defer { lock.unlock() }
        return _lastAgreedWords
    }

    public var lastAgreedSeconds: Float {
        lock.lock()
        defer { lock.unlock() }
        return _lastAgreedSeconds
    }

    /// Get the confirmed text (words that appeared in multiple runs)
    public var confirmedText: String {
        lock.lock()
        defer { lock.unlock() }
        return _confirmedWords.map { $0.word }.joined()
    }

    /// Get the hypothesis text (current best guess for unconfirmed portion)
    public func hypothesisText(currentWords: [WordTiming]) -> String {
        lock.lock()
        defer { lock.unlock() }
        let hypothesisWords = currentWords.filter { $0.start >= _lastAgreedSeconds }
        return hypothesisWords.map { $0.word }.joined()
    }

    /// Get full text (confirmed + hypothesis)
    public func fullText(currentWords: [WordTiming]) -> String {
        return confirmedText + hypothesisText(currentWords: currentWords)
    }

    // MARK: - Initialization

    public init(tokenConfirmationsNeeded: Int = 2) {
        self.tokenConfirmationsNeeded = tokenConfirmationsNeeded
    }

    // MARK: - State Management

    /// Reset all state for a new recording session
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _confirmedWords = []
        _lastAgreedWords = []
        _lastAgreedSeconds = 0
        _prevResult = nil
        _prevAdjustedWords = nil
    }

    /// Process a new transcription result and update state
    /// Returns tuple of (confirmedText, hypothesisText, wasUpdated)
    /// - Parameters:
    ///   - result: The transcription result from WhisperKit
    ///   - audioOffsetSeconds: If audio was truncated, the offset from original start (adjusts timestamps)
    @discardableResult
    public func processResult(
        _ result: TranscriptionResult, audioOffsetSeconds: Float = 0
    ) -> (confirmed: String, hypothesis: String, updated: Bool) {
        lock.lock()
        defer { lock.unlock() }

        // Adjust word timestamps if audio was truncated
        // When audio is truncated, WhisperKit returns timestamps relative to truncated audio (starting at 0)
        // We need to add the offset to get absolute timestamps
        let adjustedWords: [WordTiming]
        if audioOffsetSeconds > 0 {
            adjustedWords = result.allWords.map { word in
                WordTiming(
                    word: word.word,
                    tokens: word.tokens,
                    start: word.start + audioOffsetSeconds,
                    end: word.end + audioOffsetSeconds,
                    probability: word.probability
                )
            }
        } else {
            adjustedWords = result.allWords
        }

        // Get words from this result that are after our last agreed point
        let hypothesisWords = adjustedWords.filter { $0.start >= _lastAgreedSeconds }

        var wasUpdated = false

        if let prevWords = _prevAdjustedWords {
            // Get previous words after last agreed point
            let prevWordsFiltered = prevWords.filter { $0.start >= _lastAgreedSeconds }

            // Find longest common prefix between previous and current
            let commonPrefix = findLongestCommonPrefix(prevWordsFiltered, hypothesisWords)

            // If we have enough matching words, confirm them
            if commonPrefix.count >= tokenConfirmationsNeeded {
                // Keep the last N words as "agreed" for context
                _lastAgreedWords = Array(commonPrefix.suffix(tokenConfirmationsNeeded))
                _lastAgreedSeconds = _lastAgreedWords.first?.start ?? _lastAgreedSeconds

                // Add confirmed words (all except the last N which we keep for next comparison)
                let newlyConfirmed = commonPrefix.prefix(commonPrefix.count - tokenConfirmationsNeeded)
                _confirmedWords.append(contentsOf: newlyConfirmed)
                wasUpdated = !newlyConfirmed.isEmpty
            }
        }

        // Store adjusted words for next comparison (not the full result)
        _prevAdjustedWords = adjustedWords
        _prevResult = result

        let confirmedText = _confirmedWords.map { $0.word }.joined()
        let currentHypothesisWords = adjustedWords.filter { $0.start >= _lastAgreedSeconds }
        let hypothesisText = currentHypothesisWords.map { $0.word }.joined()

        return (confirmedText, hypothesisText, wasUpdated)
    }

    /// Get the tokens to use as prefix for the next transcription
    /// This provides context from the last agreed words
    public func getPrefixTokens() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return _lastAgreedWords.flatMap { $0.tokens }
    }

    /// Get the clip timestamps to skip already-processed audio
    public func getClipTimestamps() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return [_lastAgreedSeconds]
    }

    /// Finalize any remaining hypothesis as confirmed (call when recording ends)
    /// When using truncated audio, pass the audio offset so timestamps can be adjusted
    public func finalize(with result: TranscriptionResult?, audioOffsetSeconds: Float = 0) {
        lock.lock()
        defer { lock.unlock() }

        guard let result = result else { return }

        // Add all words from the result (they represent the remaining unconfirmed portion)
        // The result comes from truncated audio, so timestamps need to be adjusted
        for word in result.allWords {
            // Create adjusted word with corrected timestamps
            let adjustedWord = WordTiming(
                word: word.word,
                tokens: word.tokens,
                start: word.start + audioOffsetSeconds,
                end: word.end + audioOffsetSeconds,
                probability: word.probability
            )

            // Skip if this word overlaps with already confirmed words
            // (check both by timestamp and by word text to handle edge cases)
            let isDuplicate = _confirmedWords.contains { confirmedWord in
                // Consider duplicate if timestamps are very close AND text matches
                let timeDiff = abs(confirmedWord.start - adjustedWord.start)
                return timeDiff < 0.3 && normalizeWord(confirmedWord.word) == normalizeWord(adjustedWord.word)
            }

            if !isDuplicate {
                _confirmedWords.append(adjustedWord)
            }
        }
    }

    // MARK: - Private Helpers

    /// Find the longest common prefix between two word arrays
    /// Words are compared by their normalized text
    private func findLongestCommonPrefix(_ words1: [WordTiming], _ words2: [WordTiming]) -> [WordTiming] {
        let commonPrefix = zip(words1, words2).prefix(while: { word1, word2 in
            normalizeWord(word1.word) == normalizeWord(word2.word)
        })
        return commonPrefix.map { $0.1 }
    }

    /// Normalize a word for comparison (lowercase, trim whitespace)
    private func normalizeWord(_ word: String) -> String {
        return word.lowercased().trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Streaming Result

/// Result from an eager streaming transcription run
public struct EagerStreamingResult: Sendable {
    /// Text that has been confirmed by multiple runs
    public let confirmedText: String

    /// Current hypothesis (may change in next run)
    public let hypothesisText: String

    /// Full text (confirmed + hypothesis)
    public var fullText: String {
        confirmedText + hypothesisText
    }

    /// Whether new text was confirmed in this run
    public let wasUpdated: Bool

    /// The last agreed timestamp in seconds
    public let lastAgreedSeconds: Float

    /// Transcription timing information
    public let timings: TranscriptionTimings?

    public init(
        confirmedText: String,
        hypothesisText: String,
        wasUpdated: Bool,
        lastAgreedSeconds: Float,
        timings: TranscriptionTimings? = nil
    ) {
        self.confirmedText = confirmedText
        self.hypothesisText = hypothesisText
        self.wasUpdated = wasUpdated
        self.lastAgreedSeconds = lastAgreedSeconds
        self.timings = timings
    }
}
