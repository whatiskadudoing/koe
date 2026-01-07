import Foundation

public enum TextInsertionError: KoeError {
    case accessibilityDenied
    case insertionFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return "Accessibility access denied. Please enable in System Settings."
        case .insertionFailed(let error):
            return "Text insertion failed: \(error.localizedDescription)"
        }
    }
}
