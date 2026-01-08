import Foundation
import CoreAudio
import KoeCore

/// Monitors audio activity using CoreAudio APIs
public final class AudioProcessMonitor: @unchecked Sendable {

    /// Whether the microphone is currently active anywhere in the system
    public private(set) var isMicrophoneActive: Bool = false

    /// Process info for an app using audio
    public struct AudioProcess: Hashable, Sendable {
        public let pid: pid_t
        public let bundleId: String
        public let isUsingInput: Bool   // Using microphone
        public let isUsingOutput: Bool  // Using speaker
    }

    /// Callback type for audio usage changes
    public typealias AudioUsageCallback = (_ bundleId: String, _ started: Bool) -> Void

    private var isMonitoring = false
    private var pollingTimer: Timer?
    private let lock = NSLock()

    /// Currently known processes using microphone
    private var microphoneUsers: Set<String> = []  // Bundle IDs

    /// Callbacks for microphone usage changes
    private var callbacks: [AudioUsageCallback] = []

    /// Known meeting app bundle IDs (main apps and helper processes)
    /// Verified on macOS - these are the actual bundle IDs used by the apps
    private let meetingAppBundleIds: Set<String> = [
        // Video conferencing - native apps
        "us.zoom.xos",                      // Zoom (verified)
        "com.microsoft.teams2",             // Microsoft Teams new (verified)
        "com.microsoft.teams",              // Microsoft Teams classic
        "com.cisco.webexmeetingsapp",       // Webex Meetings
        "com.webex.meetingmanager",         // Webex Meeting Manager
        "Cisco-Systems.Spark",              // Webex unified app
        "com.ringcentral.glip",             // RingCentral
        "com.gotomeeting.GoToMeeting",      // GoToMeeting
        "com.apple.FaceTime",               // FaceTime

        // Browsers - main apps
        "company.thebrowser.Browser",       // Arc (verified)
        "com.google.Chrome",                // Chrome (verified)
        "com.apple.Safari",                 // Safari (verified)
        "org.mozilla.firefox",              // Firefox
        "com.microsoft.edgemac",            // Edge
        "com.brave.Browser",                // Brave
        "com.vivaldi.Vivaldi",              // Vivaldi

        // Browser helper processes - these handle audio in web meetings
        // Arc helpers (verified)
        "company.thebrowser.browser.helper",
        "company.thebrowser.browser.helper.renderer",
        "company.thebrowser.browser.helper.plugin",
        // Chrome helpers (verified)
        "com.google.Chrome.helper",
        "com.google.Chrome.helper.renderer",
        "com.google.Chrome.helper.plugin",
        // Safari (verified)
        "com.apple.WebKit.WebContent",
        // Firefox
        "org.mozilla.firefox.helper",
        // Edge
        "com.microsoft.edgemac.helper",
        "com.microsoft.edgemac.helper.renderer",
        // Brave
        "com.brave.Browser.helper",
        "com.brave.Browser.helper.renderer",

        // Communication apps (verified)
        "com.tinyspeck.slackmacgap",        // Slack (verified)
        "com.slack.Slack",                  // Slack alternative
        "com.hnc.Discord",                  // Discord (verified)
        "com.skype.skype",                  // Skype
        "com.facebook.archon",              // Messenger

        // Other recording/meeting apps
        "com.loom.desktop",                 // Loom
        "com.grain.grain"                   // Grain
    ]

    /// Map helper bundle IDs to their parent app names for display
    private let helperToAppName: [String: String] = [
        // Arc helpers
        "company.thebrowser.browser.helper": "Arc",
        "company.thebrowser.browser.helper.renderer": "Arc",
        "company.thebrowser.browser.helper.plugin": "Arc",
        // Chrome helpers
        "com.google.Chrome.helper": "Chrome",
        "com.google.Chrome.helper.renderer": "Chrome",
        "com.google.Chrome.helper.plugin": "Chrome",
        // Safari
        "com.apple.WebKit.WebContent": "Safari",
        // Firefox
        "org.mozilla.firefox.helper": "Firefox",
        // Edge helpers
        "com.microsoft.edgemac.helper": "Edge",
        "com.microsoft.edgemac.helper.renderer": "Edge",
        // Brave helpers
        "com.brave.Browser.helper": "Brave",
        "com.brave.Browser.helper.renderer": "Brave"
    ]

