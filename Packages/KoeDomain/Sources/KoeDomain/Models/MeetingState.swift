import Foundation

public enum MeetingState: Sendable, Equatable {
    case idle
    case recording(Meeting)

    public var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    public var currentMeeting: Meeting? {
        if case .recording(let meeting) = self { return meeting }
        return nil
    }
}
