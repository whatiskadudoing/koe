import Foundation

public struct Meeting: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let appName: String
    public let appBundleId: String
    public let startTime: Date
    public var endTime: Date?
    public var audioFilePath: String?
    public var duration: TimeInterval?
    public var transcript: String?

    public var isTranscribed: Bool { transcript != nil }
    public var isRecording: Bool { endTime == nil }

    public init(
        id: UUID = UUID(),
        appName: String,
        appBundleId: String,
        startTime: Date = Date(),
        endTime: Date? = nil,
        audioFilePath: String? = nil,
        duration: TimeInterval? = nil,
        transcript: String? = nil
    ) {
        self.id = id
        self.appName = appName
        self.appBundleId = appBundleId
        self.startTime = startTime
        self.endTime = endTime
        self.audioFilePath = audioFilePath
        self.duration = duration
        self.transcript = transcript
    }
}
