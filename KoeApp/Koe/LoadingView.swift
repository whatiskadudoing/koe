import SwiftUI
import KoeDomain
import KoeUI
import KoeModels

struct LoadingView: View {
    @Environment(AppState.self) private var appState
    @Environment(RecordingCoordinator.self) private var coordinator
    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 20
    @State private var checkTimer: Timer?
    @State private var progressTimer: Timer?

    // Loading state
    @State private var loadingPhase: LoadingPhase = .checkingModels
    @State private var downloadProgress: Double = 0
    @State private var downloadingModelName: String?

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let circleSize: CGFloat = 80

    enum LoadingPhase {
        case checkingModels
        case downloading
        case loadingModel
        case ready
    }

    var body: some View {
        ZStack {
            // Background matching app
            Color(nsColor: NSColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Animated ring with brain icon
                ZStack {
                    AnimatedRing(
                        isActive: true,
                        audioLevel: 0,
                        color: accentColor,
                        style: appState.currentRingAnimationStyle,
                        maxAmplitude: 14
                    )
                    .frame(width: circleSize + 44, height: circleSize + 44)

                    Circle()
                        .fill(Color.white)
                        .frame(width: circleSize, height: circleSize)
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)

                    Image(systemName: phaseIcon)
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(accentColor)
                }

                // Loading text
                VStack(spacing: 8) {
                    Text(phaseTitle)
                        .font(.system(size: 18, weight: .light, design: .rounded))
                        .foregroundColor(accentColor)
                        .tracking(0.3)

                    // Show progress or status
                    Group {
                        switch loadingPhase {
                        case .checkingModels:
                            Text("Checking models...")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(lightGray.opacity(0.8))

                        case .downloading:
                            VStack(spacing: 6) {
                                if let modelName = downloadingModelName {
                                    Text("Downloading \(modelName)")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(lightGray.opacity(0.8))
                                }

                                // Progress bar
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(lightGray.opacity(0.2))
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(accentColor)
                                            .frame(width: geo.size.width * downloadProgress)
                                    }
                                }
                                .frame(width: 160, height: 6)

                                Text("\(Int(downloadProgress * 100))%")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(lightGray)
                            }

                        case .loadingModel:
                            VStack(spacing: 6) {
                                if downloadProgress > 0.01 && downloadProgress < 0.95 {
                                    Text("Downloading model... \(Int(downloadProgress * 100))%")
                                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                                        .foregroundColor(lightGray)

                                    // Progress bar for download
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(lightGray.opacity(0.2))
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(accentColor)
                                                .frame(width: geo.size.width * downloadProgress)
                                        }
                                    }
                                    .frame(width: 160, height: 6)
                                } else if downloadProgress >= 0.95 {
                                    Text("Compiling AI model...")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(lightGray.opacity(0.8))

                                    Text("First run only - please wait")
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(lightGray.opacity(0.5))
                                } else {
                                    Text("Loading AI model...")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(lightGray.opacity(0.8))

                                    Text("This may take a moment")
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(lightGray.opacity(0.5))
                                }
                            }

                        case .ready:
                            Text("Ready")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(lightGray.opacity(0.8))
                        }
                    }
                }

                Spacer()
            }
            .opacity(contentOpacity)
            .offset(y: contentOffset)
        }
        .onAppear {
            // Fade in content with animation
            withAnimation(.easeOut(duration: 0.5)) {
                contentOpacity = 1
                contentOffset = 0
            }

            // Start progress polling timer
            startProgressPolling()

            // Start the loading process
            Task {
                await checkAndLoadModels()
            }

            // Start checking for model loaded state
            startModelLoadingCheck()
        }
        .onDisappear {
            stopModelLoadingCheck()
            stopProgressPolling()
        }
    }

    private var phaseTitle: String {
        switch loadingPhase {
        case .checkingModels:
            return "Getting ready"
        case .downloading:
            return "Downloading models"
        case .loadingModel:
            return "Getting smarter"
        case .ready:
            return "Welcome back"
        }
    }

    private var phaseIcon: String {
        switch loadingPhase {
        case .checkingModels:
            return "magnifyingglass"
        case .downloading:
            return "arrow.down.circle"
        case .loadingModel:
            return "brain"
        case .ready:
            return "checkmark.circle"
        }
    }

    private func checkAndLoadModels() async {
        // Skip WhisperKit model loading if Apple Speech is enabled (instant startup)
        // WhisperKit model will be loaded on-demand when user enables that node
        if AppState.shared.isAppleSpeechEnabled && !AppState.shared.isWhisperKitEnabled {
            // Apple Speech is ready instantly - no model loading needed
            loadingPhase = .ready
            AppState.shared.isModelLoaded = true
            advanceToReady()
            return
        }

        // Load WhisperKit model if enabled
        loadingPhase = .loadingModel
        await startModelLoading()
    }

    private func startModelLoading() async {
        // Only load WhisperKit if it's enabled
        if AppState.shared.isWhisperKitEnabled && !coordinator.isModelLoaded {
            await RecordingCoordinator.shared.loadModel(name: AppState.shared.selectedModel)
        }
    }

    private func startModelLoadingCheck() {
        // If Apple Speech is enabled and WhisperKit is disabled, we're ready immediately
        if AppState.shared.isAppleSpeechEnabled && !AppState.shared.isWhisperKitEnabled {
            AppState.shared.isModelLoaded = true
            advanceToReady()
            return
        }

        // Check immediately - use coordinator.isModelLoaded which checks actual transcriber state
        if coordinator.isModelLoaded {
            advanceToReady()
            return
        }

        // Poll every 0.5 seconds - check the actual transcriber ready state
        checkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak checkTimer] _ in
            // Must dispatch to main thread since coordinator is MainActor-isolated
            Task { @MainActor in
                let isLoaded = RecordingCoordinator.shared.isModelLoaded

                // Use coordinator.isModelLoaded which returns transcriber.isReady
                // This ensures we only advance when the model is ACTUALLY ready
                if isLoaded {
                    checkTimer?.invalidate()
                    // Also sync the AppState flag
                    AppState.shared.isModelLoaded = true
                    withAnimation(.easeOut(duration: 0.4)) {
                        AppState.shared.advanceReadinessState()
                    }
                }
            }
        }
    }

    private func stopModelLoadingCheck() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func startProgressPolling() {
        // Poll progress every 100ms to update UI reactively
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                let progress = RecordingCoordinator.shared.modelLoadingProgress
                if progress != self.downloadProgress {
                    self.downloadProgress = progress
                }
            }
        }
    }

    private func stopProgressPolling() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func advanceToReady() {
        // Sync the AppState flag before advancing
        appState.isModelLoaded = true
        appState.advanceReadinessState()
    }
}
