import KoePipeline
import KoeUI
import SwiftUI

/// Main container that displays the horizontal pipeline visualization
/// Shows parallel triggers at the start, then sequential processing stages
struct PipelineStripView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedStage: PipelineStageInfo?
    var onOpenComposite: ((NodeInfo) -> Void)?

    /// State for setup confirmation popup
    @State private var showSetupConfirmation = false
    @State private var setupNodeInfo: NodeInfo?

    /// Node state controller - manages toggle states and relationships
    private var nodeController: NodeStateController<PipelineStageInfo> {
        NodeStateController.forPipeline(appState: appState)
    }

    /// Handle setup required callback
    private func handleSetupRequired(_ nodeInfo: NodeInfo) {
        setupNodeInfo = nodeInfo
        showSetupConfirmation = true
    }

    /// Confirm setup and queue the job
    private func confirmSetup() {
        guard let nodeInfo = setupNodeInfo else { return }

        // Create and submit the setup job based on node type
        switch nodeInfo.typeId {
        // WhisperKit transcription models
        case NodeTypeId.whisperKitBalanced:
            let job = JobScheduler.createWhisperKitSetupJob(model: .balanced)
            JobScheduler.shared.submit(job)
        case NodeTypeId.whisperKitAccurate:
            let job = JobScheduler.createWhisperKitSetupJob(model: .accurate)
            JobScheduler.shared.submit(job)

        // AI processing models
        case NodeTypeId.aiFast:
            let job = JobScheduler.createAISetupJob(model: .fast)
            JobScheduler.shared.submit(job)
        case NodeTypeId.aiBalanced:
            let job = JobScheduler.createAISetupJob(model: .balanced)
            JobScheduler.shared.submit(job)
        case NodeTypeId.aiReasoning:
            let job = JobScheduler.createAISetupJob(model: .reasoning)
            JobScheduler.shared.submit(job)

        default:
            break
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Parallel triggers section (includes merge connector)
            ParallelTriggersView(
                nodeController: nodeController,
                selectedStage: $selectedStage,
                isHotkeyRunning: isHotkeyRunning,
                isVoiceRunning: isVoiceRunning,
                onOpenSettings: { stage in selectedStage = stage },
                onSetupRequired: handleSetupRequired,
                onOpenComposite: onOpenComposite
            )

            // Pre-transcription stages (recorder)
            ForEach(Array(PipelineStageInfo.preTranscriptionStages.enumerated()), id: \.element.id) { index, stage in
                HStack(spacing: 0) {
                    if index > 0 {
                        PipelineConnector(isActive: true, color: activeTriggerColor)
                    }

                    PipelineNodeView(
                        stage: stage,
                        isEnabled: nodeController.binding(for: stage),
                        isSelected: selectedStage == stage,
                        isRunning: isStageRunning(stage),
                        metrics: metricsFor(stage),
                        onToggle: { nodeController.toggle(stage) },
                        onOpenSettings: { selectedStage = stage },
                        onSetupRequired: handleSetupRequired,
                        onOpenComposite: onOpenComposite
                    )
                }
            }

            // Parallel transcription engines section
            ParallelTranscriptionView(
                nodeController: nodeController,
                selectedStage: $selectedStage,
                isTranscribing: appState.recordingState == .transcribing,
                onOpenSettings: { stage in selectedStage = stage },
                onSetupRequired: handleSetupRequired,
                onOpenComposite: onOpenComposite
            )

            // Parallel AI processing engines section
            ParallelAIProcessingView(
                nodeController: nodeController,
                selectedStage: $selectedStage,
                isRefining: appState.recordingState == .refining,
                onOpenSettings: { stage in selectedStage = stage },
                onSetupRequired: handleSetupRequired,
                onOpenComposite: onOpenComposite
            )

            // Post-AI processing stages (type, enter)
            ForEach(Array(PipelineStageInfo.postAIProcessingStages.enumerated()), id: \.element.id) { index, stage in
                HStack(spacing: 0) {
                    if index > 0 {
                        PipelineConnector(isActive: true, color: activeTriggerColor)
                    }

                    PipelineNodeView(
                        stage: stage,
                        isEnabled: nodeController.binding(for: stage),
                        isSelected: selectedStage == stage,
                        isRunning: isStageRunning(stage),
                        metrics: metricsFor(stage),
                        onToggle: { nodeController.toggle(stage) },
                        onOpenSettings: { selectedStage = stage },
                        onSetupRequired: handleSetupRequired,
                        onOpenComposite: onOpenComposite
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(KoeColors.surface.opacity(0.5))
        .cornerRadius(16)
        .alert("Setup Required", isPresented: $showSetupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Set Up") {
                confirmSetup()
            }
        } message: {
            if let info = setupNodeInfo {
                Text("\(info.displayName) needs to be set up before you can use it.")
            }
        }
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
            // All transcription engine nodes show running state when transcribing
            return stage.isTranscriptionEngine
        case .refining:
            // All AI processing engine nodes show running state when refining
            return stage.isAIProcessingEngine
        }
    }

    private func isConnectorActive(stage: PipelineStageInfo, previousIndex: Int) -> Bool {
        // Sequential connectors are always active - they just show the flow path
        // The nodes themselves show enabled/disabled state via opacity
        return true
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
    var onSetupRequired: ((NodeInfo) -> Void)?
    var onOpenComposite: ((NodeInfo) -> Void)?

    private var isAnyTriggerEnabled: Bool {
        nodeController.isEnabled(.hotkeyTrigger) || nodeController.isEnabled(.voiceTrigger)
    }

    private var isHotkeyEnabled: Bool {
        nodeController.isEnabled(.hotkeyTrigger)
    }

    private var isVoiceEnabled: Bool {
        nodeController.isEnabled(.voiceTrigger)
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
            // Lines are active based on whether trigger is ENABLED (not just running)
            PipelineMergeConnector(
                isTopActive: isHotkeyEnabled,
                isBottomActive: isVoiceEnabled,
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
            onOpenSettings: { onOpenSettings(stage) },
            onSetupRequired: onSetupRequired,
            onOpenComposite: onOpenComposite
        )
        .opacity(isDimmedByOther ? 0.4 : 1.0)
    }
}

// MARK: - Parallel Transcription View

struct ParallelTranscriptionView: View {
    let nodeController: NodeStateController<PipelineStageInfo>
    @Binding var selectedStage: PipelineStageInfo?
    let isTranscribing: Bool
    let onOpenSettings: (PipelineStageInfo) -> Void
    var onSetupRequired: ((NodeInfo) -> Void)?
    var onOpenComposite: ((NodeInfo) -> Void)?

    private var isAppleEnabled: Bool {
        nodeController.isEnabled(.transcribeApple)
    }

    private var isBalancedEnabled: Bool {
        nodeController.isEnabled(.transcribeWhisperKitBalanced)
    }

    private var isAccurateEnabled: Bool {
        nodeController.isEnabled(.transcribeWhisperKitAccurate)
    }

    private var activeEngine: PipelineStageInfo? {
        if isAppleEnabled { return .transcribeApple }
        if isBalancedEnabled { return .transcribeWhisperKitBalanced }
        if isAccurateEnabled { return .transcribeWhisperKitAccurate }
        return nil
    }

    private var isAnyTranscriptionEnabled: Bool {
        activeEngine != nil
    }

    var body: some View {
        HStack(spacing: 0) {
            // Split connector from recorder to 3 transcription nodes
            TranscriptionSplitConnector(
                isTopActive: isAppleEnabled,
                isMiddleActive: isBalancedEnabled,
                isBottomActive: isAccurateEnabled,
                isSplitActive: true,
                activeColor: KoeColors.accent
            )

            // Transcription engines stacked vertically
            VStack(spacing: 4) {
                // Apple Speech
                transcriptionNode(
                    stage: .transcribeApple,
                    isRunning: isTranscribing && isAppleEnabled
                )

                // WhisperKit Balanced
                transcriptionNode(
                    stage: .transcribeWhisperKitBalanced,
                    isRunning: isTranscribing && isBalancedEnabled
                )

                // WhisperKit Accurate
                transcriptionNode(
                    stage: .transcribeWhisperKitAccurate,
                    isRunning: isTranscribing && isAccurateEnabled
                )
            }

            // Merge connector from 3 transcription nodes to next stage
            TranscriptionMergeConnector(
                isTopActive: isAppleEnabled,
                isMiddleActive: isBalancedEnabled,
                isBottomActive: isAccurateEnabled,
                isMergeActive: isAnyTranscriptionEnabled,
                activeColor: KoeColors.accent
            )
        }
    }

    @ViewBuilder
    private func transcriptionNode(stage: PipelineStageInfo, isRunning: Bool) -> some View {
        let isEnabled = nodeController.isEnabled(stage)
        let isDimmed = isTranscribing && activeEngine != stage

        PipelineNodeView(
            stage: stage,
            isEnabled: nodeController.binding(for: stage),
            isSelected: selectedStage == stage,
            isRunning: isRunning,
            metrics: nil,
            onToggle: {
                // Toggle with mutual exclusivity - disable other transcription nodes
                nodeController.toggleExclusive(stage, in: PipelineStageInfo.transcriptionStages)
            },
            onOpenSettings: { onOpenSettings(stage) },
            onSetupRequired: onSetupRequired,
            onOpenComposite: onOpenComposite
        )
        .opacity(isDimmed ? 0.4 : (isEnabled ? 1.0 : 0.6))
    }
}

// MARK: - Parallel AI Processing View

struct ParallelAIProcessingView: View {
    let nodeController: NodeStateController<PipelineStageInfo>
    @Binding var selectedStage: PipelineStageInfo?
    let isRefining: Bool
    let onOpenSettings: (PipelineStageInfo) -> Void
    var onSetupRequired: ((NodeInfo) -> Void)?
    var onOpenComposite: ((NodeInfo) -> Void)?

    private var isFastEnabled: Bool {
        nodeController.isEnabled(.aiFast)
    }

    private var isBalancedEnabled: Bool {
        nodeController.isEnabled(.aiBalanced)
    }

    private var isReasoningEnabled: Bool {
        nodeController.isEnabled(.aiReasoning)
    }

    private var activeEngine: PipelineStageInfo? {
        if isFastEnabled { return .aiFast }
        if isBalancedEnabled { return .aiBalanced }
        if isReasoningEnabled { return .aiReasoning }
        return nil
    }

    private var isAnyAIEnabled: Bool {
        activeEngine != nil
    }

    var body: some View {
        HStack(spacing: 0) {
            // Split connector from transcription merge to 3 AI nodes
            GenericSplitConnector(
                nodeStates: [isFastEnabled, isBalancedEnabled, isReasoningEnabled],
                activeColor: KoeColors.accent
            )

            // AI engines stacked vertically
            VStack(spacing: 4) {
                // Fast
                aiNode(
                    stage: .aiFast,
                    isRunning: isRefining && isFastEnabled
                )

                // Balanced
                aiNode(
                    stage: .aiBalanced,
                    isRunning: isRefining && isBalancedEnabled
                )

                // Reasoning
                aiNode(
                    stage: .aiReasoning,
                    isRunning: isRefining && isReasoningEnabled
                )
            }

            // Merge connector from 3 AI nodes to next stage
            GenericMergeConnector(
                nodeStates: [isFastEnabled, isBalancedEnabled, isReasoningEnabled],
                activeColor: KoeColors.accent
            )
        }
    }

    @ViewBuilder
    private func aiNode(stage: PipelineStageInfo, isRunning: Bool) -> some View {
        let isEnabled = nodeController.isEnabled(stage)
        let isDimmed = isRefining && activeEngine != stage

        PipelineNodeView(
            stage: stage,
            isEnabled: nodeController.binding(for: stage),
            isSelected: selectedStage == stage,
            isRunning: isRunning,
            metrics: nil,
            onToggle: {
                // Toggle with mutual exclusivity - disable other AI nodes
                nodeController.toggleExclusive(stage, in: PipelineStageInfo.aiProcessingStages)
            },
            onOpenSettings: { onOpenSettings(stage) },
            onSetupRequired: onSetupRequired,
            onOpenComposite: onOpenComposite
        )
        .opacity(isDimmed ? 0.4 : (isEnabled ? 1.0 : 0.6))
    }
}

// MARK: - Transcription Split Connector (1 input to 3 outputs)

struct TranscriptionSplitConnector: View {
    let isTopActive: Bool
    let isMiddleActive: Bool
    let isBottomActive: Bool
    let isSplitActive: Bool
    let activeColor: Color

    private let nodeHeight: CGFloat = 60  // Total slot height
    private let nodeSize: CGFloat = 44    // Actual node visual size
    private let spacing: CGFloat = 4
    private let inputWidth: CGFloat = 20
    private let splitWidth: CGFloat = 16

    private var inactiveColor: Color { KoeColors.textLighter.opacity(0.4) }

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let topY = nodeSize / 2  // Center of first node visual
            let bottomY = size.height - (nodeSize / 2)  // Center of last node visual
            let splitX = inputWidth

            // Input line from previous node to split point
            var inPath = Path()
            inPath.move(to: CGPoint(x: 0, y: midY))
            inPath.addLine(to: CGPoint(x: splitX, y: midY))
            context.stroke(
                inPath,
                with: .color(isSplitActive ? activeColor : inactiveColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )

            // Line from split point to top node (Apple Speech)
            var topPath = Path()
            topPath.move(to: CGPoint(x: splitX, y: midY))
            topPath.addLine(to: CGPoint(x: splitX, y: topY))
            topPath.addLine(to: CGPoint(x: size.width, y: topY))
            context.stroke(
                topPath,
                with: .color(isTopActive ? activeColor : inactiveColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            // Line from split point to middle node (Balanced)
            var middlePath = Path()
            middlePath.move(to: CGPoint(x: splitX, y: midY))
            middlePath.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(
                middlePath,
                with: .color(isMiddleActive ? activeColor : inactiveColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )

            // Line from split point to bottom node (Accurate)
            var bottomPath = Path()
            bottomPath.move(to: CGPoint(x: splitX, y: midY))
            bottomPath.addLine(to: CGPoint(x: splitX, y: bottomY))
            bottomPath.addLine(to: CGPoint(x: size.width, y: bottomY))
            context.stroke(
                bottomPath,
                with: .color(isBottomActive ? activeColor : inactiveColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: inputWidth + splitWidth, height: (nodeHeight * 3) + (spacing * 2))
    }
}

// MARK: - Transcription Merge Connector (3 inputs to 1 output)

struct TranscriptionMergeConnector: View {
    let isTopActive: Bool
    let isMiddleActive: Bool
    let isBottomActive: Bool
    let isMergeActive: Bool
    let activeColor: Color

    private let nodeHeight: CGFloat = 60  // Total slot height
    private let nodeSize: CGFloat = 44    // Actual node visual size
    private let spacing: CGFloat = 4
    private let mergeWidth: CGFloat = 16
    private let outputWidth: CGFloat = 20

    private var inactiveColor: Color { KoeColors.textLighter.opacity(0.4) }

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let topY = nodeSize / 2  // Center of first node visual
            let bottomY = size.height - (nodeSize / 2)  // Center of last node visual
            let mergeX = mergeWidth

            // Line from top node to merge point
            var topPath = Path()
            topPath.move(to: CGPoint(x: 0, y: topY))
            topPath.addLine(to: CGPoint(x: mergeX, y: topY))
            topPath.addLine(to: CGPoint(x: mergeX, y: midY))
            context.stroke(
                topPath,
                with: .color(isTopActive ? activeColor : inactiveColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            // Line from middle node to merge point
            var middlePath = Path()
            middlePath.move(to: CGPoint(x: 0, y: midY))
            middlePath.addLine(to: CGPoint(x: mergeX, y: midY))
            context.stroke(
                middlePath,
                with: .color(isMiddleActive ? activeColor : inactiveColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )

            // Line from bottom node to merge point
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
        .frame(width: mergeWidth + outputWidth, height: (nodeHeight * 3) + (spacing * 2))
    }
}

// MARK: - Generic Parallel Section Connectors (Reusable for any number of nodes)

/// Generic split connector that works with any number of nodes
struct GenericSplitConnector: View {
    let nodeStates: [Bool]  // Active state for each node
    let activeColor: Color
    let nodeHeight: CGFloat = 60  // Total slot height per node (includes node + spacing)
    let spacing: CGFloat = 4

    private let inputWidth: CGFloat = 20
    private let splitWidth: CGFloat = 16
    private let nodeSize: CGFloat = 44  // Actual visual node size
    private var inactiveColor: Color { KoeColors.textLighter.opacity(0.4) }

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let splitX = inputWidth
            let hasAnyActive = nodeStates.contains(true)

            // Input line from previous node to split point
            var inPath = Path()
            inPath.move(to: CGPoint(x: 0, y: midY))
            inPath.addLine(to: CGPoint(x: splitX, y: midY))
            context.stroke(
                inPath,
                with: .color(hasAnyActive ? activeColor : inactiveColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )

            // Lines from split point to each node
            for (index, isActive) in nodeStates.enumerated() {
                // Calculate Y position: aim at center of actual node visual (not center of slot)
                let nodeY = (CGFloat(index) * nodeHeight) + (CGFloat(index) * spacing) + (nodeSize / 2)

                var path = Path()
                path.move(to: CGPoint(x: splitX, y: midY))
                path.addLine(to: CGPoint(x: splitX, y: nodeY))
                path.addLine(to: CGPoint(x: size.width, y: nodeY))
                context.stroke(
                    path,
                    with: .color(isActive ? activeColor : inactiveColor),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(
            width: inputWidth + splitWidth,
            height: (CGFloat(nodeStates.count) * nodeHeight) + (CGFloat(max(0, nodeStates.count - 1)) * spacing)
        )
    }
}

/// Generic merge connector that works with any number of nodes
struct GenericMergeConnector: View {
    let nodeStates: [Bool]  // Active state for each node
    let activeColor: Color
    let nodeHeight: CGFloat = 60  // Total slot height per node (includes node + spacing)
    let spacing: CGFloat = 4

    private let mergeWidth: CGFloat = 16
    private let outputWidth: CGFloat = 20
    private let nodeSize: CGFloat = 44  // Actual visual node size
    private var inactiveColor: Color { KoeColors.textLighter.opacity(0.4) }

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let mergeX = mergeWidth
            let hasAnyActive = nodeStates.contains(true)

            // Lines from each node to merge point
            for (index, isActive) in nodeStates.enumerated() {
                // Calculate Y position: aim at center of actual node visual (not center of slot)
                let nodeY = (CGFloat(index) * nodeHeight) + (CGFloat(index) * spacing) + (nodeSize / 2)

                var path = Path()
                path.move(to: CGPoint(x: 0, y: nodeY))
                path.addLine(to: CGPoint(x: mergeX, y: nodeY))
                path.addLine(to: CGPoint(x: mergeX, y: midY))
                context.stroke(
                    path,
                    with: .color(isActive ? activeColor : inactiveColor),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }

            // Output line from merge point to next node
            var outPath = Path()
            outPath.move(to: CGPoint(x: mergeX, y: midY))
            outPath.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(
                outPath,
                with: .color(hasAnyActive ? activeColor : inactiveColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
        }
        .frame(
            width: mergeWidth + outputWidth,
            height: (CGFloat(nodeStates.count) * nodeHeight) + (CGFloat(max(0, nodeStates.count - 1)) * spacing)
        )
    }
}

// MARK: - Split Connector

struct PipelineSplitConnector: View {
    let isTopActive: Bool
    let isBottomActive: Bool
    let isSplitActive: Bool
    let activeColor: Color

    private let nodeHeight: CGFloat = 60
    private let spacing: CGFloat = 8
    private let inputWidth: CGFloat = 20
    private let splitWidth: CGFloat = 16

    private var inactiveColor: Color { KoeColors.textLighter.opacity(0.4) }

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let topY = nodeHeight / 2
            let bottomY = size.height - (nodeHeight / 2)
            let splitX = inputWidth

            // Input line from previous node to split point
            var inPath = Path()
            inPath.move(to: CGPoint(x: 0, y: midY))
            inPath.addLine(to: CGPoint(x: splitX, y: midY))
            context.stroke(
                inPath,
                with: .color(isSplitActive ? activeColor : inactiveColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )

            // Line from split point to top transcription node
            var topPath = Path()
            topPath.move(to: CGPoint(x: splitX, y: midY))
            topPath.addLine(to: CGPoint(x: splitX, y: topY))
            topPath.addLine(to: CGPoint(x: size.width, y: topY))
            context.stroke(
                topPath,
                with: .color(isTopActive ? activeColor : inactiveColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            // Line from split point to bottom transcription node
            var bottomPath = Path()
            bottomPath.move(to: CGPoint(x: splitX, y: midY))
            bottomPath.addLine(to: CGPoint(x: splitX, y: bottomY))
            bottomPath.addLine(to: CGPoint(x: size.width, y: bottomY))
            context.stroke(
                bottomPath,
                with: .color(isBottomActive ? activeColor : inactiveColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: inputWidth + splitWidth, height: (nodeHeight * 2) + spacing)
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
    private let outputWidth: CGFloat = 20  // Width for output line

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
