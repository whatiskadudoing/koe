import Foundation
import KoeRefinement

// MARK: - Chat Service

/// Manages chat conversations and AI interactions
@MainActor
@Observable
final class ChatService {
    static let shared = ChatService()

    // MARK: - State

    /// Current active conversation
    var currentConversation: ChatConversation

    /// All saved conversations
    var conversations: [ChatConversation] = []

    /// Whether AI is currently generating a response
    var isGenerating = false

    /// Current tool action being performed (for UI feedback)
    var currentToolAction: String? = nil

    /// Whether tools are enabled for this chat
    var toolsEnabled = true

    /// Current generation task (for cancellation)
    private var generationTask: Task<Void, Never>?

    /// Ollama client for API calls
    private let client = OllamaClient()

    /// Tool registry
    private let toolRegistry = ToolRegistry.shared

    // MARK: - Settings

    /// Default model to use
    var selectedModel: String = "qwen2.5:7b" {
        didSet {
            currentConversation.model = selectedModel
        }
    }

    /// Default system prompt
    var defaultSystemPrompt: String? =
        "You are a helpful AI assistant. When you need current information that you don't have, use the web_search tool to find it. Be concise and helpful."

    // MARK: - Init

    private init() {
        // Initialize with default values first
        self.currentConversation = ChatConversation(
            systemPrompt: nil,
            model: "qwen2.5:7b"
        )
        loadConversations()

        // Register built-in tools
        toolRegistry.registerBuiltInTools()
    }

    // MARK: - Message Handling

    /// Send a user message and get AI response (with tool calling support)
    func sendMessage(_ content: String) async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isGenerating else { return }

        // Add user message
        let userMessage = ChatMessage.user(content)
        currentConversation.messages.append(userMessage)
        currentConversation.updatedAt = Date()

        // Create placeholder for assistant response
        var assistantMessage = ChatMessage.assistant("", isStreaming: true)
        currentConversation.messages.append(assistantMessage)

        isGenerating = true

