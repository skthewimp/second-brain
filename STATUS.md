# Pensieve — Status

Last updated: 2026-04-26 (3 weeks of live data collected)

This file separates what's actually built from what's planned, since the repo
mixes scaffold, live system, and future ideas. Source of truth for "what
exists right now."

## Implemented (in this repo, working)

### iOS capture app
- Voice recording → on-device WhisperKit transcription → Claude API theme
  extraction → markdown saved to Obsidian vault in `raw/`.
- Vault linking via security-scoped bookmarks.
- Settings: API key, vault picker, vault sync, stats.
- Status: functional, installed on phone, in daily use.

### Wiki ingestion (`scripts/pensieve-ingest/`)
- Swift Package with `PensieveIngest` (CLI) + `PensieveIngestCore` (library,
  platform-agnostic so iOS can import it later).
- Single direct Claude API call per ingest, patch-based vault mutation.
  ~33x cheaper than the old agentic Claude Code path.
- 21 unit tests covering patch application, note-count aggregation,
  vault read/write.
- Driven by two launchd user agents:
  - Daily 10:17am — wiki ingest + mindmap (only when there were new notes).
  - Weekly Sunday 23:00 — `--rebuild-mindmap` (forced refresh).
- Manual `--rebuild-mindmap` flag for ad-hoc iteration.

### Mindmap visualization
- `wiki/mindmap.json` — stateful tree maintained via diff/patch ops.
- `wiki/mindmap.html` — self-contained D3 v7 radial tree, click-through to
  Obsidian via `obsidian://`.
- Hard cap of 5 top-level themes.
- Deterministic noteCount aggregation (Swift, not LLM) with leaf-segment
  match + parent rollup.
- Insights framed as observations about user thinking, not tree-organization
  tips.

## Live-only (running, not tracked in git)

The actual populated wiki lives in the iCloud Obsidian vault at
`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/SecondBrain/`, not
here. The `wiki/` directory in this repo is the schema scaffold only.

- `raw/` notes — 3 weeks of captures, phone-only artifact.
- `wiki/themes/*.md` — populated theme pages.
- `wiki/timeline.md`, `wiki/log.md`, `wiki/tensions/contradictions.md` —
  populated and growing.
- `wiki/mindmap.json` and `wiki/mindmap.html` — generated daily/weekly.

## Deferred (intentionally not built yet)

Full list with rationale lives in `CLAUDE.md` under "Deferred work." Summary:

1. Retrieval/resurfacing — daily digests, "you're going in circles" alerts,
   related past notes on new capture.
2. Phone-only wiki ingestion (currently needs Mac).
3. Prompt caching optimization (~30-50% further cost cut).
4. **Contradiction provenance tagging** — `EXTRACTED` / `INFERRED` /
   `AMBIGUOUS`. Independently confirmed as the right design by an external
   review (`docs/2026-04-25-project-review.md`). Highest-priority deferred
   item now that 3 weeks of data exists.
5. Action item routing.
6. Blog post revision.
7. "Challenge" prompt at ingestion — actively surface conflicts, not just
   passive logging.
8. Periodic lint/health pass (`--lint` mode).
9. Entity pages — dedicated pages for recurring people/companies/projects.
10. Bi-temporal fact tracking — when a thing was true vs. when the vault
    learned it.

## Planned next (post-3-weeks-of-data)

Picked from `docs/2026-04-25-project-review.md` review. In rough priority:

1. **Contradiction provenance** (deferred item #4) — the contradictions page
   is the most valuable page; a hallucinated contradiction is worse than a
   missed one. ~20 lines of Swift + a prompt tweak.
2. **Code-enforced invariants on patches** — slug normalization, duplicate
   detection, `indexRewrite` consistency check. LLM proposes structure;
   code enforces it.
3. **Resurfacing on capture** (deferred item #1) — bring the right past
   notes back at capture time. The data finally exists to validate this.

Not picked from the review:
- Keychain for API key — overengineered for a single-user tool.
- iOS app hardening — works fine for the one user it has.
- Most of the "analytics layer" features (mood×topic, priority drift,
  decision journal) — interesting but premature; revisit after the trust
  layer (provenance) is in place.
