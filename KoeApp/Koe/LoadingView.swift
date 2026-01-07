import SwiftUI
import KoeDomain

struct LoadingView: View {
    @Environment(AppState.self) private var appState
    @State private var animationPhase: CGFloat = 0
    @State private var contentOpacity: Double = 0
    @State private var checkTimer: Timer?

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

    var body: some View {
        ZStack {
            // Background matching app
            Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Animated blue waveform
                LoadingWaveform(phase: animationPhase)
                    .frame(width: 140, height: 70)

                // Loading text
                VStack(spacing: 12) {
                    Text("Loading models...")
                        .font(.system(size: 16, weight: .light, design: .rounded))
                        .foregroundColor(accentColor)

                    // Show progress percentage if downloading
                    if appState.modelLoadingProgress > 0 && appState.modelLoadingProgress < 1 {
                        Text("\(Int(appState.modelLoadingProgress * 100))%")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundColor(lightGray)
                            .monospacedDigit()
                    }
                }

                Spacer()
            }
            .opacity(contentOpacity)
        }
        .onAppear {
            // Fade in content
            withAnimation(.easeOut(duration: 0.4)) {
                contentOpacity = 1
            }

            // Start continuous waveform animation
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                animationPhase = .pi * 2
            }

            // Start checking for model loaded state
            startModelLoadingCheck()
        }
        .onDisappear {
            stopModelLoadingCheck()
        }
    }

    private func startModelLoadingCheck() {
        // Check immediately
        if appState.isModelLoaded {
            advanceToReady()
            return
        }

        // Poll every 0.2 seconds
        checkTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            if appState.isModelLoaded {
                stopModelLoadingCheck()
                withAnimation(.easeOut(duration: 0.4)) {
                    appState.advanceReadinessState()
                }
            }
        }
    }

    private func stopModelLoadingCheck() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func advanceToReady() {
        appState.advanceReadinessState()
    }
}

// MARK: - Loading Waveform

struct LoadingWaveform: View {
    let phase: CGFloat
    private let barCount = 9
    private let blueColor = Color(nsColor: NSColor.systemBlue)

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(blueColor)
                    .frame(width: 8, height: barHeight(for: index))
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let minHeight: CGFloat = 16
        let maxHeight: CGFloat = 68
        let centerIndex = CGFloat(barCount - 1) / 2
        let distanceFromCenter = abs(CGFloat(index) - centerIndex) / centerIndex

        // Create wave pattern from center outward
        let baseHeight = maxHeight - (distanceFromCenter * (maxHeight - minHeight) * 0.5)
        let waveOffset = sin(phase + CGFloat(index) * 0.7) * 0.35 + 0.65

        return baseHeight * waveOffset
    }
}
