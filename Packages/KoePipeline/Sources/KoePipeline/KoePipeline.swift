// KoePipeline - Modular Audio Processing Pipeline Framework
//
// A reusable pipeline system for processing audio and text.
// Features:
// - Stages (data transformation): Transcription, Language Improvement, etc.
// - Actions (output): Auto Type, Auto Enter, Copy to Clipboard, etc.
// - Sleep mode for resource management
// - Configurable settings per element
//
// Example Usage:
// ```swift
// // Setup
// registerBuiltInElements()
//
// // Create pipeline
// var pipeline = Pipeline(name: "Voice to Text")
// pipeline.add(PipelineElementInstance(typeId: "audio-input"))
// pipeline.add(PipelineElementInstance(typeId: "transcription"))
// pipeline.add(PipelineElementInstance(typeId: "language-improvement"))
// pipeline.add(PipelineElementInstance(typeId: "auto-type"))
//
// // Run
// let orchestrator = PipelineOrchestrator()
// let context = try await orchestrator.run(pipeline)
// ```

import Foundation

// MARK: - Version

public struct KoePipelineVersion {
    public static let major = 1
    public static let minor = 0
    public static let patch = 0
    public static let string = "\(major).\(minor).\(patch)"
}

// MARK: - Convenience Registration

/// Register all built-in stages and actions with the registry
public func registerBuiltInElements() {
    let registry = ElementRegistry.shared

    // Triggers
    registry.register(action: HotkeyTrigger.self) { HotkeyTrigger() }

    // Source stages
    registry.register(stage: AudioInputStage.self) { AudioInputStage() }
    registry.register(stage: VADStage.self) { VADStage() }
    registry.register(stage: TranscriptionStage.self) { TranscriptionStage() }

    // Processing stages
    registry.register(stage: TextImproveStage.self) { TextImproveStage() }
    registry.register(stage: LanguageImprovementStage.self) { LanguageImprovementStage() }  // Legacy
    registry.register(stage: PromptOptimizerStage.self) { PromptOptimizerStage() }  // Legacy
    registry.register(stage: CleanupStage.self) { CleanupStage() }  // Legacy

    // Actions
    registry.register(action: AutoTypeAction.self) { AutoTypeAction() }
    registry.register(action: AutoEnterAction.self) { AutoEnterAction() }
    registry.register(action: CopyToClipboardAction.self) { CopyToClipboardAction() }
    registry.register(action: NotificationAction.self) { NotificationAction() }
}

// MARK: - Pipeline Templates

extension PipelineTemplates {
    /// Simple voice to text with language improvement
    public static let simpleVoiceToText = Pipeline(
        name: "Simple Voice to Text",
        description: "Transcribe and clean up speech",
        elements: [
            PipelineElementInstance(typeId: "audio-input"),
            PipelineElementInstance(typeId: "transcription"),
            PipelineElementInstance(typeId: "language-improvement"),
            PipelineElementInstance(typeId: "auto-type")
        ]
    )

    /// Formal writing pipeline
    public static let formalVoiceToText = Pipeline(
        name: "Formal Writing",
        description: "Transcribe with formal tone",
        elements: [
            PipelineElementInstance(typeId: "audio-input"),
            PipelineElementInstance(typeId: "transcription"),
            PipelineElementInstance(
                typeId: "language-improvement",
                configuration: [
                    "cleanupEnabled": AnyCodable(true),
                    "tone": AnyCodable("formal")
                ]
            ),
            PipelineElementInstance(typeId: "auto-type")
        ]
    )

    /// AI prompt mode pipeline
    public static let promptMode = Pipeline(
        name: "Prompt Mode",
        description: "Optimize speech as AI prompt",
        elements: [
            PipelineElementInstance(typeId: "audio-input"),
            PipelineElementInstance(typeId: "transcription"),
            PipelineElementInstance(typeId: "language-improvement"),
            PipelineElementInstance(typeId: "prompt-optimizer"),
            PipelineElementInstance(typeId: "auto-type")
        ]
    )

    /// Full featured with auto-enter
    public static let fullWithEnter = Pipeline(
        name: "Full with Enter",
        description: "Complete pipeline with auto-enter",
        elements: [
            PipelineElementInstance(typeId: "audio-input"),
            PipelineElementInstance(typeId: "transcription"),
            PipelineElementInstance(typeId: "language-improvement"),
            PipelineElementInstance(typeId: "prompt-optimizer", isEnabled: false),
            PipelineElementInstance(typeId: "auto-type"),
            PipelineElementInstance(typeId: "auto-enter")
        ]
    )
}

// MARK: - Sleep Configuration Presets

extension SleepConfiguration {
    /// Performance mode: no sleep, always ready
    public static let performance = SleepConfiguration(
        enabled: false,
        autoSleepDelay: 0,
        preWarm: true
    )

    /// Battery saver: aggressive sleep after 10s
    public static let batterySaver = SleepConfiguration(
        enabled: true,
        autoSleepDelay: 10.0,
        preWarm: false
    )

    /// Custom timeout
    public static func custom(timeout: TimeInterval, preWarm: Bool = false) -> SleepConfiguration {
        SleepConfiguration(
            enabled: timeout > 0,
            autoSleepDelay: timeout,
            preWarm: preWarm
        )
    }
}

// MARK: - Convenience Factory

/// Create a simple pipeline for voice to text
public func createVoiceToTextPipeline(
    cleanup: Bool = true,
    tone: ToneOption = .none,
    promptMode: Bool = false,
    autoEnter: Bool = false
) -> Pipeline {
    var elements: [PipelineElementInstance] = [
        PipelineElementInstance(typeId: "audio-input"),
        PipelineElementInstance(typeId: "transcription")
    ]

    // Language improvement
    if cleanup || tone != .none {
        elements.append(PipelineElementInstance(
            typeId: "language-improvement",
            configuration: [
                "cleanupEnabled": AnyCodable(cleanup),
                "tone": AnyCodable(tone.rawValue)
            ]
        ))
    }

    // Prompt optimizer
    if promptMode {
        elements.append(PipelineElementInstance(typeId: "prompt-optimizer"))
    }

    // Output
    elements.append(PipelineElementInstance(typeId: "auto-type"))

    if autoEnter {
        elements.append(PipelineElementInstance(typeId: "auto-enter"))
    }

    return Pipeline(
        name: promptMode ? "Prompt Mode" : "Voice to Text",
        description: "Custom pipeline",
        elements: elements
    )
}
