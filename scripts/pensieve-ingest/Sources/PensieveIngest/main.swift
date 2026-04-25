import Foundation
import PensieveIngestCore

@main
struct Main {
    static func main() async {
        let defaultVault = ("~/Library/Mobile Documents/iCloud~md~obsidian/Documents/SecondBrain" as NSString)
            .expandingTildeInPath

        let args = CommandLine.arguments.dropFirst()
        var vaultPath = defaultVault
        var dryRun = false
        var rebuildMindmap = false
        var it = args.makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--vault": vaultPath = it.next() ?? vaultPath
            case "--dry-run": dryRun = true
            case "--rebuild-mindmap": rebuildMindmap = true
            case "--help", "-h":
                print("usage: pensieve-ingest [--vault PATH] [--dry-run] [--rebuild-mindmap]")
                print("  --rebuild-mindmap   skip wiki ingest, run only the mindmap pass")
                exit(0)
            default:
                FileHandle.standardError.write("unknown arg: \(arg)\n".data(using: .utf8)!)
                exit(2)
            }
        }

        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !apiKey.isEmpty else {
            FileHandle.standardError.write("error: ANTHROPIC_API_KEY not set\n".data(using: .utf8)!)
            exit(1)
        }

        let vaultURL = URL(fileURLWithPath: vaultPath)

        if rebuildMindmap {
            print("\(timestamp()): mindmap-only rebuild (vault: \(vaultPath))")
            let mm = MindmapEngine(vaultURL: vaultURL, apiKey: apiKey)
            do {
                let s = try await mm.run()
                print("\(timestamp()): mindmap done — \(s.opsApplied) ops, \(s.insightsCount) insights, tokens \(s.inputTokens)/\(s.outputTokens)")
                exit(0)
            } catch {
                FileHandle.standardError.write("error: \(error.localizedDescription)\n".data(using: .utf8)!)
                exit(1)
            }
        }

        let engine = IngestEngine(vaultURL: vaultURL, apiKey: apiKey, dryRun: dryRun)

        let startedAt = Date()
        print("\(timestamp()): starting ingestion (vault: \(vaultPath), dryRun: \(dryRun))")

        do {
            let stats = try await engine.run()
            let elapsed = Date().timeIntervalSince(startedAt)

            if stats.notesProcessed == 0 {
                print("\(timestamp()): no unprocessed notes")
                exit(0)
            }

            print("""
            \(timestamp()): done in \(String(format: "%.1f", elapsed))s
              notes processed:       \(stats.notesProcessed)
              themes updated:        \(stats.themesUpdated)
              themes created:        \(stats.themesCreated)
              contradictions flagged:\(stats.contradictionsFlagged)
              tokens in/out:         \(stats.inputTokens)/\(stats.outputTokens)
              cache read/write:      \(stats.cacheReadTokens)/\(stats.cacheWriteTokens)
              est. cost USD:         \(String(format: "%.4f", stats.estimatedCostUSD))
            """)
        } catch {
            FileHandle.standardError.write("error: \(error.localizedDescription)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
