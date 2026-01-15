import AppKit
import Foundation
import KoeDomain
import KoePipeline
import KoeRefinement
import KoeStorage
import KoeTextInsertion
import KoeTranscription

// MARK: - Pre-Pipeline Context

/// Context from recording and transcription phases that happen before the pipeline
/// This allows PipelineManager to include all nodes in execution data
public struct PrePipelineContext: Sendable {
    /// Which trigger started this pipeline
    public let triggerType: TriggerType

    /// When the trigger was activated
    public let triggerStartTime: Date

    /// Recording info
    public let recordingStartTime: Date
    public let recordingEndTime: Date
    public let audioSampleCount: Int
    public let audioSampleRate: Double

    /// Transcription info
    public let transcriptionStartTime: Date
    public let transcriptionEndTime: Date
    public let transcriptionEngine: String
    public let rawTranscription: String

    public enum TriggerType: String, Sendable {
        case hotkey = "hotkey-trigger"
        case voice = "voice-trigger"
        case nativeMac = "native-mac-trigger"
    }

    public init(
        triggerType: TriggerType,
        triggerStartTime: Date,
        recordingStartTime: Date,
        recordingEndTime: Date,
        audioSampleCount: Int,
        audioSampleRate: Double = 16000,
        transcriptionStartTime: Date,
        transcriptionEndTime: Date,
        transcriptionEngine: String,
        rawTranscription: String
    ) {
        self.triggerType = triggerType
        self.triggerStartTime = triggerStartTime
        self.recordingStartTime = recordingStartTime
        self.recordingEndTime = recordingEndTime
        self.audioSampleCount = audioSampleCount
        self.audioSampleRate = audioSampleRate
        self.transcriptionStartTime = transcriptionStartTime
        self.transcriptionEndTime = transcriptionEndTime
        self.transcriptionEngine = transcriptionEngine
        self.rawTranscription = rawTranscription
    }
}

/// Manages pipeline creation, configuration, and execution
/// Bridges KoePipeline stages/actions with actual Koe services
@MainActor
public final class PipelineManager {
    // MARK: - Shared Instance

    public static let shared = PipelineManager()

    // MARK: - Dependencies

    private let aiService: AIService
    private let textInserter: TextInsertionServiceImpl
    private let targetLockService: TargetLockService

    // MARK: - Pipeline State

    private var orchestrator: PipelineOrchestrator?

    // MARK: - Initialization

    public init(
        aiService: AIService = AIService.shared,
        textInserter: TextInsertionServiceImpl = TextInsertionServiceImpl(),
        targetLockService: TargetLockService = TargetLockService.shared
    ) {
        self.aiService = aiService
        self.textInserter = textInserter
        self.targetLockService = targetLockService

        // Register built-in stages and actions
        registerBuiltInElements()
    }

    // MARK: - Pipeline Creation

    /// Create a pipeline based on current app settings
    public func createPipeline(forTranscription text: String) -> (Pipeline, PipelineContext) {
        var elements: [PipelineElementInstance] = []

        // Note: For the text refinement flow, we skip audio input and transcription
        // since those happen in RecordingCoordinator before pipeline execution

        // Text Improve stage (combined: cleanup, tone, prompt mode) - single AI call via Ollama
        if AppState.shared.isRefinementEnabled {
            let config = buildImproveConfig()
            elements.append(
                PipelineElementInstance(
                    typeId: "text-improve",
                    configuration: [
                        "cleanupEnabled": AnyCodable(config.cleanupEnabled),
                        "tone": AnyCodable(config.tone),
                        "promptMode": AnyCodable(config.promptMode),
                    ]
                ))
        }

        // Auto Type action
        elements.append(
            PipelineElementInstance(
                typeId: "auto-type",
                configuration: [
                    "speed": AnyCodable("instant"),
                    "delayBefore": AnyCodable(0.1),
                ]
            ))

        // Auto Enter action (if enabled)
        if AppState.shared.isAutoEnterEnabled {
            elements.append(
                PipelineElementInstance(
                    typeId: "auto-enter",
                    configuration: [
                        "delayAfterType": AnyCodable(0.1),
                        "enterCount": AnyCodable(1),
                    ]
                ))
        }

        let pipeline = Pipeline(
            name: "Voice to Text",
            description: "Transcription processing pipeline",
            elements: elements
        )

        // Create context with initial text
        let context = PipelineContext()
        context.text = text
        context.originalText = text

        return (pipeline, context)
    }

