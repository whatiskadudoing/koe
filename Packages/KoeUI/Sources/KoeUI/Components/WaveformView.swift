import SwiftUI
import KoeDomain

// MARK: - Animated Ring (Main Component)

/// Audio-reactive animated ring with multiple style options
public struct AnimatedRing: View {
    public let isActive: Bool
    public let audioLevel: Float
    public let color: Color
    public let style: RingAnimationStyle
    public let maxAmplitude: CGFloat

    public init(
        isActive: Bool = true,
        audioLevel: Float = 0,
        color: Color,
        style: RingAnimationStyle = .wave,
        maxAmplitude: CGFloat = 14
    ) {
        self.isActive = isActive
        self.audioLevel = audioLevel
        self.color = color
        self.style = style
        self.maxAmplitude = maxAmplitude
    }

    public var body: some View {
        switch style {
        case .wave:
            WaveRingAnimation(isActive: isActive, audioLevel: audioLevel, color: color, maxAmplitude: maxAmplitude)
        case .blob:
            BlobRingAnimation(isActive: isActive, audioLevel: audioLevel, color: color, maxAmplitude: maxAmplitude)
        }
    }
}

// MARK: - Wave Ring Animation (Siri-style)

struct WaveRingAnimation: View {
    let isActive: Bool
    let audioLevel: Float
    let color: Color
    let maxAmplitude: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - maxAmplitude - 4
                let time = timeline.date.timeIntervalSinceReferenceDate

                // Draw 3 wave layers for depth - outer to inner
                for layer in (0..<3).reversed() {
                    drawWaveLayer(
                        context: context,
                        center: center,
                        radius: radius,
                        time: time,
                        layer: layer
                    )
                }
            }
            .drawingGroup() // GPU acceleration for smoother rendering
        }
    }

    private func drawWaveLayer(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        layer: Int
    ) {
        let layerOffset = Double(layer) * 0.4
        let layerScale = 1.0 - Double(layer) * 0.08
        let lineWidth: CGFloat = layer == 0 ? 2.5 : (layer == 1 ? 2.0 : 1.5)

        var path = Path()
        let phase = -time * 2.5 + layerOffset * .pi
        let normalizedAudio = CGFloat(min(audioLevel * 2.5, 1.0))
        let segmentCount = 120 // More segments for smoother curves

        for i in 0...segmentCount {
            let t = Double(i) / Double(segmentCount)
            let angle = t * 2.0 * .pi

            // Multi-frequency waves for organic feel
            let wave1 = sin(3.0 * angle + phase) * 0.5
            let wave2 = sin(5.0 * angle - phase * 1.2) * 0.3
            let wave3 = sin(7.0 * angle + phase * 0.7) * 0.2
            let wave4 = sin(11.0 * angle - phase * 0.5) * 0.1
            let waveValue = wave1 + wave2 + wave3 + wave4

            var amplitude: CGFloat
            if audioLevel > 0.005 {
                // Smooth audio response
                let smoothAudio = pow(normalizedAudio, 0.7) // Softer response curve
                let baseAmp = 0.3 + smoothAudio * 0.7
                amplitude = CGFloat(waveValue) * baseAmp * maxAmplitude * layerScale

                // Add harmonic boost for louder audio
                if normalizedAudio > 0.3 {
                    let boost = sin(angle * 6 + phase * 2) * smoothAudio * 0.25
                    amplitude += CGFloat(boost) * maxAmplitude
                }
            } else if isActive {
                // Gentle idle animation
                let idleWave = sin(time * 1.5 + angle * 2) * 0.15
                amplitude = CGFloat(waveValue * 0.4 + idleWave) * maxAmplitude * layerScale
            } else {
                // Subtle static wave
                amplitude = CGFloat(waveValue) * 0.2 * maxAmplitude * layerScale
            }

            let r = radius * layerScale + amplitude
            let cgAngle = CGFloat(angle)
            let point = CGPoint(x: center.x + cos(cgAngle) * r, y: center.y + sin(cgAngle) * r)

            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()

        // Layer opacity - inner layers more transparent
        let baseOpacity: Double
        if audioLevel > 0.005 {
            baseOpacity = 0.7 + Double(normalizedAudio) * 0.3
        } else if isActive {
            baseOpacity = 0.6
        } else {
            baseOpacity = 0.4
        }
        let layerOpacity = baseOpacity * (1.0 - Double(layer) * 0.25)

        context.stroke(path, with: .color(color.opacity(layerOpacity)), lineWidth: lineWidth)
    }
}

// MARK: - Blob Ring Animation (Organic)

struct BlobRingAnimation: View {
    let isActive: Bool
    let audioLevel: Float
    let color: Color
    let maxAmplitude: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - maxAmplitude - 4
                let time = timeline.date.timeIntervalSinceReferenceDate

                let normalizedAudio = CGFloat(min(audioLevel * 2.2, 1.0))
                let segmentCount = 150 // More segments for ultra-smooth blob

                // Draw multiple blob layers
                for layer in (0..<2).reversed() {
                    let layerScale = 1.0 - CGFloat(layer) * 0.05
                    let layerTimeOffset = Double(layer) * 0.3

                    var path = Path()

                    for i in 0...segmentCount {
                        let t = Double(i) / Double(segmentCount)
                        let angle = t * 2.0 * .pi

                        // Organic blob with multiple noise frequencies
                        let noise1 = sin(angle * 2 + (time + layerTimeOffset) * 1.2) * 0.35
                        let noise2 = sin(angle * 3 - (time + layerTimeOffset) * 1.8) * 0.25
                        let noise3 = sin(angle * 5 + (time + layerTimeOffset) * 0.9) * 0.15
                        let noise4 = cos(angle * 4 - (time + layerTimeOffset) * 1.4) * 0.1
                        let blobNoise = noise1 + noise2 + noise3 + noise4

                        var amplitude: CGFloat
                        if audioLevel > 0.005 {
                            let smoothAudio = pow(normalizedAudio, 0.6)
                            amplitude = CGFloat(blobNoise) * (0.5 + smoothAudio * 0.7) * maxAmplitude * layerScale
                        } else if isActive {
                            amplitude = CGFloat(blobNoise) * 0.55 * maxAmplitude * layerScale
                        } else {
                            amplitude = CGFloat(blobNoise) * 0.25 * maxAmplitude * layerScale
                        }

                        let r = radius * layerScale + amplitude
                        let cgAngle = CGFloat(angle)
                        let point = CGPoint(x: center.x + cos(cgAngle) * r, y: center.y + sin(cgAngle) * r)

                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    path.closeSubpath()

                    let baseOpacity = audioLevel > 0.005 ? (0.65 + Double(normalizedAudio) * 0.35) : (isActive ? 0.55 : 0.35)
                    let layerOpacity = baseOpacity * (1.0 - Double(layer) * 0.3)
                    let lineWidth: CGFloat = layer == 0 ? 2.5 : 1.5

                    // Subtle fill for inner layer
                    if layer == 0 {
                        context.fill(path, with: .color(color.opacity(layerOpacity * 0.08)))
                    }
                    context.stroke(path, with: .color(color.opacity(layerOpacity)), lineWidth: lineWidth)
                }
            }
            .drawingGroup()
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
