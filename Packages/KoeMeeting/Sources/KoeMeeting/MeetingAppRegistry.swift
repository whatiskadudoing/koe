import Foundation

/// Registry of known meeting apps and browsers
public enum MeetingAppRegistry {
    /// Known meeting apps with their bundle IDs
    public static let meetingApps: [String: String] = [
        // Native meeting apps
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams": "Microsoft Teams",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.slack.Slack": "Slack",

        // Browsers (for Google Meet, Zoom web, etc.)
        "com.google.Chrome": "Chrome",
        "com.apple.Safari": "Safari",
        "company.thebrowser.Browser": "Arc",
    ]

    /// Check if a bundle ID is a known meeting app
    public static func isMeetingApp(_ bundleId: String) -> Bool {
        meetingApps.keys.contains(bundleId)
    }

    /// Get the display name for a meeting app
    public static func displayName(for bundleId: String) -> String? {
        meetingApps[bundleId]
    }

    /// All known meeting app bundle IDs
    public static var allBundleIds: [String] {
        Array(meetingApps.keys)
    }
}
