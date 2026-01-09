import SwiftUI
import KoeDomain
import KoeUI

/// Simple loading view that shows during app startup
/// No longer loads models - that's handled on-demand via the setup queue
struct LoadingView: View {
    @Environment(AppState.self) private var appState
    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 20

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

                // Animated ring with icon
                ZStack {
                    AnimatedRing(
                        isActive: true,
                        audioLevel: 0,
                        color: accentColor,
                        style: appState.currentRingAnimationStyle,
                        maxAmplitude: 14
                    )
                    .frame(width: circleSize + 44, height: circleSize + 44)

                    Circle()
                        .fill(Color.white)
                        .frame(width: circleSize, height: circleSize)
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)

                    Image(systemName: "waveform")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(accentColor)
                }

                // Loading text
                VStack(spacing: 8) {
                    Text("Getting ready")
                        .font(.system(size: 18, weight: .light, design: .rounded))
                        .foregroundColor(accentColor)
                        .tracking(0.3)

                    Text("Just a moment...")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(lightGray.opacity(0.8))
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

            // Go to ready state after a brief moment
            Task {
                // Small delay for smooth transition
                try? await Task.sleep(nanoseconds: 500_000_000)

                await MainActor.run {
                    appState.isModelLoaded = true
                    appState.advanceReadinessState()
                }
            }
        }
    }
}
