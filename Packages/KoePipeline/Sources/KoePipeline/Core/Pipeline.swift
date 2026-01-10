import Foundation

/// A configured pipeline consisting of ordered stages and actions
public struct Pipeline: Identifiable, Codable, Sendable {
    public let id: String
    public var name: String
    public var description: String
    public var elements: [PipelineElementInstance]
    public var isEnabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String = "",
        elements: [PipelineElementInstance] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.elements = elements
        self.isEnabled = isEnabled
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Add an element to the pipeline
    public mutating func add(_ element: PipelineElementInstance, at index: Int? = nil) {
        if let index = index, index < elements.count {
            elements.insert(element, at: index)
        } else {
            elements.append(element)
        }
        updatedAt = Date()
    }

    /// Remove an element from the pipeline
    public mutating func remove(at index: Int) {
        guard index < elements.count else { return }
        elements.remove(at: index)
        updatedAt = Date()
    }

    /// Move an element within the pipeline
    public mutating func move(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex < elements.count, destinationIndex < elements.count else { return }
        let element = elements.remove(at: sourceIndex)
        elements.insert(element, at: destinationIndex)
        updatedAt = Date()
    }

    /// Toggle an element's enabled state
    public mutating func toggle(at index: Int) {
        guard index < elements.count else { return }
        elements[index].isEnabled.toggle()
        updatedAt = Date()
    }

    /// Get enabled elements only
    public var enabledElements: [PipelineElementInstance] {
        elements.filter { $0.isEnabled }
    }
}

/// Predefined pipeline templates
public struct PipelineTemplates {
    /// Simple voice-to-text pipeline
    public static let simpleTranscription = Pipeline(
        name: "Simple Transcription",
        description: "Audio to text with basic cleanup",
        elements: [
            PipelineElementInstance(typeId: "audio-input"),
            PipelineElementInstance(typeId: "transcription"),
            PipelineElementInstance(typeId: "cleanup"),
            PipelineElementInstance(typeId: "auto-type"),
        ]
    )

    /// Formal writing pipeline
    public static let formalWriting = Pipeline(
        name: "Formal Writing",
        description: "Transcribe and format as professional text",
        elements: [
            PipelineElementInstance(typeId: "audio-input"),
            PipelineElementInstance(typeId: "transcription"),
            PipelineElementInstance(typeId: "language-improvement"),
            PipelineElementInstance(typeId: "auto-type"),
        ]
    )

    /// AI prompt optimization pipeline
    public static let promptOptimization = Pipeline(
        name: "Prompt Optimizer",
        description: "Transcribe and optimize as AI prompt",
        elements: [
            PipelineElementInstance(typeId: "audio-input"),
            PipelineElementInstance(typeId: "transcription"),
            PipelineElementInstance(typeId: "language-improvement"),
            PipelineElementInstance(typeId: "prompt-optimizer"),
            PipelineElementInstance(typeId: "auto-type"),
        ]
    )

    /// Full pipeline with all options
    public static let fullPipeline = Pipeline(
        name: "Full Pipeline",
        description: "Complete pipeline with all options",
        elements: [
            PipelineElementInstance(typeId: "audio-input"),
            PipelineElementInstance(typeId: "transcription"),
            PipelineElementInstance(typeId: "language-improvement"),
            PipelineElementInstance(typeId: "prompt-optimizer", isEnabled: false),
            PipelineElementInstance(typeId: "auto-type"),
            PipelineElementInstance(typeId: "auto-enter", isEnabled: false),
        ]
    )

    /// All predefined templates
    public static let all: [Pipeline] = [
        simpleTranscription,
        formalWriting,
        promptOptimization,
        fullPipeline,
    ]
}