    // MARK: - Pipeline Execution

    /// Execute the text processing pipeline
    /// Returns the final processed text
    /// - Parameters:
    ///   - text: The transcribed text to process
    ///   - prePipelineContext: Optional context from recording/transcription phases
    public func processText(
        _ text: String, prePipelineContext: PrePipelineContext? = nil
    ) async throws -> PipelineResult {
        NSLog("[Pipeline] processText called with %d chars", text.count)
        let (pipeline, context) = createPipeline(forTranscription: text)

        // Create orchestrator
        let orchestrator = PipelineOrchestrator()
        self.orchestrator = orchestrator

        // Set up element configurator to wire handlers
        await orchestrator.setElementConfigurator { [weak self] element, typeId in
            self?.configureElement(element, typeId: typeId)
        }

        // Run pipeline
        NSLog("[Pipeline] Starting pipeline with %d elements...", pipeline.elements.count)
        let resultContext = try await orchestrator.run(pipeline, initialContext: context)
        NSLog("[Pipeline] Pipeline completed in %@", resultContext.summary.formattedElapsedTime)

        self.orchestrator = nil

        // Store execution record in AppState
        let status: ElementExecutionMetrics.ExecutionStatus = .success
        let metricsArray = Array(resultContext.summary.elementMetrics.values)
        let runId = UUID()
        NSLog(
            "[Pipeline] Creating execution record with %d metrics from context, runId=%@", metricsArray.count,
            runId.uuidString)
        for (key, value) in resultContext.summary.elementMetrics {
            NSLog(
                "[Pipeline] Context metric: key='%@', type='%@', duration=%@", key, value.elementType,
                value.formattedDuration)
        }

        // Capture current settings for the execution record
        let executionSettings = PipelineExecutionSettings(
            language: "auto",
            model: KoeModel.balanced.rawValue,
            cleanupEnabled: AppState.shared.isCleanupEnabled,
            tone: AppState.shared.toneStyle,
            promptMode: AppState.shared.isPromptImproverEnabled,
            hotkeyKeyCode: AppState.shared.hotkeyKeyCode,
            hotkeyModifiers: AppState.shared.hotkeyModifiers
        )

        let executionRecord = PipelineExecutionRecord(
            id: runId,
            timestamp: Date(),
            pipelineName: pipeline.name,
            totalDurationMs: resultContext.summary.elapsedTime * 1000,
            status: status,
            elementMetrics: metricsArray,
            inputText: text,
            outputText: resultContext.text,
            settings: executionSettings
        )
        AppState.shared.addPipelineExecution(executionRecord)

        // Save enhanced execution data to JSON repository
        await saveEnhancedExecutionData(
            runId: runId,
            pipeline: pipeline,
            context: resultContext,
            inputText: text,
            metricsArray: metricsArray,
            prePipelineContext: prePipelineContext
        )

        return PipelineResult(
            originalText: text,
            processedText: resultContext.text,
            wasRefined: AppState.shared.isRefinementEnabled,
            summary: resultContext.summary,
            pipelineRunId: runId
        )
    }

    /// Cancel current pipeline execution
    public func cancel() async {
        await orchestrator?.cancel()
    }

    // MARK: - Element Configuration

