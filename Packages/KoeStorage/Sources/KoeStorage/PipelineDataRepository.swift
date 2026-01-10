import Foundation

// MARK: - Node Execution Data

/// Dynamic data captured by a node during execution
/// Each node type can store different fields based on its function
public struct NodeExecutionData: Codable, Sendable {
    /// Node type identifier (e.g., "transcribe-whisperkit-balanced", "ai-fast")
    public let nodeTypeId: String

    /// Node display name for UI
    public let nodeName: String

    /// Execution timing
    public let startTime: Date
    public let endTime: Date
    public let durationMs: Double

    /// Status of this node's execution
    public let status: ExecutionStatus

    /// Input received by this node (text, audio path, etc.)
    public let input: NodeInput

    /// Output produced by this node
    public let output: NodeOutput

    /// Error information if failed
    public let error: NodeError?

    /// Node-specific custom data (flexible key-value pairs)
    /// Examples:
    /// - Transcription: ["model": "whisper-large", "language": "en", "confidence": 0.95]
    /// - AI Processing: ["prompt": "...", "tokensUsed": 150, "rewriteStyle": "formal"]
    /// - Translation: ["sourceLanguage": "en", "targetLanguage": "pt"]
    public let customData: [String: AnyCodableValue]

    public init(
        nodeTypeId: String,
        nodeName: String,
        startTime: Date,
        endTime: Date,
        status: ExecutionStatus,
        input: NodeInput,
        output: NodeOutput,
        error: NodeError? = nil,
        customData: [String: AnyCodableValue] = [:]
    ) {
        self.nodeTypeId = nodeTypeId
        self.nodeName = nodeName
        self.startTime = startTime
        self.endTime = endTime
        self.durationMs = endTime.timeIntervalSince(startTime) * 1000
        self.status = status
        self.input = input
        self.output = output
        self.error = error
        self.customData = customData
    }

    public var formattedDuration: String {
        if durationMs < 1000 {
            return String(format: "%.0fms", durationMs)
        } else {
            return String(format: "%.2fs", durationMs / 1000)
        }
    }
}

// MARK: - Execution Status

public enum ExecutionStatus: String, Codable, Sendable {
    case pending
    case running
    case success
    case skipped
    case failed
    case cancelled
}

// MARK: - Node Input/Output

/// Input received by a node
public struct NodeInput: Codable, Sendable {
    /// Type of input (text, audio, data)
    public let type: InputType

    /// Text content (if applicable)
    public let text: String?

    /// Audio file path (if applicable)
    public let audioPath: String?

    /// Audio duration in seconds (if applicable)
    public let audioDuration: Double?

    /// Character/sample count
    public let count: Int

    public enum InputType: String, Codable, Sendable {
        case text
        case audio
        case data
        case none
    }

    public init(
        type: InputType,
        text: String? = nil,
        audioPath: String? = nil,
        audioDuration: Double? = nil,
        count: Int = 0
    ) {
        self.type = type
        self.text = text
        self.audioPath = audioPath
        self.audioDuration = audioDuration
        self.count = count
    }

    public static func text(_ text: String) -> NodeInput {
        NodeInput(type: .text, text: text, count: text.count)
    }

    public static func audio(path: String, duration: Double) -> NodeInput {
        NodeInput(type: .audio, audioPath: path, audioDuration: duration)
    }

    public static let none = NodeInput(type: .none)
}

/// Output produced by a node
public struct NodeOutput: Codable, Sendable {
    /// Type of output
    public let type: OutputType

    /// Text content (if applicable)
    public let text: String?

    /// Audio path (if applicable)
    public let audioPath: String?

    /// Audio duration (if applicable)
    public let audioDuration: Double?

    /// Character/sample count
    public let count: Int

    /// Whether output differs from input (for transformation nodes)
    public let wasTransformed: Bool

    public enum OutputType: String, Codable, Sendable {
        case text
        case audio
        case action  // For nodes that perform actions (auto-type, etc.)
        case none
    }

