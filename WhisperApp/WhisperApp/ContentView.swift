import SwiftUI
import KoeDomain

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @ObservedObject private var recordingService = RecordingService.shared

    var body: some View {
        ZStack {
            // Background - warm off-white (washi paper)
            Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Settings button at top right
                HStack {
                    Spacer()
                    Button(action: {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }) {
                        Image(systemName: "gear")
                            .font(.system(size: 14))
                            .foregroundColor(Color(nsColor: NSColor(red: 0.50, green: 0.48, blue: 0.46, alpha: 1.0)))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.top, 12)
                }

                // Top spacing
                Spacer()
                    .frame(height: 20)

                // Main content area
                VStack(spacing: 32) {
                    // Mic button
                    MicButton(
                        state: appState.recordingState,
                        audioLevel: recordingService.audioLevel,
                        onTap: {
                            if appState.recordingState == .idle {
                                RecordingService.shared.startRecording()
                            } else if appState.recordingState == .recording {
                                RecordingService.shared.stopRecording()
                            }
                        }
                    )

                    // Status text
                    StatusText(state: appState.recordingState)

                    // Hotkey hint
                    HotkeyHint()

                    // Mode toggle
                    ModeToggle()

                    // Transcription display
                    if !appState.currentTranscription.isEmpty {
                        TranscriptionCard(text: appState.currentTranscription)
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                // Bottom section - history preview
                if !appState.transcriptionHistory.isEmpty {
                    HistoryPreview(entries: appState.transcriptionHistory)
                        .padding(.bottom, 24)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 520)
    }
}

// MARK: - Mic Button

struct MicButton: View {
    let state: RecordingState
    let audioLevel: Float
    let onTap: () -> Void

    // Japanese indigo accent
    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Outer ring - audio visualization
                if state == .recording {
                    Circle()
                        .stroke(accentColor.opacity(0.3), lineWidth: 2)
                        .frame(width: 140 + CGFloat(audioLevel) * 40, height: 140 + CGFloat(audioLevel) * 40)
                        .animation(.easeOut(duration: 0.1), value: audioLevel)
                }

                // Main circle
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 8)

                // Inner content
                Group {
                    switch state {
                    case .idle:
                        Image(systemName: "mic.fill")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(accentColor)

                    case .recording:
                        WaveformView(audioLevel: audioLevel, color: .white)
                            .frame(width: 60, height: 40)

                    case .processing:
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: state)
    }

    private var backgroundColor: Color {
        switch state {
        case .idle:
            return Color.white
        case .recording:
            return Color.red.opacity(0.9)
        case .processing:
            return accentColor
        }
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    let audioLevel: Float
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.15), value: audioLevel)
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 8
        let maxHeight: CGFloat = 36
        let variation = sin(Double(index) * 0.8 + Double(audioLevel) * 10) * 0.3 + 0.7
        return baseHeight + CGFloat(audioLevel * Float(variation)) * (maxHeight - baseHeight)
    }
}

// MARK: - Status Text

struct StatusText: View {
    let state: RecordingState

    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

    var body: some View {
        Text(statusText)
            .font(.system(size: 13, weight: .regular, design: .default))
            .foregroundColor(lightGray)
            .tracking(0.5)
    }

    private var statusText: String {
        switch state {
        case .idle:
            return "tap to speak"
        case .recording:
            return "listening..."
        case .processing:
            return "transcribing..."
        }
    }
}

// MARK: - Hotkey Hint

struct HotkeyHint: View {
    private let lightGray = Color(nsColor: NSColor(red: 0.70, green: 0.68, blue: 0.66, alpha: 1.0))

    var body: some View {
        HStack(spacing: 4) {
            KeyCap(text: "⌥")
            KeyCap(text: "space")
        }
        .padding(.top, 8)
    }
}

struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundColor(Color(nsColor: NSColor(red: 0.50, green: 0.48, blue: 0.46, alpha: 1.0)))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(nsColor: NSColor(red: 0.92, green: 0.91, blue: 0.89, alpha: 1.0)))
            .cornerRadius(4)
    }
}

// MARK: - Transcription Card

struct TranscriptionCard: View {
    let text: String

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(accentColor.opacity(0.3))
                .frame(width: 24, height: 2)

            Text(text)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(Color(nsColor: NSColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1.0)))
                .lineSpacing(4)
                .textSelection(.enabled)

            HStack {
                Spacer()
                Label("copied", systemImage: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0)))
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
    }
}

// MARK: - History Preview

struct HistoryPreview: View {
    let entries: [Transcription]

    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("recent")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(lightGray)
                .tracking(1)
                .textCase(.uppercase)
                .padding(.horizontal, 32)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(entries.prefix(5)) { entry in
                        HistoryChip(entry: entry)
                    }
                }
                .padding(.horizontal, 32)
            }
        }
    }
}

struct HistoryChip: View {
    let entry: Transcription

    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.text, forType: .string)
        }) {
            Text(entry.text.prefix(30) + (entry.text.count > 30 ? "..." : ""))
                .font(.system(size: 12))
                .foregroundColor(Color(nsColor: NSColor(red: 0.35, green: 0.33, blue: 0.30, alpha: 1.0)))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.8))
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mode Toggle

struct ModeToggle: View {
    @AppStorage("transcriptionMode") private var mode: String = "vad"

    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Button(action: { mode = "vad" }) {
                    Text("on release")
                        .font(.system(size: 11, weight: mode == "vad" ? .medium : .regular))
                        .foregroundColor(mode == "vad" ? .white : lightGray)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(mode == "vad" ? accentColor : Color.clear)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)

                Button(action: { mode = "realtime" }) {
                    Text("while speaking")
                        .font(.system(size: 11, weight: mode == "realtime" ? .medium : .regular))
                        .foregroundColor(mode == "realtime" ? .white : lightGray)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(mode == "realtime" ? accentColor : Color.clear)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .padding(3)
            .background(Color(nsColor: NSColor(red: 0.92, green: 0.91, blue: 0.89, alpha: 1.0)))
            .cornerRadius(14)

            Text(mode == "vad" ? "types after you release the key" : "types as you speak")
                .font(.system(size: 10))
                .foregroundColor(lightGray)
        }
    }
}
