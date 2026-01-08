import AVFoundation
import CoreAudio
import Foundation
import os.log
import Speech

private let logger = Logger(subsystem: "com.koe.voice", category: "CommandListener")

/// Errors that can occur during command listening
public enum CommandListenerError: Error, LocalizedError {
    case speechRecognitionNotAvailable
    case speechRecognitionNotAuthorized
    case audioEngineError(Error)
    case recognitionFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .speechRecognitionNotAvailable:
            return "Speech recognition is not available on this device"
        case .speechRecognitionNotAuthorized:
            return "Speech recognition is not authorized"
        case .audioEngineError(let error):
            return "Audio engine error: \(error.localizedDescription)"
        case .recognitionFailed(let error):
            return "Recognition failed: \(error.localizedDescription)"
        }
    }
}

/// Delegate for receiving command listener events
public protocol CommandListenerDelegate: AnyObject, Sendable {
    /// Called when text is detected from speech
    func commandListener(_ listener: CommandListener, didDetectText text: String, audioSamples: [Float])

    /// Called when the listener starts
    func commandListenerDidStart(_ listener: CommandListener)

    /// Called when the listener stops
    func commandListenerDidStop(_ listener: CommandListener)

    /// Called when an error occurs
    func commandListener(_ listener: CommandListener, didEncounterError error: CommandListenerError)
}

/// Background listener that uses SFSpeechRecognizer for voice command detection
public final class CommandListener: NSObject, @unchecked Sendable {
    // MARK: - Properties

    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private let lock = NSLock()
    private var _isListening = false
    private var _isPaused = false  // Paused due to another app using mic
    private var audioSampleBuffer: [Float] = []
    private let maxBufferDuration: TimeInterval = 5.0  // Keep last 5 seconds
    private let sampleRate: Double = 16000
    private var microphoneMonitorTimer: Timer?

    public weak var delegate: CommandListenerDelegate?

