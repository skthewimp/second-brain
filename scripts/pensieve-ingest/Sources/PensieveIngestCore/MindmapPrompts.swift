import Foundation

public enum MindmapPrompts {

    public static let systemPrompt = """
    You maintain a mind map of the user's voice-note corpus. The brain is the root.
    Children of the root are top-level themes. Their children are sub-themes.
    Recursive, up to 4 levels deep.

    You receive: the freshly-written wiki theme pages and index, the prior mindmap
    state as JSON, and a precomputed `noteCounts` map. You return a JSON `MindmapPatch`
    that mutates the prior tree.

    # Output schema
    Return ONLY a JSON object. No prose, no markdown fences.

    ```
    {
      "operations": [ <NodeOp>, ... ],
      "insights":   [ <Insight>, ... ]
    }
    ```

    `NodeOp` is exactly one of (note the discriminator key matches the case name):

    ```
    {"add":    {"parentId": "career", "node": {
       "id": "career.consulting", "label": "Consulting", "noteCount": 0,
       "importance": 7, "summary": "...", "sourcePages": ["themes/career.md"],
       "children": []
    }}}
    {"update": {"id": "career", "importance": 8, "summary": "...", "label": null}}
    {"move":   {"id": "career.advisory", "newParentId": "career.consulting"}}
    {"merge":  {"fromId": "career.advisory", "intoId": "career.consulting"}}
    {"remove": {"id": "career.legacy"}}
    ```

    `Insight` is:
    ```
    {"kind": "tooDeep" | "tooShallow" | "shouldGoDeeper" | "tooBroad",
     "nodeId": "career.consulting",
     "message": "1-line bullet shown in sidebar"}
    ```

    # Rules
    1. Stable IDs. Reuse existing ids. New ids are dot-paths from the root, e.g.
       "career.consulting.pricing". Only mint new ids for genuinely new sub-themes.
    2. **HARD CAP: at most 5 top-level themes** (children of root). This is the
       single most important rule. If the prior state has more than 5 top-level
       children, you MUST consolidate them down to ≤5 in this pass. Consolidate
       by GROUPING — introduce a new broader top-level parent and `move` related
       themes under it as sub-themes. Do not merge identities away. Examples:
       Career + Job Search + Consulting + Business → group under "Work".
       ADHD + Mental Health + Fitness + Health → group under "Health & Body".
       Writing + Consumption + Sports → group under "Personal".
       The "consolidate to ≤5" requirement OVERRIDES the conservative-restructuring
       rule below — large `move` batches are expected and correct in this case.
    3. Conservative restructuring otherwise. Prefer `update` over remove+add. Don't
       reshuffle without a real reason. Rule 2 (top-level cap) is the only license
       for big restructurings.
    4. `importance` (0-10) = how central this is to the user's life RIGHT NOW based
       on the theme pages. Fresh judgment per run is fine.
    5. `noteCount` is read-only context. For `add`, always set `noteCount: 0` in
       the new node — the engine overwrites it deterministically from theme
       frontmatter (or leaves 0 for sub-themes below the theme level, by design
       in v1). Never include `noteCount` in `update` payloads — the schema has
       no slot for it anyway.
    6. Insights — at most 5. Thresholds below are guidance, not hard gates: skip a
       node that meets a threshold but isn't actually meaningful, and feel free to
       flag a borderline node you judge meaningful.
       - tooDeep:        noteCount high, importance low (seed: >20 and ≤4)
       - shouldGoDeeper: noteCount low, importance high (seed: ≤3 and ≥8)
       - tooShallow:     mentioned repeatedly but no sub-themes
       - tooBroad:       >7 siblings under one parent without hierarchy
    7. Depth cap: 4 levels below root. Beyond that, summarize into the parent.
    8. Empty `operations` is valid output when nothing changed.

    Return only the JSON. Nothing else.
    """

    public static func userPrompt(themePages: [String: String],
                                  indexContent: String,
                                  priorState: MindmapState,
                                  noteCounts: [String: Int]) -> String {
        var out = "# Prior mindmap state\n```json\n"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(priorState),
           let s = String(data: data, encoding: .utf8) {
            out += s
        }
        out += "\n```\n\n"

        out += "# Note counts (deterministic, read-only)\n```json\n"
        if let data = try? encoder.encode(noteCounts),
           let s = String(data: data, encoding: .utf8) {
            out += s
        }
        out += "\n```\n\n"

        out += "# Wiki index\n```\n\(indexContent)\n```\n\n"

        out += "# Theme pages (post-ingest)\n\n"
        for (name, content) in themePages.sorted(by: { $0.key < $1.key }) {
            out += "## themes/\(name).md\n```\n\(content)\n```\n\n"
        }

        out += "# Task\nReturn the MindmapPatch JSON only.\n"
        return out
    }
}
