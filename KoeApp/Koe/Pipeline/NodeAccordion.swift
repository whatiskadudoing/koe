import KoeUI
import SwiftUI

/// Accordion panel for composite node sub-options
/// Expands below the parent node container to show sub-pipeline options
struct NodeAccordion: View {
    let parentNode: NodeInfo
    let isExpanded: Bool

    @State private var refreshID = UUID()

    // MARK: - Node Grouping

    /// All unique exclusive groups in the sub-pipeline
    private var exclusiveGroups: [String] {
        let groups = Set(parentNode.subNodes.compactMap { $0.exclusiveGroup })
        return groups.sorted { g1, g2 in
            if g1.contains("-selection") && !g2.contains("-selection") { return false }
            if !g1.contains("-selection") && g2.contains("-selection") { return true }
            return g1 < g2
        }
    }

    /// Standalone nodes (no exclusive group) - gate toggles
    private var standaloneNodes: [NodeInfo] {
        parentNode.subNodes.filter { $0.exclusiveGroup == nil }
    }

    /// Get nodes for a specific exclusive group
    private func nodes(inGroup group: String) -> [NodeInfo] {
        parentNode.subNodes.filter { $0.exclusiveGroup == group }
    }

    /// Check if a selection group should be visible based on its gate node
    private func isGroupVisible(_ group: String) -> Bool {
        if group.contains("-selection") || group.contains("-language") {
            if let gateNode = standaloneNodes.first(where: { $0.typeId.contains("translate") }) {
                return isNodeEnabled(gateNode)
            }
        }
        return true
    }

    /// Get human-readable label for a group
    private func groupLabel(_ group: String) -> String {
        if group.contains("style") || group.contains("rewrite") {
            return "Style"
        } else if group.contains("language") {
            return "Language"
        }
        return group.replacingOccurrences(of: "-", with: " ").capitalized
    }

    var body: some View {
        if isExpanded {
            VStack(alignment: .center, spacing: PipelineLayout.rowSpacing) {
                // Non-gated exclusive groups (like rewrite styles)
                ForEach(
                    exclusiveGroups.filter { !$0.contains("-language") && !$0.contains("-selection") },
                    id: \.self
                ) { group in
                    AccordionGroupRow(
                        label: groupLabel(group),
                        nodes: nodes(inGroup: group),
                        allSiblings: parentNode.subNodes
                    )
                }

                // Standalone toggle nodes (like translate)
                if !standaloneNodes.isEmpty {
                    AccordionStandaloneRow(
                        nodes: standaloneNodes,
                        allSiblings: parentNode.subNodes
                    )
                }

                // Gated exclusive groups (like language selection)
                ForEach(
                    exclusiveGroups.filter { $0.contains("-language") || $0.contains("-selection") },
                    id: \.self
                ) { group in
                    if isGroupVisible(group) {
                        AccordionGroupRow(
                            label: groupLabel(group),
                            nodes: nodes(inGroup: group),
                            allSiblings: parentNode.subNodes
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(.horizontal, PipelineLayout.containerPaddingH)
            .padding(.top, PipelineLayout.accordionPaddingV + 8)
            .padding(.bottom, PipelineLayout.accordionPaddingV)
            .frame(maxWidth: .infinity)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: PipelineLayout.cornerRadius + 4,
                    bottomTrailingRadius: PipelineLayout.cornerRadius + 4,
                    topTrailingRadius: 0
                )
                .fill(KoeColors.surface.opacity(0.5))
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: PipelineLayout.cornerRadius + 4,
                    bottomTrailingRadius: PipelineLayout.cornerRadius + 4,
                    topTrailingRadius: 0
                )
                .stroke(KoeColors.textLighter.opacity(0.15), lineWidth: 1)
            )
            .offset(y: -8)
            .id(refreshID)
            .onReceive(NotificationCenter.default.publisher(for: .subNodeExclusiveGroupChanged)) { _ in
                refreshID = UUID()
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                refreshID = UUID()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
    }

    private func isNodeEnabled(_ node: NodeInfo) -> Bool {
        guard let key = node.persistenceKey else { return node.isAlwaysEnabled }
        return UserDefaults.standard.bool(forKey: key)
    }
}

// MARK: - Accordion Group Row

/// Row displaying an exclusive group of options with a label
struct AccordionGroupRow: View {
    let label: String
    let nodes: [NodeInfo]
    let allSiblings: [NodeInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Label
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(KoeColors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            // Nodes row
            HStack(spacing: 8) {
                ForEach(nodes) { node in
                    CompactSubNodeView(node: node, siblingNodes: allSiblings)
                }
            }
        }
    }
}

// MARK: - Accordion Standalone Row

/// Row displaying standalone toggle nodes (gates)
struct AccordionStandaloneRow: View {
    let nodes: [NodeInfo]
    let allSiblings: [NodeInfo]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(nodes) { node in
                CompactSubNodeView(node: node, siblingNodes: allSiblings)
            }
        }
    }
}

// MARK: - Compact Sub-Node View

/// Compact version of sub-node for accordion display
/// 48x48 instead of 56x56, same visual style as PipelineNodeView
struct CompactSubNodeView: View {
    let node: NodeInfo
    let siblingNodes: [NodeInfo]

