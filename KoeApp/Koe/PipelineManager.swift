import Foundation
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

    // MARK: - Pipeline State

    private var orchestrator: PipelineOrchestrator?

    // MARK: - Initialization

    public init(
        aiService: AIService = AIService.shared,
        textInserter: TextInsertionServiceImpl = TextInsertionServiceImpl()
    ) {
        self.aiService = aiService
        self.textInserter = textInserter

        // Register built-in stages and actions
        registerBuiltInElements()
    }

    // MARK: - Pipeline Creation

    /// Create a pipeline based on current app settings
    public func createPipeline(forTranscription text: String) -> (Pipeline, PipelineContext) {
        var elements: [PipelineElementInstance] = []

        // Note: For the text refinement flow, we skip audio input and transcription
        // since those happen in RecordingCoordinator before pipeline execution

        // Language Improvement stage (if refinement is enabled)
        if AppState.shared.isRefinementEnabled {
            let langConfig = buildLanguageImprovementConfig()
            elements.append(PipelineElementInstance(
                typeId: "language-improvement",
                configuration: [
                    "cleanupEnabled": AnyCodable(langConfig.cleanupEnabled),
                    "tone": AnyCodable(langConfig.tone.rawValue),
                    "model": AnyCodable(langConfig.model)
                ]
            ))

            // Prompt Optimizer stage (if enabled)
            if AppState.shared.isPromptImproverEnabled {
                elements.append(PipelineElementInstance(
                    typeId: "prompt-optimizer",
                    configuration: [
                        "addStructure": AnyCodable(true),
                        "removeAmbiguity": AnyCodable(true),
                        "makeSpecific": AnyCodable(true)
                    ]
                ))
            }
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

        let executionRecord = PipelineExecutionRecord(
            id: runId,
            timestamp: Date(),
            pipelineName: pipeline.name,
            totalDurationMs: resultContext.summary.elapsedTime * 1000,
            status: status,
            elementMetrics: metricsArray,
            inputText: text,
            outputText: resultContext.text
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
        case "language-improvement":
            if let stage = element as? LanguageImprovementStage {
                stage.processHandler = { [weak self] text, config in
                    guard let self = self else { return text }
                    let prompt = self.buildRefinementPrompt(config: config)
                    return try await self.aiService.refine(text: text, mode: .custom, customPrompt: prompt)
                }
            }

        case "prompt-optimizer":
            if let stage = element as? PromptOptimizerStage {
                stage.processHandler = { [weak self] text, config in
                    guard let self = self else { return text }
                    let prompt = self.buildPromptOptimizerPrompt(config: config)
                    return try await self.aiService.refine(text: text, mode: .custom, customPrompt: prompt)
                }
            }

        case "auto-type":
            if let action = element as? AutoTypeAction {
                action.instantInsertHandler = { [weak self] text in
                    try await self?.textInserter.insertText(text)
                }
                action.typeHandler = { [weak self] text, _, _ in
                    try await self?.textInserter.insertText(text)
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

    private func buildLanguageImprovementConfig() -> LanguageImprovementConfig {
        let tone: ToneOption
        switch AppState.shared.toneStyle {
        case "formal": tone = .formal
        case "casual": tone = .casual
        default: tone = .none
        }

        return LanguageImprovementConfig(
            cleanupEnabled: AppState.shared.isCleanupEnabled,
            tone: tone,
            model: "qwen-3b"
        )
    }

    private func buildRefinementPrompt(config: LanguageImprovementConfig) -> String {
        var tasks: [String] = []

        if config.cleanupEnabled {
            tasks.append("fix grammar, remove filler words like um/uh/like/you know")
        }

        switch config.tone {
        case .formal:
            tasks.append("make it formal and professional")
        case .casual:
            tasks.append("make it casual and friendly")
        case .none:
            break
        }

        let custom = AppState.shared.customRefinementPrompt
        if !custom.isEmpty {
            tasks.append(custom)
        }

        let taskList = tasks.isEmpty ? "clean up the text" : tasks.joined(separator: ", ")

        return """
        Edit this text: \(taskList).
        Reply with ONLY the edited text. No explanations. No quotes. Just the text.
        """
    }

    private func buildPromptOptimizerPrompt(config: PromptOptimizerConfig) -> String {
        // More conservative prompt - only optimize if text is clearly a request/instruction
        return """
        If this text is a request or instruction for an AI, improve its clarity.
        If it's just casual speech or a simple statement, return it unchanged.
        Do NOT add bullet points, lists, or extra structure unless absolutely needed.
        Reply with ONLY the text. No explanations.
        """
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
