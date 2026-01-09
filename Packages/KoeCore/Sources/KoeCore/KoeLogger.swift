import Foundation
import os.log

/// Logger for Koe application
/// Uses OSLog for system-integrated logging with file fallback for debugging
public struct KoeLogger: Sendable {
    private static let subsystem = "com.koe.voice"

    /// Log categories
    public enum Category: String, Sendable {
        case audio = "Audio"
        case transcription = "Transcription"
        case refinement = "Refinement"
        case hotkey = "Hotkey"
        case ui = "UI"
        case storage = "Storage"
        case meeting = "Meeting"
        case general = "General"
    }

    private let category: Category
    private let osLog: OSLog

    /// File logging path (for debugging)
    public static var debugLogPath: String? = nil

    /// Enable file logging for debugging
    public static var enableFileLogging = false

    public init(category: Category = .general) {
        self.category = category
        self.osLog = OSLog(subsystem: Self.subsystem, category: category.rawValue)
    }

    /// Log debug message
    public func debug(_ message: String) {
        os_log(.debug, log: osLog, "%{public}@", message)
        logToFileIfEnabled("DEBUG", message)
    }

    /// Log info message
    public func info(_ message: String) {
        os_log(.info, log: osLog, "%{public}@", message)
        logToFileIfEnabled("INFO", message)
    }

    /// Log warning message
    public func warning(_ message: String) {
        os_log(.default, log: osLog, "⚠️ %{public}@", message)
        logToFileIfEnabled("WARNING", message)
    }

    /// Log error message
    public func error(_ message: String) {
        os_log(.error, log: osLog, "❌ %{public}@", message)
        logToFileIfEnabled("ERROR", message)
    }

    /// Log error with Error object
    public func error(_ message: String, error: Error) {
        let fullMessage = "\(message): \(error.localizedDescription)"
        os_log(.error, log: osLog, "❌ %{public}@", fullMessage)
        logToFileIfEnabled("ERROR", fullMessage)
    }

    private func logToFileIfEnabled(_ level: String, _ message: String) {
        guard Self.enableFileLogging else { return }

        let logPath = Self.debugLogPath ?? "/tmp/koe_debug.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] [\(category.rawValue)] [\(level)] \(message)\n"

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
}

// MARK: - Convenience Loggers

public extension KoeLogger {
    /// Audio logger
    static let audio = KoeLogger(category: .audio)

    /// Transcription logger
    static let transcription = KoeLogger(category: .transcription)

    /// Refinement logger
    static let refinement = KoeLogger(category: .refinement)

    /// Hotkey logger
    static let hotkey = KoeLogger(category: .hotkey)

    /// UI logger
    static let ui = KoeLogger(category: .ui)

    /// Storage logger
    static let storage = KoeLogger(category: .storage)

    /// Meeting logger
    static let meeting = KoeLogger(category: .meeting)

    /// General logger
    static let general = KoeLogger(category: .general)
}
