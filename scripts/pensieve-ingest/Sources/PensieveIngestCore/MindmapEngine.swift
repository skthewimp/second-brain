import Foundation

public struct MindmapEngine {
    public let vaultURL: URL
    public let apiKey: String
    public let model: String

    public init(vaultURL: URL, apiKey: String, model: String = "claude-sonnet-4-6") {
        self.vaultURL = vaultURL; self.apiKey = apiKey; self.model = model
    }

    public func run() async throws -> MindmapStats {
        let reader = VaultReader(vaultURL: vaultURL)

        let prior = (try reader.loadMindmapState()) ?? MindmapState(
            version: 1,
            lastUpdated: todayString(),
            root: MindmapNode(id: "root", label: "Brain", noteCount: 0,
                              importance: 10, summary: "", sourcePages: [], children: [])
        )

        let allThemes = try reader.allThemeNames()
        let themePages = try loadAllThemePages(allThemes, reader: reader)
        let indexContent = (try? String(contentsOf: vaultURL.appendingPathComponent("wiki/index.md"),
                                         encoding: .utf8)) ?? ""

        let counts = try MindmapNoteCountAggregator.countsFromThemesDir(reader.themesDirectoryURL())

        let client = ClaudeClient(apiKey: apiKey, model: model)
        let system = MindmapPrompts.systemPrompt
        let user = MindmapPrompts.userPrompt(
            themePages: themePages, indexContent: indexContent,
            priorState: prior, noteCounts: counts
        )
        let response = try await client.complete(system: system, user: user, maxTokens: 8000)
        let patch = try decodePatch(response.text)

        var newState = try MindmapPatchApplier.apply(patch, to: prior)
        newState.lastUpdated = todayString()
        newState = stampNoteCounts(newState, counts: counts)

        let html = MindmapRenderer.render(state: newState, insights: patch.insights)
        try VaultWriter(vaultURL: vaultURL).writeMindmap(state: newState, html: html)

        let knownIds = collectIds(newState.root)

        return MindmapStats(
            nodesTotal: knownIds.count,
            opsApplied: patch.operations.count,
            insightsCount: patch.insights.count,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens
        )
    }

    private func loadAllThemePages(_ names: [String], reader: VaultReader) throws -> [String: String] {
        var out: [String: String] = [:]
        for name in names {
            let path = vaultURL.appendingPathComponent("wiki/themes/\(name).md")
            if let s = try? String(contentsOf: path, encoding: .utf8) { out[name] = s }
        }
        return out
    }

    private func collectIds(_ node: MindmapNode) -> [String] {
        [node.id] + node.children.flatMap(collectIds)
    }

    private func stampNoteCounts(_ state: MindmapState, counts: [String: Int]) -> MindmapState {
        func walk(_ n: MindmapNode) -> MindmapNode {
            var copy = n
            if let c = counts[n.id] { copy.noteCount = c }
            copy.children = copy.children.map(walk)
            return copy
        }
        return MindmapState(version: state.version, lastUpdated: state.lastUpdated, root: walk(state.root))
    }

    private func decodePatch(_ text: String) throws -> MindmapPatch {
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```") {
            let lines = json.split(separator: "\n", omittingEmptySubsequences: false)
            json = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        guard let data = json.data(using: .utf8) else {
            throw IngestError.decodeError("mindmap response not UTF-8")
        }
        do {
            return try JSONDecoder().decode(MindmapPatch.self, from: data)
        } catch {
            throw IngestError.decodeError("mindmap decode: \(error) -- raw:\n\(json.prefix(2000))")
        }
    }

    private func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
