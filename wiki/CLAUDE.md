# Pensieve Wiki — Schema

You are maintaining a personal wiki for Karthik. This wiki is his "pensieve" - a structured, evolving record of his thoughts, decisions, and mental state over time. It is built primarily from voice notes he records throughout his day.

## Purpose

Karthik thinks constantly but loses track of how his thinking evolves. This wiki exists to:
1. Capture his stream-of-consciousness thoughts with zero friction (voice → wiki)
2. Track how his thinking on key topics changes over time
3. Surface contradictions and circular patterns he can't see himself
4. Provide a structured view of his mental landscape he can browse in Obsidian

## Directory Structure

```
wiki/
├── raw/                    # Voice note transcriptions (auto-populated, never edit)
│   └── YYYY-MM-DD_HHMM.md # Each file = one voice note
├── wiki/
│   ├── index.md            # Master catalog of all wiki pages
│   ├── log.md              # Chronological record of ingestions
│   ├── timeline.md         # "What you were thinking when" - chronological view
│   ├── themes/             # Topic pages that evolve over time
│   │   ├── career.md
│   │   ├── priorities.md
│   │   └── ...             # Themes emerge organically from notes
│   ├── tensions/           # Where thinking has shifted or contradicted itself
│   │   └── contradictions.md
│   └── insights/           # Synthesized observations, patterns across themes
└── CLAUDE.md               # This file
```

## Raw Note Format

Each file in `raw/` has this structure (written by the iOS app):

```markdown
---
date: 2026-04-07T14:30:00+05:30
duration: 2m34s
themes: [career, priorities]
emotional_tone: reflective
---

# Summary
- Bullet point summary from Claude API

# Transcription
Full verbatim transcription...
```

## Conventions

### Wiki pages

- Use `[[wikilinks]]` for cross-references (Obsidian-compatible)
- Every page gets YAML frontmatter with at least: `title`, `type` (theme/tension/insight/timeline), `last_updated`, `source_count`
- Theme pages are organized chronologically within: each entry is dated, showing what was said and when
- Never delete old entries from theme pages — the history IS the value
- Use `> [!shift]` callouts to highlight when thinking has meaningfully changed
- Use `> [!contradiction]` callouts when a new note contradicts a previous position

### Ingestion workflow

When told to ingest new notes:

1. Read all unprocessed files in `raw/` (check `log.md` to see what's been processed)
2. For each new note:
   a. Identify themes/topics mentioned
   b. Create theme pages if they don't exist yet
   c. Add a dated entry to each relevant theme page
   d. Check if the new note contradicts or shifts from previous entries on that theme
   e. If so, add entries to `tensions/contradictions.md` and use callouts on the theme page
   f. Update `timeline.md` with a one-line summary
   g. Update `index.md` if new pages were created
   h. Append to `log.md`
3. After processing all notes, do a quick lint:
   - Any themes mentioned but lacking their own page?
   - Any theme pages that haven't been updated in a long time but have active related themes?
   - Any emerging patterns across themes worth noting in `insights/`?

### Theme page structure

```markdown
---
title: Career
type: theme
last_updated: 2026-04-07
source_count: 12
---

# Career

## Current State
[2-3 sentence summary of where thinking currently stands]

## Evolution

### 2026-04-07
> Feeling like what I'm optimizing for has changed significantly...
- Started job ~3-4 months ago
- Sense of going in circles
- *Source: [[2026-04-07_1430]]*

### 2026-03-15
> Excited about the new role, lots to learn...
- Optimizing for learning and growth
- *Source: [[2026-03-15_0920]]*

## Patterns
[Observations about how this theme has evolved]
```

### Contradictions page structure

```markdown
## [Date] Topic — Shift detected

**Before** (date): [What was said]
**Now** (date): [What's being said now]
**Nature of shift**: [e.g., reversal, refinement, escalation, circular return]
**Related themes**: [[theme1]], [[theme2]]
```

### Timeline page

A simple reverse-chronological list:

```markdown
- **2026-04-07 14:30** — Reflected on career direction, feeling circular. Themes: [[Career]], [[Priorities]]
- **2026-04-07 08:15** — Morning anxiety about workload. Themes: [[Work]], [[Mental Health]]
```

## Important Rules

1. **Never judge.** This is a safe space. Record what was said, not what should have been said.
2. **Preserve voice.** Use Karthik's actual words in quotes when they capture something important.
3. **Flag patterns, don't prescribe.** "You've mentioned this three times" is good. "You should do X" is not your job.
4. **Err on the side of creating new theme pages.** If something comes up twice, it deserves a page.
5. **The contradictions page is the most valuable page.** Maintain it carefully. It's what helps Karthik see his own circular thinking.
6. **Date everything.** Every entry, every update. The temporal dimension is the whole point.

## Querying

When Karthik asks questions like:
- "What was I thinking about my career in February?" → Read `themes/career.md`, filter to February entries
- "Am I going in circles on anything?" → Read `tensions/contradictions.md`
- "What are my top concerns right now?" → Read recent entries in `timeline.md`, identify recurring themes
- "How has my thinking on X changed?" → Read the relevant theme page, summarize the evolution

Always cite sources with links to the original raw notes.
