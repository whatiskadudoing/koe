import SwiftUI
import KoeDomain
import KoeMeeting
import KoeRefinement
import KoePipeline
import KoeUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(RecordingCoordinator.self) private var coordinator
    @Environment(MeetingCoordinator.self) private var meetingCoordinator

    @State private var selectedTab: AppTab = .dictation

    /// Track if we auto-switched to meetings (to know if we should auto-return)
    @State private var didAutoSwitchToMeetings: Bool = false

    /// Selected history item for detail view
    @State private var selectedHistoryItem: Transcription?

    /// Selected pipeline stage for settings modal
    @State private var selectedPipelineStage: PipelineStageInfo?

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

            // Modal overlays at root level (to cover entire window)
            if selectedHistoryItem != nil {
                ModalOverlay(isPresented: Binding(
                    get: { selectedHistoryItem != nil },
                    set: { if !$0 { selectedHistoryItem = nil } }
                )) {
                    SettingsModal(
                        title: "Transcription Details",
                        icon: "text.bubble",
                        iconColor: KoeColors.accent,
                        onClose: { withAnimation { selectedHistoryItem = nil } }
                    ) {
                        if let item = selectedHistoryItem {
                            HistoryDetailContent(entry: item)
                        }
                    }
                }
                .zIndex(10)
            }

            if let stage = selectedPipelineStage, stage.isToggleable || stage.hasSettings {
                ModalOverlay(isPresented: Binding(
                    get: { selectedPipelineStage != nil },
                    set: { if !$0 { selectedPipelineStage = nil } }
                )) {
                    SettingsModal(
                        title: "\(stage.displayName) Settings",
                        icon: stage.icon,
                        iconColor: stage.color,
                        onClose: { withAnimation { selectedPipelineStage = nil } }
                    ) {
                        NodeSettingsContent(stage: stage)
                    }
                }
                .zIndex(10)
            }
        }
        .frame(minWidth: 380, minHeight: 520)
        .onAppear {
            setupTabSwitchObservers()
        }
    }

    // MARK: - Tab Switch Observers

    private func setupTabSwitchObservers() {
        // Observe meeting detected - switch to meetings tab
        NotificationCenter.default.addObserver(
            forName: .meetingDetectedSwitchTab,
            object: nil,
            queue: .main
        ) { _ in
            // Only auto-switch if we're on dictation and not recording
            if selectedTab == .dictation && appState.recordingState == .idle {
                withAnimation(.easeOut(duration: 0.3)) {
                    selectedTab = .meetings
                    didAutoSwitchToMeetings = true
                }
            }
        }

        // Observe meeting ended - return to dictation if we auto-switched
        NotificationCenter.default.addObserver(
            forName: .meetingEndedSwitchTab,
            object: nil,
            queue: .main
        ) { _ in
            if didAutoSwitchToMeetings {
                withAnimation(.easeOut(duration: 0.3)) {
                    selectedTab = .dictation
                    didAutoSwitchToMeetings = false
                }
            }
        }
    }

    // MARK: - Main UI

    private var mainUI: some View {
        VStack(spacing: 0) {
            // Top bar with tab toggle
            HStack {
                Spacer()

                // Tab toggle
                TabToggle(selectedTab: $selectedTab, onManualSwitch: handleManualTabSwitch)

                Spacer()
            }
            .padding(.top, 12)

            // Content based on selected tab
            switch selectedTab {
            case .dictation:
                dictationView
            case .meetings:
                MeetingsView()
            }
        }
    }

    /// Handle manual tab switch - clear auto-switch flag
    private func handleManualTabSwitch(_ tab: AppTab) {
        // If user manually switches away from meetings during auto-switch, clear the flag
        if tab == .dictation && didAutoSwitchToMeetings {
            didAutoSwitchToMeetings = false
            ModeManager.shared.userDidSwitchTab(to: "dictation")
        }
    }

    // MARK: - Dictation View

    private var dictationView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Center section - Mic button and controls
            VStack(spacing: 20) {
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

                // Pipeline visualization
                PipelineStripView(selectedStage: $selectedPipelineStage)

                // Current transcription (if any)
                if !appState.currentTranscription.isEmpty {
                    TranscriptionCard(text: appState.currentTranscription)
                        .frame(maxWidth: 340)
                }
            }
            .frame(maxWidth: 360)

            Spacer()

            // History section - at the bottom
            if !appState.transcriptionHistory.isEmpty {
                HistoryList(entries: appState.transcriptionHistory, selectedItem: $selectedHistoryItem)
                    .frame(maxHeight: 180)
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Tab Toggle

struct TabToggle: View {
    @Binding var selectedTab: ContentView.AppTab
    /// Binding to clear auto-switch flag when user manually switches
    var onManualSwitch: ((ContentView.AppTab) -> Void)?

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
                    onManualSwitch?(.dictation)
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
                    onManualSwitch?(.meetings)
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
    @State private var contentOpacity: Double = 0
    @State private var contentScale: Double = 0.95
    @State private var contentOffset: CGFloat = 20

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let circleSize: CGFloat = 100

    var body: some View {
        ZStack {
            // Background matching app
            Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Animated ring with Japanese character
                ZStack {
                    AnimatedRing(
                        isActive: true,
                        audioLevel: 0,
                        color: accentColor,
                        style: AppState.shared.currentRingAnimationStyle,
                        maxAmplitude: 16
                    )
                    .frame(width: circleSize + 50, height: circleSize + 50)

                    Circle()
                        .fill(Color.white)
                        .frame(width: circleSize, height: circleSize)
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)

                    Text("声")
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(accentColor)
                }

                // App name
                Text("koe")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundColor(accentColor)
                    .tracking(6)

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

            // Advance to next state after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeOut(duration: 0.6)) {
                    appState.advanceReadinessState()
                }
            }
        }
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
    private let containerSize: CGFloat = 160
    private let circleSize: CGFloat = 80

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

                // Animated ring
                AnimatedRing(
                    isActive: state != .idle,
                    audioLevel: state == .recording ? audioLevel : 0,
                    color: stateColor,
                    style: AppState.shared.currentRingAnimationStyle,
                    maxAmplitude: 18
                )
                .frame(width: circleSize + 60, height: circleSize + 60)

                // Main circle
                Circle()
                    .fill(backgroundColor)
                    .frame(width: circleSize, height: circleSize)
                    .shadow(color: .black.opacity(isHovered ? 0.15 : 0.10), radius: isHovered ? 16 : 12, x: 0, y: isHovered ? 6 : 4)

                // Inner content - icon
                Image(systemName: stageIcon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(iconColor)
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

    private var stageIcon: String {
        switch state {
        case .idle, .recording:
            return "mic.fill"
        case .transcribing:
            return "text.bubble"
        case .refining:
            return "sparkles"
        }
    }

    private var stateColor: Color {
        KoeColors.color(for: state)
    }

    private var iconColor: Color {
        state == .idle ? accentColor : .white
    }

    private var backgroundColor: Color {
        switch state {
        case .idle:
            return Color.white
        case .recording, .transcribing, .refining:
            return stateColor.opacity(0.95)
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
        case .transcribing:
            return "transcribing..."
        case .refining:
            return "refining..."
        }
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
    @Binding var selectedItem: Transcription?

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

                Text("\(entries.count)")
                    .font(.system(size: 10))
                    .foregroundColor(lightGray.opacity(0.7))
            }
            .padding(.horizontal, 16)

            // Horizontal scrollable list
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(entries.prefix(20)) { entry in
                        HistoryCard(entry: entry, onTap: {
                            withAnimation(.easeOut(duration: 0.25)) {
                                selectedItem = entry
                            }
                        })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - History Card (Horizontal)

struct HistoryCard: View {
    let entry: Transcription
    var onTap: (() -> Void)?

    @State private var isHovered = false
    @State private var appeared = false

    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let textColor = Color(nsColor: NSColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0))

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 8) {
                // Transcription text preview
                Text(entry.text.prefix(60) + (entry.text.count > 60 ? "..." : ""))
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // Timestamp
                Text(formatTimestamp(entry.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(lightGray)
            }
            .padding(12)
            .frame(width: 160, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(isHovered ? 0.10 : 0.05), radius: isHovered ? 8 : 4, y: isHovered ? 3 : 2)
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

struct HistoryRow: View {
    let entry: Transcription
    var onTap: (() -> Void)?

    @State private var isHovered = false
    @State private var showCopied = false

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let textColor = Color(nsColor: NSColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0))

    var body: some View {
        Button(action: {
            if let onTap = onTap {
                onTap()
            } else {
                copyText()
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                // Transcription text - show more characters (up to 120)
                Text(entry.text.prefix(120) + (entry.text.count > 120 ? "..." : ""))
                    .font(.system(size: 13))
                    .foregroundColor(textColor)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Bottom row: timestamp and detail hint
                HStack {
                    // Timestamp
                    Text(formatTimestamp(entry.timestamp))
                        .font(.system(size: 11))
                        .foregroundColor(lightGray)

                    Spacer()

                    // Detail indicator
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
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .medium))
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

// MARK: - History Detail View

struct HistoryDetailView: View {
    let entry: Transcription
    let onClose: () -> Void

    @Environment(AppState.self) private var appState
    @State private var showCopied = false

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let textColor = Color(nsColor: NSColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1.0))
    private let backgroundColor = Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))

    // State colors
    private let transcribingColor = Color(nsColor: NSColor(red: 0.95, green: 0.75, blue: 0.20, alpha: 1.0))
    private let refiningColor = Color(nsColor: NSColor(red: 0.58, green: 0.35, blue: 0.78, alpha: 1.0))
    private let actionColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    /// Get the pipeline execution record for this transcription
    private var executionRecord: PipelineExecutionRecord? {
        guard let runId = entry.pipelineRunId else { return nil }
        return appState.pipelineExecutionHistory.first { $0.id == runId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(accentColor)
                }
                .buttonStyle(.plain)

                Text("Details")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(textColor)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .background(lightGray.opacity(0.3))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Timestamp and duration
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatFullTimestamp(entry.timestamp))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(textColor)

                        if entry.duration > 0 {
                            Text("Total: \(String(format: "%.1fs", entry.duration))")
                                .font(.system(size: 12))
                                .foregroundColor(lightGray)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    // Dynamic Pipeline steps
                    VStack(alignment: .leading, spacing: 12) {
                        // Transcription step (always present - not part of pipeline record)
                        PipelineStepCard(
                            stepName: "Transcription",
                            stepIcon: "waveform",
                            stepColor: transcribingColor,
                            inputDescription: "Audio input",
                            outputText: entry.originalText ?? entry.text,
                            status: .completed,
                            duration: nil  // Transcription duration not tracked separately
                        )

                        // Dynamic stages from pipeline execution (sorted by execution order)
                        if let record = executionRecord {
                            ForEach(record.elementMetrics.sorted(by: { $0.startTime < $1.startTime }), id: \.elementType) { metrics in
                                PipelineStepCard(
                                    stepName: displayName(for: metrics.elementType),
                                    stepIcon: icon(for: metrics.elementType),
                                    stepColor: color(for: metrics.elementType),
                                    inputDescription: inputDescription(for: metrics.elementType),
                                    outputText: outputText(for: metrics.elementType, record: record),
                                    isAction: isAction(for: metrics.elementType),
                                    actionDescription: actionDescription(for: metrics.elementType),
                                    status: metrics.status == .success ? .completed : .failed,
                                    duration: metrics.durationMs / 1000.0,
                                    settingsSummary: settingsSummary(for: metrics.elementType)
                                )
                            }
                        } else if entry.wasRefined {
                            // Fallback for old entries without pipeline record
                            PipelineStepCard(
                                stepName: "AI Refinement",
                                stepIcon: "sparkles",
                                stepColor: refiningColor,
                                inputDescription: entry.originalText ?? "Transcribed text",
                                outputText: entry.text,
                                status: .completed,
                                duration: entry.refinementSettings?.durationSeconds,
                                settingsSummary: entry.refinementSettings?.summary
                            )
                        }
                    }
                    .padding(.horizontal, 16)

                    // Final text section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Final Text")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(lightGray)

                        Text(entry.text)
                            .font(.system(size: 14))
                            .foregroundColor(textColor)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white)
                            .cornerRadius(8)
                    }
                    .padding(.horizontal, 16)

                    // Copy button
                    Button(action: copyText) {
                        HStack {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12))
                            Text(showCopied ? "Copied!" : "Copy Text")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(accentColor)
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(width: 300)
        .background(backgroundColor)
        .shadow(color: .black.opacity(0.15), radius: 20, x: -5, y: 0)
    }

    // MARK: - Helpers for dynamic pipeline display

    private func displayName(for typeId: String) -> String {
        switch typeId {
        case "text-improve": return "Improve"
        case "language-improvement": return "Language Improve"  // Legacy
        case "prompt-optimizer": return "Prompt Optimizer"  // Legacy
        case "auto-type": return "Auto Type"
        case "auto-enter": return "Auto Enter"
        default: return typeId.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    private func icon(for typeId: String) -> String {
        switch typeId {
        case "text-improve": return "sparkles"
        case "language-improvement": return "text.badge.checkmark"
        case "prompt-optimizer": return "sparkles"
        case "auto-type": return "keyboard"
        case "auto-enter": return "return"
        default: return "gearshape"
        }
    }

    private func color(for typeId: String) -> Color {
        switch typeId {
        case "text-improve": return refiningColor
        case "language-improvement": return refiningColor
        case "prompt-optimizer": return Color.orange
        case "auto-type": return actionColor
        case "auto-enter": return actionColor
        default: return lightGray
        }
    }

    private func inputDescription(for typeId: String) -> String {
        switch typeId {
        case "text-improve": return "Raw transcription"
        case "language-improvement": return "Raw transcription"
        case "prompt-optimizer": return "Improved text"
        case "auto-type": return executionRecord?.outputText ?? entry.text  // Show actual text that was typed
        case "auto-enter": return "Sends Enter key"
        default: return "Previous output"
        }
    }

    private func outputText(for typeId: String, record: PipelineExecutionRecord) -> String? {
        switch typeId {
        case "text-improve", "language-improvement", "prompt-optimizer":
            // For text transformations, show the output
            return record.outputText
        case "auto-type", "auto-enter":
            // Actions don't have output - they perform side effects
            return nil
        default:
            return nil
        }
    }

    /// Check if this element is an action (side effect) vs a transformation
    private func isAction(for typeId: String) -> Bool {
        switch typeId {
        case "auto-type", "auto-enter": return true
        default: return false
        }
    }

    private func actionDescription(for typeId: String) -> String? {
        switch typeId {
        case "auto-type": return "Typed to active window"
        case "auto-enter": return "Pressed Enter"
        default: return nil
        }
    }

    private func settingsSummary(for typeId: String) -> String? {
        guard let settings = entry.refinementSettings else { return nil }
        switch typeId {
        case "text-improve":
            var parts: [String] = []
            if settings.cleanup { parts.append("cleanup") }
            if settings.tone != "none" { parts.append(settings.tone) }
            if settings.promptMode { parts.append("prompt") }
            return parts.isEmpty ? nil : parts.joined(separator: " + ")
        case "language-improvement":
            var parts: [String] = []
            if settings.cleanup { parts.append("cleanup") }
            if settings.tone != "none" { parts.append(settings.tone) }
            return parts.isEmpty ? nil : parts.joined(separator: " + ")
        case "prompt-optimizer":
            return settings.promptMode ? "enabled" : nil
        default:
            return nil
        }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)

        withAnimation(.easeOut(duration: 0.2)) {
            showCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.3)) {
                showCopied = false
            }
        }
    }

    private func formatFullTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - History Detail Content (for modal)

/// Content view for history detail - used inside SettingsModal
struct HistoryDetailContent: View {
    let entry: Transcription

    @Environment(AppState.self) private var appState
    @State private var showCopied = false

    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let textColor = Color(nsColor: NSColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1.0))
    private let transcribingColor = Color(nsColor: NSColor(red: 0.95, green: 0.75, blue: 0.20, alpha: 1.0))
    private let refiningColor = Color(nsColor: NSColor(red: 0.58, green: 0.35, blue: 0.78, alpha: 1.0))
    private let actionColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    private var executionRecord: PipelineExecutionRecord? {
        guard let runId = entry.pipelineRunId else { return nil }
        return appState.pipelineExecutionHistory.first { $0.id == runId }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Timestamp and duration
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatFullTimestamp(entry.timestamp))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textColor)

                    if entry.duration > 0 {
                        Text("Total: \(String(format: "%.1fs", entry.duration))")
                            .font(.system(size: 12))
                            .foregroundColor(lightGray)
                    }
                }

                // Dynamic Pipeline steps
                VStack(alignment: .leading, spacing: 12) {
                    // Transcription step
                    PipelineStepCard(
                        stepName: "Transcription",
                        stepIcon: "waveform",
                        stepColor: transcribingColor,
                        inputDescription: "Audio input",
                        outputText: entry.originalText ?? entry.text,
                        status: .completed,
                        duration: nil
                    )

                    // Dynamic stages from pipeline execution
                    if let record = executionRecord {
                        ForEach(record.elementMetrics.sorted(by: { $0.startTime < $1.startTime }), id: \.elementType) { metrics in
                            PipelineStepCard(
                                stepName: displayName(for: metrics.elementType),
                                stepIcon: icon(for: metrics.elementType),
                                stepColor: color(for: metrics.elementType),
                                inputDescription: inputDescription(for: metrics.elementType),
                                outputText: outputText(for: metrics.elementType, record: record),
                                isAction: isAction(for: metrics.elementType),
                                actionDescription: actionDescription(for: metrics.elementType),
                                status: metrics.status == .success ? .completed : .failed,
                                duration: metrics.durationMs / 1000.0,
                                settingsSummary: settingsSummary(for: metrics.elementType)
                            )
                        }
                    } else if entry.wasRefined {
                        PipelineStepCard(
                            stepName: "AI Refinement",
                            stepIcon: "sparkles",
                            stepColor: refiningColor,
                            inputDescription: entry.originalText ?? "Transcribed text",
                            outputText: entry.text,
                            status: .completed,
                            duration: entry.refinementSettings?.durationSeconds,
                            settingsSummary: entry.refinementSettings?.summary
                        )
                    }
                }

                // Final text section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Final Text")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(lightGray)

                    Text(entry.text)
                        .font(.system(size: 14))
                        .foregroundColor(textColor)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(KoeColors.surface)
                        .cornerRadius(8)
                }

                // Copy button
                Button(action: copyText) {
                    HStack {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                        Text(showCopied ? "Copied!" : "Copy Text")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(KoeColors.accent)
                    .cornerRadius(20)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxHeight: 400)
    }

    // MARK: - Helpers

    private func displayName(for typeId: String) -> String {
        switch typeId {
        case "text-improve": return "Improve"
        case "language-improvement": return "Language Improve"
        case "prompt-optimizer": return "Prompt Optimizer"
        case "auto-type": return "Auto Type"
        case "auto-enter": return "Auto Enter"
        default: return typeId.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    private func icon(for typeId: String) -> String {
        switch typeId {
        case "text-improve": return "sparkles"
        case "language-improvement": return "text.badge.checkmark"
        case "prompt-optimizer": return "sparkles"
        case "auto-type": return "keyboard"
        case "auto-enter": return "return"
        default: return "gearshape"
        }
    }

    private func color(for typeId: String) -> Color {
        switch typeId {
        case "text-improve": return refiningColor
        case "language-improvement": return refiningColor
        case "prompt-optimizer": return Color.orange
        case "auto-type": return actionColor
        case "auto-enter": return actionColor
        default: return lightGray
        }
    }

    private func inputDescription(for typeId: String) -> String {
        switch typeId {
        case "text-improve", "language-improvement": return "Raw transcription"
        case "prompt-optimizer": return "Improved text"
        case "auto-type": return executionRecord?.outputText ?? entry.text
        case "auto-enter": return "Sends Enter key"
        default: return "Previous output"
        }
    }

    private func outputText(for typeId: String, record: PipelineExecutionRecord) -> String? {
        switch typeId {
        case "text-improve", "language-improvement", "prompt-optimizer":
            return record.outputText
        case "auto-type", "auto-enter":
            return nil
        default:
            return nil
        }
    }

    private func isAction(for typeId: String) -> Bool {
        switch typeId {
        case "auto-type", "auto-enter": return true
        default: return false
        }
    }

    private func actionDescription(for typeId: String) -> String? {
        switch typeId {
        case "auto-type": return "Typed to active window"
        case "auto-enter": return "Pressed Enter"
        default: return nil
        }
    }

    private func settingsSummary(for typeId: String) -> String? {
        guard let settings = entry.refinementSettings else { return nil }
        switch typeId {
        case "text-improve":
            var parts: [String] = []
            if settings.cleanup { parts.append("cleanup") }
            if settings.tone != "none" { parts.append(settings.tone) }
            if settings.promptMode { parts.append("prompt") }
            return parts.isEmpty ? nil : parts.joined(separator: " + ")
        case "language-improvement":
            var parts: [String] = []
            if settings.cleanup { parts.append("cleanup") }
            if settings.tone != "none" { parts.append(settings.tone) }
            return parts.isEmpty ? nil : parts.joined(separator: " + ")
        case "prompt-optimizer":
            return settings.promptMode ? "enabled" : nil
        default:
            return nil
        }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)

        withAnimation(.easeOut(duration: 0.2)) {
            showCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.3)) {
                showCopied = false
            }
        }
    }

    private func formatFullTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Pipeline Step Card

