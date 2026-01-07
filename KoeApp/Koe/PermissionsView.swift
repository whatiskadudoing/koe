import SwiftUI
import AVFoundation
import ApplicationServices
import AppKit
import KoeTextInsertion

enum PermissionStep {
    case microphone
    case accessibility
    case complete
}

struct PermissionsView: View {
    @Environment(AppState.self) private var appState
    @State private var checkTimer: Timer?
    @State private var notificationObserver: NSObjectProtocol?
    @State private var currentStep: PermissionStep = .microphone
    @State private var contentOpacity = 0.0
    @State private var contentOffset: CGFloat = 20
    @State private var isRequestingPermission = false

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

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

                        // Step indicator
                        HStack(spacing: 8) {
                            Circle()
                                .fill(currentStep == .microphone ? accentColor : (appState.hasMicrophonePermission ? Color.green : lightGray.opacity(0.3)))
                                .frame(width: 8, height: 8)
                            Circle()
                                .fill(currentStep == .accessibility ? accentColor : (appState.hasAccessibilityPermission ? Color.green : lightGray.opacity(0.3)))
                                .frame(width: 8, height: 8)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.top, 40)

                    // Current permission card
                    VStack(spacing: 20) {
                        switch currentStep {
                        case .microphone:
                            PermissionCard(
                                icon: "mic.fill",
                                title: "Microphone Access",
                                description: "Koe needs microphone access to record your voice for transcription.",
                                isGranted: appState.hasMicrophonePermission,
                                isRequesting: isRequestingPermission,
                                buttonTitle: "Allow Microphone",
                                onRequest: requestMicrophonePermission
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))

                        case .accessibility:
                            PermissionCard(
                                icon: "hand.point.up.left.fill",
                                title: "Accessibility Access",
                                description: "Koe needs accessibility access to type transcribed text into other apps.",
                                isGranted: appState.hasAccessibilityPermission,
                                isRequesting: isRequestingPermission,
                                buttonTitle: "Open Settings",
                                onRequest: requestAccessibilityPermission
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))

                        case .complete:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 40)
                    .animation(.easeInOut(duration: 0.4), value: currentStep)

                    Spacer()
                }

                // Status summary at bottom
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        StatusPill(title: "Microphone", isGranted: appState.hasMicrophonePermission)
                        StatusPill(title: "Accessibility", isGranted: appState.hasAccessibilityPermission)
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

            // Check current permissions and set initial step
            appState.checkAllPermissions()
            updateStep()

            // Start polling
            startPermissionPolling()
        }
        .onDisappear {
            stopPermissionPolling()
        }
    }

    private func updateStep() {
        if !appState.hasMicrophonePermission {
            currentStep = .microphone
        } else if !appState.hasAccessibilityPermission {
            currentStep = .accessibility
        } else {
            currentStep = .complete
        }
    }

    private func requestMicrophonePermission() {
        isRequestingPermission = true

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                isRequestingPermission = false
                appState.checkMicrophonePermission()

                if granted {
                    // Move to next step with animation
                    withAnimation(.easeInOut(duration: 0.4)) {
                        updateStep()
                    }
                }
            }
        }
    }

    private func requestAccessibilityPermission() {
        isRequestingPermission = true

        // Just open System Settings - user can toggle Koe in the list
        // No need to call requestPermission() which shows an extra dialog
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isRequestingPermission = false
        }
    }

    private func startPermissionPolling() {
        // Register for distributed notification when accessibility permissions change
        // This notification fires when ANY app's accessibility permission changes
        // Store the observer token so we can remove it later
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { _ in
            // When notification fires, AXIsProcessTrusted() cache is refreshed
            Task { @MainActor in
                AppState.shared.checkAllPermissions()
            }
        }

        // Also poll with timer as backup (for microphone and edge cases)
        checkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                AppState.shared.checkAllPermissions()

                // Update step based on current permissions
                withAnimation(.easeInOut(duration: 0.3)) {
                    updateStep()
                }

                // Auto-advance when all permissions granted
                if AppState.shared.hasAllPermissions {
                    stopPermissionPolling()
                    withAnimation(.easeOut(duration: 0.4)) {
                        AppState.shared.advanceReadinessState()
                    }
                }
            }
        }
    }

    private func stopPermissionPolling() {
        checkTimer?.invalidate()
        checkTimer = nil
        // Remove distributed notification observer using the stored token
        if let observer = notificationObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            notificationObserver = nil
        }
    }
}

// MARK: - Permission Card

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let isRequesting: Bool
    let buttonTitle: String
    let onRequest: () -> Void

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

    var body: some View {
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.1) : accentColor.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: isGranted ? "checkmark" : icon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(isGranted ? .green : accentColor)
            }

            // Title and description
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(accentColor)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(lightGray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            // Button or granted state
            if isGranted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Granted")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(.top, 8)
            } else {
                Button(action: onRequest) {
                    HStack(spacing: 8) {
                        if isRequesting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(buttonTitle)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(accentColor)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(isRequesting)
                .padding(.top, 8)
            }
        }
        .padding(28)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 4)
    }
}

// MARK: - Status Pill

struct StatusPill: View {
    let title: String
    let isGranted: Bool

    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isGranted ? Color.green : lightGray.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isGranted ? Color.green : lightGray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isGranted ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
        .cornerRadius(20)
    }
}
