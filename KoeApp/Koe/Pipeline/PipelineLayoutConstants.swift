import KoeUI
import SwiftUI

// MARK: - Pipeline Layout Constants

/// Centralized layout constants for the pipeline visualization system.
/// Use these everywhere to ensure consistent sizing and spacing across
/// main pipeline, sub-pipelines, and all node types.
enum PipelineLayout {
    // MARK: - Node Dimensions

    /// Width of a node card
    static let nodeWidth: CGFloat = 56

    /// Height of a node card (icon area + label inside)
    static let nodeSize: CGFloat = 56

    /// Total height of a node slot (same as nodeSize since label is inside)
    static let nodeHeight: CGFloat = 56

    /// Corner radius for node backgrounds
    static let cornerRadius: CGFloat = 12

    // MARK: - Spacing

    /// Vertical spacing between nodes in parallel sections
    static let nodeSpacing: CGFloat = 4

    /// Spacing between node icon and label (inside a node)
    static let labelSpacing: CGFloat = 4

    /// Horizontal padding inside the pipeline container
    static let containerPaddingH: CGFloat = 16

    /// Vertical padding inside the pipeline container
    static let containerPaddingV: CGFloat = 12

    // MARK: - Connector Dimensions

    /// Width of input line segment before split point
    static let connectorInputWidth: CGFloat = 20

    /// Width of split/merge area
    static let connectorSplitWidth: CGFloat = 16

    /// Width of output line segment after merge point
    static let connectorOutputWidth: CGFloat = 20

    /// Total width of a split connector
    static var splitConnectorWidth: CGFloat {
        connectorInputWidth + connectorSplitWidth
    }

    /// Total width of a merge connector
    static var mergeConnectorWidth: CGFloat {
        connectorSplitWidth + connectorOutputWidth
    }

    /// Width of a simple sequential connector
    static let simpleConnectorWidth: CGFloat = 20

    /// Height/thickness of connector lines
    static let connectorLineWidth: CGFloat = 2

    // MARK: - Colors

    /// Active connector color
    static var activeColor: Color { KoeColors.accent }

    /// Inactive connector color
    static var inactiveColor: Color { KoeColors.textLighter.opacity(0.4) }

    // MARK: - Calculations

    /// Calculate total height for a parallel section with N nodes
    static func parallelSectionHeight(nodeCount: Int) -> CGFloat {
        let nodesHeight = CGFloat(nodeCount) * nodeHeight
        let spacingHeight = CGFloat(max(0, nodeCount - 1)) * nodeSpacing
        return nodesHeight + spacingHeight
    }

    /// Calculate Y position for a node at given index in a parallel section
    static func nodeYPosition(at index: Int) -> CGFloat {
        let slotOffset = CGFloat(index) * nodeHeight
        let spacingOffset = CGFloat(index) * nodeSpacing
        let centerOffset = nodeSize / 2
        return slotOffset + spacingOffset + centerOffset
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        Text("Pipeline Layout Constants")
            .font(.headline)

        Group {
            Text("Node size: \(Int(PipelineLayout.nodeSize))px")
            Text("Node height (with label): \(Int(PipelineLayout.nodeHeight))px")
            Text("Corner radius: \(Int(PipelineLayout.cornerRadius))px")
            Text("Node spacing: \(Int(PipelineLayout.nodeSpacing))px")
        }
        .font(.system(size: 12, design: .monospaced))

        Divider()

        Group {
            Text("3 nodes section height: \(Int(PipelineLayout.parallelSectionHeight(nodeCount: 3)))px")
            Text("Node 0 Y: \(Int(PipelineLayout.nodeYPosition(at: 0)))px")
            Text("Node 1 Y: \(Int(PipelineLayout.nodeYPosition(at: 1)))px")
            Text("Node 2 Y: \(Int(PipelineLayout.nodeYPosition(at: 2)))px")
        }
        .font(.system(size: 12, design: .monospaced))
    }
    .padding()
    .background(KoeColors.background)
}
