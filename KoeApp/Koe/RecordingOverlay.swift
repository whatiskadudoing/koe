import AppKit
import KoeDomain
import KoeUI
import SwiftUI

// MARK: - Overlay Window Controller

@MainActor
class RecordingOverlayController {
    static let shared = RecordingOverlayController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<OverlayContentView>?

    private init() {}

    func show() {
        if self.window == nil {
            self.createWindow()
        } else {
            // Reposition to current focused screen
            self.repositionWindow()
        }
        self.window?.orderFront(nil)
    }

    private func repositionWindow() {
        guard let window = window else { return }

        // Get the screen with the current mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen = screen else { return }

        let screenFrame = screen.frame
        let windowWidth: CGFloat = 112
        let windowHeight: CGFloat = 112
        let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        let y = screenFrame.origin.y + 100

        window.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
    }

    func hide() {
        self.window?.orderOut(nil)
    }

    func updateFromService(audioLevel: Float, state: RecordingState) {
        RecordingOverlayViewModel.shared.audioLevel = audioLevel
        RecordingOverlayViewModel.shared.state = state

        if state.isBusy {
            self.show()
        } else {
            self.hide()
        }
    }

    private func createWindow() {
        // Get the screen with the current mouse cursor (focused screen)
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen = screen else { return }

        let screenFrame = screen.frame

        let windowWidth: CGFloat = 112
        let windowHeight: CGFloat = 112
        // Center horizontally, position near bottom of the focused screen
        let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        let y = screenFrame.origin.y + 100  // 100px from bottom of the screen

        let contentRect = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)

        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window?.level = .floating
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.hasShadow = true
        window?.ignoresMouseEvents = true
        window?.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        hostingView = NSHostingView(rootView: OverlayContentView())
        window?.contentView = hostingView
    }
}

// MARK: - View Model

@MainActor
class RecordingOverlayViewModel: ObservableObject {
    static let shared = RecordingOverlayViewModel()

    @Published var audioLevel: Float = 0.0
    @Published var state: RecordingState = .idle

    private init() {}
}

// MARK: - Simple Overlay View

struct OverlayContentView: View {
    @ObservedObject private var viewModel = RecordingOverlayViewModel.shared

    // Dark neutral background
    private let backgroundColor = Color(nsColor: NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0))
    private let circleSize: CGFloat = 56

    var body: some View {
        ZStack {
            // Animated ring (user-selected style)
            AnimatedRing(
                isActive: viewModel.state != .idle,
                audioLevel: viewModel.state == .recording ? viewModel.audioLevel : 0,
                color: stateColor,
                style: AppState.shared.currentRingAnimationStyle
            )
            .frame(width: circleSize + 48, height: circleSize + 48)

            // Dark circle background
            Circle()
                .fill(backgroundColor)
                .frame(width: circleSize, height: circleSize)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 2)

            // Stage icon
            Image(systemName: stageIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(stateColor)
        }
        .frame(width: circleSize + 56, height: circleSize + 56)
    }

    /// Map recording state to pipeline stage to get the icon
    private var currentStage: PipelineStageInfo {
        switch viewModel.state {
        case .idle:
            return .hotkeyTrigger
        case .recording:
            return .recorder
        case .transcribing:
            // Show the icon of the active transcription engine
            return activeTranscriptionStage
        case .refining:
            return .improve
        }
    }

    /// Get the active transcription engine stage
    private var activeTranscriptionStage: PipelineStageInfo {
        let appState = AppState.shared
        if appState.isWhisperKitBalancedEnabled {
            return .transcribeWhisperKitBalanced
        } else if appState.isWhisperKitAccurateEnabled {
            return .transcribeWhisperKitAccurate
        } else {
            return .transcribeApple
        }
    }

    private var stageIcon: String {
        currentStage.icon
    }

    private var stateColor: Color {
        KoeColors.color(for: viewModel.state)
    }
}

// MARK: - Processing Indicator (Waveform Progress)

struct ProcessingIndicator: View {
    let state: RecordingState

    var body: some View {
        WaveformProgress(state: state)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
    }
}

// MARK: - Waveform Progress Animation

struct WaveformProgress: View {
    let state: RecordingState
    private let barCount = 20

