import KoePipeline
import KoeUI
import SwiftUI

// MARK: - Node Info

/// Complete definition of a pipeline node's properties
/// This is the single source of truth for how a node appears and behaves
public struct NodeInfo: Identifiable, Sendable {
    public var id: String { typeId }

    // MARK: - Identity

    /// Unique identifier matching pipeline element typeId
    public let typeId: String

    /// Display name shown in UI
    public let displayName: String

    /// SF Symbol icon name
    public let icon: String

    /// Theme color for this node
    public let color: Color

    // MARK: - State Behavior

    /// Whether user can toggle this node on/off
    public let isUserToggleable: Bool

    /// Whether this node is always enabled (core functionality)
    public let isAlwaysEnabled: Bool

    /// Other nodes that must be enabled for this to work
    public let requiredNodes: [String]

    /// Nodes to temporarily dim when this node is running
    public let dimsWhenRunning: [String]

    // MARK: - Report Behavior

    /// What kind of output this node produces
    public let outputType: NodeOutputType

    /// Description shown as input in reports
    public let inputDescription: String

    /// Whether this is an action (side effect) vs transformation
    public let isAction: Bool

    /// Description of the action performed (for action nodes)
    public let actionDescription: String?

    /// Whether to show before/after comparison in reports
    public let showsComparison: Bool

    // MARK: - Settings

    /// Whether this node has configurable settings
    public let hasSettings: Bool

    /// Key for storing enabled state in UserDefaults (nil = not persisted)
    public let persistenceKey: String?

    // MARK: - Mutual Exclusivity

    /// Group name for mutually exclusive nodes (only one in group can be enabled)
    /// Nodes with the same exclusiveGroup will auto-disable when another in the group is enabled
    public let exclusiveGroup: String?

    // MARK: - Experimental

    /// Whether this node uses experimental/beta features
    public let isExperimental: Bool

    // MARK: - Setup Requirements

    /// Whether this node requires setup before use (download, compile, etc.)
    public let requiresSetup: Bool

    /// Setup requirements for this node (if requiresSetup is true)
    public let setupRequirements: NodeSetupRequirements?

    // MARK: - Resource Management

    /// Whether this node uses significant memory/power and should be unloaded when not in use
    /// Resource-intensive nodes are automatically unloaded when switching away from dictation mode
    public let isResourceIntensive: Bool

    // MARK: - Composition (Sub-Pipelines)

    /// Internal nodes that make up this composite node's sub-pipeline
    /// When present, clicking this node opens a tab showing the internal pipeline
    public let subNodes: [NodeInfo]

    /// Whether this is a composite node with an internal sub-pipeline
    public var isComposite: Bool {
        !subNodes.isEmpty
    }

    // MARK: - Init

    public init(
        typeId: String,
        displayName: String,
        icon: String,
        color: Color,
        isUserToggleable: Bool = false,
        isAlwaysEnabled: Bool = true,
        requiredNodes: [String] = [],
        dimsWhenRunning: [String] = [],
        outputType: NodeOutputType = .text,
        inputDescription: String = "Previous output",
        isAction: Bool = false,
        actionDescription: String? = nil,
        showsComparison: Bool = false,
        hasSettings: Bool = false,
        persistenceKey: String? = nil,
        exclusiveGroup: String? = nil,
        isExperimental: Bool = false,
        requiresSetup: Bool = false,
        setupRequirements: NodeSetupRequirements? = nil,
        isResourceIntensive: Bool = false,
        subNodes: [NodeInfo] = []
    ) {
        self.typeId = typeId
        self.displayName = displayName
        self.icon = icon
        self.color = color
        self.isUserToggleable = isUserToggleable
        self.isAlwaysEnabled = isAlwaysEnabled
        self.requiredNodes = requiredNodes
        self.dimsWhenRunning = dimsWhenRunning
        self.outputType = outputType
        self.inputDescription = inputDescription
        self.isAction = isAction
        self.actionDescription = actionDescription
        self.showsComparison = showsComparison
        self.hasSettings = hasSettings
        self.persistenceKey = persistenceKey
        self.exclusiveGroup = exclusiveGroup
        self.isExperimental = isExperimental
        self.requiresSetup = requiresSetup
        self.setupRequirements = setupRequirements
        self.isResourceIntensive = isResourceIntensive
        self.subNodes = subNodes
    }
}

// MARK: - Node Output Type

/// What kind of output a node produces (determines how to render in reports)
public enum NodeOutputType: Sendable {
    /// Produces text output (most common)
    case text

    /// Produces audio (shows waveform/duration)
    case audio

    /// Produces no output (action only)
    case none

    /// Produces structured data (custom rendering)
    case custom(String)
}

// MARK: - Node Registry

