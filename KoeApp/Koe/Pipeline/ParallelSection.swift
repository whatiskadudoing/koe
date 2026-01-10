import KoeUI
import SwiftUI

// MARK: - Parallel Section

/// A reusable component for rendering parallel nodes in a pipeline flowchart.
/// Pass any array of items and configure how they should be displayed.
///
/// Usage:
/// ```swift
/// ParallelSection(
///     items: transcriptionEngines,
///     itemStates: [isAppleEnabled, isBalancedEnabled, isAccurateEnabled],
///     showSplitConnector: true,
///     showMergeConnector: true
/// ) { engine, isEnabled in
///     PipelineNodeView(stage: engine, isEnabled: isEnabled, ...)
/// }
/// ```
struct ParallelSection<Item, Content: View>: View {
    let items: [Item]
    let itemStates: [Bool]
    let showSplitConnector: Bool
    let showMergeConnector: Bool
    let activeColor: Color
    let content: (Item, Int, Bool) -> Content

    init(
        items: [Item],
        itemStates: [Bool],
        showSplitConnector: Bool = true,
        showMergeConnector: Bool = true,
        activeColor: Color = PipelineLayout.activeColor,
        @ViewBuilder content: @escaping (Item, Int, Bool) -> Content
    ) {
        self.items = items
        self.itemStates = itemStates
        self.showSplitConnector = showSplitConnector
        self.showMergeConnector = showMergeConnector
        self.activeColor = activeColor
        self.content = content
    }

    var body: some View {
        HStack(spacing: 0) {
            // Split connector (input -> multiple outputs)
            if showSplitConnector {
                SplitConnector(
                    nodeStates: itemStates,
                    activeColor: activeColor
                )
            }

            // Nodes stacked vertically
            VStack(spacing: PipelineLayout.nodeSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    let isActive = index < itemStates.count ? itemStates[index] : false
                    content(item, index, isActive)
                }
            }

            // Merge connector (multiple inputs -> output)
            if showMergeConnector {
                MergeConnector(
                    nodeStates: itemStates,
                    activeColor: activeColor
                )
            }
        }
    }
}

// MARK: - Split Connector

/// Draws lines from a single input point splitting to multiple node outputs.
/// Used at the start of a parallel section.
struct SplitConnector: View {
    let nodeStates: [Bool]
    let activeColor: Color

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let splitX = PipelineLayout.connectorInputWidth
            let hasAnyActive = nodeStates.contains(true)

            // Input line from previous node to split point
            var inPath = Path()
            inPath.move(to: CGPoint(x: 0, y: midY))
            inPath.addLine(to: CGPoint(x: splitX, y: midY))
            context.stroke(
                inPath,
                with: .color(hasAnyActive ? activeColor : PipelineLayout.inactiveColor),
                style: StrokeStyle(lineWidth: PipelineLayout.connectorLineWidth, lineCap: .round)
            )

            // Lines from split point to each node
            for (index, isActive) in nodeStates.enumerated() {
                let nodeY = PipelineLayout.nodeYPosition(at: index)

                var path = Path()
                path.move(to: CGPoint(x: splitX, y: midY))
                path.addLine(to: CGPoint(x: splitX, y: nodeY))
                path.addLine(to: CGPoint(x: size.width, y: nodeY))
                context.stroke(
                    path,
                    with: .color(isActive ? activeColor : PipelineLayout.inactiveColor),
                    style: StrokeStyle(lineWidth: PipelineLayout.connectorLineWidth, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(
            width: PipelineLayout.splitConnectorWidth,
            height: PipelineLayout.parallelSectionHeight(nodeCount: nodeStates.count)
        )
    }
}

// MARK: - Merge Connector

/// Draws lines from multiple node inputs merging to a single output point.
/// Used at the end of a parallel section.
struct MergeConnector: View {
    let nodeStates: [Bool]
    let activeColor: Color

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let mergeX = PipelineLayout.connectorSplitWidth
            let hasAnyActive = nodeStates.contains(true)

            // Lines from each node to merge point
            for (index, isActive) in nodeStates.enumerated() {
                let nodeY = PipelineLayout.nodeYPosition(at: index)

                var path = Path()
                path.move(to: CGPoint(x: 0, y: nodeY))
                path.addLine(to: CGPoint(x: mergeX, y: nodeY))
                path.addLine(to: CGPoint(x: mergeX, y: midY))
                context.stroke(
                    path,
                    with: .color(isActive ? activeColor : PipelineLayout.inactiveColor),
                    style: StrokeStyle(lineWidth: PipelineLayout.connectorLineWidth, lineCap: .round, lineJoin: .round)
                )
            }

            // Output line from merge point to next node
            var outPath = Path()
            outPath.move(to: CGPoint(x: mergeX, y: midY))
            outPath.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(
                outPath,
                with: .color(hasAnyActive ? activeColor : PipelineLayout.inactiveColor),
                style: StrokeStyle(lineWidth: PipelineLayout.connectorLineWidth, lineCap: .round)
            )
        }
        .frame(
            width: PipelineLayout.mergeConnectorWidth,
            height: PipelineLayout.parallelSectionHeight(nodeCount: nodeStates.count)
        )
    }
}

// MARK: - Simple Connector

/// A simple horizontal line connector between sequential nodes.
struct SimpleConnector: View {
    let isActive: Bool
    var activeColor: Color = PipelineLayout.activeColor

    var body: some View {
        Rectangle()
            .fill(isActive ? activeColor : PipelineLayout.inactiveColor)
            .frame(width: PipelineLayout.simpleConnectorWidth, height: PipelineLayout.connectorLineWidth)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        // 2-node parallel section
        ParallelSection(
            items: ["Hotkey", "Voice"],
            itemStates: [true, false],
            showSplitConnector: false,
            showMergeConnector: true
        ) { item, _, isActive in
            RoundedRectangle(cornerRadius: PipelineLayout.cornerRadius)
                .fill(isActive ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                .frame(width: PipelineLayout.nodeSize, height: PipelineLayout.nodeSize)
                .overlay(Text(item).font(.system(size: 8)))
        }

        // 3-node parallel section
        ParallelSection(
            items: ["Apple", "Balanced", "Accurate"],
            itemStates: [false, true, false]
        ) { item, _, isActive in
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: PipelineLayout.cornerRadius)
                    .fill(isActive ? Color.green.opacity(0.2) : Color.gray.opacity(0.1))
                    .frame(width: PipelineLayout.nodeSize, height: PipelineLayout.nodeSize)
                Text(item)
                    .font(.system(size: 9))
            }
        }
    }
    .padding()
    .background(KoeColors.background)
}
