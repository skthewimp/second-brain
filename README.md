# Pensieve

A voice-driven personal wiki for capturing and organizing thoughts over time. Talk into your phone, and a structured wiki builds itself.

Inspired by [Andrej Karpathy's LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

## How It Works

1. **Talk into your phone.** That's it. No titles, no categories, no organization needed.
2. **The phone handles the rest:**
   - Transcribes your voice on-device using [WhisperKit](https://github.com/argmaxinc/WhisperKit) (no network needed)
   - Sends the transcription to Claude API to extract themes, emotional tone, key quotes, and connections
   - Saves a structured markdown file to an Obsidian vault
3. **On your Mac, a daily script runs Claude Code** to ingest the raw notes into a structured wiki - theme pages, timeline, contradiction tracking, and cross-references.
4. **Browse in Obsidian** whenever you want to see where your head is at.

## Why This Exists

The problem: you think a lot, your priorities shift, and three months later you can't remember what you were optimizing for in January vs. April. You sense you might be going in circles but can't prove it.

The solution: talk freely, let the system organize everything, and the wiki shows you your own patterns - including the contradictions and circular thinking you can't see from inside your own head.

## Architecture

```
Phone (iOS)                          Mac
┌──────────────────┐                ┌──────────────────────────┐
│ Record voice     │                │ Obsidian (browse wiki)   │
│       ↓          │                │                          │
│ WhisperKit       │   iCloud/      │ Claude Code              │
│ (on-device)      │   Obsidian  →  │ (ingest raw → wiki)      │
│       ↓          │   sync         │                          │
│ Claude API       │                │ Wiki:                    │
│ (themes/tone)    │                │   themes/career.md       │
│       ↓          │                │   themes/priorities.md   │
│ Save .md to vault│                │   tensions/contradictions│
└──────────────────┘                │   timeline.md            │
                                    └──────────────────────────┘
```

## Project Structure

```
Pensieve/
├── iOS/                    # iPhone app (SwiftUI)
│   └── SecondBrain/
│       ├── Models/         # ThoughtNote, ClaudeResponse
│       ├── Services/       # Audio, Transcription, Claude API, Storage
│       └── Views/          # Recording, Notes List, Detail, Settings
├── wiki/                   # Obsidian vault (syncs from phone)
│   ├── raw/                # Auto-populated voice note markdowns
│   ├── wiki/               # LLM-maintained structured pages
│   │   ├── index.md
│   │   ├── timeline.md
│   │   ├── themes/         # Career, priorities, health, etc.
│   │   └── tensions/       # Contradictions and shifts
│   └── CLAUDE.md           # Schema for wiki maintenance
├── scripts/
│   └── ingest.sh           # Daily wiki ingestion via Claude Code
└── docs/
    ├── karpathy-llm-wiki.md    # Reference: the original pattern
    └── superpowers/plans/       # Implementation plan
```

## Setup

### Prerequisites
- iPhone running iOS 17+
- Mac with Xcode 15+
- Anthropic API key (from [console.anthropic.com](https://console.anthropic.com))
- Obsidian (free) on both Mac and iPhone
- Claude Code on Mac

### Steps

1. **Open the Xcode project** in `iOS/` and build to your iPhone
2. **Enter your API key** in the app's Settings
3. **Wait for Whisper model** to download (~150MB, one time)
4. **Start talking.** Record thoughts, the app handles the rest.
5. **Set up Obsidian vault sync** between phone and Mac (iCloud or manual)
6. **On Mac**, the daily cron job runs `scripts/ingest.sh` to process new notes into the wiki

### Sync Options
- **Obsidian + iCloud** (recommended): Create the vault in Obsidian on iPhone, it syncs via iCloud. Open same vault on Mac. Free, automatic, ~KB of storage.
- **Manual**: Connect phone to Mac via Finder, copy the vault folder.

## Privacy

- Audio never leaves your phone
- Transcription runs entirely on-device (WhisperKit)
- Only transcription text is sent to Claude API for analysis
- All data syncs via iCloud (encrypted by Apple) or stays local

## Wiki Maintenance

The wiki in `wiki/` is maintained by Claude Code. Open Claude Code in that directory and:

- **"Ingest new notes"** - processes raw voice notes into the wiki structure
- **"What was I thinking about X in February?"** - queries the wiki
- **"Am I going in circles on anything?"** - checks contradictions
- **"Lint the wiki"** - health-check for orphan pages, stale entries, missing links

The CLAUDE.md file in the wiki directory contains the full schema and instructions.
