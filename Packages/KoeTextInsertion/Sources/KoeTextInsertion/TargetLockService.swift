import AppKit
import ApplicationServices
import Foundation

/// Captures and restores focus to a specific text field across application switches.
/// Uses macOS Accessibility APIs to lock onto a target input field.
public final class TargetLockService: @unchecked Sendable {
    // MARK: - Shared Instance

    public static let shared = TargetLockService()

    // MARK: - Target State

    private var lockedElement: AXUIElement?
    private var lockedApp: NSRunningApplication?
    private var lockedAppElement: AXUIElement?
    private var isValueSettable: Bool = false

    /// Whether a target is currently locked
    public var hasLockedTarget: Bool {
        lockedElement != nil
    }

    /// Bundle identifier of the locked app (for debugging)
    public var lockedAppBundleId: String? {
        lockedApp?.bundleIdentifier
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Target Locking

    /// Capture the currently focused text element as the insertion target.
    /// Call this when recording starts.
    /// - Returns: True if a target was successfully captured
    @discardableResult
    public func lockCurrentTarget() -> Bool {
        // Clear previous target
        clearTarget()

        guard AXIsProcessTrusted() else {
            NSLog("[TargetLock] Accessibility not trusted, cannot lock target")
            return false
        }

        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            NSLog("[TargetLock] No frontmost application")
            return false
        }

        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Get the focused UI element within the app
        var focusedValue: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard focusResult == .success, let focused = focusedValue else {
            NSLog("[TargetLock] Could not get focused element: \(focusResult.rawValue)")
            return false
        }

        let focusedElement = focused as! AXUIElement

        // Check if this element accepts text input (has AXValue attribute that's settable)
        var settable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(
            focusedElement,
            kAXValueAttribute as CFString,
            &settable
        )

        if settableResult == .success {
            isValueSettable = settable.boolValue
        } else {
            isValueSettable = false
        }

        // Get role to log what type of element we captured
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute as CFString, &roleValue)
        let role = (roleValue as? String) ?? "unknown"

        // Store the locked target
        lockedElement = focusedElement
        lockedApp = frontApp
        lockedAppElement = appElement

        NSLog(
            "[TargetLock] Locked target: app=\(frontApp.bundleIdentifier ?? "unknown"), role=\(role), valueSettable=\(isValueSettable)"
        )

        return true
    }

    /// Clear the locked target.
    /// Call this after text insertion completes or is cancelled.
    public func clearTarget() {
        lockedElement = nil
        lockedApp = nil
        lockedAppElement = nil
        isValueSettable = false
    }

    // MARK: - Target Validation

    /// Check if the locked target is still valid and can receive text.
    /// - Returns: True if target is valid and focus can be restored
    public func canRestoreTarget() -> Bool {
        guard let element = lockedElement,
            let app = lockedApp
        else {
            NSLog("[TargetLock] No locked target")
            return false
        }

        // Check if the app is still running
        guard app.isTerminated == false else {
            NSLog("[TargetLock] Locked app has terminated")
            return false
        }

        // Try to get a simple attribute to verify element is still valid
        var roleValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)

        if result == .success {
            return true
        } else if result == .invalidUIElement {
            NSLog("[TargetLock] Element is no longer valid (UI may have rebuilt)")
            return false
        } else {
            NSLog("[TargetLock] Could not validate element: \(result.rawValue)")
            return false
        }
    }

    // MARK: - Focus Restoration

    /// Attempt to restore focus to the locked target.
    /// - Returns: True if focus was successfully restored
    public func restoreFocus() -> Bool {
        guard let element = lockedElement,
            let app = lockedApp,
            let appElement = lockedAppElement
        else {
            return false
        }

        // First, bring the app to the foreground
        let activated = app.activate(options: [])
        if !activated {
            NSLog("[TargetLock] Could not activate app")
            return false
        }

        // Small delay to let the app come to front
        Thread.sleep(forTimeInterval: 0.05)

        // Try to set the focused element on the app
        let setFocusResult = AXUIElementSetAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            element
        )

        if setFocusResult == .success {
            NSLog("[TargetLock] Successfully restored focus to locked element")
            return true
        }

        // Fallback: try setting kAXFocusedAttribute on the element itself
        let setFocusedResult = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )

        if setFocusedResult == .success {
            NSLog("[TargetLock] Restored focus via kAXFocusedAttribute")
            return true
        }

        NSLog(
            "[TargetLock] Could not restore focus: setFocusedUIElement=\(setFocusResult.rawValue), setFocused=\(setFocusedResult.rawValue)"
        )
        return false
    }

    // MARK: - Direct Value Setting

    /// Attempt to set text directly on the locked element (bypasses typing).
    /// - Parameter text: The text to set
    /// - Returns: True if text was successfully set
    public func setValueDirectly(_ text: String) -> Bool {
        guard let element = lockedElement, isValueSettable else {
            return false
        }

        // Get current value first to append
        var currentValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue)
        let currentText = (currentValue as? String) ?? ""

        // Append new text to existing content
        let newValue = currentText + text

        let result = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            newValue as CFString
        )

        if result == .success {
            NSLog("[TargetLock] Set value directly on element")
            return true
        } else {
            NSLog("[TargetLock] Could not set value: \(result.rawValue)")
            return false
        }
    }

    // MARK: - Combined Restore and Insert

    /// Result of attempting to restore focus for text insertion
    public enum RestoreResult {
        /// Focus is already on the correct target (same app focused)
        case alreadyFocused
        /// Successfully restored focus to the locked target
        case restored
        /// Could not restore focus - insertion should be skipped
        case failed(reason: String)
    }

    /// Check if focus needs to be restored and attempt to restore if needed.
    /// - Returns: RestoreResult indicating the outcome
    public func prepareForInsertion() -> RestoreResult {
        guard let lockedApp = lockedApp else {
            return .failed(reason: "No locked target")
        }

        // Check if we're still in the same app
        if let currentApp = NSWorkspace.shared.frontmostApplication,
            currentApp.processIdentifier == lockedApp.processIdentifier
        {
            // Same app - check if element is still valid
            if canRestoreTarget() {
                return .alreadyFocused
            } else {
                return .failed(reason: "Target element is no longer valid")
            }
        }

        // Different app - need to restore
        if !canRestoreTarget() {
            return .failed(reason: "Target is no longer valid")
        }

        if restoreFocus() {
            return .restored
        } else {
            return .failed(reason: "Could not restore focus to target app")
        }
    }
}
