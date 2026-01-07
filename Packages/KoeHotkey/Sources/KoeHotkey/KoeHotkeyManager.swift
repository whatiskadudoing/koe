import HotKey
import AppKit
import KoeDomain

/// Global hotkey manager for Koe
/// Handles Option+Space for push-to-talk recording
public final class KoeHotkeyManager: HotkeyService {
    private var hotKey: HotKey?
    private var onKeyDown: (@Sendable () -> Void)?
    private var onKeyUp: (@Sendable () -> Void)?

    public init() {}

    /// Register hotkey handlers
    /// - Parameters:
    ///   - onKeyDown: Called when hotkey is pressed (start recording)
    ///   - onKeyUp: Called when hotkey is released (stop recording)
    public func register(
        onKeyDown: @escaping @Sendable () -> Void,
        onKeyUp: @escaping @Sendable () -> Void
    ) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp

        // Option + Space
        hotKey = HotKey(key: .space, modifiers: [.option])

        hotKey?.keyDownHandler = { [weak self] in
            self?.onKeyDown?()
        }

        hotKey?.keyUpHandler = { [weak self] in
            self?.onKeyUp?()
        }
    }

    /// Unregister the hotkey
    public func unregister() {
        hotKey = nil
        onKeyDown = nil
        onKeyUp = nil
    }

    /// Check if hotkey is registered
    public var isRegistered: Bool {
        hotKey != nil
    }
}
