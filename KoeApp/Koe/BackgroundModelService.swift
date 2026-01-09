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
public struct ModelDownloadStatus: Codable, Sendable, Equatable {
    public var model: KoeModel
    public var phase: ModelPhase
    public var downloadProgress: Double  // 0.0 - 1.0
    public var compilationProgress: Double  // 0.0 - 1.0
    public var errorMessage: String?
    public var startedAt: Date?
    public var completedAt: Date?
    public var retryCount: Int  // Number of retry attempts made
    public var lastFailedAt: Date?  // When the last failure occurred

    public init(model: KoeModel) {
        self.model = model
        self.phase = .pending
        self.downloadProgress = 0
        self.compilationProgress = 0
        self.retryCount = 0
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

/// Aggregated state for background model processing (for persistence)
public struct BackgroundModelState: Codable, Equatable {
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

    // MARK: - Published State (individual properties for better SwiftUI observation)
    @Published public private(set) var isProcessing: Bool = false
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var currentModelName: String?
    @Published public private(set) var currentPhase: ModelPhase = .pending
    @Published public private(set) var currentDownloadProgress: Double = 0
    @Published public private(set) var currentCompilationProgress: Double = 0
    @Published public private(set) var modelStatuses: [String: ModelDownloadStatus] = [:]
    @Published public private(set) var isFirstLaunch: Bool = false
    @Published public private(set) var hasPendingWork: Bool = false

    /// Whether to automatically switch to better models when they become ready
    @Published public var autoSwitchToNewModels: Bool {
        didSet {
            UserDefaults.standard.set(autoSwitchToNewModels, forKey: autoSwitchKey)
        }
    }

    // MARK: - Private
    private let transcriber = WhisperKitTranscriber()
    private let logger = Logger(subsystem: "com.koe.voice", category: "BackgroundModels")
    private var backgroundTask: Task<Void, Never>?
    private var isPausedForTranscription = false

    // UserDefaults keys
    private let stateKey = "BackgroundModelState"
    private let hasCompletedFirstBackgroundKey = "HasCompletedFirstBackground"
    private let autoSwitchKey = "AutoSwitchToNewModels"

    // Retry configuration
    private let maxRetries = 3
    private let baseRetryDelaySeconds: UInt64 = 30  // 30 seconds, doubles each retry

    private init() {
        // Initialize auto-switch preference (defaults to true for new users)
        // Use object(forKey:) to check if preference was ever set
        if UserDefaults.standard.object(forKey: autoSwitchKey) == nil {
            // Never set before - will be set by explanation screen
            self.autoSwitchToNewModels = true  // Default to auto
        } else {
            self.autoSwitchToNewModels = UserDefaults.standard.bool(forKey: autoSwitchKey)
        }

        logger.notice("BackgroundModelService initializing...")

        // Load persisted state
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let savedState = try? JSONDecoder().decode(BackgroundModelState.self, from: data) {
            logger.notice("Loaded persisted state: isProcessing=\(savedState.isProcessing), models=\(savedState.models.count)")
            // Restore individual properties from saved state
            self.modelStatuses = savedState.models
            self.isPaused = savedState.isPaused
            self.currentModelName = savedState.currentlyProcessing

            // If was processing before, we need to resume
            if savedState.isProcessing {
                logger.notice("Previous session was processing - will resume")
            }
        }

        // Check if this is first launch (no background models completed yet)
        isFirstLaunch = !UserDefaults.standard.bool(forKey: hasCompletedFirstBackgroundKey)

        // Check if there's pending work
        updateHasPendingWork()

        logger.notice("BackgroundModelService initialized: isFirstLaunch=\(self.isFirstLaunch), hasPendingWork=\(self.hasPendingWork), autoSwitch=\(self.autoSwitchToNewModels)")

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
            hasPendingWork = false
            return
        }

        logger.notice("Starting background model processing for \(pendingModels.count) models: \(pendingModels.map { $0.shortName })")

        backgroundTask = Task {
            await processBackgroundModels()
        }
    }

    /// Pause background processing (call when transcription starts)
    public func pauseForTranscription() {
        isPausedForTranscription = true
        isPaused = true
        persistState()
        logger.notice("Background processing paused for transcription")
    }

    /// Resume background processing (call when transcription ends)
    public func resumeAfterTranscription() {
        isPausedForTranscription = false
        isPaused = false
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
        if let status = modelStatuses[model.rawValue], status.phase == .ready {
            return true
        }

        // Check file system as fallback (model might have been compiled before)
        let isDownloaded = transcriber.isModelDownloaded(model)
        if isDownloaded {
            // Update our state to reflect this
            var status = ModelDownloadStatus(model: model)
            status.phase = .ready
            status.downloadProgress = 1.0
            status.compilationProgress = 1.0
            modelStatuses[model.rawValue] = status
        }
        return isDownloaded
    }

    /// Get current status for a model
    public func statusFor(_ model: KoeModel) -> ModelDownloadStatus? {
        modelStatuses[model.rawValue]
    }

    /// Overall progress for all background models (0.0 - 1.0)
    public var overallProgress: Double {
        let backgroundModels = KoeModel.backgroundModels
        guard !backgroundModels.isEmpty else { return 1.0 }

        var total = 0.0
        for model in backgroundModels {
            if isModelReady(model) {
                total += 1.0
            } else if let status = modelStatuses[model.rawValue] {
                total += status.totalProgress
            }
        }
        return total / Double(backgroundModels.count)
    }

    /// Human-readable status message
    public var statusMessage: String? {
        if isPaused {
            return "Paused"
        }

        guard isProcessing, let modelName = currentModelName,
              let model = KoeModel(rawValue: modelName) else {
            // Show pending models if not processing yet
            if hasPendingWork && !isProcessing {
                let pending = KoeModel.backgroundModels.filter { !isModelReady($0) }
                let names = pending.map { $0.shortName }.joined(separator: ", ")
                return "\(names) modes will download in background"
            }
            return nil
        }

        // Check if this is a retry attempt
        let retryInfo: String
        if let status = modelStatuses[modelName], status.retryCount > 0 {
            retryInfo = " (retry \(status.retryCount)/\(maxRetries))"
        } else {
            retryInfo = ""
        }

        switch currentPhase {
        case .downloading:
            let percent = Int(currentDownloadProgress * 100)
            return "Downloading \(model.shortName)... \(percent)%\(retryInfo)"
        case .compiling:
            return "Optimizing \(model.shortName)...\(retryInfo)"
        default:
            return nil
        }
    }

    /// Estimated time remaining for current model
    public var estimatedTimeRemaining: TimeInterval? {
        guard let modelName = currentModelName,
              let status = modelStatuses[modelName] else {
            return nil
        }
        return status.estimatedTimeRemaining
    }

    // MARK: - Private Implementation

    private func updateHasPendingWork() {
        // Check for models that need work (not ready AND not permanently failed)
        let pending = KoeModel.backgroundModels.filter { model in
            if isModelReady(model) { return false }
            // Check if permanently failed (all retries exhausted)
            if let status = modelStatuses[model.rawValue],
               status.phase == .failed && status.retryCount > maxRetries {
                return false
            }
            return true
        }
        hasPendingWork = !pending.isEmpty
        logger.notice("Pending work check: \(pending.count) models pending, hasPendingWork=\(self.hasPendingWork)")
    }

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
        isProcessing = true
        persistState()

        logger.notice("processBackgroundModels started")

        // Process models in order: Balanced, then Best
        for model in KoeModel.backgroundModels {
            // Skip if already ready
            if isModelReady(model) {
                logger.notice("Model \(model.shortName) already available, skipping")
                var status = ModelDownloadStatus(model: model)
                status.phase = .ready
                status.downloadProgress = 1.0
                status.compilationProgress = 1.0
                modelStatuses[model.rawValue] = status
                continue
            }

            // Skip if permanently failed (all retries exhausted)
            if let status = modelStatuses[model.rawValue],
               status.phase == .failed && status.retryCount > maxRetries {
                logger.notice("Model \(model.shortName) permanently failed after \(status.retryCount) attempts, skipping")
                continue
            }

            // Wait if paused
            while isPausedForTranscription {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            }

            // Check for cancellation
            if Task.isCancelled { break }

            // Process this model (will retry if previously failed with retries remaining)
            await processModel(model)
        }

        isProcessing = false
        currentModelName = nil
        currentPhase = .pending
        currentDownloadProgress = 0
        currentCompilationProgress = 0

        // Mark first background completion
        let allReady = KoeModel.backgroundModels.allSatisfy { isModelReady($0) }
        if allReady {
            UserDefaults.standard.set(true, forKey: hasCompletedFirstBackgroundKey)
            isFirstLaunch = false
            hasPendingWork = false

            // Send final notification that everything is ready
            await sendAllModelsReadyNotification()
        }

        persistState()
        backgroundTask = nil
        logger.notice("Background model processing complete. All ready: \(allReady)")
    }

