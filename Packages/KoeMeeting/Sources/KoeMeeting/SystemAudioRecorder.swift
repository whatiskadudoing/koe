import Foundation
import AVFoundation
import AudioToolbox
import CoreAudio
import KoeCore

// MARK: - Errors

public enum SystemAudioRecorderError: Error, LocalizedError {
    case notAvailable
    case coreAudioError(OSStatus, String)
    case noOutputDevice
    case failedToCreateTap
    case failedToCreateAggregateDevice
    case failedToAddTapToDevice
    case failedToCreateAudioFile
    case failedToGetFormat
    case notRecording
    case alreadyRecording
    case mergeFailed

    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Core Audio Taps requires macOS 14.4 or later"
        case .coreAudioError(let status, let context):
            return "\(context): OSStatus \(status)"
        case .noOutputDevice:
            return "No audio output device found"
        case .failedToCreateTap:
            return "Failed to create audio process tap"
        case .failedToCreateAggregateDevice:
            return "Failed to create aggregate audio device"
        case .failedToAddTapToDevice:
            return "Failed to add tap to aggregate device"
        case .failedToCreateAudioFile:
            return "Failed to create audio file for recording"
        case .failedToGetFormat:
            return "Failed to get audio format"
        case .notRecording:
            return "Not currently recording"
        case .alreadyRecording:
            return "Already recording"
        case .mergeFailed:
            return "Failed to merge audio files"
        }
    }
}

// MARK: - System Audio Recorder

/// Records system audio using Core Audio Taps (macOS 14.4+)
/// Records mic and system audio to separate files, then merges them
@available(macOS 14.4, *)
public final class SystemAudioRecorder: @unchecked Sendable {

    // MARK: - State

    private var processTapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?

    // Separate files for system and mic audio
    private var systemAudioFile: AVAudioFile?
    private var micAudioFile: AVAudioFile?
    private var systemAudioURL: URL?
    private var micAudioURL: URL?
    private var finalOutputURL: URL?

    private var startTime: Date?
    private var streamFormat: AudioStreamBasicDescription?

    private var isRecording = false
    private let lock = NSLock()

    /// Audio level continuations for UI updates
    private var audioLevelContinuations: [UUID: AsyncStream<Float>.Continuation] = [:]

    // Microphone capture
    private var audioEngine: AVAudioEngine?

    // MARK: - Init

    public init() {}

    deinit {
        cleanup()
    }

    // MARK: - Public API

    /// Check if Core Audio Taps is available
    public static var isAvailable: Bool {
        return true  // This class is only available on macOS 14.4+
    }

    /// Start recording system audio to a file
    public func startRecording(to url: URL) async throws {
        lock.lock()
        guard !isRecording else {
            lock.unlock()
            throw SystemAudioRecorderError.alreadyRecording
        }
        lock.unlock()

        KoeLogger.meeting.info("Starting system audio recording using Core Audio Taps")

        // Store final output URL
        finalOutputURL = url

        // Create temp URLs for separate audio streams
        let tempDir = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        systemAudioURL = tempDir.appendingPathComponent("\(baseName)_system.wav")
        micAudioURL = tempDir.appendingPathComponent("\(baseName)_mic.wav")

        // 1. Create the process tap for global system audio
        let tapID = try createSystemAudioTap()
        processTapID = tapID
        KoeLogger.meeting.debug("Created process tap: \(tapID)")

        // 2. Create aggregate device
        let deviceID = try createAggregateDevice()
        aggregateDeviceID = deviceID
        KoeLogger.meeting.debug("Created aggregate device: \(deviceID)")

        // 3. Add tap to aggregate device
        try addTapToAggregateDevice(tapID: tapID, deviceID: deviceID)
        KoeLogger.meeting.debug("Added tap to aggregate device")

        // 4. Get the format from the TAP (not the aggregate device)
        let format = try getTapFormat(tapID: tapID)
        streamFormat = format
        KoeLogger.meeting.debug("System audio format: \(format.mSampleRate)Hz, \(format.mChannelsPerFrame) channels")

        // 5. Create audio file for system audio recording
        let systemFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.mSampleRate,
            channels: AVAudioChannelCount(format.mChannelsPerFrame),
            interleaved: false
        )!

