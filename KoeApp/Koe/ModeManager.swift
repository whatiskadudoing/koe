import Foundation
import os.log

/// Coordinates mutually exclusive modes between Dictation and Meeting recording
@Observable
@MainActor
public final class ModeManager {
    public static let shared = ModeManager()

    private let logger = Logger(subsystem: "com.koe.voice", category: "ModeManager")

    public enum ActiveMode: Equatable {
        case none
        case dictation
        case meeting
    }

    /// Current active recording mode
    public private(set) var activeMode: ActiveMode = .none

    /// Whether meeting detection is currently paused (due to active dictation)
    public private(set) var isMeetingDetectionPaused: Bool = false

    /// Whether we auto-switched to meetings tab (to know if we should auto-return)
    public private(set) var didAutoSwitchToMeetings: Bool = false

    private init() {
        setupObservers()
    }

    private func setupObservers() {
        // Observe dictation state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDictationStarted),
            name: NSNotification.Name("dictationStarted"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDictationEnded),
            name: NSNotification.Name("dictationEnded"),
            object: nil
        )

        // Observe meeting state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMeetingDetected),
            name: NSNotification.Name("meetingDetectedSwitchTab"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMeetingEnded),
            name: NSNotification.Name("meetingEndedSwitchTab"),
            object: nil
        )
    }

    @objc private func handleDictationStarted() {
        guard activeMode == .none else {
            logger.info(
                "ModeManager: Dictation start blocked - already in mode: \(String(describing: self.activeMode))")
            return
        }
        activeMode = .dictation
        logger.info("ModeManager: Dictation started, pausing meeting detection")

        // Pause meeting detection while dictating
        isMeetingDetectionPaused = true
        NotificationCenter.default.post(name: NSNotification.Name("requestPauseMeetingDetection"), object: nil)
    }

    @objc private func handleDictationEnded() {
        guard activeMode == .dictation else { return }
        activeMode = .none
        logger.info("ModeManager: Dictation ended, resuming meeting detection")

        // Resume meeting detection
        isMeetingDetectionPaused = false
        NotificationCenter.default.post(name: NSNotification.Name("requestResumeMeetingDetection"), object: nil)
    }

    @objc private func handleMeetingDetected(_ notification: Notification) {
        guard activeMode == .none else {
            logger.info(
                "ModeManager: Meeting detection ignored - already in mode: \(String(describing: self.activeMode))")
            return
        }
        activeMode = .meeting
        didAutoSwitchToMeetings = true
        logger.info("ModeManager: Meeting detected, switching to meetings mode")
    }

    @objc private func handleMeetingEnded() {
        guard activeMode == .meeting else { return }
        activeMode = .none
        logger.info("ModeManager: Meeting ended")

        // Only post return notification if we auto-switched
        if didAutoSwitchToMeetings {
            didAutoSwitchToMeetings = false
            // The ContentView will handle the actual tab switch
        }
    }

    /// Called when user manually switches tabs
    public func userDidSwitchTab(to tab: String) {
        // If user manually switches during a meeting, clear auto-switch flag
        if tab == "dictation" && activeMode == .meeting {
            didAutoSwitchToMeetings = false
            logger.info("ModeManager: User manually switched to dictation during meeting")
        }
    }
}
