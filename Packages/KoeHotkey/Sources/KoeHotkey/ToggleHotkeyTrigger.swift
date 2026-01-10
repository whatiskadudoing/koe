import Foundation
import KoeDomain

/// A trigger that activates/deactivates recording via keyboard toggle
/// Unlike HotkeyTrigger (press-and-hold), this uses press-to-start, press-again-to-stop
/// Similar to native macOS dictation behavior (F5/microphone key)
public final class ToggleHotkeyTrigger: RecordingTrigger, @unchecked Sendable {
    public let id: String
    public let typeId: String = "native-mac-trigger"
    public let displayName: String = "Toggle Key"
    public var isEnabled: Bool = true

    private let hotkeyManager: ToggleHotkeyManager
    private var eventHandler: (@Sendable (TriggerEvent) -> Void)?

    public init(id: String = UUID().uuidString, hotkeyManager: ToggleHotkeyManager) {
        self.id = id
        self.hotkeyManager = hotkeyManager
    }

    public func activate(handler: @escaping @Sendable (TriggerEvent) -> Void) async throws {
        self.eventHandler = handler

        hotkeyManager.register { [weak self] isRecording in
            guard let self = self else { return }
            let context = TriggerContext(triggerId: self.id, triggerType: self.typeId)
            if isRecording {
                handler(.start(context: context))
            } else {
                handler(.stop(context: context))
            }
        }
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
