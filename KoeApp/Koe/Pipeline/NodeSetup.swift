import Foundation

// MARK: - Setup Step Types

/// Types of setup steps a node might need
public enum SetupStepType: Codable, Sendable, Equatable {
    /// Download a model from a URL
    case downloadModel(url: String, sizeBytes: Int64)

    /// Compile model for the device (e.g., ANE compilation)
    case compileModel

    /// Verify an API key is configured
    case checkAPIKey(provider: String)

    /// Load model into memory
    case loadIntoMemory

    /// Display name for UI
    public var displayName: String {
        switch self {
        case let .downloadModel(_, sizeBytes):
            let sizeStr = ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
            return "Download model (\(sizeStr))"
        case .compileModel:
            return "Compile for your device"
        case let .checkAPIKey(provider):
            return "Configure \(provider) API key"
        case .loadIntoMemory:
            return "Load into memory"
        }
    }

    /// Icon for UI
    public var icon: String {
        switch self {
        case .downloadModel: return "arrow.down.circle"
        case .compileModel: return "hammer"
        case .checkAPIKey: return "key"
        case .loadIntoMemory: return "memorychip"
        }
    }
}

// MARK: - Setup Step Status

/// Status of a setup step
public enum SetupStepStatus: String, Codable, Sendable {
    case pending
    case inProgress
    case completed
    case failed
}

// MARK: - Setup Step

/// A single setup step with progress tracking
public struct SetupStep: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let type: SetupStepType
    public var status: SetupStepStatus
    public var progress: Double
    public var errorMessage: String?
    public var retryCount: Int

    public init(
        id: UUID = UUID(),
        type: SetupStepType,
        status: SetupStepStatus = .pending,
        progress: Double = 0.0,
        errorMessage: String? = nil,
        retryCount: Int = 0
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.progress = progress
        self.errorMessage = errorMessage
        self.retryCount = retryCount
    }

    public var displayName: String {
        type.displayName
    }

    public var icon: String {
        type.icon
    }
}

// MARK: - Node Setup Task

/// A complete setup task for a node, containing multiple steps
public struct NodeSetupTask: Identifiable, Sendable {
    public let id: UUID
    public let nodeId: String
    public let nodeDisplayName: String
    public let nodeIcon: String
    public let nodeColor: String
    public var steps: [SetupStep]
    public var currentStepIndex: Int
    public var status: TaskStatus
    public var startedAt: Date?
    public var completedAt: Date?

    public enum TaskStatus: Sendable, Equatable {
        case queued
        case inProgress
        case completed
        case failed(String)
    }

    public init(
        id: UUID = UUID(),
        nodeId: String,
        nodeDisplayName: String,
        nodeIcon: String,
        nodeColor: String = "accent",
        steps: [SetupStep],
        currentStepIndex: Int = 0,
        status: TaskStatus = .queued,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.nodeId = nodeId
        self.nodeDisplayName = nodeDisplayName
        self.nodeIcon = nodeIcon
        self.nodeColor = nodeColor
        self.steps = steps
        self.currentStepIndex = currentStepIndex
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    /// Overall progress across all steps (0.0 - 1.0)
    public var overallProgress: Double {
        guard !steps.isEmpty else { return 0 }

        let completedSteps = steps.prefix(currentStepIndex).count
        let currentStepProgress = currentStepIndex < steps.count ? steps[currentStepIndex].progress : 0

        let totalProgress = (Double(completedSteps) + currentStepProgress) / Double(steps.count)
        return totalProgress
    }

    /// Current step being executed
    public var currentStep: SetupStep? {
        guard currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }

    /// Description of current activity
    public var currentActivity: String {
        switch status {
        case .queued:
            return "Waiting..."
        case .inProgress:
            return currentStep?.displayName ?? "Processing..."
        case .completed:
            return "Ready"
        case let .failed(message):
            return "Failed: \(message)"
        }
    }
}

// MARK: - Node Setup State

/// Setup state for a node (used in UI)
public enum NodeSetupState: Sendable, Equatable {
    /// No setup required for this node
    case notNeeded

    /// Setup is required before the node can be used
    case setupRequired

    /// Setup is in progress (queued or active)
    case settingUp(progress: Double)

    /// Setup is complete, node is ready
    case ready

    /// Setup failed
    case failed(String)
}

// MARK: - Node Setup Requirements

/// Definition of setup requirements for a node type
public struct NodeSetupRequirements: Sendable {
    public let nodeId: String
    public let stepTypes: [SetupStepType]

    /// Create setup steps from the requirements
    public func createSteps() -> [SetupStep] {
        stepTypes.map { SetupStep(type: $0) }
    }

    public init(nodeId: String, stepTypes: [SetupStepType]) {
        self.nodeId = nodeId
        self.stepTypes = stepTypes
    }
}

// MARK: - Predefined Setup Requirements

public extension NodeSetupRequirements {
    /// WhisperKit transcription engine setup
    static let whisperKit = NodeSetupRequirements(
        nodeId: "transcribe-whisperkit",
        stepTypes: [
            .downloadModel(url: "argmaxinc/whisperkit-coreml", sizeBytes: 954_000_000),
            .compileModel
        ]
    )

    /// AI Improve node setup (local model)
    static let improveLocal = NodeSetupRequirements(
        nodeId: "text-improve",
        stepTypes: [
            .downloadModel(url: "local-llm", sizeBytes: 2_000_000_000),
            .loadIntoMemory
        ]
    )

    /// AI Improve node setup (cloud API)
    static let improveCloud = NodeSetupRequirements(
        nodeId: "text-improve",
        stepTypes: [
            .checkAPIKey(provider: "OpenAI")
        ]
    )
}
