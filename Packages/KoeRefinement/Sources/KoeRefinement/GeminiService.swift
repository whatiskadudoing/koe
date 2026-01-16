import Foundation
import KoeCore
import KoeDomain

/// Service for calling Google's Gemini API to improve text (same method as Gemini CLI)
@MainActor
public final class GeminiService: ObservableObject {
    public static let shared = GeminiService()

    // MARK: - Published State

    @Published public private(set) var isReady: Bool = false

    // MARK: - Configuration

    private let apiEndpoint = "https://generativelanguage.googleapis.com/v1beta"
    private let logger = KoeLogger.refinement

    /// Model fallback chain - try each in order if rate limited
    private let modelFallbackChain = [
        "gemini-3-flash-preview",  // Primary: newest, best quality (preview)
        "gemini-2.5-flash",        // Fallback 1: fast and reliable (stable)
        "gemini-2.5-flash-lite",   // Fallback 2: fastest, lower quality
    ]

    /// Track which model was last used successfully
    @Published public private(set) var currentModel: String = "gemini-3-flash-preview"

    // API key storage
    private let apiKeyKey = "geminiApiKey"

    public var apiKey: String? {
        get { UserDefaults.standard.string(forKey: apiKeyKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: apiKeyKey)
            updateReadyState()
        }
    }

    // MARK: - Initialization

    private init() {
        updateReadyState()
    }

    // MARK: - Public API

    /// Update ready state based on API key
    public func updateReadyState() {
        isReady = apiKey != nil && !apiKey!.isEmpty
    }

    /// Check if service is ready
    public func prepare() async {
        updateReadyState()
    }

    /// Improve text using Gemini with automatic model fallback on rate limits
    public func improveText(_ text: String) async throws -> String {
        guard let key = apiKey, !key.isEmpty else {
            logger.error("Gemini: no API key configured")
            throw GeminiError.notAuthenticated
        }

        // Try models in fallback order
        var lastError: Error?

        for model in modelFallbackChain {
            do {
                let result = try await callGemini(text: text, model: model, apiKey: key)
                // Success - update current model and return
                if currentModel != model {
                    currentModel = model
                    logger.info("Gemini: switched to model \(model)")
                }
                return result
            } catch let error as GeminiError {
                lastError = error
                if case .rateLimited = error {
                    logger.warning("Gemini: rate limited on \(model), trying next model...")
                    continue // Try next model
                }
                // For other errors, don't fallback
                throw error
            } catch {
                lastError = error
                throw error
            }
        }

        // All models exhausted
        logger.error("Gemini: all models rate limited")
        throw lastError ?? GeminiError.allModelsRateLimited
    }

