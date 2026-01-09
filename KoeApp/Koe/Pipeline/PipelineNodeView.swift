import SwiftUI
import KoeUI
import KoePipeline

/// Individual node in the pipeline visualization
/// Uses NodeUIProvider for rendering - each node type controls its own appearance
///
/// Interactions:
/// - Click toggle indicator: turn on/off (if toggleable)
/// - Double tap node: open settings (if has settings)
struct PipelineNodeView: View {
    let stage: PipelineStageInfo
    @Binding var isEnabled: Bool
    let isSelected: Bool
    let isRunning: Bool
    let metrics: ElementExecutionMetrics?
    let onToggle: () -> Void
    let onOpenSettings: () -> Void

    @State private var isHovered = false
    @State private var lastTapTime: Date = .distantPast

    private let nodeSize: CGFloat = 44
    private let cornerRadius: CGFloat = 10
    private let doubleTapThreshold: TimeInterval = 0.3

    /// Get the UI provider for this node
    private var uiProvider: NodeUIProvider {
        stage.nodeInfo.uiProvider
    }

    /// Create UI context for current state
    private var uiContext: NodeUIContext {
        let state: NodeUIState = {
            if isRunning { return .running }
            if !isEnabled && stage.isToggleable { return .disabled }
            if let m = metrics, m.status == .failed { return .failed(m.errorMessage) }
            return .idle
        }()

        return NodeUIContext(
            nodeInfo: stage.nodeInfo,
            state: state,
            isEnabled: isEnabled,
            isSelected: isSelected,
            metrics: metrics
        )
    }

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
    /// - Single tap: toggle immediately (for toggleable nodes)
    /// - Double tap: open settings
    private func handleTap() {
        let now = Date()
        let timeSinceLastTap = now.timeIntervalSince(lastTapTime)

        if timeSinceLastTap < doubleTapThreshold {
            // Double tap - open settings
            lastTapTime = .distantPast
            if stage.hasSettings {
                onOpenSettings()
            }
        } else {
            lastTapTime = now

            // For toggleable nodes: single tap toggles immediately
            if stage.isToggleable {
                withAnimation(.easeOut(duration: 0.15)) {
                    isEnabled.toggle()
                }
            }
        }
    }

    private var nodeContent: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // Background from provider
                uiProvider.pipelineBackground(context: uiContext)
                    .frame(width: nodeSize, height: nodeSize)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .shadow(
                        color: .black.opacity(isHovered ? 0.10 : 0.05),
                        radius: isHovered ? 8 : 4,
                        y: 2
                    )

                // Icon from provider
                uiProvider.pipelineIcon(context: uiContext)
                    .frame(width: nodeSize, height: nodeSize)

                // Toggle indicator (for toggleable nodes)
                if stage.isToggleable && !isRunning {
                    NodeToggleIndicator(
                        isOn: $isEnabled,
                        size: 10
                    )
                    .offset(x: -2, y: 2)
                }

                // Badge from provider (error indicator, etc.)
                if !stage.isToggleable, let badge = uiProvider.pipelineBadge(context: uiContext) {
                    badge.offset(x: -4, y: 4)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 2)
            )

            // Name label
            Text(stage.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(labelColor)
                .fixedSize()
                .lineLimit(1)
        }
        .opacity(effectiveOpacity)
        .scaleEffect(isHovered ? 1.05 : 1.0)
    }

    private var borderColor: Color {
        if isRunning { return stage.color }
        if isSelected { return KoeColors.accent }
        return .clear
    }

    private var labelColor: Color {
        if isRunning { return stage.color }
        if isEnabled { return KoeColors.textSecondary }
        return KoeColors.textLight
    }

    private var effectiveOpacity: Double {
        if !stage.isToggleable { return 1.0 }
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
