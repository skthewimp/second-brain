import Foundation

public struct VaultWriter {
    public let vaultURL: URL
    public init(vaultURL: URL) { self.vaultURL = vaultURL }

    private var wikiDir: URL { vaultURL.appendingPathComponent("wiki") }
    private var themesDir: URL { wikiDir.appendingPathComponent("themes") }
    private var logFile: URL { wikiDir.appendingPathComponent("log.md") }
    private var timelineFile: URL { wikiDir.appendingPathComponent("timeline.md") }
    private var contradictionsFile: URL { wikiDir.appendingPathComponent("tensions/contradictions.md") }
    private var indexFile: URL { wikiDir.appendingPathComponent("index.md") }
    private var mindmapJSONFile: URL { wikiDir.appendingPathComponent("mindmap.json") }
    private var mindmapHTMLFile: URL { wikiDir.appendingPathComponent("mindmap.html") }

    public func apply(patch: IngestionPatch, notes: [RawNote]) throws {
        try FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: contradictionsFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try appendLogEntries(patch.logEntries, notes: notes)
        try prependTimelineEntries(patch.timelineEntries)
        for update in patch.themeUpdates { try applyThemeUpdate(update) }
        for new in patch.newThemes { try writeNewTheme(new) }
        if let contradictions = patch.contradictions, !contradictions.isEmpty {
            try appendToContradictions(contradictions)
        }
        if let newIndex = patch.indexRewrite, !newIndex.isEmpty {
            try newIndex.write(to: indexFile, atomically: true, encoding: .utf8)
        }
    }

    public func writeMindmap(state: MindmapState, html: String) throws {
        try FileManager.default.createDirectory(at: wikiDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: mindmapJSONFile, options: .atomic)
        try html.write(to: mindmapHTMLFile, atomically: true, encoding: .utf8)
    }

    private func appendLogEntries(_ entries: [IngestionPatch.LogEntry], notes: [RawNote]) throws {
        guard !entries.isEmpty else { return }
        var existing = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
        if existing.isEmpty {
            existing = "---\ntitle: Ingestion Log\ntype: log\n---\n\n# Ingestion Log\n\n"
        }

        let byDate = Dictionary(grouping: entries) { entry -> String in
            String(entry.noteId.prefix(10))
        }

        for date in byDate.keys.sorted(by: >) {
            let items = byDate[date]!.sorted { $0.noteId > $1.noteId }
            let header = "## \(date)"
            var lines = items.map { "- **\($0.noteId)** — \($0.summary)" }.joined(separator: "\n")
            lines += "\n"

            if let headerRange = existing.range(of: header) {
                let insertAt = existing.index(after: headerRange.upperBound)
                existing.insert(contentsOf: "\n" + lines, at: insertAt)
            } else {
                let insertAt = existing.range(of: "# Ingestion Log\n")?.upperBound ?? existing.endIndex
                existing.insert(contentsOf: "\n\(header)\n\n\(lines)", at: insertAt)
            }
        }

        try existing.write(to: logFile, atomically: true, encoding: .utf8)
    }

    private func prependTimelineEntries(_ entries: [String]) throws {
        guard !entries.isEmpty else { return }
        var existing = (try? String(contentsOf: timelineFile, encoding: .utf8)) ?? ""
        if existing.isEmpty {
            existing = "---\ntitle: Timeline\ntype: timeline\n---\n\n# Timeline\n\n"
        }

        let sorted = entries.sorted(by: >)
        let insertion = sorted.joined(separator: "\n") + "\n"

        if let headerRange = existing.range(of: "# Timeline\n") {
            existing.insert(contentsOf: "\n" + insertion, at: headerRange.upperBound)
        } else {
            existing += "\n" + insertion
        }

        try existing.write(to: timelineFile, atomically: true, encoding: .utf8)
    }

    private func applyThemeUpdate(_ update: IngestionPatch.ThemeUpdate) throws {
        let file = themesDir.appendingPathComponent("\(update.theme).md")
        guard var content = try? String(contentsOf: file, encoding: .utf8) else { return }

        content = bumpFrontmatter(content, sourceCountDelta: update.sourceCountDelta)

        if let newState = update.currentState, !newState.isEmpty {
            content = replaceSection(content, heading: "## Current State", newBody: newState)
        }

        content = prependToSection(content, heading: "## Evolution", body: update.evolutionAppend)

        try content.write(to: file, atomically: true, encoding: .utf8)
    }

