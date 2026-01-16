import AppKit
import CoreGraphics
import Foundation

/// Intercepts the Escape key to cancel recording
/// This provides a universal cancel mechanism that works with all trigger types
///
/// Usage:
/// - Call `start(onCancel:)` when recording starts
/// - Call `stop()` when recording ends
/// - The onCancel callback is invoked when Escape is pressed
public final class EscapeCancelInterceptor: @unchecked Sendable {
    /// Singleton instance - CGEventTap should only be created once
    public static let shared = EscapeCancelInterceptor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onCancel: (() -> Void)?
    private var isActive = false

    /// Escape key code
    private let escapeKeyCode: Int64 = 53

    private init() {}

    /// Start intercepting Escape key
    /// - Parameter onCancel: Called when Escape is pressed during recording
    /// - Returns: true if started successfully
    @discardableResult
    public func start(onCancel: @escaping () -> Void) -> Bool {
        // Don't start if already active
        guard !isActive else { return true }

        // Check permissions
        guard AXIsProcessTrusted() else {
            print("EscapeCancelInterceptor: Missing Accessibility permission")
            return false
        }

        self.onCancel = onCancel

        // Create event tap for keyDown events
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                    guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                    let interceptor = Unmanaged<EscapeCancelInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                    return interceptor.handleEvent(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            print("EscapeCancelInterceptor: Failed to create event tap")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        isActive = true
        print("EscapeCancelInterceptor: Started")
        return true
    }

    /// Stop intercepting Escape key
    public func stop() {
        guard isActive else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }

        onCancel = nil
        isActive = false
        print("EscapeCancelInterceptor: Stopped")
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if system disabled it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        // Only handle keyDown for Escape
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            if keyCode == escapeKeyCode {
                // Escape pressed - trigger cancel
                DispatchQueue.main.async { [weak self] in
                    self?.onCancel?()
                }

                // Consume the event to prevent it from reaching other apps
                return nil
            }
        }

        // Pass through all other events
        return Unmanaged.passRetained(event)
    }

    deinit {
        stop()
    }
}
