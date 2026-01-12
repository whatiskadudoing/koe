import SwiftUI

// MARK: - Node State

/// Represents the complete state of a node at runtime
struct NodeState {
    /// User's toggle preference (persisted)
    var isToggledOn: Bool

    /// Whether requirements are met (dependencies enabled)
    var requirementsMet: Bool

    /// Whether temporarily dimmed (another node is running)
    var isTemporarilyDimmed: Bool

    /// Computed: effective enabled state
    var isEnabled: Bool {
        isToggledOn && requirementsMet && !isTemporarilyDimmed
    }

    /// Computed: should show as disabled in UI
    var isDisabled: Bool {
        !isToggledOn || !requirementsMet
    }

    /// Computed: opacity for UI (dimmed when temp disabled or requirements not met)
    var opacity: Double {
        if isTemporarilyDimmed { return 0.4 }
        if !requirementsMet { return 0.5 }
        if !isToggledOn { return 0.5 }
        return 1.0
    }
}

// MARK: - Node State Controller

/// Centralized controller for managing pipeline node states
/// Uses NodeRegistry for node definitions, AppState for persistence
@Observable
@MainActor
final class NodeStateController<Node: Hashable & Sendable> {

    // MARK: - Dependencies

    private let appState: AppState
    private let registry: NodeRegistry

    /// Map node to its registry typeId
    private let nodeToTypeId: (Node) -> String

    /// Closure to get persisted toggle state for a node
    private let getPersistedState: (Node) -> Bool

    /// Closure to set persisted toggle state for a node
    private let setPersistedState: (Node, Bool) -> Void

    /// Closure to check if a node's requirements are met (beyond just other nodes)
    private let checkRequirements: ((Node) -> Bool)?

    /// Currently running node typeId (for mutual exclusion)
    var runningNodeTypeId: String?

    // MARK: - Init

    init(
        appState: AppState,
        registry: NodeRegistry = .shared,
        nodeToTypeId: @escaping (Node) -> String,
        getPersistedState: @escaping (Node) -> Bool,
        setPersistedState: @escaping (Node, Bool) -> Void,
        checkRequirements: ((Node) -> Bool)? = nil
    ) {
        self.appState = appState
        self.registry = registry
        self.nodeToTypeId = nodeToTypeId
        self.getPersistedState = getPersistedState
        self.setPersistedState = setPersistedState
        self.checkRequirements = checkRequirements
    }

    // MARK: - Node Info Access

    /// Get NodeInfo for a node
    func info(for node: Node) -> NodeInfo {
        registry.nodeOrDefault(for: nodeToTypeId(node))
    }

    // MARK: - State Access

    /// Get the complete state for a node
    func state(for node: Node) -> NodeState {
        let nodeInfo = info(for: node)
        let isToggledOn = nodeInfo.isAlwaysEnabled || getPersistedState(node)

        // Check if required nodes are enabled
        var requirementsMet = true
        for requiredTypeId in nodeInfo.requiredNodes {
            if let requiredInfo = registry.node(for: requiredTypeId),
                !requiredInfo.isAlwaysEnabled
            {
                // Would need to check if required node is enabled
                // For now, assume met if can't verify
            }
        }

        // Check additional requirements (like voice profile existing)
        if let check = checkRequirements, !check(node) {
            requirementsMet = false
        }

        // Check if temporarily dimmed by a running node
        var isTemporarilyDimmed = false
        if let runningTypeId = runningNodeTypeId,
            runningTypeId != nodeToTypeId(node),
            let runningInfo = registry.node(for: runningTypeId)
        {
            if runningInfo.dimsWhenRunning.contains(nodeToTypeId(node)) {
                isTemporarilyDimmed = true
            }
        }

        return NodeState(
            isToggledOn: isToggledOn,
            requirementsMet: requirementsMet,
            isTemporarilyDimmed: isTemporarilyDimmed
        )
    }

    /// Whether a node is effectively enabled (considering all factors)
    func isEnabled(_ node: Node) -> Bool {
        state(for: node).isEnabled
    }

    /// Whether a node's toggle is on (regardless of requirements/dimming)
    func isToggledOn(_ node: Node) -> Bool {
        let nodeInfo = info(for: node)
        return nodeInfo.isAlwaysEnabled || getPersistedState(node)
    }

    // MARK: - State Modification

    /// Toggle a node on/off
    func toggle(_ node: Node) {
        let nodeInfo = info(for: node)
        guard nodeInfo.isUserToggleable else { return }
        let current = getPersistedState(node)
        setPersistedState(node, !current)
    }

    /// Set a node's toggle state
    func setToggle(_ node: Node, enabled: Bool) {
        let nodeInfo = info(for: node)
        guard nodeInfo.isUserToggleable else { return }
        setPersistedState(node, enabled)
    }

