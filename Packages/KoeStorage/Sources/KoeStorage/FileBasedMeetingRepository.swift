import Foundation
import KoeDomain

/// File-based implementation of MeetingRepository
/// Stores meeting metadata in JSON and audio files in date-organized folders
public final class FileBasedMeetingRepository: MeetingRepository, @unchecked Sendable {
    public let meetingsDirectory: URL
    private let indexURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager

        // ~/Library/Application Support/Koe/Meetings/
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.meetingsDirectory = appSupport.appendingPathComponent("Koe/Meetings", isDirectory: true)
        self.indexURL = meetingsDirectory.appendingPathComponent("meetings.json")

        // Create directory if needed
        try? fileManager.createDirectory(at: meetingsDirectory, withIntermediateDirectories: true)
    }

    public func save(_ meeting: Meeting) async throws {
        lock.lock()
        defer { lock.unlock() }

        var meetings = try loadIndex()
        meetings.insert(meeting, at: 0)
        try saveIndex(meetings)
    }

    public func update(_ meeting: Meeting) async throws {
        lock.lock()
        defer { lock.unlock() }

        var meetings = try loadIndex()
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[index] = meeting
            try saveIndex(meetings)
        }
    }

    public func fetchAll() async throws -> [Meeting] {
        lock.lock()
        defer { lock.unlock() }
        return try loadIndex()
    }

    public func fetchRecent(limit: Int) async throws -> [Meeting] {
        let all = try await fetchAll()
        return Array(all.prefix(limit))
    }

    public func fetch(id: UUID) async throws -> Meeting? {
        let all = try await fetchAll()
        return all.first { $0.id == id }
    }

    public func delete(id: UUID) async throws {
        lock.lock()
        defer { lock.unlock() }

        var meetings = try loadIndex()
        if let index = meetings.firstIndex(where: { $0.id == id }) {
            let meeting = meetings[index]

            // Delete audio file if exists
            if let audioPath = meeting.audioFilePath {
                let audioURL = meetingsDirectory.appendingPathComponent(audioPath)
                try? fileManager.removeItem(at: audioURL)

                // Remove date folder if empty
                let dateFolder = audioURL.deletingLastPathComponent()
                if let contents = try? fileManager.contentsOfDirectory(atPath: dateFolder.path),
                   contents.isEmpty {
                    try? fileManager.removeItem(at: dateFolder)
                }
            }

            meetings.remove(at: index)
            try saveIndex(meetings)
        }
    }

    public func clear() async throws {
        lock.lock()
        defer { lock.unlock() }

        // Remove all contents
        if let contents = try? fileManager.contentsOfDirectory(at: meetingsDirectory, includingPropertiesForKeys: nil) {
            for url in contents {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    public func audioFileURL(for meeting: Meeting) -> URL? {
        guard let path = meeting.audioFilePath else { return nil }
        return meetingsDirectory.appendingPathComponent(path)
    }

    /// Generate a new audio file URL for a meeting
    public func createAudioFileURL(for meeting: Meeting) throws -> URL {
        // Create date folder: 2024-01-15/
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateFolder = dateFormatter.string(from: meeting.startTime)

        let dateFolderURL = meetingsDirectory.appendingPathComponent(dateFolder, isDirectory: true)
        try fileManager.createDirectory(at: dateFolderURL, withIntermediateDirectories: true)

        // Create filename: zoom_14-30-00.wav
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH-mm-ss"
        let timeString = timeFormatter.string(from: meeting.startTime)

        let appName = meeting.appName.lowercased().replacingOccurrences(of: " ", with: "_")
        let filename = "\(appName)_\(timeString).wav"

        return dateFolderURL.appendingPathComponent(filename)
    }

    /// Get the relative path from full URL
    public func relativePath(for url: URL) -> String {
        let fullPath = url.path
        let basePath = meetingsDirectory.path
        if fullPath.hasPrefix(basePath) {
            var relative = String(fullPath.dropFirst(basePath.count))
            if relative.hasPrefix("/") {
                relative = String(relative.dropFirst())
            }
            return relative
        }
        return url.lastPathComponent
    }

    // MARK: - Private

    private func loadIndex() throws -> [Meeting] {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return []
        }

        let data = try Data(contentsOf: indexURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Meeting].self, from: data)
    }

    private func saveIndex(_ meetings: [Meeting]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(meetings)
        try data.write(to: indexURL, options: .atomic)
    }
}
