import AppKit
import KoeAudio
import KoeCommands
import KoeCore
import KoeDomain
import KoeHotkey
import KoePipeline
import KoeRefinement
import KoeTextInsertion
import KoeTranscription
import SwiftUI

/// Coordinates recording, transcription, and text insertion
/// This replaces the monolithic RecordingService with a clean, modular approach
@Observable
@MainActor
public final class RecordingCoordinator {
    // MARK: - Shared Instance
    /// Shared instance for use by AppDelegate and other non-SwiftUI code
    /// Note: For SwiftUI views, prefer using @Environment injection
    public static let shared = RecordingCoordinator()

    // MARK: - Dependencies (injected)
    private let audioRecorder: AVAudioEngineRecorder
    private let whisperKitTranscriber: WhisperKitTranscriber
    private let appleSpeechTranscriber: AppleSpeechTranscriber
    private let textInserter: TextInsertionServiceImpl
    private let vadProcessor: VADProcessor
    private let hotkeyManager: KoeHotkeyManager
    private let aiService: AIService

    /// Returns the active transcriber based on which node is enabled
    private var activeTranscriber: any TranscriptionService {
        if AppState.shared.isAppleSpeechEnabled {
            return appleSpeechTranscriber
        } else {
            return whisperKitTranscriber
        }
    }

    // MARK: - State
    public private(set) var isRecording = false
    public private(set) var audioLevel: Float = 0.0
    public private(set) var currentTranscription: String = ""

    /// True when pipeline is processing (transcribing/refining/typing)
    /// Prevents new recordings until the entire flow completes
    public private(set) var isPipelineProcessing = false

    // Recording state
    private var recordingStartTime: Date?
    private var levelTimer: Timer?
    private var streamingTimer: Timer?
    private var vadMonitorTimer: Timer?
    private var isTranscribing = false

    // VAD state for voice command recordings
    private var isSpeaking = false
    private var silenceStartTime: Date?
    private var speechStartIndex: Int = 0
    private var totalSamplesRecorded: Int = 0
    private var consecutiveNonUserVoiceCount: Int = 0

    // Voice verifier for checking if speech is from trained user
    private let voiceVerifier = VoiceVerifier()
    private let voiceProfileManager = VoiceProfileManager()

    // Target lock for cross-app text insertion
    private let targetLockService = TargetLockService.shared

    // VAD processor with longer timeout for voice commands (3 seconds to allow thinking)
    private let voiceCommandVADProcessor = VADProcessor(
        silenceThreshold: 0.012,
        silenceDuration: 3.0,  // Longer timeout for voice commands
        minSpeechDuration: 0.5,
        sampleRate: 16000
    )

    // Transcription state
    private var accumulatedTranscription = ""
    private var lastTypedText = ""

    private let logger = KoeLogger.audio

    // MARK: - Initialization

    public init(
        audioRecorder: AVAudioEngineRecorder = AVAudioEngineRecorder(),
        whisperKitTranscriber: WhisperKitTranscriber = WhisperKitTranscriber(),
        appleSpeechTranscriber: AppleSpeechTranscriber = AppleSpeechTranscriber(),
        textInserter: TextInsertionServiceImpl = TextInsertionServiceImpl(),
        vadProcessor: VADProcessor = VADProcessor(),
        hotkeyManager: KoeHotkeyManager = KoeHotkeyManager(),
        aiService: AIService = AIService.shared
    ) {
        self.audioRecorder = audioRecorder
        self.whisperKitTranscriber = whisperKitTranscriber
        self.appleSpeechTranscriber = appleSpeechTranscriber
        self.textInserter = textInserter
        self.vadProcessor = vadProcessor
        self.hotkeyManager = hotkeyManager
        self.aiService = aiService
    }

    // MARK: - Hotkey Setup

