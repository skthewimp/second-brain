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

    /// Process a transcription into structured note data.
    func process(transcription: String) async throws -> ClaudeProcessedNote {
        let systemPrompt = """
        You are processing a voice note for a personal thought-capture system called Pensieve. \
        The user records stream-of-consciousness thoughts throughout their day. Your job is to \
        extract structure from the raw transcription.

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
        - keyQuotes should be verbatim phrases from the transcription that are particularly revealing or well-put
        - connections are speculative — what other life areas might this relate to?
        - emotionalTone: one of: reflective, anxious, excited, frustrated, hopeful, confused, determined, sad, neutral, angry, grateful
        - Return ONLY the JSON object, no other text
        """

        let request = ClaudeAPIRequest(
            model: model,
            max_tokens: 1024,
            messages: [
                ClaudeMessage(role: "user", content: """
                    Process this voice note transcription:

                    \(transcription)
                    """)
            ]
        )

        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.addValue("application/json", forHTTPHeaderField: "content-type")

        // Build the request body manually to include system prompt
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": "Process this voice note transcription:\n\n\(transcription)"]
            ]
        ]

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? "no body"
            throw ClaudeError.apiError(statusCode: statusCode, message: responseBody)
        }

        // Parse the Claude response
        let claudeResponse = try JSONDecoder().decode(ClaudeAPIResponse.self, from: data)

        guard let textBlock = claudeResponse.content.first(where: { $0.type == "text" }),
              let text = textBlock.text else {
            throw ClaudeError.noTextInResponse
        }

        // Extract JSON from the response (Claude might wrap it in markdown code blocks)
        let jsonString = extractJSON(from: text)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ClaudeError.invalidJSON
        }

        let processedNote = try JSONDecoder().decode(ClaudeProcessedNote.self, from: jsonData)
        return processedNote
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
