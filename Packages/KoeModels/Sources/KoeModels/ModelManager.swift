import Foundation
import os.log

private let logger = Logger(subsystem: "com.koe.voice", category: "ModelManager")

/// Manages model downloads and availability
@MainActor
public final class ModelManager: ObservableObject {

    public static let shared = ModelManager()

    // MARK: - Published Properties

    @Published public private(set) var modelStatuses: [String: ModelStatus] = [:]
    @Published public private(set) var isCheckingModels: Bool = false
    @Published public private(set) var overallProgress: Double = 0.0
    @Published public private(set) var currentDownloadingModel: String? = nil

    // MARK: - Private Properties

    private let fileManager = FileManager.default
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]

    /// Base directory for model storage
    public var modelsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Koe").appendingPathComponent("Models")
    }

    // MARK: - Initialization

    private init() {
        // Initialize statuses for all models
        for model in ModelRegistry.allModels {
            modelStatuses[model.id] = .notDownloaded
        }
    }

    // MARK: - Public Methods

    /// Check availability of all models
    public func checkAllModels() async {
        isCheckingModels = true
        logger.notice("[ModelManager] Checking all models...")

        for model in ModelRegistry.allModels {
            let status = await checkModel(model)
            modelStatuses[model.id] = status
            logger.notice("[ModelManager] \(model.name): \(status.isAvailable ? "available" : "not available")")
        }

        isCheckingModels = false
        updateOverallProgress()
    }

    /// Check if a specific model is available
    public func checkModel(_ model: ModelDefinition) async -> ModelStatus {
        // Check bundled first
        if let bundledPath = getBundledPath(for: model), fileManager.fileExists(atPath: bundledPath) {
            return .downloaded
        }

        // Check downloaded
        let downloadedPath = getDownloadedPath(for: model)
        if fileManager.fileExists(atPath: downloadedPath) {
            return .downloaded
        }

        return .notDownloaded
    }

    /// Check if all required models are available
    public var areRequiredModelsAvailable: Bool {
        for model in ModelRegistry.requiredModels {
            if let status = modelStatuses[model.id], !status.isAvailable {
                return false
            }
        }
        return true
    }

    /// Get the path to a model (bundled or downloaded)
    public func getModelPath(for model: ModelDefinition) -> String? {
        // Check bundled first
        if let bundledPath = getBundledPath(for: model), fileManager.fileExists(atPath: bundledPath) {
            return bundledPath
        }

        // Check downloaded
        let downloadedPath = getDownloadedPath(for: model)
        if fileManager.fileExists(atPath: downloadedPath) {
            return downloadedPath
        }

        return nil
    }

    /// Download a specific model
    public func downloadModel(_ model: ModelDefinition) async throws {
        logger.notice("[ModelManager] Downloading \(model.name)...")
        currentDownloadingModel = model.name
        modelStatuses[model.id] = .downloading(progress: 0)

        do {
            switch model.source {
            case .huggingFace(let repo, let files):
                try await downloadFromHuggingFace(model: model, repo: repo, files: files)
            case .bundled:
                // Already bundled, nothing to download
                modelStatuses[model.id] = .downloaded
            case .custom(let url):
                try await downloadFromURL(model: model, url: url)
            }

            modelStatuses[model.id] = .downloaded
            logger.notice("[ModelManager] Downloaded \(model.name)")
        } catch {
            modelStatuses[model.id] = .error(error.localizedDescription)
            logger.error("[ModelManager] Failed to download \(model.name): \(error)")
            throw error
        }

        currentDownloadingModel = nil
        updateOverallProgress()
    }

    /// Download all missing required models
    public func downloadRequiredModels() async throws {
        for model in ModelRegistry.requiredModels {
            if let status = modelStatuses[model.id], !status.isAvailable {
                try await downloadModel(model)
            }
        }
    }

    /// Download all missing models
    public func downloadAllMissingModels() async throws {
        for model in ModelRegistry.allModels {
            if let status = modelStatuses[model.id], !status.isAvailable {
                try await downloadModel(model)
            }
        }
    }

    // MARK: - Private Methods

    private func getBundledPath(for model: ModelDefinition) -> String? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }

        switch model.source {
        case .huggingFace(_, let files):
            // Check for first file in bundled models
            if let firstFile = files.first {
                let path = "\(resourcePath)/Models/\(firstFile)"
                return path
            }
        case .bundled(let relativePath):
            return "\(resourcePath)/\(relativePath)"
        case .custom:
            return nil
        }

        return nil
    }

    private func getDownloadedPath(for model: ModelDefinition) -> String {
        switch model.source {
        case .huggingFace(let repo, let files):
            // Match WhisperKit's path structure for compatibility
            if let firstFile = files.first {
                return
                    modelsDirectory
                    .appendingPathComponent("models")
                    .appendingPathComponent(repo.replacingOccurrences(of: "/", with: "_"))
                    .appendingPathComponent(firstFile)
                    .path
            }
        case .bundled(let relativePath):
            return modelsDirectory.appendingPathComponent(relativePath).path
        case .custom:
            return modelsDirectory.appendingPathComponent(model.id).path
        }

        return modelsDirectory.appendingPathComponent(model.id).path
    }

    private func downloadFromHuggingFace(model: ModelDefinition, repo: String, files: [String]) async throws {
        // Create directory if needed
        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let totalFiles = files.count
        var completedFiles = 0

        for file in files {
            let urlString = "https://huggingface.co/\(repo)/resolve/main/\(file)"
            guard let url = URL(string: urlString) else {
                throw ModelError.invalidURL(urlString)
            }

            let destinationDir =
                modelsDirectory
                .appendingPathComponent("models")
                .appendingPathComponent(repo.replacingOccurrences(of: "/", with: "_"))

            try? fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            let destination = destinationDir.appendingPathComponent(file)

            // Download file
            try await downloadFile(
                from: url, to: destination, model: model, fileIndex: completedFiles, totalFiles: totalFiles)
            completedFiles += 1
        }
    }

    private func downloadFromURL(model: ModelDefinition, url: URL) async throws {
        let destination = modelsDirectory.appendingPathComponent(model.id)
        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try await downloadFile(from: url, to: destination, model: model, fileIndex: 0, totalFiles: 1)
    }

    private func downloadFile(
        from url: URL, to destination: URL, model: ModelDefinition, fileIndex: Int, totalFiles: Int
    ) async throws {
        logger.notice("[ModelManager] Downloading file from \(url.lastPathComponent)")

        // Use bytes async sequence for progress tracking
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ModelError.downloadFailed("HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        let expectedLength = response.expectedContentLength
        var downloadedBytes: Int64 = 0

        // Create temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempURL)

        defer {
            try? fileHandle.close()
        }

        // Download with progress
        var buffer = Data()
        let bufferSize = 1024 * 64  // 64KB chunks

        for try await byte in asyncBytes {
            buffer.append(byte)
            downloadedBytes += 1

            // Write buffer when full
            if buffer.count >= bufferSize {
                try fileHandle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)

                // Update progress
                if expectedLength > 0 {
                    let fileProgress = Double(downloadedBytes) / Double(expectedLength)
                    let overallFileProgress = (Double(fileIndex) + fileProgress) / Double(totalFiles)
                    modelStatuses[model.id] = .downloading(progress: overallFileProgress)
                    updateOverallProgress()
                }
            }
        }

        // Write remaining buffer
        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
        }

        try fileHandle.close()

        // Move to final destination
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)

        logger.notice(
            "[ModelManager] Downloaded \(url.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)))"
        )
    }

    private func updateOverallProgress() {
        let totalModels = Double(ModelRegistry.requiredModels.count)
        guard totalModels > 0 else {
            overallProgress = 1.0
            return
        }

        var downloadedCount: Double = 0
        var partialProgress: Double = 0

        for model in ModelRegistry.requiredModels {
            if let status = modelStatuses[model.id] {
                switch status {
                case .downloaded:
                    downloadedCount += 1
                case .downloading(let progress):
                    partialProgress += progress
                default:
                    break
                }
            }
        }

        overallProgress = (downloadedCount + partialProgress) / totalModels
    }
}

// MARK: - Errors

public enum ModelError: LocalizedError {
    case invalidURL(String)
    case downloadFailed(String)
    case modelNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .modelNotFound(let name):
            return "Model not found: \(name)"
        }
    }
}
