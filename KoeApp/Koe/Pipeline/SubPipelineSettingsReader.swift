import Foundation
import KoeStorage

/// Reads sub-pipeline settings from UserDefaults based on NodeRegistry configuration
/// This bridges the UI settings to the data layer for storage and prompt building
enum SubPipelineSettingsReader {
    /// Read current sub-pipeline settings for a given AI node
    /// - Parameter aiNodeTypeId: The AI node type ID (e.g., "ai-fast", "ai-balanced")
    /// - Returns: SubPipelineSettings with current user selections
    static func readSettings(for aiNodeTypeId: String) -> SubPipelineSettings {
        guard let aiNode = NodeRegistry.shared.node(for: aiNodeTypeId) else {
            return SubPipelineSettings()
        }

        // Find active rewrite style
        let rewriteStyle = findActiveNode(
            in: aiNode.subNodes,
            withGroup: "ai-rewrite-style"
        )?.displayName.lowercased()

        // Check if translate is enabled (standalone node with "translate" in typeId)
        let translateNode = aiNode.subNodes.first {
            $0.typeId.contains("translate") && $0.exclusiveGroup == nil
        }
        let translateEnabled: Bool
        if let node = translateNode, let key = node.persistenceKey {
            translateEnabled = UserDefaults.standard.bool(forKey: key)
        } else {
            translateEnabled = false
        }

        // Find target language (only if translate is enabled)
        let targetLanguage: String?
        if translateEnabled {
            targetLanguage =
                findActiveNode(
                    in: aiNode.subNodes,
                    withGroup: "ai-language"
                )?.displayName
        } else {
            targetLanguage = nil
        }

        return SubPipelineSettings(
            rewriteStyle: rewriteStyle,
            translateEnabled: translateEnabled,
            targetLanguage: targetLanguage,
            customInstructions: nil
        )
    }

    /// Find the active node in an exclusive group
    private static func findActiveNode(in nodes: [NodeInfo], withGroup group: String) -> NodeInfo? {
        for node in nodes {
            guard node.exclusiveGroup == group,
                let key = node.persistenceKey,
                UserDefaults.standard.bool(forKey: key)
            else {
                continue
            }
            return node
        }
        return nil
    }

    /// Read settings and build the prompt modification string
    static func buildPromptModification(for aiNodeTypeId: String) -> String? {
        let settings = readSettings(for: aiNodeTypeId)
        return settings.promptInstructions
    }

    /// Get a summary of current settings for display
    static func settingsSummary(for aiNodeTypeId: String) -> String {
        let settings = readSettings(for: aiNodeTypeId)
        var parts: [String] = []

        if let style = settings.rewriteStyle {
            parts.append(style.capitalized)
        }

        if settings.translateEnabled {
            if let lang = settings.targetLanguage {
                parts.append("→ \(lang)")
            } else {
                parts.append("Translate (no language)")
            }
        }

        return parts.isEmpty ? "Default" : parts.joined(separator: " ")
    }
}

// MARK: - NodeExecutionData Builder

/// Helper to build NodeExecutionData from various sources
enum NodeExecutionDataBuilder {
    /// Build node execution data for a transcription node
    static func transcription(
        nodeTypeId: String,
        nodeName: String,
        startTime: Date,
        endTime: Date,
        status: ExecutionStatus,
        audioPath: String?,
        audioDuration: Double?,
        transcribedText: String?,
        language: String?,
        confidence: Double?,
        model: String?,
        error: Error? = nil
    ) -> NodeExecutionData {
        var customData: [String: AnyCodableValue] = [:]

        if let lang = language {
            customData["language"] = .string(lang)
        }
        if let conf = confidence {
            customData["confidence"] = .double(conf)
        }
        if let model = model {
            customData["model"] = .string(model)
        }

        return NodeExecutionData(
            nodeTypeId: nodeTypeId,
            nodeName: nodeName,
            startTime: startTime,
            endTime: endTime,
            status: status,
            input: .audio(path: audioPath ?? "", duration: audioDuration ?? 0),
            output: transcribedText.map { .text($0) } ?? .none,
            error: error.map { NodeError.from($0) },
            customData: customData
        )
    }

