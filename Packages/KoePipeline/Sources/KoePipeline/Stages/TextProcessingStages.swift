import Foundation

/// Tone options for language improvement
public enum ToneOption: String, Codable, Sendable, CaseIterable {
    case none = "none"
    case formal = "formal"
    case casual = "casual"

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .formal: return "Formal"
        case .casual: return "Casual"
        }
    }

    public var description: String {
        switch self {
        case .none: return "Keep original tone"
        case .formal: return "Professional, business style"
        case .casual: return "Friendly, conversational"
        }
    }
}

/// Configuration for Language Improvement stage
public struct LanguageImprovementConfig: Codable, Sendable, Equatable {
    /// Enable cleanup (remove fillers, fix grammar)
    public var cleanupEnabled: Bool

    /// Tone adjustment
    public var tone: ToneOption

    /// Model to use
    public var model: String

    public static let `default` = LanguageImprovementConfig(
        cleanupEnabled: true,
        tone: .none,
        model: "qwen-3b"
    )

    public init(cleanupEnabled: Bool, tone: ToneOption, model: String) {
        self.cleanupEnabled = cleanupEnabled
        self.tone = tone
        self.model = model
    }

    /// Whether any processing is enabled
    public var isActive: Bool {
        cleanupEnabled || tone != .none
    }
}

/// Language Improvement stage - combines cleanup and tone adjustment
/// Uses a single model load for efficiency
public final class LanguageImprovementStage: SleepableElementBase, SleepableElement, PipelineStage,
    ResourceTrackingElement, @unchecked Sendable
{
    // MARK: - PipelineStage Protocol

    public let stageTypeId = "language-improvement"
    public var id: String { stageTypeId }
    public let displayName = "Language Improvement"
    public let description = "Clean up text and adjust tone"
    public let icon = "text.badge.checkmark"

    public var constraints: ElementConstraints {
        // Note: Removed cannotBeFirst to allow text-only pipelines where this is the first stage
        [.cannotBeLast, .optional]
    }

    public var connectionRules: ConnectionRules {
        ConnectionRules(
            acceptsInput: [.text, .richText],
            producesOutput: .text
        )
    }

    public var isEnabled: Bool = true

    public var configuration: [String: Any] {
        get {
            [
                "cleanupEnabled": config.cleanupEnabled,
                "tone": config.tone.rawValue,
                "model": config.model,
            ]
        }
        set {
            if let cleanup = newValue["cleanupEnabled"] as? Bool {
                config.cleanupEnabled = cleanup
            }
            if let toneRaw = newValue["tone"] as? String,
                let tone = ToneOption(rawValue: toneRaw)
            {
                config.tone = tone
            }
            if let model = newValue["model"] as? String {
                config.model = model
            }
        }
    }

    // MARK: - Stage-Specific

    /// Stage configuration
    public var config: LanguageImprovementConfig = .default

    /// Combined handler (more efficient - single model call)
    public var processHandler: ((String, LanguageImprovementConfig) async throws -> String)?

    // MARK: - Resource Tracking

    private var _resourceUsage: ResourceUsage = .zero

    public var resourceUsage: ResourceUsage { _resourceUsage }

    public var estimatedResourceUsage: ResourceUsage {
        ResourceUsage(
            memoryBytes: 2_000_000_000,  // ~2GB for Qwen 3B
            modelLoaded: false,
            gpuMemoryBytes: 2_000_000_000
        )
    }

    // MARK: - Initialization

    public init(config: LanguageImprovementConfig = .default, sleepConfig: SleepConfiguration = .default) {
        self.config = config
        super.init(sleepConfig: sleepConfig)
    }

    // MARK: - SleepableElement

    public func wake() async throws {
        _resourceUsage = estimatedResourceUsage
    }

    public func sleep() async {
        setState(.shuttingDown)
        _resourceUsage = .zero
        setState(.sleeping)
    }

    // MARK: - Processing

    public func prepare() async throws {
        if !sleepConfig.enabled || sleepConfig.preWarm {
            try await ensureAwake()
        }
    }

    public func process(_ context: PipelineContext) async throws {
        guard config.isActive else { return }
        guard !context.text.isEmpty else { return }

        try await ensureAwake()
        setState(.processing)
        defer { setState(.idle) }

        if let handler = processHandler {
            context.text = try await handler(context.text, config)
        }
    }

    public func cleanup() async {
        if sleepConfig.enabled {
            await sleep()
        }
    }
}

/// Configuration for Prompt Optimizer stage
public struct PromptOptimizerConfig: Codable, Sendable, Equatable {
    /// Add structure (bullet points, numbered steps)
    public var addStructure: Bool

