import SwiftUI

// MARK: - Animated Ring (Siri-style)

/// Siri-style animated ring that pulses with audio level or smoothly animates during processing
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
        segmentCount: Int = 48,
        baseRadius: CGFloat? = nil,
        maxAmplitude: CGFloat = 14,
        strokeWidth: CGFloat = 3
    ) {
        self.isActive = isActive
        self.audioLevel = audioLevel
        self.color = color
        self.segmentCount = segmentCount
        self.baseRadius = baseRadius ?? 0  // Will be calculated from size
        self.maxAmplitude = maxAmplitude
        self.strokeWidth = strokeWidth
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 0.016)) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = baseRadius > 0 ? baseRadius : min(size.width, size.height) / 2 - maxAmplitude - 4
                let time = timeline.date.timeIntervalSinceReferenceDate

                for i in 0..<segmentCount {
                    let angle = (Double(i) / Double(segmentCount)) * 2 * .pi

                    var amplitude: CGFloat
                    if audioLevel > 0.01 {
                        // Highly reactive to audio level - more dramatic response
                        let normalizedAudio = CGFloat(min(audioLevel * 2.0, 1.0))  // Boost sensitivity
                        let wave1 = sin(time * 8 + angle * 3) * 0.4
                        let wave2 = sin(time * 12 + angle * 5) * 0.3
                        let wave3 = cos(time * 6 - angle * 4) * 0.25

                        // Base amplitude scales dramatically with audio
                        amplitude = 0.2 + normalizedAudio * 1.5
                        // Add wave variation
                        amplitude *= (0.7 + CGFloat(wave1 + wave2 + wave3) * 0.5)
                        // Extra boost for louder sounds
                        if audioLevel > 0.3 {
                            amplitude *= 1.2
                        }
                    } else if isActive {
                        // Smooth rotating wave for processing/idle animation
                        let wave = sin(time * 2.5 + angle * 2) * 0.5 + 0.5
                        let wave2 = sin(time * 4 - angle * 3) * 0.3
                        amplitude = 0.3 + (wave + wave2) * 0.5
                    } else {
                        // Subtle static ring when inactive
                        amplitude = 0.15
                    }

                    amplitude = min(1.5, max(0.1, amplitude))

                    let innerRadius = radius
                    let outerRadius = radius + amplitude * maxAmplitude

                    let innerPoint = CGPoint(
                        x: center.x + cos(angle) * innerRadius,
                        y: center.y + sin(angle) * innerRadius
                    )
                    let outerPoint = CGPoint(
                        x: center.x + cos(angle) * outerRadius,
                        y: center.y + sin(angle) * outerRadius
                    )

                    var path = Path()
                    path.move(to: innerPoint)
                    path.addLine(to: outerPoint)

                    // More visible opacity
                    let opacity = isActive ? (0.75 + amplitude * 0.25) : 0.4
                    context.stroke(
                        path,
                        with: .color(color.opacity(opacity)),
                        lineWidth: strokeWidth
                    )
                }
            }
        }
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