    public init() {}

    deinit {
        stopMonitoring()
    }

    /// Start monitoring audio process usage
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        KoeLogger.meeting.info("Starting audio process monitoring via CoreAudio")

        DispatchQueue.main.async { [weak self] in
            self?.pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkMicrophoneUsage()
            }
            // Check immediately
            self?.checkMicrophoneUsage()
        }
    }

    /// Stop monitoring
    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        pollingTimer?.invalidate()
        pollingTimer = nil

        lock.lock()
        microphoneUsers.removeAll()
        lock.unlock()

        KoeLogger.meeting.info("Stopped audio process monitoring")
    }

    /// Register a callback for microphone usage changes
    public func onMicrophoneUsageChange(_ callback: @escaping AudioUsageCallback) {
        lock.lock()
        callbacks.append(callback)
        lock.unlock()
    }

    /// Get all processes currently using the microphone
    public func getProcessesUsingMicrophone() -> [AudioProcess] {
        var processes: [AudioProcess] = []

        guard let processObjectIds = getProcessObjectList() else {
            return processes
        }

        for objectId in processObjectIds {
            if let process = getProcessInfo(objectId: objectId) {
                if process.isUsingInput {
                    processes.append(process)
                }
            }
        }

        return processes
    }

    /// Get bundle IDs of meeting apps currently using the microphone
    public func getMeetingAppsUsingMicrophone() -> [String] {
        return getProcessesUsingMicrophone()
            .filter { meetingAppBundleIds.contains($0.bundleId) }
            .map { $0.bundleId }
    }

    /// Get bundle IDs of meeting apps that are ACTIVELY using audio (mic or speaker)
    /// This detects apps that are in an active call/meeting
    public func getMeetingAppsWithActiveAudio() -> [String] {
        guard let processObjectIds = getProcessObjectList() else {
            return []
        }

        var meetingApps: [String] = []
        for objectId in processObjectIds {
            if let process = getProcessInfo(objectId: objectId) {
                // Check if this is a meeting app AND actively using audio
                if meetingAppBundleIds.contains(process.bundleId) {
                    // Active = using mic OR speaker (meetings usually have both)
                    if process.isUsingInput || process.isUsingOutput {
                        // For helpers, return the parent app's bundle ID
                        if helperToAppName[process.bundleId] != nil {
                            // Map back to main bundle ID for consistency
                            let parentBundleId = getParentBundleId(for: process.bundleId)
                            meetingApps.append(parentBundleId)
                        } else {
                            meetingApps.append(process.bundleId)
                        }
                    }
                }
            }
        }
        return meetingApps
    }

    /// Get the parent bundle ID for a helper process
    private func getParentBundleId(for helperBundleId: String) -> String {
        // Arc helpers
        if helperBundleId.hasPrefix("company.thebrowser.browser.helper") {
            return "company.thebrowser.Browser"
        }
        // Chrome helpers
        if helperBundleId.hasPrefix("com.google.Chrome.helper") {
            return "com.google.Chrome"
        }
        // Safari/WebKit
        if helperBundleId == "com.apple.WebKit.WebContent" {
            return "com.apple.Safari"
        }
        // Firefox helpers
        if helperBundleId.hasPrefix("org.mozilla.firefox.helper") {
            return "org.mozilla.firefox"
        }
        // Edge helpers
        if helperBundleId.hasPrefix("com.microsoft.edgemac.helper") {
            return "com.microsoft.edgemac"
        }
        // Brave helpers
        if helperBundleId.hasPrefix("com.brave.Browser.helper") {
            return "com.brave.Browser"
        }
        // Default: return as-is
        return helperBundleId
    }

    /// Legacy method - kept for compatibility
    public func getMeetingAppsWithAudioConnection() -> [String] {
        return getMeetingAppsWithActiveAudio()
    }

    // MARK: - Private

    private func checkMicrophoneUsage() {
        let currentUsers = Set(getMeetingAppsUsingMicrophone())

        lock.lock()
        let previousUsers = microphoneUsers

        // Detect new users
        let newUsers = currentUsers.subtracting(previousUsers)
        for bundleId in newUsers {
            KoeLogger.meeting.info("App started using microphone: \(bundleId)")
            for callback in callbacks {
                callback(bundleId, true)
            }
        }

        // Detect stopped users
        let stoppedUsers = previousUsers.subtracting(currentUsers)
        for bundleId in stoppedUsers {
            KoeLogger.meeting.info("App stopped using microphone: \(bundleId)")
            for callback in callbacks {
                callback(bundleId, false)
            }
        }

        microphoneUsers = currentUsers
        lock.unlock()
    }

    /// Get list of all audio process object IDs
    private func getProcessObjectList() -> [AudioObjectID]? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // Get the size of the property data
        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )

        guard status == kAudioHardwareNoError, propertySize > 0 else {
            return nil
        }

        // Get the property data
        let count = Int(propertySize) / MemoryLayout<AudioObjectID>.size
        var objectIds = [AudioObjectID](repeating: 0, count: count)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &objectIds
        )

        guard status == kAudioHardwareNoError else {
            return nil
        }

        return objectIds
    }

    /// Get process info for a given audio object ID
    private func getProcessInfo(objectId: AudioObjectID) -> AudioProcess? {
        // Get PID
        var pidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var pid: pid_t = 0
        var pidSize = UInt32(MemoryLayout<pid_t>.size)

        var status = AudioObjectGetPropertyData(
            objectId,
            &pidAddress,
            0,
            nil,
            &pidSize,
            &pid
        )

        guard status == kAudioHardwareNoError else {
            return nil
        }

        // Get Bundle ID
        var bundleIdAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var bundleIdRef: CFString?
        var bundleIdSize = UInt32(MemoryLayout<CFString>.size)

        status = withUnsafeMutablePointer(to: &bundleIdRef) { ptr in
            AudioObjectGetPropertyData(
                objectId,
                &bundleIdAddress,
                0,
                nil,
                &bundleIdSize,
                ptr
            )
        }

        let bundleId: String
        if status == kAudioHardwareNoError, let ref = bundleIdRef {
            bundleId = ref as String
        } else {
            bundleId = ""
        }

        // Check if running input (microphone)
        var isRunningInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var isRunningInput: UInt32 = 0
        var isRunningInputSize = UInt32(MemoryLayout<UInt32>.size)

        status = AudioObjectGetPropertyData(
            objectId,
            &isRunningInputAddress,
            0,
            nil,
            &isRunningInputSize,
            &isRunningInput
        )

        let isUsingInput = (status == kAudioHardwareNoError && isRunningInput != 0)

        // Check if running output (speaker)
        var isRunningOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var isRunningOutput: UInt32 = 0
        var isRunningOutputSize = UInt32(MemoryLayout<UInt32>.size)

        status = AudioObjectGetPropertyData(
            objectId,
            &isRunningOutputAddress,
            0,
            nil,
            &isRunningOutputSize,
            &isRunningOutput
        )

        let isUsingOutput = (status == kAudioHardwareNoError && isRunningOutput != 0)

        return AudioProcess(
            pid: pid,
            bundleId: bundleId,
            isUsingInput: isUsingInput,
            isUsingOutput: isUsingOutput
        )
    }
}
