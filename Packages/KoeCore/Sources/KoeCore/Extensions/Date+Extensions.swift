import Foundation

public extension Date {
    /// Relative time string (e.g., "2 minutes ago")
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Short relative time string (e.g., "2m ago")
    var shortRelativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Time only string (e.g., "2:30 PM")
    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: self)
    }

    /// Date and time string (e.g., "Jan 1, 2:30 PM")
    var dateTimeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .medium
        return formatter.string(from: self)
    }
}
