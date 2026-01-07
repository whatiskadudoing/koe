import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import KoeDomain

/// Implementation of TextInsertionService for macOS
/// Uses CGEvents for character-by-character typing and clipboard+paste as fallback
public final class TextInsertionServiceImpl: TextInsertionService, @unchecked Sendable {
    public init() {}

    public func insertText(_ text: String) async throws {
        // For long text, use clipboard (instant)
        if text.count > 50 {
            try await insertWithClipboard(text)
            return
        }

        // For short text, try CGEvents (looks more natural)
        if await insertWithCGEvents(text) {
            return
        }

        // Fallback to clipboard + paste
        try await insertWithClipboard(text)
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

    private func insertWithClipboard(_ text: String) async throws {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                Self.typeWithClipboardSync(text)
                continuation.resume()
            }
        }
    }

    // MARK: - Static Sync Methods (run on background thread)

    private static func typeWithCGEventsSync(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }

        for character in text {
            let str = String(character)

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
                return false
            }

            var unicodeString = [UniChar](str.utf16)
            keyDown.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: &unicodeString)
            keyDown.post(tap: .cghidEventTap)

            guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                return false
            }

            keyUp.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: &unicodeString)
            keyUp.post(tap: .cghidEventTap)

            Thread.sleep(forTimeInterval: 0.01)
        }

        return true
    }

    private static func typeWithClipboardSync(_ text: String) {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        // Set new text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Use AppleScript to paste - more reliable than CGEvents
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }

        Thread.sleep(forTimeInterval: 0.2)

        // Restore old clipboard after a delay
        if let old = oldContents {
            Thread.sleep(forTimeInterval: 0.5)
            pasteboard.clearContents()
            pasteboard.setString(old, forType: .string)
        }
    }
}
