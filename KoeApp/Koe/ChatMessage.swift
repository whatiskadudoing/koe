import Foundation

// MARK: - Message Role

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

// MARK: - Tool Usage

/// Record of a tool that was used during response generation
struct ToolUsage: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let toolName: String
    let query: String?
    let timestamp: Date

    init(id: UUID = UUID(), toolName: String, query: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.toolName = toolName
        self.query = query
        self.timestamp = timestamp
    }

    /// Display name for the tool
    var displayName: String {
        switch toolName {
        case "web_search":
            return "Wikipedia"
        default:
            return toolName
        }
    }

    /// Icon for the tool
    var iconName: String {
        switch toolName {
        case "web_search":
            return "globe"
        default:
            return "wrench"
        }
    }
}

// MARK: - Chat Message

/// A single message in a chat conversation
struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date

    /// Whether this message is still being streamed
    var isStreaming: Bool

    /// Error if generation failed
    var error: String?

    /// Tools that were used to generate this response
    var toolsUsed: [ToolUsage]

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        error: String? = nil,
        toolsUsed: [ToolUsage] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.error = error
        self.toolsUsed = toolsUsed
    }

    /// Create a user message
    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    /// Create an assistant message (optionally streaming)
    static func assistant(_ content: String = "", isStreaming: Bool = false) -> ChatMessage {
        ChatMessage(role: .assistant, content: content, isStreaming: isStreaming)
    }

    /// Create a system message
    static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }
}

// MARK: - Chat Conversation

/// A conversation containing multiple messages
struct ChatConversation: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String?
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date

    /// System prompt for this conversation
    var systemPrompt: String?

    /// Model used for this conversation
    var model: String

    /// Temperature setting
    var temperature: Double

    init(
        id: UUID = UUID(),
        title: String? = nil,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        systemPrompt: String? = nil,
        model: String = "qwen2.5:7b",
        temperature: Double = 0.7
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.systemPrompt = systemPrompt
        self.model = model
        self.temperature = temperature
    }

    /// Get display title (first user message or default)
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        if let firstUserMessage = messages.first(where: { $0.role == .user }) {
            let preview = firstUserMessage.content.prefix(50)
            return preview.count < firstUserMessage.content.count ? "\(preview)..." : String(preview)
        }
        return "New Chat"
    }

    /// Build conversation history for API call
    func buildPromptContext() -> String {
        var context = ""

        for message in messages where message.role != .system {
            switch message.role {
            case .user:
                context += "User: \(message.content)\n"
            case .assistant:
                context += "Assistant: \(message.content)\n"
            case .system:
                break
            }
        }

        return context
    }
}
