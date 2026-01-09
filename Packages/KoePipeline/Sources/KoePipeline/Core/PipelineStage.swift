import Foundation

// MARK: - Base Protocol

/// Base protocol for all pipeline elements (stages and actions)
public protocol PipelineElement: AnyObject, Sendable, Identifiable {
    /// Unique identifier for this element type
    var typeId: String { get }

    /// Unique instance ID
    var id: String { get }

    /// Display name for UI
    var displayName: String { get }

    /// Short description
    var description: String { get }

    /// Icon name (SF Symbol)
    var icon: String { get }

    /// Position and connection constraints
    var constraints: ElementConstraints { get }

    /// Connection rules (input/output types, dependencies)
    var connectionRules: ConnectionRules { get }

    /// Whether this element is currently enabled
    var isEnabled: Bool { get set }

    /// Element-specific configuration
    var configuration: [String: Any] { get set }

    /// Process the pipeline context
    func process(_ context: PipelineContext) async throws

    /// Prepare the element (load models, etc.)
    func prepare() async throws

    /// Cleanup resources
    func cleanup() async
}

/// Default implementations
public extension PipelineElement {
    var id: String { typeId }
    var constraints: ElementConstraints { .none }
    var connectionRules: ConnectionRules {
        ConnectionRules(acceptsInput: [.any], producesOutput: .any)
    }
    var isEnabled: Bool {
        get { true }
        set { }
    }
    var configuration: [String: Any] {
        get { [:] }
        set { }
    }
    func prepare() async throws { }
    func cleanup() async { }
}

// MARK: - Stage Protocol (Data Transformation)

/// A stage transforms or processes data
/// Examples: Transcription, Language Improvement, Prompt Optimizer
public protocol PipelineStage: PipelineElement {
    /// The stage type ID (convenience for typeId)
    var stageTypeId: String { get }
}

public extension PipelineStage {
    var typeId: String { stageTypeId }
}

// MARK: - Action Protocol (Performs Actions)

/// An action does something with the data
/// Examples: Auto Type, Auto Enter, Copy to Clipboard, Notification
public protocol PipelineAction: PipelineElement {
    /// The action type ID (convenience for typeId)
    var actionTypeId: String { get }
}

public extension PipelineAction {
    var typeId: String { actionTypeId }
}

// MARK: - Configured Instance

/// A configured instance of an element in a pipeline
public struct PipelineElementInstance: Identifiable, Codable, Sendable {
    public let id: String
    public let typeId: String
    public var isEnabled: Bool
    public var configuration: [String: AnyCodable]

    public init(
        id: String = UUID().uuidString,
        typeId: String,
        isEnabled: Bool = true,
        configuration: [String: AnyCodable] = [:]
    ) {
        self.id = id
        self.typeId = typeId
        self.isEnabled = isEnabled
        self.configuration = configuration
    }
}

// MARK: - Type-Erased Codable

/// Type-erased Codable wrapper
public struct AnyCodable: Codable, Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = ()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - Registry

/// Registry of available stages and actions
public final class ElementRegistry: @unchecked Sendable {
    public static let shared = ElementRegistry()

    private var factories: [String: () -> any PipelineElement] = [:]
    private let lock = NSLock()

    private init() {}

    /// Register a stage
    public func register<T: PipelineStage>(stage: T.Type, factory: @escaping () -> T) {
        lock.lock()
        defer { lock.unlock() }
        let instance = factory()
        factories[instance.typeId] = factory
    }

    /// Register an action
    public func register<T: PipelineAction>(action: T.Type, factory: @escaping () -> T) {
        lock.lock()
        defer { lock.unlock() }
        let instance = factory()
        factories[instance.typeId] = factory
    }

    /// Create an element instance
    public func create(typeId: String) -> (any PipelineElement)? {
        lock.lock()
        defer { lock.unlock() }
        return factories[typeId]?()
    }

    /// Get all registered type IDs
    public var registeredTypeIds: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(factories.keys)
    }

    /// Get info for all registered elements
    public func getAllInfo() -> [ElementInfo] {
        lock.lock()
        defer { lock.unlock() }

        return factories.values.map { factory in
            let element = factory()
            return ElementInfo(
                typeId: element.typeId,
                displayName: element.displayName,
                description: element.description,
                icon: element.icon,
                constraints: element.constraints,
                connectionRules: element.connectionRules,
                isStage: element is any PipelineStage,
                isAction: element is any PipelineAction
            )
        }
    }

    /// Get all stages
    public func getStages() -> [ElementInfo] {
        getAllInfo().filter { $0.isStage }
    }

    /// Get all actions
    public func getActions() -> [ElementInfo] {
        getAllInfo().filter { $0.isAction }
    }
}

/// Information about a stage or action (for UI)
public struct ElementInfo: Identifiable, Sendable {
    public var id: String { typeId }
    public let typeId: String
    public let displayName: String
    public let description: String
    public let icon: String
    public let constraints: ElementConstraints
    public let connectionRules: ConnectionRules
    public let isStage: Bool
    public let isAction: Bool
}
