import Foundation

// MARK: - Tool Protocol

/// A tool that the AI can call during chat
protocol ChatTool: Sendable {
    /// Unique identifier for this tool
    var name: String { get }

    /// Description for the AI to understand when to use this tool
    var description: String { get }

    /// JSON schema for the tool parameters
    var parameters: [String: Any] { get }

    /// Execute the tool with given arguments
    func execute(arguments: [String: Any]) async throws -> String
}

// MARK: - Tool Call

/// A tool call requested by the AI
struct ToolCall: Codable, Sendable {
    let name: String
    let arguments: [String: Any]

    enum CodingKeys: String, CodingKey {
        case name
        case arguments
    }

    init(name: String, arguments: [String: Any]) {
        self.name = name
        self.arguments = arguments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)

        // Decode arguments as a JSON string first, then parse
        if let argsData = try? container.decode(String.self, forKey: .arguments),
            let data = argsData.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            arguments = parsed
        } else if let argsDict = try? container.decode([String: JSONAnyCodable].self, forKey: .arguments) {
            arguments = argsDict.mapValues { $0.value }
        } else {
            arguments = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        let argsData = try JSONSerialization.data(withJSONObject: arguments)
        let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
        try container.encode(argsString, forKey: .arguments)
    }
}

// MARK: - Tool Response

/// Response from the Ollama API when tools are available
struct OllamaToolResponse: Codable {
    let model: String
    let message: OllamaMessage
    let done: Bool

    struct OllamaMessage: Codable {
        let role: String
        let content: String?
        let toolCalls: [OllamaToolCall]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }
    }

    struct OllamaToolCall: Codable {
        let function: OllamaFunction

        struct OllamaFunction: Codable {
            let name: String
            let arguments: [String: JSONAnyCodable]
        }
    }
}

// MARK: - Tool Registry

/// Registry of available tools
@MainActor
final class ToolRegistry {
    static let shared = ToolRegistry()

    private var tools: [String: any ChatTool] = [:]

    private init() {}

    /// Register a tool
    func register(_ tool: any ChatTool) {
        tools[tool.name] = tool
    }

    /// Get a tool by name
    func tool(named name: String) -> (any ChatTool)? {
        tools[name]
    }

    /// Get all registered tools
    var allTools: [any ChatTool] {
        Array(tools.values)
    }

    /// Build tools array for Ollama API
    func buildToolsPayload() -> [[String: Any]] {
        allTools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.parameters,
                ],
            ]
        }
    }

    /// Execute a tool call
    func execute(_ toolCall: ToolCall) async throws -> String {
        guard let tool = tools[toolCall.name] else {
            throw ToolError.unknownTool(toolCall.name)
        }
        return try await tool.execute(arguments: toolCall.arguments)
    }
}

// MARK: - Tool Errors

enum ToolError: Error, LocalizedError {
    case unknownTool(String)
    case invalidArguments(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .executionFailed(let message):
            return "Tool execution failed: \(message)"
        }
    }
}

// MARK: - JSONAnyCodable Helper

/// Helper for encoding/decoding arbitrary JSON values
struct JSONAnyCodable: Codable, Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([JSONAnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: JSONAnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
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
            try container.encode(array.map { JSONAnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { JSONAnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
