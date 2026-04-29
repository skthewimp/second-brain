import Foundation

/// Writes processed voice notes as markdown files into an Obsidian vault.
///
/// The user picks their Obsidian vault folder once (via folder picker in Settings).
/// The app saves a security-scoped bookmark so it remembers the location.
/// If no vault is selected, files are saved to the app's local Documents directory.
class ObsidianStorageService: ObservableObject {

    @Published var vaultURL: URL
    @Published var isVaultLinked: Bool
    var rawDirectory: URL

    private let bookmarkKey = "obsidianVaultBookmark"

    init() {
        // Try to restore saved vault bookmark
        if let bookmarkData = UserDefaults.standard.data(forKey: "obsidianVaultBookmark"),
           let url = ObsidianStorageService.resolveBookmark(bookmarkData) {
            self.vaultURL = url
            self.isVaultLinked = true
            self.rawDirectory = url.appendingPathComponent("raw")
            print("Restored vault: \(url.path)")
        } else {
            // Fallback to local storage
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let localVault = documents.appendingPathComponent("PensieveVault")
            self.vaultURL = localVault
            self.isVaultLinked = false
            self.rawDirectory = localVault.appendingPathComponent("raw")
        }

        ensureDirectories()
        ensureWikiScaffold()
    }

    /// Link to an Obsidian vault folder selected by the user
    func linkVault(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()

        do {
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)

            self.vaultURL = url
            self.rawDirectory = url.appendingPathComponent("raw")
            self.isVaultLinked = true

            ensureDirectories()
            ensureWikiScaffold()

            print("Linked vault: \(url.path)")
        } catch {
            print("Failed to save bookmark: \(error)")
        }

        if accessing { url.stopAccessingSecurityScopedResource() }
    }

    /// Unlink the vault (revert to local storage)
    func unlinkVault() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.vaultURL = documents.appendingPathComponent("PensieveVault")
        self.rawDirectory = vaultURL.appendingPathComponent("raw")
        self.isVaultLinked = false
        ensureDirectories()
    }

    /// Save a processed thought note as a markdown file in the raw directory.
    func save(note: ThoughtNote, processed: ClaudeProcessedNote) throws -> URL {
        // Access security-scoped resource if needed
        let accessing = vaultURL.startAccessingSecurityScopedResource()
        defer { if accessing { vaultURL.stopAccessingSecurityScopedResource() } }

        let fileURL = rawDirectory.appendingPathComponent(note.wikiFilename)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withFullTime, .withTimeZone]

        let themesYAML = processed.themes.map { "\"\($0)\"" }.joined(separator: ", ")
        let summaryBullets = processed.summary.map { "- \($0)" }.joined(separator: "\n")
        let keyQuotes = processed.keyQuotes.map { "> \($0)" }.joined(separator: "\n\n")

        // Source-specific frontmatter
        var extraFrontmatter = "source: \(note.source.rawValue)\n"
        if !note.urls.isEmpty {
            let urlsYAML = note.urls.map { "  - \($0.absoluteString)" }.joined(separator: "\n")
            extraFrontmatter += "urls:\n\(urlsYAML)\n"
        }
        if let af = note.articleFetched {
            extraFrontmatter += "article_fetched: \(af)\n"
        }

        // Body section: voice → "Transcription"; text/url → "Raw Input" + URL list
        let bodySectionTitle: String
        let bodySectionContent: String
        switch note.source {
        case .voice:
            bodySectionTitle = "Transcription"
            bodySectionContent = note.transcription ?? "*No transcription available.*"
        case .text:
            bodySectionTitle = "Raw Input"
            bodySectionContent = note.rawText ?? "*No raw input.*"
        case .url:
            bodySectionTitle = "Raw Input"
            let urlBlock = note.urls.map { "- <\($0.absoluteString)>" }.joined(separator: "\n")
            let take = note.rawText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            bodySectionContent = """
            **Sources:**
            \(urlBlock)

            **User's take:**
            \(take.isEmpty ? "*(no text — derived from articles only)*" : take)
            """
        }

        let durationLine = note.source == .voice ? "duration: \(note.formattedDuration)\n" : ""

        let markdown = """
        ---
        date: \(dateFormatter.string(from: note.recordedAt))
        \(durationLine)themes: [\(themesYAML)]
        emotional_tone: \(processed.emotionalTone)
        title: "\(processed.title)"
        \(extraFrontmatter)---

        # \(processed.title)

        ## Summary
        \(summaryBullets)

        ## Key Quotes
        \(keyQuotes.isEmpty ? "*No notable quotes extracted.*" : keyQuotes)

        ## Connections
        \(processed.connections.map { "- \($0)" }.joined(separator: "\n"))

        ## \(bodySectionTitle)
        \(bodySectionContent)
        """

        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Check how many raw note files exist
    func rawNoteCount() -> Int {
        let accessing = vaultURL.startAccessingSecurityScopedResource()
        defer { if accessing { vaultURL.stopAccessingSecurityScopedResource() } }

        let files = (try? FileManager.default.contentsOfDirectory(at: rawDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }.count
    }

    // MARK: - Private

    private static func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            // Re-save bookmark
            if let newData = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(newData, forKey: "obsidianVaultBookmark")
            }
        }
        return url
    }

    private func ensureDirectories() {
        let accessing = vaultURL.startAccessingSecurityScopedResource()
        defer { if accessing { vaultURL.stopAccessingSecurityScopedResource() } }

        let dirs = [
            rawDirectory,
            vaultURL.appendingPathComponent("wiki"),
            vaultURL.appendingPathComponent("wiki/themes"),
            vaultURL.appendingPathComponent("wiki/tensions"),
            vaultURL.appendingPathComponent("wiki/insights")
        ]
        for dir in dirs {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func ensureWikiScaffold() {
        let accessing = vaultURL.startAccessingSecurityScopedResource()
        defer { if accessing { vaultURL.stopAccessingSecurityScopedResource() } }

        let indexPath = vaultURL.appendingPathComponent("wiki/index.md")
        guard !FileManager.default.fileExists(atPath: indexPath.path) else { return }

        let today = todayString()
        let files: [(String, String)] = [
            ("wiki/index.md", "---\ntitle: Index\ntype: index\nlast_updated: \(today)\n---\n\n# Pensieve — Index\n\n## Themes\n*Theme pages are created automatically as you record voice notes.*\n\n## Tensions\n- [[contradictions]] — Shifts and contradictions in thinking over time\n\n## Timeline\n- [[timeline]] — Reverse-chronological record of all thoughts"),
            ("wiki/log.md", "---\ntitle: Ingestion Log\ntype: log\n---\n\n# Ingestion Log"),
            ("wiki/timeline.md", "---\ntitle: Timeline\ntype: timeline\nlast_updated: \(today)\n---\n\n# Timeline"),
            ("wiki/tensions/contradictions.md", "---\ntitle: Contradictions & Shifts\ntype: tension\nlast_updated: \(today)\nsource_count: 0\n---\n\n# Contradictions & Shifts\n\n*Tracks where your thinking has shifted, reversed, or gone circular.*")
        ]

        for (path, content) in files {
            let url = vaultURL.appendingPathComponent(path)
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