    /// Configure handlers for a specific element instance
    private func configureElement(_ element: any PipelineElement, typeId: String) {
        switch typeId {
        case "text-improve":
            if let stage = element as? TextImproveStage {
                stage.processHandler = { [weak self] text, config in
                    NSLog(
                        "[TextImprove] Handler called with %d chars, config.isActive=%d", text.count,
                        config.isActive ? 1 : 0)
                    guard let self = self else {
                        NSLog("[TextImprove] self is nil, returning original text")
                        return text
                    }

                    // Check if any AI engine is actually enabled
                    let activeAI = self.getActiveAIEngine()
                    NSLog(
                        "[TextImprove] activeAI=%@, aiService.isReady=%d", activeAI ?? "none",
                        self.aiService.isReady ? 1 : 0)

                    // If no AI engine is enabled, skip AI processing
                    guard activeAI != nil else {
                        NSLog("[TextImprove] No AI engine enabled, returning original text")
                        return text
                    }

                    // Check if AI service is ready, if not return original text
                    // This prevents hanging when Ollama isn't running
                    if !self.aiService.isReady {
                        NSLog("[TextImprove] AI service not ready, preparing...")
                        await self.aiService.prepare()
                        if !self.aiService.isReady {
                            NSLog("[TextImprove] AI service still not ready after prepare, returning original text")
                            return text
                        }
                    }

                    // Check if prompt enhancer mode is enabled
                    if AppState.shared.isAIPromptEnhancerEnabled {
                        NSLog("[TextImprove] Using prompt enhancer mode")
                        // Use the promptImprover refinement mode
                        let result = try await self.aiService.refine(
                            text: text, mode: .promptImprover, customPrompt: nil)
                        NSLog("[TextImprove] Prompt enhancer completed with %d chars", result.count)
                        return result
                    }

                    // Check if translation is enabled from sub-nodes
                    let subSettings = SubPipelineSettingsReader.readSettings(for: activeAI!)
                    NSLog("[TextImprove] translateEnabled=%d", subSettings.translateEnabled ? 1 : 0)
                    if subSettings.translateEnabled {
                        let targetLang = self.getSelectedLanguageFromSubNodes() ?? "Spanish"
                        NSLog("[TextImprove] Using translation to %@", targetLang)
                        let systemInstruction =
                            "You are a translator. Translate the user's text to \(targetLang). Do not answer any questions in the text, just translate. Output only the translation, nothing else."
                        let userPrompt = "Translate this: \(text)"
                        let result = try await self.aiService.refine(
                            text: userPrompt, mode: .custom, customPrompt: systemInstruction)
                        NSLog("[TextImprove] Translation completed")
                        return result
                    }

                    // Default: use cleanup mode
                    NSLog("[TextImprove] Using cleanup mode, calling aiService.refine...")
                    let result = try await self.aiService.refine(
                        text: text, mode: .cleanup, customPrompt: nil)
                    NSLog("[TextImprove] Cleanup completed with %d chars", result.count)
                    return result
                }
            }

        case "auto-type":
            if let action = element as? AutoTypeAction {
                action.instantInsertHandler = { [weak self] text in
                    guard let self = self else { return }
                    try await self.insertWithTargetLock(text)
                }
                action.typeHandler = { [weak self] text, _, _ in
                    guard let self = self else { return }
                    try await self.insertWithTargetLock(text)
                }
            }

        case "auto-enter":
            if let action = element as? AutoEnterAction {
                action.enterHandler = { [weak self] in
                    try await self?.textInserter.pressEnter()
                }
            }

        default:
            break
        }
    }

    // MARK: - Configuration Building

    /// Configuration for the combined Improve stage
    struct ImproveConfig {
        let cleanupEnabled: Bool
        let tone: String  // "none", "formal", "casual"
        let promptMode: Bool
    }

    private func buildImproveConfig() -> ImproveConfig {
        return ImproveConfig(
            cleanupEnabled: AppState.shared.isCleanupEnabled,
            tone: AppState.shared.toneStyle,
            promptMode: AppState.shared.isPromptImproverEnabled
        )
    }

