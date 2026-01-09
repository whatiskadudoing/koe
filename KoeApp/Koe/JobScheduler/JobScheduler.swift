import Combine
import Foundation
import KoeDomain
import KoeTranscription
import os.log
import WhisperKit

private let logger = Logger(subsystem: "com.koe.app", category: "JobScheduler")

// MARK: - Job Scheduler

@MainActor
public final class JobScheduler: ObservableObject {
    public static let shared = JobScheduler()

    // MARK: - Published State

    @Published public private(set) var jobs: [Job] = []
    @Published public private(set) var isProcessing = false

    // MARK: - Private

    private var processingTask: Task<Void, Never>?
    private let persistenceKey = "JobScheduler.jobs"
    private let maxRetries = 3

    // MARK: - Init

    private init() {
        loadState()
    }

    // MARK: - Public API

    /// Submit a job to the queue
    public func submit(_ job: Job) {
        // Don't add duplicate jobs
        guard !jobs.contains(where: { $0.id == job.id }) else {
            logger.notice("Job \(job.id) already in queue")
            return
        }

        jobs.append(job)
        saveState()
        logger.notice("Submitted job: \(job.name)")
        startProcessingIfNeeded()
    }

    /// Retry a failed job
    public func retry(jobId: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }) else { return }

        // Reset failed tasks to pending
        for i in jobs[index].tasks.indices {
            if jobs[index].tasks[i].status == .failed {
                jobs[index].tasks[i].status = .pending
                jobs[index].tasks[i].error = nil
                jobs[index].tasks[i].progress = 0
            }
        }

        saveState()
        startProcessingIfNeeded()
    }

    /// Cancel and remove a job
    public func cancel(jobId: UUID) {
        jobs.removeAll { $0.id == jobId }
        saveState()
    }

    /// Clear completed jobs
    public func clearCompleted() {
        jobs.removeAll { $0.isCompleted }
        saveState()
    }

    /// Get setup state for a node (for UI)
    public func setupState(for nodeId: String) -> NodeSetupState {
        // Check if there's a job for this node
        for job in jobs {
            // Check if this job is for the requested node
            let hasNodeTask = job.tasks.contains { $0.metadata["nodeId"] == nodeId }
            let hasModelTask = job.tasks.contains {
                ($0.type == .downloadModel || $0.type == .compileModel) &&
                    nodeId == "transcribe-whisperkit"
            }

            if hasNodeTask || hasModelTask {
                if job.isCompleted {
                    return .ready
                } else if job.isFailed {
                    let errorMsg = job.tasks.first { $0.status == .failed }?.error ?? "Setup failed"
                    return .failed(errorMsg)
                } else {
                    return .settingUp(progress: job.progress)
                }
            }
        }

        // Not in queue - check if setup is needed
        if nodeId == "transcribe-whisperkit" {
            // Use BackgroundModelService to check model status
            if BackgroundModelService.shared.isModelReady(.turbo) {
                return .ready
            }
            return .setupRequired
        }

        return .notNeeded
    }

    /// Check if a node is currently being set up
    public func isSettingUp(nodeId: String) -> Bool {
        if case .settingUp = setupState(for: nodeId) {
            return true
        }
        return false
    }

    /// Pending job count (for badge)
    public var pendingCount: Int {
        jobs.filter { !$0.isCompleted && !$0.isFailed }.count
    }

    // MARK: - Processing

    private func startProcessingIfNeeded() {
        guard processingTask == nil else { return }
        guard jobs.contains(where: { !$0.isCompleted && !$0.isFailed }) else { return }

        processingTask = Task {
            await processQueue()
            processingTask = nil
        }
    }

    private func processQueue() async {
        isProcessing = true
        defer { isProcessing = false }

        while let jobIndex = jobs.firstIndex(where: { !$0.isCompleted && !$0.isFailed }) {
            await processJob(at: jobIndex)
        }
    }

    private func processJob(at jobIndex: Int) async {
        let jobName = jobs[jobIndex].name
        logger.notice("Processing job: \(jobName)")

        for taskIndex in jobs[jobIndex].tasks.indices {
            guard jobs[jobIndex].tasks[taskIndex].status == .pending else { continue }

            // Mark as running
            jobs[jobIndex].tasks[taskIndex].status = .running
            jobs[jobIndex].tasks[taskIndex].message = "Starting..."
            saveState()

            // Execute
            let success = await executeTask(jobIndex: jobIndex, taskIndex: taskIndex)

            if success {
                jobs[jobIndex].tasks[taskIndex].status = .completed
                jobs[jobIndex].tasks[taskIndex].progress = 1.0
                jobs[jobIndex].tasks[taskIndex].message = "Done"
                let taskName = jobs[jobIndex].tasks[taskIndex].name
                logger.notice("Task completed: \(taskName)")
            } else {
                jobs[jobIndex].tasks[taskIndex].status = .failed
                let taskName = jobs[jobIndex].tasks[taskIndex].name
                logger.error("Task failed: \(taskName)")
                saveState()
                return // Stop processing this job
            }

            saveState()
        }

        // Job completed
        if jobs[jobIndex].isCompleted {
            let completedJobName = jobs[jobIndex].name
            let completedJobId = jobs[jobIndex].id
            logger.notice("Job completed: \(completedJobName)")
            NotificationCenter.default.post(
                name: .jobCompleted,
                object: nil,
                userInfo: ["jobId": completedJobId]
            )
        }
    }

    private func executeTask(jobIndex: Int, taskIndex: Int) async -> Bool {
        let task = jobs[jobIndex].tasks[taskIndex]

        switch task.type {
        case .downloadModel:
            return await executeDownload(jobIndex: jobIndex, taskIndex: taskIndex)
        case .compileModel:
            return await executeCompile(jobIndex: jobIndex, taskIndex: taskIndex)
        case .activateNode:
            return await executeActivate(jobIndex: jobIndex, taskIndex: taskIndex)
        }
    }

    // MARK: - Task Executors

    private func executeDownload(jobIndex: Int, taskIndex: Int) async -> Bool {
        let task = jobs[jobIndex].tasks[taskIndex]
        guard let modelName = task.metadata["model"] else {
            jobs[jobIndex].tasks[taskIndex].error = "Missing model name"
            return false
        }

        let model = KoeModel(rawValue: modelName) ?? .turbo
        let transcriber = WhisperKitTranscriber()

        // Check if already downloaded
        if transcriber.isModelDownloaded(model) {
            logger.notice("Model already downloaded: \(modelName)")
            return true
        }

        do {
            jobs[jobIndex].tasks[taskIndex].message = "Downloading..."

            try await transcriber.downloadOnly(model) { [weak self] (progress: Double) in
                Task { @MainActor in
                    guard let self else { return }
                    self.jobs[jobIndex].tasks[taskIndex].progress = progress
                    self.jobs[jobIndex].tasks[taskIndex].message = "Downloading \(Int(progress * 100))%"
                    self.saveState()
                }
            }

            return true
        } catch {
            jobs[jobIndex].tasks[taskIndex].error = error.localizedDescription
            let errorDesc = error.localizedDescription
            logger.error("Download failed: \(errorDesc)")
            return false
        }
    }

    private func executeCompile(jobIndex: Int, taskIndex: Int) async -> Bool {
        let task = jobs[jobIndex].tasks[taskIndex]
        guard let modelName = task.metadata["model"] else {
            jobs[jobIndex].tasks[taskIndex].error = "Missing model name"
            return false
        }

        do {
            jobs[jobIndex].tasks[taskIndex].message = "Compiling for Apple Neural Engine..."
            jobs[jobIndex].tasks[taskIndex].progress = 0.1

            // Get model path
            let modelFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Koe")
                .appendingPathComponent("Models")
            let modelPath = modelFolder.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelName)")

            guard FileManager.default.fileExists(atPath: modelPath.path) else {
                jobs[jobIndex].tasks[taskIndex].error = "Model not found at \(modelPath.path)"
                return false
            }

            jobs[jobIndex].tasks[taskIndex].progress = 0.1
            jobs[jobIndex].tasks[taskIndex].message = "Preparing Neural Engine optimization..."

            // Force ANE compilation with cpuAndNeuralEngine compute options
            let aneComputeOptions = ModelComputeOptions(
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            )

            logger.notice("Starting ANE compilation for model: \(modelName)")

            // Compilation stages with estimated times (total ~4 min):
            // 1. MelSpectrogram (~5 sec)
            // 2. AudioEncoder (~90 sec - largest)
            // 3. TextDecoder (~90 sec)
            // 4. TextDecoderContextPrefill (~30 sec)
            // 5. Prewarm (~25 sec)

            // Background task to show estimated progress
            let stages = [
                (0.15, "1/4 Compiling MelSpectrogram...", 5.0),
                (0.25, "2/4 Compiling AudioEncoder (largest)...", 90.0),
                (0.55, "3/4 Compiling TextDecoder...", 90.0),
                (0.75, "4/4 Compiling TextDecoderContextPrefill...", 30.0),
                (0.85, "Warming up Neural Engine...", 25.0),
            ]

            let progressTask = Task { @MainActor in
                var accumulated: TimeInterval = 0
                for (progress, message, duration) in stages {
                    if Task.isCancelled { break }
                    self.jobs[jobIndex].tasks[taskIndex].progress = progress
                    self.jobs[jobIndex].tasks[taskIndex].message = message
                    self.saveState()
                    accumulated += duration
                    try? await Task.sleep(for: .seconds(duration))
                }
            }

            // Initialize WhisperKit with ANE options - this triggers compilation
            let _ = try await WhisperKit(
                modelFolder: modelPath.path,
                computeOptions: aneComputeOptions,
                verbose: true,
                logLevel: .debug,
                prewarm: true,
                load: true
            )

            // Cancel progress simulation
            progressTask.cancel()

            jobs[jobIndex].tasks[taskIndex].progress = 0.9
            jobs[jobIndex].tasks[taskIndex].message = "Creating ANE marker..."

            // Create marker file to indicate ANE compilation is complete
            let aneMarkerPath = modelFolder.appendingPathComponent(".ane-compiled-\(modelName)")
            try "".write(to: aneMarkerPath, atomically: true, encoding: .utf8)

            jobs[jobIndex].tasks[taskIndex].progress = 0.95
            jobs[jobIndex].tasks[taskIndex].message = "ANE compilation complete"
            logger.notice("ANE compilation complete for model: \(modelName)")

            return true
        } catch {
            jobs[jobIndex].tasks[taskIndex].error = error.localizedDescription
            let errorDesc = error.localizedDescription
            logger.error("ANE compile failed: \(errorDesc)")
            return false
        }
    }

    private func executeActivate(jobIndex: Int, taskIndex: Int) async -> Bool {
        let task = jobs[jobIndex].tasks[taskIndex]
        guard let nodeId = task.metadata["nodeId"] else {
            jobs[jobIndex].tasks[taskIndex].error = "Missing node ID"
            return false
        }

        jobs[jobIndex].tasks[taskIndex].message = "Activating..."
        jobs[jobIndex].tasks[taskIndex].progress = 0.3

        switch nodeId {
        case "transcribe-whisperkit":
            // Enable WhisperKit
            AppState.shared.isWhisperKitEnabled = true
            AppState.shared.isAppleSpeechEnabled = false

            // Load the model into the main RecordingCoordinator
            jobs[jobIndex].tasks[taskIndex].message = "Loading model..."
            jobs[jobIndex].tasks[taskIndex].progress = 0.5

            await RecordingCoordinator.shared.loadModel(.turbo)

            // Verify model is ready
            if !RecordingCoordinator.shared.isModelLoaded {
                jobs[jobIndex].tasks[taskIndex].error = "Failed to load model"
                return false
            }

            jobs[jobIndex].tasks[taskIndex].progress = 0.9
        case "transcribe-apple":
            AppState.shared.isAppleSpeechEnabled = true
            AppState.shared.isWhisperKitEnabled = false
        default:
            jobs[jobIndex].tasks[taskIndex].error = "Unknown node: \(nodeId)"
            return false
        }

        // Notify
        NotificationCenter.default.post(
            name: .nodeSetupCompleted,
            object: nil,
            userInfo: ["nodeId": nodeId]
        )

        return true
    }

    // MARK: - Persistence

    private func saveState() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(jobs) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    private func loadState() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let savedJobs = try? JSONDecoder().decode([Job].self, from: data)
        else {
            return
        }

        // Restore jobs, reset running tasks to pending
        jobs = savedJobs.map { job in
            var j = job
            j.tasks = j.tasks.map { task in
                var t = task
                if t.status == .running {
                    t.status = .pending
                }
                return t
            }
            return j
        }

        // Resume processing if needed
        startProcessingIfNeeded()
    }
}

// MARK: - Notifications

public extension Notification.Name {
    static let jobCompleted = Notification.Name("jobCompleted")
    static let nodeSetupCompleted = Notification.Name("nodeSetupCompleted")
}

// MARK: - Job Factory

public extension JobScheduler {
    /// Create WhisperKit setup job
    static func createWhisperKitSetupJob() -> Job {
        Job(
            name: "WhisperKit Setup",
            icon: "waveform",
            tasks: [
                JobTask(
                    type: .downloadModel,
                    name: "Download Model",
                    icon: "arrow.down.circle",
                    metadata: ["model": KoeModel.turbo.rawValue]
                ),
                JobTask(
                    type: .compileModel,
                    name: "Compile for Device",
                    icon: "cpu",
                    metadata: ["model": KoeModel.turbo.rawValue]
                ),
                JobTask(
                    type: .activateNode,
                    name: "Activate",
                    icon: "checkmark.circle",
                    metadata: ["nodeId": "transcribe-whisperkit"]
                ),
            ]
        )
    }
}
