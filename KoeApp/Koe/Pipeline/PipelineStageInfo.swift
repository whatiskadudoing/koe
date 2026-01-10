import KoeUI
import SwiftUI

/// Represents a stage in the visual pipeline editor
enum PipelineStageInfo: String, CaseIterable, Identifiable {
    // Parallel triggers (only one can be active at a time)
    case hotkeyTrigger  // Keyboard shortcut trigger
    case voiceTrigger  // Voice command trigger ("koe")

    // Sequential pipeline stages
    case recorder  // Records audio (behavior depends on trigger type)

    // Parallel transcription engines (mutually exclusive - only one can be active)
    case transcribeApple  // Apple Speech - instant, no download
    case transcribeWhisperKitBalanced  // WhisperKit Balanced - 632 MB, good speed/accuracy
    case transcribeWhisperKitAccurate  // WhisperKit Accurate - 947 MB, best accuracy

    // Parallel AI processing engines (mutually exclusive - only one can be active)
    case aiFast  // Mistral 7B - translation (~4GB)
    case aiBalanced  // Qwen 2.5 7B - balanced speed/quality (~4.5GB)
    case aiReasoning  // DeepSeek-R1 8B - complex reasoning (~5GB)

    case autoType  // Types the text
    case autoEnter  // Presses enter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hotkeyTrigger: return "On Press"
        case .voiceTrigger: return "On Voice"
        case .recorder: return "Record"
        case .transcribeApple: return "Apple Speech"
        case .transcribeWhisperKitBalanced: return "Balanced"
        case .transcribeWhisperKitAccurate: return "Accurate"
        case .aiFast: return "Translate"
        case .aiBalanced: return "Balanced"
        case .aiReasoning: return "Reasoning"
        case .autoType: return "Type"
        case .autoEnter: return "Enter"
        }
    }

    /// Icon from NodeRegistry (single source of truth)
    var icon: String {
        nodeInfo.icon
    }

    /// Color from NodeRegistry (single source of truth)
    var color: Color {
        nodeInfo.color
    }

    /// Whether this stage can be toggled on/off by the user (from NodeRegistry)
    var isToggleable: Bool {
        nodeInfo.isUserToggleable
    }

    /// Whether this stage has settings that can be configured (from NodeRegistry)
    var hasSettings: Bool {
        nodeInfo.hasSettings
    }

    /// Whether this is a trigger stage (part of parallel trigger group)
    var isTrigger: Bool {
        switch self {
        case .hotkeyTrigger, .voiceTrigger: return true
        default: return false
        }
    }

    /// Whether this is a transcription engine stage (part of parallel transcription group)
    var isTranscriptionEngine: Bool {
        switch self {
        case .transcribeApple, .transcribeWhisperKitBalanced, .transcribeWhisperKitAccurate: return true
        default: return false
        }
    }

    /// Whether this is an AI processing engine stage (part of parallel AI group)
    var isAIProcessingEngine: Bool {
        switch self {
        case .aiFast, .aiBalanced, .aiReasoning: return true
        default: return false
        }
    }

    /// Pipeline element typeId for metrics lookup
    /// Returns nil for stages that aren't tracked as pipeline elements
    var pipelineTypeId: String? {
        switch self {
        case .hotkeyTrigger: return nil
        case .voiceTrigger: return nil
        case .recorder: return nil
        case .transcribeApple: return "transcribe-apple"
        case .transcribeWhisperKitBalanced: return "transcribe-whisperkit-balanced"
        case .transcribeWhisperKitAccurate: return "transcribe-whisperkit-accurate"
        case .aiFast: return "ai-fast"
        case .aiBalanced: return "ai-balanced"
        case .aiReasoning: return "ai-reasoning"
        case .autoType: return "auto-type"
        case .autoEnter: return "auto-enter"
        }
    }

    /// Trigger stages shown in parallel at the start
    static var triggerStages: [PipelineStageInfo] {
        [.hotkeyTrigger, .voiceTrigger]
    }

    /// Transcription engine stages shown in parallel
    static var transcriptionStages: [PipelineStageInfo] {
        [.transcribeApple, .transcribeWhisperKitBalanced, .transcribeWhisperKitAccurate]
    }

    /// AI processing engine stages shown in parallel
    static var aiProcessingStages: [PipelineStageInfo] {
        [.aiFast, .aiBalanced, .aiReasoning]
    }

    /// Sequential stages after triggers (before transcription split)
    static var preTranscriptionStages: [PipelineStageInfo] {
        [.recorder]
    }

    /// Sequential stages after AI processing merge
    static var postAIProcessingStages: [PipelineStageInfo] {
        [.autoType, .autoEnter]
    }

    /// Sequential stages after triggers (includes all)
    static var sequentialStages: [PipelineStageInfo] {
        [
            .recorder,
            .transcribeApple, .transcribeWhisperKitBalanced, .transcribeWhisperKitAccurate,
            .aiFast, .aiBalanced, .aiReasoning,
            .autoType, .autoEnter,
        ]
    }
}
