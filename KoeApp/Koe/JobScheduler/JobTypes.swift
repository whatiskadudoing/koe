import Foundation

// MARK: - Node Type IDs

/// Constants for node type identifiers used throughout the app
public enum NodeTypeId {
    // Transcription engines
    public static let appleSpeech = "transcribe-apple"
    public static let whisperKitBalanced = "transcribe-whisperkit-balanced"
    public static let whisperKitAccurate = "transcribe-whisperkit-accurate"

    // Pipeline stages
    public static let hotkeyTrigger = "hotkey-trigger"
    public static let voiceTrigger = "voice-trigger"
    public static let recorder = "recorder"
    public static let improve = "text-improve"
    public static let autoType = "auto-type"
    public static let autoEnter = "auto-enter"
}

// MARK: - Task Status

public enum TaskStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
}

// MARK: - Task Type

public enum TaskType: String, Codable, Sendable {
    case downloadModel
    case compileModel
    case activateNode
}

// MARK: - Job Task

public struct JobTask: Identifiable, Codable, Sendable {
    public let id: UUID
    public let type: TaskType
    public let name: String
    public let icon: String
    public var status: TaskStatus
    public var progress: Double
    public var message: String?
    public var error: String?
    public var metadata: [String: String]

    public init(
        type: TaskType,
        name: String,
        icon: String,
        metadata: [String: String] = [:]
    ) {
        self.id = UUID()
        self.type = type
        self.name = name
        self.icon = icon
        self.status = .pending
        self.progress = 0
        self.message = nil
        self.error = nil
        self.metadata = metadata
    }
}

// MARK: - Job

public struct Job: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let icon: String
    public var tasks: [JobTask]
    public var isCompleted: Bool {
        tasks.allSatisfy { $0.status == .completed }
    }
    public var isFailed: Bool {
        tasks.contains { $0.status == .failed }
    }
    public var currentTaskIndex: Int {
        tasks.firstIndex { $0.status == .running || $0.status == .pending } ?? tasks.count
    }
    public var progress: Double {
        guard !tasks.isEmpty else { return 0 }
        let completed = Double(tasks.filter { $0.status == .completed }.count)
        let current = tasks.first { $0.status == .running }?.progress ?? 0
        return (completed + current) / Double(tasks.count)
    }

    public init(name: String, icon: String, tasks: [JobTask]) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.tasks = tasks
    }
}
