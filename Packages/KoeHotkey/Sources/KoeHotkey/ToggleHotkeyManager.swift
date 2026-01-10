import AppKit
import Foundation
import HotKey

/// Global hotkey manager for toggle-based recording
/// Press once to start recording, press again to stop
/// Similar to native macOS dictation (F5/microphone key behavior)
///
/// Uses SystemKeyInterceptor (CGEventTap) for system keys like F5,
/// falls back to HotKey library for regular shortcuts
public final class ToggleHotkeyManager: @unchecked Sendable {
    private var hotKey: HotKey?
    private var onToggle: (@Sendable (_ isRecording: Bool) -> Void)?

    // Toggle state - tracks whether we're currently recording
    private var isCurrentlyRecording = false

    // Configurable key code and modifiers
    // Default: F5 (the microphone key on Mac keyboards)
    private var keyCode: UInt32 = 96  // F5
    private var modifierFlags: Int = 0  // No modifiers

    // Whether we're using the system interceptor (for F5) or HotKey
    private var usingSystemInterceptor = false

    public init() {}

    /// Set the keyboard shortcut
    /// - Parameters:
    ///   - keyCode: The virtual key code (96 = F5, 49 = Space, etc.)
    ///   - modifiers: Modifier flags (1 = Command, 2 = Option, 4 = Control, 8 = Shift)
    public func setShortcut(keyCode: UInt32, modifiers: Int) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers

        // Re-register if already registered
        if let toggle = onToggle {
            unregister()
            register(onToggle: toggle)
        }
    }

    /// Check if this key code requires system-level interception
    /// F5 (mic key) needs CGEventTap to intercept before macOS
    private func requiresSystemInterceptor(_ code: UInt32) -> Bool {
        // F5 (microphone key) requires system interceptor when no modifiers
        return code == 96 && modifierFlags == 0
    }

    /// Register toggle handler
    /// - Parameter onToggle: Called with true when recording should start, false when it should stop
    public func register(onToggle: @escaping @Sendable (_ isRecording: Bool) -> Void) {
        self.onToggle = onToggle
        self.isCurrentlyRecording = false

        if requiresSystemInterceptor(keyCode) {
            registerWithSystemInterceptor()
        } else {
            registerRegularHotkey()
        }
    }

    /// Register using SystemKeyInterceptor (CGEventTap) for system keys
    private func registerWithSystemInterceptor() {
        usingSystemInterceptor = true

        let success = SystemKeyInterceptor.shared.start(
            intercepting: [Int64(keyCode)]
        ) { [weak self] _ in
            self?.toggle()
        }

        if success {
            print("ToggleHotkeyManager: Registered with SystemKeyInterceptor for key \(keyCode)")
        } else {
            print("ToggleHotkeyManager: Failed to register with SystemKeyInterceptor, falling back to HotKey")
            // Fall back to regular hotkey
            usingSystemInterceptor = false
            registerRegularHotkey()
        }
    }

    /// Register a regular hotkey (key + modifiers) using HotKey library
    private func registerRegularHotkey() {
        usingSystemInterceptor = false

        let key = keyFromCode(keyCode)

        // Convert modifier flags to NSEvent.ModifierFlags
        var modifiers: NSEvent.ModifierFlags = []
        if modifierFlags & 1 != 0 { modifiers.insert(.command) }
        if modifierFlags & 2 != 0 { modifiers.insert(.option) }
        if modifierFlags & 4 != 0 { modifiers.insert(.control) }
        if modifierFlags & 8 != 0 { modifiers.insert(.shift) }

        hotKey = HotKey(key: key, modifiers: modifiers)

        // Only respond to keyDown - this is the toggle
        hotKey?.keyDownHandler = { [weak self] in
            self?.toggle()
        }

        // Ignore keyUp - toggle doesn't need it
        hotKey?.keyUpHandler = nil

        print("ToggleHotkeyManager: Registered with HotKey library")
    }

    /// Toggle recording state and notify handler
    private func toggle() {
        isCurrentlyRecording.toggle()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onToggle?(self.isCurrentlyRecording)
        }
    }

    /// Reset recording state (call when recording is stopped externally)
    public func resetState() {
        isCurrentlyRecording = false
    }

    /// Force stop recording (useful when cancelling)
    public func forceStop() {
        if isCurrentlyRecording {
            isCurrentlyRecording = false
            onToggle?(false)
        }
    }

    /// Unregister the hotkey
    public func unregister() {
        if usingSystemInterceptor {
            SystemKeyInterceptor.shared.stop()
        }

        hotKey = nil
        isCurrentlyRecording = false
        onToggle = nil

        print("ToggleHotkeyManager: Unregistered")
    }

    /// Check if hotkey is registered
    public var isRegistered: Bool {
        if usingSystemInterceptor {
            return true  // SystemKeyInterceptor is singleton, always "registered" if started
        }
        return hotKey != nil
    }

    /// Check if currently recording
    public var isRecording: Bool {
        isCurrentlyRecording
    }

    /// Check if accessibility permission is granted (needed for F5 key)
    public static var hasRequiredPermissions: Bool {
        SystemKeyInterceptor.hasAccessibilityPermission
    }

    /// Request accessibility permission
    public static func requestPermissions() {
        SystemKeyInterceptor.requestAccessibilityPermission()
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
