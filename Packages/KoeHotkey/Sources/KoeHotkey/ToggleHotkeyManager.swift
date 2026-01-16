import AppKit
import Foundation
import HotKey

/// Global hotkey manager for toggle-based recording
/// Press once to start recording, press again to stop
/// Similar to native macOS dictation (F5/microphone key behavior)
///
/// Supports multiple trigger modes:
/// - F5 (microphone key): Uses SystemKeyInterceptor
/// - fn alone: Uses CGEventTap to detect fn key
/// - fn+Space: Uses CGEventTap to detect fn modifier + Space
/// - Regular hotkeys: Uses HotKey library
public final class ToggleHotkeyManager: @unchecked Sendable {
    private var hotKey: HotKey?
    private var onToggle: (@Sendable (_ isRecording: Bool) -> Void)?
    private var onCancel: (@Sendable () -> Void)?

    // Toggle state - tracks whether we're currently recording
    private var isCurrentlyRecording = false

    // Configurable key code and modifiers
    // Default: F5 (the microphone key on Mac keyboards)
    private var keyCode: UInt32 = 96  // F5
    private var modifierFlags: Int = 0  // No modifiers

    // Registration mode tracking
    private var usingSystemInterceptor = false
    private var usingFnEventTap = false

    // CGEventTap for fn-based shortcuts
    private var fnEventTap: CFMachPort?
    private var fnRunLoopSource: CFRunLoopSource?
    private var isFnHeld = false

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

    /// Check if this key code requires fn-based event tap
    /// fn alone (63) and fn+Space (49 with fn modifier flag 16) need CGEventTap
    private func requiresFnEventTap(_ code: UInt32) -> Bool {
        // fn alone (Globe key)
        if code == 63 { return true }
        // fn+Space (Space key with fn modifier)
        if code == 49 && modifierFlags == 16 { return true }
        return false
    }

    /// Register toggle handler
    /// - Parameters:
    ///   - onToggle: Called with true when recording should start, false when it should stop
    ///   - onCancel: Called when recording is cancelled (via Escape key)
    public func register(
        onToggle: @escaping @Sendable (_ isRecording: Bool) -> Void,
        onCancel: @escaping @Sendable () -> Void = {}
    ) {
        self.onToggle = onToggle
        self.onCancel = onCancel
        self.isCurrentlyRecording = false

        if requiresSystemInterceptor(keyCode) {
            registerWithSystemInterceptor()
        } else if requiresFnEventTap(keyCode) {
            registerWithFnEventTap()
        } else {
            registerRegularHotkey()
        }
    }

    /// Register using CGEventTap for fn-based shortcuts (fn alone or fn+Space)
    private func registerWithFnEventTap() {
        usingFnEventTap = true
        usingSystemInterceptor = false

        guard AXIsProcessTrusted() else {
            print("ToggleHotkeyManager: Accessibility permission required for fn key")
            return
        }

        // Create event tap for flagsChanged (fn key) and keyDown (Space key)
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                    guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                    let manager = Unmanaged<ToggleHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                    return manager.handleFnEvent(type: type, event: event)
                },
                userInfo: refcon
            )
        else {
            print("ToggleHotkeyManager: Failed to create fn event tap")
            return
        }

        fnEventTap = tap
        fnRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = fnRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        print("ToggleHotkeyManager: Registered with fn event tap for key \(keyCode)")
    }

    /// Handle fn-based events
    private func handleFnEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if system disabled it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = fnEventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        // Track fn key state
        if type == .flagsChanged {
            let fnHeld = event.flags.contains(.maskSecondaryFn)
            if fnHeld != isFnHeld {
                isFnHeld = fnHeld

                // fn alone mode: toggle on fn press
                if keyCode == 63 && fnHeld {
                    toggle()
                    return nil  // Consume the event
                }
            }
        }

        // fn+Space mode: toggle on Space press while fn is held
        if keyCode == 49 && type == .keyDown {
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            let fnInEvent = event.flags.contains(.maskSecondaryFn)

            if key == 49 && (isFnHeld || fnInEvent) {
                toggle()
                return nil  // Consume the Space key
            }
        }

        return Unmanaged.passRetained(event)
    }

    /// Register using SystemKeyInterceptor (CGEventTap) for system keys
    private func registerWithSystemInterceptor() {
        usingSystemInterceptor = true
        usingFnEventTap = false

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

        // Start/stop escape cancel interceptor based on recording state
        if isCurrentlyRecording {
            EscapeCancelInterceptor.shared.start { [weak self] in
                self?.cancel()
            }
        } else {
            EscapeCancelInterceptor.shared.stop()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onToggle?(self.isCurrentlyRecording)
        }
    }

    /// Cancel recording and reset state
    private func cancel() {
        guard isCurrentlyRecording else { return }
        isCurrentlyRecording = false
        EscapeCancelInterceptor.shared.stop()
        DispatchQueue.main.async { [weak self] in
            self?.onCancel?()
        }
    }

    /// Reset recording state (call when recording is stopped externally)
    public func resetState() {
        isCurrentlyRecording = false
        EscapeCancelInterceptor.shared.stop()
    }

    /// Force stop recording (useful when cancelling)
    public func forceStop() {
        if isCurrentlyRecording {
            isCurrentlyRecording = false
            EscapeCancelInterceptor.shared.stop()
            onToggle?(false)
        }
    }

    /// Unregister the hotkey
    public func unregister() {
        if usingSystemInterceptor {
            SystemKeyInterceptor.shared.stop()
        }

        // Clean up fn event tap if used
        if usingFnEventTap {
            if let tap = fnEventTap {
                CGEvent.tapEnable(tap: tap, enable: false)
                if let source = fnRunLoopSource {
                    CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                }
            }
            fnEventTap = nil
            fnRunLoopSource = nil
            isFnHeld = false
            usingFnEventTap = false
        }

        EscapeCancelInterceptor.shared.stop()
        hotKey = nil
        isCurrentlyRecording = false
        onToggle = nil
        onCancel = nil

        print("ToggleHotkeyManager: Unregistered")
    }

    /// Check if hotkey is registered
    public var isRegistered: Bool {
        if usingSystemInterceptor {
            return true  // SystemKeyInterceptor is singleton, always "registered" if started
        }
        if usingFnEventTap {
            return fnEventTap != nil
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
