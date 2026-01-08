import SwiftUI
import KoeUI
import KoePipeline

/// Individual node in the pipeline visualization
/// - Single tap: toggle on/off (if toggleable)
/// - Double tap: open settings (if has settings)
struct PipelineNodeView: View {
    let stage: PipelineStageInfo
    @Binding var isEnabled: Bool
    let isSelected: Bool
    let isRunning: Bool
    let metrics: ElementExecutionMetrics?
    let onToggle: () -> Void      // Called on single tap for toggleable nodes
    let onOpenSettings: () -> Void // Called on double tap for nodes with settings

    @State private var isHovered = false

    private let nodeSize: CGFloat = 44
    private let cornerRadius: CGFloat = 10

    var body: some View {
        nodeContent
            .onTapGesture(count: 2) {
                // Double tap: open settings if available
                if stage.hasSettings {
                    onOpenSettings()
                }
            }
            .onTapGesture(count: 1) {
                // Single tap: toggle if toggleable
                if stage.isToggleable {
                    withAnimation(.easeOut(duration: 0.2)) {
                        onToggle()
                    }
                }
            }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }

    private var nodeContent: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // Node background - rounded square
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isRunning ? stage.color.opacity(0.15) : Color.white)
                    .frame(width: nodeSize, height: nodeSize)
                    .shadow(
                        color: .black.opacity(isHovered ? 0.10 : 0.05),
                        radius: isHovered ? 8 : 4,
                        y: 2
                    )

                // Icon or waveform when running
                if isRunning {
                    AnimatedWaveform(color: stage.color, barCount: 4, minHeight: 4, maxHeight: 12)
                        .frame(width: 24, height: 16)
                        .frame(width: nodeSize, height: nodeSize)
                } else {
                    Image(systemName: stage.icon)
                        .font(.system(size: 16, weight: .medium))
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

            // Name label - fixed size to prevent wrapping
            Text(stage.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isRunning ? stage.color : (isEnabled ? KoeColors.textSecondary : KoeColors.textLight))
                .fixedSize()
                .lineLimit(1)
        }
        .opacity(effectiveOpacity)
        .scaleEffect(isHovered ? 1.05 : 1.0)
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

#Preview {
    HStack(spacing: 20) {
        PipelineNodeView(
            stage: .transcribe,
            isEnabled: .constant(true),
            isSelected: false,
            isRunning: true,
            metrics: nil,
            onToggle: {},
            onOpenSettings: {}
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
            onToggle: {},
            onOpenSettings: {}
        )

        PipelineNodeView(
            stage: .improve,
            isEnabled: .constant(false),
            isSelected: false,
            isRunning: false,
            metrics: nil,
            onToggle: {},
            onOpenSettings: {}
        )
    }
    .padding()
    .background(KoeColors.background)
}