    public init(
        type: OutputType,
        text: String? = nil,
        audioPath: String? = nil,
        audioDuration: Double? = nil,
        count: Int = 0,
        wasTransformed: Bool = false
    ) {
        self.type = type
        self.text = text
        self.audioPath = audioPath
        self.audioDuration = audioDuration
        self.count = count
        self.wasTransformed = wasTransformed
    }

    public static func text(_ text: String, wasTransformed: Bool = false) -> NodeOutput {
        NodeOutput(type: .text, text: text, count: text.count, wasTransformed: wasTransformed)
    }

    public static func audio(path: String, duration: Double) -> NodeOutput {
        NodeOutput(type: .audio, audioPath: path, audioDuration: duration)
    }

    public static let action = NodeOutput(type: .action)
    public static let none = NodeOutput(type: .none)
}

// MARK: - Node Error

public struct NodeError: Codable, Sendable {
    public let code: String
    public let message: String
    public let details: String?
    public let recoverable: Bool

    public init(
        code: String,
        message: String,
        details: String? = nil,
        recoverable: Bool = false
    ) {
        self.code = code
        self.message = message
        self.details = details
        self.recoverable = recoverable
    }

    public static func from(_ error: Error) -> NodeError {
        NodeError(
            code: String(describing: type(of: error)),
            message: error.localizedDescription,
            details: "\(error)",
            recoverable: false
        )
    }
}

// MARK: - Context Information Structs

/// System information at execution time
public struct SystemContextInfo: Codable, Sendable {
    public let macOSVersion: String
    public let deviceModel: String
    public let totalMemoryMB: Int
    public let availableMemoryMB: Int
    public let thermalState: String
    public let cpuType: String?

    public init(
        macOSVersion: String,
        deviceModel: String,
        totalMemoryMB: Int,
        availableMemoryMB: Int,
        thermalState: String,
        cpuType: String? = nil
    ) {
        self.macOSVersion = macOSVersion
        self.deviceModel = deviceModel
        self.totalMemoryMB = totalMemoryMB
        self.availableMemoryMB = availableMemoryMB
        self.thermalState = thermalState
        self.cpuType = cpuType
    }

    /// Capture current system info
    public static func current() -> SystemContextInfo {
        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersion
        let versionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        // Get model identifier
        var deviceModel = "Unknown"
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        if size > 0 {
            var model = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.model", &model, &size, nil, 0)
            deviceModel = String(cString: model)
        }

        // Get total and available memory
        let totalMemory = Int(processInfo.physicalMemory / (1024 * 1024))
        // Note: Available memory requires more complex calculation
        let availableMemory = totalMemory  // Placeholder

        // Get thermal state
        let thermalState: String
        switch processInfo.thermalState {
        case .nominal: thermalState = "nominal"
        case .fair: thermalState = "fair"
        case .serious: thermalState = "serious"
        case .critical: thermalState = "critical"
        @unknown default: thermalState = "unknown"
        }

        return SystemContextInfo(
            macOSVersion: versionString,
            deviceModel: deviceModel,
            totalMemoryMB: totalMemory,
            availableMemoryMB: availableMemory,
            thermalState: thermalState
        )
    }
}

/// Audio recording context with detailed metrics
public struct AudioContextInfo: Codable, Sendable {
    public let recordingDurationMs: Double
    public let sampleRate: Double
    public let sampleCount: Int
    public let channels: Int
    public let bitDepth: Int
    public let inputDeviceName: String?
    public let inputDeviceId: String?
    public let peakAmplitude: Float?
    public let averageAmplitude: Float?
    public let silencePercentage: Float?

    public init(
        recordingDurationMs: Double,
        sampleRate: Double,
        sampleCount: Int,
        channels: Int = 1,
        bitDepth: Int = 16,
        inputDeviceName: String? = nil,
        inputDeviceId: String? = nil,
        peakAmplitude: Float? = nil,
        averageAmplitude: Float? = nil,
        silencePercentage: Float? = nil
    ) {
        self.recordingDurationMs = recordingDurationMs
        self.sampleRate = sampleRate
        self.sampleCount = sampleCount
        self.channels = channels
        self.bitDepth = bitDepth
        self.inputDeviceName = inputDeviceName
        self.inputDeviceId = inputDeviceId
        self.peakAmplitude = peakAmplitude
        self.averageAmplitude = averageAmplitude
        self.silencePercentage = silencePercentage
    }
}