    @State private var isHovered = false
    @State private var refreshID = UUID()

    private var nodeSize: CGFloat { PipelineLayout.compactNodeSize }
    private var cornerRadius: CGFloat { PipelineLayout.cornerRadius }

    private var isEnabled: Bool {
        guard let key = node.persistenceKey else { return node.isAlwaysEnabled }
        return UserDefaults.standard.bool(forKey: key)
    }

    private var siblingsInSameGroup: [NodeInfo] {
        guard let group = node.exclusiveGroup else { return [] }
        return siblingNodes.filter { $0.exclusiveGroup == group && $0.typeId != node.typeId }
    }

    private var iconColor: Color {
        isEnabled ? node.color : KoeColors.textLight
    }

    private var labelColor: Color {
        isEnabled ? KoeColors.textSecondary : KoeColors.textLight
    }

    private var borderColor: Color {
        .clear
    }

    var body: some View {
        ZStack {
            // Background - white like main nodes
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white)
                .shadow(
                    color: .black.opacity(isHovered ? 0.10 : 0.05),
                    radius: isHovered ? 8 : 4,
                    y: 2
                )

            // Content: Icon centered, label at bottom
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 6)

                Image(systemName: node.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: nodeSize - 12, height: nodeSize - 24)

                Text(node.displayName)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.bottom, 3)
            }

            // Top badge bar - same layout as main nodes
            HStack(spacing: 2) {
                // Left side badges
                if node.isExperimental {
                    Image(systemName: "flask.fill")
                        .font(.system(size: 6, weight: .semibold))
                        .foregroundColor(.orange)
                }

                Spacer()

                // Right side - toggle indicator
                if node.isUserToggleable {
                    Circle()
                        .fill(isEnabled ? Color.green : KoeColors.textLighter)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 3)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: nodeSize, height: nodeSize)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(borderColor, lineWidth: 2)
        )
        .opacity(isEnabled ? 1.0 : 0.5)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            toggleNode()
        }
        .id(refreshID)
        .onReceive(NotificationCenter.default.publisher(for: .subNodeExclusiveGroupChanged)) { _ in
            refreshID = UUID()
        }
    }

    private func toggleNode() {
        guard node.isUserToggleable else { return }

        withAnimation(.easeOut(duration: 0.15)) {
            let newValue = !isEnabled
            if let key = node.persistenceKey {
                // Handle exclusive groups
                if node.exclusiveGroup != nil, newValue {
                    for sibling in siblingsInSameGroup {
                        if let siblingKey = sibling.persistenceKey {
                            UserDefaults.standard.set(false, forKey: siblingKey)
                        }
                    }
                }

                UserDefaults.standard.set(newValue, forKey: key)
                UserDefaults.standard.synchronize()

                if let group = node.exclusiveGroup {
                    NotificationCenter.default.post(
                        name: .subNodeExclusiveGroupChanged,
                        object: group
                    )
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Simulated accordion
        VStack(alignment: .leading, spacing: 8) {
            Text("AI PROCESSING")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(KoeColors.textTertiary)
                .tracking(0.8)

            // Mock parent node info
            if let aiNode = NodeRegistry.shared.node(for: "ai-fast") {
                HStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(KoeColors.accent.opacity(0.3))
                        .frame(width: 56, height: 56)
                        .overlay(Text("AI").font(.caption))
                }

                NodeAccordion(parentNode: aiNode, isExpanded: true)
            }
        }
        .padding()
        .background(KoeColors.surface.opacity(0.6))
        .cornerRadius(16)
    }
    .padding()
    .background(KoeColors.background)
}
