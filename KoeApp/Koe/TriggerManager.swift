import Foundation
import KoeDomain

/// Manages multiple recording triggers and coordinates their events
@MainActor
public final class TriggerManager {
    private var triggers: [String: any RecordingTrigger] = [:]
    private var eventHandler: (@Sendable (TriggerEvent) -> Void)?

    public init() {}

    /// Register a trigger
    public func register(_ trigger: any RecordingTrigger) async throws {
        triggers[trigger.id] = trigger
        if trigger.isEnabled {
            try await trigger.activate { [weak self] event in
                Task { @MainActor in
                    self?.eventHandler?(event)
                }
            }
        }
    }

    /// Unregister a trigger by ID
    public func unregister(id: String) async {
        if let trigger = triggers.removeValue(forKey: id) {
            await trigger.deactivate()
        }
    }

    /// Unregister all triggers
    public func unregisterAll() async {
        for trigger in triggers.values {
            await trigger.deactivate()
        }
        triggers.removeAll()
    }

    /// Set the event handler for all trigger events
    public func onEvent(_ handler: @escaping @Sendable (TriggerEvent) -> Void) {
        self.eventHandler = handler
    }

    /// Enable or disable a specific trigger
    public func setEnabled(_ enabled: Bool, for triggerId: String) async throws {
        guard let trigger = triggers[triggerId] else { return }
        trigger.isEnabled = enabled
        if enabled {
            try await trigger.activate { [weak self] event in
                Task { @MainActor in
                    self?.eventHandler?(event)
                }
            }
        } else {
            await trigger.deactivate()
        }
    }

    /// Get a trigger by ID
    public func trigger(id: String) -> (any RecordingTrigger)? {
        triggers[id]
    }

    /// Get all registered triggers
    public var allTriggers: [any RecordingTrigger] {
        Array(triggers.values)
    }
}