/// Transcription context with model and accuracy details
public struct TranscriptionContextInfo: Codable, Sendable {
    public let engineType: String  // "apple-speech", "whisperkit", etc.
    public let modelName: String
    public let modelVersion: String?
    public let modelSizeBytes: Int64?
    public let requestedLanguage: String
    public let detectedLanguage: String?
    public let languageConfidence: Double?
    public let overallConfidence: Double?
    public let wordCount: Int
    public let characterCount: Int
    public let wasModelPreloaded: Bool
    public let modelLoadTimeMs: Double?
    public let inferenceTimeMs: Double?
    public let tokensPerSecond: Double?

    public init(
        engineType: String,
        modelName: String,
        modelVersion: String? = nil,
        modelSizeBytes: Int64? = nil,
        requestedLanguage: String,
        detectedLanguage: String? = nil,
        languageConfidence: Double? = nil,
        overallConfidence: Double? = nil,
        wordCount: Int,
        characterCount: Int,
        wasModelPreloaded: Bool = false,
        modelLoadTimeMs: Double? = nil,
        inferenceTimeMs: Double? = nil,
        tokensPerSecond: Double? = nil
    ) {
        self.engineType = engineType
        self.modelName = modelName
        self.modelVersion = modelVersion
        self.modelSizeBytes = modelSizeBytes
        self.requestedLanguage = requestedLanguage
        self.detectedLanguage = detectedLanguage
        self.languageConfidence = languageConfidence
        self.overallConfidence = overallConfidence
        self.wordCount = wordCount
        self.characterCount = characterCount
        self.wasModelPreloaded = wasModelPreloaded
        self.modelLoadTimeMs = modelLoadTimeMs
        self.inferenceTimeMs = inferenceTimeMs
        self.tokensPerSecond = tokensPerSecond
    }
}

/// AI processing context with full prompt and token details
public struct AIContextInfo: Codable, Sendable {
    public let engineType: String  // "ai-fast", "ai-balanced", etc.
    public let modelName: String
    public let modelVersion: String?
    public let modelSizeBytes: Int64?

    // Prompt details
    public let systemPrompt: String
    public let userPrompt: String
    public let fullPromptCharCount: Int

    // Token metrics
    public let inputTokenCount: Int?
    public let outputTokenCount: Int?
    public let totalTokenCount: Int?

    // Generation settings
    public let temperature: Double?
    public let topP: Double?
    public let maxTokens: Int?

    // Performance metrics
    public let wasModelPreloaded: Bool
    public let modelLoadTimeMs: Double?
    public let timeToFirstTokenMs: Double?
    public let totalInferenceTimeMs: Double?
    public let tokensPerSecond: Double?

    // Processing mode
    public let processingMode: String  // "cleanup", "formal", "casual", "translate", etc.
    public let rewriteStyle: String?
    public let translateEnabled: Bool
    public let targetLanguage: String?

    public init(
        engineType: String,
        modelName: String,
        modelVersion: String? = nil,
        modelSizeBytes: Int64? = nil,
        systemPrompt: String,
        userPrompt: String,
        fullPromptCharCount: Int,
        inputTokenCount: Int? = nil,
        outputTokenCount: Int? = nil,
        totalTokenCount: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        wasModelPreloaded: Bool = false,
        modelLoadTimeMs: Double? = nil,
        timeToFirstTokenMs: Double? = nil,
        totalInferenceTimeMs: Double? = nil,
        tokensPerSecond: Double? = nil,
        processingMode: String,
        rewriteStyle: String? = nil,
        translateEnabled: Bool = false,
        targetLanguage: String? = nil
    ) {
        self.engineType = engineType
        self.modelName = modelName
        self.modelVersion = modelVersion
        self.modelSizeBytes = modelSizeBytes
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.fullPromptCharCount = fullPromptCharCount
        self.inputTokenCount = inputTokenCount
        self.outputTokenCount = outputTokenCount
        self.totalTokenCount = totalTokenCount
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.wasModelPreloaded = wasModelPreloaded
        self.modelLoadTimeMs = modelLoadTimeMs
        self.timeToFirstTokenMs = timeToFirstTokenMs
        self.totalInferenceTimeMs = totalInferenceTimeMs
        self.tokensPerSecond = tokensPerSecond
        self.processingMode = processingMode
        self.rewriteStyle = rewriteStyle
        self.translateEnabled = translateEnabled
        self.targetLanguage = targetLanguage
    }
}

