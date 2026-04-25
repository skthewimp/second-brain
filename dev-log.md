# Pensieve - Dev Log

## Project Genesis

**Date:** 2026-04-07 to 2026-04-09
**Built with:** Claude Code (Claude Opus 4.6)

---

## Context

Karthik shared a link to Andrej Karpathy's viral "LLM Wiki" gist - a pattern for building personal knowledge bases where an LLM incrementally builds and maintains a structured wiki from raw sources, rather than doing RAG-style retrieval from scratch every time.

The conversation evolved from "how do I use this?" into designing a personal system. The key constraint: Karthik's therapist recommended externalising his thinking but didn't say how to implement it. The problem wasn't just note-taking - it was tracking how his thinking evolves over time (especially around career decisions) and spotting when he's going in circles.

## Prompts and Decisions

### Session 1 (2026-04-07)

**Prompt:** "this seems to have gone viral. how can i use it? [karpathy gist link]"

Fetched the gist, summarized the LLM Wiki pattern, asked what domain to apply it to.

**Prompt:** "Okay, do I know what to use this for?"

Checked memory - knew about writing voice, data science background, Babbage Insight. Suggested a research/writing wiki since his writing is built on cross-domain connections.

**Prompt:** [Long voice-transcribed message about thought management, therapist's recommendation, needing zero-friction input, existing voice notes app]

This was the key design moment. Three critical constraints emerged:
1. Input must be dead simple (just talk)
2. The system must organize itself (no manual categorization)
3. Need to track thought evolution and circular patterns

Found the existing NotesAgent app at `/Users/Karthik/Documents/work/NotesAgent/`. Read through the full codebase - iOS app records audio, syncs to Mac via TCP, Mac runs Whisper + Ollama, saves to Apple Notes.

**Decision: Redesign the architecture.** The TCP sync was fragile (Mac had to be running). New approach: do everything on the phone.
- WhisperKit for on-device transcription (no network needed)
- Claude API instead of Ollama (better at nuanced theme extraction, and user is fine paying for API)
- Save markdown to Obsidian vault instead of Apple Notes
- Eliminate Mac server entirely

**Prompt:** "I don't know how much space I have on my iCloud drive and stuff"

Addressed the iCloud concern - markdown files are ~3KB each, even years of heavy use would be under 100MB. Obsidian on iOS syncs vaults via iCloud for free (not Obsidian Sync, which is paid).

**Prompt:** "can you create a folder for this, start coding, write the documentation..."

Built the entire project structure in one session:
- 11 Swift source files (models, services, views)
- Wiki scaffold (CLAUDE.md schema, index, timeline, contradictions page)
- Implementation plan
- Karpathy gist saved as reference
- README with architecture diagram

Key architectural decisions:
- `ThoughtCaptureService` orchestrates the pipeline: record → transcribe → Claude API → save markdown
- `ClaudeProcessingService` returns structured JSON: title, summary, themes, emotional tone, key quotes, connections
- `ObsidianStorageService` writes markdown with YAML frontmatter to the vault's raw directory
- Wiki CLAUDE.md schema includes rules like "never judge", "flag patterns don't prescribe", "the contradictions page is the most valuable page"

### Session 2 (2026-04-09)

**Prompt:** "ok let's set this up today"

Started with Xcode project generation. Had `xcodegen` available, so generated the project from a `project.yml` spec.

**Build issues encountered (and resolved):**
1. Bundle ID `com.secondbrain.app` was taken on Apple's servers → changed to `com.karthikshashidhar.secondbrain`
2. iOS 26.4 platform wasn't properly installed in Xcode → ran `xcodebuild -downloadPlatform iOS` (8.46 GB download)
3. Transitive SPM dependency issue (OrderedCollections not resolving for swift-jinja) → added swift-collections as explicit dependency
4. Precompiled module errors with yyjson → resolved after iOS platform install enabled scheme-based builds

**Build succeeded** after platform install. Deployed to phone.

**Prompt:** "it says 'no audio context was detected'"

First recording attempt failed. Likely tapped too quickly - needed to hold long enough for actual audio.

**Prompt:** "can you provide clean buttons both for start/stop and hold to record?"

Redesigned RecordingView with two recording modes:
1. Hold-to-record (press and hold mic button, release to stop)
2. Tap start/stop (explicit start button, then red stop button appears)

**Bug fix:** `isConfigured` property wasn't `@Published`, so the UI didn't update when the API key was saved. Settings showed "Configured" but the main screen button stayed gray. Fixed by making it a `@Published` stored property.

**Layout fix:** Notes list was overlapping the recording buttons because RecordingView had a `maxHeight: 280` constraint that was too small for the new two-button layout. Changed to `fixedSize(horizontal: false, vertical: true)` so the recording area takes the space it needs.

## Technical Notes

### Why WhisperKit over Apple Speech Framework
WhisperKit runs OpenAI's Whisper models on the iPhone's Neural Engine. Better accuracy than Apple's built-in speech recognition, especially for stream-of-consciousness speech with mixed vocabulary. Runs fully on-device - no network needed for transcription.

### Why Claude API over local Ollama
The original NotesAgent used Ollama (qwen2.5:7b-instruct) for summarization. For Pensieve, we need more nuanced processing - theme extraction, emotional tone detection, identifying connections to other topics. Claude is significantly better at this kind of structured analysis. Also eliminates the Mac dependency since Ollama only ran on the Mac server.

### Wiki Schema Design (CLAUDE.md)
The CLAUDE.md is the most important file in the project. It tells Claude Code how to maintain the wiki. Key design choices:
- Theme pages are chronological within - each entry is dated, showing evolution
- `> [!shift]` and `> [!contradiction]` callouts for when thinking changes
- Contradictions page is explicitly called out as "the most valuable page"
- Rule: "Never judge. This is a safe space."
- Rule: "Flag patterns, don't prescribe."
- Wikilinks (`[[page]]`) for Obsidian graph view compatibility

### Obsidian Sync Strategy
Three options documented in the plan:
1. iCloud via Obsidian (simplest - Obsidian on iOS stores vaults in iCloud by default)
2. Manual file transfer via Finder
3. Dedicated iCloud container

Went with option 1 as the recommended approach. Storage is negligible (~3KB per note).

### Session 2 continued (2026-04-09 afternoon)

**Prompt:** "on the app i selected the secondbrain folder. but now it still says 'not linked'"

Two bugs in the Obsidian vault linking:

1. `startAccessingSecurityScopedResource()` was behind a strict `guard` that caused `linkVault()` to silently fail. Fixed by just tracking whether access was granted without bailing on `false`.

2. **Same nested ObservableObject bug as recording.** `storageService.isVaultLinked` is `@Published` on `ObsidianStorageService`, but since `storageService` is a plain property on `ThoughtCaptureService`, SwiftUI never sees the change. Fixed the same way as before - forwarded `isVaultLinked` and `vaultURL` through `ThoughtCaptureService` via Combine's `assign(to:)`. Updated `SettingsView` to read from the forwarded properties. This is the third time this pattern has come up (isRecording, recordingDuration, isVaultLinked) - it's the single most common SwiftUI gotcha in this project.

**Prompt:** "ok but we need to configure obsidian on both right?"

Set up Obsidian on the phone first. User created an iCloud vault called "SecondBrain" in Obsidian. The app's folder picker was pointed to this vault. Confirmed iCloud sync was working - the vault appeared on the Mac at `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/SecondBrain/`.

**Prompt:** "as a one time exercise can you make sure all older notes are also pushed into obsidian?"

Added `resaveAllToVault()` method to `ThoughtCaptureService` - iterates over all notes with transcriptions that haven't been saved to wiki, re-processes each through Claude API to get the full structured output (title, keyQuotes, connections), and saves to the vault. Added a "Vault Sync" section in Settings with a button to trigger this.

**Prompt:** "when does the wiki get populated?"

The raw notes were being saved but the wiki pages (themes, timeline, contradictions) weren't being maintained. Built `scripts/ingest.sh` - a shell script that:
1. Checks `raw/` for notes not listed in `wiki/log.md`
2. If unprocessed notes exist, runs Claude Code (`claude -p --dangerously-skip-permissions --model sonnet`) with the CLAUDE.md instructions to ingest them
3. Lock file prevents concurrent runs

Copied `wiki/CLAUDE.md` into the Obsidian vault so Claude Code can read it when running from there.

**Test ingestion:** Ran manually against the first raw note (`2026-04-09_1154` - the AI/algorithmic thinking note). Claude Code created 6 theme pages (ai, consulting, career, business, productivity, systems), updated timeline, index, and log. Noted the themes were tightly clustered around a single idea - exactly the kind of pattern the system should surface.

**Automation:** Set up cron job to run daily at 10:17am. User explicitly declined file-watcher approach ("no overkill. daily is good enough"). Also declined Gemini's suggestion to add action item routing to CRM ("We will do it later. Let's collect data for a week").

**Personal knowledge management research:** Researched second brain systems and common failure modes. Key finding: the system has strong capture and organization but is missing automated resurfacing (daily digests, "you're going in circles" alerts, related past notes when new ones come in). User wisely decided to wait a week of actual usage before adding retrieval features.

### Nested ObservableObject Pattern (recurring lesson)

SwiftUI does not observe `@Published` properties on nested `ObservableObject`s. If `ServiceA` holds `ServiceB` (which is an `ObservableObject`), changes to `ServiceB.someProperty` won't trigger SwiftUI view updates even if `someProperty` is `@Published`.

**Fix:** Forward the property through the parent using Combine:
```swift
serviceB.$someProperty
    .receive(on: DispatchQueue.main)
    .assign(to: &$someProperty)
```

This came up three times in this project. If I add more observable state to child services, I need to forward it.

### Session 4 (2026-04-10) — Scheduler fix and Swift ingestion rewrite

**Prompt:** "did the daily script run?"

It had not. `cron` fired at 10:17 as scheduled but the script bailed with `Operation not permitted`. Root cause: macOS TCC protects `~/Documents/`, and the `cron` daemon has no Full Disk Access, so it could not even execute `scripts/ingest.sh`.

Switched from cron to a launchd user agent (`~/Library/LaunchAgents/com.karthikshashidhar.pensieve.ingest.plist`). Same error. Turned out the script file itself lived under `~/Documents/`, which also requires FDA for any interpreter to read. Moved a copy of the script to `~/.local/bin/pensieve-ingest.sh` and pointed launchd there. Got past the script-read error but then the script itself failed to enumerate `~/Library/Mobile Documents/iCloud~md~obsidian/.../raw/` — iCloud Drive is a separately TCC-protected location and launchd-spawned bash has no grant.

**Prompt:** "is the wiki prepared with the existing notes or not?"

Checked `wiki/log.md` vs `raw/`. Only 1 of 10 notes had been ingested (`2026-04-09_1154`, from the manual test on session 3). The other 9 had been sitting unprocessed. Since the current shell (launched from Terminal.app, which has FDA) could still read the vault, ran the existing `ingest.sh` manually from the session to catch up the backlog. Claude Code agentically ingested 9 notes, created 4 new theme pages (relationships, mental-health, self-awareness, job-search), updated 4 existing, and flagged 2 contradictions.

**Prompt:** "how much will it cost? estimate based on today's run. assume there will be ~25 notes a day"

Parsed the Claude Code session log at `~/.claude/projects/-Users-Karthik-Library-Mobile-Documents-iCloud-md-obsidian-Documents-SecondBrain/*.jsonl` to get actual token counts. Today's 9-note agentic run: 91K output tokens, 1.38M cache_read, 390K cache_write, 83 input — **$3.25 total, ~$0.36/note**. Extrapolated to 25 notes/day: **~$150-210/month, rising as the wiki grows**.

**Prompt:** "no way too expensive"

Diagnosed the cost: the agentic loop (Claude Code making Read/Edit/Write tool calls) round-trips the full wiki state on every tool call, which balloons cache-write and output tokens. A direct API call that takes the raw notes + current wiki state as input and returns a structured JSON patch in one shot should be 10-20x cheaper.

Recommended: rewrite as a direct API call. User picked the single-stage approach and asked for it in Swift so it can later be dropped into the iOS app.

**Implementation** — Swift Package at `scripts/pensieve-ingest/`:

```
scripts/pensieve-ingest/
  Package.swift                     # SPM manifest, macOS 13+
  Sources/
    PensieveIngest/main.swift       # CLI entry point
    PensieveIngestCore/
      IngestEngine.swift            # Orchestrates read -> API -> write
      ClaudeClient.swift            # Direct Anthropic API client
      VaultReader.swift             # Reads raw/ + selected wiki files
      VaultWriter.swift             # Applies IngestionPatch
      Prompts.swift                 # System prompt + user prompt builder
      Models.swift                  # RawNote, IngestionPatch, stats
```

Key design choice: `PensieveIngestCore` is a separate library target with zero platform-specific deps so it can be imported into the iOS app unchanged later. The CLI target is a thin wrapper that parses args, reads `ANTHROPIC_API_KEY` from the environment, and calls into the core.

**IngestionPatch schema** — hybrid: prepend for theme Evolution sections, append for log/timeline/contradictions, full rewrite for index:

```json
{
  "logEntries": [{"noteId": "...", "summary": "..."}],
  "timelineEntries": ["- **2026-04-10 13:17** — ..."],
  "themeUpdates": [
    {"theme": "career", "currentState": "...", "evolutionAppend": "### 2026-04-10...", "sourceCountDelta": 1}
  ],
  "newThemes": [{"name": "decision-making", "fullContent": "---\ntitle: ..."}],
  "contradictionsAppend": "\n## 2026-04-10 Control vs. flow\n...",
  "indexRewrite": null
}
```

**Gotchas encountered:**

1. **URLSession silently drops headers with trailing whitespace.** The `.env` file's `ANTHROPIC_API_KEY` value had a trailing newline that the shell extraction preserved. `req.addValue("sk-ant-...\n", forHTTPHeaderField: "x-api-key")` succeeds without error but the header never leaves the client, because HTTP header values cannot contain newlines. Anthropic responds with `"x-api-key header is required"` as if the header wasn't set at all. Debugging was hard because `req.allHTTPHeaderFields` showed the header missing entirely — URLSession had silently stripped it. Fix: `.trimmingCharacters(in: .whitespacesAndNewlines)` in the `ClaudeClient` initializer, defensive against any source of the key.

2. **Default URLSession timeout is 60s.** A 10-note Sonnet call takes ~90s. Bumped `timeoutIntervalForRequest` to 600 and `timeoutIntervalForResource` to 900 on a custom `URLSessionConfiguration.ephemeral`.

3. **VaultWriter initial bug: appending new Evolution entries at the bottom of the section instead of the top.** The convention (set by previous agentic runs) is reverse-chronological — newest at top. Initial implementation found the next `## ` heading and inserted just before it. Fixed by prepending right after `## Evolution`. Caught during verification by reading `career.md` after a test run and noticing the new 2026-04-10 entry was below the older 2026-04-09 entries.

**Verification** — ran the new tool against the live vault twice before deploying:

1. **Dry run** (`--dry-run` flag) — temporarily reverted `log.md` to pre-ingest state so all 10 notes looked unprocessed, ran the tool, inspected patch output and cost. Result: **$0.11 for 10 notes, 93s**, vs. the agentic $3.25 for 9 notes. Restored `log.md` from backup.

2. **Real run** on one actual new note (`2026-04-10_1317`, which the user had recorded on their phone during the session and synced via iCloud). Backed up the entire `wiki/` folder to `/tmp/wiki-backup` first. Processed the note in 31s for $0.0385. Verified `career.md` got the new entry at the top of Evolution (confirming the prepend fix), `decision-making.md` was created as a new theme page, `contradictions.md` got a new "Control vs. flow" block appended, `timeline.md` got the new entry, `log.md` got the new entry under `## 2026-04-10`, and `source_count`/`last_updated` on `career.md` frontmatter correctly bumped.

**Cost summary:**

| | Agentic (Claude Code) | Direct API (Swift) |
|---|---|---|
| Per-note cost | $0.36 | $0.011 |
| 25 notes/day | $150-210/mo | ~$7.50/mo |
| Ratio | — | ~33x cheaper |

**Deployment:**
- `swift build -c release` then copied the binary to `~/.local/bin/pensieve-ingest` (outside `~/Documents/` for TCC reasons)
- Updated launchd plist to call the Swift binary directly, with `ANTHROPIC_API_KEY` in `EnvironmentVariables` (plist chmod 600). Key read from the job-crm project's `.env` file.
- Deleted `scripts/ingest.sh` and `~/.local/bin/pensieve-ingest.sh`

**One pending manual action:** user needs to grant Full Disk Access to `/Users/Karthik/.local/bin/pensieve-ingest` in System Settings → Privacy & Security → Full Disk Access. This CANNOT be automated — macOS TCC requires GUI consent. Until granted, tomorrow's 10:17 launchd run will fail the same way cron did.

**Notes for future sessions:**
- **Prompt caching isn't firing** (`cache_read/write: 0/0` on both runs). System prompt is probably under the 1024-token minimum. Easy optimization: pad with concrete examples or cache the user-message block containing the wiki state. Current cost is low enough that this isn't urgent.
- **iOS port path is clear.** Import `PensieveIngestCore` as a local SPM dependency in `project.yml`. The only nontrivial piece is swapping direct `FileManager` paths for the security-scoped bookmark code already in `ObsidianStorageService.swift`. This would eliminate the Mac dependency entirely and remove the TCC/FDA problem.
- **The `.env` at `~/Documents/work/vibes/job-crm/.env` is where this project's `ANTHROPIC_API_KEY` lives.** There is no keychain entry for it.

## Session 5 — Mindmap visualization (2026-04-25)

**Built with:** Claude Code (Opus 4.7) + subagent-driven development

**Goal:** A radial, interactive HTML mind-map of the voice-note corpus (`wiki/mindmap.html`), regenerated each ingest. Brain at center, themes radiating out, sub-themes cascading recursively. Surfaces depth/breadth mismatches as sidebar insights — "going too deep on minor theme", "should go deeper on important theme", etc.

### Key prompts

> "Look at this picture... around the brain maybe there are 5 broad themes. Then for some of those themes there might be some more narrower themes... I want to produce this kind of a visualization which could be interactive and things like that, so that we can zoom in and out wherever we want."

> "should we have just one Claude call or multiple? I mean, I don't want to overload too much into one call... because there could be some context rot and stuff."

That second push-back was the design's biggest fork. Initial proposal was a single Claude call emitting wiki ingest + mindmap patch together. Splitting into two sequential calls (ingest first, mindmap second using the freshly-rewritten theme pages) was the right call: smaller per-call payloads, isolated failure blast radius, and the mindmap pass benefits from seeing today's wiki state.

### Architecture

```
pensieve-ingest (daily, launchd)
  ├─ Call 1: existing ingest pass → applies IngestionPatch (untouched)
  ├─ Call 2: NEW mindmap pass
  │    in:  fresh wiki/themes/*.md + wiki/index.md + prior wiki/mindmap.json
  │    out: MindmapPatch + insights
  ├─ apply patch → wiki/mindmap.json
  └─ MindmapRenderer → wiki/mindmap.html (D3 from CDN, data inlined)
```

Mindmap-pass failure is non-fatal — wiki ingest already succeeded; the engine logs `mindmap: skipped — <error>` to `/tmp/pensieve-ingest.log` and exits 0.

### Decisions

- **Standalone web page**, not Obsidian plugin or iOS native. Lowest friction; iOS port deferred to a later phase.
- **Stateful tree, daily diff.** `wiki/mindmap.json` persists across runs; LLM emits a `MindmapPatch` of `add` / `update` / `move` / `merge` / `remove` ops. Stable IDs (dot-path slugs like `career.consulting.pricing`) → no layout jitter day-to-day, and growth deltas can be surfaced later.
- **`noteCount` is computed deterministically by Swift**, not by the LLM. Source of truth: `source_count:` in each theme page's YAML frontmatter (which `VaultWriter.bumpFrontmatter` already maintains every ingest). The LLM is forbidden from emitting or mutating `noteCount` — eliminates a class of arithmetic errors. Sub-theme nodes deeper than the theme level carry `0` in v1 since no deterministic source exists below the theme level.
- **Radial collapsible D3 layout**, matching the user's hand sketch. Brain at center, themes on first ring, sub-themes outer. Color = importance/noteCount mismatch (blue = under-explored important, red = over-explored minor, gray = balanced). Click node → opens the theme page via `obsidian://open?vault=SecondBrain&file=...`.
- **Insights panel.** LLM emits up to 5 per run (`tooDeep` / `shouldGoDeeper` / `tooShallow` / `tooBroad`). Click an insight → zooms + centers the corresponding node.
- **Single self-contained HTML.** D3 v7 from CDN, data inlined as `<script>const data = {...}</script>`. Project ethos is single-binary simplicity, no Node, no build chain. Renderer is ~80 lines of Swift string-templating.

### Implementation breakdown (12 tasks, executed via subagent-driven flow)

| Task | What | Tests |
|------|------|-------|
| 1 | XCTest target on the SPM package | smoke |
| 2 | `MindmapState` / `MindmapNode` / `MindmapPatch` / `NodeOp` (5 cases) / `Insight` / `MindmapStats` | 7 (round-trip + 5 NodeOp variant decodes + Insight) |
| 3 | `MindmapPatchApplier` (pure, recursive) | 6 (one per op + unknown-id) |
| 4 | `MindmapNoteCountAggregator` reading `source_count:` from theme frontmatter | 3 |
| 5 | `VaultReader.loadMindmapState()` + `themesDirectoryURL()` | 2 |
| 6 | `VaultWriter.writeMindmap(state:html:)` | 1 |
| 7 | `MindmapPrompts` (system prompt + user-prompt builder) | — |
| 8 | `MindmapRenderer` (Swift → HTML with D3) | 1 |
| 9 | `MindmapEngine` (orchestrates load → count → prompt → call → decode → patch → stamp → render → write) | (covered end-to-end) |
| 10 | Wire into `IngestEngine.run()` as a non-fatal post-step | regression check |
| 11 | End-to-end smoke against the live vault | 21 unit + 1 live |
| 12 | This dev-log entry | — |

### Problems hit

1. **Codesigning invalidated by binary overwrite.** First smoke run hit `OS_REASON_CODESIGNING` on launchd kickstart — `state = not running, last exit reason = OS_REASON_CODESIGNING`. The newly-built release binary lacked a signature, and macOS refused to launch it. Fix: `codesign --force --sign - /Users/Karthik/.local/bin/pensieve-ingest` (adhoc-sign), then re-kickstart. This is the same gotcha already documented in `CLAUDE.md` for FDA invalidation after macOS updates — applies equally any time the binary is replaced.

2. **`Bundle.module` resource lookup vs. `#file` paths.** First pass at the note-count-aggregator test loaded fixtures via `URL(fileURLWithPath: #file)`, bypassing SwiftPM's intended resource bundling. Worked locally but defeated the `resources: [.process("Fixtures")]` directive. Pushed a fix: switch to `resources: [.copy("Fixtures")]` (preserves directory structure verbatim) + `Bundle.module.url(forResource:withExtension:subdirectory: "Fixtures/sample-themes")`. With `.copy`, the bundle path includes the top-level `Fixtures/` prefix.

3. **NodeOp Codable shape.** Swift's synthesized `Codable` for enums-with-associated-values produces JSON like `{"add": {"parentId": "...", "node": {...}}}` — the case name becomes the discriminator key. Plan-level reviewer caught the risk early; we locked the wire format with one decode test per variant (5 tests) before any code touched the LLM. Caught zero issues at smoke time.

4. **Mindmap call failure must NOT block wiki ingest.** Implemented as a dedicated `do { try await mm.run() } catch { stderr <- "skipped — \(error)" }` block after the existing wiki ingest. The wiki is the canonical artifact; the mindmap is a downstream view.

### First live run (2026-04-25 21:21:42)

- 17 notes processed, 12 themes updated, 1 created, 1 contradiction flagged
- `mindmap: 29 ops, 5 insights` — the new code path fired
- Total runtime: 373.9s (call 1 + call 2)
- Cost: **$0.37** (slightly higher than the historical ~$0.20 for similar batch sizes — call 2 added ~$0.005-0.01; rest is the larger 17-note backlog from skipped morning runs)
- `wiki/mindmap.json`: 16KB, real recursive tree
- `wiki/mindmap.html`: 18KB, opens in browser, radial layout renders

### Out of scope for v1 (deferred)

- Cross-links between themes (graph edges across the tree). v1 is a pure tree.
- Time-series animation of brain growth.
- Native iOS rendering — phase C.
- Prompt caching for call 2 — same `cache_read/write: 0/0` problem as call 1; not urgent.
- Lint/health pass integration.

## Stack

- **iOS App:** Swift, SwiftUI, iOS 17+
- **On-device transcription:** WhisperKit (Whisper base model, ~150MB)
- **Theme extraction:** Claude API (claude-sonnet-4-6)
- **Wiki browser:** Obsidian (free, iCloud sync)
- **Wiki maintenance:** Swift binary (`pensieve-ingest`) invoking Claude API directly, scheduled via launchd at 10:17am daily. Two sequential calls per run since 2026-04-25: existing wiki ingest, then a new mindmap pass that maintains `wiki/mindmap.json` and regenerates `wiki/mindmap.html`. Replaces the old `scripts/ingest.sh` + Claude Code agentic path for ~33x cost savings on call 1.
- **Mindmap rendering:** D3.js v7 from CDN, embedded in a single self-contained HTML file written by the Swift binary. Radial collapsible layout, insights sidebar, click-through to Obsidian via `obsidian://` URL.
- **Project generation:** xcodegen
