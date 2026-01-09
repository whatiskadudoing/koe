import Foundation

/// Event emitted by triggers to control recording
public enum TriggerEvent: Sendable {
    case start(context: TriggerContext)
    case stop(context: TriggerContext)
}

/// Context passed with trigger events
public struct TriggerContext: Sendable {
    public let triggerId: String
    public let triggerType: String
    public let timestamp: Date

    public init(triggerId: String, triggerType: String, timestamp: Date = Date()) {
        self.triggerId = triggerId
        self.triggerType = triggerType
        self.timestamp = timestamp
    }
}

/// Protocol for any mechanism that can trigger recording
public protocol RecordingTrigger: AnyObject, Sendable {
    /// Unique identifier for this trigger instance
    var id: String { get }

    /// Type identifier (e.g., "hotkey", "voice", "api")
    var typeId: String { get }

    /// Human-readable name for display
    var displayName: String { get }

    /// Whether the trigger is currently enabled
    var isEnabled: Bool { get set }

    /// Activate the trigger with an event handler
    func activate(handler: @escaping @Sendable (TriggerEvent) -> Void) async throws

    /// Deactivate the trigger and release resources
    func deactivate() async
}
