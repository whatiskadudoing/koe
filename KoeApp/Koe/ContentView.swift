import SwiftUI
import KoeDomain
import KoeMeeting

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(RecordingCoordinator.self) private var coordinator
    @Environment(MeetingCoordinator.self) private var meetingCoordinator

    @State private var selectedTab: AppTab = .dictation

    enum AppTab {
        case dictation
        case meetings
    }

    var body: some View {
        ZStack {
            // Background - warm off-white (washi paper)
            Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))
                .ignoresSafeArea()

            // State machine - show appropriate view based on readiness state
            switch appState.appReadinessState {
            case .welcome:
                WelcomeView()
                    .transition(.opacity)
                    .zIndex(1)

            case .needsPermissions:
                PermissionsView()
                    .transition(.opacity)
                    .zIndex(1)

            case .loading:
                LoadingView()
                    .transition(.opacity)
                    .zIndex(1)

            case .ready:
                mainUI
                    .transition(.opacity)
                    .zIndex(0)
            }
        }
        .frame(minWidth: 380, minHeight: 520)
    }

    // MARK: - Main UI

    private var mainUI: some View {
        VStack(spacing: 0) {
            // Top bar with settings and tab toggle
            HStack {
                Spacer()

                // Tab toggle
                TabToggle(selectedTab: $selectedTab)

                Spacer()

                SettingsButton()
            }
            .padding(.top, 4)

            // Content based on selected tab
            switch selectedTab {
            case .dictation:
                dictationView
            case .meetings:
                MeetingsView()
            }
        }
    }

    // MARK: - Dictation View

    private var dictationView: some View {
        VStack(spacing: 0) {
            // Top section - Mic button and controls
            VStack(spacing: 16) {
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

                // Status text and hotkey hint
                VStack(spacing: 8) {
                    StatusText(state: appState.recordingState)
                    HotkeyHint()
                }

                // Mode toggle
                ModeToggle()
            }
            .padding(.top, 8)
            .padding(.horizontal, 32)

            // Current transcription (if any)
            if !appState.currentTranscription.isEmpty {
                TranscriptionCard(text: appState.currentTranscription)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }

            // History section - vertical scrollable list
            if !appState.transcriptionHistory.isEmpty {
                HistoryList(entries: appState.transcriptionHistory)
                    .padding(.top, 16)
            } else {
                Spacer()
            }
        }
    }
}

// MARK: - Tab Toggle

struct TabToggle: View {
    @Binding var selectedTab: ContentView.AppTab

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

    var body: some View {
        HStack(spacing: 8) {
            // Dictation tab - waveform icon
            TabIconButton(
                icon: "waveform",
                isSelected: selectedTab == .dictation,
                selectedColor: accentColor,
                unselectedColor: lightGray
            ) {
                withAnimation(.easeOut(duration: 0.2)) {
                    selectedTab = .dictation
                }
            }

            // Meetings tab - video icon
            TabIconButton(
                icon: "video.fill",
                isSelected: selectedTab == .meetings,
                selectedColor: accentColor,
                unselectedColor: lightGray
            ) {
                withAnimation(.easeOut(duration: 0.2)) {
                    selectedTab = .meetings
                }
            }
        }
        .padding(4)
        .background(Color(nsColor: NSColor(red: 0.92, green: 0.91, blue: 0.89, alpha: 1.0)))
        .cornerRadius(24)
    }
}

struct TabIconButton: View {
    let icon: String
    let isSelected: Bool
    let selectedColor: Color
    let unselectedColor: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Selection indicator circle
                Circle()
                    .fill(isSelected ? selectedColor : Color.clear)
                    .frame(width: 36, height: 36)

