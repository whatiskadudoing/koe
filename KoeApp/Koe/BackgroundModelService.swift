import Foundation
import KoeDomain
import KoeTranscription
import UserNotifications
import os.log

/// Status phase for a model's download/compilation
public enum ModelPhase: String, Codable, Sendable {
    case pending        // Not started
    case downloading    // Downloading from HuggingFace
    case compiling      // ANE compilation in progress
    case ready          // Fully available
    case failed         // Error occurred
}

/// Status for a single model's download/compilation
public struct ModelDownloadStatus: Codable, Sendable {
    public var model: KoeModel
    public var phase: ModelPhase
    public var downloadProgress: Double  // 0.0 - 1.0
    public var compilationProgress: Double  // 0.0 - 1.0
    public var errorMessage: String?
    public var startedAt: Date?
    public var completedAt: Date?

    public init(model: KoeModel) {
        self.model = model
        self.phase = .pending
        self.downloadProgress = 0
        self.compilationProgress = 0
    }

    /// Combined progress (download is 50%, compilation is 50%)
    public var totalProgress: Double {
        switch phase {
        case .pending: return 0
        case .downloading: return downloadProgress * 0.5
        case .compiling: return 0.5 + compilationProgress * 0.5
        case .ready: return 1.0
        case .failed: return 0
        }
    }

    /// Estimated time remaining in seconds (rough estimate)
    public var estimatedTimeRemaining: TimeInterval? {
        guard let started = startedAt, totalProgress > 0.05 else { return nil }
        let elapsed = Date().timeIntervalSince(started)
        let estimatedTotal = elapsed / totalProgress
        return max(0, estimatedTotal - elapsed)
    }
}

/// Aggregated state for background model processing
public struct BackgroundModelState: Codable {
    public var models: [String: ModelDownloadStatus]  // keyed by model.rawValue
    public var isProcessing: Bool
    public var isPaused: Bool
    public var currentlyProcessing: String?  // model.rawValue
    public var lastCompletedAt: Date?

    public init() {
        self.models = [:]
        self.isProcessing = false
        self.isPaused = false
    }

    public func status(for model: KoeModel) -> ModelDownloadStatus? {
        models[model.rawValue]
    }
}

/// Service that downloads and compiles models in the background after app launch
@MainActor
public final class BackgroundModelService: ObservableObject {
    public static let shared = BackgroundModelService()

    // MARK: - Published State
    @Published public private(set) var state: BackgroundModelState
    @Published public private(set) var isFirstLaunch: Bool = false

    // MARK: - Private
    private let transcriber = WhisperKitTranscriber()
    private let logger = Logger(subsystem: "com.koe.voice", category: "BackgroundModels")
    private var backgroundTask: Task<Void, Never>?
    private var isPausedForTranscription = false

    // UserDefaults keys
    private let stateKey = "BackgroundModelState"
    private let hasCompletedFirstBackgroundKey = "HasCompletedFirstBackground"

    private init() {
        // Load persisted state
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let savedState = try? JSONDecoder().decode(BackgroundModelState.self, from: data) {
            self.state = savedState
        } else {
            self.state = BackgroundModelState()
        }

        // Check if this is first launch (no background models completed yet)
        isFirstLaunch = !UserDefaults.standard.bool(forKey: hasCompletedFirstBackgroundKey)

        setupObservers()
    }

    // MARK: - Public API

    /// Start background processing (call when app reaches .ready state)
    public func startBackgroundProcessing() {
        guard backgroundTask == nil else {
            logger.notice("Background processing already running")
            return
        }

        // Check if there's work to do
        let pendingModels = KoeModel.backgroundModels.filter { !isModelReady($0) }
        if pendingModels.isEmpty {
            logger.notice("All background models already ready")
            return
        }

        logger.notice("Starting background model processing for \(pendingModels.count) models")

        backgroundTask = Task {
            await processBackgroundModels()
        }
    }

    /// Pause background processing (call when transcription starts)
    public func pauseForTranscription() {
        isPausedForTranscription = true
        state.isPaused = true
        persistState()
        logger.notice("Background processing paused for transcription")
    }

    /// Resume background processing (call when transcription ends)
    public func resumeAfterTranscription() {
        isPausedForTranscription = false
        state.isPaused = false
        persistState()
        logger.notice("Background processing resumed")
    }

    /// Check if a model is ready for use
    public func isModelReady(_ model: KoeModel) -> Bool {
        // Fast is always available (installed during setup)
        if model == .fast {
            return true
        }

        // Check our state first
        if let status = state.models[model.rawValue], status.phase == .ready {
            return true
        }

        // Check file system as fallback (model might have been compiled before)
        return transcriber.isModelDownloaded(model)
    }

    /// Get current status for a model
    public func statusFor(_ model: KoeModel) -> ModelDownloadStatus? {
        state.models[model.rawValue]
    }

    /// Overall progress for all background models (0.0 - 1.0)
    public var overallProgress: Double {
        let backgroundModels = KoeModel.backgroundModels
        guard !backgroundModels.isEmpty else { return 1.0 }

        var total = 0.0
        for model in backgroundModels {
            if isModelReady(model) {
                total += 1.0
            } else if let status = state.models[model.rawValue] {
                total += status.totalProgress
            }
        }
        return total / Double(backgroundModels.count)
    }

