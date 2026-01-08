import Foundation

/// Defines a model that can be downloaded or bundled with the app
public struct ModelDefinition: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let category: ModelCategory
    public let source: ModelSource
    public let sizeBytes: Int64
    public let isRequired: Bool

    public init(
        id: String,
        name: String,
        description: String,
        category: ModelCategory,
        source: ModelSource,
        sizeBytes: Int64,
        isRequired: Bool = true
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.source = source
        self.sizeBytes = sizeBytes
        self.isRequired = isRequired
    }

    /// Human-readable size string
    public var sizeString: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

/// Category of model for grouping
public enum ModelCategory: String, Sendable, CaseIterable {
    case transcription = "Transcription"
    case speakerVerification = "Speaker Verification"
    case textRefinement = "Text Refinement"
}

/// Source of the model
public enum ModelSource: Sendable {
    case huggingFace(repo: String, files: [String])
    case bundled(relativePath: String)
    case custom(url: URL)
}

/// Status of a model
public enum ModelStatus: Sendable, Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case error(String)

    public var isAvailable: Bool {
        if case .downloaded = self { return true }
        return false
    }
}
