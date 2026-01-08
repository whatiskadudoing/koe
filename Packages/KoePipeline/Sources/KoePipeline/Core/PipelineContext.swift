import Foundation

/// Context that flows through the pipeline, carrying data between stages and actions
public final class PipelineContext: @unchecked Sendable {
    private let lock = NSLock()

    // MARK: - Data Storage

    /// Raw audio samples (from audio input)
    public var audioSamples: [Float]?

    /// Audio sample rate
    public var sampleRate: Double = 16000

    /// Path to audio file
    public var audioFilePath: URL?

    /// Current text being processed
    public var text: String = ""

    /// Original text before any processing
    public var originalText: String = ""

    /// Detected or specified language
    public var language: String?

    /// Confidence scores from various stages
    public var confidences: [String: Double] = [:]

    // MARK: - Metadata

    /// Unique ID for this pipeline run
    public let runId: UUID

    /// When this pipeline run started
    public let startTime: Date

    /// Timing data for each element (elementId -> duration in seconds)
    public var elementTimings: [String: TimeInterval] = [:]

    /// Errors that occurred (non-fatal)
    public var warnings: [String] = []

    /// Detailed metrics for each element execution
    public var elementMetrics: [String: ElementExecutionMetrics] = [:]

    /// Custom data storage for elements
    private var customData: [String: Any] = [:]

    // MARK: - State

    /// Whether the pipeline should be cancelled
    public var isCancelled: Bool = false

    /// Current element being executed
    public var currentElementId: String?

    // MARK: - Initialization

    public init(runId: UUID = UUID()) {
        self.runId = runId
        self.startTime = Date()
    }

    // MARK: - Custom Data Access

    /// Store custom data for an element
    public func setCustomData<T>(_ value: T, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        customData[key] = value
    }

    /// Retrieve custom data
    public func getCustomData<T>(forKey key: String) -> T? {
        lock.lock()
        defer { lock.unlock() }
        return customData[key] as? T
    }

    /// Remove custom data
    public func removeCustomData(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        customData.removeValue(forKey: key)
    }

    // MARK: - Timing

    /// Record timing for an element
    public func recordTiming(elementId: String, duration: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        elementTimings[elementId] = duration
    }

    /// Total elapsed time since pipeline started
    public var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    // MARK: - Convenience

    /// Create a summary of the pipeline run
    public var summary: PipelineRunSummary {
        PipelineRunSummary(
            runId: runId,
            startTime: startTime,
            elapsedTime: elapsedTime,
            elementTimings: elementTimings,
            inputLength: originalText.count,
            outputLength: text.count,
            warnings: warnings,
            elementMetrics: elementMetrics
        )
    }

    /// Record detailed metrics for an element
    public func recordMetrics(_ metrics: ElementExecutionMetrics) {
        lock.lock()
        defer { lock.unlock() }
        elementMetrics[metrics.elementId] = metrics
    }
}

/// Summary of a pipeline run
public struct PipelineRunSummary: Sendable {
    public let runId: UUID
    public let startTime: Date
    public let elapsedTime: TimeInterval
    public let elementTimings: [String: TimeInterval]
    public let inputLength: Int
    public let outputLength: Int
    public let warnings: [String]
    public let elementMetrics: [String: ElementExecutionMetrics]

    public init(
        runId: UUID,
        startTime: Date,
        elapsedTime: TimeInterval,
        elementTimings: [String: TimeInterval],
        inputLength: Int,
        outputLength: Int,
        warnings: [String],
        elementMetrics: [String: ElementExecutionMetrics] = [:]
    ) {
        self.runId = runId
        self.startTime = startTime
        self.elapsedTime = elapsedTime
        self.elementTimings = elementTimings
        self.inputLength = inputLength
        self.outputLength = outputLength
        self.warnings = warnings
        self.elementMetrics = elementMetrics
    }

    public var formattedElapsedTime: String {
        String(format: "%.2fs", elapsedTime)
    }
}

// MARK: - Element Execution Metrics

