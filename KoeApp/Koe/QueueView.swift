import KoeUI
import SwiftUI

// MARK: - Queue View

/// Third tab showing active setup jobs
struct QueueView: View {
    @ObservedObject private var scheduler = JobScheduler.shared

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let textColor = Color(nsColor: NSColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0))

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Setup")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(textColor)
                    Spacer()

                    if scheduler.jobs.contains(where: { $0.isCompleted }) {
                        Button("Clear") {
                            scheduler.clearCompleted()
                        }
                        .font(.system(size: 12))
                        .foregroundColor(lightGray)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // Show jobs
                if !scheduler.jobs.isEmpty {
                    ForEach(scheduler.jobs) { job in
                        JobRowView(
                            job: job,
                            onRetry: {
                                scheduler.retry(jobId: job.id)
                            }
                        )
                    }
                } else {
                    // Empty state - show all set message
                    AllSetView()
                }

                Spacer(minLength: 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

// MARK: - Job Row View

struct JobRowView: View {
    let job: Job
    let onRetry: () -> Void

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let textColor = Color(nsColor: NSColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0))

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Job header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: job.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(textColor)

                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundColor(lightGray)
                }

                Spacer()

                statusBadge
            }

            // Task list
            VStack(spacing: 8) {
                ForEach(job.tasks) { task in
                    TaskRowView(task: task)
                }
            }

            // Retry button if failed
            if job.isFailed {
                Button(action: onRetry) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                        Text("Retry")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(accentColor)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .padding(.horizontal, 16)
    }

    private var statusColor: Color {
        if job.isCompleted { return .green }
        if job.isFailed { return .red }
        return accentColor
    }

    private var statusText: String {
        if job.isCompleted { return "Completed" }
        if job.isFailed { return "Failed" }
        if let current = job.tasks.first(where: { $0.status == .running }) {
            return current.message ?? current.name
        }
        return "Queued"
    }

    @ViewBuilder
    private var statusBadge: some View {
        if job.isCompleted {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                Text("Done")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.green)
        } else if job.isFailed {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                Text("Failed")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.red)
        } else {
            Text("\(Int(job.progress * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(accentColor)
        }
    }
}

// MARK: - Task Row View

struct TaskRowView: View {
    let task: JobTask

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let textColor = Color(nsColor: NSColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0))

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            statusIcon
                .frame(width: 16)

            // Task name
            Text(task.name)
                .font(.system(size: 12))
                .foregroundColor(task.status == .completed ? lightGray : textColor)

            Spacer()

            // Progress or status
            if task.status == .running {
                if task.progress > 0 {
                    Text("\(Int(task.progress * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(accentColor)
                } else {
                    ProgressView()
                        .scaleEffect(0.5)
                }
            } else if task.status == .failed {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .help(task.error ?? "Failed")
            } else if task.status == .completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(task.status == .running ? accentColor.opacity(0.05) : Color.clear)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch task.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.green)
        case .running:
            Image(systemName: task.icon)
                .font(.system(size: 12))
                .foregroundColor(accentColor)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 12))
                .foregroundColor(lightGray.opacity(0.5))
        }
    }
}

// MARK: - Needs Setup View

struct NeedsSetupView: View {
    let nodeName: String
    let nodeIcon: String
    let onSetup: () -> Void

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let textColor = Color(nsColor: NSColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0))

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 56, height: 56)

                Image(systemName: nodeIcon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(accentColor)
            }

            VStack(spacing: 4) {
                Text("\(nodeName) needs setup")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(textColor)

                Text("Download models to enable offline transcription")
                    .font(.system(size: 12))
                    .foregroundColor(lightGray)
                    .multilineTextAlignment(.center)
            }

            Button(action: onSetup) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 12))
                    Text("Set Up Now")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(accentColor)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - All Set View

struct AllSetView: View {
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(lightGray.opacity(0.5))

            VStack(spacing: 4) {
                Text("All Set")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(lightGray)

                Text("All features are ready to use")
                    .font(.system(size: 13))
                    .foregroundColor(lightGray.opacity(0.7))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

// MARK: - Preview

#Preview {
    QueueView()
        .frame(width: 320, height: 400)
        .background(KoeColors.background)
}