/// User/application context
public struct UserContextInfo: Codable, Sendable {
    public let activeAppName: String?
    public let activeAppBundleId: String?
    public let activeWindowTitle: String?
    public let inputFieldType: String?  // "text_field", "text_view", "browser", etc.
    public let keyboardLayout: String?
    public let sessionId: UUID
    public let executionNumber: Int  // Count within session

    public init(
        activeAppName: String? = nil,
        activeAppBundleId: String? = nil,
        activeWindowTitle: String? = nil,
        inputFieldType: String? = nil,
        keyboardLayout: String? = nil,
        sessionId: UUID = UUID(),
        executionNumber: Int = 1
    ) {
        self.activeAppName = activeAppName
        self.activeAppBundleId = activeAppBundleId
        self.activeWindowTitle = activeWindowTitle
        self.inputFieldType = inputFieldType
        self.keyboardLayout = keyboardLayout
        self.sessionId = sessionId
        self.executionNumber = executionNumber
    }
}

// MARK: - Pipeline Execution Record (Enhanced)

/// Complete record of a pipeline execution with all node data
public struct PipelineExecutionData: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let completedAt: Date?

    /// Pipeline configuration
    public let pipelineName: String
    public let triggerType: String  // "hotkey", "voice", etc.

    /// Overall status
    public let status: ExecutionStatus
    public let totalDurationMs: Double

    /// Per-node execution data (ordered by execution)
    public let nodes: [NodeExecutionData]

    /// Final input/output for quick access
    public let originalInput: String
    public let finalOutput: String

    /// Global error if pipeline failed
    public let error: NodeError?

    /// Settings used for this execution
    public let settings: PipelineSettings

    /// Sub-pipeline settings (from composite nodes)
    public let subPipelineSettings: SubPipelineSettings?

    // MARK: - Extended Context (Optional)

    /// System information at execution time
    public let systemInfo: SystemContextInfo?

    /// Audio recording context
    public let audioContext: AudioContextInfo?

    /// Transcription context
    public let transcriptionContext: TranscriptionContextInfo?

    /// AI processing context
    public let aiContext: AIContextInfo?

    /// User/app context
    public let userContext: UserContextInfo?

    /// Session ID to group related executions
    public let sessionId: UUID?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        completedAt: Date? = nil,
        pipelineName: String,
        triggerType: String,
        status: ExecutionStatus,
        totalDurationMs: Double,
        nodes: [NodeExecutionData],
        originalInput: String,
        finalOutput: String,
        error: NodeError? = nil,
        settings: PipelineSettings,
        subPipelineSettings: SubPipelineSettings? = nil,
        systemInfo: SystemContextInfo? = nil,
        audioContext: AudioContextInfo? = nil,
        transcriptionContext: TranscriptionContextInfo? = nil,
        aiContext: AIContextInfo? = nil,
        userContext: UserContextInfo? = nil,
        sessionId: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.completedAt = completedAt
        self.pipelineName = pipelineName
        self.triggerType = triggerType
        self.status = status
        self.totalDurationMs = totalDurationMs
        self.nodes = nodes
        self.originalInput = originalInput
        self.finalOutput = finalOutput
        self.error = error
        self.settings = settings
        self.subPipelineSettings = subPipelineSettings
        self.systemInfo = systemInfo
        self.audioContext = audioContext
        self.transcriptionContext = transcriptionContext
        self.aiContext = aiContext
        self.userContext = userContext
        self.sessionId = sessionId
    }

    public var formattedDuration: String {
        if totalDurationMs < 1000 {
            return String(format: "%.0fms", totalDurationMs)
        } else {
            return String(format: "%.2fs", totalDurationMs / 1000)
        }
    }

    /// Get node data by type
    public func node(ofType typeId: String) -> NodeExecutionData? {
        nodes.first { $0.nodeTypeId == typeId }
    }

    /// Get all failed nodes
    public var failedNodes: [NodeExecutionData] {
        nodes.filter { $0.status == .failed }
    }

    /// Get the slowest node
    public var slowestNode: NodeExecutionData? {
        nodes.max(by: { $0.durationMs < $1.durationMs })
    }
}

