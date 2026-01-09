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
    var onSetupRequired: ((NodeInfo) -> Void)?

    @State private var isHovered = false
    @State private var lastTapTime: Date = .distantPast

    private let nodeSize: CGFloat = 44
    private let cornerRadius: CGFloat = 10
    private let doubleTapThreshold: TimeInterval = 0.3

    /// Check if this node requires setup
    private var nodeSetupState: NodeSetupState {
        let nodeInfo = stage.nodeInfo
        guard nodeInfo.requiresSetup else { return .notNeeded }

        // Check job scheduler for setup state
        let queueState = JobScheduler.shared.setupState(for: nodeInfo.typeId)
        if case .notNeeded = queueState {
            // Not in queue - check if actually set up
            // TODO: Add actual file verification here
            return .setupRequired
        }
        return queueState
    }

    /// Whether setup is currently in progress
    private var isSettingUp: Bool {
        if case .settingUp = nodeSetupState { return true }
        return false
    }

    /// Get setup progress (0.0 to 1.0)
    private var setupProgress: Double {
        if case .settingUp(let progress) = nodeSetupState {
            return progress
        }
        return 0
    }

    /// Whether setup is required (not done yet)
    private var needsSetup: Bool {
        if case .setupRequired = nodeSetupState { return true }
        return false
    }

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
    /// - Single tap: toggle immediately (for toggleable nodes) or show setup popup
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

            // If setup is in progress, don't allow interaction
            if isSettingUp {
                return
            }

            // If setup is required, show setup confirmation
            if needsSetup {
                onSetupRequired?(stage.nodeInfo)
                return
            }

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

                // Toggle indicator (for toggleable nodes) - hide during setup
                if stage.isToggleable && !isRunning && !isSettingUp && !needsSetup {
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

                // Experimental badge (flask icon in bottom-left)
                if stage.nodeInfo.isExperimental {
                    Image(systemName: "flask")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.orange)
                        .frame(width: nodeSize, height: nodeSize, alignment: .bottomLeading)
                        .offset(x: 4, y: -4)
                }

                // Setup required badge (download icon in bottom-right)
                if needsSetup {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.orange)
                        .frame(width: nodeSize, height: nodeSize, alignment: .bottomTrailing)
                        .offset(x: -4, y: -4)
                }

                // Setting up indicator - iOS-style circular progress
                if isSettingUp {
                    ZStack {
                        // Background track
                        Circle()
                            .stroke(Color.orange.opacity(0.2), lineWidth: 3)
                            .frame(width: nodeSize + 6, height: nodeSize + 6)

                        // Progress ring
                        Circle()
                            .trim(from: 0, to: setupProgress)
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: nodeSize + 6, height: nodeSize + 6)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: setupProgress)
                    }
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