    public func setupHotkey() {
        // Configure hotkey from AppState settings
        hotkeyManager.setShortcut(
            keyCode: AppState.shared.hotkeyKeyCode,
            modifiers: AppState.shared.hotkeyModifiers
        )

        hotkeyManager.register(
            onKeyDown: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    // Hotkey uses push-to-talk (records while held)
                    await self.startRecording(mode: .vad, language: .auto)
                }
            },
            onKeyUp: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    await self.stopRecording(mode: .vad, language: .auto)
                }
            }
        )
        logger.info("Hotkey registered: \(AppState.shared.hotkeyDisplayString)")
    }

    /// Update hotkey when settings change
    public func updateHotkey() {
        hotkeyManager.setShortcut(
            keyCode: AppState.shared.hotkeyKeyCode,
            modifiers: AppState.shared.hotkeyModifiers
        )
        logger.info("Hotkey updated: \(AppState.shared.hotkeyDisplayString)")
    }

    public func unregisterHotkey() {
        hotkeyManager.unregister()
    }

    // MARK: - Trigger Subscription

    private var triggerManager: TriggerManager?

    /// Subscribe to a TriggerManager for recording control
    /// This is the preferred way to wire up triggers instead of direct hotkey setup
    public func subscribeTo(triggerManager: TriggerManager) {
        self.triggerManager = triggerManager

        triggerManager.onEvent { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                switch event {
                case .start:
                    await self.startRecording(mode: .vad, language: .auto)
                case .stop:
                    await self.stopRecording(mode: .vad, language: .auto)
                }
            }
        }
        logger.info("Subscribed to TriggerManager")
    }

    // MARK: - Deferred Initialization

    /// Called when app reaches .ready state to finish initialization
    public func initializeWhenReady() {
        // Request accessibility permission when ready
        if !textInserter.hasPermission() {
            textInserter.requestPermission()
        }
    }

    // MARK: - Model Loading (WhisperKit specific)

    public var isModelLoaded: Bool {
        // For Apple Speech, always ready. For WhisperKit, check if loaded.
        if AppState.shared.isAppleSpeechEnabled && !AppState.shared.isWhisperKitEnabled {
            return true
        }
        return whisperKitTranscriber.isReady
    }

    public var modelLoadingProgress: Double {
        whisperKitTranscriber.loadingProgress
    }

    /// Currently loaded WhisperKit model (nil if no model loaded)
    public var currentModel: KoeModel? {
        whisperKitTranscriber.currentModel
    }

    public func loadModel(_ model: KoeModel) async {
        // Only load WhisperKit model if WhisperKit is enabled
        guard AppState.shared.isWhisperKitEnabled else {
            logger.info("Skipping WhisperKit model load - Apple Speech is active")
            return
        }

        logger.info("Loading WhisperKit model: \(model.rawValue)")
        do {
            try await whisperKitTranscriber.loadModel(model)

            // Only set loaded if transcriber is actually ready
            if whisperKitTranscriber.isReady {
                AppState.shared.isModelLoaded = true
                NotificationCenter.default.post(name: .modelLoaded, object: nil)
                logger.info("WhisperKit model loaded successfully")
            } else {
                logger.warning("loadModel completed but whisperKitTranscriber.isReady is false")
                AppState.shared.isModelLoaded = false
            }
        } catch {
            logger.error("Failed to load WhisperKit model", error: error)
            AppState.shared.isModelLoaded = false
        }
    }

    public func loadModel(name: String) async {
        let model = KoeModel(rawValue: name) ?? .balanced
        await loadModel(model)
    }

    public func unloadModel() {
        whisperKitTranscriber.unloadModel()
        AppState.shared.isModelLoaded = false
    }

    // MARK: - AI Refinement

    public var isRefinementReady: Bool {
        aiService.isReady
    }

    public var isOllamaConnected: Bool {
        OllamaRefinementService.shared.isConnected
    }

    public func checkOllamaConnection() async -> Bool {
        logger.info("Checking Ollama connection...")
        let connected = await OllamaRefinementService.shared.checkConnection()
        AppState.shared.isOllamaConnected = connected
        return connected
    }

    public func configureRefinement() async {
        // Set the AI tier from app state
        let tier = AppState.shared.currentAITier
        await aiService.setTier(tier)

        // For custom tier, configure Ollama settings
        if tier == .custom {
            let endpoint = AppState.shared.ollamaEndpoint
            let model = AppState.shared.ollamaModel

            OllamaRefinementService.shared.setEndpoint(endpoint)
            OllamaRefinementService.shared.setModel(model)
        }
    }

    // MARK: - Recording

    public func startRecording(mode: TranscriptionMode, language: Language) async {
        // Note: Recording is now decoupled from transcription readiness.
        // The transcription node will handle its own readiness check.

        // Prevent starting a new recording if currently recording OR if pipeline is still processing
        guard !isRecording && !isPipelineProcessing else {
            if isPipelineProcessing {
                logger.info("Ignoring start - pipeline still processing")
            }
            return
        }

        logger.info("Starting recording - mode: \(mode.rawValue), language: \(language.code)")

        // Lock the current text field as our insertion target
        let targetLocked = targetLockService.lockCurrentTarget()
        if targetLocked {
            logger.info("Target locked: \(targetLockService.lockedAppBundleId ?? "unknown")")
        } else {
            logger.warning("Could not lock target - will insert at current focus")
        }

        // Reset state
        resetRecordingState()
        recordingStartTime = Date()

        do {
            try await audioRecorder.startRecording()
            isRecording = true

            // Notify mode manager that dictation started
            NotificationCenter.default.post(name: .dictationStarted, object: nil)

            // Update AppState
            AppState.shared.recordingState = .recording
            AppState.shared.currentTranscription = ""

            // Update overlay
            RecordingOverlayController.shared.updateFromService(audioLevel: 0, state: .recording)

            // Start audio level monitoring
            startLevelMonitoring()

            // Start streaming timer for realtime mode
            if mode == .realtime {
                startStreamingTimer(language: language)
            }

            // If triggered by voice command, start VAD monitoring with voice verification
            if AppState.shared.isVoiceCommandTriggered {
                startVoiceAwareVADMonitoring(language: language)
            }

        } catch {
            logger.error("Failed to start recording", error: error)
            AppState.shared.errorMessage = "Recording failed: \(error.localizedDescription)"
        }
    }

    public func stopRecording(mode: TranscriptionMode, language: Language) async {
        guard isRecording else { return }

        logger.info("Stopping recording")

        // Stop timers
        levelTimer?.invalidate()
        levelTimer = nil
        vadMonitorTimer?.invalidate()
        vadMonitorTimer = nil
        streamingTimer?.invalidate()
        streamingTimer = nil

        isRecording = false
        audioLevel = 0

        // Update AppState to transcribing
        AppState.shared.recordingState = .transcribing
        RecordingOverlayController.shared.updateFromService(audioLevel: 0, state: .transcribing)

        // Wait for any in-progress transcription (max 2 seconds)
        var waitCount = 0
        while isTranscribing && waitCount < 40 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            waitCount += 1
        }
        if waitCount >= 40 {
            logger.warning("Timed out waiting for transcription to complete")
        }

        // Final transcription
        await transcribeFinalAudio(mode: mode, language: language)

        // Notify mode manager that dictation ended
        NotificationCenter.default.post(name: .dictationEnded, object: nil)

        // Update AppState to idle
        AppState.shared.recordingState = .idle
        RecordingOverlayController.shared.updateFromService(audioLevel: 0, state: .idle)
    }

    // MARK: - Private Methods

    private func resetRecordingState() {
        accumulatedTranscription = ""
        lastTypedText = ""
        currentTranscription = ""
    }

    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.audioLevel = self.audioRecorder.updateAudioLevel()

                // Update overlay waveform
                RecordingOverlayViewModel.shared.audioLevel = self.audioLevel

                // Notify for menu bar animation
                NotificationCenter.default.post(name: .audioLevelChanged, object: self.audioLevel)
            }
        }
    }

    /// Start VAD monitoring with voice verification for voice command triggered recordings
    /// Automatically stops recording when silence or non-user voice is detected
    private func startVoiceAwareVADMonitoring(language: Language) {
        // Reset VAD state
        isSpeaking = true  // Assume speaking since they just said the command
        silenceStartTime = nil
        speechStartIndex = 0
        totalSamplesRecorded = 0
        consecutiveNonUserVoiceCount = 0

        // Load user's voice profile into verifier
        if let profile = voiceProfileManager.currentProfile {
            voiceVerifier.userEmbedding = profile.embedding
            voiceVerifier.threshold = 0.5  // Lower threshold for continuous verification
        }

        logger.info("Starting voice-aware VAD monitoring for voice command recording")

        // Check every 200ms
        vadMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRecording else { return }

                // Get recent audio samples (last ~200ms = 3200 samples at 16kHz)
                let samples = self.audioRecorder.getRecentSamples(count: 3200)
                guard samples.count > 0 else { return }

                self.totalSamplesRecorded += samples.count

                // Check VAD result (using voice command VAD with longer silence timeout)
                let vadResult = self.voiceCommandVADProcessor.analyze(
                    samples: samples,
                    isSpeaking: self.isSpeaking,
                    speechStartIndex: self.speechStartIndex,
                    silenceStartTime: self.silenceStartTime,
                    totalSamples: self.totalSamplesRecorded
                )

                switch vadResult {
                case .speaking:
                    self.isSpeaking = true
                    self.silenceStartTime = nil

                    // Check if this is the user's voice
                    let (isUserVoice, _) = self.voiceVerifier.verify(samples: samples)
                    if !isUserVoice {
                        self.consecutiveNonUserVoiceCount += 1
                        self.logger.debug("Non-user voice detected (\(self.consecutiveNonUserVoiceCount)/5)")

                        // If 5 consecutive checks (~1 second) show non-user voice, stop
                        if self.consecutiveNonUserVoiceCount >= 5 {
                            self.logger.info("Stopping: non-user voice detected for too long")
                            await self.stopVoiceCommandRecording(language: language)
                        }
                    } else {
                        self.consecutiveNonUserVoiceCount = 0
                    }

                case .silence(let startedAt):
                    // Keep isSpeaking = true so VAD can detect speechEnded
                    // Only update silenceStartTime
                    if self.silenceStartTime == nil {
                        self.silenceStartTime = startedAt
                        self.logger.debug("Silence started")
                    }

                case .speechEnded:
                    // VAD detected end of speech - stop recording
                    self.logger.info("Stopping: VAD detected end of speech")
                    self.isSpeaking = false
                    await self.stopVoiceCommandRecording(language: language)
                }
            }
        }
    }

    private func stopVoiceCommandRecording(language: Language) async {
        // Stop the VAD monitor timer
        vadMonitorTimer?.invalidate()
        vadMonitorTimer = nil

        // Stop recording
        await stopRecording(mode: .vad, language: language)

        // Clear voice command flag
        AppState.shared.isVoiceCommandTriggered = false
    }

    private func startStreamingTimer(language: Language) {
        streamingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.transcribeStreamingBuffer(language: language)
            }
        }
    }

    private func transcribeStreamingBuffer(language: Language) async {
        guard !isTranscribing,
            let startTime = recordingStartTime,
            Date().timeIntervalSince(startTime) > 1.0
        else {
            return
        }

        let samples = audioRecorder.getAudioSamples()
        guard samples.count > Int(16000 / 2) else { return }  // At least 0.5s

        isTranscribing = true
        defer { isTranscribing = false }

        do {
            let lang = language.isAuto ? nil : language
            let text = try await activeTranscriber.transcribe(
                samples: samples,
                sampleRate: 16000,
                language: lang
            )

            if !text.isEmpty && text != lastTypedText {
                let newText = getNewText(previous: lastTypedText, current: text)
                if !newText.isEmpty {
                    do {
                        try await textInserter.insertText(newText)
                        lastTypedText = text
                        currentTranscription = text
                    } catch {
                        logger.error("Text insertion failed", error: error)
                        // Fallback: copy to clipboard
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(newText, forType: .string)
                        AppState.shared.errorMessage = "Text copied to clipboard (insertion failed)"
                    }
                }
            }
        } catch {
            logger.error("Streaming transcription failed", error: error)
        }
    }

    private func transcribeFinalAudio(mode: TranscriptionMode, language: Language) async {
        let samples = audioRecorder.getAudioSamples()
        let startTime = Date()

        // Need at least 0.3 seconds of audio
        guard samples.count > Int(16000 * 0.3) else {
            logger.info("Audio too short: \(samples.count) samples")
            return
        }

        // Mark pipeline as processing to prevent new recordings
        isPipelineProcessing = true
        defer { isPipelineProcessing = false }

        do {
            _ = try await audioRecorder.stopRecording()

            let lang = language.isAuto ? nil : language
            let rawText = try await activeTranscriber.transcribe(
                samples: samples,
                sampleRate: 16000,
                language: lang
            )

            let transcribedText = rawText.trimmingCharacters(in: .whitespaces)

            guard !transcribedText.isEmpty else {
                return
            }

            // Use pipeline for post-transcription processing
            // Pipeline handles: Language Improvement → Prompt Optimizer → Auto Type → Auto Enter
            if AppState.shared.isRefinementEnabled {
                AppState.shared.recordingState = .refining
                RecordingOverlayController.shared.updateFromService(audioLevel: 0, state: .refining)

                // Configure AI service with current tier
                await configureRefinement()
            }

            var finalText = transcribedText
            var wasRefined = false
            var refinementDuration: TimeInterval = 0
            var pipelineRunId: UUID? = nil

            do {
                let result = try await PipelineManager.shared.processText(transcribedText)
                finalText = result.processedText
                wasRefined = result.wasRefined
                refinementDuration = result.summary.elapsedTime
                pipelineRunId = result.pipelineRunId

                if wasRefined {
                    logger.info(
                        "Pipeline completed: \(transcribedText.count) → \(finalText.count) chars in \(result.summary.formattedElapsedTime)"
                    )
                }

                // Pipeline handles text insertion and auto-enter
                // Play success sound
                NSSound(named: "Pop")?.play()

            } catch let targetError as PipelineManager.TargetLostError {
                // Target was lost (user switched apps) - don't try fallback insertion
                // Sound already played by PipelineManager, just copy to clipboard
                logger.warning("Target lost: \(targetError.reason) - copying to clipboard instead")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcribedText, forType: .string)
                AppState.shared.errorMessage = "Target lost - text copied to clipboard (Cmd+V to paste)"

            } catch {
                logger.error("Pipeline failed, falling back to direct insertion", error: error)

                // Fallback: insert text directly
                do {
                    if mode == .realtime {
                        let newText = getNewText(previous: lastTypedText, current: transcribedText)
                        if !newText.isEmpty {
                            try await textInserter.insertText(newText)
                        }
                    } else {
                        try await textInserter.insertText(transcribedText)
                    }

                    if AppState.shared.isAutoEnterEnabled {
                        try await textInserter.pressEnter()
                    }

                    NSSound(named: "Pop")?.play()
                } catch {
                    // Last resort: copy to clipboard
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcribedText, forType: .string)
                    AppState.shared.errorMessage = "Text copied to clipboard (press Cmd+V to paste)"
                    NSSound(named: "Funk")?.play()
                }
            }

            accumulatedTranscription = finalText
            currentTranscription = finalText

            // Save to transcription history
            let duration = Date().timeIntervalSince(startTime)
            let settings =
                wasRefined
                ? RefinementSettings(
                    cleanup: AppState.shared.isCleanupEnabled,
                    tone: AppState.shared.toneStyle,
                    promptMode: AppState.shared.isPromptImproverEnabled,
                    customInstructions: AppState.shared.customRefinementPrompt.isEmpty
                        ? nil : AppState.shared.customRefinementPrompt,
                    aiTier: AppState.shared.currentAITier.rawValue,
                    durationSeconds: refinementDuration
                ) : nil
            AppState.shared.addTranscription(
                finalText,
                duration: duration,
                wasRefined: wasRefined,
                originalText: wasRefined ? transcribedText : nil,
                refinementSettings: settings,
                pipelineRunId: pipelineRunId
            )
        } catch {
            logger.error("Final transcription failed", error: error)
            AppState.shared.errorMessage = "Transcription failed: \(error.localizedDescription)"
        }
    }

    private func getNewText(previous: String, current: String) -> String {
        if previous.isEmpty { return current }
        if current.hasPrefix(previous) {
            return String(current.dropFirst(previous.count))
        }
        return current
    }

    // MARK: - Refinement Prompt Building

    /// Build combined system prompt from enabled refinement options
    private func buildRefinementPrompt() -> String {
        var tasks: [String] = []

        // Collect what to do
        if AppState.shared.isCleanupEnabled {
            tasks.append("fix grammar, remove filler words like um/uh/like/you know")
        }

        if AppState.shared.isPromptImproverEnabled {
            tasks.append("reformat as a clear AI prompt with good structure")
        } else {
            switch AppState.shared.toneStyle {
            case "formal":
                tasks.append("make it formal and professional")
            case "casual":
                tasks.append("make it casual and friendly")
            default:
                break
            }
        }

        let custom = AppState.shared.customRefinementPrompt
        if !custom.isEmpty {
            tasks.append(custom)
        }

        let taskList = tasks.isEmpty ? "clean up the text" : tasks.joined(separator: ", ")

        // Simple, direct prompt that small models can follow
        return """
            Edit this text: \(taskList).
            Reply with ONLY the edited text. No explanations. No quotes. Just the text.
            """
    }

    /// Build summary of enabled options for logging
    private func buildRefinementSummary() -> String {
        var parts: [String] = []

        if AppState.shared.isCleanupEnabled {
            parts.append("cleanup")
        }

        if AppState.shared.isPromptImproverEnabled {
            parts.append("prompt")
        } else if AppState.shared.toneStyle != "none" {
            parts.append(AppState.shared.toneStyle)
        }

        if !AppState.shared.customRefinementPrompt.isEmpty {
            parts.append("custom")
        }

        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }
}

// Note: reloadModel notification is defined in KoeApp.swift