        do {
            systemAudioFile = try AVAudioFile(
                forWriting: systemAudioURL!,
                settings: systemFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            KoeLogger.meeting.error("Failed to create system audio file", error: error)
            cleanup()
            throw SystemAudioRecorderError.failedToCreateAudioFile
        }

        startTime = Date()

        // 6. Create and start IO proc for system audio
        try startIOProc(deviceID: deviceID)

        // 7. Start microphone capture to separate file
        try startMicrophoneCapture(targetSampleRate: format.mSampleRate)

        lock.lock()
        isRecording = true
        lock.unlock()

        KoeLogger.meeting.info("Recording started - System: \(systemAudioURL!.lastPathComponent), Mic: \(micAudioURL!.lastPathComponent)")
    }

    /// Stop recording and return the duration
    public func stopRecording() async throws -> TimeInterval {
        lock.lock()
        guard isRecording else {
            lock.unlock()
            throw SystemAudioRecorderError.notRecording
        }
        lock.unlock()

        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0

        // Stop recording first
        stopRecordingInternal()

        // Merge the two audio files
        if let systemURL = systemAudioURL, let micURL = micAudioURL, let outputURL = finalOutputURL {
            do {
                try await mergeAudioFiles(systemAudioURL: systemURL, micAudioURL: micURL, outputURL: outputURL)
                KoeLogger.meeting.info("Audio files merged successfully")

                // Clean up temp files
                try? FileManager.default.removeItem(at: systemURL)
                try? FileManager.default.removeItem(at: micURL)
            } catch {
                KoeLogger.meeting.error("Failed to merge audio files", error: error)
                // If merge fails, just use system audio as the output
                try? FileManager.default.moveItem(at: systemURL, to: outputURL)
                try? FileManager.default.removeItem(at: micURL)
            }
        }

        cleanup()

        KoeLogger.meeting.info("System audio recording stopped. Duration: \(String(format: "%.1f", duration))s")

        return duration
    }

    /// Stream of audio levels (0.0 - 1.0) for UI visualization
    public func audioLevelStream() -> AsyncStream<Float> {
        let id = UUID()
        return AsyncStream { [weak self] continuation in
            self?.lock.lock()
            self?.audioLevelContinuations[id] = continuation
            self?.lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.audioLevelContinuations.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    /// Current recording state
    public var isCurrentlyRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRecording
    }

    // MARK: - Private - Setup

    private func createSystemAudioTap() throws -> AudioObjectID {
        // Create tap description for global system audio (capture everything except our own app)
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Koe-SystemAudioTap"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)

        guard status == kAudioHardwareNoError else {
            KoeLogger.meeting.error("Failed to create process tap: \(status)")
            throw SystemAudioRecorderError.failedToCreateTap
        }

        return tapID
    }

    private func createAggregateDevice() throws -> AudioObjectID {
        let uid = "com.koe.systemaudiotap.\(UUID().uuidString)"
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Koe-AggregateDevice",
            kAudioAggregateDeviceUIDKey as String: uid,
            kAudioAggregateDeviceSubDeviceListKey as String: [] as CFArray,
            kAudioAggregateDeviceMasterSubDeviceKey as String: 0,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false
        ]

        var deviceID: AudioObjectID = kAudioObjectUnknown
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID)

        guard status == kAudioHardwareNoError else {
            KoeLogger.meeting.error("Failed to create aggregate device: \(status)")
            throw SystemAudioRecorderError.failedToCreateAggregateDevice
        }

