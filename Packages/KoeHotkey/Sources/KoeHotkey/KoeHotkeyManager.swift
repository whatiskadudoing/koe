import AppKit
import HotKey
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

    // For modifier-only keys (like Right Option)
    private var flagsMonitor: Any?
    private var modifierPressTime: Date?
    private var holdTimer: Timer?
    private var isModifierHeld = false
    private let holdThreshold: TimeInterval = 0.2  // 200ms hold required

    public init() {}

    /// Set the keyboard shortcut
    /// - Parameters:
    ///   - keyCode: The virtual key code (49 = Space, 36 = Return, 61 = Right Option, etc.)
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

    /// Check if the key code is a modifier-only key
    private func isModifierOnlyKey(_ code: UInt32) -> Bool {
        // 61 = Right Option, 58 = Right Command, 60 = Right Shift, 62 = Right Control
        // 55 = Left Command, 56 = Left Shift, 58 = Left Option, 59 = Left Control
        return code == 61 || code == 58 || code == 60 || code == 62 || code == 55 || code == 56 || code == 59
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

        if isModifierOnlyKey(keyCode) {
            registerModifierOnlyKey()
        } else {
            registerRegularHotkey()
        }
    }

    /// Register a regular hotkey (key + modifiers)
    private func registerRegularHotkey() {
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

    /// Register a modifier-only key (like Right Option)
    private func registerModifierOnlyKey() {
        // Use global event monitor for flagsChanged events
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Also monitor local events (when app is focused)
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        // Store local monitor reference (we'll use flagsMonitor for cleanup)
        if flagsMonitor != nil {
            // Create a combined cleanup by storing both
            let globalMonitor = flagsMonitor
            flagsMonitor = (globalMonitor, localMonitor) as AnyObject
        }
    }

    /// Handle flagsChanged events for modifier-only keys
    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags

        // Check if our specific modifier key is pressed
        let isPressed: Bool
        switch keyCode {
        case 61:  // Right Option
            isPressed = flags.contains(.option) && event.keyCode == 61
        case 58:  // Right Command (note: keyCode for right command)
            isPressed = flags.contains(.command)
        case 60:  // Right Shift
            isPressed = flags.contains(.shift)
        case 62:  // Right Control
            isPressed = flags.contains(.control)
        default:
            isPressed = false
        }

        // For Right Option, we need to check if option is currently held
        // and distinguish between press and release
        if keyCode == 61 {
            let optionHeld = flags.contains(.option)

            if optionHeld && !isModifierHeld {
                // Option key just pressed - start hold timer
                modifierPressTime = Date()
                isModifierHeld = true

                // Start timer to check for hold threshold
                holdTimer?.invalidate()
                holdTimer = Timer.scheduledTimer(withTimeInterval: holdThreshold, repeats: false) { [weak self] _ in
                    guard let self = self, self.isModifierHeld else { return }
                    // Held long enough - trigger key down
                    DispatchQueue.main.async {
                        self.onKeyDown?()
                    }
                }
            } else if !optionHeld && isModifierHeld {
                // Option key released
                isModifierHeld = false
                holdTimer?.invalidate()
                holdTimer = nil

                // Only trigger key up if we had triggered key down (held long enough)
                if let pressTime = modifierPressTime,
                    Date().timeIntervalSince(pressTime) >= holdThreshold
                {
                    DispatchQueue.main.async { [weak self] in
                        self?.onKeyUp?()
                    }
                }
                modifierPressTime = nil
            }
        }
    }

    /// Unregister the hotkey
    public func unregister() {
        hotKey = nil

        // Clean up modifier key monitoring
        if let monitor = flagsMonitor {
            if let tuple = monitor as? (Any?, Any?) {
                if let global = tuple.0 { NSEvent.removeMonitor(global) }
                if let local = tuple.1 { NSEvent.removeMonitor(local) }
            } else {
                NSEvent.removeMonitor(monitor)
            }
            flagsMonitor = nil
        }

        holdTimer?.invalidate()
        holdTimer = nil
        isModifierHeld = false
        modifierPressTime = nil

        onKeyDown = nil
        onKeyUp = nil
    }

    /// Check if hotkey is registered
    public var isRegistered: Bool {
        hotKey != nil || flagsMonitor != nil
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