    /// Human-readable status message
    public var statusMessage: String? {
        guard state.isProcessing else { return nil }

        if state.isPaused {
            return "Paused"
        }

        guard let currentModel = state.currentlyProcessing,
              let model = KoeModel(rawValue: currentModel),
              let status = state.models[currentModel] else {
            return nil
        }

        switch status.phase {
        case .downloading:
            let percent = Int(status.downloadProgress * 100)
            return "Downloading \(model.shortName)... \(percent)%"
        case .compiling:
            return "Optimizing \(model.shortName)..."
        default:
            return nil
        }
    }

    /// Estimated time remaining for current model
    public var estimatedTimeRemaining: TimeInterval? {
        guard let currentModel = state.currentlyProcessing,
              let status = state.models[currentModel] else {
            return nil
        }
        return status.estimatedTimeRemaining
    }

    // MARK: - Private Implementation

    private func setupObservers() {
        // Observe transcription start/end for pausing
        NotificationCenter.default.addObserver(
            forName: .dictationStarted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pauseForTranscription()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .dictationEnded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resumeAfterTranscription()
            }
        }
    }

    private func processBackgroundModels() async {
        state.isProcessing = true
        persistState()

        // Process models in order: Balanced, then Best
        for model in KoeModel.backgroundModels {
            // Skip if already ready
            if isModelReady(model) {
                logger.notice("Model \(model.shortName) already available, skipping")
                var status = ModelDownloadStatus(model: model)
                status.phase = .ready
                status.downloadProgress = 1.0
                status.compilationProgress = 1.0
                state.models[model.rawValue] = status
                continue
            }

            // Wait if paused
            while isPausedForTranscription {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            }

            // Check for cancellation
            if Task.isCancelled { break }

            // Process this model
            await processModel(model)
        }

        state.isProcessing = false
        state.currentlyProcessing = nil
        state.lastCompletedAt = Date()

        // Mark first background completion
        let allReady = KoeModel.backgroundModels.allSatisfy { isModelReady($0) }
        if allReady {
            UserDefaults.standard.set(true, forKey: hasCompletedFirstBackgroundKey)
            isFirstLaunch = false
        }

        persistState()
        backgroundTask = nil
        logger.notice("Background model processing complete")
    }

    private func processModel(_ model: KoeModel) async {
        logger.notice("Processing background model: \(model.shortName)")

        // Initialize status
        var status = ModelDownloadStatus(model: model)
        status.phase = .downloading
        status.startedAt = Date()
        state.models[model.rawValue] = status
        state.currentlyProcessing = model.rawValue
        persistState()

        do {
            // Download the model
            logger.notice("Downloading \(model.shortName)...")

            try await transcriber.downloadOnly(model) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if var s = self.state.models[model.rawValue] {
                        s.downloadProgress = progress
                        self.state.models[model.rawValue] = s
                        // Don't persist on every progress update - too frequent
                    }
                }
            }

            // Update status for compilation phase
            status.phase = .compiling
            status.downloadProgress = 1.0
            state.models[model.rawValue] = status
            persistState()

            // Wait if paused before compilation
            while isPausedForTranscription {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            // Compile the model (this is the expensive ~4 min operation)
            logger.notice("Compiling \(model.shortName)...")

            // Use a separate transcriber instance for compilation to not interfere
            // with the main app's transcriber
            let compileTranscriber = WhisperKitTranscriber()
            try await compileTranscriber.loadModel(model)

            // After compilation, unload to free memory
            compileTranscriber.unloadModel()

            // Success!
            status.phase = .ready
            status.compilationProgress = 1.0
            status.completedAt = Date()
            state.models[model.rawValue] = status
            state.currentlyProcessing = nil
            persistState()

            // Send notification
            await sendModelReadyNotification(model)

            logger.notice("Model \(model.shortName) ready!")

        } catch {
            logger.error("Failed to process model \(model.shortName): \(error)")
            status.phase = .failed
            status.errorMessage = error.localizedDescription
            state.models[model.rawValue] = status
            state.currentlyProcessing = nil
            persistState()
        }
    }

    private func sendModelReadyNotification(_ model: KoeModel) async {
        let content = UNMutableNotificationContent()
        content.title = "\(model.shortName) Mode Ready"
        content.body = "Tap to switch to \(model.shortName) for better accuracy."
        content.sound = .default
        content.userInfo = ["modelRawValue": model.rawValue]
        content.categoryIdentifier = "MODEL_READY"

        let request = UNNotificationRequest(
            identifier: "model-ready-\(model.rawValue)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.notice("Notification sent for \(model.shortName)")
        } catch {
            logger.error("Failed to send notification: \(error)")
        }

        // Also post internal notification for UI updates
        NotificationCenter.default.post(
            name: .backgroundModelReady,
            object: nil,
            userInfo: ["model": model]
        )
    }

    private func persistState() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let backgroundModelReady = Notification.Name("backgroundModelReady")
    // Note: dictationStarted and dictationEnded are defined in KoeApp.swift
}
