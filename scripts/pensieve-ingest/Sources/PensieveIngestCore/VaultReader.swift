import Foundation

public struct VaultReader {
    public let vaultURL: URL

    public init(vaultURL: URL) {
        self.vaultURL = vaultURL
    }

    private var rawDir: URL { vaultURL.appendingPathComponent("raw") }
    private var wikiDir: URL { vaultURL.appendingPathComponent("wiki") }
    private var themesDir: URL { wikiDir.appendingPathComponent("themes") }
    private var logFile: URL { wikiDir.appendingPathComponent("log.md") }
    private var timelineFile: URL { wikiDir.appendingPathComponent("timeline.md") }
    private var contradictionsFile: URL { wikiDir.appendingPathComponent("tensions/contradictions.md") }
    private var indexFile: URL { wikiDir.appendingPathComponent("index.md") }
    private var mindmapFile: URL { wikiDir.appendingPathComponent("mindmap.json") }

    public func snapshot() throws -> VaultSnapshot {
        guard FileManager.default.fileExists(atPath: vaultURL.path) else {
            throw IngestError.vaultNotFound(vaultURL.path)
        }

        let logContent = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
        let unprocessed = try loadUnprocessedNotes(logContent: logContent)
        let themesNeeded = Set(unprocessed.flatMap { $0.themes })
        let existingThemes = try loadThemes(matching: themesNeeded)
        let contradictions = (try? String(contentsOf: contradictionsFile, encoding: .utf8)) ?? ""
        let timeline = (try? String(contentsOf: timelineFile, encoding: .utf8)) ?? ""
        let indexContent = (try? String(contentsOf: indexFile, encoding: .utf8)) ?? ""

        return VaultSnapshot(
            unprocessed: unprocessed,
            existingThemes: existingThemes,
            contradictions: contradictions,
            timelineTail: tail(timeline, lines: 40),
            logTail: tail(logContent, lines: 30),
            indexContent: indexContent
        )
    }

    private func loadUnprocessedNotes(logContent: String) throws -> [RawNote] {
        guard FileManager.default.fileExists(atPath: rawDir.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: rawDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var notes: [RawNote] = []
        for url in files {
            let id = url.deletingPathExtension().lastPathComponent
            if logContent.contains(id) { continue }
            let content = try String(contentsOf: url, encoding: .utf8)
            let (fm, body) = parseFrontmatter(content)
            let themes = parseThemes(fm["themes"] ?? "")
            notes.append(RawNote(id: id, path: url, frontmatter: fm, themes: themes, body: body))
        }
        return notes
    }

    private func loadThemes(matching names: Set<String>) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: themesDir.path) else { return [:] }
        var out: [String: String] = [:]
        let files = try FileManager.default.contentsOfDirectory(at: themesDir, includingPropertiesForKeys: nil)
        for url in files where url.pathExtension == "md" {
            let name = url.deletingPathExtension().lastPathComponent
            if names.contains(name) {
                out[name] = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            }
        }
        return out
    }

    public func allThemeNames() throws -> [String] {
        guard FileManager.default.fileExists(atPath: themesDir.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: themesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    private func parseFrontmatter(_ content: String) -> ([String: String], String) {
        guard content.hasPrefix("---\n") else { return ([:], content) }
        let rest = String(content.dropFirst(4))
        guard let end = rest.range(of: "\n---\n") else { return ([:], content) }
        let fmBlock = String(rest[..<end.lowerBound])
        let body = String(rest[end.upperBound...])
        var fm: [String: String] = [:]
        for line in fmBlock.split(separator: "\n") {
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                fm[key] = val
            }
        }
        return (fm, body)
    }

    private func parseThemes(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        return trimmed.split(separator: ",").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        }.filter { !$0.isEmpty }
    }

    private func tail(_ text: String, lines: Int) -> String {
        let arr = text.split(separator: "\n", omittingEmptySubsequences: false)
        return arr.suffix(lines).joined(separator: "\n")
    }

    public func loadMindmapState() throws -> MindmapState? {
        guard FileManager.default.fileExists(atPath: mindmapFile.path) else { return nil }
        let data = try Data(contentsOf: mindmapFile)
        return try JSONDecoder().decode(MindmapState.self, from: data)
    }

    public func themesDirectoryURL() -> URL { themesDir }
}