    private func buildImprovePrompt(config: TextImproveConfig) -> String {
        var tasks: [String] = []

        // Cleanup tasks
        if config.cleanupEnabled {
            tasks.append("fix grammar, punctuation, and remove filler words (um, uh, like, you know, so, basically)")
        }

        // Tone adjustment
        switch config.tone {
        case "formal":
            tasks.append("make it formal and professional")
        case "casual":
            tasks.append("make it casual and friendly")
        default:
            break
        }

        // Prompt mode - improve clarity for AI prompts
        if config.promptMode {
            tasks.append("if this is a request or instruction, improve its clarity and specificity")
        }

        // Custom instructions
        let custom = AppState.shared.customRefinementPrompt
        if !custom.isEmpty {
            tasks.append(custom)
        }

        // If nothing is enabled, just clean up
        let taskList = tasks.isEmpty ? "clean up the text" : tasks.joined(separator: ", ")

        // Note: We return empty string here because we'll put everything in the user prompt
        // This avoids the system/user message split that causes conversational responses
        return ""
    }

    // MARK: - Target Lock Integration

    /// Error thrown when text insertion target cannot be restored
    public struct TargetLostError: Error {
        public let reason: String
    }

    /// Insert text with target lock awareness.
    /// If the user switched apps, attempts to restore focus to the original target.
    /// If restoration fails, skips insertion and plays a feedback sound.
    private func insertWithTargetLock(_ text: String) async throws {
        // Check if we have a locked target and need to restore
        let result = targetLockService.prepareForInsertion()

        switch result {
        case .alreadyFocused:
            // Same app, target still valid - proceed normally
            NSLog("[Pipeline] Target still focused, inserting text")
            try await textInserter.insertText(text)

        case .restored:
            // Successfully restored focus - small delay then insert
            NSLog("[Pipeline] Focus restored to locked target, inserting text")
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms delay after app switch
            try await textInserter.insertText(text)

        case .failed(let reason):
            // Could not restore target - skip insertion, play feedback sound
            NSLog("[Pipeline] Target lost: \(reason) - skipping text insertion")

            // Play system sound to notify user
            _ = await MainActor.run {
                NSSound(named: "Basso")?.play()
            }

            // Clear the locked target since we couldn't use it
            targetLockService.clearTarget()

            // Throw error to indicate insertion was skipped
            throw TargetLostError(reason: reason)
        }

        // Clear target after successful insertion
        targetLockService.clearTarget()
    }

    // MARK: - Sub-Node Helpers

    /// Get the selected language from AI Model's sub-nodes
    /// Returns the displayName of the enabled language node, or nil if none is enabled
    private func getSelectedLanguageFromSubNodes() -> String? {
        // Get the AI Fast node (AI Model)
        guard let aiModel = NodeRegistry.shared.node(for: "ai-fast") else {
            return nil
        }

        // Find the enabled language node in the "ai-language" exclusive group
        for subNode in aiModel.subNodes {
            // Check if this is a language node
            if subNode.exclusiveGroup == "ai-language",
                let persistenceKey = subNode.persistenceKey,
                UserDefaults.standard.bool(forKey: persistenceKey)
            {
                return subNode.displayName
            }
        }

        return nil
    }

    // MARK: - Enhanced Data Capture

