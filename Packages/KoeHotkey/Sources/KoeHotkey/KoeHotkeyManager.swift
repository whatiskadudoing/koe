import AppKit
import KoeDomain

/// Global hotkey manager for Koe
/// Supports fn-based push-to-talk shortcuts using CGEventTap
///
/// Two modes:
/// - fn alone (keyCode 63): Hold fn for 0.3s+ to record, release to stop
/// - fn+Space (keyCode 49): Toggle mode - fn+Space to start, fn+Space again to stop, any other key to cancel
public final class KoeHotkeyManager: HotkeyService {
    private var onKeyDown: (@Sendable () -> Void)?
    private var onKeyUp: (@Sendable () -> Void)?
    private var onCancel: (@Sendable () -> Void)?

    // Configuration: keyCode 63 = fn alone, keyCode 49 = fn+Space
    private var keyCode: UInt32 = 63

    // CGEventTap for fn key detection
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // State tracking
    private var isFnHeld = false
    private var isRecording = false

    // For fn alone: hold threshold to distinguish tap from hold
    private var fnPressTime: Date?
    private var fnHoldTimer: Timer?
    private let fnHoldThreshold: TimeInterval = 0.3

    public init() {}

    /// Set the keyboard shortcut
    /// - keyCode 63: fn alone (hold to record)
    /// - keyCode 49: fn+Space (toggle mode)
    public func setShortcut(keyCode: UInt32, modifiers _: Int) {
        self.keyCode = keyCode

        // Re-register if already registered
        if let down = onKeyDown, let up = onKeyUp, let cancel = onCancel {
            unregister()
            register(onKeyDown: down, onKeyUp: up, onCancel: cancel)
        }
    }

    /// Register hotkey handlers
    public func register(
        onKeyDown: @escaping @Sendable () -> Void,
        onKeyUp: @escaping @Sendable () -> Void,
        onCancel: @escaping @Sendable () -> Void
    ) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        self.onCancel = onCancel

        guard AXIsProcessTrusted() else {
            NSLog("[KoeHotkey] Accessibility permission required")
            return
        }

        // Create event tap for flagsChanged (fn key) and keyDown/keyUp (space and other keys)
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                    guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                    let manager = Unmanaged<KoeHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                    return manager.handleEvent(type: type, event: event)
                },
                userInfo: refcon
            )
        else {
            NSLog("[KoeHotkey] Failed to create event tap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    /// Handle keyboard events
    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if system disabled it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        // Handle fn key state changes
        if type == .flagsChanged {
            let fnHeld = event.flags.contains(.maskSecondaryFn)

            if fnHeld != isFnHeld {
                isFnHeld = fnHeld

                if keyCode == 63 {
                    // fn alone mode: use hold threshold
                    handleFnAlone(fnHeld: fnHeld)
                }
                // fn+Space mode: fn state doesn't directly control recording
            }
        }

        // Handle key events for fn+Space mode
        if keyCode == 49 {
            if type == .keyDown {
                let key = event.getIntegerValueField(.keyboardEventKeycode)
                let fnInEvent = event.flags.contains(.maskSecondaryFn)

                // fn+Space pressed
                if key == 49, (isFnHeld || fnInEvent) {
                    if !isRecording {
                        // Start recording
                        startRecording()
                    } else {
                        // Stop recording (process pipeline)
                        stopRecording()
                    }
                    return nil  // Swallow space
                }

                // Any other key while recording = cancel
                if isRecording {
                    cancelRecording()
                    // Don't swallow the key - let it through
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    /// Handle fn alone mode with hold threshold
    private func handleFnAlone(fnHeld: Bool) {
        if fnHeld {
            // fn pressed - start hold timer
            fnPressTime = Date()
            fnHoldTimer?.invalidate()
            fnHoldTimer = Timer.scheduledTimer(withTimeInterval: fnHoldThreshold, repeats: false) {
                [weak self] _ in
                guard let self = self, self.isFnHeld else { return }
                self.startRecording()
            }
        } else {
            // fn released
            fnHoldTimer?.invalidate()
            fnHoldTimer = nil
            fnPressTime = nil

            if isRecording {
                stopRecording()
            }
        }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        DispatchQueue.main.async { [weak self] in
            self?.onKeyDown?()
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        DispatchQueue.main.async { [weak self] in
            self?.onKeyUp?()
        }
    }

    private func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        DispatchQueue.main.async { [weak self] in
            self?.onCancel?()
        }
    }

    /// Unregister the hotkey
    public func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }

        fnHoldTimer?.invalidate()
        fnHoldTimer = nil
        fnPressTime = nil
        isFnHeld = false
        isRecording = false
        onKeyDown = nil
        onKeyUp = nil
        onCancel = nil
    }

    /// Check if hotkey is registered
    public var isRegistered: Bool {
        eventTap != nil
    }
}
