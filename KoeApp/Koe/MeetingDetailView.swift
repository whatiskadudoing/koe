import SwiftUI
import AVFoundation
import KoeDomain
import KoeMeeting
import KoeTranscription

struct MeetingDetailView: View {
    let meeting: Meeting

    @Environment(\.dismiss) private var dismiss
    @Environment(MeetingCoordinator.self) private var coordinator

    @State private var isTranscribing = false
    @State private var transcriptionProgress: String = ""
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false
    @State private var isPlayingAudio = false
    @State private var audioPlayer: AVAudioPlayer?

    // Consistent color palette (matching app theme - warm Japanese aesthetic)
    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let pageBackground = Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))
    private let cardBackground = Color.white

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Meeting info card
                    infoCard

                    // Audio player card
                    if meeting.audioFilePath != nil {
                        audioPlayerCard
                    }

                    // Transcript section
                    transcriptSection

                    // Error message
                    if let error = errorMessage {
                        errorCard(error)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 440, height: 560)
        .background(pageBackground)
        .alert("Delete Meeting?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    try? await coordinator.deleteMeeting(meeting)
                    dismiss()
                }
            }
        } message: {
            Text("This will permanently delete the recording and transcript.")
        }
        .onDisappear {
            audioPlayer?.stop()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(accentColor.opacity(0.1))
                .cornerRadius(18)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: { showDeleteConfirm = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red.opacity(0.8))
                    .padding(10)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(cardBackground.opacity(0.8))
    }

    // MARK: - Info Card

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            // App name and icon
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.2), accentColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: appIconName)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(accentColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(meeting.appName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(accentColor)

                    Text(formatFullDate(meeting.startTime))
                        .font(.system(size: 13))
                        .foregroundColor(lightGray)
                }

                Spacer()
            }

            // Stats row
            HStack(spacing: 0) {
                StatCard(icon: "clock.fill", value: formatDuration(meeting.duration ?? 0), label: "Duration", color: accentColor)

                Divider()
                    .frame(height: 40)
                    .padding(.horizontal, 12)

                StatCard(icon: "calendar", value: formatShortDate(meeting.startTime), label: "Date", color: accentColor)

                Divider()
                    .frame(height: 40)
                    .padding(.horizontal, 12)

                StatCard(
                    icon: meeting.isTranscribed ? "checkmark.circle.fill" : "text.quote",
                    value: meeting.isTranscribed ? "Done" : "Pending",
                    label: "Transcript",
                    color: meeting.isTranscribed ? .green : lightGray
                )
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(pageBackground)
            .cornerRadius(12)
        }
        .padding(18)
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    // MARK: - Audio Player Card

    private var audioPlayerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recording")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(lightGray)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                if let url = coordinator.audioFileURL(for: meeting) {
                    Button(action: {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text("Show in Finder")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 14) {
                // Play button
                Button(action: togglePlayback) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [accentColor, accentColor.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .shadow(color: accentColor.opacity(0.3), radius: 8, y: 4)

                        Image(systemName: isPlayingAudio ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .offset(x: isPlayingAudio ? 0 : 2)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.audioFilePath?.components(separatedBy: "/").last ?? "Audio Recording")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(accentColor)
                        .lineLimit(1)

                    if let url = coordinator.audioFileURL(for: meeting) {
                        Text(formatFileSize(url))
                            .font(.system(size: 12))
                            .foregroundColor(lightGray)
                    }
                }

                Spacer()
            }
            .padding(14)
            .background(pageBackground)
            .cornerRadius(12)
        }
        .padding(18)
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    // MARK: - Transcript Section

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Transcript")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(lightGray)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                if meeting.isTranscribed {
                    Button(action: copyTranscript) {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                            Text("Copy")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accentColor.opacity(0.1))
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let transcript = meeting.transcript {
                // Show transcript
                Text(transcript)
                    .font(.system(size: 14))
                    .foregroundColor(accentColor)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(pageBackground)
                    .cornerRadius(12)
            } else {
                // Transcribe button
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.1))
                            .frame(width: 64, height: 64)

                        if isTranscribing {
                            ProgressView()
                                .scaleEffect(1.2)
                        } else {
                            Image(systemName: "waveform")
                                .font(.system(size: 28))
                                .foregroundColor(accentColor)
                        }
                    }

                    VStack(spacing: 6) {
                        Text(isTranscribing ? "Transcribing..." : "No transcript yet")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(accentColor)

                        if isTranscribing {
                            Text(transcriptionProgress)
                                .font(.system(size: 12))
                                .foregroundColor(lightGray)
                        } else {
                            Text("Generate a transcript using AI")
                                .font(.system(size: 13))
                                .foregroundColor(lightGray)
                        }
                    }

                    if !isTranscribing {
                        Button(action: transcribeMeeting) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14))
                                Text("Transcribe Meeting")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [accentColor, accentColor.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(22)
                            .shadow(color: accentColor.opacity(0.3), radius: 10, y: 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(pageBackground)
                .cornerRadius(12)
            }
        }
        .padding(18)
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    // MARK: - Error Card

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.orange)
            Spacer()
        }
        .padding(14)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Helpers

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

    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d 'at' h:mm a"
        return formatter.string(from: date)
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes) min"
        } else {
            return "<1 min"
        }
    }

    private func formatFileSize(_ url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return "Unknown size"
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func copyTranscript() {
        guard let transcript = meeting.transcript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }

    private func togglePlayback() {
        if isPlayingAudio {
            audioPlayer?.stop()
            isPlayingAudio = false
        } else {
            guard let url = coordinator.audioFileURL(for: meeting) else { return }
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.play()
                isPlayingAudio = true
            } catch {
                errorMessage = "Could not play audio: \(error.localizedDescription)"
            }
        }
    }

    private func transcribeMeeting() {
        guard let audioURL = coordinator.audioFileURL(for: meeting) else {
            errorMessage = "No audio file found"
            return
        }

        isTranscribing = true
        errorMessage = nil
        transcriptionProgress = "Loading model..."

        Task {
            do {
                let transcriber = WhisperKitTranscriber()

                // Load a small model for faster transcription
                transcriptionProgress = "Loading whisper model..."
                try await transcriber.loadModel(.base)

                transcriptionProgress = "Transcribing audio..."
                let transcript = try await transcriber.transcribeFile(url: audioURL, language: nil)

                // Save the transcript
                try await coordinator.updateMeetingTranscript(meeting, transcript: transcript)

                await MainActor.run {
                    isTranscribing = false
                    transcriptionProgress = ""
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Transcription failed: \(error.localizedDescription)"
                    isTranscribing = false
                    transcriptionProgress = ""
                }
            }
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    // Consistent color palette (matching app theme)
    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(accentColor)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(lightGray)
        }
        .frame(maxWidth: .infinity)
    }
}
