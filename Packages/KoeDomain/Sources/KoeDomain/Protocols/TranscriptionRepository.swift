import Foundation

/// Transcription storage - CAN run locally or remotely
public protocol TranscriptionRepository: Sendable {
    /// Save a transcription
    func save(_ transcription: Transcription) async throws

    /// Fetch recent transcriptions
    func fetchRecent(limit: Int) async throws -> [Transcription]

    /// Delete a transcription by ID
    func delete(id: UUID) async throws

    /// Clear all transcriptions
    func clear() async throws

    /// Count of stored transcriptions
    func count() async throws -> Int
}
