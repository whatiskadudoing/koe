import KoePipeline
import KoeUI
import SwiftUI

/// Vertical pipeline visualization with stage containers
/// Replaces the horizontal flow with a vertical, stage-based layout
struct VerticalPipelineView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedStage: PipelineStageInfo?

    /// State for setup confirmation popup
    @State private var showSetupConfirmation = false
    @State private var setupNodeInfo: NodeInfo?

    /// Whether to show the recording stage (always-on, can be hidden)
    private let showRecordingStage = false

    /// Node state controller
    private var nodeController: NodeStateController<PipelineStageInfo> {
        NodeStateController.forPipeline(appState: appState)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                // Triggers
                triggersContainer

                // Recording (optional - hidden by default)
                if showRecordingStage {
                    recordingContainer
                }

                // Transcription
                transcriptionContainer

                // AI Processing
                aiProcessingContainer

                // Output
                outputContainer
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
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

    // MARK: - Stage Containers

    private var triggersContainer: some View {
        PipelineStageContainer(title: "Triggers") {
            PipelineStageRow {
                ForEach(PipelineStageInfo.triggerStages, id: \.id) { stage in
                    stageNode(stage)
                        .opacity(dimOpacity(for: stage))
                }
            }
        }
    }

    private var recordingContainer: some View {
        PipelineStageContainer(title: "Recording") {
            PipelineStageRow {
                stageNode(.recorder)
            }
        }
    }

    private var transcriptionContainer: some View {
        PipelineStageContainer(title: "Transcription") {
            VStack(alignment: .center, spacing: 0) {
                // Row 1: Transcription engines
                PipelineStageRow {
                    ForEach(PipelineStageInfo.transcriptionStages, id: \.id) { stage in
                        stageNode(stage)
                    }
                }

                // Row 2: Live Preview (only available with WhisperKit)
                if isWhisperKitEnabled {
                    PipelineRowSeparator()

                    PipelineStageRow {
                        stageNode(.livePreview)
                    }
                }
            }
        }
    }

    private var aiProcessingContainer: some View {
        PipelineStageContainer(title: "AI Processing") {
            VStack(alignment: .center, spacing: 0) {
                // Row 1: AI Processing engines
                PipelineStageRow {
                    ForEach(PipelineStageInfo.aiProcessingStages, id: \.id) { stage in
                        stageNode(stage)
                    }
                }

                // Row 2: Translate options (only when Translate/ai-fast is enabled)
                if nodeController.isEnabled(.aiFast), let aiNode = NodeRegistry.shared.node(for: "ai-fast") {
                    PipelineRowSeparator()

                    TranslateOptionsRow(parentNode: aiNode)
                }
            }
        }
    }

    private var outputContainer: some View {
        PipelineStageContainer(title: "Output") {
            PipelineStageRow {
                ForEach(PipelineStageInfo.postAIProcessingStages, id: \.id) { stage in
                    stageNode(stage)
                }
            }
        }
    }

    // MARK: - Node Views

    @ViewBuilder
    private func stageNode(_ stage: PipelineStageInfo) -> some View {
        PipelineNodeView(
            stage: stage,
            isEnabled: nodeController.binding(for: stage),
            isSelected: selectedStage == stage,
            isRunning: isStageRunning(stage),
            metrics: metricsFor(stage),
            onToggle: { nodeController.toggle(stage) },
            onOpenSettings: { selectedStage = stage },
            onSetupRequired: handleSetupRequired,
            onOpenComposite: nil
        )
    }

    // MARK: - State Helpers

    private var isAnyTriggerEnabled: Bool {
        nodeController.isEnabled(.hotkeyTrigger)
            || nodeController.isEnabled(.voiceTrigger)
            || nodeController.isEnabled(.nativeMacTrigger)
    }

    private var isAnyTranscriptionEnabled: Bool {
        nodeController.isEnabled(.transcribeApple)
            || nodeController.isEnabled(.transcribeWhisperKitBalanced)
            || nodeController.isEnabled(.transcribeWhisperKitAccurate)
    }

    private var isWhisperKitEnabled: Bool {
        nodeController.isEnabled(.transcribeWhisperKitBalanced)
            || nodeController.isEnabled(.transcribeWhisperKitAccurate)
    }

    private var isAnyAIEnabled: Bool {
        nodeController.isEnabled(.aiFast)
            || nodeController.isEnabled(.aiBalanced)
            || nodeController.isEnabled(.aiReasoning)
            || nodeController.isEnabled(.aiPromptEnhancer)
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

    private func isStageRunning(_ stage: PipelineStageInfo) -> Bool {
        switch appState.recordingState {
        case .idle:
            return false
        case .recording:
            return stage == .recorder || stage.isTrigger
        case .transcribing:
            return stage.isTranscriptionEngine
        case .refining:
            return stage.isAIProcessingEngine
        }
    }

    private func dimOpacity(for stage: PipelineStageInfo) -> Double {
        // Dim triggers when another trigger is running
        if stage.isTrigger {
            if stage == .hotkeyTrigger && (isVoiceRunning || isToggleRunning) { return 0.4 }
            if stage == .voiceTrigger && (isHotkeyRunning || isToggleRunning) { return 0.4 }
            if stage == .nativeMacTrigger && (isHotkeyRunning || isVoiceRunning) { return 0.4 }
        }
        return 1.0
    }

    private func metricsFor(_ stage: PipelineStageInfo) -> ElementExecutionMetrics? {
        guard let typeId = stage.pipelineTypeId else { return nil }
        return appState.lastMetrics(for: typeId)
    }

    // MARK: - Setup

    private func handleSetupRequired(_ nodeInfo: NodeInfo) {
        setupNodeInfo = nodeInfo
        showSetupConfirmation = true
    }

    private func confirmSetup() {
        guard let nodeInfo = setupNodeInfo else { return }

        switch nodeInfo.typeId {
        case NodeTypeId.whisperKitBalanced:
            let job = JobScheduler.createWhisperKitSetupJob(model: .balanced)
            JobScheduler.shared.submit(job)
        case NodeTypeId.whisperKitAccurate:
            let job = JobScheduler.createWhisperKitSetupJob(model: .accurate)
            JobScheduler.shared.submit(job)
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
}

// MARK: - Preview

// MARK: - Translate Options Row

/// Shows sub-options for Translate (ai-fast) in organized rows
/// Row 1: Style options (Formal, Casual) + Translate toggle
/// Row 2: Language options (only if Translate toggle is on)
struct TranslateOptionsRow: View {
    let parentNode: NodeInfo
    @State private var refreshID = UUID()

    private var subNodes: [NodeInfo] {
        parentNode.subNodes
    }

    /// Style nodes (rewrite style group)
    private var styleNodes: [NodeInfo] {
        subNodes.filter { $0.exclusiveGroup?.contains("style") == true }
    }

    /// Translate toggle node (standalone, controls language visibility)
    private var translateToggleNode: NodeInfo? {
        subNodes.first { $0.typeId.contains("translate") && $0.exclusiveGroup == nil }
    }

    /// Language nodes (gated by translate toggle)
    private var languageNodes: [NodeInfo] {
        subNodes.filter { $0.exclusiveGroup?.contains("language") == true }
    }

    /// Whether translate toggle is enabled
    private var isTranslateToggleEnabled: Bool {
        guard let node = translateToggleNode else { return false }
        return isNodeEnabled(node)
    }

    var body: some View {
        VStack(spacing: PipelineLayout.rowSpacing) {
            // Row 1: Style options + Translate toggle
            HStack(spacing: PipelineLayout.nodeRowSpacing) {
                ForEach(styleNodes) { node in
                    CompactSubNodeView(node: node, siblingNodes: subNodes)
                }

                if let toggleNode = translateToggleNode {
                    CompactSubNodeView(node: toggleNode, siblingNodes: subNodes)
                }
            }

            // Row 2: Language options (only if Translate toggle is on)
            if isTranslateToggleEnabled {
                HStack(spacing: PipelineLayout.nodeRowSpacing) {
                    ForEach(languageNodes) { node in
                        CompactSubNodeView(node: node, siblingNodes: subNodes)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isTranslateToggleEnabled)
        .id(refreshID)
        .onReceive(NotificationCenter.default.publisher(for: .subNodeExclusiveGroupChanged)) { _ in
            refreshID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshID = UUID()
        }
    }

    private func isNodeEnabled(_ node: NodeInfo) -> Bool {
        guard let key = node.persistenceKey else { return node.isAlwaysEnabled }
        return UserDefaults.standard.bool(forKey: key)
    }
}

#Preview {
    VerticalPipelineView(selectedStage: .constant(nil))
        .environment(AppState.shared)
        .frame(width: 350, height: 600)
        .background(KoeColors.background)
}
