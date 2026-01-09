import SwiftUI
import KoeUI
import KoePipeline

/// Individual node in the pipeline visualization
/// - Click toggle indicator: turn on/off (if toggleable)
/// - Double tap node: open settings (if has settings)
struct PipelineNodeView: View {
    let stage: PipelineStageInfo
    @Binding var isEnabled: Bool
    let isSelected: Bool
    let isRunning: Bool
    let metrics: ElementExecutionMetrics?
    let onToggle: () -> Void      // Called when toggle indicator is clicked
    let onOpenSettings: () -> Void // Called on double tap for nodes with settings

    @State private var isHovered = false
    @State private var lastTapTime: Date = .distantPast

    private let nodeSize: CGFloat = 44
    private let cornerRadius: CGFloat = 10
    private let doubleTapThreshold: TimeInterval = 0.3

    var body: some View {
        nodeContent
            .contentShape(Rectangle())
            .onTapGesture {
                handleTap()
            }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }

    /// Handle tap with manual double-tap detection
    /// - Toggle is handled by the NodeToggleIndicator (click the dot)
    /// - Double-tap anywhere opens settings
    private func handleTap() {
        let now = Date()
        let timeSinceLastTap = now.timeIntervalSince(lastTapTime)

        if timeSinceLastTap < doubleTapThreshold {
            // Double tap - open settings
            lastTapTime = .distantPast // Reset to prevent triple-tap triggering
            if stage.hasSettings {
                onOpenSettings()
            }
        } else {
            // Record tap time for double-tap detection
            lastTapTime = now

            // For toggleable nodes: single tap also toggles (with delay to detect double tap)
            if stage.isToggleable {
                let capturedTime = now
                DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapThreshold) { [self] in
                    // Only toggle if no second tap came in
                    if lastTapTime == capturedTime {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isEnabled.toggle()
                        }
                    }
                }
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

                // Interactive toggle indicator (only for toggleable stages)
                // Clicking this is the primary way to toggle on/off
                if stage.isToggleable && !isRunning {
                    NodeToggleIndicator(
                        isOn: $isEnabled,
                        size: 10
                    )
                    .offset(x: -2, y: 2)
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
