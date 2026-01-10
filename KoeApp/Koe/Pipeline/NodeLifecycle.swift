import Foundation
import os.log

private let logger = Logger(subsystem: "com.koe.app", category: "NodeLifecycle")

// MARK: - Node Lifecycle Handler Protocol

/// Protocol for nodes that require resource management
/// Implement this for nodes that load models, establish connections, etc.
///
/// Example: WhisperKit needs to load ~1GB model, should unload when inactive
@MainActor
public protocol NodeLifecycleHandler: AnyObject {
    /// Unique identifier matching NodeInfo.typeId
    var nodeTypeId: String { get }

    /// Whether resources are currently loaded
    var isLoaded: Bool { get }

    /// Load resources (model, connection, etc.)
    /// Called when node becomes active
    func load() async throws

    /// Unload resources to free memory
    /// Called when node becomes inactive (another exclusive node activated)
    func unload()
}

// MARK: - Node Lifecycle Registry

/// Central registry for node lifecycle handlers
/// Manages resource loading/unloading when nodes are toggled
@MainActor
public final class NodeLifecycleRegistry {
    public static let shared = NodeLifecycleRegistry()

    private var handlers: [String: NodeLifecycleHandler] = [:]

    private init() {}

    // MARK: - Registration

    /// Register a lifecycle handler for a node
    public func register(_ handler: NodeLifecycleHandler) {
        handlers[handler.nodeTypeId] = handler
        logger.info("Registered lifecycle handler for: \(handler.nodeTypeId)")
    }

    /// Get handler for a node
    public func handler(for typeId: String) -> NodeLifecycleHandler? {
        handlers[typeId]
    }

    /// Check if a node has a lifecycle handler
    public func hasHandler(for typeId: String) -> Bool {
        handlers[typeId] != nil
    }

    // MARK: - Lifecycle Management

    /// Activate a node (load its resources, unload exclusive nodes)
    /// - Parameter typeId: The node to activate
    /// - Parameter exclusiveGroup: Optional group name for mutual exclusivity
    public func activate(_ typeId: String, exclusiveGroup: String? = nil) async throws {
        logger.info("Activating node: \(typeId)")

        // If part of exclusive group, unload other nodes in the group first
        if let group = exclusiveGroup {
            let exclusiveNodes = NodeRegistry.shared.nodesInExclusiveGroup(group)
            for node in exclusiveNodes where node.typeId != typeId {
                if let handler = handlers[node.typeId], handler.isLoaded {
                    logger.info("Unloading exclusive node: \(node.typeId)")
                    handler.unload()
                }
            }
        }

        // Load the target node
        if let handler = handlers[typeId] {
            if !handler.isLoaded {
                try await handler.load()
                logger.info("Node loaded: \(typeId)")
            } else {
                logger.info("Node already loaded: \(typeId)")
            }
        }
    }

    /// Deactivate a node (unload its resources)
    public func deactivate(_ typeId: String) {
        logger.info("Deactivating node: \(typeId)")

        if let handler = handlers[typeId], handler.isLoaded {
            handler.unload()
            logger.info("Node unloaded: \(typeId)")
        }
    }

    /// Check if any node in an exclusive group is loaded
    public func isAnyLoaded(inGroup group: String) -> Bool {
        let nodes = NodeRegistry.shared.nodesInExclusiveGroup(group)
        for node in nodes {
            if let handler = handlers[node.typeId], handler.isLoaded {
                return true
            }
        }
        return false
    }

    /// Get the currently loaded node in an exclusive group (if any)
    public func loadedNode(inGroup group: String) -> String? {
        let nodes = NodeRegistry.shared.nodesInExclusiveGroup(group)
        for node in nodes {
            if let handler = handlers[node.typeId], handler.isLoaded {
                return node.typeId
            }
        }
        return nil
    }

    /// Unload all resource-intensive nodes to free memory
    /// Called when leaving dictation mode
    public func unloadResourceIntensiveNodes() {
        let allNodes = NodeRegistry.shared.allNodes
        for node in allNodes where node.isResourceIntensive {
            if let handler = handlers[node.typeId], handler.isLoaded {
                logger.info("Unloading resource-intensive node: \(node.typeId)")
                handler.unload()
            }
        }
    }

    /// Load the active node from an exclusive group if it's enabled
    /// Returns the typeId of the loaded node, or nil if none
    public func loadActiveNode(inGroup group: String, enabledCheck: (String) -> Bool) async throws -> String? {
        let nodes = NodeRegistry.shared.nodesInExclusiveGroup(group)
        for node in nodes {
            if enabledCheck(node.typeId) {
                if let handler = handlers[node.typeId] {
                    if !handler.isLoaded {
                        try await handler.load()
                        logger.info("Loaded active node: \(node.typeId)")
                    }
                    return node.typeId
                }
            }
        }
        return nil
    }
}

// MARK: - Convenience Extension

extension NodeInfo {
    /// Get the lifecycle handler for this node (if any)
    @MainActor
    var lifecycleHandler: NodeLifecycleHandler? {
        NodeLifecycleRegistry.shared.handler(for: typeId)
    }

    /// Whether this node has resource management
    @MainActor
    var hasLifecycleHandler: Bool {
        NodeLifecycleRegistry.shared.hasHandler(for: typeId)
    }
}
