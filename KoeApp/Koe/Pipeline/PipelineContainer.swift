import KoeUI
import SwiftUI

// MARK: - Pipeline Container

/// Reusable container component for pipeline views
/// Provides consistent styling: background, rounded corners, padding
/// Use this to wrap both main pipeline and sub-pipeline content
struct PipelineContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, PipelineLayout.containerPaddingH)
            .padding(.vertical, PipelineLayout.containerPaddingV)
            .background(KoeColors.surface.opacity(0.5))
            .cornerRadius(PipelineLayout.cornerRadius + 6) // Slightly larger than node corners
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Example usage
        PipelineContainer {
            HStack {
                Text("Main Pipeline Content")
                    .foregroundColor(KoeColors.textSecondary)
            }
            .frame(height: 100)
        }

        PipelineContainer {
            HStack {
                Text("Sub-Pipeline Content")
                    .foregroundColor(KoeColors.textSecondary)
            }
            .frame(height: 100)
        }
    }
    .padding()
    .background(KoeColors.background)
}
