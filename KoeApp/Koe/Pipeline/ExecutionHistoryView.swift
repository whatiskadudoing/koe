import KoeStorage
import KoeUI
import SwiftUI

// MARK: - Execution History List

/// Displays recent pipeline executions from PipelineDataService
struct ExecutionHistoryList: View {
    @State private var executions: [PipelineExecutionData] = []
    @State private var selectedExecution: PipelineExecutionData?
    @State private var isLoading = true

    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Recent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(lightGray)
                    .tracking(0.5)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                } else {
                    Text("\(executions.count)")
                        .font(.system(size: 10))
                        .foregroundColor(lightGray.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)

            // Horizontal scrollable list
            if executions.isEmpty && !isLoading {
                Text("No dictations yet")
                    .font(.system(size: 12))
                    .foregroundColor(lightGray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(executions.prefix(20)) { execution in
                            ExecutionHistoryCard(
                                execution: execution,
                                onTap: {
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        selectedExecution = execution
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .task {
            await loadExecutions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pipelineExecutionSaved)) { _ in
            Task {
                await loadExecutions()
            }
        }
        .sheet(item: $selectedExecution) { execution in
            ExecutionDetailView(execution: execution)
        }
    }

    private func loadExecutions() async {
        isLoading = true
        do {
            executions = try await PipelineDataService.shared.getRecent(limit: 50)
        } catch {
            print("[ExecutionHistoryList] Failed to load: \(error)")
            executions = []
        }
        isLoading = false
    }
}

// MARK: - Execution History Card

struct ExecutionHistoryCard: View {
    let execution: PipelineExecutionData
    var onTap: (() -> Void)?

    @State private var isHovered = false
    @State private var appeared = false

    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let textColor = Color(nsColor: NSColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0))

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 8) {
                // Text preview (final output or original input)
                let previewText = execution.finalOutput.isEmpty ? execution.originalInput : execution.finalOutput
                Text(previewText.prefix(60) + (previewText.count > 60 ? "..." : ""))
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // Bottom row: timestamp, duration, status
                HStack {
                    Text(formatTimestamp(execution.timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(lightGray)

                    Spacer()

                    // Duration badge
                    Text(execution.formattedDuration)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(KoeColors.accent.opacity(0.8))

                    // Status indicator
                    statusIndicator
                }
            }
            .padding(12)
            .frame(width: 160, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(
                        color: .black.opacity(isHovered ? 0.10 : 0.05),
                        radius: isHovered ? 8 : 4,
                        y: isHovered ? 3 : 2
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -20)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch execution.status {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.red)
        case .cancelled:
            Image(systemName: "stop.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
        default:
            EmptyView()
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Execution Detail View

struct ExecutionDetailView: View {
    let execution: PipelineExecutionData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            KoeColors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header with close button
                    headerSection

                    // Quick summary bar
                    summaryBar

                    // Node Flow - the main content
                    nodeFlowSection

                    // Global error (if pipeline failed)
                    if let error = execution.error {
                        globalErrorSection(error)
                    }

                    // Export button at the bottom
                    exportSection
                }
                .padding(20)
            }
        }
        .frame(width: 500, height: 700)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Execution Details")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(KoeColors.accent)

                Text(formatFullDate(execution.timestamp))
                    .font(.system(size: 12))
                    .foregroundColor(KoeColors.textLight)
            }

            Spacer()

            // Status badge
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(execution.status.rawValue.capitalized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(statusColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.1))
            .cornerRadius(12)

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(KoeColors.textLight)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: 16) {
            SummaryChip(icon: "clock", label: execution.formattedDuration)
            SummaryChip(icon: "arrow.triangle.branch", label: "\(execution.nodes.count) nodes")
            SummaryChip(icon: "hand.tap", label: execution.triggerType.capitalized)

            Spacer()
        }
    }

    // MARK: - Node Flow Section

    private var nodeFlowSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PIPELINE FLOW")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(KoeColors.textLight)
                .tracking(0.5)
                .padding(.bottom, 12)

            // Nodes in execution order
            ForEach(Array(execution.nodes.enumerated()), id: \.element.nodeTypeId) { index, node in
                NodeFlowCard(
                    node: node,
                    isFirst: index == 0,
                    isLast: index == execution.nodes.count - 1,
                    subPipelineSettings: execution.subPipelineSettings,
                    pipelineSettings: execution.settings
                )

                // Connector line between nodes
                if index < execution.nodes.count - 1 {
                    NodeConnector()
                }
            }
        }
    }

    // MARK: - Global Error Section

    private func globalErrorSection(_ error: NodeError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PIPELINE ERROR")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.red)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 8) {
                Text(error.message)
                    .font(.system(size: 13))
                    .foregroundColor(.red)

                if let details = error.details {
                    Text(details)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(KoeColors.textLight)
                        .textSelection(.enabled)
                }

                CopyButton(text: "\(error.code): \(error.message)\n\(error.details ?? "")", label: "Copy Error")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        HStack(spacing: 12) {
            Spacer()

            // Copy all as JSON
            Button(action: exportAsJSON) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11))
                    Text("Copy Full Data (JSON)")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(KoeColors.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(KoeColors.accent.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch execution.status {
        case .success: return .green
        case .failed: return .red
        case .cancelled: return .orange
        default: return KoeColors.textSecondary
        }
    }

    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm:ss a"
        return formatter.string(from: date)
    }

    private func exportAsJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(execution),
            let jsonString = String(data: data, encoding: .utf8)
        {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(jsonString, forType: .string)
        }
    }
}

