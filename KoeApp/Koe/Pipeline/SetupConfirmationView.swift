import KoeUI
import SwiftUI

// MARK: - Setup Confirmation View

/// Popup shown when user taps on a node that needs setup
struct SetupConfirmationView: View {
    let nodeInfo: NodeInfo
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let textColor = Color(nsColor: NSColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0))

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 12) {
                // Node icon
                ZStack {
                    Circle()
                        .fill(nodeInfo.color.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: nodeInfo.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(nodeInfo.color)
                }

                // Title
                Text("Setup Required")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(textColor)

                // Description
                Text("\(nodeInfo.displayName) needs to be set up before you can use it.")
                    .font(.system(size: 13))
                    .foregroundColor(lightGray)
                    .multilineTextAlignment(.center)
            }

            // Steps list
            if let requirements = nodeInfo.setupRequirements {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This will:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(lightGray)

                    ForEach(requirements.stepTypes.indices, id: \.self) { index in
                        let stepType = requirements.stepTypes[index]
                        HStack(spacing: 10) {
                            Image(systemName: stepType.icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(accentColor)
                                .frame(width: 20)

                            Text(stepType.displayName)
                                .font(.system(size: 13))
                                .foregroundColor(textColor)

                            Spacer()
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(lightGray.opacity(0.08))
                )
            }

            // Buttons
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(lightGray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(lightGray.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Text("Set Up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(accentColor)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
        )
    }
}

// MARK: - Setup Confirmation Modifier

extension View {
    /// Show setup confirmation popup for a node
    func setupConfirmation(
        isPresented: Binding<Bool>,
        nodeInfo: NodeInfo?,
        onConfirm: @escaping () -> Void
    ) -> some View {
        ZStack {
            self

            if isPresented.wrappedValue, let info = nodeInfo {
                // Dimmed background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isPresented.wrappedValue = false
                    }

                // Popup
                SetupConfirmationView(
                    nodeInfo: info,
                    onConfirm: {
                        isPresented.wrappedValue = false
                        onConfirm()
                    },
                    onCancel: {
                        isPresented.wrappedValue = false
                    }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented.wrappedValue)
    }
}

// MARK: - Preview

#Preview {
    SetupConfirmationView(
        nodeInfo: NodeInfo(
            typeId: "transcribe-whisperkit-balanced",
            displayName: "Balanced",
            icon: "gauge.with.dots.needle.50percent",
            color: .blue,
            requiresSetup: true,
            setupRequirements: .whisperKitBalanced
        ),
        onConfirm: {},
        onCancel: {}
    )
    .padding(40)
    .background(Color.gray.opacity(0.3))
}
