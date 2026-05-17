# Pensieve — Project Guide

Voice-driven personal wiki. Talk into your phone, a structured wiki builds itself.

## Architecture

```
Phone (iOS)                              Mac
┌─────────────────────┐                 ┌────────────────────────────┐
│ 1. Record voice     │                 │ Obsidian (browse wiki)     │
│ 2. WhisperKit       │   iCloud sync   │ wiki/mindmap.html in       │
│    (on-device)      │   via Obsidian  │   browser (D3 radial tree) │
│ 3. Claude API       │ ─────────────→  │                            │
│    (theme extract)  │                 │ Daily 10:17am launchd:     │
│ 4. Save .md to      │                 │   pensieve-ingest          │
│    Obsidian vault   │                 │   → wiki ingest +          │
│                     │                 │     mindmap (when new)     │
│                     │                 │                            │
│                     │                 │ Weekly Sunday 23:00:       │
│                     │                 │   pensieve-ingest          │
│                     │                 │     --rebuild-mindmap      │
└─────────────────────┘                 └────────────────────────────┘
```

### Phone pipeline
Record audio → WhisperKit transcribes on-device → Claude API (claude-sonnet-4-6) extracts title, themes, emotional tone, key quotes, connections → saves structured markdown to `raw/` in Obsidian vault.

### Mac wiki ingestion
`scripts/pensieve-ingest/` is a Swift Package. The `pensieve-ingest` binary (installed to `~/.local/bin/`) is driven by two launchd user agents:

- `~/Library/LaunchAgents/com.karthikshashidhar.pensieve.ingest.plist` — fires daily at **10:17am**. Default mode: wiki ingest of any new notes in `raw/` + (only when there were new notes) a mindmap pass that updates `wiki/mindmap.json` and `wiki/mindmap.html`. Quiet days cost nothing.
- `~/Library/LaunchAgents/com.karthikshashidhar.pensieve.mindmap.plist` — fires weekly **Sunday 23:00**. Runs `pensieve-ingest --rebuild-mindmap` (mindmap pass only, skips wiki ingest). Guarantees the mindmap reflects current prompt logic at least once a week even on quiet weeks.
- Manual: `pensieve-ingest --rebuild-mindmap` for ad-hoc rebuilds when iterating on the mindmap prompt or renderer.

Each ingest finds unprocessed notes in `raw/` (by diffing against `wiki/log.md`), makes a single direct Claude API call with the wiki state + new notes, and applies the returned JSON patch to theme pages, timeline, contradictions, log, and index. The mindmap pass is a separate Claude call that maintains a stateful tree (`wiki/mindmap.json`) via diff/patch ops and renders a self-contained `wiki/mindmap.html` (D3 v7 from CDN, data inlined). `PensieveIngestCore` (the library target) is platform-agnostic so it can be imported into the iOS app for phone-only ingestion later.

Binary lives inside `/Applications/PensieveIngest.app/Contents/MacOS/pensieve-ingest`. The .app wrapper exists so TCC keys on the stable bundle ID (`com.karthikshashidhar.pensieve-ingest`) rather than the binary's cdhash — Full Disk Access granted to the .app survives rebuilds and OS updates. App is signed with **Developer ID Application: Karthik Shashidhar Technologies LLP (DQ23J9RMB2)** + hardened runtime, so TCC keys on the signing identity itself (strictly stronger than the prior adhoc+bundle-ID interim). API key is set via `ANTHROPIC_API_KEY` in each launchd plist's `EnvironmentVariables`. **After every rebuild, `cp` the fresh release binary into `/Applications/PensieveIngest.app/Contents/MacOS/` and re-run `codesign --force --options runtime --sign "Developer ID Application: Karthik Shashidhar Technologies LLP (DQ23J9RMB2)" /Applications/PensieveIngest.app`** — launchd refuses to spawn unsigned binaries with `OS_REASON_CODESIGNING`.

### Obsidian vault location
`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/SecondBrain/`

Syncs automatically between phone and Mac via iCloud.

## Code Layout

