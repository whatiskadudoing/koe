import SwiftUI

// MARK: - Animated Ring (Siri-style)

/// Siri-style animated ring with smooth multi-layer waves
/// Based on Apple's Siri visualization with parabolic scaling and flowing animation
public struct AnimatedRing: View {
    public let isActive: Bool
    public let audioLevel: Float
    public let color: Color
    public let segmentCount: Int
    public let baseRadius: CGFloat
    public let maxAmplitude: CGFloat
    public let strokeWidth: CGFloat

    public init(
        isActive: Bool = true,
        audioLevel: Float = 0,
        color: Color,
        segmentCount: Int = 80,
        baseRadius: CGFloat? = nil,
        maxAmplitude: CGFloat = 14,
        strokeWidth: CGFloat = 2
    ) {
        self.isActive = isActive
        self.audioLevel = audioLevel
        self.color = color
        self.segmentCount = segmentCount
        self.baseRadius = baseRadius ?? 0
        self.maxAmplitude = maxAmplitude
        self.strokeWidth = strokeWidth
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = baseRadius > 0 ? baseRadius : min(size.width, size.height) / 2 - maxAmplitude - 2
                let time = timeline.date.timeIntervalSinceReferenceDate

                // Draw 3 wave layers for depth effect
                for layer in 0..<3 {
                    let layerOffset = Double(layer) * 0.3
                    let layerOpacity = 1.0 - Double(layer) * 0.25
                    let layerWidth = strokeWidth * (1.0 - CGFloat(layer) * 0.2)

                    drawSmoothWave(
                        context: context,
                        center: center,
                        radius: radius,
                        time: time,
                        phaseOffset: layerOffset,
                        opacity: layerOpacity,
                        lineWidth: layerWidth
                    )
                }
            }
        }
    }

    private func drawSmoothWave(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        phaseOffset: Double,
        opacity: Double,
        lineWidth: CGFloat
    ) {
        var path = Path()

        // Phase creates flowing animation
        let phase = -time * 2.0 + phaseOffset * .pi

        // Normalized audio with boost for sensitivity
        let normalizedAudio = CGFloat(min(audioLevel * 1.8, 1.0))

        for i in 0...segmentCount {
            let t = Double(i) / Double(segmentCount)
            let angle = t * 2.0 * .pi

            // Multi-frequency sine waves (like Siri)
            let freq1 = 3.0  // Primary wave
            let freq2 = 5.0  // Secondary
            let freq3 = 7.0  // Tertiary for detail

            let wave1 = sin(freq1 * angle + phase)
            let wave2 = sin(freq2 * angle - phase * 1.3) * 0.6
            let wave3 = sin(freq3 * angle + phase * 0.8) * 0.3

            // Combined wave value
            let waveValue = (wave1 + wave2 + wave3) / 2.0

            // Calculate amplitude based on state
            var amplitude: CGFloat
            if audioLevel > 0.01 {
                // Audio reactive - dramatic response to voice
                let baseAmp = 0.25 + normalizedAudio * 0.75
                amplitude = CGFloat(waveValue) * baseAmp * maxAmplitude

                // Extra peaks for loud sounds
                if normalizedAudio > 0.5 {
                    let boost = sin(angle * 4 + phase * 2.5) * normalizedAudio * 0.3
                    amplitude += CGFloat(boost) * maxAmplitude
                }
            } else if isActive {
                // Idle/processing - gentle flowing wave
                amplitude = CGFloat(waveValue) * 0.4 * maxAmplitude
            } else {
                // Inactive - very subtle
                amplitude = CGFloat(waveValue) * 0.1 * maxAmplitude
            }

            let r = radius + amplitude
            let cgAngle = CGFloat(angle)
            let point = CGPoint(
                x: center.x + cos(cgAngle) * r,
                y: center.y + sin(cgAngle) * r
            )

            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.closeSubpath()

        // Calculate final opacity
        let finalOpacity: Double
        if audioLevel > 0.01 {
            finalOpacity = (0.6 + Double(normalizedAudio) * 0.4) * opacity
        } else if isActive {
            finalOpacity = 0.5 * opacity
        } else {
            finalOpacity = 0.25 * opacity
        }

        context.stroke(
            path,
            with: .color(color.opacity(finalOpacity)),
            lineWidth: lineWidth
        )
    }
}

// MARK: - Animated Waveform (for processing states)

/// Continuously animated waveform for indicating processing/activity
/// Use this for pipeline nodes, loading states, etc.
public struct AnimatedWaveform: View {
    public let color: Color
    public let barCount: Int
    public let barWidth: CGFloat
    public let barSpacing: CGFloat
    public let minHeight: CGFloat
    public let maxHeight: CGFloat

    @State private var phase: CGFloat = 0

    public init(
        color: Color,
        barCount: Int = 5,
        barWidth: CGFloat = 3,
        barSpacing: CGFloat = 2,
        minHeight: CGFloat = 4,
        maxHeight: CGFloat = 14
    ) {
        self.color = color
        self.barCount = barCount
        self.barWidth = barWidth
        self.barSpacing = barSpacing
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }

    public var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 3)
                    .fill(color)
                    .frame(width: barWidth, height: barHeight(for: index))
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
            phase = .pi * 2
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let wave = sin(phase + CGFloat(index) * 0.8) * 0.5 + 0.5
        return minHeight + wave * (maxHeight - minHeight)
    }
}

// MARK: - Audio Level Waveform

/// Animated waveform visualization for audio levels
public struct WaveformView: View {
    public let audioLevel: Float
    public let color: Color
    public let barCount: Int

    public init(audioLevel: Float, color: Color = .white, barCount: Int = 5) {
        self.audioLevel = audioLevel
        self.color = color
        self.barCount = barCount
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.15), value: audioLevel)
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 8
        let maxHeight: CGFloat = 36
        let variation = sin(Double(index) * 0.8 + Double(audioLevel) * 10) * 0.3 + 0.7
        return baseHeight + CGFloat(audioLevel * Float(variation)) * (maxHeight - baseHeight)
    }
}
