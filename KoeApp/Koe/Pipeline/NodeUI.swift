import SwiftUI
import KoeUI
import KoePipeline

// MARK: - Node UI State

/// All possible visual states a node can be in
public enum NodeUIState: Equatable, Sendable {
    /// Node is idle, not doing anything
    case idle

    /// Node is currently processing
    case running

    /// Node completed successfully
    case completed

    /// Node failed with an error
    case failed(String?)

    /// Node was skipped (e.g., disabled)
    case skipped

    /// Node is disabled by user
    case disabled

    /// Node is temporarily dimmed (another node is running)
    case dimmed
}

// MARK: - Node UI Context

/// Context passed to node UI builders with all relevant data
public struct NodeUIContext {
    /// The node's info from registry
    public let nodeInfo: NodeInfo

    /// Current UI state
    public let state: NodeUIState

    /// Whether the node is enabled (user toggle)
    public let isEnabled: Bool

    /// Whether this node is selected in the UI
    public let isSelected: Bool

    /// Execution metrics (if available)
    public let metrics: ElementExecutionMetrics?

    /// Pipeline context with input/output data (for reports)
    public let pipelineContext: PipelineContext?

    /// The full execution record (for reports)
    public let executionRecord: PipelineExecutionRecord?

    public init(
        nodeInfo: NodeInfo,
        state: NodeUIState = .idle,
        isEnabled: Bool = true,
        isSelected: Bool = false,
        metrics: ElementExecutionMetrics? = nil,
        pipelineContext: PipelineContext? = nil,
        executionRecord: PipelineExecutionRecord? = nil
    ) {
        self.nodeInfo = nodeInfo
        self.state = state
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.metrics = metrics
        self.pipelineContext = pipelineContext
        self.executionRecord = executionRecord
    }
}

// MARK: - Node UI Provider Protocol

/// Protocol that defines all UI components a node must provide
/// Each node type implements this to control its own appearance
public protocol NodeUIProvider {
    /// The typeId this provider handles
    var typeId: String { get }

    // MARK: - Pipeline Strip UI

    /// Icon to show in the pipeline strip
    func pipelineIcon(context: NodeUIContext) -> AnyView

    /// Background for the pipeline node
    func pipelineBackground(context: NodeUIContext) -> AnyView

    /// Optional badge/indicator overlay
    func pipelineBadge(context: NodeUIContext) -> AnyView?

    // MARK: - Report UI

    /// Compact card view for history list
    func reportCard(context: NodeUIContext) -> AnyView

    /// Expanded detail view for reports
    func reportDetail(context: NodeUIContext) -> AnyView

    /// Input description for this execution
    func reportInputDescription(context: NodeUIContext) -> String

    /// Output content to display (nil for actions)
    func reportOutputContent(context: NodeUIContext) -> AnyView?

    // MARK: - Settings UI

    /// Settings panel content (nil if no settings)
    func settingsPanel(context: NodeUIContext) -> AnyView?

    // MARK: - Setup

    /// Whether this node requires setup before use
    var requiresSetup: Bool { get }
}

// MARK: - Default Implementation

/// Default UI provider with standard implementations
/// Nodes can subclass or override specific methods
open class DefaultNodeUIProvider: NodeUIProvider {
    public let typeId: String

    public init(typeId: String) {
        self.typeId = typeId
    }

    // MARK: - Pipeline Strip UI

