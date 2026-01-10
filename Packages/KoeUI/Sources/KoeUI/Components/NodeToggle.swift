import SwiftUI

/// A reusable mini toggle switch for pipeline nodes
/// Provides reliable single-click toggle with clear visual feedback
public struct NodeToggle: View {
    @Binding public var isOn: Bool
    public var size: CGFloat = 16
    public var onColor: Color = .green
    public var offColor: Color = KoeColors.textLighter
    public var showBackground: Bool = true
    public var onToggle: (() -> Void)?

    @State private var isPressed = false

    public init(
        isOn: Binding<Bool>,
        size: CGFloat = 16,
        onColor: Color = .green,
        offColor: Color = KoeColors.textLighter,
        showBackground: Bool = true,
        onToggle: (() -> Void)? = nil
    ) {
        self._isOn = isOn
        self.size = size
        self.onColor = onColor
        self.offColor = offColor
        self.showBackground = showBackground
        self.onToggle = onToggle
    }

    public var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isOn.toggle()
            }
            onToggle?()
        } label: {
            ZStack {
                // Background track
                Capsule()
                    .fill(isOn ? onColor.opacity(0.3) : offColor.opacity(0.2))
                    .frame(width: size * 1.8, height: size)

                // Knob
                Circle()
                    .fill(isOn ? onColor : offColor)
                    .frame(width: size * 0.75, height: size * 0.75)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    .offset(x: isOn ? size * 0.35 : -size * 0.35)
            }
            .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(
            minimumDuration: 0,
            pressing: { pressing in
                withAnimation(.easeOut(duration: 0.1)) {
                    isPressed = pressing
                }
            }, perform: {})
    }
}

/// A compact toggle indicator (just a dot, no track)
/// For use in tight spaces like node corners
public struct NodeToggleIndicator: View {
    @Binding public var isOn: Bool
    public var size: CGFloat = 10
    public var onColor: Color = .green
    public var offColor: Color = KoeColors.textLighter
    public var onToggle: (() -> Void)?

    @State private var isPressed = false
    @State private var isHovered = false

    public init(
        isOn: Binding<Bool>,
        size: CGFloat = 10,
        onColor: Color = .green,
        offColor: Color = KoeColors.textLighter,
        onToggle: (() -> Void)? = nil
    ) {
        self._isOn = isOn
        self.size = size
        self.onColor = onColor
        self.offColor = offColor
        self.onToggle = onToggle
    }

    public var body: some View {
        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                isOn.toggle()
            }
            onToggle?()
        } label: {
            Circle()
                .fill(isOn ? onColor : offColor)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(isOn ? onColor.opacity(0.5) : Color.clear, lineWidth: 2)
                        .frame(width: size + 4, height: size + 4)
                        .opacity(isHovered ? 1 : 0)
                )
                .scaleEffect(isPressed ? 0.85 : (isHovered ? 1.15 : 1.0))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onLongPressGesture(
            minimumDuration: 0,
            pressing: { pressing in
                withAnimation(.easeOut(duration: 0.1)) {
                    isPressed = pressing
                }
            }, perform: {}
        )
        .help(isOn ? "Click to disable" : "Click to enable")
    }
}

// MARK: - Preview

#Preview("Node Toggle") {
    struct PreviewWrapper: View {
        @State private var isOn1 = true
        @State private var isOn2 = false
        @State private var isOn3 = true
        @State private var isOn4 = false

        var body: some View {
            VStack(spacing: 24) {
                HStack(spacing: 20) {
                    VStack {
                        Text("Full Toggle")
                            .font(.caption)
                        NodeToggle(isOn: $isOn1)
                    }

                    VStack {
                        Text("Off State")
                            .font(.caption)
                        NodeToggle(isOn: $isOn2)
                    }
                }

                HStack(spacing: 20) {
                    VStack {
                        Text("Indicator On")
                            .font(.caption)
                        NodeToggleIndicator(isOn: $isOn3)
                    }

                    VStack {
                        Text("Indicator Off")
                            .font(.caption)
                        NodeToggleIndicator(isOn: $isOn4)
                    }
                }
            }
            .padding()
            .background(KoeColors.surface)
        }
    }
    return PreviewWrapper()
}
