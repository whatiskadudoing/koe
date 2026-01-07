import SwiftUI
import KoeDomain

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(RecordingCoordinator.self) private var coordinator
    @State private var showWelcome = true

    var body: some View {
        ZStack {
            // Background - warm off-white (washi paper)
            Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))
                .ignoresSafeArea()

            if showWelcome {
                WelcomeView()
                    .transition(.opacity)
                    .zIndex(1)
            }

            VStack(spacing: 0) {
                // Settings button at top right
                HStack {
                    Spacer()
                    SettingsButton()
                }

                // Top spacing
                Spacer()
                    .frame(height: 20)

                // Main content area
                VStack(spacing: 32) {
                    // Mic button
                    MicButton(
                        state: appState.recordingState,
                        audioLevel: coordinator.audioLevel,
                        onTap: {
                            Task { @MainActor in
                                if appState.recordingState == .idle {
                                    let mode = TranscriptionMode(rawValue: appState.transcriptionMode) ?? .vad
                                    let langCode = appState.selectedLanguage
                                    let language = Language.all.first { $0.code == langCode } ?? .auto
                                    await coordinator.startRecording(mode: mode, language: language)
                                } else if appState.recordingState == .recording {
                                    let mode = TranscriptionMode(rawValue: appState.transcriptionMode) ?? .vad
                                    let langCode = appState.selectedLanguage
                                    let language = Language.all.first { $0.code == langCode } ?? .auto
                                    await coordinator.stopRecording(mode: mode, language: language)
                                }
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
        .onAppear {
            // Dismiss welcome screen after 2.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showWelcome = false
                }
            }
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @State private var animationPhase: CGFloat = 0

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    var body: some View {
        ZStack {
            // Background matching app
            Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Animated waveform logo
                LogoWaveform(phase: animationPhase)
                    .frame(width: 120, height: 60)

                // App name
                Text("koe")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundColor(accentColor)
                    .tracking(4)
            }
        }
        .onAppear {
            // Start continuous animation
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                animationPhase = .pi * 2
            }
        }
    }
}

// MARK: - Logo Waveform

struct LogoWaveform: View {
    let phase: CGFloat
    private let barCount = 9
    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(accentColor)
                    .frame(width: 6, height: barHeight(for: index))
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let minHeight: CGFloat = 12
        let maxHeight: CGFloat = 56
        let centerIndex = CGFloat(barCount - 1) / 2
        let distanceFromCenter = abs(CGFloat(index) - centerIndex) / centerIndex

        // Create wave pattern from center outward
        let baseHeight = maxHeight - (distanceFromCenter * (maxHeight - minHeight) * 0.6)
        let waveOffset = sin(phase + CGFloat(index) * 0.7) * 0.3 + 0.7

        return baseHeight * waveOffset
    }
}

// MARK: - Settings Button

struct SettingsButton: View {
    @State private var isHovered = false

    private let iconColor = Color(nsColor: NSColor(red: 0.50, green: 0.48, blue: 0.46, alpha: 1.0))
    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    var body: some View {
        Button(action: {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }) {
            Image(systemName: "gear")
                .font(.system(size: 14))
                .foregroundColor(isHovered ? accentColor : iconColor)
                .rotationEffect(.degrees(isHovered ? 45 : 0))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.top, 12)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Mic Button

struct MicButton: View {
    let state: RecordingState
    let audioLevel: Float
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

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
                    .shadow(color: .black.opacity(isHovered ? 0.12 : 0.08), radius: isHovered ? 24 : 20, x: 0, y: isHovered ? 10 : 8)

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
            .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.03 : 1.0))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .pressEvents(onPress: {
            withAnimation(.easeOut(duration: 0.1)) { isPressed = true }
        }, onRelease: {
            withAnimation(.easeOut(duration: 0.1)) { isPressed = false }
        })
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

    @State private var showCopied = false
    @State private var isHovered = false
    @State private var appeared = false

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

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

                Button(action: copyText) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(showCopied ? "copied!" : "copy")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(showCopied ? accentColor : (isHovered ? accentColor : lightGray))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isHovered ? accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 4)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        withAnimation(.easeOut(duration: 0.2)) {
            showCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.3)) {
                showCopied = false
            }
        }
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

    @State private var isHovered = false
    @State private var showCopied = false

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.text, forType: .string)
            withAnimation(.easeOut(duration: 0.2)) {
                showCopied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showCopied = false
                }
            }
        }) {
            HStack(spacing: 4) {
                if showCopied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(showCopied ? "copied" : String(entry.text.prefix(30)) + (entry.text.count > 30 ? "..." : ""))
                    .font(.system(size: 12))
                    .foregroundColor(showCopied ? accentColor : Color(nsColor: NSColor(red: 0.35, green: 0.33, blue: 0.30, alpha: 1.0)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.white : Color.white.opacity(0.8))
            .cornerRadius(16)
            .shadow(color: .black.opacity(isHovered ? 0.08 : 0), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
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
                ModeButton(
                    title: "on release",
                    isSelected: mode == "vad",
                    accentColor: accentColor,
                    lightGray: lightGray
                ) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        mode = "vad"
                    }
                }

                ModeButton(
                    title: "while speaking",
                    isSelected: mode == "realtime",
                    accentColor: accentColor,
                    lightGray: lightGray
                ) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        mode = "realtime"
                    }
                }
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

struct ModeButton: View {
    let title: String
    let isSelected: Bool
    let accentColor: Color
    let lightGray: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .white : (isHovered ? accentColor : lightGray))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? accentColor : (isHovered ? accentColor.opacity(0.1) : Color.clear))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Press Events Modifier

struct PressEventsModifier: ViewModifier {
    var onPress: () -> Void
    var onRelease: () -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress() }
                    .onEnded { _ in onRelease() }
            )
    }
}

extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressEventsModifier(onPress: onPress, onRelease: onRelease))
    }
}