    /// Save detailed execution data to JSON repository for debugging and analysis
    private func saveEnhancedExecutionData(
        runId: UUID,
        pipeline: Pipeline,
        context: PipelineContext,
        inputText: String,
        metricsArray: [ElementExecutionMetrics],
        prePipelineContext: PrePipelineContext?
    ) async {
        // Build node execution data - start with pre-pipeline nodes if available
        var nodeDataList: [NodeExecutionData] = []

        // Determine active transcription and AI engines
        let activeTranscription = getActiveTranscriptionEngine()
        let activeAI = getActiveAIEngine()

        // Add pre-pipeline nodes (trigger, recorder, transcription)
        if let preCtx = prePipelineContext {
            // 1. Trigger node
            let triggerInfo = NodeRegistry.shared.nodeOrDefault(for: preCtx.triggerType.rawValue)
            nodeDataList.append(
                NodeExecutionData(
                    nodeTypeId: preCtx.triggerType.rawValue,
                    nodeName: triggerInfo.displayName,
                    startTime: preCtx.triggerStartTime,
                    endTime: preCtx.recordingStartTime,
                    status: .success,
                    input: .none,
                    output: .action,
                    customData: ["action": .string("triggered")]
                ))

            // 2. Recorder node
            let recorderInfo = NodeRegistry.shared.nodeOrDefault(for: "recorder")
            let audioDurationMs = preCtx.recordingEndTime.timeIntervalSince(preCtx.recordingStartTime) * 1000
            nodeDataList.append(
                NodeExecutionData(
                    nodeTypeId: "recorder",
                    nodeName: recorderInfo.displayName,
                    startTime: preCtx.recordingStartTime,
                    endTime: preCtx.recordingEndTime,
                    status: .success,
                    input: .none,
                    output: .audio(path: "", duration: audioDurationMs / 1000),
                    customData: [
                        "sampleCount": .int(preCtx.audioSampleCount),
                        "sampleRate": .double(preCtx.audioSampleRate),
                        "audioDurationMs": .double(audioDurationMs),
                    ]
                ))

            // 3. Transcription node
            let transcriptionInfo = NodeRegistry.shared.nodeOrDefault(for: preCtx.transcriptionEngine)
            nodeDataList.append(
                NodeExecutionData(
                    nodeTypeId: preCtx.transcriptionEngine,
                    nodeName: transcriptionInfo.displayName,
                    startTime: preCtx.transcriptionStartTime,
                    endTime: preCtx.transcriptionEndTime,
                    status: .success,
                    input: .audio(path: "", duration: audioDurationMs / 1000),
                    output: .text(preCtx.rawTranscription),
                    customData: [
                        "engine": .string(preCtx.transcriptionEngine),
                        "characterCount": .int(preCtx.rawTranscription.count),
                        "wordCount": .int(preCtx.rawTranscription.split(separator: " ").count),
                    ]
                ))
        }

        // Add nodes from pipeline execution metrics
        for metrics in metricsArray {
            // Map element types to proper node typeIds and names
            var nodeTypeId = metrics.elementType
            var nodeName: String

            // For "text-improve", map to actual AI engine being used
            if metrics.elementType == "text-improve" {
                if let aiEngine = activeAI {
                    nodeTypeId = aiEngine
                    let nodeInfo = NodeRegistry.shared.nodeOrDefault(for: aiEngine)
                    nodeName = nodeInfo.displayName
                } else {
                    nodeName = "AI Processing"
                }
            } else {
                let nodeInfo = NodeRegistry.shared.node(for: metrics.elementType)
                nodeName = nodeInfo?.displayName ?? metrics.elementType
            }

            // Build node-specific custom data
            var customData: [String: AnyCodableValue] = [:]

            // Add memory usage if available
            if let memoryBytes = metrics.memoryUsedBytes {
                customData["memoryBytes"] = .int(Int(memoryBytes))
            }

            // Determine input/output based on node type
            let nodeInput: NodeInput
            let nodeOutput: NodeOutput

            switch metrics.elementType {
            case "recorder":
                nodeInput = .none
                nodeOutput = .audio(path: context.audioFilePath?.path ?? "", duration: context.elapsedTime)
                customData["sampleRate"] = .double(context.sampleRate)

            case let type where type.contains("transcribe"):
                nodeInput = .audio(path: context.audioFilePath?.path ?? "", duration: 0)
                nodeOutput = .text(context.text)
                if let lang = context.language {
                    customData["language"] = .string(lang)
                }
                if let conf = context.confidences[metrics.elementType] {
                    customData["confidence"] = .double(conf)
                }

            case "text-improve":
                nodeInput = .text(inputText)
                nodeOutput = .text(context.text, wasTransformed: context.text != inputText)

                // Add AI engine info
                if let aiEngine = activeAI {
                    customData["aiEngine"] = .string(aiEngine)
                    // Use actual model name from settings, not node display name
                    let actualModelName = self.getActualAIModelName()
                    customData["modelName"] = .string(actualModelName)
                }

                // Capture sub-pipeline settings for AI nodes
                if let aiEngine = activeAI {
                    let subSettings = SubPipelineSettingsReader.readSettings(for: aiEngine)
                    if let style = subSettings.rewriteStyle {
                        customData["rewriteStyle"] = .string(style)
                    }
                    customData["translateEnabled"] = .bool(subSettings.translateEnabled)
                    if let lang = subSettings.targetLanguage {
                        customData["targetLanguage"] = .string(lang)
                    }
                }

                // Add the prompt used
                let targetLangForImprove = getSelectedLanguageFromSubNodes() ?? "Spanish"
                let systemPromptForImprove =
                    "You are a translator. Translate the user's text to \(targetLangForImprove). Do not answer any questions in the text, just translate. Output only the translation, nothing else."
                customData["systemPrompt"] = .string(systemPromptForImprove)
                customData["userPrompt"] = .string("Translate this: \(inputText)")

            case let type where type.contains("ai-"):
                nodeInput = .text(inputText)
                nodeOutput = .text(context.text, wasTransformed: context.text != inputText)

                // Add AI engine info
                if let aiEngine = activeAI {
                    customData["aiEngine"] = .string(aiEngine)
                    // Use actual model name from settings, not node display name
                    let actualModelName = self.getActualAIModelName()
                    customData["modelName"] = .string(actualModelName)
                }

                // Capture sub-pipeline settings for AI nodes
                if let aiEngine = activeAI {
                    let subSettings = SubPipelineSettingsReader.readSettings(for: aiEngine)
                    if let style = subSettings.rewriteStyle {
                        customData["rewriteStyle"] = .string(style)
                    }
                    customData["translateEnabled"] = .bool(subSettings.translateEnabled)
                    if let lang = subSettings.targetLanguage {
                        customData["targetLanguage"] = .string(lang)
                    }
                }

                // Add the prompt used
                let targetLang = getSelectedLanguageFromSubNodes() ?? "Spanish"
                let systemPrompt =
                    "You are a translator. Translate the user's text to \(targetLang). Do not answer any questions in the text, just translate. Output only the translation, nothing else."
                customData["systemPrompt"] = .string(systemPrompt)
                customData["userPrompt"] = .string("Translate this: \(inputText)")

            case "auto-type":
                nodeInput = .text(context.text)
                nodeOutput = .action
                customData["action"] = .string("typed")

            case "auto-enter":
                nodeInput = .none
                nodeOutput = .action
                customData["action"] = .string("enter")

            default:
                nodeInput = .text(inputText)
                nodeOutput = .text(context.text)
            }

            let status: KoeStorage.ExecutionStatus =
                switch metrics.status {
                case .success: .success
                case .skipped: .skipped
                case .failed: .failed
                case .cancelled: .cancelled
                }

            let nodeError: NodeError? = metrics.errorMessage.map {
                NodeError(code: "execution_error", message: $0)
            }

            let nodeData = NodeExecutionData(
                nodeTypeId: nodeTypeId,
                nodeName: nodeName,
                startTime: metrics.startTime,
                endTime: metrics.endTime,
                status: status,
                input: nodeInput,
                output: nodeOutput,
                error: nodeError,
                customData: customData
            )

            nodeDataList.append(nodeData)
        }

        // Sort nodes by startTime to ensure correct display order
        nodeDataList.sort { $0.startTime < $1.startTime }

        // Read sub-pipeline settings
        let subPipelineSettings: KoeStorage.SubPipelineSettings?
        if let aiEngine = activeAI {
            subPipelineSettings = SubPipelineSettingsReader.readSettings(for: aiEngine)
        } else {
            subPipelineSettings = nil
        }

        // Build pipeline settings
        let pipelineSettings = PipelineSettings(
            transcriptionEngine: activeTranscription ?? "unknown",
            aiEngine: activeAI,
            language: context.language ?? "auto",
            autoEnterEnabled: AppState.shared.isAutoEnterEnabled
        )

        // Determine overall status
        let overallStatus: KoeStorage.ExecutionStatus =
            nodeDataList.contains { $0.status == .failed }
            ? .failed
            : .success

        // Calculate total duration including pre-pipeline time
        let totalStartTime = prePipelineContext?.triggerStartTime ?? context.startTime
        let totalDurationMs = Date().timeIntervalSince(totalStartTime) * 1000

        // Get actual trigger type
        let triggerType = prePipelineContext?.triggerType.rawValue ?? "hotkey-trigger"

        // Create execution data
        let executionData = PipelineExecutionData(
            id: runId,
            timestamp: totalStartTime,
            completedAt: Date(),
            pipelineName: pipeline.name,
            triggerType: triggerType,
            status: overallStatus,
            totalDurationMs: totalDurationMs,
            nodes: nodeDataList,
            originalInput: inputText,
            finalOutput: context.text,
            error: nil,
            settings: pipelineSettings,
            subPipelineSettings: subPipelineSettings
        )

        // Save via centralized service (handles retention policy & auto-pruning)
        do {
            NSLog("[Pipeline] ABOUT TO SAVE execution data id=%@", runId.uuidString)
            try await PipelineDataService.shared.save(executionData)
            NSLog("[Pipeline] SAVED execution data via PipelineDataService, id=%@", runId.uuidString)
            // Notify UI to refresh history
            await MainActor.run {
                NotificationCenter.default.post(name: .pipelineExecutionSaved, object: nil)
            }
        } catch {
            NSLog("[Pipeline] Failed to save execution data: %@", error.localizedDescription)
        }
    }

