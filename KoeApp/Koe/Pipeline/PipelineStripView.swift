import SwiftUI
import KoeUI
import KoePipeline

/// Main container that displays the horizontal pipeline visualization
/// Shows parallel triggers at the start, then sequential processing stages
struct PipelineStripView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedStage: PipelineStageInfo?

    /// Node state controller - manages toggle states and relationships
    private var nodeController: NodeStateController<PipelineStageInfo> {
        NodeStateController.forPipeline(appState: appState)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Parallel triggers section (includes merge connector)
            ParallelTriggersView(
                nodeController: nodeController,
                selectedStage: $selectedStage,
                isHotkeyRunning: isHotkeyRunning,
                isVoiceRunning: isVoiceRunning,
                onOpenSettings: { stage in selectedStage = stage }
            )

            // Sequential stages (vertically centered)
            ForEach(Array(PipelineStageInfo.sequentialStages.enumerated()), id: \.element.id) { index, stage in
                HStack(spacing: 0) {
                    // Connector between sequential stages (skip first one - merge connector handles it)
                    if index > 0 {
                        PipelineConnector(
                            isActive: isConnectorActive(stage: stage, previousIndex: index - 1),
                            color: activeTriggerColor
                        )
                    }

                    PipelineNodeView(
                        stage: stage,
                        isEnabled: nodeController.binding(for: stage),
                        isSelected: selectedStage == stage,
                        isRunning: isStageRunning(stage),
                        metrics: metricsFor(stage),
                        onToggle: { nodeController.toggle(stage) },
                        onOpenSettings: { selectedStage = stage }
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(KoeColors.surface.opacity(0.5))
        .cornerRadius(16)
    }

    // MARK: - Computed Properties

    /// Color for active pipeline - consistent blue accent
    private var activeTriggerColor: Color {
        KoeColors.accent
    }

    private var isHotkeyRunning: Bool {
        appState.recordingState == .recording && !appState.isVoiceCommandTriggered
    }

    private var isVoiceRunning: Bool {
        appState.recordingState == .recording && appState.isVoiceCommandTriggered
    }

    private var isAnyTriggerEnabled: Bool {
        nodeController.isEnabled(.hotkeyTrigger) || nodeController.isEnabled(.voiceTrigger)
    }

    // MARK: - Stage Helpers

    private func isStageRunning(_ stage: PipelineStageInfo) -> Bool {
        switch appState.recordingState {
        case .idle:
            return false
        case .recording:
            return stage == .recorder
        case .transcribing:
            return stage == .transcribe
        case .refining:
            return stage == .improve
        }
    }

    private func isConnectorActive(stage: PipelineStageInfo, previousIndex: Int) -> Bool {
        let stages = PipelineStageInfo.sequentialStages

        // First connector connects from triggers to first sequential stage
        if previousIndex < 0 {
            return isAnyTriggerEnabled && nodeController.isEnabled(stage)
        }

        guard previousIndex < stages.count else { return false }

        let previousStage = stages[previousIndex]
        return nodeController.isEnabled(previousStage) && nodeController.isEnabled(stage)
    }

    private func metricsFor(_ stage: PipelineStageInfo) -> ElementExecutionMetrics? {
        guard let typeId = stage.pipelineTypeId else {
            return nil
        }
        return appState.lastMetrics(for: typeId)
    }
}

// MARK: - Parallel Triggers View

struct ParallelTriggersView: View {
    let nodeController: NodeStateController<PipelineStageInfo>
    @Binding var selectedStage: PipelineStageInfo?
    let isHotkeyRunning: Bool
    let isVoiceRunning: Bool
    let onOpenSettings: (PipelineStageInfo) -> Void

    private var isAnyTriggerEnabled: Bool {
        nodeController.isEnabled(.hotkeyTrigger) || nodeController.isEnabled(.voiceTrigger)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Triggers stacked vertically
            VStack(spacing: 8) {
                // Hotkey trigger - uses controller for state and dimming
                triggerNode(
                    stage: .hotkeyTrigger,
                    isRunning: isHotkeyRunning,
                    isDimmedByOther: isVoiceRunning
                )

                // Voice trigger - uses controller for state and dimming
                triggerNode(
                    stage: .voiceTrigger,
                    isRunning: isVoiceRunning,
                    isDimmedByOther: isHotkeyRunning
                )
            }

            // Merge lines from both triggers
            PipelineMergeConnector(
                isTopActive: isHotkeyRunning,
                isBottomActive: isVoiceRunning,
                isMergeActive: isAnyTriggerEnabled,
                activeColor: KoeColors.accent
            )
        }
    }

    @ViewBuilder
    private func triggerNode(stage: PipelineStageInfo, isRunning: Bool, isDimmedByOther: Bool) -> some View {
        PipelineNodeView(
            stage: stage,
            isEnabled: nodeController.binding(for: stage),
            isSelected: selectedStage == stage,
            isRunning: isRunning,
            metrics: nil,
            onToggle: { nodeController.toggle(stage) },
            onOpenSettings: { onOpenSettings(stage) }
        )
        .opacity(isDimmedByOther ? 0.4 : 1.0)
    }
}

// MARK: - Merge Connector

struct PipelineMergeConnector: View {
    let isTopActive: Bool
    let isBottomActive: Bool
    let isMergeActive: Bool  // Whether the output line should be active
    let activeColor: Color

    // Match the actual node size (44) + label (~16) = 60
    private let nodeHeight: CGFloat = 60
    private let spacing: CGFloat = 8
    private let mergeWidth: CGFloat = 16  // Width for the merge lines
    private let outputWidth: CGFloat = 20 // Width for output line

    private var inactiveColor: Color { KoeColors.textLighter.opacity(0.4) }

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            // Position lines at the vertical center of each trigger node
            let topY = nodeHeight / 2
            let bottomY = size.height - (nodeHeight / 2)
            let mergeX = mergeWidth  // X position where lines merge

            // Line from top trigger to merge point
            var topPath = Path()
            topPath.move(to: CGPoint(x: 0, y: topY))
            topPath.addLine(to: CGPoint(x: mergeX, y: topY))
            topPath.addLine(to: CGPoint(x: mergeX, y: midY))
            context.stroke(
                topPath,
                with: .color(isTopActive ? activeColor : inactiveColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            // Line from bottom trigger to merge point
            var bottomPath = Path()
            bottomPath.move(to: CGPoint(x: 0, y: bottomY))
            bottomPath.addLine(to: CGPoint(x: mergeX, y: bottomY))
            bottomPath.addLine(to: CGPoint(x: mergeX, y: midY))
            context.stroke(
                bottomPath,
                with: .color(isBottomActive ? activeColor : inactiveColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            // Output line from merge point to next node
            var outPath = Path()
            outPath.move(to: CGPoint(x: mergeX, y: midY))
            outPath.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(
                outPath,
                with: .color(isMergeActive ? activeColor : inactiveColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
        }
        .frame(width: mergeWidth + outputWidth, height: (nodeHeight * 2) + spacing)
    }
}

// MARK: - Debug View

struct PipelineMetricsDebugView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Metrics: \(appState.lastStageMetrics.count)")
                .font(.system(size: 9))
                .foregroundColor(.gray)

            ForEach(Array(appState.lastStageMetrics.keys.sorted()), id: \.self) { key in
                if let m = appState.lastStageMetrics[key] {
                    Text("\(key): \(m.formattedDuration)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(4)
        .background(Color.yellow.opacity(0.2))
        .cornerRadius(4)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedStage: PipelineStageInfo? = nil

        var body: some View {
            VStack {
                PipelineStripView(selectedStage: $selectedStage)
                    .environment(AppState.shared)
            }
            .padding()
            .background(KoeColors.background)
            .frame(width: 500)
        }
    }

    return PreviewWrapper()
}