        return deviceID
    }

    private func addTapToAggregateDevice(tapID: AudioObjectID, deviceID: AudioObjectID) throws {
        // Get the tap's UID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var tapUID: CFString = "" as CFString

        var status = withUnsafeMutablePointer(to: &tapUID) { ptr in
            AudioObjectGetPropertyData(tapID, &propertyAddress, 0, nil, &propertySize, ptr)
        }

        guard status == kAudioHardwareNoError else {
            KoeLogger.meeting.error("Failed to get tap UID: \(status)")
            throw SystemAudioRecorderError.coreAudioError(status, "Failed to get tap UID")
        }

        // Add the tap to the aggregate device
        propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let tapArray = [tapUID] as CFArray
        propertySize = UInt32(MemoryLayout<CFArray>.size)

        status = withUnsafePointer(to: tapArray) { ptr in
            AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, propertySize, ptr)
        }

        guard status == kAudioHardwareNoError else {
            KoeLogger.meeting.error("Failed to add tap to aggregate device: \(status)")
            throw SystemAudioRecorderError.failedToAddTapToDevice
        }
    }

    private func getTapFormat(tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var format = AudioStreamBasicDescription()
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        let status = AudioObjectGetPropertyData(tapID, &propertyAddress, 0, nil, &propertySize, &format)

        guard status == kAudioHardwareNoError else {
            KoeLogger.meeting.error("Failed to get tap format: \(status)")
            throw SystemAudioRecorderError.failedToGetFormat
        }

        return format
    }

    private func startMicrophoneCapture(targetSampleRate: Double) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        KoeLogger.meeting.info("Starting microphone capture: \(inputFormat.sampleRate)Hz -> \(targetSampleRate)Hz, \(inputFormat.channelCount) channels")

        // Create mic audio file with same sample rate as system audio
        let micFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,  // Mono for mic
            interleaved: false
        )!

        do {
            micAudioFile = try AVAudioFile(
                forWriting: micAudioURL!,
                settings: micFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            KoeLogger.meeting.error("Failed to create mic audio file", error: error)
            throw SystemAudioRecorderError.failedToCreateAudioFile
        }

        // Create converter if sample rates differ
        var converter: AVAudioConverter?
        if inputFormat.sampleRate != targetSampleRate {
            let converterInputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: 1,
                interleaved: false
            )!
            converter = AVAudioConverter(from: converterInputFormat, to: micFormat)
            KoeLogger.meeting.info("Created sample rate converter: \(inputFormat.sampleRate) -> \(targetSampleRate)")
        }

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            self.lock.lock()
            let currentMicFile = self.micAudioFile
            self.lock.unlock()

            guard let micFile = currentMicFile else { return }

            // Convert to mono if needed
            let monoBuffer: AVAudioPCMBuffer
            if buffer.format.channelCount > 1 {
                // Mix down to mono
                guard let mono = AVAudioPCMBuffer(
                    pcmFormat: AVAudioFormat(
                        commonFormat: .pcmFormatFloat32,
                        sampleRate: buffer.format.sampleRate,
                        channels: 1,
                        interleaved: false
                    )!,
                    frameCapacity: buffer.frameLength
                ) else { return }
                mono.frameLength = buffer.frameLength

                if let srcData = buffer.floatChannelData, let dstData = mono.floatChannelData {
                    let frameCount = Int(buffer.frameLength)
                    let channelCount = Int(buffer.format.channelCount)
                    for i in 0..<frameCount {
                        var sum: Float = 0
                        for ch in 0..<channelCount {
                            sum += srcData[ch][i]
                        }
                        dstData[0][i] = sum / Float(channelCount)
                    }
                }
                monoBuffer = mono
            } else {
                monoBuffer = buffer
            }

            // Resample if needed
            let outputBuffer: AVAudioPCMBuffer
            if let conv = converter {
                // Calculate output frame count based on sample rate ratio
                let ratio = targetSampleRate / monoBuffer.format.sampleRate
                let outputFrameCount = AVAudioFrameCount(Double(monoBuffer.frameLength) * ratio)

                guard let converted = AVAudioPCMBuffer(
                    pcmFormat: micFormat,
                    frameCapacity: outputFrameCount
                ) else { return }

                var error: NSError?
                let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return monoBuffer
                }

                conv.convert(to: converted, error: &error, withInputFrom: inputBlock)
                if error != nil { return }

                outputBuffer = converted
            } else {
                outputBuffer = monoBuffer
            }

            // Write to file
            do {
                try micFile.write(from: outputBuffer)
            } catch {
                // Silently ignore write errors in the callback
            }
        }

        try engine.start()
        audioEngine = engine
        KoeLogger.meeting.info("Microphone capture started")
    }

    private func stopMicrophoneCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        KoeLogger.meeting.info("Microphone capture stopped")
    }

    private func startIOProc(deviceID: AudioObjectID) throws {
        var procID: AudioDeviceIOProcID?

        let status = AudioDeviceCreateIOProcID(
            deviceID,
            { (inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, inClientData) -> OSStatus in
                guard let clientData = inClientData else { return noErr }
                let recorder = Unmanaged<SystemAudioRecorder>.fromOpaque(clientData).takeUnretainedValue()
                recorder.processAudioBuffer(inInputData)
                return noErr
            },
            Unmanaged.passUnretained(self).toOpaque(),
            &procID
        )

        guard status == kAudioHardwareNoError, let procID = procID else {
            KoeLogger.meeting.error("Failed to create IO proc: \(status)")
            throw SystemAudioRecorderError.coreAudioError(status, "Failed to create IO proc")
        }

        ioProcID = procID

        let startStatus = AudioDeviceStart(deviceID, procID)
        guard startStatus == kAudioHardwareNoError else {
            KoeLogger.meeting.error("Failed to start device: \(startStatus)")
            throw SystemAudioRecorderError.coreAudioError(startStatus, "Failed to start audio device")
        }

        KoeLogger.meeting.debug("IO proc started successfully")
    }

    // MARK: - Private - Audio Processing

    private var bufferCount = 0

    private func processAudioBuffer(_ inputData: UnsafePointer<AudioBufferList>?) {
        guard let inputData = inputData else { return }

        let bufferList = inputData.pointee
        guard bufferList.mNumberBuffers > 0 else { return }

        bufferCount += 1

        // Get first buffer for audio level calculation
        let firstBuffer = bufferList.mBuffers
        guard let data = firstBuffer.mData, firstBuffer.mDataByteSize > 0 else { return }

        // Calculate audio level
        let floatData = data.assumingMemoryBound(to: Float.self)
        let sampleCount = Int(firstBuffer.mDataByteSize) / MemoryLayout<Float>.size

        var sum: Float = 0
        for i in 0..<sampleCount {
            sum += floatData[i] * floatData[i]
        }
        let rms = sqrt(sum / Float(max(sampleCount, 1)))
        let level = min(1.0, rms * 5.0)

        // Emit audio level
        lock.lock()
        for continuation in audioLevelContinuations.values {
            continuation.yield(level)
        }
        let currentFile = systemAudioFile
        let currentFormat = streamFormat
        lock.unlock()

        // Log periodically
        if bufferCount == 1 || bufferCount % 500 == 0 {
            KoeLogger.meeting.debug("Audio buffer #\(bufferCount), level: \(String(format: "%.3f", level)), bytes: \(firstBuffer.mDataByteSize)")
        }

        // Write to system audio file
        guard let audioFile = currentFile, let format = currentFormat else { return }

        guard let avFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.mSampleRate,
            channels: AVAudioChannelCount(format.mChannelsPerFrame),
            interleaved: false
        ) else { return }

        let bytesPerFrame = UInt32(MemoryLayout<Float>.size * Int(format.mChannelsPerFrame))
        let frameCount = firstBuffer.mDataByteSize / bytesPerFrame

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: frameCount) else {
            return
        }
        pcmBuffer.frameLength = frameCount

        // Copy data based on channel count
        if format.mChannelsPerFrame == 2 {
            // Stereo: data is interleaved, need to deinterleave
            if let leftChannel = pcmBuffer.floatChannelData?[0],
               let rightChannel = pcmBuffer.floatChannelData?[1] {
                let frameCountInt = Int(frameCount)
                for i in 0..<frameCountInt {
                    leftChannel[i] = floatData[i * 2]
                    rightChannel[i] = floatData[i * 2 + 1]
                }
            }
        } else {
            // Mono or single channel
            if let channelData = pcmBuffer.floatChannelData?[0] {
                memcpy(channelData, floatData, Int(firstBuffer.mDataByteSize))
            }
        }

        do {
            try audioFile.write(from: pcmBuffer)
        } catch {
            if bufferCount % 100 == 0 {
                KoeLogger.meeting.error("Failed to write audio buffer", error: error)
            }
        }
    }

    // MARK: - Private - Audio Merging

    private func mergeAudioFiles(systemAudioURL: URL, micAudioURL: URL, outputURL: URL) async throws {
        KoeLogger.meeting.info("Merging audio files...")

        // Read both audio files
        let systemFile = try AVAudioFile(forReading: systemAudioURL)
        let micFile = try AVAudioFile(forReading: micAudioURL)

        let systemFormat = systemFile.processingFormat
        let micFormat = micFile.processingFormat

        KoeLogger.meeting.debug("System audio: \(systemFile.length) frames at \(systemFormat.sampleRate)Hz, \(systemFormat.channelCount) channels")
        KoeLogger.meeting.debug("Mic audio: \(micFile.length) frames at \(micFormat.sampleRate)Hz, \(micFormat.channelCount) channels")

        // Output format: stereo at system sample rate
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: systemFormat.sampleRate,
            channels: 2,
            interleaved: false
        )!

        // Create output file
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // Process in chunks
        let chunkSize: AVAudioFrameCount = 4096
        let systemBuffer = AVAudioPCMBuffer(pcmFormat: systemFormat, frameCapacity: chunkSize)!
        let micBuffer = AVAudioPCMBuffer(pcmFormat: micFormat, frameCapacity: chunkSize)!
        let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: chunkSize)!

        let systemLength = AVAudioFramePosition(systemFile.length)
        let micLength = AVAudioFramePosition(micFile.length)
        let maxLength = max(systemLength, micLength)

        var systemPosition: AVAudioFramePosition = 0
        var micPosition: AVAudioFramePosition = 0

        while systemPosition < maxLength || micPosition < maxLength {
            // Read system audio
            let systemFramesToRead = min(chunkSize, AVAudioFrameCount(max(0, systemLength - systemPosition)))
            if systemFramesToRead > 0 {
                systemFile.framePosition = systemPosition
                try systemFile.read(into: systemBuffer, frameCount: systemFramesToRead)
            } else {
                systemBuffer.frameLength = 0
            }

            // Read mic audio
            let micFramesToRead = min(chunkSize, AVAudioFrameCount(max(0, micLength - micPosition)))
            if micFramesToRead > 0 {
                micFile.framePosition = micPosition
                try micFile.read(into: micBuffer, frameCount: micFramesToRead)
            } else {
                micBuffer.frameLength = 0
            }

            // Determine output frame count
            let outputFrameCount = max(systemBuffer.frameLength, micBuffer.frameLength)
            if outputFrameCount == 0 { break }

            outputBuffer.frameLength = outputFrameCount

            // Mix: system audio on both channels, mic added to center
            guard let outputData = outputBuffer.floatChannelData else { break }
            let systemData = systemBuffer.floatChannelData
            let micData = micBuffer.floatChannelData

            for frame in 0..<Int(outputFrameCount) {
                var leftSample: Float = 0
                var rightSample: Float = 0

                // Add system audio (stereo or mono)
                if let sysData = systemData, frame < Int(systemBuffer.frameLength) {
                    if systemFormat.channelCount >= 2 {
                        leftSample = sysData[0][frame]
                        rightSample = sysData[1][frame]
                    } else {
                        leftSample = sysData[0][frame]
                        rightSample = sysData[0][frame]
                    }
                }

                // Add mic audio (centered - equal on both channels)
                if let mData = micData, frame < Int(micBuffer.frameLength) {
                    let micSample = mData[0][frame] * 0.8  // Slightly lower mic volume
                    leftSample += micSample
                    rightSample += micSample
                }

                // Clamp to prevent clipping
                outputData[0][frame] = max(-1.0, min(1.0, leftSample))
                outputData[1][frame] = max(-1.0, min(1.0, rightSample))
            }

            // Write to output
            try outputFile.write(from: outputBuffer)

            systemPosition += AVAudioFramePosition(systemFramesToRead)
            micPosition += AVAudioFramePosition(micFramesToRead)
        }

        KoeLogger.meeting.info("Audio merge complete: \(outputFile.length) frames")
    }

    // MARK: - Private - Cleanup

    private func stopRecordingInternal() {
        KoeLogger.meeting.debug("Stopping recording...")

        // Stop microphone capture
        stopMicrophoneCapture()

        // Stop device and destroy IO proc
        if let procID = ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
        }
        ioProcID = nil

        // Close audio files
        lock.lock()
        isRecording = false
        systemAudioFile = nil
        micAudioFile = nil
        lock.unlock()
    }

    private func cleanup() {
        KoeLogger.meeting.debug("Cleaning up system audio recorder")

        lock.lock()
        isRecording = false
        systemAudioFile = nil
        micAudioFile = nil
        startTime = nil
        streamFormat = nil
        systemAudioURL = nil
        micAudioURL = nil
        finalOutputURL = nil
        lock.unlock()

        // Destroy aggregate device
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }

        // Destroy tap
        if processTapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(processTapID)
            processTapID = kAudioObjectUnknown
        }

        bufferCount = 0
        KoeLogger.meeting.debug("System audio recorder cleanup complete")
    }
}
