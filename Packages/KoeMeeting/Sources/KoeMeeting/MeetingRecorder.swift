import Foundation
import AVFoundation
import KoeDomain
import KoeCore

/// Records meeting audio using Core Audio Taps (macOS 14.4+)
/// This is the primary recorder that captures system audio without requiring Screen Recording permission
public final class MeetingRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var isRecording = false
    private var startTime: Date?

    /// The underlying system audio recorder (requires macOS 14.4+)
    @available(macOS 14.4, *)
    private var _systemRecorder: SystemAudioRecorder? {
        get { _systemRecorderStorage as? SystemAudioRecorder }
        set { _systemRecorderStorage = newValue }
    }
    private var _systemRecorderStorage: Any?

    /// Audio level continuations for forwarding to UI
    private var audioLevelContinuations: [UUID: AsyncStream<Float>.Continuation] = [:]
    private var audioLevelTask: Task<Void, Never>?

    public init() {}

    deinit {
        audioLevelTask?.cancel()
    }

    // MARK: - Permissions

    /// Check if audio capture is available (macOS 14.4+ required)
    public static func hasAudioCaptureCapability() -> Bool {
        if #available(macOS 14.4, *) {
            return true
        }
        return false
    }

    /// Legacy: Check if screen recording permission is granted
    /// Note: With Core Audio Taps, we no longer need Screen Recording permission
    public static func hasScreenRecordingPermission() -> Bool {
        // Core Audio Taps doesn't require Screen Recording permission
        // But we keep this for backwards compatibility with the UI
        if #available(macOS 14.4, *) {
            return true  // Core Audio Taps available, no Screen Recording needed
        }
        return CGPreflightScreenCaptureAccess()
    }

    /// Legacy: Request screen recording permission
    /// Note: With Core Audio Taps, this is not needed
    public static func requestScreenRecordingPermission() {
        if #available(macOS 14.4, *) {
            // No permission needed for Core Audio Taps
            KoeLogger.meeting.info("Core Audio Taps available - no Screen Recording permission needed")
            return
        }
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Recording

    /// Start recording system audio to a file
    public func startRecording(to url: URL) async throws {
        lock.lock()
        guard !isRecording else {
            lock.unlock()
            throw MeetingError.alreadyRecording
        }
        lock.unlock()

        guard #available(macOS 14.4, *) else {
            KoeLogger.meeting.error("Core Audio Taps requires macOS 14.4 or later")
            throw MeetingError.audioDeviceNotFound
        }

        KoeLogger.meeting.info("Starting meeting recording using Core Audio Taps")

        // Create system recorder
        let recorder = SystemAudioRecorder()
        _systemRecorder = recorder

        // Start recording
        try await recorder.startRecording(to: url)

        lock.lock()
        isRecording = true
        startTime = Date()
        lock.unlock()

        // Forward audio levels from system recorder
        if #available(macOS 14.4, *) {
            startAudioLevelForwarding()
        }

        KoeLogger.meeting.info("Meeting recording started: \(url.lastPathComponent)")
    }

    /// Stop recording and return the duration
    public func stopRecording() async throws -> TimeInterval {
        lock.lock()
        guard isRecording else {
            lock.unlock()
            throw MeetingError.notRecording
        }
        lock.unlock()

        // Stop audio level forwarding
        audioLevelTask?.cancel()
        audioLevelTask = nil

        // Stop the system recorder
        let duration: TimeInterval
        if #available(macOS 14.4, *), let recorder = _systemRecorder {
            duration = try await recorder.stopRecording()
            _systemRecorder = nil
        } else {
            duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        }

        lock.lock()
        isRecording = false
        startTime = nil
        _systemRecorderStorage = nil
        lock.unlock()

        KoeLogger.meeting.info("Meeting recording stopped. Duration: \(String(format: "%.1f", duration))s")

        return duration
    }

    /// Stream of audio levels (0.0 - 1.0) for UI visualization
    public func audioLevelStream() -> AsyncStream<Float> {
        let id = UUID()
        return AsyncStream { [weak self] continuation in
            self?.lock.lock()
            self?.audioLevelContinuations[id] = continuation
            self?.lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.audioLevelContinuations.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    /// Current recording state
    public var isCurrentlyRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRecording
    }

    // MARK: - Private

    @available(macOS 14.4, *)
    private func startAudioLevelForwarding() {
        guard let recorder = _systemRecorder else { return }

        audioLevelTask = Task { [weak self] in
            for await level in recorder.audioLevelStream() {
                guard let self = self else { break }

                self.lock.lock()
                for continuation in self.audioLevelContinuations.values {
                    continuation.yield(level)
                }
                self.lock.unlock()
            }
        }
    }
}
