import HotKey
import AppKit
import KoeDomain

/// Global hotkey manager for Koe
/// Handles configurable push-to-talk recording shortcuts
public final class KoeHotkeyManager: HotkeyService {
    private var hotKey: HotKey?
    private var onKeyDown: (@Sendable () -> Void)?
    private var onKeyUp: (@Sendable () -> Void)?

    // Configurable key code and modifiers
    private var keyCode: UInt32 = 49  // Space
    private var modifierFlags: Int = 2  // Option

    public init() {}

    /// Set the keyboard shortcut
    /// - Parameters:
    ///   - keyCode: The virtual key code (49 = Space, 36 = Return, etc.)
    ///   - modifiers: Modifier flags (1 = Command, 2 = Option, 4 = Control, 8 = Shift)
    public func setShortcut(keyCode: UInt32, modifiers: Int) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers

        // Re-register if already registered
        if let down = onKeyDown, let up = onKeyUp {
            unregister()
            register(onKeyDown: down, onKeyUp: up)
        }
    }

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

        // Convert key code to Key enum
        let key = keyFromCode(keyCode)

        // Convert modifier flags to NSEvent.ModifierFlags
        var modifiers: NSEvent.ModifierFlags = []
        if modifierFlags & 1 != 0 { modifiers.insert(.command) }
        if modifierFlags & 2 != 0 { modifiers.insert(.option) }
        if modifierFlags & 4 != 0 { modifiers.insert(.control) }
        if modifierFlags & 8 != 0 { modifiers.insert(.shift) }

        hotKey = HotKey(key: key, modifiers: modifiers)

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

    /// Convert virtual key code to HotKey's Key enum
    private func keyFromCode(_ code: UInt32) -> Key {
        switch code {
        case 49: return .space
        case 36: return .return
        case 48: return .tab
        case 51: return .delete
        case 53: return .escape
        case 96: return .f5
        case 97: return .f6
        case 98: return .f7
        case 99: return .f3
        case 100: return .f8
        case 101: return .f9
        case 109: return .f10
        case 103: return .f11
        case 111: return .f12
        // Letter keys
        case 0: return .a
        case 1: return .s
        case 2: return .d
        case 3: return .f
        case 5: return .g
        case 4: return .h
        case 38: return .j
        case 40: return .k
        case 37: return .l
        case 6: return .z
        case 7: return .x
        case 8: return .c
        case 9: return .v
        case 11: return .b
        case 45: return .n
        case 46: return .m
        case 12: return .q
        case 13: return .w
        case 14: return .e
        case 15: return .r
        case 17: return .t
        case 16: return .y
        case 32: return .u
        case 34: return .i
        case 31: return .o
        case 35: return .p
        default: return .space
        }
    }
}