// MARK: - Pipeline Settings

public struct PipelineSettings: Codable, Sendable {
    public let transcriptionEngine: String  // "apple-speech", "whisperkit-balanced", etc.
    public let aiEngine: String?  // "ai-fast", "ai-balanced", etc. (nil if disabled)
    public let language: String
    public let autoEnterEnabled: Bool

    public init(
        transcriptionEngine: String,
        aiEngine: String?,
        language: String,
        autoEnterEnabled: Bool
    ) {
        self.transcriptionEngine = transcriptionEngine
        self.aiEngine = aiEngine
        self.language = language
        self.autoEnterEnabled = autoEnterEnabled
    }
}

// MARK: - Sub-Pipeline Settings

/// Settings from composite node sub-pipelines (e.g., AI processing options)
public struct SubPipelineSettings: Codable, Sendable {
    /// Rewrite style if enabled ("formal", "casual", or nil)
    public let rewriteStyle: String?

    /// Whether translation is enabled
    public let translateEnabled: Bool

    /// Target language for translation (if enabled)
    public let targetLanguage: String?

    /// Any custom instructions
    public let customInstructions: String?

    public init(
        rewriteStyle: String? = nil,
        translateEnabled: Bool = false,
        targetLanguage: String? = nil,
        customInstructions: String? = nil
    ) {
        self.rewriteStyle = rewriteStyle
        self.translateEnabled = translateEnabled
        self.targetLanguage = targetLanguage
        self.customInstructions = customInstructions
    }

