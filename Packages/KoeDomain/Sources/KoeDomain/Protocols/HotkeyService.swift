import Foundation

/// Hotkey service - MUST run on client
public protocol HotkeyService: Sendable {
    /// Register hotkey handlers
    func register(
        onKeyDown: @escaping @Sendable () -> Void,
        onKeyUp: @escaping @Sendable () -> Void
    )

    /// Unregister hotkey
    func unregister()
}