    /// Build node execution data for an AI processing node
    static func aiProcessing(
        nodeTypeId: String,
        nodeName: String,
        startTime: Date,
        endTime: Date,
        status: ExecutionStatus,
        inputText: String,
        outputText: String?,
        subPipelineSettings: SubPipelineSettings,
        tokensUsed: Int? = nil,
        promptUsed: String? = nil,
        error: Error? = nil
    ) -> NodeExecutionData {
        var customData: [String: AnyCodableValue] = [:]

        if let style = subPipelineSettings.rewriteStyle {
            customData["rewriteStyle"] = .string(style)
        }
        customData["translateEnabled"] = .bool(subPipelineSettings.translateEnabled)
        if let lang = subPipelineSettings.targetLanguage {
            customData["targetLanguage"] = .string(lang)
        }
        if let tokens = tokensUsed {
            customData["tokensUsed"] = .int(tokens)
        }
        if let prompt = promptUsed {
            customData["systemPrompt"] = .string(String(prompt.prefix(500)))  // Truncate for storage
        }

        let wasTransformed = outputText != nil && outputText != inputText

        return NodeExecutionData(
            nodeTypeId: nodeTypeId,
            nodeName: nodeName,
            startTime: startTime,
            endTime: endTime,
            status: status,
            input: .text(inputText),
            output: outputText.map { .text($0, wasTransformed: wasTransformed) } ?? .none,
            error: error.map { NodeError.from($0) },
            customData: customData
        )
    }

    /// Build node execution data for an action node (auto-type, auto-enter)
    static func action(
        nodeTypeId: String,
        nodeName: String,
        startTime: Date,
        endTime: Date,
        status: ExecutionStatus,
        inputText: String?,
        actionPerformed: String,
        error: Error? = nil
    ) -> NodeExecutionData {
        NodeExecutionData(
            nodeTypeId: nodeTypeId,
            nodeName: nodeName,
            startTime: startTime,
            endTime: endTime,
            status: status,
            input: inputText.map { .text($0) } ?? .none,
            output: .action,
            error: error.map { NodeError.from($0) },
            customData: ["actionPerformed": .string(actionPerformed)]
        )
    }

    /// Build node execution data for a trigger node
    static func trigger(
        nodeTypeId: String,
        nodeName: String,
        startTime: Date,
        endTime: Date,
        status: ExecutionStatus,
        triggerSource: String
    ) -> NodeExecutionData {
        NodeExecutionData(
            nodeTypeId: nodeTypeId,
            nodeName: nodeName,
            startTime: startTime,
            endTime: endTime,
            status: status,
            input: .none,
            output: .none,
            error: nil,
            customData: ["triggerSource": .string(triggerSource)]
        )
    }

    /// Build node execution data for a recorder node
    static func recorder(
        nodeTypeId: String,
        nodeName: String,
        startTime: Date,
        endTime: Date,
        status: ExecutionStatus,
        audioDuration: Double,
        sampleRate: Double,
        audioPath: String?,
        error: Error? = nil
    ) -> NodeExecutionData {
        var customData: [String: AnyCodableValue] = [
            "audioDuration": .double(audioDuration),
            "sampleRate": .double(sampleRate),
        ]

        if let path = audioPath {
            customData["audioPath"] = .string(path)
        }

        return NodeExecutionData(
            nodeTypeId: nodeTypeId,
            nodeName: nodeName,
            startTime: startTime,
            endTime: endTime,
            status: status,
            input: .none,
            output: .audio(path: audioPath ?? "", duration: audioDuration),
            error: error.map { NodeError.from($0) },
            customData: customData
        )
    }
}