    /// Get the active transcription engine typeId
    private func getActiveTranscriptionEngine() -> String? {
        if UserDefaults.standard.bool(forKey: "transcribeAppleSpeechEnabled") {
            return "transcribe-apple"
        }
        if UserDefaults.standard.bool(forKey: "transcribeWhisperKitBalancedEnabled") {
            return "transcribe-whisperkit-balanced"
        }
        if UserDefaults.standard.bool(forKey: "transcribeWhisperKitAccurateEnabled") {
            return "transcribe-whisperkit-accurate"
        }
        return nil
    }

    /// Get the active AI engine typeId
    private func getActiveAIEngine() -> String? {
        if UserDefaults.standard.bool(forKey: "aiProcessingFastEnabled") {
            return "ai-fast"
        }
        if UserDefaults.standard.bool(forKey: "aiProcessingBalancedEnabled") {
            return "ai-balanced"
        }
        if UserDefaults.standard.bool(forKey: "aiProcessingReasoningEnabled") {
            return "ai-reasoning"
        }
        if UserDefaults.standard.bool(forKey: "aiPromptEnhancerEnabled") {
            return "ai-prompt-enhancer"
        }
        return nil
    }

    /// Get the actual AI model name being used (e.g., "qwen2.5:7b" for Ollama)
    private func getActualAIModelName() -> String {
        let tier = AppState.shared.currentAITier
        switch tier {
        case .custom:
            // For Ollama/custom tier, use the configured model name
            let model = AppState.shared.ollamaModel
            return model.isEmpty ? "ollama" : model
        case .best:
            return "qwen-3b"
        }
    }
}

// MARK: - Pipeline Result

/// Result of pipeline execution
public struct PipelineResult {
    public let originalText: String
    public let processedText: String
    public let wasRefined: Bool
    public let summary: PipelineRunSummary
    /// ID of the pipeline execution record for linking to history
    public let pipelineRunId: UUID

    /// Text changed during processing
    public var textChanged: Bool {
        originalText != processedText
    }

    /// Character count change
    public var characterDelta: Int {
        processedText.count - originalText.count
    }
}

// MARK: - Orchestrator Extension

extension PipelineOrchestrator {
    /// Set element configurator from MainActor context
    func setElementConfigurator(_ configurator: @escaping (any PipelineElement, String) -> Void) async {
        self.elementConfigurator = configurator
    }
}
