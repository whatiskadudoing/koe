import AVFoundation
import Foundation

/// Audio utility functions for file operations
public enum AudioUtilities {
    /// Write audio samples to a WAV file
    /// - Parameters:
    ///   - samples: Audio samples as Float array
    ///   - url: Destination URL
    ///   - sampleRate: Sample rate (default 16000Hz for Whisper)
    public static func writeWAVFile(samples: [Float], to url: URL, sampleRate: Double = 16000) throws {
        guard
            let audioFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        else {
            throw AudioUtilitiesError.invalidFormat
        }

        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFormat,
                frameCapacity: AVAudioFrameCount(samples.count)
            )
        else {
            throw AudioUtilitiesError.bufferCreationFailed
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)

        guard let channelData = buffer.floatChannelData?[0] else {
            throw AudioUtilitiesError.invalidBuffer
        }

        for (index, sample) in samples.enumerated() {
            channelData[index] = sample
        }

        let audioFile = try AVAudioFile(forWriting: url, settings: audioFormat.settings)
        try audioFile.write(from: buffer)
    }

    /// Create a temporary WAV file with samples
    /// - Parameters:
    ///   - samples: Audio samples
    ///   - prefix: Filename prefix
    ///   - sampleRate: Sample rate
    /// - Returns: URL to the temporary file
    public static func createTempWAVFile(
        samples: [Float],
        prefix: String = "koe",
        sampleRate: Double = 16000
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString).wav")
        try writeWAVFile(samples: samples, to: url, sampleRate: sampleRate)
        return url
    }

    /// Calculate duration of samples at given sample rate
    public static func duration(sampleCount: Int, sampleRate: Double = 16000) -> TimeInterval {
        Double(sampleCount) / sampleRate
    }
}

public enum AudioUtilitiesError: LocalizedError {
    case invalidFormat
    case bufferCreationFailed
    case invalidBuffer

    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Failed to create audio format"
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .invalidBuffer:
            return "Invalid audio buffer"
        }
    }
}
