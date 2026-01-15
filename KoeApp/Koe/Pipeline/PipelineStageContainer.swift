import KoeUI
import SwiftUI

/// Container for a pipeline stage with header label
/// Used in the vertical pipeline layout to group related nodes
struct PipelineStageContainer<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            // Header
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(KoeColors.textTertiary)
                .tracking(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            // Content
            content
                .padding(.horizontal, PipelineLayout.containerPaddingH)
                .padding(.vertical, PipelineLayout.containerPaddingV)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: PipelineLayout.cornerRadius + 4)
                        .fill(KoeColors.surface.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PipelineLayout.cornerRadius + 4)
                        .stroke(KoeColors.textLighter.opacity(0.15), lineWidth: 1)
                )
        }
    }
}

/// A row of nodes within a stage container
struct PipelineStageRow: View {
    let content: AnyView

    init<Content: View>(@ViewBuilder content: () -> Content) {
        self.content = AnyView(content())
    }

    var body: some View {
        HStack(spacing: PipelineLayout.nodeRowSpacing) {
            content
        }
    }
}

/// Separator line between rows in a container
struct PipelineRowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(KoeColors.textLighter.opacity(0.15))
            .frame(height: 1)
            .padding(.vertical, 10)
    }
}

#Preview {
    VStack(spacing: PipelineLayout.stageContainerSpacing) {
        PipelineStageContainer(title: "Triggers") {
            PipelineStageRow {
                ForEach(0..<3) { i in
                    RoundedRectangle(cornerRadius: PipelineLayout.cornerRadius)
                        .fill(KoeColors.accent.opacity(0.3))
                        .frame(width: PipelineLayout.nodeSize, height: PipelineLayout.nodeSize)
                        .overlay(Text("\(i + 1)").font(.caption))
                }
            }
        }

        VerticalConnector(isActive: true)

        PipelineStageContainer(title: "Transcription") {
            VStack(alignment: .leading, spacing: 0) {
                PipelineStageRow {
                    ForEach(0..<3) { i in
                        RoundedRectangle(cornerRadius: PipelineLayout.cornerRadius)
                            .fill(KoeColors.stateTranscribing.opacity(0.3))
                            .frame(width: PipelineLayout.nodeSize, height: PipelineLayout.nodeSize)
                            .overlay(Text("T\(i + 1)").font(.caption))
                    }
                }

                PipelineRowSeparator()

                PipelineStageRow {
                    RoundedRectangle(cornerRadius: PipelineLayout.cornerRadius)
                        .fill(KoeColors.accent.opacity(0.3))
                        .frame(width: PipelineLayout.nodeSize, height: PipelineLayout.nodeSize)
                        .overlay(Text("LP").font(.caption))
                }
            }
        }
    }
    .padding()
    .background(KoeColors.background)
}
