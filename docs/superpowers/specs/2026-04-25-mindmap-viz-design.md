# Mindmap Visualization — Design Spec

**Date:** 2026-04-25
**Status:** Draft, awaiting review

## Goal

An interactive, zoomable mind-map of the user's voice-note corpus. Brain at the center, themes radiating out, sub-themes cascading recursively. Surfaces insights about *where thought is going*: too deep, too shallow, too broad, under-explored.

## Locked decisions

| Question | Choice |
|---|---|
| Where viz lives | Standalone web page, written to vault by `pensieve-ingest`. iOS port deferred. |
| Sub-theme source | Dedicated LLM pass produces the tree. |
| Per-node signals | `noteCount` (volume) + `importance` (0-10, LLM-judged). |
| Insight surfacing | Visual coloring + sidebar bullets + click-through to Obsidian. |
| Refresh model | Stateful tree, daily diff. `mindmap.json` persists across runs; LLM emits patch ops. |
| Layout | Radial collapsible (D3 `d3.tree()` with radial projection). |
| Rendering tech | Single self-contained HTML, D3 from CDN, data inlined as `<script>`. |
| LLM call structure | **Two sequential calls**, not one. Mindmap is a separate pass after ingest. |

## Architecture

```
pensieve-ingest (daily, launchd)
  ├─ Call 1: existing ingest pass → applies IngestionPatch (untouched)
  ├─ Call 2: NEW mindmap pass
  │    in:  fresh wiki/themes/*.md + wiki/index.md + prior wiki/mindmap.json
  │    out: MindmapPatch + insights
  ├─ apply patch → wiki/mindmap.json
  └─ MindmapRenderer → wiki/mindmap.html (data inlined)
```

**Why two calls, not one:**

- Wiki writing and tree maintenance are different jobs. Cramming both into one prompt invites context rot, parse failures, all-or-nothing blast radius.
- Call 2 sees the *just-updated* theme pages, which is the right signal for "where is the brain right now".
- Call 2's input is much smaller — theme summaries + index + prior tree, no raw note bodies.
- Cost delta is negligible (~+$0.003-0.005/run). Latency added ~5-15s once a day.
- Mindmap call failure is non-fatal; wiki ingest already succeeded.

## File layout

```
scripts/pensieve-ingest/Sources/PensieveIngestCore/
  MindmapModels.swift        NEW   — MindmapState, MindmapNode, MindmapPatch, NodeOp, Insight
  MindmapPrompts.swift       NEW   — system + user prompts for call 2
  MindmapRenderer.swift      NEW   — string-templates mindmap.html
  IngestEngine.swift         EDIT  — orchestrate call 2 after call 1 succeeds
  ClaudeClient.swift         (no change — already generic)
  VaultReader.swift          EDIT  — load mindmap.json
  VaultWriter.swift          EDIT  — write mindmap.json + mindmap.html
  Models.swift               (no change — IngestionPatch unchanged)

wiki/
  mindmap.json               NEW   — canonical tree state, committed to git
  mindmap.html               NEW   — generated each run, committed to git
```

## Data model

```swift
struct MindmapState: Codable {
    var version: Int                    // schema version, start 1
    var lastUpdated: String             // ISO date
    var root: MindmapNode               // the brain, fixed root
}

struct MindmapNode: Codable {
    var id: String                      // dot-path slug, e.g. "career.consulting.pricing"
    var label: String                   // human, e.g. "Pricing models"
    var noteCount: Int                  // cumulative count
    var importance: Int                 // 0-10
    var summary: String                 // 1-line, hover tooltip
    var sourcePages: [String]           // ["themes/career.md"]
    var children: [MindmapNode]
}

struct MindmapPatch: Codable {
    var operations: [NodeOp]
    var insights: [Insight]
}

enum NodeOp: Codable {
    case add(parentId: String, node: MindmapNode)
    case update(id: String, noteCount: Int?, importance: Int?, summary: String?, label: String?)
    case move(id: String, newParentId: String)
    case merge(fromId: String, intoId: String)
    case remove(id: String)
}

struct Insight: Codable {
    enum Kind: String, Codable { case tooDeep, tooShallow, shouldGoDeeper, tooBroad }
    var kind: Kind
    var nodeId: String
    var message: String
}
```

**Stable IDs.** Dot-path slugs. LLM is told to reuse existing IDs unless splitting/merging. This is what kills layout jitter across runs and lets us show growth deltas later.