    open func pipelineIcon(context: NodeUIContext) -> AnyView {
        let color = iconColor(for: context)

        return AnyView(
            Group {
                if context.state == .running {
                    AnimatedWaveform(
                        color: context.nodeInfo.color,
                        barCount: 4,
                        minHeight: 4,
                        maxHeight: 12
                    )
                    .frame(width: 24, height: 16)
                } else {
                    Image(systemName: context.nodeInfo.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(color)
                }
            }
        )
    }

    open func pipelineBackground(context: NodeUIContext) -> AnyView {
        let fillColor: Color = context.state == .running
            ? context.nodeInfo.color.opacity(0.15)
            : .white

        return AnyView(
            RoundedRectangle(cornerRadius: 10)
                .fill(fillColor)
        )
    }

    open func pipelineBadge(context: NodeUIContext) -> AnyView? {
        // Show toggle indicator for toggleable nodes
        if context.nodeInfo.isUserToggleable && context.state != .running {
            return AnyView(
                Circle()
                    .fill(context.isEnabled ? Color.green : KoeColors.textLighter)
                    .frame(width: 8, height: 8)
            )
        }

        // Show error indicator for failed nodes
        if case .failed = context.state {
            return AnyView(
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            )
        }

        return nil
    }

    // MARK: - Report UI

    open func reportCard(context: NodeUIContext) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: context.nodeInfo.icon)
                        .foregroundColor(context.nodeInfo.color)
                    Text(context.nodeInfo.displayName)
                        .font(.system(size: 12, weight: .medium))
                }

                if let metrics = context.metrics {
                    Text(metrics.formattedDuration)
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                }
            }
        )
    }

    open func reportDetail(context: NodeUIContext) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: context.nodeInfo.icon)
                        .font(.system(size: 14))
                        .foregroundColor(context.nodeInfo.color)
                    Text(context.nodeInfo.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if let metrics = context.metrics {
                        Text(metrics.formattedDuration)
                            .font(.system(size: 12))
                            .foregroundColor(KoeColors.textLight)
                    }
                }

                // Input
                VStack(alignment: .leading, spacing: 4) {
                    Text("Input")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(KoeColors.textLight)
                    Text(reportInputDescription(context: context))
                        .font(.system(size: 12))
                        .foregroundColor(KoeColors.textSecondary)
                }

                // Output (if any)
                if let outputView = reportOutputContent(context: context) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Output")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(KoeColors.textLight)
                        outputView
                    }
                }

                // Action description (for action nodes)
                if context.nodeInfo.isAction, let desc = context.nodeInfo.actionDescription {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                        Text(desc)
                            .font(.system(size: 12))
                            .foregroundColor(KoeColors.textSecondary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
            )
        )
    }

    open func reportInputDescription(context: NodeUIContext) -> String {
        context.nodeInfo.inputDescription
    }

    open func reportOutputContent(context: NodeUIContext) -> AnyView? {
        // Actions don't have output
        if context.nodeInfo.isAction {
            return nil
        }

        // Text output nodes show the text
        if case .text = context.nodeInfo.outputType,
           let record = context.executionRecord {
            return AnyView(
                Text(record.outputText)
                    .font(.system(size: 12))
                    .foregroundColor(KoeColors.textPrimary)
                    .lineLimit(5)
            )
        }

        return nil
    }

    open func settingsPanel(context: NodeUIContext) -> AnyView? {
        // Default: no settings panel
        // Subclasses override this
        nil
    }

    // MARK: - Setup

    open var requiresSetup: Bool {
        // Default: no setup required
        false
    }

    // MARK: - Helpers

    func iconColor(for context: NodeUIContext) -> Color {
        switch context.state {
        case .disabled, .dimmed, .skipped:
            return KoeColors.textLight
        case .failed:
            return .red
        default:
            return context.isEnabled ? context.nodeInfo.color : KoeColors.textLight
        }
    }

    func opacity(for context: NodeUIContext) -> Double {
        switch context.state {
        case .dimmed:
            return 0.4
        case .disabled, .skipped:
            return 0.5
        default:
            return context.isEnabled ? 1.0 : 0.5
        }
    }
}

// MARK: - Node UI Registry

/// Registry for node UI providers
/// Maps typeIds to their UI implementations
public final class NodeUIRegistry: @unchecked Sendable {
    public static let shared = NodeUIRegistry()

