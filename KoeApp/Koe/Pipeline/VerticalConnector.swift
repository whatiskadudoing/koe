import KoeUI
import SwiftUI

/// Vertical connector between stage containers
/// Shows the flow direction with a subtle line and optional arrow
struct VerticalConnector: View {
    var isActive: Bool = true

    private var color: Color {
        isActive ? PipelineLayout.activeColor.opacity(0.5) : PipelineLayout.inactiveColor
    }

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: PipelineLayout.connectorLineWidth, height: PipelineLayout.verticalConnectorHeight)
    }
}

#Preview {
    VStack(spacing: 0) {
        RoundedRectangle(cornerRadius: 8)
            .fill(KoeColors.surface)
            .frame(width: 200, height: 60)

        VerticalConnector(isActive: true)

        RoundedRectangle(cornerRadius: 8)
            .fill(KoeColors.surface)
            .frame(width: 200, height: 60)

        VerticalConnector(isActive: false)

        RoundedRectangle(cornerRadius: 8)
            .fill(KoeColors.surface)
            .frame(width: 200, height: 60)
    }
    .padding()
    .background(KoeColors.background)
}
