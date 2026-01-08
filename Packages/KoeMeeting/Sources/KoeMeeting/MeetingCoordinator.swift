import Foundation
import KoeDomain
import KoeCore
import KoeStorage

/// Coordinates meeting detection, recording, and storage
@Observable
@MainActor
public final class MeetingCoordinator {
    public static let shared = MeetingCoordinator()

    // MARK: - State

    /// Current meeting state
    public private(set) var meetingState: MeetingState = .idle

    /// All stored meetings
    public private(set) var meetings: [Meeting] = []

    /// Current audio level during recording
    public private(set) var audioLevel: Float = 0.0

    /// Whether auto-recording is enabled
    public var autoRecordMeetings: Bool {
        get { UserDefaults.standard.bool(forKey: "autoRecordMeetings") }
        set { UserDefaults.standard.set(newValue, forKey: "autoRecordMeetings") }
    }

    /// Whether monitoring is active
    public private(set) var isMonitoring: Bool = false

    // MARK: - Dependencies

    private let detector: MeetingDetector
    private let recorder: MeetingRecorder
    private let repository: FileBasedMeetingRepository

    private var detectionTask: Task<Void, Never>?
    private var audioLevelTask: Task<Void, Never>?

    /// Debounce: Timestamp of last recording attempt (to prevent rapid re-triggering)
    private var lastRecordingAttemptTime: Date?

    /// Debounce: Bundle ID of the meeting we last attempted to record
    private var lastRecordingAttemptBundleId: String?

    /// Cooldown period after a recording attempt (in seconds)
    private let recordingCooldownSeconds: TimeInterval = 30.0

    /// Whether detection is temporarily paused (due to dictation)
    private var isDetectionPaused: Bool = false

    // MARK: - Init

    public init(
        detector: MeetingDetector = MeetingDetector(),
        recorder: MeetingRecorder = MeetingRecorder(),
        repository: FileBasedMeetingRepository = FileBasedMeetingRepository()
    ) {
        self.detector = detector
        self.recorder = recorder
        self.repository = repository

        // Enable auto-record by default
        if !UserDefaults.standard.bool(forKey: "autoRecordMeetingsInitialized") {
            UserDefaults.standard.set(true, forKey: "autoRecordMeetings")
            UserDefaults.standard.set(true, forKey: "autoRecordMeetingsInitialized")
        }

        // Load existing meetings
        Task {
            await loadMeetings()
        }

        // Observe mode coordination notifications
        setupModeCoordinationObservers()
    }