/// Central registry of all pipeline node definitions
/// Single source of truth for node properties across the app
/// Thread-safe for concurrent access
public final class NodeRegistry: @unchecked Sendable {
    public static let shared = NodeRegistry()

    private var nodes: [String: NodeInfo] = [:]
    private let lock = NSLock()

    private init() {
        registerBuiltInNodes()
    }

    // MARK: - Registration

    /// Register a node definition
    public func register(_ node: NodeInfo) {
        lock.lock()
        defer { lock.unlock() }
        nodes[node.typeId] = node
    }

    /// Register multiple nodes
    public func register(_ nodeList: [NodeInfo]) {
        lock.lock()
        defer { lock.unlock() }
        for node in nodeList {
            nodes[node.typeId] = node
        }
    }

    // MARK: - Lookup

    /// Get node info by typeId
    public func node(for typeId: String) -> NodeInfo? {
        lock.lock()
        defer { lock.unlock() }
        return nodes[typeId]
    }

    /// Get node info, with fallback for unknown nodes
    public func nodeOrDefault(for typeId: String) -> NodeInfo {
        lock.lock()
        defer { lock.unlock() }
        return nodes[typeId]
            ?? NodeInfo(
                typeId: typeId,
                displayName: typeId.replacingOccurrences(of: "-", with: " ").capitalized,
                icon: "gearshape",
                color: KoeColors.textLight
            )
    }

    /// Get all registered nodes
    public var allNodes: [NodeInfo] {
        lock.lock()
        defer { lock.unlock() }
        return Array(nodes.values)
    }

    /// Get nodes that are toggleable
    public var toggleableNodes: [NodeInfo] {
        lock.lock()
        defer { lock.unlock() }
        return nodes.values.filter { $0.isUserToggleable }
    }

    /// Get all nodes in the same exclusive group
    public func nodesInExclusiveGroup(_ group: String) -> [NodeInfo] {
        lock.lock()
        defer { lock.unlock() }
        return nodes.values.filter { $0.exclusiveGroup == group }
    }

    /// Get other nodes that should be disabled when enabling a node
    public func exclusiveNodes(for typeId: String) -> [NodeInfo] {
        lock.lock()
        defer { lock.unlock() }
        guard let node = nodes[typeId], let group = node.exclusiveGroup else {
            return []
        }
        return nodes.values.filter { $0.exclusiveGroup == group && $0.typeId != typeId }
    }

    // MARK: - Built-in Nodes

