import Foundation
import os.log

private let logger = Logger(subsystem: "com.koe.voice", category: "VoiceProfileManager")

/// Manages storage and retrieval of voice profiles
public final class VoiceProfileManager: @unchecked Sendable {
    // MARK: - Properties

    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let profilesDirectory: URL

    private let lock = NSLock()
    private var _currentProfile: VoiceProfile?

    private static let profileKey = "koe_voice_profile"
    private static let commandsKey = "koe_voice_commands"

    /// Shared instance
    public static let shared = VoiceProfileManager()

    /// The current user's voice profile
    public var currentProfile: VoiceProfile? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _currentProfile
        }
        set {
            lock.lock()
            _currentProfile = newValue
            lock.unlock()

            if let profile = newValue {
                saveProfile(profile)
            } else {
                deleteProfile()
            }
        }
    }

    /// Whether a voice profile exists
    public var hasProfile: Bool {
        currentProfile != nil
    }

    // MARK: - Initialization

    public init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager

        // Create profiles directory in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.profilesDirectory = appSupport.appendingPathComponent("Koe/VoiceProfiles", isDirectory: true)

        try? fileManager.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)

        // Load existing profile
        _currentProfile = loadProfile()

        let hasProfile = _currentProfile != nil
        logger.notice("[VoiceProfileManager] Initialized. Has profile: \(hasProfile ? "YES" : "NO")")
    }

    // MARK: - Profile Management

    /// Save a voice profile
    public func saveProfile(_ profile: VoiceProfile) {
        do {
            let data = try JSONEncoder().encode(profile)
            userDefaults.set(data, forKey: Self.profileKey)
            userDefaults.synchronize()  // Force immediate write
            logger.notice("[VoiceProfileManager] Profile saved: \(profile.name) with \(profile.embedding.count) features")
        } catch {
            logger.notice("[VoiceProfileManager] Failed to save profile: \(error)")
        }
    }

    /// Load the saved voice profile
    public func loadProfile() -> VoiceProfile? {
        guard let data = userDefaults.data(forKey: Self.profileKey) else {
            logger.notice("[VoiceProfileManager] No profile data found in UserDefaults")
            return nil
        }

        do {
            let profile = try JSONDecoder().decode(VoiceProfile.self, from: data)
            logger.notice("[VoiceProfileManager] Loaded profile: \(profile.name) with \(profile.embedding.count) features")
            return profile
        } catch {
            logger.notice("[VoiceProfileManager] Failed to load profile: \(error)")
            return nil
        }
    }

    /// Delete the current profile
    public func deleteProfile() {
        userDefaults.removeObject(forKey: Self.profileKey)

        lock.lock()
        _currentProfile = nil
        lock.unlock()
    }

    // MARK: - Command Management

    /// Save registered commands
    public func saveCommands(_ commands: [VoiceCommand]) {
        do {
            let data = try JSONEncoder().encode(commands)
            userDefaults.set(data, forKey: Self.commandsKey)
        } catch {
            logger.notice("[VoiceProfileManager] Failed to save commands: \(error)")
        }
    }

    /// Load registered commands
    public func loadCommands() -> [VoiceCommand] {
        guard let data = userDefaults.data(forKey: Self.commandsKey) else {
            // Return default command if none saved
            return [.koeDefault]
        }

        do {
            return try JSONDecoder().decode([VoiceCommand].self, from: data)
        } catch {
            logger.notice("[VoiceProfileManager] Failed to load commands: \(error)")
            return [.koeDefault]
        }
    }

    // MARK: - Audio Sample Storage

    /// Save training audio samples for a command
    public func saveTrainingSamples(_ samples: [[Float]], forCommand trigger: String) {
        let fileName = "training_\(trigger.lowercased()).json"
        let fileURL = profilesDirectory.appendingPathComponent(fileName)

        do {
            let data = try JSONEncoder().encode(samples)
            try data.write(to: fileURL)
        } catch {
            logger.notice("[VoiceProfileManager] Failed to save training samples: \(error)")
        }
    }

    /// Load training audio samples for a command
    public func loadTrainingSamples(forCommand trigger: String) -> [[Float]]? {
        let fileName = "training_\(trigger.lowercased()).json"
        let fileURL = profilesDirectory.appendingPathComponent(fileName)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([[Float]].self, from: data)
        } catch {
            logger.notice("[VoiceProfileManager] Failed to load training samples: \(error)")
            return nil
        }
    }

    /// Delete all training data
    public func deleteAllTrainingData() {
        deleteProfile()

        // Delete all files in profiles directory
        if let files = try? fileManager.contentsOfDirectory(at: profilesDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }

        // Reset commands to default
        saveCommands([.koeDefault])
    }
}
