import AppKit
import KoeUI
import SwiftUI

// MARK: - Transcription Overlay Window Controller

@MainActor
class TranscriptionOverlayController {
    static let shared = TranscriptionOverlayController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<TranscriptionOverlayView>?
    private var initialCursorPosition: NSPoint?

    private init() {}

    func show() {
        // Capture cursor position when showing
        initialCursorPosition = NSEvent.mouseLocation

        if window == nil {
            createWindow()
        } else {
            repositionWindow()
        }
        window?.orderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
        initialCursorPosition = nil
        // Clear text when hiding
        TranscriptionOverlayViewModel.shared.confirmedText = ""
        TranscriptionOverlayViewModel.shared.hypothesisText = ""
    }

    func updateText(confirmed: String, hypothesis: String) {
        TranscriptionOverlayViewModel.shared.confirmedText = confirmed
        TranscriptionOverlayViewModel.shared.hypothesisText = hypothesis

        // Reposition to fit new content size
        if window?.isVisible == true {
            repositionWindow()
        }
    }

    private func repositionWindow() {
        guard let window = window,
              let cursorPos = initialCursorPosition else { return }

        // Find screen containing cursor
        let screen = NSScreen.screens.first { NSMouseInRect(cursorPos, $0.frame, false) } ?? NSScreen.main
        guard let screen = screen else { return }

        let screenFrame = screen.frame
        let contentSize = calculateContentSize()

        // Position below cursor with offset
        var x = cursorPos.x - contentSize.width / 2
        var y = cursorPos.y - contentSize.height - 24  // 24px below cursor

        // Keep on screen horizontally
        x = max(screenFrame.minX + 10, min(x, screenFrame.maxX - contentSize.width - 10))

        // Keep on screen vertically (if too low, show above cursor instead)
        if y < screenFrame.minY + 10 {
            y = cursorPos.y + 24  // Show above cursor
        }

        window.setFrame(
            NSRect(x: x, y: y, width: contentSize.width, height: contentSize.height),
            display: true
        )
    }

    private func calculateContentSize() -> CGSize {
        let viewModel = TranscriptionOverlayViewModel.shared
        let text = viewModel.confirmedText + viewModel.hypothesisText

        if text.isEmpty {
            return CGSize(width: 100, height: 44)
        }

        // Calculate text size with max width constraint
        let maxWidth: CGFloat = 400
        let font = NSFont.systemFont(ofSize: 14)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        let textRect = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth - 32, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )

        let width = min(max(textRect.width + 32, 100), maxWidth)
        let height = max(textRect.height + 24, 44)

        return CGSize(width: width, height: height)
    }

    private func createWindow() {
        guard let cursorPos = initialCursorPosition else { return }

        // Find screen containing cursor
        let screen = NSScreen.screens.first { NSMouseInRect(cursorPos, $0.frame, false) } ?? NSScreen.main
        guard let screen = screen else { return }

        let contentSize = calculateContentSize()

        // Position below cursor
        var x = cursorPos.x - contentSize.width / 2
        var y = cursorPos.y - contentSize.height - 24

        // Keep on screen
        let screenFrame = screen.frame
        x = max(screenFrame.minX + 10, min(x, screenFrame.maxX - contentSize.width - 10))
        if y < screenFrame.minY + 10 {
            y = cursorPos.y + 24
        }

        let contentRect = NSRect(x: x, y: y, width: contentSize.width, height: contentSize.height)

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

        hostingView = NSHostingView(rootView: TranscriptionOverlayView())
        window?.contentView = hostingView
    }
}

// MARK: - View Model

@MainActor
class TranscriptionOverlayViewModel: ObservableObject {
    static let shared = TranscriptionOverlayViewModel()

    @Published var confirmedText: String = ""
    @Published var hypothesisText: String = ""

    var hasText: Bool {
        !confirmedText.isEmpty || !hypothesisText.isEmpty
    }

    private init() {}
}

// MARK: - Overlay View

struct TranscriptionOverlayView: View {
    @ObservedObject private var viewModel = TranscriptionOverlayViewModel.shared

    // Dark neutral background matching RecordingOverlay
    private let backgroundColor = Color(nsColor: NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 0.95))
    private let confirmedColor = Color.white
    private let hypothesisColor = Color.white.opacity(0.5)

    var body: some View {
        Group {
            if viewModel.hasText {
                HStack(spacing: 0) {
                    // Confirmed text (solid white)
                    if !viewModel.confirmedText.isEmpty {
                        Text(viewModel.confirmedText)
                            .foregroundColor(confirmedColor)
                    }

                    // Hypothesis text (dimmed gray)
                    if !viewModel.hypothesisText.isEmpty {
                        Text(viewModel.hypothesisText)
                            .foregroundColor(hypothesisColor)
                    }
                }
                .font(.system(size: 14, weight: .regular))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(backgroundColor)
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
            } else {
                // Empty state - small indicator
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.6)))
                    Text("Listening...")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(backgroundColor)
                )
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Preview with text
        TranscriptionOverlayView()
            .onAppear {
                TranscriptionOverlayViewModel.shared.confirmedText = "Hello world, "
                TranscriptionOverlayViewModel.shared.hypothesisText = "this is a test"
            }
    }
    .padding(40)
    .background(Color.gray.opacity(0.3))
}