    private func processModel(_ model: KoeModel) async {
        logger.notice("Processing background model: \(model.shortName)")

        // Get existing status or create new one (preserves retry count across app restarts)
        var status = modelStatuses[model.rawValue] ?? ModelDownloadStatus(model: model)

        // Retry loop with exponential backoff
        while status.retryCount <= maxRetries {
            // Reset for this attempt
            status.phase = .downloading
            status.startedAt = Date()
            status.downloadProgress = 0
            status.compilationProgress = 0
            status.errorMessage = nil
            modelStatuses[model.rawValue] = status
            currentModelName = model.rawValue
            currentPhase = .downloading
            currentDownloadProgress = 0
            persistState()

            let attemptNumber = status.retryCount + 1
            logger.notice("Attempt \(attemptNumber)/\(self.maxRetries + 1) for \(model.shortName)")

            do {
                // Download the model
                logger.notice("Downloading \(model.shortName)...")

                try await transcriber.downloadOnly(model) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.currentDownloadProgress = progress
                        if var s = self.modelStatuses[model.rawValue] {
                            s.downloadProgress = progress
                            self.modelStatuses[model.rawValue] = s
                        }
                    }
                }

                // Update status for compilation phase
                status.phase = .compiling
                status.downloadProgress = 1.0
                modelStatuses[model.rawValue] = status
                currentPhase = .compiling
                currentDownloadProgress = 1.0
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
                modelStatuses[model.rawValue] = status
                currentModelName = nil
                currentPhase = .pending
                currentCompilationProgress = 1.0
                persistState()

                // Auto-switch to better model if enabled
                if autoSwitchToNewModels {
                    await autoSwitchToModel(model)
                }

                // Send notification
                await sendModelReadyNotification(model)

                logger.notice("Model \(model.shortName) ready!")
                return  // Success, exit retry loop

            } catch {
                status.retryCount += 1
                status.lastFailedAt = Date()
                status.errorMessage = error.localizedDescription
                logger.error("Attempt \(attemptNumber) failed for \(model.shortName): \(error)")

                if status.retryCount > maxRetries {
                    // All retries exhausted
                    logger.error("All \(self.maxRetries + 1) attempts failed for \(model.shortName)")
                    status.phase = .failed
                    modelStatuses[model.rawValue] = status
                    currentModelName = nil
                    currentPhase = .failed
                    persistState()
                    return
                }

                // Exponential backoff: 30s, 60s, 120s
                let delaySeconds = baseRetryDelaySeconds * UInt64(1 << (status.retryCount - 1))
                logger.notice("Waiting \(delaySeconds) seconds before retry \(status.retryCount + 1)...")
                modelStatuses[model.rawValue] = status
                persistState()

                // Wait before retry (check for cancellation)
                try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)

