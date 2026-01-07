import AVFoundation
import SwiftUI

class AudioRecorder: NSObject, ObservableObject {
    @Published var audioLevel: Float = 0.0
    @Published var isRecording: Bool = false

    private var audioRecorder: AVAudioRecorder?
    private var audioURL: URL?
    private var levelTimer: Timer?

    override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        // Request microphone permission
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                print("Microphone permission denied")
            }
        }
    }

    func startRecording() {
        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        audioURL = tempDir.appendingPathComponent("whisper_recording_\(UUID().uuidString).wav")

        // Audio settings optimized for Whisper (16kHz, mono, 16-bit)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: audioURL!, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            isRecording = true

            // Start level monitoring
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.updateAudioLevel()
            }

        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        levelTimer?.invalidate()
        levelTimer = nil

        audioRecorder?.stop()
        isRecording = false
        audioLevel = 0.0

        // Small delay to ensure file is written
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            completion(self?.audioURL)
        }
    }

    private func updateAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }

        recorder.updateMeters()

        // Get average power (in dB, typically -160 to 0)
        let avgPower = recorder.averagePower(forChannel: 0)

        // Convert to 0-1 range
        // -50 dB = silence, 0 dB = loud
        let normalizedLevel = max(0, (avgPower + 50) / 50)

        DispatchQueue.main.async {
            self.audioLevel = normalizedLevel
        }
    }
}
