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
    public let existingFrameworks: [String: String]
}

public struct IngestionPatch: Codable {
    public let logEntries: [LogEntry]
    public let timelineEntries: [String]
    public let themeUpdates: [ThemeUpdate]
    public let newThemes: [NewTheme]
    public let contradictions: [Contradiction]?
    public let indexRewrite: String?
    public let frameworkUpdates: [FrameworkUpdate]?
    public let newFrameworks: [NewFramework]?
    public let forwardReferences: [ForwardReference]?

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

    /// A new framework page to write at `wiki/frameworks/<slug>.md`.
    public struct NewFramework: Codable {
        public let slug: String
        public let fullContent: String
    }

    /// Append/refresh on an existing framework page.
    public struct FrameworkUpdate: Codable {
        public let slug: String
        public let pattern: String?           // optional rewrite of "## The Pattern" body
        public let evidenceAppend: String     // markdown to prepend inside "## Evidence"
        public let sourceCountDelta: Int
    }

    /// Forward reference: a new note resolves / updates / realizes an older note.
    /// Rendered into the `## Forward References` section of the named theme page.
    public struct ForwardReference: Codable {
        public enum Kind: String, Codable {
            case resolves
            case updates
            case realizes
        }

        public struct Endpoint: Codable {
            public let date: String
            public let noteId: String
            public let quote: String
        }

        public var kind: Kind
        public let theme: String
        public let from: Endpoint
        public let to: Endpoint
        public let summary: String
    }
}

public struct IngestionStats {
    public let notesProcessed: Int
    public let themesUpdated: Int
    public let themesCreated: Int
    public let contradictionsFlagged: Int
    public let frameworksUpdated: Int
    public let frameworksCreated: Int
    public let forwardReferencesAdded: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int

    public init(
        notesProcessed: Int,
        themesUpdated: Int,
        themesCreated: Int,
        contradictionsFlagged: Int,
        frameworksUpdated: Int = 0,
        frameworksCreated: Int = 0,
        forwardReferencesAdded: Int = 0,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheWriteTokens: Int
    ) {
        self.notesProcessed = notesProcessed
        self.themesUpdated = themesUpdated
        self.themesCreated = themesCreated
        self.contradictionsFlagged = contradictionsFlagged
        self.frameworksUpdated = frameworksUpdated
        self.frameworksCreated = frameworksCreated
        self.forwardReferencesAdded = forwardReferencesAdded
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
    }

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
