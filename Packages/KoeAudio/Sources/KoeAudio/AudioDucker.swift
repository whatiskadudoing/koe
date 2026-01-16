import Foundation

/// Manages system audio ducking during recording
/// Mutes system audio while dictation is active (preserves volume level)
/// Uses NSAppleScript for reliable cross-version macOS support
public final class AudioDucker: @unchecked Sendable {
    public static let shared = AudioDucker()

    private var isMuted = false
    private let lock = NSLock()

    private init() {}

    /// Mute system audio for recording
    public func duck() {
        lock.lock()
        defer { lock.unlock() }

        guard !isMuted else { return }

        // Mute system audio (preserves volume level)
        let script = NSAppleScript(source: "set volume with output muted")
        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)

        if errorInfo == nil {
            isMuted = true
        }
    }

    /// Unmute system audio after recording
    public func unduck() {
        lock.lock()
        defer { lock.unlock() }

        guard isMuted else { return }

        // Unmute system audio (restores previous volume)
        let script = NSAppleScript(source: "set volume without output muted")
        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)

        if errorInfo == nil {
            isMuted = false
        }
    }

    /// Check if audio is currently muted
    public var isAudioDucked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isMuted
    }

    deinit {
        // Ensure audio is unmuted if object is deallocated
        if isMuted {
            let script = NSAppleScript(source: "set volume without output muted")
            var errorInfo: NSDictionary?
            script?.executeAndReturnError(&errorInfo)
        }
    }
}