        generationTask = Task {
            do {
                // Agent loop - keep going until we get a final response (no tool calls)
                var continueLoop = true
                var loopCount = 0
                let maxLoops = 5  // Prevent infinite loops
                var toolsUsedInResponse: [ToolUsage] = []

                while continueLoop && loopCount < maxLoops {
                    loopCount += 1

                    // Build messages for chat API
                    let messages = buildChatMessages()
                    let tools = toolsEnabled ? toolRegistry.buildToolsPayload() : []

                    // Call Ollama chat API
                    let result = try await chatWithTools(
                        model: currentConversation.model,
                        messages: messages,
                        tools: tools,
                        temperature: currentConversation.temperature
                    )

                    // Check if we have tool calls
                    if let toolCalls = result.toolCalls, !toolCalls.isEmpty {
                        // Execute each tool call
                        for toolCall in toolCalls {
                            let query = toolCall.query ?? toolCall.name
                            currentToolAction = "Searching: \(query)"

                            // Track tool usage
                            let toolUsage = ToolUsage(
                                toolName: toolCall.name,
                                query: toolCall.query
                            )
                            toolsUsedInResponse.append(toolUsage)

                            do {
                                let toolResult = try await toolRegistry.execute(
                                    ToolCall(name: toolCall.name, arguments: toolCall.arguments)
                                )

                                // Add tool result to conversation (hidden from UI but sent to model)
                                let toolMessage = ChatMessage(
                                    role: .system,
                                    content: "[Tool Result from \(toolCall.name)]: \(toolResult)"
                                )
                                currentConversation.messages.append(toolMessage)

                            } catch {
                                print("[ChatService] Tool error: \(error)")
                                let errorMessage = ChatMessage(
                                    role: .system,
                                    content: "[Tool Error]: \(error.localizedDescription)"
                                )
                                currentConversation.messages.append(errorMessage)
                            }
                        }
                        currentToolAction = nil
                        // Continue loop to get final response
                    } else {
                        // No tool calls - this is the final response
                        continueLoop = false

                        // Update assistant message with final content and tools used
                        if let index = currentConversation.messages.lastIndex(where: { $0.id == assistantMessage.id }) {
                            currentConversation.messages[index].content = result.content
                            currentConversation.messages[index].isStreaming = false
                            currentConversation.messages[index].toolsUsed = toolsUsedInResponse
                        }
                    }
                }

                // If we hit max loops, mark as complete
                if loopCount >= maxLoops {
                    if let index = currentConversation.messages.lastIndex(where: { $0.id == assistantMessage.id }) {
                        if currentConversation.messages[index].content.isEmpty {
                            currentConversation.messages[index].content =
                                "I encountered too many tool calls. Please try a simpler question."
                        }
                        currentConversation.messages[index].isStreaming = false
                        currentConversation.messages[index].toolsUsed = toolsUsedInResponse
                    }
                }

            } catch {
                // Handle error
                if let index = currentConversation.messages.lastIndex(where: { $0.id == assistantMessage.id }) {
                    currentConversation.messages[index].isStreaming = false
                    currentConversation.messages[index].error = error.localizedDescription

                    if currentConversation.messages[index].content.isEmpty {
                        currentConversation.messages[index].content = "Failed to generate response"
                    }
                }
                print("[ChatService] Generation error: \(error)")
            }

            currentToolAction = nil
            isGenerating = false
            generationTask = nil
        }
    }

    // MARK: - Chat API with Tools

    /// Result from chat API
    struct ChatResult {
        let content: String
        let toolCalls: [ParsedToolCall]?

        struct ParsedToolCall {
            let name: String
            let arguments: [String: Any]

            var query: String? {
                arguments["query"] as? String
            }
        }
    }

    /// Call Ollama chat API with tools support
    private func chatWithTools(
        model: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        temperature: Double
    ) async throws -> ChatResult {
        let url = client.endpoint.appendingPathComponent("api/chat")

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false,
            "options": [
                "temperature": temperature
            ],
        ]

        if !tools.isEmpty {
            body["tools"] = tools
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw ChatError.modelNotFound(model)
            }
            throw ChatError.serverError(httpResponse.statusCode)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = json["message"] as? [String: Any]
        else {
            throw ChatError.invalidResponse
        }

        let content = message["content"] as? String ?? ""

        // Check for tool calls
        var parsedToolCalls: [ChatResult.ParsedToolCall]? = nil

        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
            parsedToolCalls = toolCalls.compactMap { tc in
                guard let function = tc["function"] as? [String: Any],
                    let name = function["name"] as? String
                else { return nil }

                var arguments: [String: Any] = [:]
                if let args = function["arguments"] as? [String: Any] {
                    arguments = args
                } else if let argsString = function["arguments"] as? String,
                    let argsData = argsString.data(using: .utf8),
                    let parsed = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]
                {
                    arguments = parsed
                }

                return ChatResult.ParsedToolCall(name: name, arguments: arguments)
            }
        }

        return ChatResult(content: content, toolCalls: parsedToolCalls)
    }

    /// Build messages array for chat API
    private func buildChatMessages() -> [[String: Any]] {
        var messages: [[String: Any]] = []

        // Add system prompt
        if let systemPrompt = currentConversation.systemPrompt ?? defaultSystemPrompt {
            messages.append([
                "role": "system",
                "content": systemPrompt,
            ])
        }

        // Add conversation history (last 20 messages)
        let recentMessages = currentConversation.messages.suffix(20)

        for message in recentMessages {
            if message.isStreaming { continue }  // Skip streaming placeholder

            let role: String
            switch message.role {
            case .user:
                role = "user"
            case .assistant:
                role = "assistant"
            case .system:
                role = "system"
            }

            messages.append([
                "role": role,
                "content": message.content,
            ])
        }

        return messages
    }

    /// Cancel ongoing generation
    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false

        // Mark any streaming message as complete
        if let index = currentConversation.messages.lastIndex(where: { $0.isStreaming }) {
            currentConversation.messages[index].isStreaming = false
        }
    }

    /// Start a new conversation
    func newConversation() {
        // Save current if it has messages
        if !currentConversation.messages.isEmpty {
            saveCurrentConversation()
        }

        currentConversation = ChatConversation(
            systemPrompt: defaultSystemPrompt,
            model: selectedModel
        )
    }

    /// Clear current conversation messages
    func clearConversation() {
        currentConversation.messages.removeAll()
        currentConversation.updatedAt = Date()
    }

    /// Delete a message from the conversation
    func deleteMessage(_ message: ChatMessage) {
        currentConversation.messages.removeAll { $0.id == message.id }
        currentConversation.updatedAt = Date()
    }

    // MARK: - Persistence

    private func saveCurrentConversation() {
        // Only save if there are actual messages
        guard !currentConversation.messages.isEmpty else { return }

        // Check if already exists
        if let index = conversations.firstIndex(where: { $0.id == currentConversation.id }) {
            conversations[index] = currentConversation
        } else {
            conversations.insert(currentConversation, at: 0)
        }

        saveConversations()
    }

    private func saveConversations() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(conversations) {
            UserDefaults.standard.set(data, forKey: "chat_conversations")
        }
    }

    private func loadConversations() {
        guard let data = UserDefaults.standard.data(forKey: "chat_conversations"),
            let loaded = try? JSONDecoder().decode([ChatConversation].self, from: data)
        else { return }
        conversations = loaded
    }

    func loadConversation(_ conversation: ChatConversation) {
        // Save current first
        if !currentConversation.messages.isEmpty {
            saveCurrentConversation()
        }
        currentConversation = conversation
    }

    func deleteConversation(_ conversation: ChatConversation) {
        conversations.removeAll { $0.id == conversation.id }
        saveConversations()
    }
}

// MARK: - Chat Errors

enum ChatError: Error, LocalizedError {
    case invalidResponse
    case serverError(Int)
    case modelNotFound(String)
    case ollamaNotRunning

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from AI"
        case .serverError(let code):
            return "Server error (HTTP \(code))"
        case .modelNotFound(let model):
            return "Model '\(model)' not found"
        case .ollamaNotRunning:
            return "Ollama is not running"
        }
    }
}