/// Detailed execution metrics for a single pipeline element
public struct ElementExecutionMetrics: Codable, Sendable {
    public let elementId: String
    public let elementType: String
    public let startTime: Date
    public let endTime: Date
    public let durationMs: Double
    public let status: ExecutionStatus
    public let memoryUsedBytes: Int64?
    public let inputCharCount: Int
    public let outputCharCount: Int
    public let errorMessage: String?

    public enum ExecutionStatus: String, Codable, Sendable {
        case success
        case skipped
        case failed
        case cancelled
    }

    public init(
        elementId: String,
        elementType: String,
        startTime: Date,
        endTime: Date,
        status: ExecutionStatus,
        memoryUsedBytes: Int64? = nil,
        inputCharCount: Int = 0,
        outputCharCount: Int = 0,
        errorMessage: String? = nil
    ) {
        self.elementId = elementId
        self.elementType = elementType
        self.startTime = startTime
        self.endTime = endTime
        self.durationMs = endTime.timeIntervalSince(startTime) * 1000
        self.status = status
        self.memoryUsedBytes = memoryUsedBytes
        self.inputCharCount = inputCharCount
        self.outputCharCount = outputCharCount
        self.errorMessage = errorMessage
    }

    public var formattedDuration: String {
        if durationMs < 1000 {
            return String(format: "%.0fms", durationMs)
        } else {
            return String(format: "%.2fs", durationMs / 1000)
        }
    }

    public var formattedMemory: String? {
        guard let bytes = memoryUsedBytes else { return nil }
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
}

// MARK: - Pipeline Execution Settings

/// Settings used during a pipeline execution (for comparison/testing)
public struct PipelineExecutionSettings: Codable, Sendable, Equatable {
    public let language: String
    public let model: String
    public let cleanupEnabled: Bool
    public let tone: String
    public let promptMode: Bool
    public let hotkeyKeyCode: UInt32
    public let hotkeyModifiers: Int

    public init(
        language: String,
        model: String,
        cleanupEnabled: Bool,
        tone: String,
        promptMode: Bool,
        hotkeyKeyCode: UInt32,
        hotkeyModifiers: Int
    ) {
        self.language = language
        self.model = model
        self.cleanupEnabled = cleanupEnabled
        self.tone = tone
        self.promptMode = promptMode
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
    }

    public var summary: String {
        var parts: [String] = []
        parts.append(language == "auto" ? "Auto" : language)
        parts.append(model)
        if cleanupEnabled { parts.append("cleanup") }
        if tone != "none" { parts.append(tone) }
        if promptMode { parts.append("prompt") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Pipeline Execution History

/// Complete history of a pipeline execution
public struct PipelineExecutionRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let pipelineName: String
    public let totalDurationMs: Double
    public let status: ElementExecutionMetrics.ExecutionStatus
    public let elementMetrics: [ElementExecutionMetrics]
    public let inputText: String
    public let outputText: String
    public let errorMessage: String?
    public let settings: PipelineExecutionSettings?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        pipelineName: String,
        totalDurationMs: Double,
        status: ElementExecutionMetrics.ExecutionStatus,
        elementMetrics: [ElementExecutionMetrics],
        inputText: String,
        outputText: String,
        errorMessage: String? = nil,
        settings: PipelineExecutionSettings? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.pipelineName = pipelineName
        self.totalDurationMs = totalDurationMs
        self.status = status
        self.elementMetrics = elementMetrics
        self.inputText = inputText
        self.outputText = outputText
        self.errorMessage = errorMessage
        self.settings = settings
    }

    public var formattedDuration: String {
        if totalDurationMs < 1000 {
            return String(format: "%.0fms", totalDurationMs)
        } else {
            return String(format: "%.2fs", totalDurationMs / 1000)
        }
    }

    /// Get metrics for a specific element type
    public func metrics(for elementType: String) -> ElementExecutionMetrics? {
        elementMetrics.first { $0.elementType == elementType }
    }

    /// Find the slowest element
    public var slowestElement: ElementExecutionMetrics? {
        elementMetrics.max(by: { $0.durationMs < $1.durationMs })
    }

    /// Find failed elements
    public var failedElements: [ElementExecutionMetrics] {
        elementMetrics.filter { $0.status == .failed }
    }
}
