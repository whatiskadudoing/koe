import SwiftUI
import KoeDomain

struct LoadingView: View {
    @Environment(AppState.self) private var appState
    @Environment(RecordingCoordinator.self) private var coordinator
    @State private var animationPhase: CGFloat = 0
    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 20
    @State private var checkTimer: Timer?
    @State private var animationTimer: Timer?

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

    var body: some View {
        ZStack {
            // Background matching app
            Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Animated waveform - matching WelcomeView style
                LoadingWaveform(phase: animationPhase)
                    .frame(width: 120, height: 60)

                Spacer()
                    .frame(height: 36)

                // Loading text
                VStack(spacing: 8) {
                    Text("Loading models...")
                        .font(.system(size: 16, weight: .light, design: .rounded))
                        .foregroundColor(accentColor)
                        .tracking(0.2)

                    // Subtle divider line
                    Rectangle()
                        .fill(accentColor.opacity(0.15))
                        .frame(height: 1)
                        .frame(width: 40)

                    // Show progress percentage or status - use coordinator for accurate progress
                    if coordinator.modelLoadingProgress > 0 && coordinator.modelLoadingProgress < 1 {
                        Text("\(Int(coordinator.modelLoadingProgress * 100))%")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(lightGray)
                            .monospacedDigit()
                            .tracking(0.1)
                    } else {
                        Text("Preparing...")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(lightGray.opacity(0.7))
                            .tracking(0.1)
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

            // Start continuous waveform animation using Timer for reliable animation
            startWaveformAnimation()

            // Trigger model loading now that we're past the permissions screen
            startModelLoading()

            // Start checking for model loaded state
            startModelLoadingCheck()
        }
        .onDisappear {
            stopModelLoadingCheck()
            stopWaveformAnimation()
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

    private func startWaveformAnimation() {
        // Use Timer for reliable animation at 30fps
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            animationPhase += 0.15
            if animationPhase > .pi * 2 {
                animationPhase = 0
            }
        }
    }

    private func stopWaveformAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
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

// MARK: - Loading Waveform

struct LoadingWaveform: View {
    let phase: CGFloat
    private let barCount = 9
    // Japanese indigo accent color - matching WelcomeView
    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(accentColor)
                    .frame(width: 6, height: barHeight(for: index))
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let minHeight: CGFloat = 12
        let maxHeight: CGFloat = 56
        let centerIndex = CGFloat(barCount - 1) / 2
        let distanceFromCenter = abs(CGFloat(index) - centerIndex) / centerIndex

        // Create wave pattern from center outward - matching LogoWaveform style
        let baseHeight = maxHeight - (distanceFromCenter * (maxHeight - minHeight) * 0.6)
        let waveOffset = sin(phase + CGFloat(index) * 0.7) * 0.3 + 0.7

        return baseHeight * waveOffset
    }
}