    private func registerBuiltInNodes() {
        register([
            // Triggers
            NodeInfo(
                typeId: "hotkey-trigger",
                displayName: "On Press",
                icon: "command",
                color: KoeColors.accent,
                isUserToggleable: false,
                isAlwaysEnabled: true,
                dimsWhenRunning: ["voice-trigger"],
                outputType: .none,
                inputDescription: "Hotkey pressed",
                isAction: true,
                actionDescription: "Triggers recording on hotkey",
                hasSettings: true
            ),

            NodeInfo(
                typeId: "voice-trigger",
                displayName: "On Voice",
                icon: "waveform",
                color: KoeColors.accent,
                isUserToggleable: true,
                isAlwaysEnabled: false,
                dimsWhenRunning: ["hotkey-trigger"],
                outputType: .none,
                inputDescription: "Voice command detected",
                isAction: true,
                actionDescription: "Triggers recording on voice command",
                hasSettings: true,
                persistenceKey: "isCommandListeningEnabled",
                isExperimental: true
            ),

            // Core Processing
            NodeInfo(
                typeId: "recorder",
                displayName: "Record",
                icon: "mic.fill",
                color: KoeColors.stateRecording,
                isUserToggleable: false,
                isAlwaysEnabled: true,
                outputType: .audio,
                inputDescription: "Audio input",
                hasSettings: true
            ),

            // Transcription Engines (mutually exclusive - only one can be active)

            // Apple Speech - instant, no download needed
            NodeInfo(
                typeId: "transcribe-apple",
                displayName: "Apple Speech",
                icon: "apple.logo",
                color: KoeColors.stateTranscribing,
                isUserToggleable: true,
                isAlwaysEnabled: false,
                outputType: .text,
                inputDescription: "Audio recording",
                hasSettings: true,
                persistenceKey: "transcribeAppleSpeechEnabled",
                exclusiveGroup: "transcription"
            ),

            // WhisperKit Balanced - turbo model, good speed and accuracy (default)
            NodeInfo(
                typeId: "transcribe-whisperkit-balanced",
                displayName: "Balanced",
                icon: "gauge.with.dots.needle.50percent",
                color: KoeColors.stateTranscribing,
                isUserToggleable: true,
                isAlwaysEnabled: false,
                outputType: .text,
                inputDescription: "Audio recording",
                hasSettings: true,
                persistenceKey: "transcribeWhisperKitBalancedEnabled",
                exclusiveGroup: "transcription",
                isExperimental: true,
                requiresSetup: true,
                setupRequirements: .whisperKitBalanced,
                isResourceIntensive: true
            ),

            // WhisperKit Accurate - large model, best accuracy
            NodeInfo(
                typeId: "transcribe-whisperkit-accurate",
                displayName: "Accurate",
                icon: "target",
                color: KoeColors.stateTranscribing,
                isUserToggleable: true,
                isAlwaysEnabled: false,
                outputType: .text,
                inputDescription: "Audio recording",
                hasSettings: true,
                persistenceKey: "transcribeWhisperKitAccurateEnabled",
                exclusiveGroup: "transcription",
                isExperimental: true,
                requiresSetup: true,
                setupRequirements: .whisperKitAccurate,
                isResourceIntensive: true
            ),

            // AI Processing Engines (mutually exclusive - only one can be active)

            // AI Model - Mistral 7B (Composite Node with Internal Pipeline)
            NodeInfo(
                typeId: "ai-fast",
                displayName: "Mistral 7B",
                icon: "cpu.fill",
                color: KoeColors.stateRefining,
                isUserToggleable: true,
                isAlwaysEnabled: false,
                outputType: .text,
                inputDescription: "Raw transcription",
                showsComparison: true,
                hasSettings: true,
                persistenceKey: "aiProcessingFastEnabled",
                exclusiveGroup: "ai-processing",
                requiresSetup: true,
                setupRequirements: .aiFast,
                isResourceIntensive: true,
                subNodes: [
                    // Capability Nodes (What the AI should do - Mutually Exclusive)
                    NodeInfo(
                        typeId: "ai-fast.capability.translate",
                        displayName: "Translate",
                        icon: "character.bubble",
                        color: KoeColors.stateRefining,
                        isUserToggleable: true,
                        isAlwaysEnabled: false,
                        persistenceKey: "aiCapabilityTranslate",
                        exclusiveGroup: "ai-capability"
                    ),
                    NodeInfo(
                        typeId: "ai-fast.capability.summarize",
                        displayName: "Summarize",
                        icon: "doc.text.magnifyingglass",
                        color: KoeColors.stateRefining,
                        isUserToggleable: true,
                        isAlwaysEnabled: false,
                        persistenceKey: "aiCapabilitySummarize",
                        exclusiveGroup: "ai-capability"
                    ),
                    NodeInfo(
                        typeId: "ai-fast.capability.rewrite",
                        displayName: "Rewrite",
                        icon: "pencil.line",
                        color: KoeColors.stateRefining,
                        isUserToggleable: true,
                        isAlwaysEnabled: false,
                        persistenceKey: "aiCapabilityRewrite",
                        exclusiveGroup: "ai-capability"
                    ),

                    // Language Selectors (Mutually Exclusive - for Translate capability)
                    NodeInfo(
                        typeId: "ai-fast.lang.spanish",
                        displayName: "Spanish",
                        icon: "globe",
                        color: KoeColors.accent,
                        isUserToggleable: true,
                        isAlwaysEnabled: false,
                        persistenceKey: "aiLangSpanish",
                        exclusiveGroup: "ai-language"
                    ),
                    NodeInfo(
                        typeId: "ai-fast.lang.portuguese",
                        displayName: "Portuguese",
                        icon: "globe",
                        color: KoeColors.accent,
                        isUserToggleable: true,
                        isAlwaysEnabled: false,
                        persistenceKey: "aiLangPortuguese",
                        exclusiveGroup: "ai-language"
                    ),
                    NodeInfo(
                        typeId: "ai-fast.lang.french",
                        displayName: "French",
                        icon: "globe",
                        color: KoeColors.accent,
                        isUserToggleable: true,
                        isAlwaysEnabled: false,
                        persistenceKey: "aiLangFrench",
                        exclusiveGroup: "ai-language"
                    ),
                    NodeInfo(
                        typeId: "ai-fast.lang.german",
                        displayName: "German",
                        icon: "globe",
                        color: KoeColors.accent,
                        isUserToggleable: true,
                        isAlwaysEnabled: false,
                        persistenceKey: "aiLangGerman",
                        exclusiveGroup: "ai-language"
                    ),
                    NodeInfo(
                        typeId: "ai-fast.lang.italian",
                        displayName: "Italian",
                        icon: "globe",
                        color: KoeColors.accent,
                        isUserToggleable: true,
                        isAlwaysEnabled: false,
                        persistenceKey: "aiLangItalian",
                        exclusiveGroup: "ai-language"
                    ),
                    NodeInfo(
                        typeId: "ai-fast.lang.japanese",
                        displayName: "Japanese",
                        icon: "globe",
                        color: KoeColors.accent,
                        isUserToggleable: true,
                        isAlwaysEnabled: false,
                        persistenceKey: "aiLangJapanese",
                        exclusiveGroup: "ai-language"
                    ),
                    NodeInfo(
                        typeId: "ai-fast.lang.chinese",
                        displayName: "Chinese",
                        icon: "globe",
                        color: KoeColors.accent,
                        isUserToggleable: true,
                        isAlwaysEnabled: false,
                        persistenceKey: "aiLangChinese",
                        exclusiveGroup: "ai-language"
                    ),
                    NodeInfo(
                        typeId: "ai-fast.lang.korean",
                        displayName: "Korean",
                        icon: "globe",
                        color: KoeColors.accent,
                        isUserToggleable: true,
                        isAlwaysEnabled: false,
                        persistenceKey: "aiLangKorean",
                        exclusiveGroup: "ai-language"
                    ),
                ]
            ),

            // Balanced - Qwen 2.5 7B, good balance of speed and quality
            NodeInfo(
                typeId: "ai-balanced",
                displayName: "Balanced",
                icon: "gauge.with.dots.needle.50percent",
                color: KoeColors.stateRefining,
                isUserToggleable: true,
                isAlwaysEnabled: false,
                outputType: .text,
                inputDescription: "Raw transcription",
                showsComparison: true,
                hasSettings: true,
                persistenceKey: "aiProcessingBalancedEnabled",
                exclusiveGroup: "ai-processing",
                requiresSetup: true,
                setupRequirements: .aiBalanced,
                isResourceIntensive: true
            ),

            // Reasoning - DeepSeek-R1 8B, best for complex reasoning and prompts
            NodeInfo(
                typeId: "ai-reasoning",
                displayName: "Reasoning",
                icon: "brain",
                color: KoeColors.stateRefining,
                isUserToggleable: true,
                isAlwaysEnabled: false,
                outputType: .text,
                inputDescription: "Raw transcription",
                showsComparison: true,
                hasSettings: true,
                persistenceKey: "aiProcessingReasoningEnabled",
                exclusiveGroup: "ai-processing",
                isExperimental: true,
                requiresSetup: true,
                setupRequirements: .aiReasoning,
                isResourceIntensive: true
            ),

            // Legacy nodes (for backwards compatibility with old pipeline records)
            NodeInfo(
                typeId: "text-improve",
                displayName: "Improve (Legacy)",
                icon: "flask",
                color: KoeColors.stateRefining,
                outputType: .text,
                inputDescription: "Raw transcription",
                showsComparison: true
            ),

            // Actions
            NodeInfo(
                typeId: "auto-type",
                displayName: "Type",
                icon: "keyboard",
                color: KoeColors.accent,
                isUserToggleable: false,
                isAlwaysEnabled: true,
                outputType: .none,
                inputDescription: "Final text",
                isAction: true,
                actionDescription: "Typed to active window"
            ),

            NodeInfo(
                typeId: "auto-enter",
                displayName: "Enter",
                icon: "return",
                color: KoeColors.accent,
                isUserToggleable: true,
                isAlwaysEnabled: false,
                outputType: .none,
                inputDescription: "After typing",
                isAction: true,
                actionDescription: "Sent Enter key",
                persistenceKey: "isAutoEnterEnabled",
                isExperimental: true
            ),
        ])
    }
}