    /// Call Gemini API with a specific model
    private func callGemini(text: String, model: String, apiKey key: String) async throws -> String {
        let url = URL(string: "\(apiEndpoint)/models/\(model):generateContent?key=\(key)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let systemPrompt = """
            You are a prompt refiner that transforms spoken/dictated text into well-structured prompts optimized for Claude Code (Opus 4.5).

            ## How Claude Code Works

            Claude Code is an agentic coding assistant that:
            - Takes instructions LITERALLY - it does exactly what you ask, nothing more
            - Responds best to specific, explicit instructions over vague requests
            - Prefers structured prompts with clear sections
            - Works better when given context BEFORE the task
            - Handles one focused intent per prompt better than mixed requests

            ## Claude Code Prompting Best Practices

            1. **Be Explicit and Specific**
               BAD: "add tests for foo.py"
               GOOD: "Write a new test case for foo.py covering the edge case where the user is logged out. Avoid mocks."

            2. **Use Action-Oriented Verbs**
               Start with imperative verbs: Create, Update, Fix, Refactor, Add, Remove, Implement, Optimize

            3. **Provide Context First**
               Mention relevant files, existing patterns, or what already exists BEFORE stating the task.

            4. **Include Constraints**
               State what NOT to do: "Avoid over-engineering", "Don't create new files unless necessary", "Keep the existing API"

            5. **Single Intent Per Prompt**
               Don't mix building + learning + reviewing. Keep each prompt focused on ONE mode.

            6. **For Complex Tasks**
               Add "Make a plan first" or "ultrathink" to trigger deeper reasoning before implementation.

            ## Transformation Rules

            - Remove filler words (um, uh, like, you know, so, basically, I mean, kind of, I guess, maybe)
            - Fix grammar and make text concise
            - Preserve ALL original intent and key details
            - Keep the natural tone - don't over-formalize casual requests
            - For coding tasks: extract file names, function names, expected behavior, and constraints
            - For simple requests: keep them simple! Don't inflate a 5-word request into a paragraph
            - For questions: clarify what information is needed and why
            - If multiple unrelated requests exist: output them as separate numbered items
            - DO NOT answer or execute the request - only restructure it
            - DO NOT add information that wasn't implied in the original
            - DO NOT use corporate/formal language like "operational status", "functionality", "verify proper operation"

            **CRITICAL**: Output ONLY plain text. NEVER use XML tags. Keep output natural and conversational - like how a developer would actually type to Claude Code.

            ## Examples

            INPUT: "so um I want to like make the recording start faster you know it takes too long when I press the button"

            OUTPUT:
            Optimize recording startup latency. The current delay between pressing the record button and actual recording start is too long.

            Focus on the recording initialization code and identify what's causing the delay. Keep changes minimal and avoid restructuring the existing architecture.

            ---

            INPUT: "can you look at my code and like think about how to make it faster I guess the database queries are slow"

            OUTPUT:
            Analyze and optimize the slow database queries.

            Context: Performance issue with database query execution time.

            Requested actions:
            1. Identify which queries are slow
            2. Analyze the root cause of poor performance
            3. Suggest specific optimizations

            ---

            INPUT: "fix the bug in the login thing where users cant sign in sometimes and also maybe add a loading spinner"

            OUTPUT:
            Two separate tasks:

            1. Fix the intermittent login bug where users sometimes cannot sign in. Investigate the login flow to identify under what conditions the bug occurs.

            2. Add a loading spinner to the login form during authentication.

            ---

            INPUT: "I need to refactor this whole authentication system it's a mess and we need to support OAuth and also the tests are broken"

            OUTPUT:
            Make a plan first for refactoring the authentication system.

            Current issues:
            - Codebase needs cleanup/restructuring
            - Need to add OAuth support
            - Existing tests are broken

            Start by analyzing the current auth implementation and propose a refactoring approach before making changes. Fix existing tests as part of the refactor.

            ---

            INPUT: "um so we have this pipeline thing and I want to add a new node that does like text formatting or something"

            OUTPUT:
            Add a new pipeline node for text formatting.

            Before implementing, identify:
            1. Where existing nodes are defined (check the node registry)
            2. The pattern used by other nodes

            Follow the existing node implementation pattern. Keep the new node minimal and focused on text formatting only.

            ---

            INPUT: "let's see if this works, check if it's working properly"

            OUTPUT:
            Test if this is working correctly.

            ---

            INPUT: "can you show me the code for the main function"

            OUTPUT:
            Show me the main function code.

            ---

            INPUT: "what's wrong with this, it's not working"

            OUTPUT:
            Debug this - it's not working. Identify the issue.
            """

        let requestBody = GeminiRequest(
            contents: [
                GeminiContent(
                    role: "user",
                    parts: [GeminiPart(text: text)]
                )
            ],
            systemInstruction: GeminiSystemInstruction(
                parts: [GeminiPart(text: systemPrompt)]
            ),
            generationConfig: GeminiGenerationConfig(
                temperature: 0.3,
                maxOutputTokens: 2048
            )
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        logger.info("Gemini: sending API request (\(text.count) chars)...")

        let (data, response) = try await URLSession.shared.data(for: request)

        logger.info("Gemini: got API response")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"

            switch httpResponse.statusCode {
            case 401, 403:
                logger.error("Gemini API auth error - check API key")
                throw GeminiError.authExpired
            case 429:
                logger.warning("Gemini API rate limited (429)")
                throw GeminiError.rateLimited
            default:
                logger.error("Gemini API error: \(errorBody)")
                throw GeminiError.apiFailed(httpResponse.statusCode, errorBody)
            }
        }

        return try parseResponse(data)
    }

    private func parseResponse(_ data: Data) throws -> String {
        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

        guard let candidate = geminiResponse.candidates.first,
            let part = candidate.content.parts.first
        else {
            throw GeminiError.noResponse
        }

        let improvedText = part.text.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Gemini improved text to \(improvedText.count) chars")

        return improvedText
    }

    /// Shutdown (no-op for API service)
    public func shutdown() async {
        // Nothing to clean up for API service
    }
}

// MARK: - Gemini API Types

public enum GeminiError: LocalizedError {
    case notAuthenticated
    case authExpired
    case invalidResponse
    case apiFailed(Int, String)
    case noResponse
    case rateLimited
    case allModelsRateLimited

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not signed in to Google"
        case .authExpired:
            return "Google authentication expired"
        case .invalidResponse:
            return "Invalid response from Gemini"
        case .apiFailed(let code, let message):
            return "Gemini API error (\(code)): \(message)"
        case .noResponse:
            return "No response from Gemini"
        case .rateLimited:
            return "Gemini API rate limited"
        case .allModelsRateLimited:
            return "All Gemini models are rate limited - try again later"
        }
    }
}

private struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiSystemInstruction
    let generationConfig: GeminiGenerationConfig
}

private struct GeminiContent: Codable {
    let role: String
    let parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    let text: String
}

private struct GeminiSystemInstruction: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiGenerationConfig: Encodable {
    let temperature: Double
    let maxOutputTokens: Int
}

private struct GeminiResponse: Decodable {
    let candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    let content: GeminiContent
}