                // Icon
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : (isHovered ? selectedColor : unselectedColor))
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered && !isSelected ? 1.08 : 1.0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @State private var animationPhase: CGFloat = 0
    @State private var contentOpacity: Double = 0
    @State private var contentScale: Double = 0.95
    @State private var contentOffset: CGFloat = 20
    @State private var animationTimer: Timer?

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    var body: some View {
        ZStack {
            // Background matching app
            Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                // Animated waveform logo
                LogoWaveform(phase: animationPhase)
                    .frame(width: 120, height: 60)

                // App name with Japanese character
                VStack(spacing: 12) {
                    Text("声")
                        .font(.system(size: 40, weight: .thin))
                        .foregroundColor(accentColor.opacity(0.7))

                    Text("koe")
                        .font(.system(size: 32, weight: .light, design: .rounded))
                        .foregroundColor(accentColor)
                        .tracking(6)
                }

                Spacer()
            }
            .opacity(contentOpacity)
            .scaleEffect(contentScale)
            .offset(y: contentOffset)
        }
        .onAppear {
            // Fade in content with slight scale
            withAnimation(.easeOut(duration: 0.7)) {
                contentOpacity = 1
                contentScale = 1
                contentOffset = 0
            }

            // Start continuous waveform animation using Timer for reliable animation
            startWaveformAnimation()

            // Advance to next state after 12 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                withAnimation(.easeOut(duration: 0.6)) {
                    appState.advanceReadinessState()
                }
            }
        }
        .onDisappear {
            stopWaveformAnimation()
        }
    }

    private func startWaveformAnimation() {
        // Use Timer for reliable animation at 30fps
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            animationPhase += 0.12
            if animationPhase > .pi * 2 {
                animationPhase = 0
            }
        }
    }

    private func stopWaveformAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
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
    @Environment(AppState.self) private var appState
    let state: RecordingState
    let audioLevel: Float
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    // Japanese indigo accent
    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    // Fixed container size to prevent layout shifts
    private let containerSize: CGFloat = 180

    var body: some View {
        Button(action: {
            // Prevent recording before app is fully ready
            guard appState.appReadinessState == .ready else {
                NSSound(named: "Basso")?.play()
                return
            }
            onTap()
        }) {
            ZStack {
                // Fixed size container to prevent layout shifts
                Color.clear
                    .frame(width: containerSize, height: containerSize)

                // Outer ring - audio visualization (always present but invisible when not recording)
                Circle()
                    .stroke(state == .recording ? accentColor.opacity(0.3) : Color.clear, lineWidth: 2)
                    .frame(width: 140 + CGFloat(state == .recording ? audioLevel : 0) * 40,
                           height: 140 + CGFloat(state == .recording ? audioLevel : 0) * 40)
                    .animation(.easeOut(duration: 0.1), value: audioLevel)

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
            return accentColor.opacity(0.95)
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

// MARK: - History List

struct HistoryList: View {
    let entries: [Transcription]

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Recent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(lightGray)
                    .tracking(0.5)

                Spacer()

                Text("\(entries.count) items")
                    .font(.system(size: 11))
                    .foregroundColor(lightGray.opacity(0.7))
            }
            .padding(.horizontal, 24)

            // Scrollable list
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(entries.prefix(20)) { entry in
                        HistoryRow(entry: entry)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }
}

struct HistoryRow: View {
    let entry: Transcription

    @State private var isHovered = false
    @State private var showCopied = false

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let textColor = Color(nsColor: NSColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0))

    var body: some View {
        Button(action: copyText) {
            VStack(alignment: .leading, spacing: 8) {
                // Transcription text - show more characters (up to 120)
                Text(entry.text.prefix(120) + (entry.text.count > 120 ? "..." : ""))
                    .font(.system(size: 13))
                    .foregroundColor(textColor)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Bottom row: timestamp and copy indicator
                HStack {
                    // Timestamp
                    Text(formatTimestamp(entry.timestamp))
                        .font(.system(size: 11))
                        .foregroundColor(lightGray)

                    Spacer()

                    // Copy indicator
                    if showCopied {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Copied")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(accentColor)
                        .transition(.scale.combined(with: .opacity))
                    } else if isHovered {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                            Text("Click to copy")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(lightGray)
                        .transition(.opacity)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 8 : 4, y: isHovered ? 2 : 1)
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

    private func copyText() {
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
    }

    private func formatTimestamp(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
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
