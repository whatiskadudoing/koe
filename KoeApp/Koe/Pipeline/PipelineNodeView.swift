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

    // Use shared layout constants
    private var nodeSize: CGFloat { PipelineLayout.nodeSize }
    private var cornerRadius: CGFloat { PipelineLayout.cornerRadius }
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
        ZStack {
            // Background from provider
            uiProvider.pipelineBackground(context: uiContext)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(
                    color: .black.opacity(isHovered ? 0.10 : 0.05),
                    radius: isHovered ? 8 : 4,
                    y: 2
                )

            // Content: Icon centered, label at bottom (inside card)
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 8) // Space for top badges

                // Icon from provider
                uiProvider.pipelineIcon(context: uiContext)
                    .frame(width: nodeSize - 16, height: nodeSize - 28)

                // Name label inside card
                Text(displayName)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.bottom, 4)
            }

            // Top badge bar - all status icons organized at top
            HStack(spacing: 2) {
                // Left side badges
                HStack(spacing: 2) {
                    // Experimental badge (flask icon)
                    if stage.nodeInfo.isExperimental && !stage.nodeInfo.isComposite {
                        Image(systemName: "flask.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.orange)
                    }

                    // Composite node badge (layers icon) - clickable to expand
                    if stage.nodeInfo.isComposite {
                        Button(action: {
                            onOpenComposite?(stage.nodeInfo)
                        }) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // Right side badges
                HStack(spacing: 2) {
                    // Setup required badge (download icon)
                    if needsSetup && !setupFailed && !isSettingUp {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.orange)
                    }

                    // Setup failed badge (warning icon)
                    if setupFailed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.red)
                    }

                    // Setting up indicator - percentage badge
                    if isSettingUp {
                        Text("\(Int(setupProgress * 100))%")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(Color.orange)
                            )
                    }

                    // Badge from provider (error indicator, etc.)
                    if !stage.isToggleable, let badge = uiProvider.pipelineBadge(context: uiContext) {
                        badge
                    }

                    // Toggle indicator (for toggleable nodes) - hide during setup
                    if stage.isToggleable && !isRunning && !isSettingUp && !needsSetup && !setupFailed {
                        NodeToggleIndicator(
                            isOn: $isEnabled,
                            size: 8
                        )
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: nodeSize, height: nodeSize)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(borderColor, lineWidth: 2)
        )
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