## Prompt rules (call 2)

The system prompt for the mindmap call enforces:

1. **Stable IDs.** Reuse existing IDs. Mint new IDs only for genuinely new sub-themes. Dot-path slugs.
2. **Conservative restructuring.** Prefer `update` over `remove`+`add`. Don't reshuffle for no reason.
3. **`importance` (0-10)** = how central this is to the user's life *right now*, judged from theme pages, not legacy. Fresh judgment per run is fine.
4. **`noteCount`** = cumulative count of raw notes mentioning this node. Source of truth: `wiki/log.md`. Increment, don't reset.
5. **Insights — at most 5.** Only flag genuine mismatches:
    - `tooDeep`: `noteCount` high, `importance` low (heuristic seed: >20 and ≤4)
    - `shouldGoDeeper`: `noteCount` low, `importance` high (≤3 and ≥8)
    - `tooShallow`: mentioned repeatedly but no sub-themes spawned
    - `tooBroad`: >7 siblings under one parent without clear hierarchy
6. **Depth cap: 4 levels** below root. Beyond that, summarize into parent.
7. **Empty `operations` is valid output** when nothing changed.

## Renderer

`MindmapRenderer.swift` exposes:

```swift
static func render(state: MindmapState, insights: [Insight]) -> String
```

The HTML template is kept inline as a Swift string (no separate resource file → no SPM resource-bundle complications for the future iOS port). Data + insights are inlined as `<script>const data = ...; const insights = ...;</script>`. D3.js is loaded from a CDN (`d3@7`).

## Visualization (D3)

- **Layout:** `d3.tree()` with radial projection. Root at center. Children placed on rings by depth. Mirror of the user's sketch.
- **Sizing:** node radius scales with `noteCount` (sqrt scale, capped).
- **Color (HSL ramp):**
    - Blue = under-explored important (`importance` ≫ `noteCount`)
    - Red = over-explored minor (`noteCount` ≫ `importance`)
    - Gray = balanced
- **Interaction:**
    - Click node → expand/collapse subtree.
    - Hover node → tooltip with `summary`, `noteCount`, `importance`.
    - Shift-click or "open in Obsidian" link → `obsidian://open?vault=SecondBrain&file=<sourcePages[0]>`.
    - Pinch/scroll to zoom, drag to pan.
- **Sidebar:** insight bullets in `<aside id="insights">`. Each bullet shows kind icon + message. Click bullet → highlight + center the corresponding node.
- **Header:** "Last updated: {{UPDATED}}". That's it. No chrome.

## Failure handling

- Call 2 fails → log to `/tmp/pensieve-ingest.log`, exit 0 from the mindmap step. Wiki ingest already succeeded.
- Patch parse fails → same: log and skip. Yesterday's `mindmap.html` and `mindmap.json` stay in place.
- Renderer fails → same.
- These are best-effort; the wiki itself is the canonical artifact.

## Out of scope (v1)

- **Cross-links** between themes (graph edges across the tree). v1 is a pure tree.
- **Time-series animation** ("show me how the brain grew over the past 30 days"). Stable IDs make this possible later.
- **Phone viewing** beyond opening `mindmap.html` in mobile Safari from the synced vault. Native iOS rendering = phase C.
- **Prompt caching** for call 2. Hooks into the existing deferred work item; defer.
- **Lint/health pass** integration. Separate deferred item.

## Test plan

- Unit: encoding/decoding of `MindmapPatch` round-trips.
- Unit: `applyPatch(to:)` correctly handles add / update / move / merge / remove.
- Unit: `MindmapRenderer.render()` produces parseable HTML; inlined JSON is valid JSON.
- Integration: dry-run `pensieve-ingest` against a 5-note fixture vault; verify `mindmap.json` populated and `mindmap.html` opens.
- Manual: open `mindmap.html` in Safari + Chrome; verify radial layout, click-to-expand, sidebar, Obsidian link.

## Cost note

- Call 2 input ≈ themes (small) + index + prior `mindmap.json` (grows with tree size, expected <50 KB for months).
- Call 2 output ≈ patch JSON, typically small.
- Estimated added cost: ~$0.003-0.005 per ingest run on Sonnet 4.6. Acceptable.

## Devlog

Per the global new-project workflow, append a session entry to `dev-log.md` after implementation, covering: prompts used, decisions made (one-call vs two, layout choice, ID stability), problems hit.
