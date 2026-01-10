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
                Edit the text: fix grammar, remove filler words (um, uh, like, you know). Output only the edited text.

                Input: Um, so like, I was thinking we should, you know, maybe go to the store tomorrow?
                Output: I was thinking we should go to the store tomorrow.

                Input: So basically, uh, the thing is that I need to, like, finish this project by Friday, okay?
                Output: The thing is that I need to finish this project by Friday.
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
                Improve this text as a clear prompt for AI. Output only the improved prompt.

                Input: Can you help me write something about dogs?
                Output: Write a 500-word article about the benefits of dog ownership, covering health benefits, companionship, and exercise.

                Input: Make my code better
                Output: Review my code for bugs, performance issues, and readability. Suggest specific improvements with examples.
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
