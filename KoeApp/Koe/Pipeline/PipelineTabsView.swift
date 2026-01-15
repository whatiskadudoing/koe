import KoeUI
import SwiftUI

// MARK: - Pipeline Tabs View

/// Container view that displays the vertical pipeline layout
/// Sub-pipelines are now shown as accordions instead of tabs
struct PipelineTabsView: View {
    @Binding var selectedStage: PipelineStageInfo?

    var body: some View {
        VerticalPipelineView(selectedStage: $selectedStage)
    }
}

// MARK: - Sub-Pipeline Canvas (Reuses Main Pipeline Visual Style)

/// Dynamic sub-pipeline canvas that renders nodes based on their configuration.
/// Works with any composite node - adapts layout based on exclusive groups and standalone nodes.
///
/// Layout rules:
/// - Nodes with same exclusiveGroup render as parallel (split/merge connectors)
/// - Nodes with no exclusiveGroup render inline as toggles
/// - Groups containing "gate" in their name control visibility of related groups
///   (e.g., "translate-gate" controls visibility of "language-selection")
struct SubPipelineCanvas: View {
    let parentNode: NodeInfo
    @State private var refreshID = UUID()

    // MARK: - Dynamic Node Grouping

    /// All unique exclusive groups in the sub-pipeline
    private var exclusiveGroups: [String] {
        let groups = Set(parentNode.subNodes.compactMap { $0.exclusiveGroup })
        // Sort to ensure consistent ordering: style groups first, then gate-controlled groups
        return groups.sorted { g1, g2 in
            // Gates come after their controlled groups
            if g1.contains("-selection") && !g2.contains("-selection") { return false }
            if !g1.contains("-selection") && g2.contains("-selection") { return true }
            return g1 < g2
        }
    }

    /// Standalone nodes (no exclusive group) - these are toggles that may control other groups
    private var standaloneNodes: [NodeInfo] {
        parentNode.subNodes.filter { $0.exclusiveGroup == nil }
    }

    /// Get nodes for a specific exclusive group
    private func nodes(inGroup group: String) -> [NodeInfo] {
        parentNode.subNodes.filter { $0.exclusiveGroup == group }
    }

    /// Get the active node in a group (the one that's enabled)
    private func activeNode(inGroup group: String) -> NodeInfo? {
        nodes(inGroup: group).first { isNodeEnabled($0) }
    }

    /// Check if any node in a group is active
    private func hasActiveNode(inGroup group: String) -> Bool {
        activeNode(inGroup: group) != nil
    }

    /// Check if a selection group should be visible based on its gate node
    /// Convention: "-selection" groups are controlled by standalone nodes with matching prefix
    /// e.g., "language-selection" is controlled by a node with typeId containing "translate"
    private func isGroupVisible(_ group: String) -> Bool {
        // Selection groups depend on a gate being active
        if group.contains("-selection") || group.contains("-language") {
            // Find the gate node (standalone node that controls this)
            // Convention: translate gate controls language selection
            if let gateNode = standaloneNodes.first(where: { $0.typeId.contains("translate") }) {
                return isNodeEnabled(gateNode)
            }
        }
        // Non-gated groups are always visible
        return true
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Input node
            SubPipelineInputNode()

            // Render pipeline stages dynamically
            renderPipelineStages()

            // Simple connector to output
            PipelineConnector(isActive: true, color: PipelineLayout.activeColor)

            // Output node
            SubPipelineOutputNode()
        }
        .id(refreshID)
        .onReceive(NotificationCenter.default.publisher(for: .subNodeExclusiveGroupChanged)) { _ in
            refreshID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshID = UUID()
        }
    }

    @ViewBuilder
    private func renderPipelineStages() -> some View {
        // First: non-gated exclusive groups (like rewrite styles)
        ForEach(exclusiveGroups.filter { !$0.contains("-language") && !$0.contains("-selection") }, id: \.self) {
            group in
            PipelineConnector(isActive: true, color: PipelineLayout.activeColor)
            renderExclusiveGroup(group)
        }

        // Second: standalone toggle nodes (like translate)
        ForEach(standaloneNodes) { node in
            PipelineConnector(isActive: true, color: PipelineLayout.activeColor)
            SubPipelineNodeView(node: node, siblingNodes: parentNode.subNodes)
        }

        // Third: gated exclusive groups (like language selection) - only show when gate is active
        ForEach(exclusiveGroups.filter { $0.contains("-language") || $0.contains("-selection") }, id: \.self) { group in
            if isGroupVisible(group) {
                renderExclusiveGroup(group)
            }
        }
    }

    @ViewBuilder
    private func renderExclusiveGroup(_ group: String) -> some View {
        let groupNodes = nodes(inGroup: group)
        let active = activeNode(inGroup: group)
        let hasActive = active != nil

        if !groupNodes.isEmpty {
            SplitConnector(
                nodeStates: groupNodes.map { isNodeEnabled($0) },
                activeColor: PipelineLayout.activeColor
            )

            VStack(spacing: PipelineLayout.nodeSpacing) {
                ForEach(groupNodes) { node in
                    let isActive = isNodeEnabled(node)
                    SubPipelineNodeView(node: node, siblingNodes: parentNode.subNodes)
                        .opacity(hasActive && !isActive ? 0.4 : 1.0)
                }
            }
            .frame(height: PipelineLayout.parallelSectionHeight(nodeCount: groupNodes.count))

            MergeConnector(
                nodeStates: groupNodes.map { isNodeEnabled($0) },
                activeColor: active?.color ?? PipelineLayout.activeColor
            )
        }
    }

    private func isNodeEnabled(_ node: NodeInfo) -> Bool {
        guard let key = node.persistenceKey else { return node.isAlwaysEnabled }
        return UserDefaults.standard.bool(forKey: key)
    }
}