    private var providers: [String: NodeUIProvider] = [:]
    private let lock = NSLock()

    private init() {
        registerBuiltInProviders()
    }

    // MARK: - Registration

    public func register(_ provider: NodeUIProvider) {
        lock.lock()
        defer { lock.unlock() }
        providers[provider.typeId] = provider
    }

    // MARK: - Lookup

    public func provider(for typeId: String) -> NodeUIProvider {
        lock.lock()
        defer { lock.unlock() }
        return providers[typeId] ?? DefaultNodeUIProvider(typeId: typeId)
    }

    // MARK: - Built-in Providers

    private func registerBuiltInProviders() {
        // Register specialized providers
        register(TextTransformNodeUI(typeId: "text-improve"))
        register(TextTransformNodeUI(typeId: "language-improvement"))
        register(TextTransformNodeUI(typeId: "prompt-optimizer"))
        register(ActionNodeUI(typeId: "auto-type"))
        register(ActionNodeUI(typeId: "auto-enter"))
        register(RecorderNodeUI())
        register(TranscribeNodeUI())
        register(TriggerNodeUI(typeId: "hotkey-trigger"))
        register(TriggerNodeUI(typeId: "voice-trigger"))
        register(WhisperKitNodeUI())
    }
}

// MARK: - Specialized Node UI Providers

/// UI for text transformation nodes (improve, etc.)
public class TextTransformNodeUI: DefaultNodeUIProvider {
    public override func reportOutputContent(context: NodeUIContext) -> AnyView? {
        guard let record = context.executionRecord else { return nil }

        // Show before/after comparison if enabled
        if context.nodeInfo.showsComparison {
            return AnyView(
                VStack(alignment: .leading, spacing: 8) {
                    // Before
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Before")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(KoeColors.textLight)
                        Text(record.inputText)
                            .font(.system(size: 11))
                            .foregroundColor(KoeColors.textSecondary)
                            .lineLimit(3)
                    }
                    .padding(8)
                    .background(KoeColors.surface.opacity(0.5))
                    .cornerRadius(6)

                    // Arrow
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                        .frame(maxWidth: .infinity)

                    // After
                    VStack(alignment: .leading, spacing: 2) {
                        Text("After")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(context.nodeInfo.color)
                        Text(record.outputText)
                            .font(.system(size: 11))
                            .foregroundColor(KoeColors.textPrimary)
                            .lineLimit(3)
                    }
                    .padding(8)
                    .background(context.nodeInfo.color.opacity(0.1))
                    .cornerRadius(6)
                }
            )
        }

        return AnyView(
            Text(record.outputText)
                .font(.system(size: 12))
                .foregroundColor(KoeColors.textPrimary)
                .lineLimit(5)
        )
    }
}

/// UI for action nodes (auto-type, auto-enter)
public class ActionNodeUI: DefaultNodeUIProvider {
    public override func reportDetail(context: NodeUIContext) -> AnyView {
        AnyView(
            HStack(spacing: 8) {
                Image(systemName: context.nodeInfo.icon)
                    .font(.system(size: 14))
                    .foregroundColor(context.nodeInfo.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.nodeInfo.displayName)
                        .font(.system(size: 12, weight: .medium))

                    if let desc = context.nodeInfo.actionDescription {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                            Text(desc)
                                .font(.system(size: 11))
                                .foregroundColor(KoeColors.textSecondary)
                        }
                    }
                }

                Spacer()

                if let metrics = context.metrics {
                    Text(metrics.formattedDuration)
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
            )
        )
    }

    public override func reportInputDescription(context: NodeUIContext) -> String {
        if typeId == "auto-type", let record = context.executionRecord {
            return record.outputText
        }
        return context.nodeInfo.inputDescription
    }
}

/// UI for recorder node
public class RecorderNodeUI: DefaultNodeUIProvider {
    public init() {
        super.init(typeId: "recorder")
    }

