import KoeUI
import SwiftUI

// MARK: - Pipeline Tab Model

/// Represents a pipeline tab (main or sub-pipeline)
struct PipelineTab: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let nodeTypeId: String? // nil for main pipeline, typeId for composite nodes
    let isCloseable: Bool

    static let main = PipelineTab(
        title: "Main Pipeline",
        nodeTypeId: nil,
        isCloseable: false
    )

    static func forComposite(_ node: NodeInfo) -> PipelineTab {
        PipelineTab(
            title: node.displayName,
            nodeTypeId: node.typeId,
            isCloseable: true
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PipelineTab, rhs: PipelineTab) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Pipeline Tabs View

/// Container view that manages pipeline tabs and shows appropriate content
struct PipelineTabsView: View {
    @Binding var selectedStage: PipelineStageInfo?
    @State private var tabs: [PipelineTab] = [.main]
    @State private var activeTab: PipelineTab = .main

    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            TabBarView(
                tabs: tabs,
                activeTab: $activeTab,
                onClose: { tab in
                    closeTab(tab)
                }
            )

            // Tab Content
            TabContentView(
                activeTab: activeTab,
                selectedStage: $selectedStage,
                onOpenComposite: { node in
                    openCompositeTab(node)
                }
            )
        }
    }

    // MARK: - Tab Management

    private func openCompositeTab(_ node: NodeInfo) {
        // Check if tab already exists
        if let existingTab = tabs.first(where: { $0.nodeTypeId == node.typeId }) {
            activeTab = existingTab
            return
        }

        // Create new tab
        let newTab = PipelineTab.forComposite(node)
        tabs.append(newTab)
        activeTab = newTab
    }

    private func closeTab(_ tab: PipelineTab) {
        guard tab.isCloseable else { return }

        if let index = tabs.firstIndex(of: tab) {
            tabs.remove(at: index)

            // Switch to main tab if closing active tab
            if activeTab == tab {
                activeTab = .main
            }
        }
    }
}

// MARK: - Tab Bar

struct TabBarView: View {
    let tabs: [PipelineTab]
    @Binding var activeTab: PipelineTab
    let onClose: (PipelineTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                TabButton(
                    tab: tab,
                    isActive: activeTab == tab,
                    onSelect: { activeTab = tab },
                    onClose: { onClose(tab) }
                )
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(KoeColors.background)
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let tab: PipelineTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Tab label
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    // Breadcrumb indicator for sub-pipelines
                    if tab.nodeTypeId != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(KoeColors.textLight)
                    }

                    Text(tab.title)
                        .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                        .foregroundColor(isActive ? KoeColors.accent : KoeColors.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? KoeColors.surface : Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // Close button
            if tab.isCloseable {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(KoeColors.textLight)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isActive ? 1.0 : 0.6)
            }
        }
    }
}

// MARK: - Tab Content

struct TabContentView: View {
    let activeTab: PipelineTab
    @Binding var selectedStage: PipelineStageInfo?
    let onOpenComposite: (NodeInfo) -> Void

    var body: some View {
        Group {
            if activeTab.nodeTypeId == nil {
                // Main pipeline
                MainPipelineContent(
                    selectedStage: $selectedStage,
                    onOpenComposite: onOpenComposite
                )
            } else {
                // Sub-pipeline
                SubPipelineContent(
                    nodeTypeId: activeTab.nodeTypeId!,
                    selectedStage: $selectedStage
                )
            }
        }
    }
}

// MARK: - Main Pipeline Content

struct MainPipelineContent: View {
    @Binding var selectedStage: PipelineStageInfo?
    let onOpenComposite: (NodeInfo) -> Void

    var body: some View {
        PipelineStripView(
            selectedStage: $selectedStage,
            onOpenComposite: onOpenComposite
        )
    }
}

// MARK: - Sub-Pipeline Content

struct SubPipelineContent: View {
    let nodeTypeId: String
    @Binding var selectedStage: PipelineStageInfo?

    private var parentNode: NodeInfo? {
        NodeRegistry.shared.node(for: nodeTypeId)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header showing model name and configuration
            HStack {
                Image(systemName: parentNode?.icon ?? "gearshape.2")
                    .font(.system(size: 14))
                    .foregroundColor(KoeColors.textLight)
                Text(parentNode?.displayName ?? "Configuration")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(KoeColors.accent)
                Text("Configuration")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(KoeColors.textSecondary)
            }
            .padding(.top, 20)

            // Main pipeline canvas (reusing same style)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 0) {
                    if let node = parentNode {
                        SubPipelineCanvas(parentNode: node)
                    }
                }
                .padding(.horizontal, 40)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KoeColors.background)
    }
}

// MARK: - Sub-Pipeline Canvas (Reuses Main Pipeline Visual Style)

struct SubPipelineCanvas: View {
    let parentNode: NodeInfo

    // Group nodes by exclusive groups for visual organization
    private var capabilityNodes: [NodeInfo] {
        parentNode.subNodes.filter { $0.exclusiveGroup == "ai-capability" }
    }

