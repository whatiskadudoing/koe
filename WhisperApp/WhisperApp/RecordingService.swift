import AVFoundation
import SwiftUI
import WhisperKit
import ApplicationServices

// Simple file logger
func logToFile(_ message: String) {
    let logPath = "/tmp/whisper_debug.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] \(message)\n"

    if let data = logMessage.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath) {
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logPath, contents: data, attributes: nil)
        }
    }
}

@MainActor
class RecordingService: ObservableObject {
    static let shared = RecordingService()

    @Published var audioLevel: Float = 0.0

    // AVAudioEngine for real-time audio capture
    private var audioEngine: AVAudioEngine?
    private var audioBuffers: [Float] = []
    private var audioBufferLock = NSLock()

    private var levelTimer: Timer?
    private var streamingTimer: Timer?  // For real-time mode
    private var transcriber: TranscriberService?
    private var isTranscribing: Bool = false
    private var recordingStartTime: Date?

    // VAD (Voice Activity Detection) parameters
    private var speechStartSampleIndex: Int = 0
    private var lastTranscribedSampleIndex: Int = 0  // Track what's been transcribed
    private var lastSpeechEndTime: Date?
    private var isSpeaking: Bool = false
    private var accumulatedTranscription: String = ""

    // Real-time mode parameters
    private var lastTypedText: String = ""

    // VAD thresholds - tuned to avoid fragmenting speech
    private let silenceThreshold: Float = 0.012  // RMS threshold for silence detection (lower = less sensitive)
    private let silenceDuration: TimeInterval = 1.2  // Seconds of silence to trigger transcription (longer = less fragmentation)
    private let minSpeechDuration: TimeInterval = 0.5  // Minimum speech duration to transcribe

    private let sampleRate: Double = 16000
    private let bufferSize: AVAudioFrameCount = 1024

    private init() {
        logToFile("RecordingService initialized")
        setupAudioSession()
        requestAccessibilityPermission()
    }

