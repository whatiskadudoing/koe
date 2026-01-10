import KoePipeline
import KoeUI
import SwiftUI

/// Individual node in the pipeline visualization
/// Uses NodeUIProvider for rendering - each node type controls its own appearance
///
/// Interactions:
/// - Click toggle indicator: turn on/off (if toggleable)
/// - Double tap node: open settings (if has settings)
/// - Shift + tap composite node: open sub-pipeline
struct PipelineNodeView: View {
    let stage: PipelineStageInfo
    @Binding var isEnabled: Bool
    let isSelected: Bool
    let isRunning: Bool
    let metrics: ElementExecutionMetrics?
    let onToggle: () -> Void
    let onOpenSettings: () -> Void
    var onSetupRequired: ((NodeInfo) -> Void)?
    var onOpenComposite: ((NodeInfo) -> Void)?

    /// Observe JobScheduler for reactive UI updates during setup
    @ObservedObject private var scheduler = JobScheduler.shared

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

    /// Whether setup failed
    private var setupFailed: Bool {
        if case .failed = nodeSetupState { return true }
        return false
    }

    /// Get setup failure message
    private var setupErrorMessage: String? {
        if case .failed(let message) = nodeSetupState { return message }
        return nil
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
            // Double tap
            lastTapTime = .distantPast

            // If composite node, open sub-pipeline
            if stage.nodeInfo.isComposite {
                onOpenComposite?(stage.nodeInfo)
            } else if stage.hasSettings {
                // Otherwise open settings
                onOpenSettings()
            }
        } else {
            lastTapTime = now

            // If setup is in progress, don't allow interaction
            if isSettingUp {
                return
            }

            // If setup is required or failed, show setup confirmation
            if needsSetup || setupFailed {
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
                if stage.nodeInfo.isExperimental && !stage.nodeInfo.isComposite {
                    Image(systemName: "flask")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.orange)
                        .frame(width: nodeSize, height: nodeSize, alignment: .bottomLeading)
                        .offset(x: 4, y: -4)
                }

                // Composite node badge (layers icon in bottom-left) - clickable to expand
                if stage.nodeInfo.isComposite {
                    Button(action: {
                        onOpenComposite?(stage.nodeInfo)
                    }) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.blue)
                            .padding(2)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.9))
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(width: nodeSize, height: nodeSize, alignment: .bottomLeading)
                    .offset(x: 2, y: -2)
                }

                // Setup required badge (download icon in bottom-right)
                if needsSetup && !setupFailed {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.orange)
                        .frame(width: nodeSize, height: nodeSize, alignment: .bottomTrailing)
                        .offset(x: -4, y: -4)
                }

                // Setup failed badge (warning icon in bottom-right)
                if setupFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                        .frame(width: nodeSize, height: nodeSize, alignment: .bottomTrailing)
                        .offset(x: -4, y: -4)
                }

                // Setting up indicator - percentage badge only
                if isSettingUp {
                    Text("\(Int(setupProgress * 100))%")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.orange)
                        )
                        .frame(width: nodeSize, height: nodeSize, alignment: .topTrailing)
                        .offset(x: 6, y: -6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 2)
            )

            // Name label
            Text(displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(labelColor)
                .fixedSize()
                .lineLimit(1)
        }
        .opacity(effectiveOpacity)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .help(setupErrorMessage ?? stage.nodeInfo.displayName)
    }

    private var borderColor: Color {
        if setupFailed { return .red }
        if isRunning { return stage.color }
        if isSelected { return KoeColors.accent }
        return .clear
    }

    private var labelColor: Color {
        if setupFailed { return .red }
        if isRunning { return stage.color }
        if isEnabled { return KoeColors.textSecondary }
        return KoeColors.textLight
    }

    private var effectiveOpacity: Double {
        if setupFailed { return 0.6 }
        if !stage.isToggleable { return 1.0 }
        return isEnabled ? 1.0 : 0.5
    }

    /// Display name - always show stage name
    private var displayName: String {
        stage.displayName
    }
}

#Preview {
    HStack(spacing: 20) {
        PipelineNodeView(
            stage: .transcribeApple,
            isEnabled: .constant(true),
            isSelected: false,
            isRunning: true,
            metrics: nil,
            onToggle: {},
            onOpenSettings: {}
        )

        PipelineNodeView(
            stage: .aiFast,
            isEnabled: .constant(true),
            isSelected: true,
            isRunning: false,
            metrics: ElementExecutionMetrics(
                elementId: "test",
                elementType: "ai-fast",
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
            stage: .aiFast,
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
