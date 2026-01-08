import SwiftUI
import KoeDomain
import KoeUI

struct LoadingView: View {
    @Environment(AppState.self) private var appState
    @Environment(RecordingCoordinator.self) private var coordinator
    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 20
    @State private var checkTimer: Timer?

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let circleSize: CGFloat = 80

    var body: some View {
        ZStack {
            // Background matching app
            Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Animated ring with brain icon
                ZStack {
                    AnimatedRing(
                        isActive: true,
                        audioLevel: 0,
                        color: accentColor,
                        segmentCount: 48,
                        maxAmplitude: 14,
                        strokeWidth: 3
                    )
                    .frame(width: circleSize + 44, height: circleSize + 44)

                    Circle()
                        .fill(Color.white)
                        .frame(width: circleSize, height: circleSize)
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)

                    Image(systemName: "brain")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(accentColor)
                }

                // Loading text
                VStack(spacing: 8) {
                    Text("Getting smarter")
                        .font(.system(size: 18, weight: .light, design: .rounded))
                        .foregroundColor(accentColor)
                        .tracking(0.3)

                    // Show progress percentage or status
                    if coordinator.modelLoadingProgress > 0 && coordinator.modelLoadingProgress < 1 {
                        Text("\(Int(coordinator.modelLoadingProgress * 100))%")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(lightGray)
                    } else {
                        Text("Loading intelligence...")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(lightGray.opacity(0.8))
                    }
                }

                Spacer()
            }
            .opacity(contentOpacity)
            .offset(y: contentOffset)
        }
        .onAppear {
            // Fade in content with animation
            withAnimation(.easeOut(duration: 0.5)) {
                contentOpacity = 1
                contentOffset = 0
            }

            // Trigger model loading now that we're past the permissions screen
            startModelLoading()

            // Start checking for model loaded state
            startModelLoadingCheck()
        }
        .onDisappear {
            stopModelLoadingCheck()
        }
    }

    private func startModelLoading() {
        // Only start loading if not already loaded
        if !coordinator.isModelLoaded {
            Task {
                await RecordingCoordinator.shared.loadModel(name: AppState.shared.selectedModel)
            }
        }
    }

    private func startModelLoadingCheck() {
        // Check immediately - use coordinator.isModelLoaded which checks actual transcriber state
        if coordinator.isModelLoaded {
            advanceToReady()
            return
        }

        // Poll every 0.5 seconds - check the actual transcriber ready state
        checkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak checkTimer] _ in
            // Must dispatch to main thread since coordinator is MainActor-isolated
            Task { @MainActor in
                let isLoaded = RecordingCoordinator.shared.isModelLoaded

                // Use coordinator.isModelLoaded which returns transcriber.isReady
                // This ensures we only advance when the model is ACTUALLY ready
                if isLoaded {
                    checkTimer?.invalidate()
                    // Also sync the AppState flag
                    AppState.shared.isModelLoaded = true
                    withAnimation(.easeOut(duration: 0.4)) {
                        AppState.shared.advanceReadinessState()
                    }
                }
            }
        }
    }

    private func stopModelLoadingCheck() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func advanceToReady() {
        // Sync the AppState flag before advancing
        appState.isModelLoaded = true
        appState.advanceReadinessState()
    }
}