```
iOS/
  SecondBrain/
    SecondBrainApp.swift          # App entry point
    Models/
      ThoughtNote.swift           # Note model with processing status
      ClaudeResponse.swift        # Claude API request/response types
    Services/
      ThoughtCaptureService.swift # Main orchestrator (record→transcribe→process→save)
      AudioRecorderService.swift  # AVAudioRecorder wrapper
      TranscriptionService.swift  # WhisperKit integration
      ClaudeProcessingService.swift # Claude API for theme extraction
      ObsidianStorageService.swift  # Vault linking, markdown file writing
    Views/
      ContentView.swift           # Main screen (nav title: "Pensieve")
      RecordingView.swift         # Start/stop recording UI
      NotesListView.swift         # List of captured notes
      NoteDetailView.swift        # Single note detail
      SettingsView.swift          # API key, vault picker, vault sync, stats
  project.yml                    # xcodegen spec
  SecondBrain.xcodeproj/         # Generated Xcode project

wiki/
  CLAUDE.md                      # Wiki maintenance schema (for Claude Code ingestion)
  raw/                           # Raw voice note markdowns (auto-populated)
  wiki/                          # LLM-maintained wiki pages
    index.md
    timeline.md
    log.md
    themes/                      # Topic pages (career, ai, consulting, etc.)
    tensions/
      contradictions.md          # The most important page
    insights/

scripts/
  pensieve-ingest/                 # Swift Package
    Package.swift
    Sources/
      PensieveIngest/              # CLI entry point (main.swift)
      PensieveIngestCore/          # Reusable library
        IngestEngine.swift         # Orchestrator
        ClaudeClient.swift         # Direct Anthropic API client
        VaultReader.swift          # Reads raw/ and wiki/ files
        VaultWriter.swift          # Applies IngestionPatch to the vault
        Prompts.swift              # System + user prompts
        Models.swift               # RawNote, IngestionPatch, etc.
```

## Key Technical Details

### Build & deploy
- Bundle ID: `com.karthikshashidhar.secondbrain`
- Team: `DQ23J9RMB2` (Karthik Shashidhar Technologies LLP — paid Apple Developer, profile valid ~1 year). Previously `6APL9VM8C3` (free personal team, 7-day profile expiry — switched 2026-05-17)
- Build: `xcodegen generate` then `xcodebuild -project SecondBrain.xcodeproj -scheme SecondBrain`
- Phone device ID may change; use `xcrun xctrace list devices` to find current ID
- `xcodebuild install` wipes app data including cached WhisperKit model

### SwiftUI nested ObservableObject pattern
SwiftUI does NOT observe `@Published` properties on nested `ObservableObject`s. `ThoughtCaptureService` holds `audioRecorder` and `storageService` as plain properties. Their published state must be forwarded via Combine:

```swift
storageService.$isVaultLinked
    .receive(on: DispatchQueue.main)
    .assign(to: &$isVaultLinked)
```

This has been the single most common bug in this project. If adding new observable state to a child service, it MUST be forwarded through `ThoughtCaptureService`.

### WhisperKit model persistence
The model (~150MB) downloads from HuggingFace on first launch and caches in `Documents/huggingface/models/`. The code checks for cached `.mlmodelc` files before downloading. Only re-downloads if cache is empty (e.g., after app reinstall).

### Obsidian vault linking
Uses iOS security-scoped bookmarks to persist folder access. User picks vault via `UIDocumentPickerViewController`, app saves bookmark to `UserDefaults`. On launch, restores bookmark and re-accesses the folder.

## Current State (April 2026)

- App is functional, installed on user's phone
- Wiki ingestion rewritten as a Swift binary (`pensieve-ingest`) that does a single direct Claude API call — ~33x cheaper than the old agentic Claude Code path (~$0.01/note vs ~$0.36/note on a measured 10-note run)
- User is in "collect data for a week" mode — do NOT add features unless asked

### Known gotcha: Full Disk Access
The vault lives in iCloud and macOS Sequoia tags those files with the restricted `com.apple.provenance` xattr, which forces TCC/FDA checks on read. The binary now lives inside `/Applications/PensieveIngest.app` so TCC keys on bundle ID (stable) rather than cdhash (changes every rebuild). Grant FDA **once** to `/Applications/PensieveIngest.app` in System Settings → Privacy & Security → Full Disk Access. Symptom of missing FDA: `error: The file "…md" couldn't be opened` in `/tmp/pensieve-ingest.log`. Verify with `launchctl kickstart -k gui/$(id -u)/com.karthikshashidhar.pensieve.ingest`. Note: `xattr -dr com.apple.provenance` does not work on Sequoia — the xattr is system-restricted; FDA is the only path.