    private func writeNewTheme(_ new: IngestionPatch.NewTheme) throws {
        let file = themesDir.appendingPathComponent("\(new.name).md")
        try new.fullContent.write(to: file, atomically: true, encoding: .utf8)
    }

    private func appendToContradictions(_ items: [IngestionPatch.Contradiction]) throws {
        var existing = (try? String(contentsOf: contradictionsFile, encoding: .utf8)) ?? ""
        if existing.isEmpty {
            existing = "---\ntitle: Contradictions\ntype: tension\n---\n\n# Contradictions\n"
        }
        if !existing.hasSuffix("\n") { existing += "\n" }
        for item in items {
            existing += "\n" + Self.renderContradiction(item) + "\n"
        }
        try existing.write(to: contradictionsFile, atomically: true, encoding: .utf8)
    }

    static func renderContradiction(_ raw: IngestionPatch.Contradiction) -> String {
        var c = raw
        // Code-enforced invariant: `extracted` requires source note IDs on both sides.
        // If missing, downgrade to `inferred` so the trust signal stays honest.
        if c.kind == .extracted,
           (c.before.sourceNoteId?.isEmpty ?? true) || (c.now.sourceNoteId?.isEmpty ?? true) {
            c.kind = .inferred
        }

        func renderPos(_ label: String, _ p: IngestionPatch.Contradiction.Position) -> String {
            var line = "> **\(label)** (\(p.date)"
            if let id = p.sourceNoteId, !id.isEmpty {
                line += " from [[\(id)]]"
            }
            line += "): \"\(p.quote)\""
            return line
        }

        var lines: [String] = []
        lines.append("> [!\(c.kind.rawValue)] \(c.now.date) — \(c.topic)")
        lines.append(renderPos("Before", c.before))
        lines.append(renderPos("Now", c.now))
        if let nature = c.nature, !nature.isEmpty {
            lines.append("> **Nature**: \(nature)")
        }
        if let themes = c.relatedThemes, !themes.isEmpty {
            let links = themes.map { "[[\($0)]]" }.joined(separator: ", ")
            lines.append("> **Related**: \(links)")
        }
        return lines.joined(separator: "\n")
    }

    private func bumpFrontmatter(_ content: String, sourceCountDelta: Int) -> String {
        guard content.hasPrefix("---\n"),
              let end = content.range(of: "\n---\n", range: content.index(content.startIndex, offsetBy: 4)..<content.endIndex)
        else { return content }

        var fm = String(content[content.index(content.startIndex, offsetBy: 4)..<end.lowerBound])
        let today = Self.todayString()

        fm = fm.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let s = String(line)
            if s.hasPrefix("last_updated:") { return "last_updated: \(today)" }
            if s.hasPrefix("source_count:") {
                let current = Int(s.replacingOccurrences(of: "source_count:", with: "")
                    .trimmingCharacters(in: .whitespaces)) ?? 0
                return "source_count: \(current + sourceCountDelta)"
            }
            return s
        }.joined(separator: "\n")

        return "---\n\(fm)\n---\n" + content[end.upperBound...]
    }

    private func replaceSection(_ content: String, heading: String, newBody: String) -> String {
        guard let headingRange = content.range(of: heading) else { return content }
        let bodyStart = content.index(after: headingRange.upperBound)
        let nextHeadingRange = content.range(
            of: "\n## ", range: bodyStart..<content.endIndex
        )
        let bodyEnd = nextHeadingRange?.lowerBound ?? content.endIndex

        var result = String(content[..<headingRange.upperBound])
        result += "\n\n\(newBody.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        if bodyEnd < content.endIndex {
            result += content[bodyEnd...]
        }
        return result
    }

    private func prependToSection(_ content: String, heading: String, body: String) -> String {
        guard let headingRange = content.range(of: heading) else {
            return content + "\n\n" + heading + "\n\n" + body + "\n"
        }
        let insertAt = content.index(after: headingRange.upperBound)
        var result = String(content[..<insertAt])
        result += "\n" + body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
        if insertAt < content.endIndex {
            result += content[insertAt...]
        }
        return result
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: Date())
    }
}
