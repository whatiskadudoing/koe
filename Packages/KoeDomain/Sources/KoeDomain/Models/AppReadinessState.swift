public enum AppReadinessState: Equatable, Sendable {
    case welcome
    case needsPermissions
    case loading
    case ready
}
