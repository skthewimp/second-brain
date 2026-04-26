import Foundation

public struct RawNote {
    public let id: String
    public let path: URL
    public let frontmatter: [String: String]
    public let themes: [String]
    public let body: String

    public init(id: String, path: URL, frontmatter: [String: String], themes: [String], body: String) {
        self.id = id
        self.path = path
        self.frontmatter = frontmatter
        self.themes = themes
        self.body = body
    }
}

public struct VaultSnapshot {
    public let unprocessed: [RawNote]
    public let existingThemes: [String: String]
    public let contradictions: String
    public let timelineTail: String
    public let logTail: String
    public let indexContent: String
}

public struct IngestionPatch: Codable {
    public let logEntries: [LogEntry]
    public let timelineEntries: [String]
    public let themeUpdates: [ThemeUpdate]
    public let newThemes: [NewTheme]
    public let contradictions: [Contradiction]?
    public let indexRewrite: String?

    public struct LogEntry: Codable {
        public let noteId: String
        public let summary: String
    }

    public struct ThemeUpdate: Codable {
        public let theme: String
        public let currentState: String?
        public let evolutionAppend: String
        public let sourceCountDelta: Int
    }

    public struct NewTheme: Codable {
        public let name: String
        public let fullContent: String
    }

    public struct Contradiction: Codable {
        public enum Kind: String, Codable {
            case extracted
            case inferred
            case ambiguous
        }

        public struct Position: Codable {
            public let date: String
            public let quote: String
            public let sourceNoteId: String?
        }

        public var kind: Kind
        public let topic: String
        public let before: Position
        public let now: Position
        public let nature: String?
        public let relatedThemes: [String]?
    }
}

public struct IngestionStats {
    public let notesProcessed: Int
    public let themesUpdated: Int
    public let themesCreated: Int
    public let contradictionsFlagged: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int

    public var estimatedCostUSD: Double {
        let inCost = Double(inputTokens) * 3.0 / 1_000_000
        let outCost = Double(outputTokens) * 15.0 / 1_000_000
        let cacheReadCost = Double(cacheReadTokens) * 0.30 / 1_000_000
        let cacheWriteCost = Double(cacheWriteTokens) * 3.75 / 1_000_000
        return inCost + outCost + cacheReadCost + cacheWriteCost
    }
}

public enum IngestError: LocalizedError {
    case vaultNotFound(String)
    case missingAPIKey
    case apiError(Int, String)
    case decodeError(String)

    public var errorDescription: String? {
        switch self {
        case .vaultNotFound(let p): return "Vault not found at \(p)"
        case .missingAPIKey: return "ANTHROPIC_API_KEY env var not set"
        case .apiError(let code, let msg): return "Claude API error (\(code)): \(msg)"
        case .decodeError(let msg): return "Failed to decode model output: \(msg)"
        }
    }
}