struct PipelineStepCard: View {
    let stepName: String
    let stepIcon: String
    let stepColor: Color
    let inputDescription: String
    let outputText: String?
    var isAction: Bool = false
    var actionDescription: String? = nil
    let status: StepStatus
    let duration: Double?
    var settingsSummary: String? = nil

    enum StepStatus {
        case completed
        case failed
        case skipped
    }

    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let textColor = Color(nsColor: NSColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1.0))

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Step header
            HStack {
                // Icon with color
                Image(systemName: stepIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(stepColor)
                    .frame(width: 24, height: 24)
                    .background(stepColor.opacity(0.15))
                    .cornerRadius(6)

                Text(stepName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(textColor)

                Spacer()

                // Status badge
                statusBadge
            }

            // Content based on status
            if status == .completed {
                VStack(alignment: .leading, spacing: 6) {
                    if isAction {
                        // Action display - show what action was performed
                        if let action = actionDescription {
                            HStack(spacing: 4) {
                                Text("Action:")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(lightGray)
                                Text(action)
                                    .font(.system(size: 11))
                                    .foregroundColor(textColor)
                            }
                        }
                    } else {
                        // Transformation display - show input/output
                        HStack(spacing: 4) {
                            Text("Input:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(lightGray)
                            Text(inputDescription)
                                .font(.system(size: 11))
                                .foregroundColor(lightGray)
                        }

                        // Output preview
                        if let output = outputText {
                            HStack(alignment: .top, spacing: 4) {
                                Text("Output:")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(lightGray)
                                Text(output.prefix(80) + (output.count > 80 ? "..." : ""))
                                    .font(.system(size: 11))
                                    .foregroundColor(textColor)
                                    .lineLimit(2)
                            }
                        }
                    }

                    // Duration
                    if let duration = duration {
                        Text(String(format: "%.1fs", duration))
                            .font(.system(size: 10))
                            .foregroundColor(lightGray.opacity(0.8))
                    }
                }
                .padding(.leading, 28)
            } else if status == .skipped {
                Text("Skipped")
                    .font(.system(size: 11))
                    .foregroundColor(lightGray)
                    .padding(.leading, 28)
            }

            // Settings summary (if present)
            if let settings = settingsSummary, status == .completed {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 9))
                    Text(settings)
                        .font(.system(size: 10))
                }
                .foregroundColor(stepColor.opacity(0.8))
                .padding(.leading, 28)
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(stepColor.opacity(status == .completed ? 0.3 : 0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .completed:
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                Text("Done")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.green)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.1))
            .cornerRadius(4)

        case .failed:
            HStack(spacing: 3) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                Text("Failed")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.red)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.1))
            .cornerRadius(4)

        case .skipped:
            Text("Skipped")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(lightGray)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(lightGray.opacity(0.1))
                .cornerRadius(4)
        }
    }
}

