import Foundation

/// Position constraints for pipeline elements (stages and actions)
public struct ElementConstraints: OptionSet, Sendable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Element must be the first in the pipeline
    public static let mustBeFirst = ElementConstraints(rawValue: 1 << 0)

    /// Element must be the last in the pipeline
    public static let mustBeLast = ElementConstraints(rawValue: 1 << 1)

    /// Element cannot be first
    public static let cannotBeFirst = ElementConstraints(rawValue: 1 << 2)

    /// Element cannot be last
    public static let cannotBeLast = ElementConstraints(rawValue: 1 << 3)

    /// Element can appear multiple times in the pipeline
    public static let allowMultiple = ElementConstraints(rawValue: 1 << 4)

    /// Element is optional and can be skipped
    public static let optional = ElementConstraints(rawValue: 1 << 5)

    /// No constraints
    public static let none: ElementConstraints = []
}

/// Defines what data types an element can accept and produce
public enum DataType: String, Codable, Sendable, CaseIterable {
    case audio          // Raw audio data/samples
    case audioFile      // Path to audio file
    case text           // Plain text
    case richText       // Text with metadata (language, confidence, etc.)
    case any            // Accepts any type
}

/// Configuration for element connections
public struct ConnectionRules: Codable, Sendable {
    /// Data types this element can accept as input
    public let acceptsInput: Set<DataType>

    /// Data type this element produces as output
    public let producesOutput: DataType

    /// Element IDs that must come before this element (dependencies)
    public let requiredPredecessors: Set<String>

    /// Element IDs that cannot come before this element
    public let incompatiblePredecessors: Set<String>

    /// Element IDs that must come after this element
    public let requiredSuccessors: Set<String>

    public init(
        acceptsInput: Set<DataType> = [.any],
        producesOutput: DataType = .any,
        requiredPredecessors: Set<String> = [],
        incompatiblePredecessors: Set<String> = [],
        requiredSuccessors: Set<String> = []
    ) {
        self.acceptsInput = acceptsInput
        self.producesOutput = producesOutput
        self.requiredPredecessors = requiredPredecessors
        self.incompatiblePredecessors = incompatiblePredecessors
        self.requiredSuccessors = requiredSuccessors
    }
}

/// Validation result for pipeline configuration
public struct PipelineValidationResult: Sendable {
    public let isValid: Bool
    public let errors: [PipelineValidationError]
    public let warnings: [String]

    public static let valid = PipelineValidationResult(isValid: true, errors: [], warnings: [])

    public init(isValid: Bool, errors: [PipelineValidationError], warnings: [String] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
}

/// Validation errors
public enum PipelineValidationError: Error, Sendable, CustomStringConvertible {
    case emptyPipeline
    case missingRequiredElement(typeId: String, reason: String)
    case invalidPosition(typeId: String, reason: String)
    case incompatibleConnection(from: String, to: String, reason: String)
    case duplicateElement(typeId: String)
    case cyclicDependency(typeIds: [String])
    case missingDependency(typeId: String, dependsOn: String)

    public var description: String {
        switch self {
        case .emptyPipeline:
            return "Pipeline cannot be empty"
        case .missingRequiredElement(let id, let reason):
            return "Missing required element '\(id)': \(reason)"
        case .invalidPosition(let id, let reason):
            return "Invalid position for '\(id)': \(reason)"
        case .incompatibleConnection(let from, let to, let reason):
            return "Incompatible connection from '\(from)' to '\(to)': \(reason)"
        case .duplicateElement(let id):
            return "Duplicate element '\(id)' not allowed"
        case .cyclicDependency(let ids):
            return "Cyclic dependency detected: \(ids.joined(separator: " -> "))"
        case .missingDependency(let id, let dep):
            return "Element '\(id)' requires '\(dep)' to be present"
        }
    }
}
