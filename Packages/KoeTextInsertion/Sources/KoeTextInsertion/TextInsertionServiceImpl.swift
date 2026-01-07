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
        let success = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                let result = Self.typeWithClipboardSync(text)
                continuation.resume(returning: result)
            }
        }

        if !success {
            throw TextInsertionError.clipboardPasteFailed
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

    private static func typeWithClipboardSync(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        // For very large text, split into chunks to avoid overwhelming the target app
        let chunkSize = 2000
        let chunks: [String]

        if text.count > chunkSize {
            chunks = text.chunked(into: chunkSize)
        } else {
            chunks = [text]
        }

        var success = true

        for (index, chunk) in chunks.enumerated() {
            // Set chunk to clipboard
            pasteboard.clearContents()
            let setResult = pasteboard.setString(chunk, forType: .string)

            if !setResult {
                success = false
                break
            }

            // Use AppleScript to paste - more reliable than CGEvents
            let script = """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """

            guard let appleScript = NSAppleScript(source: script) else {
                success = false
                break
            }

            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)

            if error != nil {
                success = false
                break
            }

            // Scale delay based on chunk size - give target app time to process
            // Base delay of 100ms + 50ms per 500 characters
            let baseDelay = 0.1
            let additionalDelay = Double(chunk.count) / 500.0 * 0.05
            let totalDelay = min(baseDelay + additionalDelay, 0.5) // Cap at 500ms per chunk

            Thread.sleep(forTimeInterval: totalDelay)

            // Add extra delay between chunks to let target app settle
            if index < chunks.count - 1 {
                Thread.sleep(forTimeInterval: 0.15)
            }
        }

        // Restore old clipboard after a delay
        Thread.sleep(forTimeInterval: 0.3)
        pasteboard.clearContents()
        if let old = oldContents {
            pasteboard.setString(old, forType: .string)
        }

        return success
    }
}

// MARK: - String Extension for Chunking

private extension String {
    func chunked(into size: Int) -> [String] {
        var chunks: [String] = []
        var currentIndex = startIndex

        while currentIndex < endIndex {
            let endIndex = index(currentIndex, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[currentIndex..<endIndex]))
            currentIndex = endIndex
        }

        return chunks
    }
}
