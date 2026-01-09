import Foundation

/// Represents a single step in the processing pipeline
public struct ProcessingStep: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let input: StepData
    public var output: String?
    public var status: StepStatus
    public let startedAt: Date
    public var completedAt: Date?
    public var error: String?
    public var metadata: [String: String]

    /// Duration of this step (if completed)
    public var duration: TimeInterval? {
        guard let completedAt = completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }

    public init(
        id: UUID = UUID(),
        name: String,
        input: StepData,
        output: String? = nil,
        status: StepStatus = .pending,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        error: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.input = input
        self.output = output
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.error = error
        self.metadata = metadata
    }

    /// Mark step as completed with output
    public mutating func complete(output: String) {
        self.output = output
        self.status = .completed
        self.completedAt = Date()
    }

    /// Mark step as failed with error
    public mutating func fail(error: String) {
        self.error = error
        self.status = .failed
        self.completedAt = Date()
    }

    /// Mark step as skipped
    public mutating func skip() {
        self.status = .skipped
        self.completedAt = Date()
    }
}

/// Data that flows between processing steps
public enum StepData: Codable, Sendable, Equatable {
    case audio(sampleCount: Int, sampleRate: Double)
    case text(String)

    /// Get text content if this is text data
    public var textValue: String? {
        if case .text(let value) = self {
            return value
        }
        return nil
    }
}

/// Status of a processing step
public enum StepStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case pending
    case running
    case completed
    case failed
    case skipped
}