    public override func pipelineIcon(context: NodeUIContext) -> AnyView {
        if context.state == .running {
            // Show animated recording indicator
            return AnyView(
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 2)
                        .frame(width: 20, height: 20)
                        .scaleEffect(context.state == .running ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: context.state)
                }
            )
        }
        return super.pipelineIcon(context: context)
    }

    public override func reportOutputContent(context: NodeUIContext) -> AnyView? {
        // Could show audio waveform here
        if let metrics = context.metrics {
            return AnyView(
                HStack {
                    Image(systemName: "waveform")
                        .foregroundColor(context.nodeInfo.color)
                    Text("Audio recorded")
                        .font(.system(size: 11))
                        .foregroundColor(KoeColors.textSecondary)
                    Spacer()
                    Text(metrics.formattedDuration)
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                }
            )
        }
        return nil
    }
}

/// UI for transcribe node
public class TranscribeNodeUI: DefaultNodeUIProvider {
    public init() {
        super.init(typeId: "transcribe")
    }

    public override func reportOutputContent(context: NodeUIContext) -> AnyView? {
        guard let record = context.executionRecord else { return nil }

        // Show transcription with character count
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Text(record.inputText.isEmpty ? record.outputText : record.inputText)
                    .font(.system(size: 12))
                    .foregroundColor(KoeColors.textPrimary)
                    .lineLimit(5)

                if let metrics = context.metrics {
                    Text("\(metrics.outputCharCount) characters")
                        .font(.system(size: 10))
                        .foregroundColor(KoeColors.textLight)
                }
            }
        )
    }
}

/// UI for trigger nodes
public class TriggerNodeUI: DefaultNodeUIProvider {
    public override func pipelineBadge(context: NodeUIContext) -> AnyView? {
        // Triggers show enabled/disabled more prominently
        if context.nodeInfo.isUserToggleable {
            return AnyView(
                Circle()
                    .fill(context.isEnabled ? Color.green : KoeColors.textLighter)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 1.5)
                    )
            )
        }
        return nil
    }

    public override func reportDetail(context: NodeUIContext) -> AnyView {
        AnyView(
            HStack(spacing: 8) {
                Image(systemName: context.nodeInfo.icon)
                    .font(.system(size: 14))
                    .foregroundColor(context.nodeInfo.color)

                Text(context.nodeInfo.displayName)
                    .font(.system(size: 12, weight: .medium))

                Text("triggered")
                    .font(.system(size: 11))
                    .foregroundColor(KoeColors.textSecondary)

                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(context.nodeInfo.color.opacity(0.3), lineWidth: 1)
            )
        )
    }
}

/// UI for WhisperKit transcription node (requires setup)
public class WhisperKitNodeUI: DefaultNodeUIProvider {
    public init() {
        super.init(typeId: "transcribe-whisperkit")
    }

    public override var requiresSetup: Bool {
        // WhisperKit requires model download/compilation
        // Actual readiness is checked by JobScheduler
        true
    }
}

// MARK: - Convenience Extensions

extension NodeRegistry {
    /// Get UI provider for a node
    public func uiProvider(for typeId: String) -> NodeUIProvider {
        NodeUIRegistry.shared.provider(for: typeId)
    }
}

extension NodeInfo {
    /// Get the UI provider for this node
    public var uiProvider: NodeUIProvider {
        NodeUIRegistry.shared.provider(for: typeId)
    }

    /// Create a UI context for this node
    public func uiContext(
        state: NodeUIState = .idle,
        isEnabled: Bool = true,
        isSelected: Bool = false,
        metrics: ElementExecutionMetrics? = nil,
        executionRecord: PipelineExecutionRecord? = nil
    ) -> NodeUIContext {
        NodeUIContext(
            nodeInfo: self,
            state: state,
            isEnabled: isEnabled,
            isSelected: isSelected,
            metrics: metrics,
            executionRecord: executionRecord
        )
    }
}