    private func setupModeCoordinationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePauseDetection),
            name: NSNotification.Name("requestPauseMeetingDetection"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResumeDetection),
            name: NSNotification.Name("requestResumeMeetingDetection"),
            object: nil
        )
    }

    @objc private func handlePauseDetection() {
        Task { @MainActor in
            isDetectionPaused = true
            debugLog("Meeting detection PAUSED (dictation active)")
            KoeLogger.meeting.info("Meeting detection paused (dictation active)")
        }
    }

    @objc private func handleResumeDetection() {
        Task { @MainActor in
            isDetectionPaused = false
            debugLog("Meeting detection RESUMED")
            KoeLogger.meeting.info("Meeting detection resumed")
        }
    }

    // MARK: - Monitoring

    /// Start monitoring for meetings
    public func startMonitoring() async {
        guard !isMonitoring else { return }
        isMonitoring = true

        debugLog("MeetingCoordinator.startMonitoring() called")

        // IMPORTANT: Start listening for events BEFORE starting the detector
        // This prevents race conditions where events are emitted before listener is ready
        detectionTask = Task { [weak self] in
            guard let self = self else { return }
            debugLog("Started listening for meeting events...")

            for await event in self.detector.meetingEventStream() {
                await self.handleMeetingEvent(event)
            }
        }

        // Give the listener task a moment to start iterating
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        // Now start the detector
        detector.startMonitoring()

        KoeLogger.meeting.info("Meeting monitoring started")
    }

    /// Debug log helper that writes to a file
    private func debugLog(_ message: String) {
        let logPath = "/tmp/koe_meeting_debug.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data, attributes: nil)
            }
        }
    }

    /// Stop monitoring for meetings
    public func stopMonitoring() async {
        guard isMonitoring else { return }
        isMonitoring = false

        // Stop any active recording
        if meetingState.isRecording {
            try? await stopRecording()
        }

        detector.stopMonitoring()
        detectionTask?.cancel()
        detectionTask = nil

        KoeLogger.meeting.info("Meeting monitoring stopped")
    }

    // MARK: - Recording Control

    /// Manually start recording a meeting
    public func startRecording(appName: String, appBundleId: String) async throws {
        guard !meetingState.isRecording else {
            throw MeetingError.alreadyRecording
        }

        // Create meeting
        var meeting = Meeting(
            appName: appName,
            appBundleId: appBundleId
        )

        // Get audio file URL
        let audioURL = try repository.createAudioFileURL(for: meeting)
        meeting = Meeting(
            id: meeting.id,
            appName: meeting.appName,
            appBundleId: meeting.appBundleId,
            startTime: meeting.startTime,
            audioFilePath: repository.relativePath(for: audioURL)
        )

        // Start recording
        try await recorder.startRecording(to: audioURL)

        // Update state
        meetingState = .recording(meeting)

        // Save meeting (will be updated when recording stops)
        try await repository.save(meeting)
        await loadMeetings()

        // Start audio level monitoring
        startAudioLevelMonitoring()

        KoeLogger.meeting.info("Started recording meeting: \(appName)")
    }

    /// Stop the current recording
    public func stopRecording() async throws {
        guard case .recording(var meeting) = meetingState else {
            throw MeetingError.notRecording
        }

        // Stop recording
        let duration = try await recorder.stopRecording()

        // Update meeting with end time and duration
        meeting = Meeting(
            id: meeting.id,
            appName: meeting.appName,
            appBundleId: meeting.appBundleId,
            startTime: meeting.startTime,
            endTime: Date(),
            audioFilePath: meeting.audioFilePath,
            duration: duration,
            transcript: meeting.transcript
        )

        // Update in repository
        try await repository.update(meeting)
        await loadMeetings()

        // Tell detector this meeting is done (prevents re-triggering)
        detector.endMeeting(bundleId: meeting.appBundleId)

        // Reset state
        meetingState = .idle
        audioLevel = 0.0

        stopAudioLevelMonitoring()

        KoeLogger.meeting.info("Stopped recording meeting: \(meeting.appName), duration: \(String(format: "%.1f", duration))s")
    }

    // MARK: - Meeting Management

    /// Load all meetings from storage
    public func loadMeetings() async {
        do {
            meetings = try await repository.fetchAll()
        } catch {
            KoeLogger.meeting.error("Failed to load meetings", error: error)
            meetings = []
        }
    }

    /// Delete a meeting
    public func deleteMeeting(_ meeting: Meeting) async throws {
        try await repository.delete(id: meeting.id)
        await loadMeetings()
    }

    /// Get audio file URL for a meeting
    public func audioFileURL(for meeting: Meeting) -> URL? {
        repository.audioFileURL(for: meeting)
    }

    /// Transcribe a meeting (placeholder - will integrate with WhisperKit)
    public func transcribeMeeting(_ meeting: Meeting) async throws -> String {
        // This will be implemented to use WhisperKitTranscriber
        // For now, return a placeholder
        throw MeetingError.transcriptionFailed(underlying: NSError(domain: "KoeMeeting", code: -1, userInfo: [NSLocalizedDescriptionKey: "Transcription not yet implemented"]))
    }

    /// Update meeting with transcript
    public func updateMeetingTranscript(_ meeting: Meeting, transcript: String) async throws {
        var updated = meeting
        updated = Meeting(
            id: meeting.id,
            appName: meeting.appName,
            appBundleId: meeting.appBundleId,
            startTime: meeting.startTime,
            endTime: meeting.endTime,
            audioFilePath: meeting.audioFilePath,
            duration: meeting.duration,
            transcript: transcript
        )
        try await repository.update(updated)
        await loadMeetings()
    }

    // MARK: - Permissions

    /// Check if screen recording permission is granted
    public var hasScreenRecordingPermission: Bool {
        MeetingRecorder.hasScreenRecordingPermission()
    }

    /// Request screen recording permission
    public func requestScreenRecordingPermission() {
        MeetingRecorder.requestScreenRecordingPermission()
    }

    // MARK: - Private

    private func handleMeetingEvent(_ event: MeetingEvent) async {
        switch event {
        case .meetingStarted(let bundleId, let appName):
            debugLog("Received meeting started event: \(appName) (\(bundleId))")
            debugLog("autoRecordMeetings=\(autoRecordMeetings), isRecording=\(meetingState.isRecording), isDetectionPaused=\(isDetectionPaused)")

            // Skip if detection is paused (dictation is active)
            if isDetectionPaused {
                debugLog("Meeting detection PAUSED - ignoring: \(appName)")
                return
            }

            // Only auto-record if enabled and not already recording
            if autoRecordMeetings && !meetingState.isRecording {
                // Check debounce: skip if we recently attempted to record this same meeting
                if let lastTime = lastRecordingAttemptTime,
                   let lastBundleId = lastRecordingAttemptBundleId,
                   lastBundleId == bundleId {
                    let elapsed = Date().timeIntervalSince(lastTime)
                    if elapsed < recordingCooldownSeconds {
                        debugLog("Debounce: Skipping recording attempt for \(appName) - cooldown active (\(Int(recordingCooldownSeconds - elapsed))s remaining)")
                        return
                    }
                }

                // Record the attempt time and bundle ID for debouncing
                lastRecordingAttemptTime = Date()
                lastRecordingAttemptBundleId = bundleId

                debugLog("Auto-starting recording...")
                do {
                    try await startRecording(appName: appName, appBundleId: bundleId)
                    debugLog("Recording started successfully")

                    // Notify to switch to meetings tab
                    NotificationCenter.default.post(
                        name: NSNotification.Name("meetingDetectedSwitchTab"),
                        object: nil,
                        userInfo: ["appName": appName, "bundleId": bundleId]
                    )
                } catch {
                    debugLog("Failed to auto-start recording: \(error)")
                    KoeLogger.meeting.error("Failed to auto-start recording", error: error)
                }
            }

        case .meetingEnded(let bundleId):
            // Stop recording if this is the meeting we're recording
            // This only fires when the meeting app QUITS
            if case .recording(let meeting) = meetingState, meeting.appBundleId == bundleId {
                do {
                    try await stopRecording()

                    // Notify to switch back to dictation tab
                    NotificationCenter.default.post(
                        name: NSNotification.Name("meetingEndedSwitchTab"),
                        object: nil
                    )
                } catch {
                    KoeLogger.meeting.error("Failed to stop recording", error: error)
                }
            }

            // Clear debounce state when meeting ends
            if lastRecordingAttemptBundleId == bundleId {
                lastRecordingAttemptTime = nil
                lastRecordingAttemptBundleId = nil
            }
        }
    }

    private func startAudioLevelMonitoring() {
        audioLevelTask = Task { [weak self] in
            guard let self = self else { return }

            for await level in self.recorder.audioLevelStream() {
                await MainActor.run {
                    self.audioLevel = level
                }
            }
        }
    }

    private func stopAudioLevelMonitoring() {
        audioLevelTask?.cancel()
        audioLevelTask = nil
    }
}