    /// Whether listening is paused (another app is using microphone)
    public var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isPaused
    }

    /// Callback for text detection (alternative to delegate)
    public var onTextDetected: ((String, [Float]) -> Void)?

    /// Callback for errors
    public var onError: ((CommandListenerError) -> Void)?

    /// Whether the listener is currently active
    public var isListening: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isListening
    }

    // MARK: - Initialization

    public override init() {
        // Use device locale for better recognition
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        super.init()
    }

    public init(locale: Locale) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
        super.init()
    }

    // MARK: - Public Methods

    /// Request speech recognition authorization
    public func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Start listening for voice commands
    public func startListening() async throws {
        logger.notice("[CommandListener] Starting voice command listener...")

        guard let speechRecognizer = speechRecognizer else {
            logger.notice("[CommandListener] ERROR: Speech recognizer not available")
            let error = CommandListenerError.speechRecognitionNotAvailable
            onError?(error)
            delegate?.commandListener(self, didEncounterError: error)
            throw error
        }

        logger.notice("[CommandListener] Speech recognizer locale: \(speechRecognizer.locale.identifier)")
        logger.notice("[CommandListener] On-device recognition supported: \(speechRecognizer.supportsOnDeviceRecognition)")

        guard speechRecognizer.isAvailable else {
            logger.notice("[CommandListener] ERROR: Speech recognizer not available")
            let error = CommandListenerError.speechRecognitionNotAvailable
            onError?(error)
            delegate?.commandListener(self, didEncounterError: error)
            throw error
        }

        // Check authorization
        let status = await requestAuthorization()
        logger.notice("[CommandListener] Authorization status: \(status.rawValue)")
        guard status == .authorized else {
            logger.notice("[CommandListener] ERROR: Speech recognition not authorized")
            let error = CommandListenerError.speechRecognitionNotAuthorized
            onError?(error)
            delegate?.commandListener(self, didEncounterError: error)
            throw error
        }

        // Stop any existing session
        stopListening()

        lock.lock()
        _isListening = true
        audioSampleBuffer.removeAll()
        lock.unlock()

        do {
            try await startRecognition()
            logger.notice("[CommandListener] ✓ Listening started successfully")
            delegate?.commandListenerDidStart(self)
        } catch {
            logger.notice("[CommandListener] ERROR: Failed to start recognition: \(error)")
            lock.lock()
            _isListening = false
            lock.unlock()

            let listenerError = CommandListenerError.audioEngineError(error)
            onError?(listenerError)
            delegate?.commandListener(self, didEncounterError: listenerError)
            throw listenerError
        }
    }

    /// Stop listening for voice commands
    public func stopListening() {
        lock.lock()
        let wasListening = _isListening
        _isListening = false
        lock.unlock()

        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        if wasListening {
            delegate?.commandListenerDidStop(self)
        }
    }

    // MARK: - Private Methods

    private func startRecognition() async throws {
        guard let speechRecognizer = speechRecognizer else { return }

        // Note: AVAudioSession is not available on macOS
        // Audio configuration is handled by AVAudioEngine directly

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else { return }

        // Configure for on-device recognition (privacy + low latency)
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition

        // Add context hints for better recognition of "kon" and "koe"
        recognitionRequest.contextualStrings = [
            "kon", "Kon", "KON", "kong", "Kong", "con", "Con",
            "koe", "Koe", "KOE", "koi", "Koi", "coy", "Coy"
        ]

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        logger.notice("[CommandListener] Audio format: \(recordingFormat.sampleRate, privacy: .public) Hz, \(recordingFormat.channelCount, privacy: .public) channels")

        // Install tap on audio input
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            [weak self] buffer, _ in
            guard let self = self else { return }

            // Append to recognition request
            self.recognitionRequest?.append(buffer)

            // Also store samples for voice verification
            self.appendAudioSamples(from: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        logger.notice("[CommandListener] Audio engine started, beginning speech recognition...")

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) {
            [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                // Check if this is just a cancellation
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                    // Recognition was cancelled, not an error
                    return
                }

                let listenerError = CommandListenerError.recognitionFailed(error)
                self.onError?(listenerError)
                self.delegate?.commandListener(self, didEncounterError: listenerError)

                // Restart if we're still supposed to be listening
                if self.isListening {
                    Task {
                        try? await self.restartRecognition()
                    }
                }
                return
            }

            if let result = result {
                let text = result.bestTranscription.formattedString

                // Log all detected text for debugging (public for visibility)
                logger.notice("[CommandListener] Heard: \"\(text, privacy: .public)\" (final: \(result.isFinal))")

                // Get recent audio samples for voice verification
                self.lock.lock()
                let samples = Array(self.audioSampleBuffer)
                self.lock.unlock()

                // Notify about detected text
                self.onTextDetected?(text, samples)
                self.delegate?.commandListener(self, didDetectText: text, audioSamples: samples)

                // If final result, restart recognition for continuous listening
                if result.isFinal && self.isListening {
                    Task {
                        try? await self.restartRecognition()
                    }
                }
            }
        }
    }

    private func restartRecognition() async throws {
        // Brief pause before restarting
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        guard isListening else { return }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        try await startRecognition()
    }

    private func appendAudioSamples(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        var samples = [Float](repeating: 0, count: frameLength)
        for i in 0..<frameLength {
            samples[i] = channelData[i]
        }

        lock.lock()
        defer { lock.unlock() }

        audioSampleBuffer.append(contentsOf: samples)

        // Trim buffer to max duration
        let maxSamples = Int(maxBufferDuration * sampleRate)
        if audioSampleBuffer.count > maxSamples {
            audioSampleBuffer.removeFirst(audioSampleBuffer.count - maxSamples)
        }
    }

    // MARK: - Microphone Sharing Detection

    /// Check if another app is likely using the microphone (meeting/call apps)
    public func isOtherAppUsingMicrophone() -> Bool {
        // List of bundle identifiers for apps that commonly use microphone
        let meetingAppBundleIds = [
            "us.zoom.xos",           // Zoom
            "com.microsoft.teams",   // Microsoft Teams
            "com.microsoft.teams2",  // Microsoft Teams (new)
            "com.apple.FaceTime",    // FaceTime
            "com.skype.skype",       // Skype
            "com.google.Chrome",     // Chrome (for web meetings)
            "com.apple.Safari",      // Safari (for web meetings)
            "com.discord.Discord",   // Discord
            "com.slack.Slack",       // Slack
            "com.webex.meetingmanager", // Webex
            "com.cisco.webexmeetings",  // Webex
            "com.gotomeeting.GoToMeeting", // GoToMeeting
        ]

        // Check if any of these apps are actively using audio input
        // by checking if they have the microphone in use
        return checkMicrophoneInUseByOtherApp(excludingBundleIds: ["com.koe.voice"])
    }

    /// Check if the default input device is being used by another process
    private func checkMicrophoneInUseByOtherApp(excludingBundleIds: [String]) -> Bool {
        var deviceId = AudioObjectID(kAudioObjectSystemObject)
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)

        // Get the default input device
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceId
        )

        guard status == noErr else {
            return false
        }

        // Check if the device is running (being used by any app including us)
        var isRunning: UInt32 = 0
        propertySize = UInt32(MemoryLayout<UInt32>.size)
        propertyAddress.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere

        let runningStatus = AudioObjectGetPropertyData(
            deviceId,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &isRunning
        )

        guard runningStatus == noErr else {
            return false
        }

        // If device is running and we're not the only one using it
        // This is a heuristic - if device is running and we detect
        // more than one audio tap, another app is using it
        if isRunning > 0 {
            // Check number of streams
            var streamCount: UInt32 = 0
            propertySize = 0
            propertyAddress.mSelector = kAudioDevicePropertyStreams
            propertyAddress.mScope = kAudioDevicePropertyScopeInput

            AudioObjectGetPropertyDataSize(
                deviceId,
                &propertyAddress,
                0,
                nil,
                &propertySize
            )

            streamCount = propertySize / UInt32(MemoryLayout<AudioStreamID>.size)

            // If there are multiple input streams, another app might be using mic
            // This is a rough heuristic
            return streamCount > 1
        }

        return false
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension CommandListener: SFSpeechRecognizerDelegate {
    public func speechRecognizer(
        _ speechRecognizer: SFSpeechRecognizer,
        availabilityDidChange available: Bool
    ) {
        if !available && isListening {
            stopListening()
            let error = CommandListenerError.speechRecognitionNotAvailable
            onError?(error)
            delegate?.commandListener(self, didEncounterError: error)
        }
    }
}
