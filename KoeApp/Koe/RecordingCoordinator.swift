import SwiftUI
import AppKit
import KoeDomain
import KoeAudio
import KoeTranscription
import KoeTextInsertion
import KoeHotkey
import KoeCore

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
    private let transcriber: WhisperKitTranscriber
    private let textInserter: TextInsertionServiceImpl
    private let vadProcessor: VADProcessor
    private let hotkeyManager: KoeHotkeyManager

    // MARK: - State
    public private(set) var isRecording = false
    public private(set) var audioLevel: Float = 0.0
    public private(set) var currentTranscription: String = ""

    // Recording state
    private var recordingStartTime: Date?
    private var levelTimer: Timer?
    private var streamingTimer: Timer?
    private var isTranscribing = false

    // Transcription state
    private var accumulatedTranscription = ""
    private var lastTypedText = ""

    private let logger = KoeLogger.audio

    // MARK: - Initialization

    public init(
        audioRecorder: AVAudioEngineRecorder = AVAudioEngineRecorder(),
        transcriber: WhisperKitTranscriber = WhisperKitTranscriber(),
        textInserter: TextInsertionServiceImpl = TextInsertionServiceImpl(),
        vadProcessor: VADProcessor = VADProcessor(),
        hotkeyManager: KoeHotkeyManager = KoeHotkeyManager()
    ) {
        self.audioRecorder = audioRecorder
        self.transcriber = transcriber
        self.textInserter = textInserter
        self.vadProcessor = vadProcessor
        self.hotkeyManager = hotkeyManager
    }

    // MARK: - Hotkey Setup

    public func setupHotkey() {
        hotkeyManager.register(
            onKeyDown: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    let mode = TranscriptionMode(rawValue: AppState.shared.transcriptionMode) ?? .vad
                    let langCode = AppState.shared.selectedLanguage
                    let language = Language.all.first { $0.code == langCode } ?? .auto
                    await self.startRecording(mode: mode, language: language)
                }
            },
            onKeyUp: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    let mode = TranscriptionMode(rawValue: AppState.shared.transcriptionMode) ?? .vad
                    let langCode = AppState.shared.selectedLanguage
                    let language = Language.all.first { $0.code == langCode } ?? .auto
                    await self.stopRecording(mode: mode, language: language)
                }
            }
        )
        logger.info("Hotkey registered: Option+Space")
    }

    public func unregisterHotkey() {
        hotkeyManager.unregister()
    }

    // MARK: - Deferred Initialization

    /// Called when app reaches .ready state to finish initialization
    public func initializeWhenReady() {
        // Request accessibility permission when ready
        if !textInserter.hasPermission() {
            textInserter.requestPermission()
        }
    }

    // MARK: - Model Loading

    public var isModelLoaded: Bool {
        transcriber.isReady
    }

    public var modelLoadingProgress: Double {
        transcriber.loadingProgress
    }

    public func loadModel(_ model: KoeModel) async {
        logger.info("Loading model: \(model.rawValue)")
        do {
            try await transcriber.loadModel(model)
            AppState.shared.isModelLoaded = true
            NotificationCenter.default.post(name: .modelLoaded, object: nil)
            logger.info("Model loaded successfully")
        } catch {
            logger.error("Failed to load model", error: error)
        }
    }

    public func loadModel(name: String) async {
        let model = KoeModel(rawValue: name) ?? .tiny
        await loadModel(model)
    }

    public func unloadModel() {
        transcriber.unloadModel()
        AppState.shared.isModelLoaded = false
    }

    // MARK: - Recording

    public func startRecording(mode: TranscriptionMode, language: Language) async {
        guard transcriber.isReady else {
            logger.warning("Cannot start recording - model not loaded")
            AppState.shared.errorMessage = "Model still loading..."
            NSSound(named: "Basso")?.play()
            return
        }

        guard !isRecording else { return }

        logger.info("Starting recording - mode: \(mode.rawValue), language: \(language.code)")

        // Reset state
        resetRecordingState()
        recordingStartTime = Date()

        do {
            try await audioRecorder.startRecording()
            isRecording = true

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
        streamingTimer?.invalidate()
        streamingTimer = nil

        isRecording = false
        audioLevel = 0

        // Update AppState to processing
        AppState.shared.recordingState = .processing
        RecordingOverlayController.shared.updateFromService(audioLevel: 0, state: .processing)

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
              Date().timeIntervalSince(startTime) > 1.0 else {
            return
        }

        let samples = audioRecorder.getAudioSamples()
        guard samples.count > Int(16000 / 2) else { return } // At least 0.5s

        isTranscribing = true
        defer { isTranscribing = false }

        do {
            let lang = language.isAuto ? nil : language
            let text = try await transcriber.transcribe(
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

        // Need at least 0.3 seconds of audio
        guard samples.count > Int(16000 * 0.3) else {
            logger.info("Audio too short: \(samples.count) samples")
            return
        }

        let startTime = Date()

        do {
            _ = try await audioRecorder.stopRecording()

            let lang = language.isAuto ? nil : language
            let text = try await transcriber.transcribe(
                samples: samples,
                sampleRate: 16000,
                language: lang
            )

            if !text.isEmpty {
                let cleanText = text.trimmingCharacters(in: .whitespaces)
                var insertionSucceeded = false

                do {
                    if mode == .realtime {
                        // Type only new text not already typed
                        let newText = getNewText(previous: lastTypedText, current: cleanText)
                        if !newText.isEmpty {
                            try await textInserter.insertText(newText)
                            insertionSucceeded = true
                        }
                    } else {
                        // VAD mode - paste all text at once
                        try await textInserter.insertText(cleanText)
                        insertionSucceeded = true
                    }
                } catch {
                    logger.error("Text insertion failed", error: error)
                    // Fallback: copy to clipboard
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cleanText, forType: .string)
                    AppState.shared.errorMessage = "Text copied to clipboard (press Cmd+V to paste)"
                    NSSound(named: "Funk")?.play()
                }

                accumulatedTranscription = cleanText
                currentTranscription = cleanText

                // Save to history
                let duration = Date().timeIntervalSince(startTime)
                AppState.shared.addTranscription(cleanText, duration: duration)

                // Play success sound if insertion worked
                if insertionSucceeded {
                    NSSound(named: "Pop")?.play()
                }
            }
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
}

// Note: reloadModel notification is defined in KoeApp.swift
