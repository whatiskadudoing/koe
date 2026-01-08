import SwiftUI
import KoeUI

/// Represents a stage in the visual pipeline editor
enum PipelineStageInfo: String, CaseIterable, Identifiable {
    case hotkey
    case transcription
    case languageImprovement
    case promptOptimizer
    case autoType
    case autoEnter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hotkey: return "Hotkey"
        case .transcription: return "Transcribe"
        case .languageImprovement: return "Improve"
        case .promptOptimizer: return "Prompt"
        case .autoType: return "Type"
        case .autoEnter: return "Enter"
        }
    }

    var icon: String {
        switch self {
        case .hotkey: return "command"
        case .transcription: return "text.bubble"
        case .languageImprovement: return "text.badge.checkmark"
        case .promptOptimizer: return "sparkles"
        case .autoType: return "keyboard"
        case .autoEnter: return "return"
        }
    }

    var color: Color {
        switch self {
        case .hotkey: return KoeColors.accent
        case .transcription: return KoeColors.stateTranscribing
        case .languageImprovement: return KoeColors.stateRefining
        case .promptOptimizer: return .orange
        case .autoType: return KoeColors.accent
        case .autoEnter: return KoeColors.accent
        }
    }

    /// Whether this stage can be toggled on/off by the user
    var isToggleable: Bool {
        switch self {
        case .languageImprovement, .promptOptimizer, .autoEnter: return true
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
        case .hotkey, .languageImprovement: return true
        default: return false
        }
    }

    /// Pipeline element typeId for metrics lookup
    /// Returns nil for stages that aren't tracked as pipeline elements
    var pipelineTypeId: String? {
        switch self {
        case .hotkey: return nil  // Hotkey is a trigger, not a pipeline element
        case .transcription: return nil  // Transcription happens before pipeline
        case .languageImprovement: return "language-improvement"
        case .promptOptimizer: return "prompt-optimizer"
        case .autoType: return "auto-type"
        case .autoEnter: return "auto-enter"
        }
    }

    /// Stages to show in the pipeline strip (excludes implicit ones)
    static var visibleStages: [PipelineStageInfo] {
        allCases.filter { !$0.isImplicit }
    }
}
