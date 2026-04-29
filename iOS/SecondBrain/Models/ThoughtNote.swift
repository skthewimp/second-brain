import Foundation

/// Represents a single voice note / thought capture
struct ThoughtNote: Identifiable, Codable {
    let id: String
    let filename: String
    let audioURL: URL?
    let recordedAt: Date
    let duration: TimeInterval
    var status: ProcessingStatus
    var transcription: String?
    var summary: String?
    var themes: [String]?
    var emotionalTone: String?
    var savedToWiki: Bool
    var lastError: String?
    var source: Source
    var urls: [URL]
    var articleFetched: Bool?
    var rawText: String?

    init(id: String = UUID().uuidString,
         filename: String,
         audioURL: URL? = nil,
         recordedAt: Date = Date(),
         duration: TimeInterval = 0,
         status: ProcessingStatus = .recorded,
         transcription: String? = nil,
         summary: String? = nil,
         themes: [String]? = nil,
         emotionalTone: String? = nil,
         savedToWiki: Bool = false,
         lastError: String? = nil,
         source: Source = .voice,
         urls: [URL] = [],
         articleFetched: Bool? = nil,
         rawText: String? = nil) {
        self.id = id
        self.filename = filename
        self.audioURL = audioURL
        self.recordedAt = recordedAt
        self.duration = duration
        self.status = status
        self.transcription = transcription
        self.summary = summary
        self.themes = themes
        self.emotionalTone = emotionalTone
        self.savedToWiki = savedToWiki
        self.lastError = lastError
        self.source = source
        self.urls = urls
        self.articleFetched = articleFetched
        self.rawText = rawText
    }

    // Backwards compat: existing saved notes lack `source`/`urls`/`rawText`.
    enum CodingKeys: String, CodingKey {
        case id, filename, audioURL, recordedAt, duration, status
        case transcription, summary, themes, emotionalTone, savedToWiki, lastError
        case source, urls, articleFetched, rawText
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        filename = try c.decode(String.self, forKey: .filename)
        audioURL = try c.decodeIfPresent(URL.self, forKey: .audioURL)
        recordedAt = try c.decode(Date.self, forKey: .recordedAt)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        status = try c.decode(ProcessingStatus.self, forKey: .status)
        transcription = try c.decodeIfPresent(String.self, forKey: .transcription)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        themes = try c.decodeIfPresent([String].self, forKey: .themes)
        emotionalTone = try c.decodeIfPresent(String.self, forKey: .emotionalTone)
        savedToWiki = try c.decodeIfPresent(Bool.self, forKey: .savedToWiki) ?? false
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        source = try c.decodeIfPresent(Source.self, forKey: .source) ?? .voice
        urls = try c.decodeIfPresent([URL].self, forKey: .urls) ?? []
        articleFetched = try c.decodeIfPresent(Bool.self, forKey: .articleFetched)
        rawText = try c.decodeIfPresent(String.self, forKey: .rawText)
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: recordedAt)
    }

    /// Filename for the wiki raw file (e.g., "2026-04-07_1430.md")
    var wikiFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return "\(formatter.string(from: recordedAt)).md"
    }
}

enum Source: String, Codable {
    case voice
    case text
    case url
}

enum ProcessingStatus: String, Codable {
    case recorded           // Audio captured, nothing else
    case transcribing       // WhisperKit running
    case transcribed        // Transcription done, waiting for Claude
    case processing         // Claude API call in progress
    case processed          // Claude returned structured output
    case saving             // Writing markdown to Obsidian vault
    case completed          // All done, saved to wiki
    case failed             // Something went wrong

    var displayText: String {
        switch self {
        case .recorded: return "Recorded"
        case .transcribing: return "Transcribing..."
        case .transcribed: return "Transcribed"
        case .processing: return "Thinking..."
        case .processed: return "Processed"
        case .saving: return "Saving..."
        case .completed: return "Done"
        case .failed: return "Failed"
        }
    }

    var isInProgress: Bool {
        switch self {
        case .transcribing, .processing, .saving: return true
        default: return false
        }
    }
}