                // Wait if paused during retry delay
                while isPausedForTranscription {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }

                if Task.isCancelled {
                    logger.notice("Task cancelled, stopping retries for \(model.shortName)")
                    return
                }
            }
        }
    }

    private func autoSwitchToModel(_ model: KoeModel) async {
        logger.notice("Auto-switching to \(model.shortName) model")

        // Update AppState's selected model
        AppState.shared.selectedModel = model.rawValue

        // Load the new model
        await RecordingCoordinator.shared.loadModel(name: model.rawValue)

        logger.notice("Auto-switched to \(model.shortName)")
    }

    private func sendModelReadyNotification(_ model: KoeModel) async {
        let content = UNMutableNotificationContent()
        content.title = "\(model.shortName) Mode Ready"

        // Different message based on auto-switch setting
        if autoSwitchToNewModels {
            content.body = "Switched to \(model.shortName) for better accuracy."
        } else {
            content.body = "Tap to switch to \(model.shortName) for better accuracy."
        }
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

    private func sendAllModelsReadyNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Koe is Fully Optimized!"
        content.body = "All speech recognition models are ready. Your app is now at full power."
        content.sound = .default
        content.categoryIdentifier = "ALL_MODELS_READY"

        let request = UNNotificationRequest(
            identifier: "all-models-ready",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.notice("All models ready notification sent")
        } catch {
            logger.error("Failed to send all models ready notification: \(error)")
        }
    }

    private func persistState() {
        let state = BackgroundModelState(
            models: modelStatuses,
            isProcessing: isProcessing,
            isPaused: isPaused,
            currentlyProcessing: currentModelName,
            lastCompletedAt: nil
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }
}

// Helper extension to create state from individual properties
extension BackgroundModelState {
    init(models: [String: ModelDownloadStatus], isProcessing: Bool, isPaused: Bool, currentlyProcessing: String?, lastCompletedAt: Date?) {
        self.models = models
        self.isProcessing = isProcessing
        self.isPaused = isPaused
        self.currentlyProcessing = currentlyProcessing
        self.lastCompletedAt = lastCompletedAt
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let backgroundModelReady = Notification.Name("backgroundModelReady")
    // Note: dictationStarted and dictationEnded are defined in KoeApp.swift
}