    private var stateColor: Color {
        KoeColors.color(for: state)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.04)) { timeline in
            Canvas { context, size in
                let barWidth: CGFloat = 3
                let gap: CGFloat = 3.5
                let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
                let startX = (size.width - totalWidth) / 2
                let maxHeight = size.height * 0.85
                let centerY = size.height / 2

                let time = timeline.date.timeIntervalSinceReferenceDate

                // Progress sweeps from left to right over ~3 seconds, then repeats
                let cycleTime = 2.5
                let progress = (time.truncatingRemainder(dividingBy: cycleTime)) / cycleTime

                for i in 0..<barCount {
                    let x = startX + CGFloat(i) * (barWidth + gap)
                    let barProgress = CGFloat(i) / CGFloat(barCount - 1)

                    // Create a "frozen waveform" pattern - different heights for each bar
                    // This simulates a recorded audio waveform
                    let seed = Double(i) * 1.618  // Golden ratio for nice distribution
                    let baseHeight = 0.3 + 0.5 * abs(sin(seed * 2.1)) * abs(cos(seed * 0.7))

                    // Add subtle animation to processed bars
                    let isProcessed = barProgress < progress
                    var heightRatio = baseHeight

                    if isProcessed {
                        // Processed bars have subtle movement
                        let wave = sin(time * 4.0 + Double(i) * 0.3) * 0.08
                        heightRatio += wave
                    }

                    // Center emphasis
                    let center = CGFloat(barCount - 1) / 2
                    let dist = abs(CGFloat(i) - center) / center
                    heightRatio *= (1.0 - dist * 0.3)

                    heightRatio = min(1.0, max(0.15, heightRatio))
                    let barHeight = maxHeight * CGFloat(heightRatio)

                    let rect = CGRect(
                        x: x,
                        y: centerY - barHeight / 2,
                        width: barWidth,
                        height: barHeight
                    )

                    let path = RoundedRectangle(cornerRadius: 1.5)
                        .path(in: rect)

                    // Color: state color for processed, dim gray for unprocessed
                    if isProcessed {
                        // Glow effect at the leading edge
                        let edgeDist = abs(barProgress - progress) * CGFloat(barCount)
                        let glowIntensity = max(0, 1.0 - edgeDist / 2.0)
                        let brightness = 0.9 + glowIntensity * 0.1
                        context.fill(path, with: .color(stateColor.opacity(brightness)))
                    } else {
                        context.fill(path, with: .color(Color.white.opacity(0.25)))
                    }
                }
            }
        }
    }
}

// MARK: - Simple Waveform (Live Recording)

struct SimpleWaveform: View {
    let audioLevel: Float
    let state: RecordingState

    private let barCount = 16

    private var stateColor: Color {
        KoeColors.color(for: state)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.03)) { timeline in
            Canvas { context, size in
                let barWidth: CGFloat = 4
                let gap: CGFloat = 4
                let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
                let startX = (size.width - totalWidth) / 2
                let maxHeight = size.height * 0.85
                let centerY = size.height / 2

                let time = timeline.date.timeIntervalSinceReferenceDate
                let audio = CGFloat(max(0.05, audioLevel))  // Minimum visible level

                for i in 0..<barCount {
                    let x = startX + CGFloat(i) * (barWidth + gap)

                    // Each bar has its own "personality" based on position
                    let phase = Double(i) * 0.5
                    let wave1 = sin(time * 6.0 + phase) * 0.3
                    let wave2 = sin(time * 9.0 + phase * 1.3) * 0.2

                    // Audio level directly affects amplitude - more responsive
                    var heightRatio = 0.12 + audio * 0.88 * (0.6 + CGFloat(wave1 + wave2))

                    // Center emphasis - bars in middle are taller
                    let center = CGFloat(barCount - 1) / 2
                    let dist = abs(CGFloat(i) - center) / center
                    heightRatio *= (1.0 - dist * 0.4)

                    // Add some randomness based on audio to feel more alive
                    let jitter = sin(time * 12.0 + Double(i) * 2.1) * Double(audio) * 0.15
                    heightRatio += CGFloat(jitter)

                    heightRatio = min(1.0, max(0.08, heightRatio))
                    let barHeight = maxHeight * heightRatio

                    let rect = CGRect(
                        x: x,
                        y: centerY - barHeight / 2,
                        width: barWidth,
                        height: barHeight
                    )

                    let path = RoundedRectangle(cornerRadius: 2)
                        .path(in: rect)

                    // Use state-based color (red for recording)
                    context.fill(path, with: .color(stateColor))
                }
            }
        }
    }
}
