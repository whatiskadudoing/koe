import AppKit
import CoreAudio
import CoreGraphics
import Foundation
import KoeCore
import KoeDomain

/// Event emitted when meeting status changes
public enum MeetingEvent: Sendable {
    case meetingStarted(appBundleId: String, appName: String)
    case meetingEnded(appBundleId: String)
}

/// Detection mode used by the detector
public enum DetectionMode: Sendable {
    case microphoneUsage  // Primary: CoreAudio process monitoring (like Krisp)
    case windowTitle  // Fallback: window title detection (requires Screen Recording)
    case processMonitoring  // Last resort: just check if meeting apps are running
}

/// Window title patterns that indicate an active meeting
private struct MeetingWindowPattern {
    let appName: String
    let bundleId: String
    let patterns: [String]
}

/// App display name mapping
private struct AppInfo {
    let bundleId: String
    let displayName: String
}

/// Detects when meeting apps are active
/// Uses microphone usage detection (same approach as Krisp) as primary method
public final class MeetingDetector: @unchecked Sendable {
    private var isMonitoring = false
    private var continuations: [UUID: AsyncStream<MeetingEvent>.Continuation] = [:]
    private let lock = NSLock()

    /// Currently active meetings (keyed by bundle ID)
    private var activeMeetings: Set<String> = []

    /// Polling timer for fallback detection
    private var pollingTimer: Timer?

    /// Audio process monitor (primary detection method)
    private let audioMonitor = AudioProcessMonitor()

    /// Current detection mode
    private var detectionMode: DetectionMode = .microphoneUsage

    /// App info for display names
    private let appInfoMap: [String: String] = [
        // Native apps
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.slack.Slack": "Slack",
        "com.hnc.Discord": "Discord",
        "com.skype.skype": "Skype",
        "com.loom.desktop": "Loom",
        "com.apple.FaceTime": "FaceTime",
        // Browsers - main apps
        "company.thebrowser.Browser": "Arc",
        "com.google.Chrome": "Chrome",
        "com.apple.Safari": "Safari",
        "org.mozilla.firefox": "Firefox",
        "com.microsoft.edgemac": "Edge",
        "com.brave.Browser": "Brave",
        // Browser helpers (fallback if not mapped)
        "company.thebrowser.browser.helper": "Arc",
        "company.thebrowser.browser.helper.renderer": "Arc",
        "com.google.Chrome.helper": "Chrome",
        "com.google.Chrome.helper.renderer": "Chrome",
        "com.apple.WebKit.WebContent": "Safari",
        "org.mozilla.firefox.helper": "Firefox",
        "com.microsoft.edgemac.helper": "Edge",
        "com.brave.Browser.helper": "Brave",
    ]

    /// Window patterns for title-based detection (fallback)
    private let meetingPatterns: [MeetingWindowPattern] = [
        // Browsers - Google Meet shows "Title - Google Meet" or contains "meet.google.com"
        MeetingWindowPattern(
            appName: "Arc", bundleId: "company.thebrowser.Browser",
            patterns: ["Google Meet", "meet.google.com", "Zoom", "teams.microsoft.com"]),
        MeetingWindowPattern(
            appName: "Google Chrome", bundleId: "com.google.Chrome",
            patterns: ["Google Meet", "meet.google.com", "Zoom", "teams.microsoft.com"]),
        MeetingWindowPattern(
            appName: "Safari", bundleId: "com.apple.Safari",
            patterns: ["Google Meet", "meet.google.com", "Zoom", "teams.microsoft.com"]),
        MeetingWindowPattern(
            appName: "Firefox", bundleId: "org.mozilla.firefox",
            patterns: ["Google Meet", "meet.google.com", "Zoom", "teams.microsoft.com"]),
        MeetingWindowPattern(
            appName: "Microsoft Edge", bundleId: "com.microsoft.edgemac",
            patterns: ["Google Meet", "meet.google.com", "Zoom", "teams.microsoft.com"]),
        // Native apps
        MeetingWindowPattern(appName: "zoom.us", bundleId: "us.zoom.xos", patterns: ["Zoom Meeting", "Zoom Webinar"]),
        MeetingWindowPattern(
            appName: "Microsoft Teams", bundleId: "com.microsoft.teams2", patterns: ["(Meeting)", "Call with"]),
        MeetingWindowPattern(appName: "Slack", bundleId: "com.slack.Slack", patterns: ["Huddle"]),
        MeetingWindowPattern(appName: "Webex", bundleId: "com.cisco.webexmeetingsapp", patterns: ["Meeting"]),
        MeetingWindowPattern(appName: "Discord", bundleId: "com.hnc.Discord", patterns: ["Voice Connected"]),
    ]

    public init() {}

    deinit {
        stopMonitoring()
    }

    /// Current detection mode being used
    public var currentDetectionMode: DetectionMode {
        return detectionMode
    }

