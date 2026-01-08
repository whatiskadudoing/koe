import SwiftUI
import KoeUI
import KoePipeline

/// Individual node in the pipeline visualization
struct PipelineNodeView: View {
    let stage: PipelineStageInfo
    @Binding var isEnabled: Bool
    let isSelected: Bool
    let isRunning: Bool
    let metrics: ElementExecutionMetrics?
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var wavePhase: CGFloat = 0

    private let nodeSize: CGFloat = 48
    private let cornerRadius: CGFloat = 10

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    // Node background
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(isRunning ? stage.color.opacity(0.15) : Color.white)
                        .frame(width: nodeSize, height: nodeSize)
                        .shadow(
                            color: .black.opacity(isHovered ? 0.08 : 0.04),
                            radius: isHovered ? 8 : 4,
                            y: 2
                        )

                    // Icon or waveform when running
                    if isRunning {
                        MiniWaveform(phase: wavePhase, color: stage.color)
                            .frame(width: 24, height: 16)
                            .frame(width: nodeSize, height: nodeSize)
                    } else {
                        Image(systemName: stage.icon)
                            .font(.system(size: 18))
                            .foregroundColor(effectiveIconColor)
                            .frame(width: nodeSize, height: nodeSize)
                    }

                    // Toggle indicator (only for toggleable stages)
                    if stage.isToggleable && !isRunning {
                        Circle()
                            .fill(isEnabled ? Color.green : KoeColors.textLighter)
                            .frame(width: 8, height: 8)
                            .offset(x: -4, y: 4)
                    }

                    // Status indicator for failed stages
                    if let m = metrics, m.status == .failed, !isRunning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .offset(x: -4, y: 4)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(isRunning ? stage.color : (isSelected ? KoeColors.accent : Color.clear), lineWidth: 2)
                )

                // Name label
                Text(stage.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isRunning ? stage.color : (isEnabled ? KoeColors.textSecondary : KoeColors.textLight))

                // Timing badge (only show when metrics available and stage was executed, not while running)
                if let m = metrics, isEnabled, !isRunning {
                    Text(m.formattedDuration)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(timingColor(for: m))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(timingColor(for: m).opacity(0.12))
                        .cornerRadius(4)
                }
            }
            .opacity(effectiveOpacity)
            .scaleEffect(isHovered ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            if isRunning {
                startWaveAnimation()
            }
        }
        .onChange(of: isRunning) { _, newValue in
            if newValue {
                startWaveAnimation()
            }
        }
    }

    private func startWaveAnimation() {
        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
            wavePhase = .pi * 2
        }
    }

    /// Color for timing badge based on duration
    private func timingColor(for metrics: ElementExecutionMetrics) -> Color {
        switch metrics.status {
        case .failed:
            return .red
        case .cancelled:
            return .orange
        case .skipped:
            return KoeColors.textLight
        case .success:
            // Color based on duration: <100ms green, <500ms yellow, >500ms orange
            if metrics.durationMs < 100 {
                return .green
            } else if metrics.durationMs < 500 {
                return .orange
            } else {
                return .red
            }
        }
    }

    private var effectiveIconColor: Color {
        if !stage.isToggleable {
            // Always-on stages use their color
            return stage.color
        }
        return isEnabled ? stage.color : KoeColors.textLight
    }

    private var effectiveOpacity: Double {
        if !stage.isToggleable {
            return 1.0
        }
        return isEnabled ? 1.0 : 0.5
    }
}

// MARK: - Mini Waveform for Running State

struct MiniWaveform: View {
    let phase: CGFloat
    let color: Color
    private let barCount = 5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3, height: barHeight(for: index))
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let minHeight: CGFloat = 4
        let maxHeight: CGFloat = 14
        let wave = sin(phase + CGFloat(index) * 0.8) * 0.5 + 0.5
        return minHeight + wave * (maxHeight - minHeight)
    }
}

#Preview {
    HStack(spacing: 20) {
        PipelineNodeView(
            stage: .transcription,
            isEnabled: .constant(true),
            isSelected: false,
            isRunning: true,
            metrics: nil,
            onTap: {}
        )

        PipelineNodeView(
            stage: .improve,
            isEnabled: .constant(true),
            isSelected: true,
            isRunning: false,
            metrics: ElementExecutionMetrics(
                elementId: "test",
                elementType: "language-improvement",
                startTime: Date(),
                endTime: Date().addingTimeInterval(0.45),
                status: .success,
                inputCharCount: 100,
                outputCharCount: 95
            ),
            onTap: {}
        )

        PipelineNodeView(
            stage: .improve,
            isEnabled: .constant(false),
            isSelected: false,
            isRunning: false,
            metrics: nil,
            onTap: {}
        )
    }
    .padding()
    .background(KoeColors.background)
}
