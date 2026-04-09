# Second Brain - Dev Log

## Project Genesis

**Date:** 2026-04-07 to 2026-04-09
**Built with:** Claude Code (Claude Opus 4.6)

---

## Context

Karthik shared a link to Andrej Karpathy's viral "LLM Wiki" gist - a pattern for building personal knowledge bases where an LLM incrementally builds and maintains a structured wiki from raw sources, rather than doing RAG-style retrieval from scratch every time.

The conversation evolved from "how do I use this?" into designing a personal system. The key constraint: Karthik has ADHD and his therapist recommended a "safe second brain" but didn't say how to implement it. The problem wasn't just note-taking - it was tracking how his thinking evolves over time (especially around career decisions) and spotting when he's going in circles.

## Prompts and Decisions

### Session 1 (2026-04-07)

**Prompt:** "this seems to have gone viral. how can i use it? [karpathy gist link]"

Fetched the gist, summarized the LLM Wiki pattern, asked what domain to apply it to.

**Prompt:** "Okay, do I know what to use this for?"

Checked memory - knew about writing voice, data science background, Babbage Insight. Suggested a research/writing wiki since his writing is built on cross-domain connections.

**Prompt:** [Long voice-transcribed message about ADHD, therapist's recommendation, needing zero-friction input, existing voice notes app]

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
The original NotesAgent used Ollama (qwen2.5:7b-instruct) for summarization. For the second brain, we need more nuanced processing - theme extraction, emotional tone detection, identifying connections to other topics. Claude is significantly better at this kind of structured analysis. Also eliminates the Mac dependency since Ollama only ran on the Mac server.

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

**ADHD Second Brain research:** Researched the concept from an ADHD standpoint. Key finding: the system has strong capture and organization but is missing automated resurfacing (daily digests, "you're going in circles" alerts, related past notes when new ones come in). User wisely decided to wait a week of actual usage before adding retrieval features.

### Nested ObservableObject Pattern (recurring lesson)

SwiftUI does not observe `@Published` properties on nested `ObservableObject`s. If `ServiceA` holds `ServiceB` (which is an `ObservableObject`), changes to `ServiceB.someProperty` won't trigger SwiftUI view updates even if `someProperty` is `@Published`.

**Fix:** Forward the property through the parent using Combine:
```swift
serviceB.$someProperty
    .receive(on: DispatchQueue.main)
    .assign(to: &$someProperty)
```

This came up three times in this project. If I add more observable state to child services, I need to forward it.

## Stack

- **iOS App:** Swift, SwiftUI, iOS 17+
- **On-device transcription:** WhisperKit (Whisper base model, ~150MB)
- **Theme extraction:** Claude API (claude-sonnet-4-6)
- **Wiki browser:** Obsidian (free, iCloud sync)
- **Wiki maintenance:** Claude Code (daily cron via `scripts/ingest.sh`)
- **Project generation:** xcodegen
