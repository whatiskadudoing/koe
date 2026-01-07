import SwiftUI
import AVFoundation
import ApplicationServices

struct PermissionsView: View {
    @Environment(AppState.self) private var appState
    @State private var checkTimer: Timer?

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

    var body: some View {
        ZStack {
            // Background matching app
            Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 32) {
                // Header
                VStack(spacing: 12) {
                    Text("Permissions Required")
                        .font(.system(size: 24, weight: .light, design: .rounded))
                        .foregroundColor(accentColor)

                    Text("Koe needs these permissions to work")
                        .font(.system(size: 13))
                        .foregroundColor(lightGray)
                }

                // Permission list
                VStack(spacing: 16) {
                    PermissionRow(
                        icon: "mic.fill",
                        title: "Microphone",
                        description: "To record your voice",
                        isGranted: appState.hasMicrophonePermission
                    )

                    PermissionRow(
                        icon: "hand.point.up.left.fill",
                        title: "Accessibility",
                        description: "To type into other apps",
                        isGranted: appState.hasAccessibilityPermission
                    )
                }
                .padding(.horizontal, 40)

                // Open System Settings button
                Button(action: openSystemSettings) {
                    Text("Open System Settings")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.top, 40)
        }
        .onAppear {
            startPermissionPolling()
        }
        .onDisappear {
            stopPermissionPolling()
        }
    }

    private func startPermissionPolling() {
        // Check immediately
        appState.checkAllPermissions()

        // Poll every 0.5 seconds
        checkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            appState.checkAllPermissions()

            // Auto-advance when both permissions granted
            if appState.hasAllPermissions {
                stopPermissionPolling()
                withAnimation(.easeOut(duration: 0.4)) {
                    appState.advanceReadinessState()
                }
            }
        }
    }

    private func stopPermissionPolling() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(isGranted ? .green : lightGray)
                .frame(width: 32)

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(accentColor)

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(lightGray)
            }

            Spacer()

            // Status indicator
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundColor(isGranted ? .green : lightGray.opacity(0.5))
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}
