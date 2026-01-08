import SwiftUI
import KoeUI

/// Represents a stage in the visual pipeline editor
enum PipelineStageInfo: String, CaseIterable, Identifiable {
    case hotkey
    case transcription
    case improve  // Combined: cleanup, tone, and prompt optimization
    case autoType
    case autoEnter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hotkey: return "Hotkey"
        case .transcription: return "Transcribe"
        case .improve: return "Improve"
        case .autoType: return "Type"
        case .autoEnter: return "Enter"
        }
    }

    var icon: String {
        switch self {
        case .hotkey: return "command"
        case .transcription: return "text.bubble"
        case .improve: return "sparkles"
        case .autoType: return "keyboard"
        case .autoEnter: return "return"
        }
    }

    var color: Color {
        switch self {
        case .hotkey: return KoeColors.accent
        case .transcription: return KoeColors.stateTranscribing
        case .improve: return KoeColors.stateRefining
        case .autoType: return KoeColors.accent
        case .autoEnter: return KoeColors.accent
        }
    }

    /// Whether this stage can be toggled on/off by the user
    var isToggleable: Bool {
        switch self {
        case .improve, .autoEnter: return true
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
        case .hotkey, .transcription, .improve: return true
        default: return false
        }
    }

    /// Pipeline element typeId for metrics lookup
    /// Returns nil for stages that aren't tracked as pipeline elements
    var pipelineTypeId: String? {
        switch self {
        case .hotkey: return nil  // Hotkey is a trigger, not a pipeline element
        case .transcription: return nil  // Transcription happens before pipeline
        case .improve: return "text-improve"
        case .autoType: return "auto-type"
        case .autoEnter: return "auto-enter"
        }
    }

    /// Stages to show in the pipeline strip (excludes implicit ones)
    static var visibleStages: [PipelineStageInfo] {
        allCases.filter { !$0.isImplicit }
    }
}
