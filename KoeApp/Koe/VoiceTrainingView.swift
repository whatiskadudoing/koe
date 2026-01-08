import Accelerate
import AVFoundation
import KoeCommands
import KoeUI
import SwiftUI

/// Voice training wizard for enrolling the user's voice
struct VoiceTrainingView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var trainingState: TrainingState = .intro
    @State private var currentSample: Int = 0
    @State private var audioSamples: [[Float]] = []
    @State private var isRecording = false
    @State private var audioLevel: Float = 0.0
    @State private var errorMessage: String?

    private let totalSamples = 5
    private let commandDetector: CommandDetector
    private let onComplete: ((VoiceProfile) -> Void)?

    // Colors
    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let pageBackground = Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))
    private let recordingColor = Color(nsColor: NSColor(red: 0.90, green: 0.25, blue: 0.20, alpha: 1.0))

    enum TrainingState {
        case intro
        case recording
        case processing
        case complete
        case error
    }

    init(
        commandDetector: CommandDetector = CommandDetector(),
        onComplete: ((VoiceProfile) -> Void)? = nil
    ) {
        self.commandDetector = commandDetector
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            header

            // Content based on state
            Group {
                switch trainingState {
                case .intro:
                    introContent
                case .recording:
                    recordingContent
                case .processing:
                    processingContent
                case .complete:
                    completeContent
                case .error:
                    errorContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer with buttons
            footer
        }
        .padding(24)
        .frame(width: 400, height: 480)
        .background(pageBackground)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(accentColor)

            Text("Voice Training")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(accentColor)
                .tracking(2)

            Text("Train Koe to recognize your voice")
                .font(.system(size: 13))
                .foregroundColor(lightGray)
        }
    }

    // MARK: - Intro Content

    private var introContent: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                instructionRow(
                    number: "1",
                    text: "You'll say \"kon\" five times"
                )
                instructionRow(
                    number: "2",
                    text: "Speak naturally, as you would normally"
                )
                instructionRow(
                    number: "3",
                    text: "Koe will learn to recognize your voice"
                )
            }
            .padding(.horizontal, 20)

            Spacer()

            Text("This helps ensure only you can trigger voice commands")
                .font(.system(size: 12))
                .foregroundColor(lightGray)
                .multilineTextAlignment(.center)
        }
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(accentColor)
                .clipShape(Circle())

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(accentColor)
        }
    }

    // MARK: - Recording Content

    private var recordingContent: some View {
        VStack(spacing: 24) {
            Spacer()

            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<totalSamples, id: \.self) { index in
                    Circle()
                        .fill(index < currentSample ? Color.green : (index == currentSample ? recordingColor : lightGray.opacity(0.3)))
                        .frame(width: 12, height: 12)
                }
            }

            Text("Sample \(currentSample + 1) of \(totalSamples)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(lightGray)

            // Recording visualization
            ZStack {
                Circle()
                    .stroke(lightGray.opacity(0.2), lineWidth: 4)
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(isRecording ? recordingColor.opacity(0.1) : Color.clear)
                    .frame(width: 120 + CGFloat(audioLevel * 40), height: 120 + CGFloat(audioLevel * 40))
                    .animation(.easeOut(duration: 0.1), value: audioLevel)

                Circle()
                    .fill(isRecording ? recordingColor : accentColor)
                    .frame(width: 80, height: 80)

                Image(systemName: isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }

            // Instruction
            VStack(spacing: 4) {
                Text(isRecording ? "Say \"kon\" now" : "Tap to record")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isRecording ? recordingColor : accentColor)

                if isRecording {
                    Text("Recording...")
                        .font(.system(size: 12))
                        .foregroundColor(lightGray)
                }
            }

            Spacer()
        }
        .onTapGesture {
            if !isRecording {
                startRecording()
            }
        }
    }

    // MARK: - Processing Content

    private var processingContent: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Processing your voice...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(accentColor)

            Text("Creating your voice profile")
                .font(.system(size: 13))
                .foregroundColor(lightGray)

            Spacer()
        }
    }

    // MARK: - Complete Content

    private var completeContent: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Voice Training Complete!")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(accentColor)

            Text("Koe will now recognize your voice when you say \"kon\"")
                .font(.system(size: 13))
                .foregroundColor(lightGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Spacer()
        }
    }

    // MARK: - Error Content

    private var errorContent: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundColor(.orange)

            Text("Training Failed")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(accentColor)

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(lightGray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Spacer()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            // Cancel button
            Button(action: { dismiss() }) {
                Text(trainingState == .complete ? "Close" : "Cancel")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(lightGray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Action button
            if trainingState == .intro {
                Button(action: {
                    withAnimation {
                        trainingState = .recording
                    }
                }) {
                    Text("Start Training")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            } else if trainingState == .error {
                Button(action: {
                    withAnimation {
                        trainingState = .intro
                        currentSample = 0
                        audioSamples = []
                        errorMessage = nil
                    }
                }) {
                    Text("Try Again")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Recording Logic

    private func startRecording() {
        isRecording = true

        // Record for 2 seconds
        Task {
            do {
                let samples = try await recordAudioSamples(duration: 2.0)
                audioSamples.append(samples)
                currentSample += 1

                if currentSample >= totalSamples {
                    await processTraining()
                }

                isRecording = false
            } catch {
                isRecording = false
                errorMessage = error.localizedDescription
                trainingState = .error
            }
        }
    }

    private func recordAudioSamples(duration: TimeInterval) async throws -> [Float] {
        // Use AVAudioEngine to capture audio
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let inputSampleRate = inputFormat.sampleRate

        // Target 16kHz for voice verification
        let targetSampleRate: Double = 16000

        var samples: [Float] = []
        let sampleCount = Int(inputSampleRate * duration)

        let semaphore = DispatchSemaphore(value: 0)

        print("[VoiceTraining] Recording at \(inputSampleRate) Hz, will resample to \(targetSampleRate) Hz")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)

            for i in 0..<frameLength {
                if samples.count < sampleCount {
                    samples.append(channelData[i])
                }
            }

            // Update audio level for visualization
            var rms: Float = 0
            vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
            DispatchQueue.main.async {
                self.audioLevel = min(rms * 10, 1.0)
            }

            if samples.count >= sampleCount {
                semaphore.signal()
            }
        }

        engine.prepare()
        try engine.start()

        // Wait for recording to complete (with timeout)
        let result = semaphore.wait(timeout: .now() + duration + 1.0)

        engine.stop()
        inputNode.removeTap(onBus: 0)

        DispatchQueue.main.async {
            self.audioLevel = 0
        }

        if result == .timedOut && samples.count < sampleCount / 2 {
            throw NSError(
                domain: "VoiceTraining",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Recording timed out"]
            )
        }

        // Resample to 16kHz if needed
        let resampledSamples = resample(samples, from: inputSampleRate, to: targetSampleRate)
        print("[VoiceTraining] Recorded \(samples.count) samples, resampled to \(resampledSamples.count)")

        return resampledSamples
    }

    /// Simple linear interpolation resampling
    private func resample(_ samples: [Float], from inputRate: Double, to outputRate: Double) -> [Float] {
        guard inputRate != outputRate else { return samples }
        guard !samples.isEmpty else { return [] }

        let ratio = inputRate / outputRate
        let outputLength = Int(Double(samples.count) / ratio)
        var output = [Float](repeating: 0, count: outputLength)

        for i in 0..<outputLength {
            let srcIndex = Double(i) * ratio
            let srcIndexInt = Int(srcIndex)
            let frac = Float(srcIndex - Double(srcIndexInt))

            if srcIndexInt + 1 < samples.count {
                // Linear interpolation
                output[i] = samples[srcIndexInt] * (1 - frac) + samples[srcIndexInt + 1] * frac
            } else if srcIndexInt < samples.count {
                output[i] = samples[srcIndexInt]
            }
        }

        return output
    }

    private func processTraining() async {
        await MainActor.run {
            trainingState = .processing
        }

        // Small delay for UX
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Train the voice profile
        if let profile = commandDetector.trainVoiceProfile(name: "User", samples: audioSamples) {
            await MainActor.run {
                trainingState = .complete
                onComplete?(profile)
            }
        } else {
            await MainActor.run {
                errorMessage = "Failed to create voice profile. Please try again."
                trainingState = .error
            }
        }
    }
}

#Preview {
    VoiceTrainingView()
}