    /// Build prompt additions based on settings
    public var promptInstructions: String? {
        var parts: [String] = []

        if let style = rewriteStyle {
            parts.append("Rewrite in \(style) tone.")
        }

        if translateEnabled, let lang = targetLanguage {
            parts.append("Translate to \(lang).")
        }

        if let custom = customInstructions, !custom.isEmpty {
            parts.append(custom)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

// MARK: - AnyCodableValue (for dynamic custom data)

/// Type-erased codable value for flexible custom data storage
public enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodableValue].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dict)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .dictionary(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    // Convenience initializers
    public static func from(_ value: Any) -> AnyCodableValue {
        switch value {
        case let s as String: return .string(s)
        case let i as Int: return .int(i)
        case let d as Double: return .double(d)
        case let b as Bool: return .bool(b)
        case let a as [Any]: return .array(a.map { from($0) })
        case let d as [String: Any]: return .dictionary(d.mapValues { from($0) })
        default: return .null
        }
    }

    // Value extraction
    public var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    public var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    public var doubleValue: Double? {
        if case .double(let v) = self { return v }
        if case .int(let v) = self { return Double(v) }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
}

// MARK: - Pipeline Data Repository Protocol

public protocol PipelineDataRepository: Sendable {
    /// Save a pipeline execution record
    func save(_ execution: PipelineExecutionData) async throws

    /// Load a specific execution by ID
    func load(id: UUID) async throws -> PipelineExecutionData?

    /// Load recent executions (most recent first)
    func loadRecent(limit: Int) async throws -> [PipelineExecutionData]

    /// Load executions within a date range
    func load(from startDate: Date, to endDate: Date) async throws -> [PipelineExecutionData]

    /// Delete an execution
    func delete(id: UUID) async throws

    /// Delete executions older than a date
    func deleteOlderThan(_ date: Date) async throws -> Int

    /// Get total count of stored executions
    func count() async throws -> Int
}

// MARK: - JSON File Repository Implementation

public actor JSONPipelineDataRepository: PipelineDataRepository {
    private let baseDirectory: URL
    private let indexFile: URL
    private var index: ExecutionIndex

    private struct ExecutionIndex: Codable {
        var entries: [IndexEntry]

        struct IndexEntry: Codable {
            let id: UUID
            let timestamp: Date
            let status: ExecutionStatus
            let durationMs: Double
            let fileName: String
        }
    }

    public init(directory: URL? = nil) {
        let dir =
            directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Koe")
            .appendingPathComponent("PipelineData")

        self.baseDirectory = dir
        self.indexFile = dir.appendingPathComponent("index.json")
        self.index = ExecutionIndex(entries: [])

        // Create directory if needed
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Load existing index
        if let data = try? Data(contentsOf: indexFile),
            let loadedIndex = try? JSONDecoder().decode(ExecutionIndex.self, from: data)
        {
            self.index = loadedIndex
        }
    }

    public func save(_ execution: PipelineExecutionData) async throws {
        // Generate filename
        let fileName = "\(execution.id.uuidString).json"
        let fileURL = baseDirectory.appendingPathComponent(fileName)

        // Encode and save execution data
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(execution)
        try data.write(to: fileURL)

        // Update index
        let entry = ExecutionIndex.IndexEntry(
            id: execution.id,
            timestamp: execution.timestamp,
            status: execution.status,
            durationMs: execution.totalDurationMs,
            fileName: fileName
        )

        // Insert at beginning (most recent first)
        index.entries.insert(entry, at: 0)

        // Save index
        try saveIndex()
    }

    public func load(id: UUID) async throws -> PipelineExecutionData? {
        guard let entry = index.entries.first(where: { $0.id == id }) else {
            return nil
        }

        let fileURL = baseDirectory.appendingPathComponent(entry.fileName)
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PipelineExecutionData.self, from: data)
    }

    public func loadRecent(limit: Int) async throws -> [PipelineExecutionData] {
        let entries = Array(index.entries.prefix(limit))
        var results: [PipelineExecutionData] = []

        for entry in entries {
            if let execution = try await load(id: entry.id) {
                results.append(execution)
            }
        }

        return results
    }

    public func load(from startDate: Date, to endDate: Date) async throws -> [PipelineExecutionData] {
        let matchingEntries = index.entries.filter { entry in
            entry.timestamp >= startDate && entry.timestamp <= endDate
        }

        var results: [PipelineExecutionData] = []
        for entry in matchingEntries {
            if let execution = try await load(id: entry.id) {
                results.append(execution)
            }
        }

        return results
    }

    public func delete(id: UUID) async throws {
        guard let entryIndex = index.entries.firstIndex(where: { $0.id == id }) else {
            return
        }

        let entry = index.entries[entryIndex]
        let fileURL = baseDirectory.appendingPathComponent(entry.fileName)

        try? FileManager.default.removeItem(at: fileURL)
        index.entries.remove(at: entryIndex)
        try saveIndex()
    }

    public func deleteOlderThan(_ date: Date) async throws -> Int {
        let oldEntries = index.entries.filter { $0.timestamp < date }
        var deletedCount = 0

        for entry in oldEntries {
            let fileURL = baseDirectory.appendingPathComponent(entry.fileName)
            try? FileManager.default.removeItem(at: fileURL)
            deletedCount += 1
        }

        index.entries.removeAll { $0.timestamp < date }
        try saveIndex()

        return deletedCount
    }

    public func count() async throws -> Int {
        return index.entries.count
    }

    // MARK: - Private

    private func saveIndex() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(index)
        try data.write(to: indexFile)
    }
}

// MARK: - Shared Instance

extension JSONPipelineDataRepository {
    public static let shared = JSONPipelineDataRepository()
}
