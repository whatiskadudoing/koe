import SwiftUI
import KoeUI

/// Represents a stage in the visual pipeline editor
enum PipelineStageInfo: String, CaseIterable, Identifiable {
    // Parallel triggers (only one can be active at a time)
    case hotkeyTrigger   // Keyboard shortcut trigger
    case voiceTrigger    // Voice command trigger ("koe")

    // Sequential pipeline stages
    case recorder        // Records audio (behavior depends on trigger type)
    case transcribe      // Converts audio to text (model selection)
    case improve         // AI text improvement (cleanup, tone, prompt)
    case autoType        // Types the text
    case autoEnter       // Presses enter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hotkeyTrigger: return "On Press"
        case .voiceTrigger: return "On Voice"
        case .recorder: return "Record"
        case .transcribe: return "Transcribe"
        case .improve: return "Improve"
        case .autoType: return "Type"
        case .autoEnter: return "Enter"
        }
    }

    var icon: String {
        switch self {
        case .hotkeyTrigger: return "command"
        case .voiceTrigger: return "waveform"
        case .recorder: return "mic"
        case .transcribe: return "text.bubble"
        case .improve: return "sparkles"
        case .autoType: return "keyboard"
        case .autoEnter: return "return"
        }
    }

    var color: Color {
        switch self {
        case .hotkeyTrigger: return KoeColors.accent
        case .voiceTrigger: return KoeColors.accent
        case .recorder: return KoeColors.stateRecording
        case .transcribe: return KoeColors.stateTranscribing
        case .improve: return KoeColors.stateRefining
        case .autoType: return KoeColors.accent
        case .autoEnter: return KoeColors.accent
        }
    }

    /// Whether this stage can be toggled on/off by the user
    var isToggleable: Bool {
        switch self {
        case .hotkeyTrigger, .voiceTrigger, .improve, .autoEnter: return true
        default: return false
        }
    }

    /// Whether this stage is implicit (shown but not interactive)
    var isImplicit: Bool {
        return false
    }

    /// Whether this stage has settings that can be configured
    var hasSettings: Bool {
        switch self {
        case .hotkeyTrigger, .voiceTrigger, .recorder, .transcribe, .improve: return true
        default: return false
        }
    }

    /// Whether this is a trigger stage (part of parallel trigger group)
    var isTrigger: Bool {
        switch self {
        case .hotkeyTrigger, .voiceTrigger: return true
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
        case .transcribe: return nil
        case .improve: return "text-improve"
        case .autoType: return "auto-type"
        case .autoEnter: return "auto-enter"
        }
    }

    /// Trigger stages shown in parallel at the start
    static var triggerStages: [PipelineStageInfo] {
        [.hotkeyTrigger, .voiceTrigger]
    }

    /// Sequential stages after triggers
    static var sequentialStages: [PipelineStageInfo] {
        [.recorder, .transcribe, .improve, .autoType, .autoEnter]
    }

    /// Stages to show in the pipeline strip (excludes implicit ones)
    static var visibleStages: [PipelineStageInfo] {
        allCases.filter { !$0.isImplicit }
    }
}
