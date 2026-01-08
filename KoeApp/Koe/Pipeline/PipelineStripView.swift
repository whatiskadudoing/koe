import SwiftUI
import KoeUI
import KoePipeline

/// Main container that displays the horizontal pipeline visualization
struct PipelineStripView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedStage: PipelineStageInfo?

    var body: some View {
        // Pipeline strip with nodes
        HStack(spacing: 0) {
            ForEach(Array(PipelineStageInfo.visibleStages.enumerated()), id: \.element.id) { index, stage in
                HStack(spacing: 0) {
                    // Connector (skip for first node)
                    if index > 0 {
                        PipelineConnector(isActive: isConnectorActive(beforeIndex: index))
                    }

                    // Node
                    // - Single tap: toggles on/off (if toggleable)
                    // - Double tap: opens settings (if has settings)
                    PipelineNodeView(
                        stage: stage,
                        isEnabled: binding(for: stage),
                        isSelected: selectedStage == stage,
                        isRunning: isStageRunning(stage),
                        metrics: metricsFor(stage),
                        onToggle: { toggleStage(stage) },
                        onOpenSettings: { selectedStage = stage }
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(KoeColors.surface.opacity(0.5))
        .cornerRadius(16)
    }

    // MARK: - Helpers

    private func toggleStage(_ stage: PipelineStageInfo) {
        switch stage {
        case .improve:
            appState.isRefinementEnabled.toggle()
        case .autoEnter:
            appState.isAutoEnterEnabled.toggle()
        default:
            break
        }
    }

    private func binding(for stage: PipelineStageInfo) -> Binding<Bool> {
        switch stage {
        case .improve:
            return Binding(
                get: { appState.isRefinementEnabled },
                set: { appState.isRefinementEnabled = $0 }
            )
        case .autoEnter:
            return Binding(
                get: { appState.isAutoEnterEnabled },
                set: { appState.isAutoEnterEnabled = $0 }
            )
        default:
            // Hotkey, Transcription, AutoType are always enabled
            return .constant(true)
        }
    }

    private func isStageEnabled(_ stage: PipelineStageInfo) -> Bool {
        switch stage {
        case .improve:
            return appState.isRefinementEnabled
        case .autoEnter:
            return appState.isAutoEnterEnabled
        default:
            return true
        }
    }

    /// Determine if a stage is currently running based on recording state
    private func isStageRunning(_ stage: PipelineStageInfo) -> Bool {
        switch appState.recordingState {
        case .idle:
            return false
        case .recording:
            // Recording means trigger is active (hotkey held or voice command)
            return stage == .trigger
        case .transcribing:
            return stage == .transcription
        case .refining:
            // During refining, the AI improve stage is running
            return stage == .improve
        }
    }

    private func isConnectorActive(beforeIndex index: Int) -> Bool {
        let stages = PipelineStageInfo.visibleStages
        guard index > 0 && index < stages.count else { return false }

        let previousStage = stages[index - 1]
        let currentStage = stages[index]

        return isStageEnabled(previousStage) && isStageEnabled(currentStage)
    }

    private func metricsFor(_ stage: PipelineStageInfo) -> ElementExecutionMetrics? {
        guard let typeId = stage.pipelineTypeId else {
            return nil
        }
        let metrics = appState.lastMetrics(for: typeId)
        return metrics
    }

    private func shortName(_ typeId: String) -> String {
        switch typeId {
        case "language-improvement": return "Imp"
        case "prompt-optimizer": return "Pmt"
        case "auto-type": return "Typ"
        case "auto-enter": return "Ent"
        default: return String(typeId.prefix(3))
        }
    }
}

// Debug view to show current metrics state
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
            .frame(width: 400)
        }
    }

    return PreviewWrapper()
}
