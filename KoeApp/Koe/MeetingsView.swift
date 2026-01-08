import SwiftUI
import KoeDomain
import KoeMeeting

struct MeetingsView: View {
    @Environment(MeetingCoordinator.self) private var coordinator

    @State private var selectedMeeting: Meeting?
    @State private var showDetail = false
    @State private var errorMessage: String?
    @State private var isStartingRecording = false

    // Consistent color palette (matching app theme - warm Japanese aesthetic)
    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let cardBackground = Color.white
    private let pageBackground = Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))

    var body: some View {
        VStack(spacing: 0) {
            // Recording status bar or Start Recording button
            if coordinator.meetingState.isRecording {
                RecordingStatusBar(
                    meeting: coordinator.meetingState.currentMeeting!,
                    audioLevel: coordinator.audioLevel,
                    onStopRecording: {
                        Task {
                            try? await coordinator.stopRecording()
                        }
                    }
                )
            } else {
                // Start Recording button when not recording
                VStack(spacing: 8) {
                    HStack {
                        Spacer()
                        Button(action: {
                            errorMessage = nil
                            isStartingRecording = true
                            Task {
                                do {
                                    try await coordinator.startRecording(appName: "Manual Recording", appBundleId: "com.koe.manual")
                                } catch {
                                    await MainActor.run {
                                        errorMessage = "Error: \(error.localizedDescription)"
                                        isStartingRecording = false
                                    }
                                }
                            }
                        }) {
                            HStack(spacing: 8) {
                                if isStartingRecording {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 14, height: 14)
                                } else {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 10, height: 10)
                                }
                                Text(isStartingRecording ? "Starting..." : "Start Recording")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [Color.red, Color.red.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .cornerRadius(20)
                            .shadow(color: Color.red.opacity(0.3), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(isStartingRecording)
                        Spacer()
                    }

                    // Show error if any
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
                .background(pageBackground)
            }

            // Main content
            if coordinator.meetings.isEmpty && !coordinator.meetingState.isRecording {
                emptyState
            } else {
                meetingsList
            }
        }
        .background(pageBackground)
        .sheet(isPresented: $showDetail) {
            if let meeting = selectedMeeting {
                MeetingDetailView(meeting: meeting)
            }
        }
        .onChange(of: coordinator.meetingState.isRecording) { _, isRecording in
            // Reset button state when recording state changes
            if isRecording || !isRecording {
                isStartingRecording = false
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 10) {
                Text("No meetings yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(accentColor)

                Text("Meetings will be recorded automatically\nwhen you join Zoom, Teams, Meet, or other apps")
                    .font(.system(size: 14))
                    .foregroundColor(lightGray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Meetings List

    private var meetingsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(coordinator.meetings) { meeting in
                    MeetingRow(meeting: meeting) {
                        selectedMeeting = meeting
                        showDetail = true
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - Recording Status Bar

struct RecordingStatusBar: View {
    let meeting: Meeting
    let audioLevel: Float
    let onStopRecording: () -> Void

    @State private var blinkOpacity: Double = 1.0
    @State private var currentTime = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 14) {
            // Recording indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(blinkOpacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            blinkOpacity = 0.3
                        }
                    }

                Text("REC")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.red.opacity(0.15))
            .cornerRadius(12)

            // App name
            Text(meeting.appName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)

            Spacer()

            // Audio level bars
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 3, height: barHeight(for: index))
                }
            }

            // Duration
            Text(formatDuration(currentTime.timeIntervalSince(meeting.startTime)))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .onReceive(timer) { _ in
                    currentTime = Date()
                }

            // Stop Recording button
            Button(action: onStopRecording) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                    Text("Stop")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.2))
                .cornerRadius(16)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0)), Color(nsColor: NSColor(red: 0.34, green: 0.40, blue: 0.56, alpha: 1.0))],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 4
        let maxHeight: CGFloat = 18
        let variation = sin(Double(index) * 0.8 + Double(audioLevel) * 10) * 0.3 + 0.7
        return baseHeight + CGFloat(audioLevel * Float(variation)) * (maxHeight - baseHeight)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Meeting Row

struct MeetingRow: View {
    let meeting: Meeting
    let onTap: () -> Void

    @State private var isHovered = false

    // Consistent color palette (matching app theme)
    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // App icon
                appIcon

                // Meeting info
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(meeting.appName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(accentColor)

                        if meeting.isTranscribed {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                Text("Transcribed")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }

                    HStack(spacing: 8) {
                        // Date/time
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                            Text(formatDate(meeting.startTime))
                                .font(.system(size: 12))
                        }
                        .foregroundColor(lightGray)

                        // Duration
                        if let duration = meeting.duration {
                            Text("•")
                                .foregroundColor(lightGray.opacity(0.5))
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 10))
                                Text(formatDuration(duration))
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(lightGray)
                        }
                    }
                }

                Spacer()

                // Arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(lightGray.opacity(0.5))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 12 : 6, y: isHovered ? 4 : 2)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var appIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.15), accentColor.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)

            Image(systemName: appIconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(accentColor)
        }
    }

    private var appIconName: String {
        let name = meeting.appName.lowercased()
        if name.contains("zoom") { return "video.fill" }
        if name.contains("teams") { return "person.3.fill" }
        if name.contains("slack") { return "number" }
        if name.contains("chrome") || name.contains("safari") || name.contains("arc") || name.contains("meet") {
            return "globe"
        }
        if name.contains("discord") { return "headphones" }
        return "video.fill"
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today' h:mm a"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "'Yesterday' h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }

        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }
}
