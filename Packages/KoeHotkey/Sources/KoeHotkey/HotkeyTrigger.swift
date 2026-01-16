import Foundation
import KoeDomain

/// A trigger that activates recording via keyboard shortcut
public final class HotkeyTrigger: RecordingTrigger, @unchecked Sendable {
    public let id: String
    public let typeId: String = "hotkey"
    public let displayName: String = "Keyboard Shortcut"
    public var isEnabled: Bool = true

    private let hotkeyManager: KoeHotkeyManager
    private var eventHandler: (@Sendable (TriggerEvent) -> Void)?

    public init(id: String = UUID().uuidString, hotkeyManager: KoeHotkeyManager) {
        self.id = id
        self.hotkeyManager = hotkeyManager
    }

    public func activate(handler: @escaping @Sendable (TriggerEvent) -> Void) async throws {
        self.eventHandler = handler

        hotkeyManager.register(
            onKeyDown: { [weak self] in
                guard let self = self else { return }
                let context = TriggerContext(triggerId: self.id, triggerType: self.typeId)
                handler(.start(context: context))
            },
            onKeyUp: { [weak self] in
                guard let self = self else { return }
                let context = TriggerContext(triggerId: self.id, triggerType: self.typeId)
                handler(.stop(context: context))
            },
            onCancel: { [weak self] in
                guard let self = self else { return }
                let context = TriggerContext(triggerId: self.id, triggerType: self.typeId)
                handler(.cancel(context: context))
            }
        )
    }

    public func deactivate() async {
        hotkeyManager.unregister()
        eventHandler = nil
    }

    /// Update the keyboard shortcut
    /// - Parameters:
    ///   - keyCode: The virtual key code
    ///   - modifiers: Modifier flags
    public func updateShortcut(keyCode: UInt32, modifiers: Int) {
        hotkeyManager.setShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    /// Check if the hotkey is currently registered
    public var isRegistered: Bool {
        hotkeyManager.isRegistered
    }
}
