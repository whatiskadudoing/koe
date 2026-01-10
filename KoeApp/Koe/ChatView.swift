import KoeUI
import SwiftUI

// MARK: - Chat View

/// Chat mode tab for AI conversations
struct ChatView: View {
    @State private var chatService = ChatService.shared
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let textColor = Color(nsColor: NSColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0))

    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            if chatService.currentConversation.messages.isEmpty {
                emptyState
            } else {
                messageList
            }

            // Input area
            inputArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(lightGray.opacity(0.5))

            VStack(spacing: 4) {
                Text("Chat Mode")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(textColor)

                Text("Start a conversation with AI")
                    .font(.system(size: 13))
                    .foregroundColor(lightGray.opacity(0.7))
            }

            Spacer()
        }
    }

    // MARK: - Message List

    /// Messages to display (filter out system messages)
    private var visibleMessages: [ChatMessage] {
        chatService.currentConversation.messages.filter { $0.role != .system }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(visibleMessages) { message in
                        ChatMessageView(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: visibleMessages.count) { _, _ in
                // Scroll to bottom when new message added
                if let lastMessage = visibleMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: visibleMessages.last?.content) { _, _ in
                // Scroll during streaming
                if let lastMessage = visibleMessages.last,
                    lastMessage.isStreaming
                {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider()
                .background(lightGray.opacity(0.2))

            HStack(spacing: 8) {
                // Microphone button (placeholder for voice input)
                Button(action: {
                    // TODO: Voice input
                }) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16))
                        .foregroundColor(lightGray)
                        .frame(width: 32, height: 32)
                        .background(lightGray.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Voice input (coming soon)")

                // Text input field
                TextField("Message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit {
                        sendMessage()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white)
                            .stroke(lightGray.opacity(0.2), lineWidth: 1)
                    )

                // Send button
                Button(action: sendMessage) {
                    Image(systemName: chatService.isGenerating ? "stop.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(canSend || chatService.isGenerating ? accentColor : lightGray.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend && !chatService.isGenerating)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(KoeColors.background)
    }

    // MARK: - Actions

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chatService.isGenerating
    }

    private func sendMessage() {
        if chatService.isGenerating {
            chatService.cancelGeneration()
            return
        }

        guard canSend else { return }

        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""

        Task {
            await chatService.sendMessage(message)
        }
    }
}

// MARK: - Chat Message View

struct ChatMessageView: View {
    let message: ChatMessage

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))
    private let textColor = Color(nsColor: NSColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0))

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Message bubble
                Text(message.content.isEmpty && message.isStreaming ? "..." : message.content)
                    .font(.system(size: 14))
                    .foregroundColor(message.role == .user ? .white : textColor)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(message.role == .user ? accentColor : Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                message.role == .assistant ? lightGray.opacity(0.2) : Color.clear,
                                lineWidth: 1
                            )
                    )

                // Streaming indicator or tool action
                if message.isStreaming {
                    StreamingIndicator()
                }

                // Tool usage indicator (show what tools were used)
                if !message.toolsUsed.isEmpty {
                    ToolsUsedIndicator(toolsUsed: message.toolsUsed)
                }

                // Error indicator
                if let error = message.error {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }
}

// MARK: - Streaming Indicator

struct StreamingIndicator: View {
    @State private var chatService = ChatService.shared

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))
    private let lightGray = Color(nsColor: NSColor(red: 0.60, green: 0.58, blue: 0.56, alpha: 1.0))

    var body: some View {
        HStack(spacing: 6) {
            if let toolAction = chatService.currentToolAction {
                // Show tool action (e.g., "Searching: query")
                Image(systemName: "globe")
                    .font(.system(size: 10))
                    .foregroundColor(accentColor)

                Text(toolAction)
                    .font(.system(size: 10))
                    .foregroundColor(accentColor)
                    .lineLimit(1)

                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 10, height: 10)
            } else {
                // Normal generating indicator
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)

                Text("Generating...")
                    .font(.system(size: 10))
                    .foregroundColor(lightGray)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(chatService.currentToolAction != nil ? accentColor.opacity(0.1) : Color.clear)
        )
    }
}

// MARK: - Tools Used Indicator

struct ToolsUsedIndicator: View {
    let toolsUsed: [ToolUsage]

    private let accentColor = Color(nsColor: NSColor(red: 0.24, green: 0.30, blue: 0.46, alpha: 1.0))

    var body: some View {
        HStack(spacing: 4) {
            ForEach(toolsUsed) { usage in
                HStack(spacing: 4) {
                    Image(systemName: usage.iconName)
                        .font(.system(size: 9))
                    Text(usage.displayName)
                        .font(.system(size: 9, weight: .medium))
                    if let query = usage.query {
                        Text("·")
                            .font(.system(size: 9))
                        Text("\"\(query.prefix(20))\(query.count > 20 ? "..." : "")\"")
                            .font(.system(size: 9))
                            .italic()
                    }
                }
                .foregroundColor(accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(accentColor.opacity(0.1))
                )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ChatView()
        .frame(width: 320, height: 500)
        .background(KoeColors.background)
}