// MARK: - Refinement Toggle

struct RefinementToggle: View {
    @Environment(AppState.self) private var appState
    @State private var isWorking = false
    @State private var statusMessage: String = ""

    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let purpleColor = Color(nsColor: NSColor(red: 0.58, green: 0.35, blue: 0.78, alpha: 1.0))

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 6) {
            HStack(spacing: 6) {
                // AI icon or loading indicator
                if isWorking {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: appState.currentAITier.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(appState.isRefinementEnabled ? purpleColor : lightGray)
                }

                // Toggle
                Toggle("", isOn: Binding(
                    get: { appState.isRefinementEnabled },
                    set: { newValue in
                        handleToggle(newValue)
                    }
                ))
                    .toggleStyle(.switch)
                    .scaleEffect(0.65)
                    .disabled(isWorking)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(nsColor: NSColor(red: 0.92, green: 0.91, blue: 0.89, alpha: 1.0)))
            .cornerRadius(14)

            // Status text - show tier and mode when enabled
            Text(statusText)
                .font(.system(size: 10))
                .foregroundColor(statusColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(appState.isRefinementEnabled
            ? "AI: \(appState.currentAITier.displayName) • \(appState.currentRefinementMode.displayName)"
            : "Enable AI refinement")
    }

    private func handleToggle(_ newValue: Bool) {
        if newValue {
            // Turning ON - prepare the appropriate provider based on tier
            isWorking = true
            statusMessage = "Loading..."

            Task {
                let tier = appState.currentAITier

                if tier == .custom {
                    // Custom tier uses Ollama
                    await prepareOllama()
                } else {
                    // Fast/Smart/Best use local models via AIService
                    await prepareLocalAI(tier: tier)
                }
            }
        } else {
            // Turning OFF
            appState.isRefinementEnabled = false
            statusMessage = ""

            Task {
                // Shutdown AIService
                await AIService.shared.shutdown()

                // Also stop Ollama if it was running
                if appState.currentAITier == .custom {
                    OllamaManager.shared.stopServer()
                    await MainActor.run {
                        appState.isOllamaConnected = false
                    }
                }
            }
        }
    }

    @MainActor
    private func prepareLocalAI(tier: AITier) async {
        let aiService = AIService.shared

        NSLog("[AI Toggle] Starting prepareLocalAI for tier: %@", tier.displayName)

        statusMessage = "Preparing..."
        NSLog("[AI Toggle] Status set to Preparing")

        // Set tier if different, then always prepare
        NSLog("[AI Toggle] Current tier: %@, isReady: %d", aiService.currentTier.displayName, aiService.isReady)
        if aiService.currentTier != tier {
            NSLog("[AI Toggle] Calling setTier...")
            await aiService.setTier(tier)
        } else {
            // Same tier but not ready - just prepare
            NSLog("[AI Toggle] Calling prepare...")
            await aiService.prepare()
        }

        NSLog("[AI Toggle] After prepare - isReady: %d", aiService.isReady)

        isWorking = false
        if aiService.isReady {
            NSLog("[AI Toggle] SUCCESS - enabling refinement")
            appState.isRefinementEnabled = true
            statusMessage = ""
        } else {
            NSLog("[AI Toggle] FAILED - aiService not ready, status: %@", String(describing: aiService.status))
            statusMessage = "Setup failed"
            appState.errorMessage = "Failed to prepare AI model"
        }
    }

    private func prepareOllama() async {
        let manager = OllamaManager.shared

        // Check installation
        manager.checkInstallation()

        if !manager.isInstalled {
            await MainActor.run {
                isWorking = false
                statusMessage = ""
                manager.showInstallDialog()
            }
            return
        }

        await MainActor.run {
            statusMessage = "Starting Ollama..."
        }

        // Start server (will auto-pull model if needed)
        let modelName = appState.ollamaModel.isEmpty ? OllamaManager.defaultModel : appState.ollamaModel
        let success = await manager.startServer(modelName: modelName)

        await MainActor.run {
            isWorking = false
            if success {
                appState.isRefinementEnabled = true
                appState.isOllamaConnected = true
                appState.ollamaModel = modelName
                statusMessage = ""
            } else {
                if case .error(let msg) = manager.status {
                    appState.errorMessage = "AI setup failed: \(msg)"
                }
                statusMessage = "Setup failed"
            }
        }
    }

    private var statusText: String {
        if isWorking && !statusMessage.isEmpty {
            return statusMessage
        }
        if appState.isRefinementEnabled {
            return optionsSummary
        }
        return "AI off"
    }

    private var optionsSummary: String {
        var parts: [String] = []

        if appState.isCleanupEnabled {
            parts.append("cleanup")
        }

        if appState.isPromptImproverEnabled {
            parts.append("prompt")
        } else if appState.toneStyle == "formal" {
            parts.append("formal")
        } else if appState.toneStyle == "casual" {
            parts.append("casual")
        }

        return parts.isEmpty ? "AI on" : parts.joined(separator: "+")
    }

    private var statusColor: Color {
        if isWorking || appState.isRefinementEnabled {
            return purpleColor
        }
        return lightGray
    }
}

