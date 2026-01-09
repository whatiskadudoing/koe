import Foundation

/// Represents the data flowing through the processing pipeline
public struct ProcessingResult: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public var steps: [ProcessingStep]

    /// Final output (last completed step's output)
    public var finalOutput: String? {
        steps.last { $0.status == .completed }?.output
    }

    /// Total duration across all steps
    public var totalDuration: TimeInterval {
        steps.compactMap { $0.duration }.reduce(0, +)
    }

    /// Whether all steps completed successfully
    public var isSuccess: Bool {
        steps.allSatisfy { $0.status == .completed || $0.status == .skipped }
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        steps: [ProcessingStep] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.steps = steps
    }
}
