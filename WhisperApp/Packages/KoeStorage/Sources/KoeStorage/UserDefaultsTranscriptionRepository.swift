import Foundation
import KoeDomain

/// UserDefaults-based implementation of TranscriptionRepository
/// Stores transcriptions locally using UserDefaults with JSON encoding
public final class UserDefaultsTranscriptionRepository: TranscriptionRepository, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let maxEntries: Int
    private let maxAgeDays: Int

    public init(
        defaults: UserDefaults = .standard,
        key: String = "transcriptionHistory",
        maxEntries: Int = 50,
        maxAgeDays: Int = 7
    ) {
        self.defaults = defaults
        self.key = key
        self.maxEntries = maxEntries
        self.maxAgeDays = maxAgeDays
    }

    public func save(_ transcription: Transcription) async throws {
        var history = try await fetchAll()
        history.insert(transcription, at: 0)

        // Limit entries
        if history.count > maxEntries {
            history = Array(history.prefix(maxEntries))
        }

        try persist(history)
    }

    public func fetchRecent(limit: Int) async throws -> [Transcription] {
        let all = try await fetchAll()
        return Array(all.prefix(limit))
    }

    public func delete(id: UUID) async throws {
        var history = try await fetchAll()
        history.removeAll { $0.id == id }
        try persist(history)
    }

    public func clear() async throws {
        defaults.removeObject(forKey: key)
    }

    public func count() async throws -> Int {
        return try await fetchAll().count
    }

    // MARK: - Private

    private func fetchAll() async throws -> [Transcription] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        let decoder = JSONDecoder()
        let history = try decoder.decode([Transcription].self, from: data)

        // Filter out old entries
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 24 * 60 * 60)
        return history.filter { $0.timestamp > cutoff }
    }

    private func persist(_ history: [Transcription]) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(history)
        defaults.set(data, forKey: key)
    }
}
