import SwiftUI

/// A reusable modal component for displaying settings
/// Use this for node settings, preferences, and other configuration panels
public struct SettingsModal<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    public init(
        title: String,
        icon: String,
        iconColor: Color = KoeColors.accent,
        onClose: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.onClose = onClose
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(KoeColors.accent)

                Spacer()

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(KoeColors.textLight)
                        .padding(8)
                        .background(KoeColors.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()
                .padding(.horizontal, 16)

            // Content
            content()
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        .frame(minWidth: 340, maxWidth: 420)
    }
}

/// A modal overlay that dims the background and centers the modal
/// Supports Escape key to close
public struct ModalOverlay<Content: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content

    public init(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isPresented = isPresented
        self.content = content
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
    }

    public var body: some View {
        if isPresented {
            ZStack {
                // Dim background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismiss()
                    }

                // Modal content
                content()
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            .animation(.easeOut(duration: 0.2), value: isPresented)
            .onKeyPress(.escape) {
                dismiss()
                return .handled
            }
        }
    }
}

/// View modifier for presenting a settings modal
public struct SettingsModalModifier<ModalContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let modalContent: () -> ModalContent

    public init(
        isPresented: Binding<Bool>,
        @ViewBuilder modalContent: @escaping () -> ModalContent
    ) {
        self._isPresented = isPresented
        self.modalContent = modalContent
    }

    public func body(content: Content) -> some View {
        ZStack {
            content

            ModalOverlay(isPresented: $isPresented) {
                modalContent()
            }
        }
    }
}

public extension View {
    /// Present a settings modal overlay
    func settingsModal<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(SettingsModalModifier(isPresented: isPresented, modalContent: content))
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var isPresented = true

        var body: some View {
            ZStack {
                KoeColors.background
                    .ignoresSafeArea()

                Button("Show Modal") {
                    isPresented = true
                }
            }
            .settingsModal(isPresented: $isPresented) {
                SettingsModal(
                    title: "Hotkey Settings",
                    icon: "command",
                    iconColor: KoeColors.accent,
                    onClose: { isPresented = false }
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Press and hold to record")
                            .font(.system(size: 12))
                            .foregroundColor(KoeColors.textSecondary)

                        HStack {
                            Text("Current:")
                                .font(.system(size: 11))
                                .foregroundColor(KoeColors.textLight)

                            Text("⌥ Space")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(KoeColors.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(KoeColors.surface)
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
    }

    return PreviewWrapper()
        .frame(width: 400, height: 400)
}