    private func requestAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        logToFile("Accessibility permission: \(trusted)")

        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            logToFile("Requested accessibility permission from user")
        }
    }

    func setTranscriber(_ transcriber: TranscriberService) {
        self.transcriber = transcriber
    }

    private func setupAudioSession() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                logToFile("❌ Microphone permission denied")
            }
        }
    }

    func startRecording() {
        logToFile("🎤 startRecording called")

        guard transcriber?.isLoaded == true else {
            logToFile("❌ Model not loaded yet")
            AppState.shared.errorMessage = "Model still loading..."
            // Play error sound to notify user
            NSSound(named: "Basso")?.play()
            return
        }

        logToFile("✅ Model is loaded, starting recording with AVAudioEngine")

        // Reset state
        audioBufferLock.lock()
        audioBuffers = []
        audioBufferLock.unlock()
        speechStartSampleIndex = 0
        lastTranscribedSampleIndex = 0
        lastSpeechEndTime = nil
        isSpeaking = false
        accumulatedTranscription = ""
        lastTypedText = ""
        recordingStartTime = Date()

        let isRealtimeMode = AppState.shared.transcriptionMode == "realtime"
        let language = AppState.shared.selectedLanguage
        logToFile("📋 Mode: \(isRealtimeMode ? "Real-time" : "VAD")")
        logToFile("📋 Language: \(language)")

        // Setup AVAudioEngine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            logToFile("❌ Failed to create AVAudioEngine")
            return
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Convert to 16kHz mono for Whisper
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                sampleRate: sampleRate,
                                                channels: 1,
                                                interleaved: false) else {
            logToFile("❌ Failed to create output format")
            return
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            logToFile("❌ Failed to create audio converter")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer: buffer, converter: converter, outputFormat: outputFormat)
        }

        do {
            try audioEngine.start()
            logToFile("✅ AVAudioEngine started")

            AppState.shared.recordingState = .recording
            AppState.shared.currentTranscription = ""

            RecordingOverlayController.shared.updateFromService(audioLevel: 0, state: .recording)

            // Audio level timer (always runs for UI)
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateAudioLevel()
                }
            }

            if isRealtimeMode {
                // Real-time mode: streaming transcription every 1.5 seconds
                streamingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        await self?.transcribeRealtimeBuffer()
                    }
                }
            }
            // On-release mode: no streaming timer - just record, transcribe on release

        } catch {
            logToFile("❌ Failed to start AVAudioEngine: \(error)")
            AppState.shared.errorMessage = "Recording failed: \(error.localizedDescription)"
        }
    }

    private func processAudioBuffer(buffer: AVAudioPCMBuffer, converter: AVAudioConverter, outputFormat: AVAudioFormat) {
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / buffer.format.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            logToFile("❌ Conversion error: \(error)")
            return
        }

        guard let floatData = convertedBuffer.floatChannelData?[0] else { return }
        let frameLength = Int(convertedBuffer.frameLength)

        audioBufferLock.lock()
        for i in 0..<frameLength {
            audioBuffers.append(floatData[i])
        }
        audioBufferLock.unlock()
    }

    // Simple audio level update for real-time mode
    private func updateAudioLevel() {
        audioBufferLock.lock()
        let recentSamples = Array(audioBuffers.suffix(1600))
        audioBufferLock.unlock()

        guard !recentSamples.isEmpty else { return }

        let rms = sqrt(recentSamples.map { $0 * $0 }.reduce(0, +) / Float(recentSamples.count))
        let db = 20 * log10(max(rms, 0.0001))
        let normalizedLevel = max(0, min(1, (db + 50) / 50))

        audioLevel = normalizedLevel
        RecordingOverlayController.shared.updateFromService(audioLevel: normalizedLevel, state: .recording)

        // Notify menu bar for waveform animation
        NotificationCenter.default.post(name: .audioLevelChanged, object: normalizedLevel)
    }

    // VAD mode: audio level + voice activity detection
    private func updateAudioLevelAndCheckVAD() {
        audioBufferLock.lock()
        let recentSamples = Array(audioBuffers.suffix(1600)) // Last 0.1 seconds
        let totalSamples = audioBuffers.count
        audioBufferLock.unlock()

        guard !recentSamples.isEmpty else { return }

        // Calculate RMS for audio level display
        let rms = sqrt(recentSamples.map { $0 * $0 }.reduce(0, +) / Float(recentSamples.count))
        let db = 20 * log10(max(rms, 0.0001))
        let normalizedLevel = max(0, min(1, (db + 50) / 50))

        audioLevel = normalizedLevel
        RecordingOverlayController.shared.updateFromService(audioLevel: normalizedLevel, state: .recording)

        // VAD: Voice Activity Detection
        let isSpeakingNow = rms > silenceThreshold

        if isSpeakingNow {
            // Speech detected
            if !isSpeaking {
                // Speech just started
                isSpeaking = true
                speechStartSampleIndex = totalSamples
                logToFile("🎤 VAD: Speech started at sample \(totalSamples)")
            }
            lastSpeechEndTime = nil  // Reset silence timer
        } else {
            // Silence detected
            if isSpeaking {
                // Was speaking, now silent
                if lastSpeechEndTime == nil {
                    lastSpeechEndTime = Date()
                    logToFile("🔇 VAD: Silence started")
                } else if let silenceStart = lastSpeechEndTime,
                          Date().timeIntervalSince(silenceStart) >= silenceDuration {
                    // Silence has been long enough - trigger transcription
                    let speechSamples = totalSamples - speechStartSampleIndex
                    let speechDuration = Double(speechSamples) / sampleRate

                    if speechDuration >= minSpeechDuration && !isTranscribing {
                        logToFile("🎯 VAD: Triggering transcription after \(String(format: "%.1f", speechDuration))s of speech")
                        isSpeaking = false
                        lastSpeechEndTime = nil

                        Task {
                            await transcribeSpeechSegment(startIndex: speechStartSampleIndex, endIndex: totalSamples)
                        }
                    }
                }
            }
        }
    }

    private func transcribeSpeechSegment(startIndex: Int, endIndex: Int) async {
        guard !isTranscribing, let transcriber = transcriber else { return }

        audioBufferLock.lock()
        let allSamples = audioBuffers
        audioBufferLock.unlock()

        // Include some context before speech start (0.2s)
        let contextSamples = Int(sampleRate * 0.2)
        let actualStart = max(0, startIndex - contextSamples)
        let segmentSamples = Array(allSamples[actualStart..<min(endIndex, allSamples.count)])

        guard !segmentSamples.isEmpty else { return }

        isTranscribing = true
        let duration = Double(segmentSamples.count) / sampleRate
        logToFile("🎙️ VAD transcription: \(segmentSamples.count) samples (\(String(format: "%.1f", duration))s)")

        do {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("vad_\(UUID().uuidString).wav")
            try writeWAVFile(samples: segmentSamples, to: tempURL)

            let text = try await transcriber.transcribe(
                audioURL: tempURL,
                language: AppState.shared.selectedLanguage == "auto" ? nil : AppState.shared.selectedLanguage
            )

            try? FileManager.default.removeItem(at: tempURL)

            logToFile("🎙️ VAD result: \(text)")

            if !text.isEmpty {
                let separator = accumulatedTranscription.isEmpty ? "" : " "
                let cleanText = text.trimmingCharacters(in: .whitespaces)

                logToFile("📝 Typing: \(cleanText)")
                typeTextInBackground(separator + cleanText)

                accumulatedTranscription += separator + cleanText
                AppState.shared.currentTranscription = accumulatedTranscription
            }

            // Mark this segment as transcribed
            lastTranscribedSampleIndex = endIndex
        } catch {
            logToFile("🎙️ VAD transcription error: \(error)")
        }

        isTranscribing = false
    }

    // Real-time mode: transcribe all accumulated audio and type new text
    private func transcribeRealtimeBuffer() async {
        guard !isTranscribing,
              let startTime = recordingStartTime,
              Date().timeIntervalSince(startTime) > 1.0,
              let transcriber = transcriber else {
            return
        }

        audioBufferLock.lock()
        let currentSamples = audioBuffers
        audioBufferLock.unlock()

        // Need at least 0.5 seconds of audio
        guard currentSamples.count > Int(sampleRate / 2) else { return }

        isTranscribing = true
        logToFile("🔄 Real-time transcription with \(currentSamples.count) samples")

        do {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("realtime_\(UUID().uuidString).wav")
            try writeWAVFile(samples: currentSamples, to: tempURL)

            let text = try await transcriber.transcribe(
                audioURL: tempURL,
                language: AppState.shared.selectedLanguage == "auto" ? nil : AppState.shared.selectedLanguage
            )

            try? FileManager.default.removeItem(at: tempURL)

            logToFile("🔄 Real-time result: \(text)")

            if !text.isEmpty && text != lastTypedText {
                let newText = getNewText(previous: lastTypedText, current: text)
                if !newText.isEmpty {
                    logToFile("📝 Typing new: \(newText)")
                    typeTextInBackground(newText)
                    lastTypedText = text
                    AppState.shared.currentTranscription = text
                }
            }
        } catch {
            logToFile("🔄 Real-time transcription error: \(error)")
        }

        isTranscribing = false
    }

    // Helper to find new text that hasn't been typed yet
    private func getNewText(previous: String, current: String) -> String {
        if previous.isEmpty {
            return current
        }
        if current.hasPrefix(previous) {
            return String(current.dropFirst(previous.count))
        }
        // Text diverged - Whisper corrected something
        // Just return the new text (this can cause duplicates but is safer)
        return current
    }

    func stopRecording() {
        logToFile("🛑 stopRecording called")

        levelTimer?.invalidate()
        levelTimer = nil
        streamingTimer?.invalidate()
        streamingTimer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        audioLevel = 0.0
        logToFile("🛑 Processing final audio...")
        AppState.shared.recordingState = .processing
        RecordingOverlayController.shared.updateFromService(audioLevel: 0, state: .processing)

        Task {
            await transcribeFinalBuffer()
        }
    }

    private func transcribeFinalBuffer() async {
        while isTranscribing {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        audioBufferLock.lock()
        let totalSamples = audioBuffers.count
        let allSamples = audioBuffers
        audioBufferLock.unlock()

        guard !allSamples.isEmpty, let transcriber = transcriber else {
            AppState.shared.recordingState = .idle
            RecordingOverlayController.shared.updateFromService(audioLevel: 0, state: .idle)
            return
        }

        let startTime = Date()
        let isRealtimeMode = AppState.shared.transcriptionMode == "realtime"

        if isRealtimeMode {
            // Real-time mode: do final full transcription for accuracy
            logToFile("🏁 Final transcription (real-time mode): \(totalSamples) samples")

            if totalSamples > Int(sampleRate * 0.3) {
                do {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("final_\(UUID().uuidString).wav")
                    try writeWAVFile(samples: allSamples, to: tempURL)

                    let text = try await transcriber.transcribe(
                        audioURL: tempURL,
                        language: AppState.shared.selectedLanguage == "auto" ? nil : AppState.shared.selectedLanguage
                    )

                    try? FileManager.default.removeItem(at: tempURL)

                    logToFile("🏁 Final result: \(text)")

                    // Type any remaining text that wasn't typed in streaming
                    if !text.isEmpty && text != lastTypedText {
                        let newText = getNewText(previous: lastTypedText, current: text)
                        if !newText.isEmpty {
                            logToFile("📝 Final typing: \(newText)")
                            typeTextInBackground(newText)
                        }
                        accumulatedTranscription = text
                    }
                } catch {
                    logToFile("🏁 Final transcription error: \(error)")
                }
            }
        } else {
            // On-release mode: transcribe ALL audio at once for best accuracy
            logToFile("🏁 On-release mode: transcribing all \(totalSamples) samples")

            if totalSamples > Int(sampleRate * 0.3) {
                do {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("final_\(UUID().uuidString).wav")
                    try writeWAVFile(samples: allSamples, to: tempURL)

                    let text = try await transcriber.transcribe(
                        audioURL: tempURL,
                        language: AppState.shared.selectedLanguage == "auto" ? nil : AppState.shared.selectedLanguage
                    )

                    try? FileManager.default.removeItem(at: tempURL)

                    logToFile("🏁 Final result: \(text)")

                    if !text.isEmpty {
                        let cleanText = text.trimmingCharacters(in: .whitespaces)
                        logToFile("📝 Typing all: \(cleanText)")
                        // Use instant paste for on-release mode (faster)
                        typeTextInBackground(cleanText, usePaste: true)
                        accumulatedTranscription = cleanText
                    }
                } catch {
                    logToFile("🏁 Final transcription error: \(error)")
                }
            } else {
                logToFile("🏁 Audio too short: \(totalSamples) samples")
            }
        }

        let duration = Date().timeIntervalSince(startTime)

        // Save full transcription to history
        if !accumulatedTranscription.isEmpty {
            AppState.shared.currentTranscription = accumulatedTranscription
            AppState.shared.addTranscription(accumulatedTranscription, duration: duration)
        }

        RecordingOverlayController.shared.updateFromService(audioLevel: 0, state: .idle)
        AppState.shared.recordingState = .idle
        isSpeaking = false
        lastTypedText = ""
        accumulatedTranscription = ""
    }

    private func writeWAVFile(samples: [Float], to url: URL) throws {
        let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)

        let channelData = buffer.floatChannelData![0]
        for (index, sample) in samples.enumerated() {
            channelData[index] = sample
        }

        let audioFile = try AVAudioFile(forWriting: url, settings: audioFormat.settings)
        try audioFile.write(from: buffer)
    }

    private func typeTextInBackground(_ text: String, usePaste: Bool = false) {
        // Run typing on background thread to not block UI
        let textToType = text
        DispatchQueue.global(qos: .userInteractive).async {
            Self.typeText(textToType, preferPaste: usePaste)
        }
    }

    nonisolated private static func typeText(_ text: String, preferPaste: Bool = false) {
        logToFile("📝 Typing text: \(text)")

        // For long text or when paste is preferred, use clipboard (instant)
        if preferPaste || text.count > 50 {
            logToFile("⚡ Using instant paste for \(text.count) characters")
            typeWithClipboard(text)
            return
        }

        // For short text, try CGEvents (looks more natural)
        if typeWithCGEvents(text) {
            logToFile("✅ Finished typing \(text.count) characters with CGEvents")
            return
        }

        // Fallback to clipboard + paste
        logToFile("⚠️ CGEvents failed, using clipboard fallback")
        typeWithClipboard(text)
    }

    nonisolated private static func typeWithCGEvents(_ text: String) -> Bool {
        // Check accessibility permission first
        guard AXIsProcessTrusted() else {
            logToFile("❌ No accessibility permission for CGEvents")
            return false
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            logToFile("❌ Failed to create CGEventSource")
            return false
        }

        for character in text {
            let str = String(character)

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
                logToFile("❌ Failed to create keyDown event")
                return false
            }

            var unicodeString = [UniChar](str.utf16)
            keyDown.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: &unicodeString)
            keyDown.post(tap: .cghidEventTap)

            guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                return false
            }

            keyUp.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: &unicodeString)
            keyUp.post(tap: .cghidEventTap)

            Thread.sleep(forTimeInterval: 0.01)
        }

        return true
    }

    nonisolated private static func typeWithClipboard(_ text: String) {
        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        // Set new text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Use AppleScript to paste - more reliable than CGEvents
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                logToFile("❌ AppleScript error: \(error)")
            }
        }

        Thread.sleep(forTimeInterval: 0.2)

        // Restore old clipboard after a delay
        if let old = oldContents {
            Thread.sleep(forTimeInterval: 0.5)
            pasteboard.clearContents()
            pasteboard.setString(old, forType: .string)
        }

        logToFile("✅ Pasted text via AppleScript")
    }
}
