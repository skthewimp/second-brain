import Foundation

/// Calls Claude API to extract structured information from a voice note transcription.
/// This is the "thinking" step — Claude identifies themes, emotional tone, key quotes,
/// and potential connections to other topics.
class ClaudeProcessingService {

    private let apiKey: String
    private let model = "claude-sonnet-4-6"
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    struct ProcessResult {
        let note: ClaudeProcessedNote
        let articleFetched: Bool?  // nil when no URLs in input
    }

    /// Process a transcription into structured note data. (voice path)
    func process(transcription: String) async throws -> ClaudeProcessedNote {
        let result = try await processInput(text: transcription, urls: [], kind: .voice)
        return result.note
    }

    /// Process typed text and/or URLs.
    /// - kind: .text (no URLs) or .url (with URLs to fetch)
    func processInput(text: String, urls: [URL], kind: Source) async throws -> ProcessResult {
        let systemPrompt = Self.buildSystemPrompt(kind: kind)
        let userMessage = Self.buildUserMessage(text: text, urls: urls, kind: kind)

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        // Enable server-side web fetch when URLs present.
        if kind == .url, !urls.isEmpty {
            body["tools"] = [[
                "type": "web_fetch_20250910",
                "name": "web_fetch",
                "max_uses": urls.count
            ]]
        }

        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.addValue("application/json", forHTTPHeaderField: "content-type")
        // web_fetch is a beta tool — declare opt-in.
        if kind == .url, !urls.isEmpty {
            urlRequest.addValue("web-fetch-2025-09-10", forHTTPHeaderField: "anthropic-beta")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? "no body"
            throw ClaudeError.apiError(statusCode: statusCode, message: responseBody)
        }

        // Parse content blocks. With tools, multiple blocks may be present;
        // we want the final text block (Claude's structured JSON answer).
        // We also inspect tool_use / web_fetch_tool_result blocks to detect fetch failures.
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentBlocks = json["content"] as? [[String: Any]] else {
            throw ClaudeError.invalidJSON
        }

        var textOut: String?
        var anyFetchAttempted = false
        var anyFetchFailed = false

        for block in contentBlocks {
            let type = block["type"] as? String ?? ""
            switch type {
            case "text":
                textOut = block["text"] as? String
            case "web_fetch_tool_result", "tool_result":
                anyFetchAttempted = true
                // Anthropic wraps result content. Detect explicit error markers.
                if let content = block["content"] as? [String: Any],
                   (content["type"] as? String) == "web_fetch_tool_result_error" {
                    anyFetchFailed = true
                } else if let isError = block["is_error"] as? Bool, isError {
                    anyFetchFailed = true
                }
            case "server_tool_use":
                anyFetchAttempted = true
            default:
                break
            }
        }

        guard let text = textOut else { throw ClaudeError.noTextInResponse }

        let jsonString = extractJSON(from: text)
        guard let jsonData = jsonString.data(using: .utf8) else { throw ClaudeError.invalidJSON }
        let processed = try JSONDecoder().decode(ClaudeProcessedNote.self, from: jsonData)

        let fetched: Bool?
        if kind == .url, !urls.isEmpty {
            // If we never saw any fetch tool activity, treat as failure (Claude didn't fetch).
            fetched = anyFetchAttempted && !anyFetchFailed
        } else {
            fetched = nil
        }

        return ProcessResult(note: processed, articleFetched: fetched)
    }

    private static func buildSystemPrompt(kind: Source) -> String {
        let base = """
        You are processing a thought capture for a personal thought-capture system called Pensieve. \
        The user records stream-of-consciousness thoughts throughout their day — sometimes spoken \
        aloud and transcribed, sometimes typed, sometimes a reaction to something they read online. \
        Your job is to extract structure from the raw input.

        Return a JSON object with exactly these fields:
        {
          "title": "3-5 word title for this thought",
          "summary": ["bullet point 1", "bullet point 2", ...],
          "themes": ["theme1", "theme2", ...],
          "emotionalTone": "one word describing the emotional tone",
          "keyQuotes": ["notable phrase 1", ...],
          "connections": ["potential connection to topic X", ...]
        }

        Rules:
        - themes should be lowercase, simple words (e.g., "career", "health", "priorities", "relationships", "money", "creativity")
        - Use consistent theme names across notes (prefer common words)
        - keyQuotes should be verbatim phrases from the input that are particularly revealing or well-put
        - connections are speculative — what other life areas might this relate to?
        - emotionalTone: one of: reflective, anxious, excited, frustrated, hopeful, confused, determined, sad, neutral, angry, grateful
        - Return ONLY the JSON object, no other text
        """

        switch kind {
        case .voice, .text:
            return base
        case .url:
            return base + """


            URL CONTEXT:
            The user has shared one or more URLs along with their own text. Use the web_fetch tool \
            to fetch each URL. Treat the article content as the thing the user is reacting to, and \
            the user's text as their take on it. Themes, key quotes, and connections should reflect \
            the user's reaction (their take), not just summarize the article. If a fetch fails, \
            proceed using the user's text alone.
            """
        }
    }

    private static func buildUserMessage(text: String, urls: [URL], kind: Source) -> String {
        switch kind {
        case .voice:
            return "Process this voice note transcription:\n\n\(text)"
        case .text:
            return "Process this typed thought:\n\n\(text)"
        case .url:
            let urlList = urls.map { "- \($0.absoluteString)" }.joined(separator: "\n")
            let userTake = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "(no additional text — extract from articles only)"
                : text
            return """
            The user is reacting to these URLs:
            \(urlList)

            User's take:
            \(userTake)

            Fetch each URL and return the structured JSON.
            """
        }
    }

    /// Extract JSON from Claude's response, handling possible markdown wrapping
    private func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // If wrapped in ```json ... ```
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: "\n")
            let jsonLines = lines.dropFirst().dropLast() // Remove ``` lines
            return jsonLines.joined(separator: "\n")
        }

        return trimmed
    }
}

enum ClaudeError: LocalizedError {
    case apiError(statusCode: Int, message: String)
    case noTextInResponse
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .apiError(let code, let msg): return "Claude API error (\(code)): \(msg)"
        case .noTextInResponse: return "No text in Claude response"
        case .invalidJSON: return "Could not parse Claude response as JSON"
        }
    }
}