    /// Remove ambiguity and vague language
    public var removeAmbiguity: Bool

    /// Make specific and actionable
    public var makeSpecific: Bool

    /// Model to use
    public var model: String

    public static let `default` = PromptOptimizerConfig(
        addStructure: true,
        removeAmbiguity: true,
        makeSpecific: true,
        model: "qwen-3b"
    )

    public init(addStructure: Bool, removeAmbiguity: Bool, makeSpecific: Bool, model: String) {
        self.addStructure = addStructure
        self.removeAmbiguity = removeAmbiguity
        self.makeSpecific = makeSpecific
        self.model = model
    }

    /// Build instruction hints based on config
    public var instructionHints: [String] {
        var hints: [String] = []
        if addStructure { hints.append("add structure") }
        if removeAmbiguity { hints.append("remove ambiguity") }
        if makeSpecific { hints.append("make specific") }
        return hints
    }
}

/// Prompt Optimizer stage - optimizes text as an AI prompt
public final class PromptOptimizerStage: SleepableElementBase, SleepableElement, PipelineStage, ResourceTrackingElement,
    @unchecked Sendable
{
    // MARK: - PipelineStage Protocol

    public let stageTypeId = "prompt-optimizer"
    public var id: String { stageTypeId }
    public let displayName = "Prompt Optimizer"
    public let description = "Optimize text as AI prompt"
    public let icon = "sparkles"

    public var constraints: ElementConstraints {
        [.cannotBeFirst, .cannotBeLast, .optional]
    }

    public var connectionRules: ConnectionRules {
        ConnectionRules(
            acceptsInput: [.text, .richText],
            producesOutput: .text
        )
    }

    public var isEnabled: Bool = true

    public var configuration: [String: Any] {
        get {
            [
                "addStructure": config.addStructure,
                "removeAmbiguity": config.removeAmbiguity,
                "makeSpecific": config.makeSpecific,
                "model": config.model,
            ]
        }
        set {
            if let v = newValue["addStructure"] as? Bool { config.addStructure = v }
            if let v = newValue["removeAmbiguity"] as? Bool { config.removeAmbiguity = v }
            if let v = newValue["makeSpecific"] as? Bool { config.makeSpecific = v }
            if let v = newValue["model"] as? String { config.model = v }
        }
    }

    // MARK: - Stage-Specific

    public var config: PromptOptimizerConfig = .default

    /// Handler for prompt optimization (injected from app)
    public var processHandler: ((String, PromptOptimizerConfig) async throws -> String)?

    // MARK: - Resource Tracking

    private var _resourceUsage: ResourceUsage = .zero

    public var resourceUsage: ResourceUsage { _resourceUsage }

    public var estimatedResourceUsage: ResourceUsage {
        ResourceUsage(
            memoryBytes: 2_000_000_000,
            modelLoaded: false,
            gpuMemoryBytes: 2_000_000_000
        )
    }

    // MARK: - Initialization

    public init(config: PromptOptimizerConfig = .default, sleepConfig: SleepConfiguration = .default) {
        self.config = config
        super.init(sleepConfig: sleepConfig)
    }

    // MARK: - SleepableElement

    public func wake() async throws {
        _resourceUsage = estimatedResourceUsage
    }

    public func sleep() async {
        setState(.shuttingDown)
        _resourceUsage = .zero
        setState(.sleeping)
    }

    // MARK: - Processing

    public func prepare() async throws {
        if !sleepConfig.enabled || sleepConfig.preWarm {
            try await ensureAwake()
        }
    }

    public func process(_ context: PipelineContext) async throws {
        guard !context.text.isEmpty else { return }

        try await ensureAwake()
        setState(.processing)
        defer { setState(.idle) }

        if let handler = processHandler {
            context.text = try await handler(context.text, config)
        }

        context.setCustomData(true, forKey: "prompt_optimized")
        context.setCustomData(config.instructionHints, forKey: "prompt_hints_applied")
    }

    public func cleanup() async {
        if sleepConfig.enabled {
            await sleep()
        }
    }
}

// MARK: - Combined Text Improve Stage

/// Configuration for the combined Text Improve stage
public struct TextImproveConfig: Codable, Sendable, Equatable {
    /// Enable cleanup (remove fillers, fix grammar)
    public var cleanupEnabled: Bool

    /// Tone: "none", "formal", "casual"
    public var tone: String

    /// Enable prompt mode (optimize for AI prompts)
    public var promptMode: Bool

    /// Model to use
    public var model: String

    public static let `default` = TextImproveConfig(
        cleanupEnabled: true,
        tone: "none",
        promptMode: false,
        model: "qwen-3b"
    )

