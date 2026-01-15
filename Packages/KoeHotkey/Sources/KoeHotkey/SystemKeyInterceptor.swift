import AppKit
import CoreGraphics
import Foundation

/// Intercepts system-level keys (like the 🎤 microphone key) using CGEventTap
/// This allows capturing keys BEFORE macOS processes them, preventing system dialogs
///
/// Requires:
/// - Accessibility permission (System Settings → Privacy & Security → Accessibility)
/// - Input Monitoring permission (System Settings → Privacy & Security → Input Monitoring)
public final class SystemKeyInterceptor: @unchecked Sendable {
    /// Singleton instance - CGEventTap should only be created once
    public static let shared = SystemKeyInterceptor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Key codes to intercept
    private var interceptedKeyCodes: Set<Int64> = []

    // Callback when an intercepted key is pressed
    private var onKeyDown: ((_ keyCode: Int64) -> Void)?

    // Track key state for toggle behavior
    private var keyStates: [Int64: Bool] = [:]

    private init() {}

    /// Check if the app has the required permissions
    public static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Request accessibility permission (opens System Settings)
    public static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Start intercepting specified key codes
    /// - Parameters:
    ///   - keyCodes: Set of virtual key codes to intercept (e.g., 96 for F5/mic key)
    ///   - onKeyDown: Called when an intercepted key is pressed
    /// - Returns: true if successful, false if failed (usually permissions)
    @discardableResult
    public func start(intercepting keyCodes: Set<Int64>, onKeyDown: @escaping (_ keyCode: Int64) -> Void) -> Bool {
        // Check permissions first
        guard SystemKeyInterceptor.hasAccessibilityPermission else {
            print("SystemKeyInterceptor: Missing Accessibility permission")
            SystemKeyInterceptor.requestAccessibilityPermission()
            return false
        }

        // Stop any existing tap
        stop()

        self.interceptedKeyCodes = keyCodes
        self.onKeyDown = onKeyDown

        // Create event tap at session level to intercept before system
        // We want keyDown events
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        // Create the tap - use a static callback that routes to our instance
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,  // Session level - intercepts before most system handling
                place: .headInsertEventTap,  // Insert at head to be first
                options: .defaultTap,  // Can modify/consume events
                eventsOfInterest: eventMask,
                callback: systemKeyCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            print("SystemKeyInterceptor: Failed to create event tap")
            return false
        }

        self.eventTap = tap

        // Create run loop source and add to current run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

        // Enable the tap
        CGEvent.tapEnable(tap: tap, enable: true)

        print("SystemKeyInterceptor: Started intercepting keys: \(keyCodes)")
        return true
    }

    /// Stop intercepting keys
    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        eventTap = nil
        interceptedKeyCodes = []
        onKeyDown = nil
        keyStates = [:]

        print("SystemKeyInterceptor: Stopped")
    }

    /// Called from the C callback
    fileprivate func handleEvent(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        // Handle tap being disabled by timeout
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Re-enable the tap
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return event
        }

        // Get the key code
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Check if this is a key we're intercepting
        guard interceptedKeyCodes.contains(keyCode) else {
            return event  // Pass through unmodified
        }

        // Handle key down
        if type == .keyDown {
            // Prevent key repeat - only trigger on initial press
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !isRepeat {
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyDown?(keyCode)
                }
            }

            // Return nil to CONSUME the event - prevent macOS from seeing it
            return nil
        }

        // Also consume keyUp for intercepted keys to prevent any system handling
        if type == .keyUp {
            return nil
        }

        return event
    }

    deinit {
        stop()
    }
}

/// C callback function for CGEventTap
private func systemKeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }

    let interceptor = Unmanaged<SystemKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

    if let resultEvent = interceptor.handleEvent(proxy, type, event) {
        return Unmanaged.passRetained(resultEvent)
    } else {
        // Return nil to consume the event
        return nil
    }
}

// MARK: - Key Codes Reference

extension SystemKeyInterceptor {
    /// Common key codes for reference
    public enum KeyCode: Int64 {
        case f1 = 122
        case f2 = 120
        case f3 = 99
        case f4 = 118
        case f5 = 96  // 🎤 Microphone key on newer MacBooks
        case f6 = 97
        case f7 = 98
        case f8 = 100
        case f9 = 101
        case f10 = 109
        case f11 = 103
        case f12 = 111
        case space = 49
        case returnKey = 36
        case escape = 53
    }
}
