import Foundation

public struct IngestEngine {
    public let vaultURL: URL
    public let apiKey: String
    public let model: String
    public let dryRun: Bool

    public init(vaultURL: URL, apiKey: String, model: String = "claude-sonnet-4-6", dryRun: Bool = false) {
        self.vaultURL = vaultURL
        self.apiKey = apiKey
        self.model = model
        self.dryRun = dryRun
    }

    public func run() async throws -> IngestionStats {
        let reader = VaultReader(vaultURL: vaultURL)
        let snapshot = try reader.snapshot()

        guard !snapshot.unprocessed.isEmpty else {
            return IngestionStats(
                notesProcessed: 0, themesUpdated: 0, themesCreated: 0,
                contradictionsFlagged: 0, inputTokens: 0, outputTokens: 0,
                cacheReadTokens: 0, cacheWriteTokens: 0
            )
        }

        let allThemes = try reader.allThemeNames()
        let client = ClaudeClient(apiKey: apiKey, model: model)
        let system = Prompts.systemPrompt
        let user = Prompts.userPrompt(snapshot: snapshot, allThemeNames: allThemes)
        let response = try await client.complete(system: system, user: user)
        let patch = try decodePatch(response.text)

        if !dryRun {
            let writer = VaultWriter(vaultURL: vaultURL)
            try writer.apply(patch: patch, notes: snapshot.unprocessed)
        }

        // ---- non-fatal mindmap pass; only fires when there were new notes,
        // since wiki state actually changed. Forced standalone refresh is
        // available via the `--rebuild-mindmap` CLI flag (driven by a
        // separate weekly launchd entry).
        if !dryRun {
            do {
                let mm = MindmapEngine(vaultURL: vaultURL, apiKey: apiKey, model: model)
                let mmStats = try await mm.run()
                FileHandle.standardError.write(Data("mindmap: \(mmStats.opsApplied) ops, \(mmStats.insightsCount) insights\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("mindmap: skipped — \(error.localizedDescription)\n".utf8))
            }
        }

        return IngestionStats(
            notesProcessed: snapshot.unprocessed.count,
            themesUpdated: patch.themeUpdates.count,
            themesCreated: patch.newThemes.count,
            contradictionsFlagged: (patch.contradictionsAppend?.isEmpty == false) ? 1 : 0,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens,
            cacheReadTokens: response.cacheReadTokens,
            cacheWriteTokens: response.cacheWriteTokens
        )
    }

    private func decodePatch(_ text: String) throws -> IngestionPatch {
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```") {
            let lines = json.split(separator: "\n", omittingEmptySubsequences: false)
            json = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        guard let data = json.data(using: .utf8) else {
            throw IngestError.decodeError("could not encode response as UTF-8")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(IngestionPatch.self, from: data)
        } catch {
            throw IngestError.decodeError("\(error) -- raw output:\n\(json.prefix(2000))")
        }
    }
}