// MARK: - Input/Output Reference Nodes

/// Visual node representing data flow in/out of sub-pipeline
/// Uses same sizing as regular nodes but with distinct styling
struct SubPipelineReferenceNode: View {
    let label: String
    let icon: String

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: PipelineLayout.cornerRadius)
                .fill(KoeColors.surface.opacity(0.8))

            // Content: Icon centered, label at bottom
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 8)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(KoeColors.textLight)

                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(KoeColors.textLight)
                    .padding(.bottom, 4)
            }
        }
        .frame(width: PipelineLayout.nodeWidth, height: PipelineLayout.nodeSize)
        .overlay(
            RoundedRectangle(cornerRadius: PipelineLayout.cornerRadius)
                .stroke(KoeColors.textLighter.opacity(0.4), lineWidth: 1.5)
        )
    }
}

/// Input node - represents data entering the sub-pipeline
struct SubPipelineInputNode: View {
    var body: some View {
        SubPipelineReferenceNode(label: "In", icon: "arrow.right.circle")
    }
}

/// Output node - represents data leaving the sub-pipeline
struct SubPipelineOutputNode: View {
    var body: some View {
        SubPipelineReferenceNode(label: "Out", icon: "arrow.right.circle.fill")
    }
}

// MARK: - Sub-Pipeline Node View

struct SubPipelineNodeView: View {
    let node: NodeInfo
    let siblingNodes: [NodeInfo]  // All nodes in the same parent (for exclusive group handling)
    @State private var isHovered = false
    @State private var refreshID = UUID()

    private var isEnabled: Bool {
        guard let key = node.persistenceKey else { return node.isAlwaysEnabled }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Get sibling nodes in the same exclusive group
    private var siblingsInSameGroup: [NodeInfo] {
        guard let group = node.exclusiveGroup else { return [] }
        return siblingNodes.filter { $0.exclusiveGroup == group && $0.typeId != node.typeId }
    }

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: PipelineLayout.cornerRadius)
                .fill(isEnabled ? node.color.opacity(0.15) : KoeColors.surface)
                .shadow(
                    color: .black.opacity(isHovered ? 0.10 : 0.05),
                    radius: isHovered ? 8 : 4,
                    y: 2
                )

            // Content: Icon centered, label at bottom
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 8)  // Space for top badges

                // Icon
                Image(systemName: node.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isEnabled ? node.color : KoeColors.textLight)

                // Label inside card
                Text(node.displayName)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(isEnabled ? KoeColors.textSecondary : KoeColors.textLight)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.bottom, 4)
            }

            // Top badge bar - same structure as main pipeline nodes
            HStack(spacing: 2) {
                // Left side badges
                HStack(spacing: 2) {
                    // Experimental badge (flask icon)
                    if node.isExperimental {
                        Image(systemName: "flask.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                // Right side badges
                HStack(spacing: 2) {
                    // Toggle indicator (for toggleable nodes)
                    if node.isUserToggleable {
                        Circle()
                            .fill(isEnabled ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: PipelineLayout.nodeWidth, height: PipelineLayout.nodeSize)
        .overlay(
            RoundedRectangle(cornerRadius: PipelineLayout.cornerRadius)
                .stroke(
                    isEnabled ? node.color : KoeColors.textLighter.opacity(0.3),
                    lineWidth: PipelineLayout.connectorLineWidth)
        )
        .opacity(isEnabled ? 1.0 : 0.6)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .onTapGesture {
            if node.isUserToggleable {
                withAnimation(.easeOut(duration: 0.15)) {
                    let newValue = !isEnabled
                    if let key = node.persistenceKey {
                        // Handle exclusive groups - disable ALL siblings in same group FIRST
                        if node.exclusiveGroup != nil, newValue {
                            for sibling in siblingsInSameGroup {
                                if let siblingKey = sibling.persistenceKey {
                                    UserDefaults.standard.set(false, forKey: siblingKey)
                                }
                            }
                        }

                        // Now set this node's value
                        UserDefaults.standard.set(newValue, forKey: key)
                        UserDefaults.standard.synchronize()

                        // Notify all nodes to refresh
                        if let group = node.exclusiveGroup {
                            NotificationCenter.default.post(
                                name: .subNodeExclusiveGroupChanged,
                                object: group
                            )
                        }

                        // Trigger refresh for this node
                        refreshID = UUID()
                    }
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .subNodeExclusiveGroupChanged)) { notification in
            // Refresh when any node in an exclusive group changes
            if let changedGroup = notification.object as? String,
                node.exclusiveGroup == changedGroup
            {
                refreshID = UUID()
            }
        }
        .id(refreshID)
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let subNodeExclusiveGroupChanged = Notification.Name("subNodeExclusiveGroupChanged")
}

// MARK: - Sub-Pipeline Connector

struct SubPipelineConnectorLine: View {
    let isActive: Bool
    let color: Color

    var body: some View {
        Rectangle()
            .fill(isActive ? color : KoeColors.textLighter.opacity(0.3))
            .frame(width: 20, height: 2)
    }
}
