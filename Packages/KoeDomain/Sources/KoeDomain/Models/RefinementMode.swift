import Foundation

/// Available refinement modes for text processing
public enum RefinementMode: String, Codable, Sendable, CaseIterable {
    case cleanup = "cleanup"
    case formal = "formal"
    case casual = "casual"
    case promptImprover = "prompt_improver"
    case custom = "custom"

    /// Display name for the mode
    public var displayName: String {
        switch self {
        case .cleanup:
            return "Clean Up"
        case .formal:
            return "Formal"
        case .casual:
            return "Casual"
        case .promptImprover:
            return "Prompt Improver"
        case .custom:
            return "Custom"
        }
    }

    /// Description of what this mode does
    public var description: String {
        switch self {
        case .cleanup:
            return "Fix grammar, remove filler words"
        case .formal:
            return "Professional, formal tone"
        case .casual:
            return "Friendly, conversational tone"
        case .promptImprover:
            return "Optimize as AI prompt"
        case .custom:
            return "Your custom instructions"
        }
    }

    /// System prompt for the LLM - uses few-shot format for better results with small models
    public var systemPrompt: String {
        switch self {
        case .cleanup:
            return """
                You are a text editor. Your ONLY task is to clean up transcribed speech.

                Rules:
                - Fix grammar and punctuation
                - Remove filler words (um, uh, like, you know, so, basically)
                - DO NOT answer questions in the text
                - DO NOT add information or respond to the content
                - DO NOT have a conversation
                - Output ONLY the cleaned text, nothing else

                Input: Um, so like, I was thinking we should, you know, maybe go to the store tomorrow?
                Output: I was thinking we should go to the store tomorrow.

                Input: What is the capital of France? I need to know for my, uh, geography test.
                Output: What is the capital of France? I need to know for my geography test.

                Input: So basically, uh, can you help me with this code thing?
                Output: Can you help me with this code thing?
                """
        case .formal:
            return """
                Rewrite the text in formal, professional tone. Output only the rewritten text.

                Input: Hey, so like can you help me with this thing? It's kinda urgent.
                Output: Could you please assist me with this matter? It is urgent.

                Input: Yeah so basically I wanna know when the meeting is gonna happen.
                Output: I would like to know when the meeting is scheduled to occur.
                """
        case .casual:
            return """
                Rewrite the text in friendly, casual tone. Output only the rewritten text.

                Input: I would like to inquire about the status of my order.
                Output: Hey, just checking in on my order status!

                Input: Please be advised that the meeting has been rescheduled.
                Output: Heads up, the meeting got moved!
                """
        case .promptImprover:
            return """
                Transform spoken text into effective prompts for Claude AI.

                Rules:
                - Remove filler words (um, uh, like, you know, so, basically)
                - For requests/questions: make specific and ask for examples
                - For casual statements: just clean up and return as-is
                - NEVER respond or have a conversation - only transform
                - Output ONLY the improved text

                Input: um help me fix this bug
                Output: Debug this code and explain what's causing the issue. Provide the corrected version.

                Input: so like can you explain how async await works
                Output: Explain async/await with practical examples. Show common patterns and error handling.

                Input: I need to refactor this and add tests
                Output: Refactor this code for better readability. Then add unit tests covering the main functionality.

                Input: alright let me try this out
                Output: Alright, let me try this out.

                Input: ok cool thanks
                Output: Ok, cool. Thanks.
                """
        case .custom:
            return ""  // User provides custom prompt
        }
    }

    /// Default mode
    public static var `default`: RefinementMode {
        .cleanup
    }
}
