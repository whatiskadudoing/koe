import Foundation

/// Action to execute when a voice command is detected
public enum CommandAction: Codable, Sendable, Equatable {
    case notification(title: String, body: String)
    case startRecording
    case stopRecording
    case togglePipelineOption(String)
    case custom(String)
}

/// A voice command that can be detected and executed
public struct VoiceCommand: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let trigger: String
    public let action: CommandAction
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        trigger: String,
        action: CommandAction,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.trigger = trigger
        self.action = action
        self.isEnabled = isEnabled
    }

    /// Default "kon" command that starts recording
    public static let koeDefault = VoiceCommand(
        trigger: "kon",
        action: .startRecording,
        isEnabled: true
    )
}

/// Result of command detection
public struct CommandDetectionResult: Sendable {
    public let command: VoiceCommand
    public let confidence: Double
    public let isVoiceVerified: Bool
    public let timestamp: Date

    public init(
        command: VoiceCommand,
        confidence: Double,
        isVoiceVerified: Bool,
        timestamp: Date = Date()
    ) {
        self.command = command
        self.confidence = confidence
        self.isVoiceVerified = isVoiceVerified
        self.timestamp = timestamp
    }

    /// Whether the command should be executed
    /// Confidence threshold raised to 0.7 to reduce false positives
    public var shouldExecute: Bool {
        command.isEnabled && isVoiceVerified && confidence >= 0.7
    }
}
