import Foundation

/// Meeting storage - persists meetings with audio files
public protocol MeetingRepository: Sendable {
    /// Save a new meeting
    func save(_ meeting: Meeting) async throws

    /// Update an existing meeting
    func update(_ meeting: Meeting) async throws

    /// Fetch all meetings, sorted by start time descending
    func fetchAll() async throws -> [Meeting]

    /// Fetch recent meetings
    func fetchRecent(limit: Int) async throws -> [Meeting]

    /// Fetch a meeting by ID
    func fetch(id: UUID) async throws -> Meeting?

    /// Delete a meeting and its audio file
    func delete(id: UUID) async throws

    /// Clear all meetings
    func clear() async throws

    /// Get the audio file URL for a meeting
    func audioFileURL(for meeting: Meeting) -> URL?

    /// Get the base directory for meeting storage
    var meetingsDirectory: URL { get }
}