    private var languageNodes: [NodeInfo] {
        parentNode.subNodes.filter { $0.exclusiveGroup == "ai-language" }
    }

    private var activeCapability: NodeInfo? {
        capabilityNodes.first { isNodeEnabled($0) }
    }

    private var activeLanguage: NodeInfo? {
        languageNodes.first { isNodeEnabled($0) }
    }

    private var hasActiveCapability: Bool {
        activeCapability != nil
    }

    private var hasActiveLanguage: Bool {
        activeLanguage != nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Capability nodes section - use same generic connectors as main pipeline
            if !capabilityNodes.isEmpty {
                // Split connector before capabilities
                GenericSplitConnector(
                    nodeStates: capabilityNodes.map { isNodeEnabled($0) },
                    activeColor: KoeColors.accent
                )

                // Capability nodes
                VStack(spacing: 4) {
                    ForEach(capabilityNodes) { node in
                        let isActive = isNodeEnabled(node)
                        SubPipelineNodeView(node: node)
                            .opacity(hasActiveCapability && !isActive ? 0.4 : 1.0)
                    }
                }

                // Merge connector after capabilities
                GenericMergeConnector(
                    nodeStates: capabilityNodes.map { isNodeEnabled($0) },
                    activeColor: activeCapability?.color ?? KoeColors.accent
                )
            }

            // Language nodes section - use same generic connectors
            if !languageNodes.isEmpty && hasActiveCapability {
                GenericSplitConnector(
                    nodeStates: languageNodes.map { isNodeEnabled($0) },
                    activeColor: KoeColors.accent
                )

                // Language nodes
                VStack(spacing: 4) {
                    ForEach(languageNodes) { node in
                        let isActive = isNodeEnabled(node)
                        SubPipelineNodeView(node: node)
                            .opacity(hasActiveLanguage && !isActive ? 0.4 : 1.0)
                    }
                }

                // Merge connector from languages
                GenericMergeConnector(
                    nodeStates: languageNodes.map { isNodeEnabled($0) },
                    activeColor: activeLanguage?.color ?? KoeColors.accent
                )
            }

            // Output indicator showing connection to parent node
            OutputIndicator()
        }
    }

    private func isNodeEnabled(_ node: NodeInfo) -> Bool {
        guard let key = node.persistenceKey else { return node.isAlwaysEnabled }
        return UserDefaults.standard.bool(forKey: key)
    }
}

// MARK: - Output Indicator

struct OutputIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(KoeColors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Output to")
                    .font(.system(size: 9))
                    .foregroundColor(KoeColors.textLight)
                Text("Parent Node")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(KoeColors.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(KoeColors.surface)
        .cornerRadius(8)
    }
}

// MARK: - Sub-Pipeline Node View

struct SubPipelineNodeView: View {
    let node: NodeInfo
    @State private var isHovered = false
    @State private var refreshID = UUID()

    private var isEnabled: Bool {
        guard let key = node.persistenceKey else { return node.isAlwaysEnabled }
        return UserDefaults.standard.bool(forKey: key)
    }

    private let nodeSize: CGFloat = 44
    private let cornerRadius: CGFloat = 10

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // Background
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isEnabled ? node.color.opacity(0.15) : KoeColors.surface)
                    .frame(width: nodeSize, height: nodeSize)
                    .shadow(
                        color: .black.opacity(isHovered ? 0.10 : 0.05),
                        radius: isHovered ? 8 : 4,
                        y: 2
                    )

                // Icon
                Image(systemName: node.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isEnabled ? node.color : KoeColors.textLight)
                    .frame(width: nodeSize, height: nodeSize)

                // Toggle indicator
                if node.isUserToggleable {
                    Circle()
                        .fill(isEnabled ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                        .offset(x: -2, y: 2)
                } else if node.isAlwaysEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                        .offset(x: -2, y: 2)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isEnabled ? node.color : KoeColors.textLighter.opacity(0.3), lineWidth: 2)
            )

            // Label
            Text(node.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isEnabled ? KoeColors.accent : KoeColors.textSecondary)
                .fixedSize()
                .lineLimit(1)
        }
        .opacity(isEnabled ? 1.0 : 0.6)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .onTapGesture {
            if node.isUserToggleable {
                withAnimation(.easeOut(duration: 0.15)) {
                    let newValue = !isEnabled
                    if let key = node.persistenceKey {
                        UserDefaults.standard.set(newValue, forKey: key)

                        // Handle exclusive groups - disable other nodes in same group
                        if let group = node.exclusiveGroup, newValue {
                            let otherNodes = NodeRegistry.shared.nodesInExclusiveGroup(group)
                            for other in otherNodes where other.typeId != node.typeId {
                                if let otherKey = other.persistenceKey {
                                    UserDefaults.standard.set(false, forKey: otherKey)
                                }
                            }

                            // Notify all nodes in this exclusive group to refresh
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

