import SwiftUI

/// Keyboard key cap display component
public struct KeyCap: View {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundColor(KoeColors.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(KoeColors.surface)
            .cornerRadius(4)
    }
}

/// Hotkey hint display (e.g., "⌥ space")
public struct HotkeyHint: View {
    public let keys: [String]

    public init(keys: [String] = ["⌥", "space"]) {
        self.keys = keys
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                KeyCap(key)
            }
        }
    }
}
