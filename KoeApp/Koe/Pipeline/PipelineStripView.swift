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
        case NodeTypeId.aiPromptEnhancer:
            let job = JobScheduler.createAISetupJob(model: .promptEnhancer)
            JobScheduler.shared.submit(job)

        default:
            break
        }
    }

    var body: some View {
        PipelineContainer {
            HStack(alignment: .center, spacing: 0) {
                // Parallel triggers section (includes merge connector)
                ParallelTriggersView(
                    nodeController: nodeController,
                    selectedStage: $selectedStage,
                    isHotkeyRunning: isHotkeyRunning,
                    isVoiceRunning: isVoiceRunning,
                    isToggleRunning: isToggleRunning,
                    onOpenSettings: { stage in selectedStage = stage },
                    onSetupRequired: handleSetupRequired,
                    onOpenComposite: onOpenComposite
                )

                // Pre-transcription stages (recorder)
                ForEach(Array(PipelineStageInfo.preTranscriptionStages.enumerated()), id: \.element.id) {
                    index, stage in
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

                // Parallel transcription engines section with output branches
                TranscriptionWithBranchesView(
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
                ForEach(Array(PipelineStageInfo.postAIProcessingStages.enumerated()), id: \.element.id) {
                    index, stage in
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
        }
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
        appState.recordingState == .recording && !appState.isVoiceCommandTriggered && !appState.isToggleTriggered
    }

    private var isVoiceRunning: Bool {
        appState.recordingState == .recording && appState.isVoiceCommandTriggered
    }

    private var isToggleRunning: Bool {
        appState.recordingState == .recording && appState.isToggleTriggered
    }

    private var isAnyTriggerEnabled: Bool {
        nodeController.isEnabled(.hotkeyTrigger) || nodeController.isEnabled(.voiceTrigger)
            || nodeController.isEnabled(.nativeMacTrigger)
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
    let isToggleRunning: Bool
    let onOpenSettings: (PipelineStageInfo) -> Void
    var onSetupRequired: ((NodeInfo) -> Void)?
    var onOpenComposite: ((NodeInfo) -> Void)?

    private var isAnyTriggerEnabled: Bool {
        nodeController.isEnabled(.hotkeyTrigger) || nodeController.isEnabled(.voiceTrigger)
            || nodeController.isEnabled(.nativeMacTrigger)
    }

    private var isHotkeyEnabled: Bool {
        nodeController.isEnabled(.hotkeyTrigger)
    }

    private var isVoiceEnabled: Bool {
        nodeController.isEnabled(.voiceTrigger)
    }

    private var isToggleEnabled: Bool {
        nodeController.isEnabled(.nativeMacTrigger)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Triggers stacked vertically
            VStack(spacing: PipelineLayout.nodeSpacing) {
                // Hotkey trigger - uses controller for state and dimming
                triggerNode(
                    stage: .hotkeyTrigger,
                    isRunning: isHotkeyRunning,
                    isDimmedByOther: isVoiceRunning || isToggleRunning
                )

                // Voice trigger - uses controller for state and dimming
                triggerNode(
                    stage: .voiceTrigger,
                    isRunning: isVoiceRunning,
                    isDimmedByOther: isHotkeyRunning || isToggleRunning
                )

                // Native Mac toggle trigger (🎤 microphone key)
                triggerNode(
                    stage: .nativeMacTrigger,
                    isRunning: isToggleRunning,
                    isDimmedByOther: isHotkeyRunning || isVoiceRunning
                )
            }
            .frame(height: PipelineLayout.parallelSectionHeight(nodeCount: 3))

            // Merge lines from all triggers
            MergeConnector(
                nodeStates: [isHotkeyEnabled, isVoiceEnabled, isToggleEnabled],
                activeColor: PipelineLayout.activeColor
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
            // Split connector from recorder to transcription nodes
            SplitConnector(
                nodeStates: [isAppleEnabled, isBalancedEnabled, isAccurateEnabled],
                activeColor: PipelineLayout.activeColor
            )

            // Transcription engines stacked vertically
            VStack(spacing: PipelineLayout.nodeSpacing) {
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
            .frame(height: PipelineLayout.parallelSectionHeight(nodeCount: 3))

            // Merge connector from transcription nodes to next stage
            MergeConnector(
                nodeStates: [isAppleEnabled, isBalancedEnabled, isAccurateEnabled],
                activeColor: PipelineLayout.activeColor
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

    private var isPromptEnhancerEnabled: Bool {
        nodeController.isEnabled(.aiPromptEnhancer)
    }

    private var activeEngine: PipelineStageInfo? {
        if isFastEnabled { return .aiFast }
        if isBalancedEnabled { return .aiBalanced }
        if isReasoningEnabled { return .aiReasoning }
        if isPromptEnhancerEnabled { return .aiPromptEnhancer }
        return nil
    }

    private var isAnyAIEnabled: Bool {
        activeEngine != nil
    }

    var body: some View {
        HStack(spacing: 0) {
            // Split connector from transcription merge to AI nodes
            SplitConnector(
                nodeStates: [isFastEnabled, isBalancedEnabled, isReasoningEnabled, isPromptEnhancerEnabled],
                activeColor: PipelineLayout.activeColor
            )

            // AI engines stacked vertically
            VStack(spacing: PipelineLayout.nodeSpacing) {
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

                // Prompt Enhancer
                aiNode(
                    stage: .aiPromptEnhancer,
                    isRunning: isRefining && isPromptEnhancerEnabled
                )
            }
            .frame(height: PipelineLayout.parallelSectionHeight(nodeCount: 4))

            // Merge connector from AI nodes to next stage
            MergeConnector(
                nodeStates: [isFastEnabled, isBalancedEnabled, isReasoningEnabled, isPromptEnhancerEnabled],
                activeColor: PipelineLayout.activeColor
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

// MARK: - Transcription With Output Branches View

/// Wraps ParallelTranscriptionView and adds output branches below
/// Output branches split off from transcription but don't merge back to main pipeline
struct TranscriptionWithBranchesView: View {
    let nodeController: NodeStateController<PipelineStageInfo>
    @Binding var selectedStage: PipelineStageInfo?
    let isTranscribing: Bool
    let onOpenSettings: (PipelineStageInfo) -> Void
    var onSetupRequired: ((NodeInfo) -> Void)?
    var onOpenComposite: ((NodeInfo) -> Void)?

    private var isLivePreviewEnabled: Bool {
        nodeController.isEnabled(.livePreview)
    }

    private var isAppleEnabled: Bool {
        nodeController.isEnabled(.transcribeApple)
    }

    private var isBalancedEnabled: Bool {
        nodeController.isEnabled(.transcribeWhisperKitBalanced)
    }

    private var isAccurateEnabled: Bool {
        nodeController.isEnabled(.transcribeWhisperKitAccurate)
    }

    private var isAnyTranscriptionEnabled: Bool {
        isAppleEnabled || isBalancedEnabled || isAccurateEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main transcription section
            ParallelTranscriptionView(
                nodeController: nodeController,
                selectedStage: $selectedStage,
                isTranscribing: isTranscribing,
                onOpenSettings: onOpenSettings,
                onSetupRequired: onSetupRequired,
                onOpenComposite: onOpenComposite
            )

            // Output branch section (below transcription)
            HStack(alignment: .top, spacing: 0) {
                // Spacer to align with merge point
                // Width = splitConnector + nodeWidth + part of mergeConnector
                Spacer()
                    .frame(width: PipelineLayout.splitConnectorWidth + PipelineLayout.nodeWidth)

                // Branch connector going down from merge line
                BranchDownConnector(
                    isActive: isLivePreviewEnabled && isAnyTranscriptionEnabled
                )

                // Live Preview node
                PipelineNodeView(
                    stage: .livePreview,
                    isEnabled: nodeController.binding(for: .livePreview),
                    isSelected: selectedStage == .livePreview,
                    isRunning: isTranscribing && isLivePreviewEnabled,
                    metrics: nil,
                    onToggle: { nodeController.toggle(.livePreview) },
                    onOpenSettings: { onOpenSettings(.livePreview) },
                    onSetupRequired: onSetupRequired,
                    onOpenComposite: onOpenComposite
                )
                .opacity(isLivePreviewEnabled ? 1.0 : 0.6)
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Branch Down Connector

/// Draws a line that branches down from the transcription merge point
struct BranchDownConnector: View {
    let isActive: Bool

    var body: some View {
        Canvas { context, size in
            let color = isActive ? PipelineLayout.activeColor : PipelineLayout.inactiveColor
            let lineWidth = PipelineLayout.connectorLineWidth
            let nodeCenter = PipelineLayout.nodeSize / 2

            // Vertical line going down from top
            var vPath = Path()
            vPath.move(to: CGPoint(x: lineWidth / 2, y: 0))
            vPath.addLine(to: CGPoint(x: lineWidth / 2, y: nodeCenter))
            context.stroke(
                vPath,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )

            // Horizontal line to node
            var hPath = Path()
            hPath.move(to: CGPoint(x: lineWidth / 2, y: nodeCenter))
            hPath.addLine(to: CGPoint(x: size.width, y: nodeCenter))
            context.stroke(
                hPath,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
        }
        .frame(width: PipelineLayout.simpleConnectorWidth, height: PipelineLayout.nodeSize)
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
