import AVFoundation
import KoeDomain

/// Audio recorder using AVAudioEngine
/// Captures microphone audio and converts to 16kHz mono for transcription
public final class AVAudioEngineRecorder: AudioRecordingService, @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private let audioBuffer: AudioBufferManager
    private let levelMonitor: AudioLevelMonitor
    private let lock = NSLock()

    private var _isRecording = false
    private var _audioLevel: Float = 0.0

    /// Target sample rate for Whisper models (16kHz)
    public let targetSampleRate: Double = 16000

    /// Buffer size for audio capture
    public let bufferSize: AVAudioFrameCount = 1024

    public var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRecording
    }

    public var audioLevel: Float {
        lock.lock()
        defer { lock.unlock() }
        return _audioLevel
    }

    public init() {
        self.audioBuffer = AudioBufferManager()
        self.levelMonitor = AudioLevelMonitor()
    }

    /// Request microphone permission
    public func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Start recording audio from the microphone
    public func startRecording() async throws {
        guard !_isRecording else { return }

        // Clear previous buffer
        audioBuffer.clear()

        // Setup audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw AudioError.engineStartFailed(underlying: NSError(domain: "KoeAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAudioEngine"]))
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create output format for 16kHz mono
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioError.engineStartFailed(underlying: NSError(domain: "KoeAudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create output format"]))
        }

        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioError.engineStartFailed(underlying: NSError(domain: "KoeAudio", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"]))
        }

        // Install tap to capture audio
        let buffer = audioBuffer
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [targetSampleRate] inputBuffer, _ in
            Self.processAudioBuffer(
                buffer: inputBuffer,
                converter: converter,
                outputFormat: outputFormat,
                targetSampleRate: targetSampleRate,
                audioBuffer: buffer
            )
        }

        do {
            try audioEngine.start()
            _isRecording = true
        } catch {
            audioEngine.inputNode.removeTap(onBus: 0)
            self.audioEngine = nil
            throw AudioError.engineStartFailed(underlying: error)
        }
    }

    /// Stop recording and return audio data
    public func stopRecording() async throws -> Data {
        defer {
            _isRecording = false
            _audioLevel = 0
        }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        let samples = audioBuffer.getSamples()
        guard !samples.isEmpty else {
            throw AudioError.noAudioData
        }

        // Convert samples to WAV data
        return try createWAVData(from: samples)
    }

    /// Get accumulated audio samples (for streaming transcription)
    public func getAudioSamples() -> [Float] {
        audioBuffer.getSamples()
    }

    /// Get recent audio samples
    public func getRecentSamples(count: Int) -> [Float] {
        audioBuffer.getRecentSamples(count: count)
    }

    /// Get total sample count
    public var sampleCount: Int {
        audioBuffer.count
    }

    /// Update and return current audio level (call periodically for UI updates)
    public func updateAudioLevel() -> Float {
        let recentSamples = audioBuffer.getRecentSamples(count: 1600) // ~0.1 seconds
        _audioLevel = levelMonitor.calculateLevel(from: recentSamples)
        return _audioLevel
    }

    /// Audio level stream for real-time updates
    public func audioLevelStream() -> AsyncStream<Float> {
        AsyncStream { continuation in
            // This would be implemented with a timer or callback mechanism
            // For now, provide a simple implementation
            continuation.yield(_audioLevel)
        }
    }

    // MARK: - Private Methods

    private static func processAudioBuffer(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat,
        targetSampleRate: Double,
        audioBuffer: AudioBufferManager
    ) {
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if error != nil {
            return
        }

        guard let floatData = convertedBuffer.floatChannelData?[0] else { return }
        let frameLength = Int(convertedBuffer.frameLength)

        var samples: [Float] = []
        samples.reserveCapacity(frameLength)
        for i in 0..<frameLength {
            samples.append(floatData[i])
        }
        audioBuffer.append(samples)
    }

    private func createWAVData(from samples: [Float]) throws -> Data {
        let sampleRate = UInt32(targetSampleRate)
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 32
        let bytesPerSample = bitsPerSample / 8
        let dataSize = UInt32(samples.count * Int(bytesPerSample))

        var header = Data()

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: (36 + dataSize).littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(3).littleEndian) { Array($0) }) // IEEE float
        header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        let byteRate = sampleRate * UInt32(channels) * UInt32(bytesPerSample)
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign = channels * bytesPerSample
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Append sample data
        var data = header
        for sample in samples {
            data.append(contentsOf: withUnsafeBytes(of: sample) { Array($0) })
        }

        return data
    }
}
