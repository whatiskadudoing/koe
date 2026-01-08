import SwiftUI
import KoeUI

/// Connecting line between pipeline nodes
struct PipelineConnector: View {
    let isActive: Bool
    var color: Color = KoeColors.accent

    private let width: CGFloat = 20
    private let height: CGFloat = 2

    var body: some View {
        Rectangle()
            .fill(isActive ? color : KoeColors.textLighter.opacity(0.4))
            .frame(width: width, height: height)
    }
}

#Preview {
    HStack(spacing: 8) {
        Circle()
            .fill(Color.green)
            .frame(width: 10, height: 10)

        PipelineConnector(isActive: true)

        Circle()
            .fill(Color.green)
            .frame(width: 10, height: 10)

        PipelineConnector(isActive: false)

        Circle()
            .fill(Color.gray)
            .frame(width: 10, height: 10)
    }
    .padding()
    .background(KoeColors.background)
}