    public init(cleanupEnabled: Bool, tone: String, promptMode: Bool, model: String) {
        self.cleanupEnabled = cleanupEnabled
        self.tone = tone
        self.promptMode = promptMode
        self.model = model
    }

    /// Whether any processing is enabled
    public var isActive: Bool {
        cleanupEnabled || tone != "none" || promptMode
    }

    /// Summary of active settings
    public var summary: String {
        var parts: [String] = []
        if cleanupEnabled { parts.append("cleanup") }
        if tone != "none" { parts.append(tone) }
        if promptMode { parts.append("prompt") }
        return parts.isEmpty ? "none" : parts.joined(separator: " + ")
    }
}

/// Combined Text Improve stage - cleanup, tone, and prompt mode in a single AI call
public final class TextImproveStage: SleepableElementBase, SleepableElement, PipelineStage, ResourceTrackingElement,
    @unchecked Sendable
{
    // MARK: - PipelineStage Protocol

    public let stageTypeId = "text-improve"
    public var id: String { stageTypeId }
    public let displayName = "Text Improve"
    public let description = "Improve text: cleanup, tone, and prompt optimization"
    public let icon = "sparkles"

    public var constraints: ElementConstraints {
        [.cannotBeLast, .optional]
    }

    public var connectionRules: ConnectionRules {
        ConnectionRules(
            acceptsInput: [.text, .richText],
            producesOutput: .text
        )
    }

    public var isEnabled: Bool = true

    public var configuration: [String: Any] {
        get {
            [
                "cleanupEnabled": config.cleanupEnabled,
                "tone": config.tone,
                "promptMode": config.promptMode,
                "model": config.model,
            ]
        }
        set {
            if let cleanup = newValue["cleanupEnabled"] as? Bool {
                config.cleanupEnabled = cleanup
            }
            if let tone = newValue["tone"] as? String {
                config.tone = tone
            }
            if let promptMode = newValue["promptMode"] as? Bool {
                config.promptMode = promptMode
            }
            if let model = newValue["model"] as? String {
                config.model = model
            }
        }
    }

    // MARK: - Stage-Specific

    /// Stage configuration
    public var config: TextImproveConfig = .default

    /// Handler for text improvement (injected from app)
    public var processHandler: ((String, TextImproveConfig) async throws -> String)?

    // MARK: - Resource Tracking

    private var _resourceUsage: ResourceUsage = .zero

    public var resourceUsage: ResourceUsage { _resourceUsage }

    public var estimatedResourceUsage: ResourceUsage {
        ResourceUsage(
            memoryBytes: 2_000_000_000,  // ~2GB for Qwen 3B
            modelLoaded: false,
            gpuMemoryBytes: 2_000_000_000
        )
    }

    // MARK: - Initialization

    public init(config: TextImproveConfig = .default, sleepConfig: SleepConfiguration = .default) {
        self.config = config
        super.init(sleepConfig: sleepConfig)
    }

    // MARK: - SleepableElement

    public func wake() async throws {
        _resourceUsage = estimatedResourceUsage
    }

    public func sleep() async {
        setState(.shuttingDown)
        _resourceUsage = .zero
        setState(.sleeping)
    }

    // MARK: - Processing

    public func prepare() async throws {
        if !sleepConfig.enabled || sleepConfig.preWarm {
            try await ensureAwake()
        }
    }

    public func process(_ context: PipelineContext) async throws {
        guard config.isActive else { return }
        guard !context.text.isEmpty else { return }

        try await ensureAwake()
        setState(.processing)
        defer { setState(.idle) }

        if let handler = processHandler {
            context.text = try await handler(context.text, config)
        }

        // Store what was applied
        context.setCustomData(config.summary, forKey: "improve_settings")
    }

    public func cleanup() async {
        if sleepConfig.enabled {
            await sleep()
        }
    }
}

/// Simple cleanup stage (legacy, standalone)
public final class CleanupStage: PipelineStage, @unchecked Sendable {
    public let stageTypeId = "cleanup"
    public var id: String { stageTypeId }
    public let displayName = "Cleanup"
    public let description = "Remove filler words, fix grammar"
    public let icon = "wand.and.stars"

    public var constraints: ElementConstraints { [.cannotBeFirst, .cannotBeLast, .optional] }

    public var connectionRules: ConnectionRules {
        ConnectionRules(
            acceptsInput: [.text, .richText],
            producesOutput: .text
        )
    }

    public var isEnabled: Bool = true
    public var configuration: [String: Any] = [:]

    public var processHandler: ((String) async throws -> String)?

    public init() {}

    public func process(_ context: PipelineContext) async throws {
        guard !context.text.isEmpty else { return }

        if let handler = processHandler {
            context.text = try await handler(context.text)
        }
    }
}
