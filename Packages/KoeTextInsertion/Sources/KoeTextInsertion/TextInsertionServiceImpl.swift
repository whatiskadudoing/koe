import Foundation
import ApplicationServices
import CoreGraphics
import KoeDomain

/// Implementation of TextInsertionService for macOS
/// Uses CGEvents for character-by-character typing (requires Accessibility permission)
public final class TextInsertionServiceImpl: TextInsertionService, @unchecked Sendable {
    public init() {}

    public func insertText(_ text: String) async throws {
        // Always use CGEvents to type text - only requires accessibility permission
        let success = await insertWithCGEvents(text)
        if !success {
            throw TextInsertionError.accessibilityDenied
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

            // Small delay between characters for reliability
            Thread.sleep(forTimeInterval: 0.002)
        }

        return true
    }
}
