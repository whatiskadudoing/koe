import Foundation

/// Thread-safe audio buffer manager for accumulating audio samples
public final class AudioBufferManager: @unchecked Sendable {
    private var samples: [Float] = []
    private let lock = NSLock()

    public init() {}

    /// Append samples to the buffer
    public func append(_ newSamples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(contentsOf: newSamples)
    }

    /// Get all samples
    public func getSamples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    /// Get the last N samples
    public func getRecentSamples(count: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return Array(samples.suffix(count))
    }

    /// Get samples in a specific range
    public func getSamples(from startIndex: Int, to endIndex: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let start = max(0, startIndex)
        let end = min(endIndex, samples.count)
        guard start < end else { return [] }
        return Array(samples[start..<end])
    }

    /// Get total sample count
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }

    /// Clear all samples
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
    }
}