### Deferred work (user explicitly deferred these)
1. **Retrieval/resurfacing** — daily digests, "you're going in circles" alerts, related past notes on new capture. Waiting for usage data.
2. **Phone-only wiki ingestion** — currently needs Mac. Path is now clear: `PensieveIngestCore` is platform-agnostic and can be imported into the iOS app as a local SPM dependency via `project.yml`. The nontrivial part is swapping `FileManager` direct paths for the iOS security-scoped bookmark code that already exists in `ObsidianStorageService.swift`.
3. **Prompt caching optimization** — current runs show `cache_read/write: 0/0` because the system prompt is under the 1024-token cache minimum. Padding the system prompt with concrete examples (or caching the user-message block containing the wiki state) would cut cost by another ~30-50%. Not urgent at current cost level.
4. **Contradiction provenance tagging** — every entry in `contradictions.md` should be tagged as `EXTRACTED` (literal verbatim clash between two dated quotes), `INFERRED` (Claude's reading that two positions are in tension), or `AMBIGUOUS` (possibly contradictory, interpretation-dependent). Idea stolen from [safishamsi/graphify](https://github.com/safishamsi/graphify), which uses the same tagging for graph edges. Rationale: the contradictions page is the most valuable page in the wiki, and a hallucinated contradiction is much worse than a missed one — this tag lets the reader trust the mirror. Implementation is small: add a `kind: "extracted" | "inferred" | "ambiguous"` field to the contradictions schema in `IngestionPatch`, update the system prompt in `Prompts.swift` to require verbatim citations with source note IDs for `extracted` entries, and have the writer render the tag as a callout (`> [!extracted]` / `> [!inferred]` / `> [!ambiguous]`) at the top of each contradiction block. ~20 lines of Swift + a prompt tweak. Defer until after the data-collection week.
5. **Action item routing** — extract tasks from notes, push to external systems.
6. **Blog post revision** — first draft written, may revise after more usage.
7. **"Challenge" prompt at ingestion** — at ingestion time, actively surface past statements that conflict with the new note (not just passive contradiction logging after the fact). Inspired by [eugeniughelbur/obsidian-second-brain](https://github.com/eugeniughelbur/obsidian-second-brain)'s `/obsidian-challenge` tool. Implementation: add a step in `Prompts.swift` system prompt that asks Claude to check the new note against existing Evolution entries and flag live tensions. Sharper mirror than waiting for contradictions to accumulate passively.
8. **Periodic lint/health pass** — a `pensieve-ingest --lint` mode that scans the wiki for: orphan pages with no inbound links, concepts mentioned across multiple themes but lacking their own page, stale claims superseded by newer notes, missing cross-references. Outputs a health report. Inspired by both [garrytan/gbrain](https://github.com/garrytan/gbrain) (maintenance skills) and [eugeniughelbur/obsidian-second-brain](https://github.com/eugeniughelbur/obsidian-second-brain) (nightly reconciliation agent). Not needed until note volume hits ~50+.
9. **Entity pages** — dedicated pages for recurring people/companies (e.g., Barry, Manu, Pinkie) that accumulate a compiled summary + reverse-chron timeline of every mention. Currently people are folded into theme pages which works at low volume but won't scale. Inspired by [garrytan/gbrain](https://github.com/garrytan/gbrain)'s `people/` directory with per-entity dossiers.
10. **Bi-temporal fact tracking** — record both *when something was true* and *when the vault learned it*. Adds an audit trail of belief evolution. Pairs with contradiction provenance (item 4). Inspired by [eugeniughelbur/obsidian-second-brain](https://github.com/eugeniughelbur/obsidian-second-brain).
11. **MCP server exposing the wiki** — let Claude Desktop / Claude Code / Cursor query Pensieve from anywhere. Lookup tools: `search_notes` (lexical or semantic), `get_theme(slug)`, `get_contradictions`, `recent_notes(n)`, `notes_by_theme(slug, range)`. Inspired by [flepied/second-brain-agent](https://github.com/flepied/second-brain-agent) and [vasylenko/bear-notes-mcp](https://github.com/vasylenko/bear-notes-mcp). Implementation: small Node or Swift MCP server reading the same Obsidian vault path; no schema changes needed. Highest leverage-per-LOC of the deferred items because it unlocks "what did past-me think about X?" from any agent surface without writing new UI. Skip semantic search v1; lexical + frontmatter filters get most of the value.
12. **Git auto-commit of the vault** — turn the Obsidian vault into a versioned audit trail. After every successful `pensieve-ingest` run, `git add -A && git commit -m "ingest YYYY-MM-DD: N notes, themes touched: X, Y"` from inside the vault. Pairs with item 10 (bi-temporal): the commit log *is* the "when the vault learned it" axis for free. Inspired by [agenticnotetaking/arscontexta](https://github.com/agenticnotetaking/arscontexta) (auto-commit hook) and [huytieu/COG-second-brain](https://github.com/huytieu/COG-second-brain) (Git as the persistence layer). Implementation: ~10 lines at the end of `IngestEngine.swift`. Caveat: vault lives in iCloud Obsidian sync path — confirm `git` plays nicely with iCloud's file-replacement behaviour before turning this on by default.
13. **Weekly "what shifted" diff pass** — repurpose the existing Sunday 23:00 launchd slot to run an extra Claude pass that diffs this week's theme/contradiction state vs last week's, and writes a `wiki/weekly/YYYY-Www.md` page. Different from the daily ingest (which is per-note) and the mindmap rebuild (which is structural). Closer to COG's `weekly-checkin` skill (cross-domain pattern analysis). Useful for spotting drift the per-note ingest can't see — "you started talking about X three weeks ago and it's now in 4 themes". Pre-req: item 12 (git auto-commit) makes the "vs last week" diff trivial — just `git diff` the wiki tree at the previous Sunday tag.

## GitHub
Repo: `github.com/skthewimp/pensieve`
