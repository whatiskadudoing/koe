import Foundation

/// Combined refinement options that can be toggled independently
public struct RefinementOptions: Sendable {
    public var cleanup: Bool
    public var tone: ToneStyle
    public var promptImprover: Bool
    public var customInstructions: String?

    public init(
        cleanup: Bool = true,
        tone: ToneStyle = .none,
        promptImprover: Bool = false,
        customInstructions: String? = nil
    ) {
        self.cleanup = cleanup
        self.tone = tone
        self.promptImprover = promptImprover
        self.customInstructions = customInstructions
    }

    /// Build the combined system prompt based on enabled options
    public var systemPrompt: String {
        var instructions: [String] = []

        // Base instruction
        instructions.append("You are a text editor. Process the following transcribed speech.")

        // Cleanup instructions
        if cleanup {
            instructions.append(
                """
                CLEANUP:
                - Fix grammar and punctuation
                - Remove filler words (um, uh, like, you know, so, basically, I mean)
                - Remove false starts and repetitions
                """)
        }

        // Prompt improver takes priority over tone
        if promptImprover {
            instructions.append(
                """
                PROMPT OPTIMIZATION:
                - Make it clear and specific for AI assistants
                - Add structure if needed (bullet points, numbered steps)
                - Remove ambiguity and vague language
                - Keep the original intent and requirements
                """)
        } else if let tonePrompt = tone.promptFragment {
            instructions.append("TONE: \(tonePrompt)")
        }

        // Custom instructions
        if let custom = customInstructions, !custom.isEmpty {
            instructions.append("ADDITIONAL INSTRUCTIONS: \(custom)")
        }

        // Output rules
        instructions.append(
            """

            CRITICAL RULES:
            - Output ONLY the processed text
            - Do NOT add any introduction or commentary
            - Do NOT say "Here is..." or "Sure!" or similar
            - Do NOT wrap in quotes
            - Keep the speaker's intent and meaning intact
            """)

        return instructions.joined(separator: "\n\n")
    }

    /// Summary of what transformations will be applied
    public var summaryText: String {
        var parts: [String] = []

        if cleanup {
            parts.append("clean up")
        }

        if promptImprover {
            parts.append("prompt mode")
        } else if tone != .none {
            parts.append(tone.displayName.lowercased())
        }

        if let custom = customInstructions, !custom.isEmpty {
            parts.append("custom")
        }

        return parts.isEmpty ? "no changes" : parts.joined(separator: " + ")
    }
}