    /// Toggle a node with mutual exclusivity - disables other nodes in the same group
    /// Also manages resource lifecycle (loading/unloading models, etc.)
    func toggleExclusive(_ node: Node, in group: [Node]) {
        let nodeInfo = info(for: node)
        guard nodeInfo.isUserToggleable else { return }

        let current = getPersistedState(node)
        let newState = !current
        let nodeTypeId = nodeToTypeId(node)

        if newState {
            // Enabling this node - disable all others in the group
            for otherNode in group where otherNode != node {
                setPersistedState(otherNode, false)
            }

            // Update persisted state immediately for responsive UI
            setPersistedState(node, newState)

            // Manage resources via lifecycle system (async)
            // This will unload exclusive nodes and load the new one
            Task { @MainActor in
                do {
                    try await NodeLifecycleRegistry.shared.activate(
                        nodeTypeId,
                        exclusiveGroup: nodeInfo.exclusiveGroup
                    )
                } catch {
                    // Log error but don't revert state - user can retry
                    print("Failed to activate node \(nodeTypeId): \(error)")
                }
            }
        } else {
            // Disabling this node
            setPersistedState(node, newState)

            // Unload resources
            Task { @MainActor in
                NodeLifecycleRegistry.shared.deactivate(nodeTypeId)
            }
        }
    }

    /// Mark a node as running (dims mutually exclusive nodes)
    func setRunning(_ node: Node?) {
        runningNodeTypeId = node.map { nodeToTypeId($0) }
    }

    /// Mark a node typeId as running
    func setRunning(typeId: String?) {
        runningNodeTypeId = typeId
    }

    // MARK: - SwiftUI Bindings

    /// Get a binding for a node's toggle state
    /// Returns the user's toggle preference (isToggledOn), not the effective state (isEnabled)
    /// This ensures toggling works correctly even when requirements aren't met or node is dimmed
    ///
    /// Note: Captures the getter/setter closures directly instead of `self` to avoid
    /// issues with the controller being deallocated before the binding is used.
    func binding(for node: Node) -> Binding<Bool> {
        let nodeInfo = info(for: node)
        let getPersisted = getPersistedState
        let setPersisted = setPersistedState
        let alwaysEnabled = nodeInfo.isAlwaysEnabled
        let isToggleable = nodeInfo.isUserToggleable

        return Binding(
            get: {
                alwaysEnabled || getPersisted(node)
            },
            set: { newValue in
                guard isToggleable else { return }
                setPersisted(node, newValue)
            }
        )
    }

    /// Get opacity for a node (for dimming effects)
    func opacity(for node: Node) -> Double {
        state(for: node).opacity
    }
}

// MARK: - Pipeline Stage Factory

extension NodeStateController where Node == PipelineStageInfo {
    /// Create a controller for pipeline stages using AppState
    static func forPipeline(appState: AppState) -> NodeStateController<PipelineStageInfo> {
        NodeStateController(
            appState: appState,
            nodeToTypeId: { node in
                switch node {
                case .hotkeyTrigger: return "hotkey-trigger"
                case .voiceTrigger: return "voice-trigger"
                case .nativeMacTrigger: return "native-mac-trigger"
                case .recorder: return "recorder"
                case .transcribeApple: return "transcribe-apple"
                case .transcribeWhisperKitBalanced: return "transcribe-whisperkit-balanced"
                case .transcribeWhisperKitAccurate: return "transcribe-whisperkit-accurate"
                case .aiFast: return "ai-fast"
                case .aiBalanced: return "ai-balanced"
                case .aiReasoning: return "ai-reasoning"
                case .aiPromptEnhancer: return "ai-prompt-enhancer"
                case .autoType: return "auto-type"
                case .autoEnter: return "auto-enter"
                case .livePreview: return "live-preview"
                }
            },
            getPersistedState: { node in
                switch node {
                case .hotkeyTrigger: return true
                case .voiceTrigger: return appState.isCommandListeningEnabled
                case .nativeMacTrigger: return appState.isNativeMacTriggerEnabled
                case .transcribeApple: return appState.isAppleSpeechEnabled
                case .transcribeWhisperKitBalanced: return appState.isWhisperKitBalancedEnabled
                case .transcribeWhisperKitAccurate: return appState.isWhisperKitAccurateEnabled
                case .aiFast: return appState.isAIFastEnabled
                case .aiBalanced: return appState.isAIBalancedEnabled
                case .aiReasoning: return appState.isAIReasoningEnabled
                case .aiPromptEnhancer: return appState.isAIPromptEnhancerEnabled
                case .autoEnter: return appState.isAutoEnterEnabled
                case .livePreview: return appState.isLivePreviewEnabled
                default: return true
                }
            },
            setPersistedState: { node, enabled in
                switch node {
                case .voiceTrigger: appState.isCommandListeningEnabled = enabled
                case .nativeMacTrigger: appState.isNativeMacTriggerEnabled = enabled
                case .transcribeApple: appState.isAppleSpeechEnabled = enabled
                case .transcribeWhisperKitBalanced: appState.isWhisperKitBalancedEnabled = enabled
                case .transcribeWhisperKitAccurate: appState.isWhisperKitAccurateEnabled = enabled
                case .aiFast: appState.isAIFastEnabled = enabled
                case .aiBalanced: appState.isAIBalancedEnabled = enabled
                case .aiReasoning: appState.isAIReasoningEnabled = enabled
                case .aiPromptEnhancer: appState.isAIPromptEnhancerEnabled = enabled
                case .autoEnter: appState.isAutoEnterEnabled = enabled
                case .livePreview: appState.isLivePreviewEnabled = enabled
                default: break
                }
            },
            checkRequirements: { node in
                switch node {
                case .voiceTrigger: return appState.hasVoiceProfile
                default: return true
                }
            }
        )
    }
}
