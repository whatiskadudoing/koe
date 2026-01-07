import Foundation

public struct Transcription: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let duration: TimeInterval
    public let timestamp: Date
    public let language: Language?
    public let model: KoeModel?

    public init(
        id: UUID = UUID(),
        text: String,
        duration: TimeInterval,
        timestamp: Date = Date(),
        language: Language? = nil,
        model: KoeModel? = nil
    ) {
        self.id = id
        self.text = text
        self.duration = duration
        self.timestamp = timestamp
        self.language = language
        self.model = model
    }
}