// MARK: - Summary Chip

struct SummaryChip: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(KoeColors.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(KoeColors.surface)
        .cornerRadius(6)
    }
}

// MARK: - Node Connector

struct NodeConnector: View {
    var body: some View {
        HStack {
            Rectangle()
                .fill(KoeColors.accent.opacity(0.3))
                .frame(width: 2, height: 20)
                .padding(.leading, 20)
            Spacer()
        }
    }
}

// MARK: - Node Flow Card

struct NodeFlowCard: View {
    let node: NodeExecutionData
    let isFirst: Bool
    let isLast: Bool
    let subPipelineSettings: SubPipelineSettings?
    let pipelineSettings: PipelineSettings

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header (always visible)
            cardHeader

            // Expandable content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .padding(.horizontal, 16)

                    // Input section
                    if node.input.type != .none {
                        inputSection
                    }

                    // Output section
                    if node.output.type != .none {
                        outputSection
                    }

                    // Node-specific details
                    nodeSpecificDetails

                    // Error if this node failed
                    if let error = node.error {
                        nodeErrorSection(error)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1.5)
        )
    }

    // MARK: - Card Header

    private var cardHeader: some View {
        Button(action: { withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() } }) {
            HStack(spacing: 12) {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                // Node name and type
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.nodeName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(KoeColors.accent)

                    Text(node.nodeTypeId)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(KoeColors.textLight)
                }

                Spacer()

                // Duration
                Text(node.formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(KoeColors.textSecondary)

                // Expand/collapse indicator
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(KoeColors.textLight)
            }
            .padding(16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Input", systemImage: "arrow.right.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(KoeColors.textLight)

                Spacer()

                // Copy input button
                if let text = node.input.text, !text.isEmpty {
                    SmallCopyButton(text: text)
                }

                // Play audio button
                if node.input.type == .audio, let path = node.input.audioPath, !path.isEmpty {
                    PlayAudioButton(path: path)
                }
            }

            // Input content
            inputContent
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var inputContent: some View {
        switch node.input.type {
        case .text:
            if let text = node.input.text {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(KoeColors.textSecondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(KoeColors.background.opacity(0.5))
                    .cornerRadius(8)
            }
        case .audio:
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 14))
                    .foregroundColor(KoeColors.accent)
                if let duration = node.input.audioDuration {
                    Text(String(format: "%.1fs audio", duration))
                        .font(.system(size: 12))
                        .foregroundColor(KoeColors.textSecondary)
                }
                if let path = node.input.audioPath {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(KoeColors.textLight)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KoeColors.background.opacity(0.5))
            .cornerRadius(8)
        default:
            EmptyView()
        }
    }

    // MARK: - Output Section

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Output", systemImage: "arrow.left.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(KoeColors.textLight)

                if node.output.wasTransformed {
                    Text("(transformed)")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }

                Spacer()

                // Copy output button
                if let text = node.output.text, !text.isEmpty {
                    SmallCopyButton(text: text)
                }
            }

            // Output content
            outputContent
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var outputContent: some View {
        switch node.output.type {
        case .text:
            if let text = node.output.text {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(KoeColors.textSecondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(KoeColors.background.opacity(0.5))
                    .cornerRadius(8)
            }
        case .audio:
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 14))
                    .foregroundColor(KoeColors.accent)
                if let duration = node.output.audioDuration {
                    Text(String(format: "%.1fs audio", duration))
                        .font(.system(size: 12))
                        .foregroundColor(KoeColors.textSecondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KoeColors.background.opacity(0.5))
            .cornerRadius(8)
        case .action:
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                Text("Action performed")
                    .font(.system(size: 12))
                    .foregroundColor(KoeColors.textSecondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KoeColors.background.opacity(0.5))
            .cornerRadius(8)
        default:
            EmptyView()
        }
    }

    // MARK: - Node Specific Details

    @ViewBuilder
    private var nodeSpecificDetails: some View {
        let details = buildNodeDetails()
        if !details.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Details")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(KoeColors.textLight)

                VStack(spacing: 4) {
                    ForEach(details, id: \.key) { detail in
                        HStack {
                            Text(detail.key)
                                .font(.system(size: 11))
                                .foregroundColor(KoeColors.textLight)
                            Spacer()
                            Text(detail.value)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(KoeColors.textSecondary)
                        }
                    }
                }
                .padding(10)
                .background(KoeColors.background.opacity(0.5))
                .cornerRadius(8)
            }
            .padding(.horizontal, 16)
        }
    }

    private func buildNodeDetails() -> [(key: String, value: String)] {
        var details: [(key: String, value: String)] = []

        // Add custom data
        for (key, value) in node.customData.sorted(by: { $0.key < $1.key }) {
            let formattedKey = key.replacingOccurrences(
                of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression
            ).capitalized

            switch value {
            case .string(let s):
                if !s.isEmpty && s.count < 100 {
                    details.append((formattedKey, s))
                }
            case .int(let i):
                details.append((formattedKey, "\(i)"))
            case .double(let d):
                if formattedKey.lowercased().contains("confidence") {
                    details.append((formattedKey, String(format: "%.1f%%", d * 100)))
                } else {
                    details.append((formattedKey, String(format: "%.2f", d)))
                }
            case .bool(let b):
                details.append((formattedKey, b ? "Yes" : "No"))
            default:
                break
            }
        }

        // Add sub-pipeline settings if this is an AI node
        if node.nodeTypeId.contains("ai-") || node.nodeTypeId.contains("text-improve") {
            if let settings = subPipelineSettings {
                if let style = settings.rewriteStyle {
                    details.append(("Rewrite Style", style.capitalized))
                }
                if settings.translateEnabled {
                    details.append(("Translation", "Enabled"))
                    if let lang = settings.targetLanguage {
                        details.append(("Target Language", lang))
                    }
                }
            }
        }

        // Add transcription engine info
        if node.nodeTypeId.contains("transcribe") {
            details.append(("Engine", formatEngineId(pipelineSettings.transcriptionEngine)))
        }

        return details
    }

    // MARK: - Node Error Section

    private func nodeErrorSection(_ error: NodeError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.red)

            VStack(alignment: .leading, spacing: 4) {
                Text(error.message)
                    .font(.system(size: 12))
                    .foregroundColor(.red)

                if let details = error.details {
                    Text(details)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(KoeColors.textLight)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.05))
            .cornerRadius(8)

            SmallCopyButton(text: "\(error.code): \(error.message)")
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch node.status {
        case .success: return .green
        case .failed: return .red
        case .skipped: return .gray
        case .cancelled: return .orange
        default: return .blue
        }
    }

    private var borderColor: Color {
        switch node.status {
        case .failed: return .red.opacity(0.3)
        default: return KoeColors.textLighter.opacity(0.2)
        }
    }

    private func formatEngineId(_ id: String) -> String {
        id.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - Small Copy Button

struct SmallCopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { copied = false }
        }) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundColor(copied ? .green : KoeColors.accent)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Play Audio Button

struct PlayAudioButton: View {
    let path: String
    @State private var isPlaying = false

    var body: some View {
        Button(action: playAudio) {
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 10))
                .foregroundColor(KoeColors.accent)
        }
        .buttonStyle(.plain)
        .disabled(!FileManager.default.fileExists(atPath: path))
        .opacity(FileManager.default.fileExists(atPath: path) ? 1 : 0.3)
    }

    private func playAudio() {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Detail Section

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(KoeColors.textLight)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        }
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String
    var color: Color = KoeColors.textSecondary

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(KoeColors.textLight)

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
        }
    }
}

// MARK: - Copy Button

struct CopyButton: View {
    let text: String
    let label: String
    @State private var copied = false

    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copied = false
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                Text(copied ? "Copied!" : label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(copied ? .green : KoeColors.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(KoeColors.accent.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AnyCodableValue Extensions

extension AnyCodableValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let value) = self { return value }
        if case .int(let value) = self { return Double(value) }
        return nil
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let pipelineExecutionSaved = Notification.Name("pipelineExecutionSaved")
}
