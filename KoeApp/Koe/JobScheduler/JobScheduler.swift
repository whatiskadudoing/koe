import Combine
import Foundation
import KoeDomain
import KoeTranscription
import UserNotifications
import WhisperKit
import os.log

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
        // Don't add duplicate jobs - check by name since each createXxxJob() generates new UUID
        guard !jobs.contains(where: { $0.name == job.name && !$0.isCompleted && !$0.isFailed }) else {
            logger.notice("Job '\(job.name)' already in queue or processing")
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
            // Check if this job is for the requested node via the activate task
            let hasNodeTask = job.tasks.contains { $0.metadata["nodeId"] == nodeId }

            // For WhisperKit nodes, check if download/compile tasks are for THIS specific model
            let expectedModel: String?
            if nodeId == NodeTypeId.whisperKitBalanced {
                expectedModel = KoeModel.balanced.rawValue
            } else if nodeId == NodeTypeId.whisperKitAccurate {
                expectedModel = KoeModel.accurate.rawValue
            } else {
                expectedModel = nil
            }

            let hasModelTask = expectedModel != nil && job.tasks.contains {
                ($0.type == .downloadModel || $0.type == .compileModel) && $0.metadata["model"] == expectedModel
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
        if nodeId == NodeTypeId.whisperKitBalanced {
            // Use BackgroundModelService to check model status
            if BackgroundModelService.shared.isModelReady(.balanced) {
                return .ready
            }
            return .setupRequired
        }

        if nodeId == NodeTypeId.whisperKitAccurate {
            // Use BackgroundModelService to check model status
            if BackgroundModelService.shared.isModelReady(.accurate) {
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
                return  // Stop processing this job
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

            // Send macOS notification
            sendCompletionNotification(jobName: completedJobName)
        }
    }

    /// Send macOS notification when job completes
    private func sendCompletionNotification(jobName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Setup Complete"
        content.body = "\(jobName) is ready to use"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "job-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logger.error("Failed to send notification: \(error.localizedDescription)")
            }
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

        let model = KoeModel(rawValue: modelName) ?? .balanced
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
            jobs[jobIndex].tasks[taskIndex].message = "Compiling model..."
            jobs[jobIndex].tasks[taskIndex].progress = 0.1

            // Get model path
            let modelFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Koe")
                .appendingPathComponent("Models")
            let modelPath = modelFolder.appendingPathComponent(
                "models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelName)")

            guard FileManager.default.fileExists(atPath: modelPath.path) else {
                jobs[jobIndex].tasks[taskIndex].error = "Model not found at \(modelPath.path)"
                return false
            }

            jobs[jobIndex].tasks[taskIndex].progress = 0.2
            jobs[jobIndex].tasks[taskIndex].message = "Loading model..."

            // Use GPU+ANE for best performance on Mac
            // AudioEncoder: GPU handles large matrix operations efficiently
            // TextDecoder: Neural Engine optimized for sequential token generation
            let computeOptions = ModelComputeOptions(
                audioEncoderCompute: .cpuAndGPU,
                textDecoderCompute: .cpuAndNeuralEngine
            )

            logger.notice("Compiling model: \(modelName)")

            jobs[jobIndex].tasks[taskIndex].progress = 0.3
            jobs[jobIndex].tasks[taskIndex].message = "Compiling for GPU + Neural Engine..."

            // Initialize WhisperKit to compile model for optimal performance
            let _ = try await WhisperKit(
                modelFolder: modelPath.path,
                computeOptions: computeOptions,
                verbose: false,
                logLevel: .error,
                prewarm: false,  // Skip prewarm for faster setup
                load: true
            )

            jobs[jobIndex].tasks[taskIndex].progress = 0.9
            jobs[jobIndex].tasks[taskIndex].message = "Compilation complete"
            logger.notice("Model compilation complete: \(modelName)")

            return true
        } catch {
            jobs[jobIndex].tasks[taskIndex].error = error.localizedDescription
            let errorDesc = error.localizedDescription
            logger.error("Model compilation failed: \(errorDesc)")
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

        // Get the node's exclusive group for proper lifecycle management
        let nodeInfo = NodeRegistry.shared.node(for: nodeId)
        let exclusiveGroup = nodeInfo?.exclusiveGroup

        do {
            jobs[jobIndex].tasks[taskIndex].message = "Loading resources..."
            jobs[jobIndex].tasks[taskIndex].progress = 0.5

            // Use lifecycle system to activate the node
            // This handles: unloading exclusive nodes, loading this node's resources
            try await NodeLifecycleRegistry.shared.activate(nodeId, exclusiveGroup: exclusiveGroup)

            // Verify activation succeeded (for nodes with handlers)
            if let handler = NodeLifecycleRegistry.shared.handler(for: nodeId) {
                if !handler.isLoaded {
                    jobs[jobIndex].tasks[taskIndex].error = "Failed to load resources"
                    return false
                }
            }

            jobs[jobIndex].tasks[taskIndex].progress = 0.9

        } catch {
            jobs[jobIndex].tasks[taskIndex].error = "Activation failed: \(error.localizedDescription)"
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

extension Notification.Name {
    public static let jobCompleted = Notification.Name("jobCompleted")
    public static let nodeSetupCompleted = Notification.Name("nodeSetupCompleted")
}

// MARK: - Job Factory

extension JobScheduler {
    /// Create WhisperKit setup job for a specific model
    public static func createWhisperKitSetupJob(model: KoeModel) -> Job {
        let nodeId = model == .balanced ? NodeTypeId.whisperKitBalanced : NodeTypeId.whisperKitAccurate
        let displayName = model == .balanced ? "Balanced" : "Accurate"

        return Job(
            name: "\(displayName) Setup",
            icon: model == .balanced ? "gauge.with.dots.needle.50percent" : "target",
            tasks: [
                JobTask(
                    type: .downloadModel,
                    name: "Download Model (\(model.sizeString))",
                    icon: "arrow.down.circle",
                    metadata: ["model": model.rawValue]
                ),
                JobTask(
                    type: .compileModel,
                    name: "Compile Model",
                    icon: "cpu",
                    metadata: ["model": model.rawValue]
                ),
                JobTask(
                    type: .activateNode,
                    name: "Activate",
                    icon: "checkmark.circle",
                    metadata: ["nodeId": nodeId]
                ),
            ]
        )
    }
}
