import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.koe.voice", category: "CommandDetector")

/// Main coordinator for voice command detection with speaker verification
public final class CommandDetector: @unchecked Sendable {
    // MARK: - Properties

    private let listener: CommandListener
    private let verifier: VoiceVerifier
    private let fluidVerifier: FluidAudioVerifier
    private let profileManager: VoiceProfileManager

    private let lock = NSLock()
    private var _commands: [VoiceCommand] = []
    private var _isEnabled: Bool = false
    private var _settings: VoiceCommandSettings = .load()
    private var lastDetectionTime: Date?
    private let detectionCooldown: TimeInterval = 2.0  // Prevent rapid re-triggers

    // Silence confirmation - wait for pause after trigger word
    private var pendingCommand: CommandDetectionResult?
    private var pendingCommandTimer: Timer?
    private var triggerWordCount: Int = 0  // Word count when trigger was detected
    private let defaultSilenceConfirmationDelay: TimeInterval = 2.0

    /// Voice command settings (experimental features)
    public var settings: VoiceCommandSettings {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _settings
        }
        set {
            lock.lock()
            _settings = newValue
            lock.unlock()
            newValue.save()
            applySettings()
        }
    }

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
        fluidVerifier: FluidAudioVerifier = FluidAudioVerifier(),
        profileManager: VoiceProfileManager = .shared
    ) {
        self.listener = listener
        self.verifier = verifier
        self.fluidVerifier = fluidVerifier
        self.profileManager = profileManager

        // Load saved commands
        _commands = profileManager.loadCommands()

        // Load user embedding if profile exists
        if let profile = profileManager.currentProfile {
            verifier.userEmbedding = profile.embedding
            // Also load for FluidVerifier (will use if ECAPA-TDNN enabled and embedding is 256-dim)
            if profile.neuralEmbedding != nil {
                fluidVerifier.userEmbedding = profile.neuralEmbedding
                logger.notice(
                    "[CommandDetector] Loaded neural embedding with \(profile.neuralEmbedding?.count ?? 0) dimensions")
            }
            logger.notice("[CommandDetector] Loaded profile with \(profile.embedding.count)-dim embedding")
        } else {
            logger.notice("[CommandDetector] No profile found at init")
        }

        setupListener()
        applySettings()
        let commandCount = _commands.count
        logger.notice("[CommandDetector] Initialized with \(commandCount) commands")
    }

    /// Apply current settings to components
    private func applySettings() {
        lock.lock()
        let currentSettings = _settings
        lock.unlock()

        // Apply VAD threshold to verifier
        verifier.vadThreshold = currentSettings.vadThreshold

        // Apply confidence threshold to both verifiers
        verifier.threshold = currentSettings.confidenceThreshold
        fluidVerifier.threshold = currentSettings.confidenceThreshold

        // If ECAPA-TDNN is enabled, load the model in background (lazy loading)
        if currentSettings.useECAPATDNN && !fluidVerifier.isReady {
            Task {
                logger.notice("[CommandDetector] Loading FluidAudio model for ECAPA-TDNN...")
                await fluidVerifier.loadModelIfNeeded()
            }
        }

        logger.notice(
            "[CommandDetector] Applied settings: VAD=\(currentSettings.vadEnabled), threshold=\(currentSettings.confidenceThreshold), ECAPA=\(currentSettings.useECAPATDNN)"
        )
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

        // Extract and average embeddings (simple MFCC-based)
        let embedding = verifier.train(samples: samples)

        guard !embedding.isEmpty else {
            logger.notice("[CommandDetector] Training failed: empty embedding returned")
            return nil
        }

        logger.notice("[CommandDetector] Generated embedding with \(embedding.count) features")

        // Create and save profile
        var profile = VoiceProfile(
            name: name,
            embedding: embedding,
            trainingCommandSamples: samples.count
        )

        profileManager.currentProfile = profile
        profileManager.saveTrainingSamples(samples, forCommand: "koe")

        logger.notice("[CommandDetector] Voice profile saved successfully")

        // Also train neural embedding asynchronously if ECAPA-TDNN is enabled
        Task {
            await self.trainNeuralEmbedding(samples: samples)
        }

        return profile
    }

    /// Train neural embedding asynchronously (for ECAPA-TDNN/WeSpeaker)
    private func trainNeuralEmbedding(samples: [[Float]]) async {
        logger.notice("[CommandDetector] Training neural embedding with FluidAudio...")

        let neuralEmbedding = await fluidVerifier.train(samples: samples)

        guard !neuralEmbedding.isEmpty else {
            logger.notice("[CommandDetector] Neural embedding training failed")
            return
        }

        logger.notice("[CommandDetector] Generated neural embedding with \(neuralEmbedding.count) dimensions")

        // Update the profile with neural embedding
        if var profile = profileManager.currentProfile {
            profile.neuralEmbedding = neuralEmbedding
            profile.updatedAt = Date()
            profileManager.currentProfile = profile
            fluidVerifier.userEmbedding = neuralEmbedding
            logger.notice("[CommandDetector] Saved neural embedding to profile")
        }
    }

    /// Perform speaker verification using the appropriate verifier based on settings
    private func performVerification(samples: [Float]) -> (isMatch: Bool, confidence: Float) {
        lock.lock()
        let useNeural = _settings.useECAPATDNN
        lock.unlock()

        if useNeural && fluidVerifier.isReady && fluidVerifier.userEmbedding != nil {
            // Use neural network verification (ECAPA-TDNN/WeSpeaker)
            logger.notice("[CommandDetector] Using FluidAudio neural verification")

            // FluidAudioVerifier.verify is async, so we need to run it in a detached task
            // For now, use synchronous fallback with the simple verifier
            // The neural verification happens asynchronously below
            let semaphore = DispatchSemaphore(value: 0)
            var neuralResult: (Bool, Float) = (false, 0.0)

            Task {
                neuralResult = await self.fluidVerifier.verify(samples: samples)
                semaphore.signal()
            }

            // Wait with timeout
            let waitResult = semaphore.wait(timeout: .now() + 2.0)
            if waitResult == .success {
                return neuralResult
            } else {
                logger.notice("[CommandDetector] Neural verification timed out, falling back to simple verifier")
            }
        }

        // Use simple MFCC-based verification
        return verifier.verify(samples: samples)
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
            if let neuralEmb = profile.neuralEmbedding {
                fluidVerifier.userEmbedding = neuralEmb
                logger.notice("[CommandDetector] Reloaded neural embedding: \(neuralEmb.count) dimensions")
            }
            logger.notice("[CommandDetector] Reloaded voice profile: \(profile.name)")
        } else {
            verifier.userEmbedding = nil
            fluidVerifier.userEmbedding = nil
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
        let currentSettings = settings

        // Check if another app is using the microphone (skip to avoid false triggers during calls)
        if listener.isOtherAppUsingMicrophone() {
            logger.notice("[CommandDetector] Another app is using microphone, skipping")
            return
        }

        // Voice Activity Detection - skip if no speech detected (if enabled)
        if currentSettings.vadEnabled {
            let vadScore = verifier.detectVoiceActivity(in: samples)
            if vadScore < currentSettings.vadThreshold {
                logger.notice("[CommandDetector] VAD: No speech detected (score: \(vadScore)), skipping")
                return
            }
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

        logger.notice(
            "[CommandDetector] Processing: \"\(normalizedText, privacy: .public)\" (words: \(currentWordCount))")

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

        // Check for extended trigger phrase first (Phase 2 feature)
        if currentSettings.useExtendedTrigger {
            let extendedTrigger = currentSettings.extendedTriggerPhrase.lowercased()
            if normalizedText.contains(extendedTrigger) {
                logger.notice("[CommandDetector] ✓ Matched extended trigger: \(extendedTrigger, privacy: .public)")
                processMatchedTrigger(
                    text: normalizedText, samples: samples, wordCount: currentWordCount, settings: currentSettings)
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
                let (isMatch, confidence) = performVerification(samples: samples)
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
                    logger.notice(
                        "[CommandDetector] ✗ Command '\(command.trigger)' detected but verification failed (confidence: \(confidence))"
                    )
                }

                break  // Only process first matching command
            }
        }
    }

    /// Process a matched trigger (used for both regular and extended triggers)
    private func processMatchedTrigger(text: String, samples: [Float], wordCount: Int, settings: VoiceCommandSettings) {
        // Get the first enabled command (for extended trigger, use default command)
        lock.lock()
        let activeCommands = _commands.filter { $0.isEnabled }
        lock.unlock()

        guard let command = activeCommands.first else {
            logger.notice("[CommandDetector] No active commands to execute")
            return
        }

        // Verify speaker
        logger.notice("[CommandDetector] Verifying voice with \(samples.count) samples...")
        let (isMatch, confidence) = performVerification(samples: samples)
        logger.notice("[CommandDetector] Voice verification: match=\(isMatch), confidence=\(confidence)")

        let result = CommandDetectionResult(
            command: command,
            confidence: Double(confidence),
            isVoiceVerified: isMatch
        )

        // Use settings threshold for shouldExecute check
        let meetsThreshold = confidence >= settings.confidenceThreshold
        if command.isEnabled && isMatch && meetsThreshold {
            // Don't execute immediately - wait for silence confirmation
            logger.notice("[CommandDetector] ⏳ Waiting for silence confirmation...")
            setPendingCommand(result, wordCount: wordCount)
        } else {
            logger.notice(
                "[CommandDetector] ✗ Extended trigger detected but verification failed (confidence: \(confidence), threshold: \(settings.confidenceThreshold))"
            )
        }
    }

    // MARK: - Silence Confirmation

    private func setPendingCommand(_ result: CommandDetectionResult, wordCount: Int) {
        pendingCommand = result
        triggerWordCount = wordCount

        // Start timer - if no more words detected, execute command
        let delay = settings.silenceConfirmationDelay
        pendingCommandTimer?.invalidate()
        pendingCommandTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.executePendingCommand()
        }
    }

    private func resetPendingCommandTimer() {
        let delay = settings.silenceConfirmationDelay
        pendingCommandTimer?.invalidate()
        pendingCommandTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
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
