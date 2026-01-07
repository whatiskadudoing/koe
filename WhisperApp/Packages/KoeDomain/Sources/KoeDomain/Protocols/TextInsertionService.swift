import Foundation

/// Text insertion service - MUST run on client (accessibility)
public protocol TextInsertionService: Sendable {
    /// Insert text at current cursor position
    func insertText(_ text: String) async throws

    /// Check if accessibility permission is granted
    func hasPermission() -> Bool

    /// Request accessibility permission
    func requestPermission()
}
