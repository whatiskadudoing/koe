import Foundation

// MARK: - Web Search Tool

/// Tool that searches Wikipedia for information (free, no API key needed)
final class WebSearchTool: ChatTool, @unchecked Sendable {
    let name = "web_search"

    let description = """
        Search for information using Wikipedia. Use this when you need factual information \
        about topics, people, places, events, concepts, or anything you're unsure about. \
        This searches Wikipedia's vast knowledge base.
        """

    let parameters: [String: Any] = [
        "type": "object",
        "properties": [
            "query": [
                "type": "string",
                "description": "The search query to look up",
            ],
            "max_results": [
                "type": "integer",
                "description": "Maximum number of results to return (default: 3)",
            ],
        ],
        "required": ["query"],
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        guard let query = arguments["query"] as? String, !query.isEmpty else {
            throw ToolError.invalidArguments("Missing 'query' parameter")
        }

        let maxResults = arguments["max_results"] as? Int ?? 3

        print("[WebSearchTool] Searching Wikipedia for: \(query)")

        // Search Wikipedia
        let searchResults = try await searchWikipedia(query: query, limit: maxResults)

        if searchResults.isEmpty {
            return "No Wikipedia articles found for: \(query)"
        }

        // Get summaries for top results
        var output = "Wikipedia search results for '\(query)':\n\n"

        for (index, result) in searchResults.enumerated() {
            output += "[\(index + 1)] \(result.title)\n"

            // Fetch summary for this article
            if let summary = try? await getWikipediaSummary(title: result.title) {
                output += summary
            } else {
                output += result.snippet
            }
            output += "\n\n"
        }

        return output
    }

    // MARK: - Wikipedia Search API

    private struct WikiSearchResult {
        let title: String
        let snippet: String
        let pageId: Int
    }

    private func searchWikipedia(query: String, limit: Int) async throws -> [WikiSearchResult] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(
                string:
                    "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=\(encodedQuery)&format=json&srlimit=\(limit)&utf8=1"
            )
        else {
            throw ToolError.executionFailed("Invalid search query")
        }

        var request = URLRequest(url: url)
        request.setValue(
            "KoeApp/1.0 (https://github.com/user/koe; contact@example.com)",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ToolError.executionFailed("Wikipedia search failed")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let query = json["query"] as? [String: Any],
            let search = query["search"] as? [[String: Any]]
        else {
            return []
        }

        return search.compactMap { item in
            guard let title = item["title"] as? String,
                let snippet = item["snippet"] as? String,
                let pageId = item["pageid"] as? Int
            else { return nil }

            // Clean HTML from snippet
            let cleanSnippet =
                snippet
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&#039;", with: "'")

            return WikiSearchResult(title: title, snippet: cleanSnippet, pageId: pageId)
        }
    }

    // MARK: - Wikipedia Summary API

    private func getWikipediaSummary(title: String) async throws -> String {
        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encodedTitle)")
        else {
            throw ToolError.executionFailed("Invalid title")
        }

        var request = URLRequest(url: url)
        request.setValue(
            "KoeApp/1.0 (https://github.com/user/koe; contact@example.com)",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ToolError.executionFailed("Failed to fetch summary")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let extract = json["extract"] as? String
        else {
            throw ToolError.executionFailed("Failed to parse summary")
        }

        // Truncate if too long
        if extract.count > 500 {
            let truncated = String(extract.prefix(500))
            if let lastPeriod = truncated.lastIndex(of: ".") {
                return String(truncated[...lastPeriod])
            }
            return truncated + "..."
        }

        return extract
    }
}

// MARK: - Tool Registration

extension ToolRegistry {
    /// Register all built-in tools
    func registerBuiltInTools() {
        register(WebSearchTool())
        print("[ToolRegistry] Registered web_search tool (Wikipedia)")
    }
}
