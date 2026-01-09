import Foundation

/// Settings for voice command detection with experimental features
public struct VoiceCommandSettings: Codable, Sendable, Equatable {
    // MARK: - Phase 1 Settings (Always On)

    /// Whether VAD is enabled (default: true)
    public var vadEnabled: Bool

    /// VAD threshold (0.0 - 1.0, default: 0.3)
    public var vadThreshold: Float

    // MARK: - Phase 2 Settings (Optional)

    /// Use adaptive confidence threshold based on noise level
    public var useAdaptiveThreshold: Bool

    /// Base confidence threshold for voice verification (0.5 - 0.95)
    public var confidenceThreshold: Float

    /// Use extended trigger phrase (e.g., "Hey Koe" instead of "kon")
    public var useExtendedTrigger: Bool

    /// The extended trigger phrase
    public var extendedTriggerPhrase: String

    // MARK: - Phase 3 Settings (Experimental)

    /// Use ECAPA-TDNN model for speaker verification (requires CoreML model)
    public var useECAPATDNN: Bool

    /// Silence confirmation delay in seconds
    public var silenceConfirmationDelay: TimeInterval

    // MARK: - Initialization

    public init(
        vadEnabled: Bool = true,
        vadThreshold: Float = 0.3,
        useAdaptiveThreshold: Bool = false,
        confidenceThreshold: Float = 0.7,
        useExtendedTrigger: Bool = false,
        extendedTriggerPhrase: String = "hey koe",
        useECAPATDNN: Bool = false,
        silenceConfirmationDelay: TimeInterval = 2.0
    ) {
        self.vadEnabled = vadEnabled
        self.vadThreshold = vadThreshold
        self.useAdaptiveThreshold = useAdaptiveThreshold
        self.confidenceThreshold = confidenceThreshold
        self.useExtendedTrigger = useExtendedTrigger
        self.extendedTriggerPhrase = extendedTriggerPhrase
        self.useECAPATDNN = useECAPATDNN
        self.silenceConfirmationDelay = silenceConfirmationDelay
    }

    /// Default settings
    public static let `default` = VoiceCommandSettings()

    // MARK: - Persistence

    private static let userDefaultsKey = "VoiceCommandSettings"

    public static func load() -> VoiceCommandSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(VoiceCommandSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
