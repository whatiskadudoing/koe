import Foundation
import AppKit
import KoePipeline
import KoeRefinement
import KoeTextInsertion
import KoeTranscription
import KoeDomain

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

        // Text Improve stage (combined: cleanup, tone, prompt mode) - single AI call
        if AppState.shared.isRefinementEnabled {
            let config = buildImproveConfig()
            elements.append(PipelineElementInstance(
                typeId: "text-improve",
                configuration: [
                    "cleanupEnabled": AnyCodable(config.cleanupEnabled),
                    "tone": AnyCodable(config.tone),
                    "promptMode": AnyCodable(config.promptMode),
                    "model": AnyCodable("qwen-3b")
                ]
            ))
        }

        // Auto Type action
        elements.append(PipelineElementInstance(
            typeId: "auto-type",
            configuration: [
                "speed": AnyCodable("instant"),
                "delayBefore": AnyCodable(0.1)
            ]
        ))

        // Auto Enter action (if enabled)
        if AppState.shared.isAutoEnterEnabled {
            elements.append(PipelineElementInstance(
                typeId: "auto-enter",
                configuration: [
                    "delayAfterType": AnyCodable(0.1),
                    "enterCount": AnyCodable(1)
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
    public func processText(_ text: String) async throws -> PipelineResult {
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
        NSLog("[Pipeline] Creating execution record with %d metrics from context, runId=%@", metricsArray.count, runId.uuidString)
        for (key, value) in resultContext.summary.elementMetrics {
            NSLog("[Pipeline] Context metric: key='%@', type='%@', duration=%@", key, value.elementType, value.formattedDuration)
        }

        // Capture current settings for the execution record
        let executionSettings = PipelineExecutionSettings(
            language: AppState.shared.selectedLanguage,
            model: AppState.shared.selectedModel,
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
                    guard let self = self else { return text }
                    let prompt = self.buildImprovePrompt(config: config)
                    return try await self.aiService.refine(text: text, mode: .custom, customPrompt: prompt)
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
            tasks.append("fix grammar and remove filler words (um, uh, like, you know)")
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

        return """
        Edit this text: \(taskList).
        Keep the original meaning. Do NOT add bullet points or extra structure.
        Reply with ONLY the edited text. No explanations. No quotes. Just the text.
        """
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
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms delay after app switch
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
