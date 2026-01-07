import SwiftUI
import AVFoundation
import ApplicationServices
import AppKit
import KoeTextInsertion

struct PermissionsView: View {
    @Environment(AppState.self) private var appState
    @State private var checkTimer: Timer?
    @State private var hasUserAgreed = false
    @State private var contentOpacity = 0.0
    @State private var contentOffset: CGFloat = 20

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let darkGray = Color(nsColor: NSColor(red: 0.35, green: 0.33, blue: 0.30, alpha: 1.0))

    var body: some View {
        ZStack {
            // Background matching app
            Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 28) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Permissions")
                            .font(.system(size: 28, weight: .light, design: .rounded))
                            .foregroundColor(accentColor)

                        // Subtle divider line
                        Rectangle()
                            .fill(accentColor.opacity(0.2))
                            .frame(height: 1)
                            .frame(width: 32)

                        Text("We need your permission to record and type")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(lightGray)
                            .tracking(0.3)
                    }
                    .padding(.top, 40)

                    // Permission list
                    VStack(spacing: 12) {
                        PermissionRow(
                            icon: "mic.fill",
                            title: "Microphone",
                            description: "To record your voice",
                            isGranted: appState.hasMicrophonePermission,
                            isRequested: hasUserAgreed
                        )

                        PermissionRow(
                            icon: "hand.point.up.left.fill",
                            title: "Accessibility",
                            description: "To type into other apps",
                            isGranted: appState.hasAccessibilityPermission,
                            isRequested: hasUserAgreed
                        )
                    }
                    .padding(.horizontal, 40)

                    Spacer()
                }

                // Bottom button - fixed at bottom
                VStack(spacing: 12) {
                    if !appState.hasAllPermissions {
                        Button(action: agreeAndRequestPermissions) {
                            Text("Agree & Permit")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(accentColor)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .opacity(contentOpacity)
            .offset(y: contentOffset)
        }
        .onAppear {
            // Animate in
            withAnimation(.easeOut(duration: 0.5)) {
                contentOpacity = 1
                contentOffset = 0
            }
        }
        .onDisappear {
            stopPermissionPolling()
        }
    }

    private func agreeAndRequestPermissions() {
        withAnimation(.easeInOut(duration: 0.3)) {
            hasUserAgreed = true
        }

        // After animation, request permissions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            requestPermissions()
            startPermissionPolling()
        }
    }

    private func startPermissionPolling() {
        // Add a small delay before first check (macOS TCC caching issue)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            appState.checkAllPermissions()
        }

        // Poll more frequently to catch permission updates quickly
        checkTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
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

    private func requestPermissions() {
        // Request microphone permission (shows system dialog)
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        // Request accessibility permission
        // Try the API first, then open System Settings as fallback
        let textInserter = TextInsertionServiceImpl()
        textInserter.requestPermission()

        // Also open System Settings to Privacy > Accessibility
        // This ensures user sees where to enable it if dialog doesn't appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            openAccessibilitySettings()
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let isRequested: Bool

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(isGranted ? .green : (isRequested ? accentColor : lightGray))
                .frame(width: 32)
                .opacity(isRequested && !isGranted ? 0.6 : 1.0)

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
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
                    .transition(.scale.combined(with: .opacity))
            } else if isRequested {
                // Subtle loading indicator when requested but not granted
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundColor(accentColor.opacity(0.5))
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 20))
                    .foregroundColor(lightGray.opacity(0.4))
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: .black.opacity(isRequested ? 0.06 : 0.04), radius: 8, x: 0, y: 2)
    }
}
