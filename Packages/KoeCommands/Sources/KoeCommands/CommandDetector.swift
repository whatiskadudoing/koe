import Foundation
import os.log
import UserNotifications

private let logger = Logger(subsystem: "com.koe.voice", category: "CommandDetector")

/// Main coordinator for voice command detection with speaker verification
public final class CommandDetector: @unchecked Sendable {
    // MARK: - Properties

    private let listener: CommandListener
    private let verifier: VoiceVerifier
    private let profileManager: VoiceProfileManager

    private let lock = NSLock()
    private var _commands: [VoiceCommand] = []
    private var _isEnabled: Bool = false
    private var lastDetectionTime: Date?
    private let detectionCooldown: TimeInterval = 2.0  // Prevent rapid re-triggers

    // Silence confirmation - wait for pause after trigger word
    private var pendingCommand: CommandDetectionResult?
    private var pendingCommandTimer: Timer?
    private var triggerWordCount: Int = 0  // Word count when trigger was detected
    private let silenceConfirmationDelay: TimeInterval = 2.0  // Wait 2 seconds of silence

    /// Callback when a command is detected and verified
    public var onCommandDetected: ((CommandDetectionResult) -> Void)?

    /// Callback for state changes
    public var onStateChanged: ((Bool) -> Void)?

    /// Registered commands
    public var commands: [VoiceCommand] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _commands
        }
        set {
            lock.lock()
            _commands = newValue
            lock.unlock()
            profileManager.saveCommands(newValue)
        }
    }

    /// Whether command detection is enabled
    public var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isEnabled
        }
        set {
            lock.lock()
            let oldValue = _isEnabled
            _isEnabled = newValue
            lock.unlock()

            if newValue != oldValue {
                if newValue {
                    Task { await startDetection() }
                } else {
                    stopDetection()
                }
                onStateChanged?(newValue)
            }
        }
    }

    /// Whether the listener is currently active
    public var isListening: Bool {
        listener.isListening
    }

    /// The current voice profile
    public var voiceProfile: VoiceProfile? {
        profileManager.currentProfile
    }

    // MARK: - Initialization

    public init(
        listener: CommandListener = CommandListener(),
        verifier: VoiceVerifier = VoiceVerifier(),
        profileManager: VoiceProfileManager = .shared
    ) {
        self.listener = listener
        self.verifier = verifier
        self.profileManager = profileManager

        // Load saved commands
        _commands = profileManager.loadCommands()

        // Load user embedding if profile exists
        if let profile = profileManager.currentProfile {
            verifier.userEmbedding = profile.embedding
            logger.notice("[CommandDetector] Loaded profile with \(profile.embedding.count)-dim embedding")
        } else {
            logger.notice("[CommandDetector] No profile found at init")
        }

        setupListener()
        let commandCount = _commands.count
        logger.notice("[CommandDetector] Initialized with \(commandCount) commands")
    }

    // MARK: - Public Methods

    /// Start command detection
    public func startDetection() async {
        logger.notice("[CommandDetector] startDetection called")

        guard profileManager.hasProfile else {
            logger.notice("[CommandDetector] Cannot start: no voice profile trained")
            return
        }

        logger.notice("[CommandDetector] Profile exists, starting listener...")

        // Make sure we have the profile loaded
        if verifier.userEmbedding == nil {
            logger.notice("[CommandDetector] Loading profile into verifier...")
            reloadProfile()
        }

        do {
            try await listener.startListening()
            lock.lock()
            _isEnabled = true
            lock.unlock()
            logger.notice("[CommandDetector] ✓ Command detection started")
        } catch {
            logger.notice("[CommandDetector] Failed to start: \(error)")
        }
    }

    /// Stop command detection
    public func stopDetection() {
        listener.stopListening()
        lock.lock()
        _isEnabled = false
        lock.unlock()
    }

    /// Train a new voice profile with audio samples
    public func trainVoiceProfile(name: String, samples: [[Float]]) -> VoiceProfile? {
        logger.notice("[CommandDetector] Training voice profile with \(samples.count) samples")

        guard !samples.isEmpty else {
            logger.notice("[CommandDetector] Training failed: no samples provided")
            return nil
        }

        // Log sample info
        for (i, sample) in samples.enumerated() {
            logger.notice("[CommandDetector] Sample \(i+1): \(sample.count) samples")
        }

        // Extract and average embeddings
        let embedding = verifier.train(samples: samples)

        guard !embedding.isEmpty else {
            logger.notice("[CommandDetector] Training failed: empty embedding returned")
            return nil
        }

        logger.notice("[CommandDetector] Generated embedding with \(embedding.count) features")

        // Create and save profile
        let profile = VoiceProfile(
            name: name,
            embedding: embedding,
            trainingCommandSamples: samples.count
        )

        profileManager.currentProfile = profile
        profileManager.saveTrainingSamples(samples, forCommand: "koe")

        logger.notice("[CommandDetector] Voice profile saved successfully")

        return profile
    }

    /// Delete the current voice profile
    public func deleteVoiceProfile() {
        stopDetection()
        profileManager.deleteAllTrainingData()
        verifier.userEmbedding = nil
    }

    /// Reload the voice profile from storage (call after training or app resume)
    public func reloadProfile() {
        if let profile = profileManager.currentProfile {
            verifier.userEmbedding = profile.embedding
            logger.notice("[CommandDetector] Reloaded voice profile: \(profile.name)")
        } else {
            verifier.userEmbedding = nil
            logger.notice("[CommandDetector] No voice profile found")
        }
    }

    /// Add a new command
    public func addCommand(_ command: VoiceCommand) {
        lock.lock()
        _commands.append(command)
        let cmds = _commands
        lock.unlock()
        profileManager.saveCommands(cmds)
    }

    /// Remove a command
    public func removeCommand(_ command: VoiceCommand) {
        lock.lock()
        _commands.removeAll { $0.id == command.id }
        let cmds = _commands
        lock.unlock()
        profileManager.saveCommands(cmds)
    }

    /// Update a command
    public func updateCommand(_ command: VoiceCommand) {
        lock.lock()
        if let index = _commands.firstIndex(where: { $0.id == command.id }) {
            _commands[index] = command
        }
        let cmds = _commands
        lock.unlock()
        profileManager.saveCommands(cmds)
    }

    // MARK: - Private Methods

    private func setupListener() {
        listener.onTextDetected = { [weak self] text, samples in
            self?.handleDetectedText(text, samples: samples)
        }

        listener.onError = { [weak self] error in
            logger.notice("[CommandDetector] Listener error: \(error)")

            // Attempt restart on error
            guard let self = self, self.isEnabled else { return }
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
                if self.isEnabled {
                    await self.startDetection()
                }
            }
        }
    }

    private func handleDetectedText(_ text: String, samples: [Float]) {
        // Check if another app is using the microphone (skip to avoid false triggers during calls)
        if listener.isOtherAppUsingMicrophone() {
            logger.notice("[CommandDetector] Another app is using microphone, skipping")
            return
        }

        // Check cooldown
        if let lastTime = lastDetectionTime,
            Date().timeIntervalSince(lastTime) < detectionCooldown
        {
            logger.notice("[CommandDetector] Cooldown active, ignoring text")
            return
        }

        let normalizedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let currentWordCount = normalizedText.split(separator: " ").count

        logger.notice("[CommandDetector] Processing: \"\(normalizedText, privacy: .public)\" (words: \(currentWordCount))")

        // If we have a pending command, check if user continued speaking
        if pendingCommand != nil {
            if currentWordCount > triggerWordCount {
                // User continued speaking after trigger - cancel the pending command
                logger.notice("[CommandDetector] User continued speaking, cancelling pending command")
                cancelPendingCommand()
                return
            } else {
                // Same word count, reset the timer (extend silence wait)
                resetPendingCommandTimer()
                return
            }
        }

        // Check for matching commands
        lock.lock()
        let activeCommands = _commands.filter { $0.isEnabled }
        lock.unlock()

        let triggers = activeCommands.map { $0.trigger }.joined(separator: ", ")
        logger.notice("[CommandDetector] Active commands: [\(triggers, privacy: .public)]")

        for command in activeCommands {
            // Check if text contains the trigger word or similar variations
            let triggerVariations = getTriggerVariations(for: command.trigger.lowercased())
            let matched = triggerVariations.contains { variation in
                normalizedText.contains(variation)
            }

            if matched {
                logger.notice("[CommandDetector] ✓ Matched trigger: \(command.trigger, privacy: .public)")
                // Verify speaker
                logger.notice("[CommandDetector] Verifying voice with \(samples.count) samples...")
                let (isMatch, confidence) = verifier.verify(samples: samples)
                logger.notice("[CommandDetector] Voice verification: match=\(isMatch), confidence=\(confidence)")

                let result = CommandDetectionResult(
                    command: command,
                    confidence: Double(confidence),
                    isVoiceVerified: isMatch
                )

                if result.shouldExecute {
                    // Don't execute immediately - wait for silence confirmation
                    logger.notice("[CommandDetector] ⏳ Waiting for silence confirmation...")
                    setPendingCommand(result, wordCount: currentWordCount)
                } else {
                    logger.notice("[CommandDetector] ✗ Command '\(command.trigger)' detected but verification failed (confidence: \(confidence))")
                }

                break  // Only process first matching command
            }
        }
    }

    // MARK: - Silence Confirmation

    private func setPendingCommand(_ result: CommandDetectionResult, wordCount: Int) {
        pendingCommand = result
        triggerWordCount = wordCount

        // Start timer - if no more words detected, execute command
        pendingCommandTimer?.invalidate()
        pendingCommandTimer = Timer.scheduledTimer(withTimeInterval: silenceConfirmationDelay, repeats: false) { [weak self] _ in
            self?.executePendingCommand()
        }
    }

    private func resetPendingCommandTimer() {
        pendingCommandTimer?.invalidate()
        pendingCommandTimer = Timer.scheduledTimer(withTimeInterval: silenceConfirmationDelay, repeats: false) { [weak self] _ in
            self?.executePendingCommand()
        }
    }

    private func cancelPendingCommand() {
        pendingCommandTimer?.invalidate()
        pendingCommandTimer = nil
        pendingCommand = nil
        triggerWordCount = 0
    }

    private func executePendingCommand() {
        guard let result = pendingCommand else { return }

        logger.notice("[CommandDetector] ✓ Silence confirmed, executing command: \(result.command.trigger)")
        lastDetectionTime = Date()
        onCommandDetected?(result)

        // Execute the command action
        executeCommand(result)

        // Clear pending state
        pendingCommand = nil
        pendingCommandTimer = nil
        triggerWordCount = 0
    }

    /// Get variations of a trigger word that speech recognition might produce
    private func getTriggerVariations(for trigger: String) -> [String] {
        // Speech recognition often misrecognizes short words
        // IMPORTANT: Keep this list tight to reduce false positives
        // Removed common words: "on", "call", "gone", "john", "calm", "co", "key", "kay"
        switch trigger {
        case "kon":
            // Only similar-sounding uncommon words
            return ["kon", "kong", "con", "cone", "khan"]
        case "koe":
            return ["koe", "koi", "coy"]
        default:
            return [trigger]
        }
    }

    private func executeCommand(_ result: CommandDetectionResult) {
        switch result.command.action {
        case .notification(let title, let body):
            sendNotification(title: title, body: body)

        case .startRecording:
            NotificationCenter.default.post(
                name: NSNotification.Name("KoeCommandStartRecording"),
                object: nil
            )

        case .stopRecording:
            NotificationCenter.default.post(
                name: NSNotification.Name("KoeCommandStopRecording"),
                object: nil
            )

        case .togglePipelineOption(let option):
            NotificationCenter.default.post(
                name: NSNotification.Name("KoeCommandToggleOption"),
                object: nil,
                userInfo: ["option": option]
            )

        case .custom(let action):
            NotificationCenter.default.post(
                name: NSNotification.Name("KoeCommandCustom"),
                object: nil,
                userInfo: ["action": action]
            )
        }
    }

    private func sendNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()

        // Request permission if needed
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )

        center.add(request) { error in
            if let error = error {
                logger.notice("[CommandDetector] Notification error: \(error)")
            }
        }
    }
}
