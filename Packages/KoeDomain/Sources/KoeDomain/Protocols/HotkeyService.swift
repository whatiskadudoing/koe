import Foundation

/// Hotkey service - MUST run on client
public protocol HotkeyService: Sendable {
    /// Register hotkey handlers
    /// - onKeyDown: Called when recording should start
    /// - onKeyUp: Called when recording should stop and process
    /// - onCancel: Called when recording should be cancelled (discarded)
    func register(
        onKeyDown: @escaping @Sendable () -> Void,
        onKeyUp: @escaping @Sendable () -> Void,
        onCancel: @escaping @Sendable () -> Void
    )

    /// Unregister hotkey
    func unregister()
}
