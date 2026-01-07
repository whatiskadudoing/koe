import SwiftUI
import AppKit

// MARK: - Overlay Window Controller

class RecordingOverlayController {
    static let shared = RecordingOverlayController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<OverlayContentView>?

    private init() {}

    func show() {
        DispatchQueue.main.async {
            if self.window == nil {
                self.createWindow()
            } else {
                // Reposition to current focused screen
                self.repositionWindow()
            }
            self.window?.orderFront(nil)
        }
    }

    private func repositionWindow() {
        guard let window = window else { return }

        // Get the screen with the current mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen = screen else { return }

        let screenFrame = screen.frame
        let windowWidth: CGFloat = 200
        let windowHeight: CGFloat = 50
        let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        let y = screenFrame.origin.y + 100

        window.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
    }

    func hide() {
        DispatchQueue.main.async {
            self.window?.orderOut(nil)
        }
    }

    func updateFromService(audioLevel: Float, state: RecordingState) {
        DispatchQueue.main.async {
            RecordingOverlayViewModel.shared.audioLevel = audioLevel
            RecordingOverlayViewModel.shared.state = state

            if state == .recording || state == .processing {
                self.show()
            } else {
                self.hide()
            }
        }
    }

    private func createWindow() {
        // Get the screen with the current mouse cursor (focused screen)
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen = screen else { return }

        let screenFrame = screen.frame

        let windowWidth: CGFloat = 200
        let windowHeight: CGFloat = 50
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

class RecordingOverlayViewModel: ObservableObject {
    static let shared = RecordingOverlayViewModel()

    @Published var audioLevel: Float = 0.0
    @Published var state: RecordingState = .idle

    private init() {}
}

// MARK: - Simple Overlay View

struct OverlayContentView: View {
    @ObservedObject private var viewModel = RecordingOverlayViewModel.shared

    var body: some View {
        ZStack {
            // Dark rounded background
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.black.opacity(0.85))

            if viewModel.state == .processing {
                // Processing: show spinner + text
                ProcessingIndicator()
            } else {
                // Recording: show waveform
                SimpleWaveform(audioLevel: viewModel.audioLevel)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
        }
        .frame(width: 200, height: 50)
    }
}

// MARK: - Processing Indicator (Waveform Progress)

struct ProcessingIndicator: View {
    var body: some View {
        WaveformProgress()
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
    }
}

// MARK: - Waveform Progress Animation

struct WaveformProgress: View {
    private let barCount = 20

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

                    // Color: white for processed, dim gray for unprocessed
                    if isProcessed {
                        // Glow effect at the leading edge
                        let edgeDist = abs(barProgress - progress) * CGFloat(barCount)
                        let glowIntensity = max(0, 1.0 - edgeDist / 2.0)
                        let brightness = 0.9 + glowIntensity * 0.1
                        context.fill(path, with: .color(Color.white.opacity(brightness)))
                    } else {
                        context.fill(path, with: .color(Color.white.opacity(0.25)))
                    }
                }
            }
        }
    }
}

// MARK: - Simple White Waveform

struct SimpleWaveform: View {
    let audioLevel: Float

    private let barCount = 16

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

                    context.fill(path, with: .color(.white))
                }
            }
        }
    }
}