// MARK: - PipelineStageInfo Bridge

/// Bridge between the existing PipelineStageInfo enum and NodeRegistry
extension PipelineStageInfo {
    /// Get the NodeInfo for this stage
    var nodeInfo: NodeInfo {
        NodeRegistry.shared.nodeOrDefault(for: registryTypeId)
    }

    /// Map stage to registry typeId
    private var registryTypeId: String {
        switch self {
        case .hotkeyTrigger: return "hotkey-trigger"
        case .voiceTrigger: return "voice-trigger"
        case .recorder: return "recorder"
        case .transcribeApple: return "transcribe-apple"
        case .transcribeWhisperKitBalanced: return "transcribe-whisperkit-balanced"
        case .transcribeWhisperKitAccurate: return "transcribe-whisperkit-accurate"
        case .aiFast: return "ai-fast"
        case .aiBalanced: return "ai-balanced"
        case .aiReasoning: return "ai-reasoning"
        case .autoType: return "auto-type"
        case .autoEnter: return "auto-enter"
        }
    }
}

// MARK: - Convenience Extensions

extension NodeInfo {
    /// Check if another node is required
    func requires(_ typeId: String) -> Bool {
        requiredNodes.contains(typeId)
    }

    /// Check if this dims another node when running
    func dims(_ typeId: String) -> Bool {
        dimsWhenRunning.contains(typeId)
    }
}
