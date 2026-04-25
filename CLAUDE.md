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

Requires Full Disk Access granted to `/Users/Karthik/.local/bin/pensieve-ingest` so launchd-spawned runs can access the iCloud vault. API key is set via `ANTHROPIC_API_KEY` in each launchd plist's `EnvironmentVariables`. **After every `cp` of a fresh release binary into `~/.local/bin/`, re-run `codesign --force --sign - ~/.local/bin/pensieve-ingest`** — launchd refuses to spawn unsigned binaries with `OS_REASON_CODESIGNING`.

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
- Team: `6APL9VM8C3`
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

### Known gotcha: Full Disk Access after macOS updates
`/Users/Karthik/.local/bin/pensieve-ingest` needs Full Disk Access so launchd-spawned runs can read the iCloud Obsidian vault. The binary is adhoc-signed, so macOS updates can invalidate the TCC grant while leaving the UI toggle visibly "on" — symptom is `error: The file "…md" couldn't be opened` in `/tmp/pensieve-ingest.log`. Fix: remove the entry with `–` in System Settings → Privacy & Security → Full Disk Access, re-add `/Users/Karthik/.local/bin/pensieve-ingest` (⌘⇧G to paste path), then test with `launchctl kickstart -k gui/$(id -u)/com.karthikshashidhar.pensieve.ingest`.

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

## GitHub
Repo: `github.com/skthewimp/pensieve`