    /// Debug log helper
    private func debugLog(_ message: String) {
        let logPath = "/tmp/koe_meeting_debug.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] [Detector] \(message)\n"
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

    /// Start monitoring for meetings
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        debugLog("Meeting detector starting...")

        // Setup microphone usage monitoring (secondary method)
        setupMicrophoneMonitoring()

        // Start polling for meeting detection (check every second)
        // Delay initial check slightly to allow event listeners to set up
        DispatchQueue.main.async { [weak self] in
            self?.pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                // PRIMARY: Check audio processes (like Krisp)
                self?.checkAudioProcesses()
                // SECONDARY: Window title detection (if Screen Recording permission available)
                self?.supplementaryWindowCheck()
            }
            self?.debugLog("Meeting detection started (audio process + window title polling every 1s)")
        }

        KoeLogger.meeting.info("Meeting detector started (audio process + window title detection)")
    }

    /// Stop monitoring
    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        audioMonitor.stopMonitoring()
        pollingTimer?.invalidate()
        pollingTimer = nil

        lock.lock()
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
        activeMeetings.removeAll()
        lock.unlock()

        KoeLogger.meeting.info("Meeting detector stopped")
    }

    /// Stream of meeting detection events
    public func meetingEventStream() -> AsyncStream<MeetingEvent> {
        let id = UUID()
        return AsyncStream { [weak self] continuation in
            self?.lock.lock()
            self?.continuations[id] = continuation
            self?.lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.continuations.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    /// Manually mark a meeting as ended
    /// This clears both tracking sets so the same app can be detected again
    public func endMeeting(bundleId: String) {
        lock.lock()
        if activeMeetings.contains(bundleId) {
            activeMeetings.remove(bundleId)
            // IMPORTANT: Also remove from audioConnectedMeetings so the app can be re-detected
            audioConnectedMeetings.remove(bundleId)
            windowDetectedMeetings.remove(bundleId)
            KoeLogger.meeting.info("Meeting manually ended for \(bundleId)")
        }
        lock.unlock()
    }

    // MARK: - Private - Audio Process Detection (Primary - like Krisp)

    /// Tracks meeting apps that are connected to audio (detected via CoreAudio)
    private var audioConnectedMeetings: Set<String> = []

    /// Check for meeting apps registered as audio processes
    /// This is the primary detection method - similar to how Krisp detects apps
    private func checkAudioProcesses() {
        let connectedApps = Set(audioMonitor.getMeetingAppsWithAudioConnection())

        lock.lock()
        defer { lock.unlock() }

        // Detect new meeting apps
        let newApps = connectedApps.subtracting(audioConnectedMeetings)
        var eventsToEmit: [MeetingEvent] = []

        for bundleId in newApps {
            audioConnectedMeetings.insert(bundleId)

            if !activeMeetings.contains(bundleId) {
                activeMeetings.insert(bundleId)
                let appName = getAppDisplayName(for: bundleId)
                eventsToEmit.append(.meetingStarted(appBundleId: bundleId, appName: appName))
                debugLog("🟢 MEETING DETECTED (audio process): \(appName) (\(bundleId))")
                KoeLogger.meeting.info("Meeting detected (audio process): \(appName) (\(bundleId))")
            }
        }

        // Detect ended meetings (apps no longer in audio process list)
        let endedApps = audioConnectedMeetings.subtracting(connectedApps)
        for bundleId in endedApps {
            audioConnectedMeetings.remove(bundleId)

            if activeMeetings.contains(bundleId) {
                activeMeetings.remove(bundleId)
                eventsToEmit.append(.meetingEnded(appBundleId: bundleId))
                let appName = getAppDisplayName(for: bundleId)
                debugLog("🔴 MEETING ENDED (audio process): \(appName) (\(bundleId))")
                KoeLogger.meeting.info("Meeting ended (audio process): \(appName) (\(bundleId))")
            }
        }

        // Copy continuations and emit events outside the main logic
        let continuationsCopy = Array(continuations.values)
        for event in eventsToEmit {
            for continuation in continuationsCopy {
                continuation.yield(event)
            }
        }
    }

    // MARK: - Private - Microphone Monitoring (Secondary)

    private func setupMicrophoneMonitoring() {
        audioMonitor.onMicrophoneUsageChange { [weak self] (rawBundleId: String, started: Bool) in
            guard let self = self else { return }

            // Map helper bundle ID to parent bundle ID
            let bundleId = self.getParentBundleId(for: rawBundleId)

            self.lock.lock()

            var eventToEmit: MeetingEvent?

            if started {
                // App started using microphone
                if !self.activeMeetings.contains(bundleId) {
                    self.activeMeetings.insert(bundleId)
                    let appName = self.getAppDisplayName(for: bundleId)
                    eventToEmit = .meetingStarted(appBundleId: bundleId, appName: appName)
                    KoeLogger.meeting.info("Meeting detected (microphone): \(appName) (\(bundleId))")
                }
            } else {
                // App stopped using microphone
                if self.activeMeetings.contains(bundleId) {
                    self.activeMeetings.remove(bundleId)
                    eventToEmit = .meetingEnded(appBundleId: bundleId)
                    let appName = self.getAppDisplayName(for: bundleId)
                    KoeLogger.meeting.info("Meeting ended (microphone stopped): \(appName) (\(bundleId))")
                }
            }

            // Copy continuations and unlock before emitting
            let continuationsCopy = Array(self.continuations.values)
            self.lock.unlock()

            if let event = eventToEmit {
                for continuation in continuationsCopy {
                    continuation.yield(event)
                }
            }
        }

        audioMonitor.startMonitoring()
    }

    /// Map helper bundle IDs to their parent app bundle IDs
    private func getParentBundleId(for bundleId: String) -> String {
        // Arc helpers
        if bundleId.hasPrefix("company.thebrowser.browser.helper") {
            return "company.thebrowser.Browser"
        }
        // Chrome helpers
        if bundleId.hasPrefix("com.google.Chrome.helper") {
            return "com.google.Chrome"
        }
        // Safari/WebKit
        if bundleId == "com.apple.WebKit.WebContent" {
            return "com.apple.Safari"
        }
        // Firefox helpers
        if bundleId.hasPrefix("org.mozilla.firefox.helper") {
            return "org.mozilla.firefox"
        }
        // Edge helpers
        if bundleId.hasPrefix("com.microsoft.edgemac.helper") {
            return "com.microsoft.edgemac"
        }
        // Brave helpers
        if bundleId.hasPrefix("com.brave.Browser.helper") {
            return "com.brave.Browser"
        }
        return bundleId
    }

    // MARK: - Private - Window Title Check (Supplementary)

    /// Bundle IDs detected via window title (to track when they end)
    private var windowDetectedMeetings: Set<String> = []

    /// Supplementary window title check for browser-based meetings
    /// Helps confirm browser meetings even before microphone is used
    private func supplementaryWindowCheck() {
        // Only run if we have Screen Recording permission
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            KoeLogger.meeting.debug("Window check: failed to get window list")
            return
        }

        // Check if any window has a name (indicates permission granted)
        var hasPermission = false
        for window in windowList {
            if let name = window[kCGWindowName as String] as? String, !name.isEmpty {
                hasPermission = true
                break
            }
        }

        guard hasPermission else {
            debugLog("Window check: no Screen Recording permission")
            return
        }

        // Track which meetings we find this cycle
        var foundMeetings: Set<String> = []

        // Log window check with permission status
        var titledWindows = 0
        for w in windowList {
            if let name = w[kCGWindowName as String] as? String, !name.isEmpty {
                titledWindows += 1
            }
        }
        debugLog("Checking \(windowList.count) windows (\(titledWindows) with titles)")

        // Collect events to emit
        var eventsToEmit: [MeetingEvent] = []

        // Look for meeting window patterns
        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String else {
                continue
            }
            let windowName = window[kCGWindowName as String] as? String ?? ""

            // Skip empty window names
            if windowName.isEmpty { continue }

            for pattern in meetingPatterns {
                let ownerMatches = ownerName == pattern.appName || ownerName.contains(pattern.appName)
                if ownerMatches {
                    // Log Arc windows specifically for debugging
                    if ownerName == "Arc" {
                        debugLog("Arc window: '\(windowName)'")
                    }
                    for titlePattern in pattern.patterns {
                        let titleMatches = windowName.contains(titlePattern)
                        // Log potential matches
                        if titleMatches {
                            debugLog("MATCH: owner='\(ownerName)' title='\(windowName)' pattern='\(titlePattern)'")
                            foundMeetings.insert(pattern.bundleId)

                            lock.lock()
                            let bundleId = pattern.bundleId

                            // Only emit if not already detected
                            if !activeMeetings.contains(bundleId) {
                                activeMeetings.insert(bundleId)
                                windowDetectedMeetings.insert(bundleId)
                                let appName = getAppDisplayName(for: bundleId)
                                eventsToEmit.append(.meetingStarted(appBundleId: bundleId, appName: appName))
                                debugLog("🟢 MEETING DETECTED: \(appName) - '\(windowName)'")
                                KoeLogger.meeting.info("Meeting detected (window title): \(appName) - '\(windowName)'")
                            }
                            lock.unlock()
                            break
                        }
                    }
                }
            }
        }

        // Check for meetings that ended (window-detected only)
        lock.lock()
        let endedMeetings = windowDetectedMeetings.subtracting(foundMeetings)
        for bundleId in endedMeetings {
            windowDetectedMeetings.remove(bundleId)
            if activeMeetings.contains(bundleId) {
                activeMeetings.remove(bundleId)
                eventsToEmit.append(.meetingEnded(appBundleId: bundleId))
                let appName = getAppDisplayName(for: bundleId)
                KoeLogger.meeting.info("Meeting ended (window closed): \(appName)")
            }
        }
        let continuationsCopy = Array(continuations.values)
        lock.unlock()

        // Emit all events outside the lock
        for event in eventsToEmit {
            for continuation in continuationsCopy {
                continuation.yield(event)
            }
        }
    }

    /// Get display name for a bundle ID
    private func getAppDisplayName(for bundleId: String) -> String {
        if let name = appInfoMap[bundleId] {
            return name
        }
        if let name = MeetingAppRegistry.displayName(for: bundleId) {
            return name
        }
        return bundleId
    }
}