// MARK: - Refinement Options Panel

struct RefinementOptionsPanel: View {
    @Environment(AppState.self) private var appState

    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let purpleColor = Color(nsColor: NSColor(red: 0.58, green: 0.35, blue: 0.78, alpha: 1.0))
    private let chipBg = Color(nsColor: NSColor(red: 0.92, green: 0.91, blue: 0.89, alpha: 1.0))

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 8) {
            // Row 1: Clean Up + Prompt Mode toggles
            HStack(spacing: 8) {
                OptionChip(
                    label: "Clean Up",
                    icon: "wand.and.stars",
                    isSelected: $appState.isCleanupEnabled,
                    accentColor: purpleColor,
                    chipBg: chipBg
                )

                OptionChip(
                    label: "Prompt",
                    icon: "sparkles",
                    isSelected: $appState.isPromptImproverEnabled,
                    accentColor: Color.orange,
                    chipBg: chipBg
                )
            }

            // Row 2: Tone options (mutually exclusive, disabled when Prompt is on)
            HStack(spacing: 6) {
                Text("Tone:")
                    .font(.system(size: 10))
                    .foregroundColor(lightGray)

                ToneChip(label: "None", isSelected: appState.toneStyle == "none", isDisabled: appState.isPromptImproverEnabled, accentColor: accentColor, chipBg: chipBg) {
                    appState.toneStyle = "none"
                }

                ToneChip(label: "Formal", isSelected: appState.toneStyle == "formal", isDisabled: appState.isPromptImproverEnabled, accentColor: accentColor, chipBg: chipBg) {
                    appState.toneStyle = "formal"
                }

                ToneChip(label: "Casual", isSelected: appState.toneStyle == "casual", isDisabled: appState.isPromptImproverEnabled, accentColor: accentColor, chipBg: chipBg) {
                    appState.toneStyle = "casual"
                }
            }
            .opacity(appState.isPromptImproverEnabled ? 0.4 : 1.0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(chipBg.opacity(0.5))
        .cornerRadius(12)
    }
}

