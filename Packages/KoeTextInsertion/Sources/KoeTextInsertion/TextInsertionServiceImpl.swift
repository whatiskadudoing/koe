import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import KoeDomain

/// Text insertion mode
public enum TextInsertionMode: String, Sendable, CaseIterable {
    /// Type text character-by-character using CGEvents
    /// Works well for most GUI applications
    case type

    /// Paste text using clipboard (Cmd+V)
    /// More reliable for terminals and command-line applications
    case paste

    /// Use AppleScript to type text via System Events
    /// Most compatible method for terminals and CLI apps
    case appleScript
}

/// Implementation of TextInsertionService for macOS
/// Supports CGEvent typing, clipboard paste, and AppleScript methods
public final class TextInsertionServiceImpl: TextInsertionService, @unchecked Sendable {
    /// Current insertion mode - can be changed at runtime
    /// Default is appleScript for best terminal compatibility
    public var insertionMode: TextInsertionMode = .appleScript

    public init() {}

    public func insertText(_ text: String) async throws {
        guard AXIsProcessTrusted() else {
            throw TextInsertionError.accessibilityDenied
        }

        switch insertionMode {
        case .type:
            let success = await insertWithCGEvents(text)
            if !success {
                throw TextInsertionError.accessibilityDenied
            }
        case .paste:
            let success = await insertWithClipboard(text)
            if !success {
                throw TextInsertionError.clipboardPasteFailed
            }
        case .appleScript:
            let success = await insertWithAppleScript(text)
            if !success {
                // Fallback to paste method if AppleScript fails
                let pasteSuccess = await insertWithClipboard(text)
                if !pasteSuccess {
                    throw TextInsertionError.clipboardPasteFailed
                }
            }
        }
    }

    public func pressEnter() async throws {
        guard AXIsProcessTrusted() else {
            throw TextInsertionError.accessibilityDenied
        }

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                Self.pressEnterSync()
                continuation.resume()
            }
        }
    }

    public func hasPermission() -> Bool {
        // Use AXIsProcessTrusted() for silent check - does NOT trigger any prompts
        // Note: This may have caching issues but it's the only way to check without prompting
        // CGEvent.tapCreate was previously used as fallback but it triggers the accessibility dialog
        return AXIsProcessTrusted()
    }

    public func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Private Methods

    private func insertWithCGEvents(_ text: String) async -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                let result = Self.typeWithCGEventsSync(text)
                continuation.resume(returning: result)
            }
        }
    }

    /// Insert text using clipboard paste (Cmd+V)
    /// This method is more reliable for terminal applications
    private func insertWithClipboard(_ text: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let pasteboard = NSPasteboard.general

                // Save current clipboard contents
                let savedItems = pasteboard.pasteboardItems?.compactMap { item -> (String, Data)? in
                    guard let type = item.types.first,
                        let data = item.data(forType: type)
                    else {
                        return nil
                    }
                    return (type.rawValue, data)
                }

                // Set new text to clipboard
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)

                // Small delay to ensure clipboard is ready
                DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.01) {
                    // Perform Cmd+V paste
                    Self.pasteSync()

                    // Small delay before restoring clipboard
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        // Restore original clipboard contents
                        if let savedItems = savedItems, !savedItems.isEmpty {
                            pasteboard.clearContents()
                            for (typeString, data) in savedItems {
                                let type = NSPasteboard.PasteboardType(typeString)
                                pasteboard.setData(data, forType: type)
                            }
                        }
                        continuation.resume(returning: true)
                    }
                }
            }
        }
    }

    /// Insert text using AppleScript via System Events
    /// This is the most compatible method for terminal applications
    private func insertWithAppleScript(_ text: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                // Escape special characters for AppleScript string
                let escapedText =
                    text
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")

                let script = """
                    tell application "System Events"
                        keystroke "\(escapedText)"
                    end tell
                    """

                var error: NSDictionary?
                if let appleScript = NSAppleScript(source: script) {
                    appleScript.executeAndReturnError(&error)
                    if let error = error {
                        NSLog("[TextInsertion] AppleScript error: %@", error)
                        continuation.resume(returning: false)
                    } else {
                        continuation.resume(returning: true)
                    }
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Static Sync Methods (run on background thread)

    private static func typeWithCGEventsSync(_ text: String) -> Bool {
        // Use combinedSessionState for better compatibility across all application types
        // including terminals and command-line applications
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }

        for character in text {
            let str = String(character)

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
                return false
            }

            var unicodeString = [UniChar](str.utf16)
            keyDown.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: &unicodeString)
            // Use cgSessionEventTap for better terminal compatibility
            keyDown.post(tap: .cgSessionEventTap)

            // Small delay between keyDown and keyUp for reliability
            Thread.sleep(forTimeInterval: 0.001)

            guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                return false
            }

            keyUp.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: &unicodeString)
            keyUp.post(tap: .cgSessionEventTap)

            // Delay between characters for reliability
            Thread.sleep(forTimeInterval: 0.003)
        }

        return true
    }

    /// Perform Cmd+V paste keystroke
    private static func pasteSync() {
        // Use combinedSessionState for better compatibility with terminals
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        // Virtual key code for 'V' is 9
        let vKeyCode: CGKeyCode = 9

        // Key down with Command modifier
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            return
        }
        keyDown.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)

        // Small delay for reliability
        Thread.sleep(forTimeInterval: 0.001)

        // Key up with Command modifier
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cgSessionEventTap)
    }

    private static func pressEnterSync() {
        // Use combinedSessionState for better compatibility with terminals
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        // Virtual key code for Return/Enter is 36
        let returnKeyCode: CGKeyCode = 36

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: true) else {
            return
        }
        keyDown.post(tap: .cgSessionEventTap)

        // Small delay for reliability
        Thread.sleep(forTimeInterval: 0.001)

        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: false) else {
            return
        }
        keyUp.post(tap: .cgSessionEventTap)
    }
}