// MARK: - Option Chip (Toggle style)

private struct OptionChip: View {
    let label: String
    let icon: String
    @Binding var isSelected: Bool
    let accentColor: Color
    let chipBg: Color

    var body: some View {
        Button(action: { isSelected.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? accentColor : chipBg)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tone Chip (Radio style)

private struct ToneChip: View {
    let label: String
    let isSelected: Bool
    let isDisabled: Bool
    let accentColor: Color
    let chipBg: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? accentColor : chipBg)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

// MARK: - Auto Enter Toggle

struct AutoEnterToggle: View {
    @Environment(AppState.self) private var appState

    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 6) {
            HStack(spacing: 6) {
                // Return key icon
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(appState.isAutoEnterEnabled ? accentColor : lightGray)

                // Toggle
                Toggle("", isOn: $appState.isAutoEnterEnabled)
                    .toggleStyle(.switch)
                    .scaleEffect(0.65)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(nsColor: NSColor(red: 0.92, green: 0.91, blue: 0.89, alpha: 1.0)))
            .cornerRadius(14)

            // Status text
            Text(appState.isAutoEnterEnabled ? "auto enter" : "no enter")
                .font(.system(size: 10))
                .foregroundColor(lightGray)
        }
        .help("Automatically press Enter after inserting text")
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
