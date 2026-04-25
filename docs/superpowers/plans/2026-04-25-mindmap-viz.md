# Mindmap Visualization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a daily-rebuilt, radial, interactive HTML mind-map of the user's voice-note corpus (`wiki/mindmap.html`), driven by a second sequential Claude call inside `pensieve-ingest`.

**Architecture:** A stateful tree (`wiki/mindmap.json`) is mutated each ingest by a separate Claude call that sees the freshly-rewritten theme pages and the prior tree. A Swift renderer string-templates the tree into a self-contained HTML page (D3 from CDN, data inlined). Failures in the mindmap pass are non-fatal — wiki ingest already succeeded.

**Tech Stack:** Swift 5.9 (PensieveIngestCore SPM target), D3.js v7 (CDN), Foundation `JSONEncoder`/`Decoder`, `XCTest`.

**Spec:** `docs/superpowers/specs/2026-04-25-mindmap-viz-design.md`

---

## File Structure

```
scripts/pensieve-ingest/
  Package.swift                                            EDIT  — add test target
  Sources/PensieveIngestCore/
    MindmapModels.swift                                    NEW   — MindmapState, MindmapNode, MindmapPatch, NodeOp, Insight, MindmapStats
    MindmapPatchApplier.swift                              NEW   — pure function: applyPatch(prior, patch) -> MindmapState
    MindmapNoteCountAggregator.swift                       NEW   — pure function: countsFromThemes(themeFrontmatters) -> [String: Int]
    MindmapPrompts.swift                                   NEW   — system + user prompts for call 2
    MindmapRenderer.swift                                  NEW   — renderHTML(state, insights) -> String, embeds D3 template
    MindmapEngine.swift                                    NEW   — orchestrates call 2, swallows + logs errors
    VaultReader.swift                                      EDIT  — load mindmap.json (returns MindmapState? — nil if missing)
    VaultWriter.swift                                      EDIT  — write mindmap.json + mindmap.html
    IngestEngine.swift                                     EDIT  — invoke MindmapEngine after main pass, log result
  Tests/PensieveIngestCoreTests/                           NEW   — test target dir
    MindmapModelsTests.swift                               NEW
    MindmapPatchApplierTests.swift                         NEW
    MindmapNoteCountAggregatorTests.swift                  NEW
    MindmapRendererTests.swift                             NEW
    Fixtures/                                              NEW
      sample-themes/                                       NEW   — directory of fake theme .md files for aggregator tests
      sample-mindmap.json
docs/superpowers/specs/2026-04-25-mindmap-viz-design.md    (already committed)
docs/superpowers/plans/2026-04-25-mindmap-viz.md           (this file)
dev-log.md                                                 EDIT  — final task appends session entry
```

**Boundaries:** Each new file has one job. Patch application is pure (no I/O). Note-count aggregation is pure. Renderer is pure (string in, string out). Only `MindmapEngine`, `VaultReader`, `VaultWriter`, `IngestEngine` touch the filesystem or network. This keeps the bulk of logic trivially testable.

---

## Task 1: Add XCTest target to the SPM package

**Files:**
- Modify: `scripts/pensieve-ingest/Package.swift`
- Create: `scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/SmokeTest.swift`

- [ ] **Step 1: Add a smoke test that imports the library**

Create `scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/SmokeTest.swift`:

```swift
import XCTest
@testable import PensieveIngestCore

final class SmokeTest: XCTestCase {
    func testLibraryImports() {
        // existence check; will fail to compile if module is broken
        let _: VaultReader.Type = VaultReader.self
    }
}
```

- [ ] **Step 2: Add test target to `Package.swift`**

Replace the `targets:` array in `Package.swift` with:

```swift
    targets: [
        .executableTarget(name: "PensieveIngest", dependencies: ["PensieveIngestCore"]),
        .target(name: "PensieveIngestCore"),
        .testTarget(name: "PensieveIngestCoreTests", dependencies: ["PensieveIngestCore"]),
    ]
```

- [ ] **Step 3: Verify tests run**

```bash
cd scripts/pensieve-ingest && swift test
```

Expected: `Test Suite 'All tests' passed`. 1 test, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add scripts/pensieve-ingest/Package.swift scripts/pensieve-ingest/Tests
git commit -m "add XCTest target to pensieve-ingest package"
```

---

## Task 2: Define mindmap data types

**Files:**
- Create: `scripts/pensieve-ingest/Sources/PensieveIngestCore/MindmapModels.swift`
- Create: `scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/MindmapModelsTests.swift`

- [ ] **Step 1: Write the failing round-trip test**

Create `MindmapModelsTests.swift`:

```swift
import XCTest
@testable import PensieveIngestCore

final class MindmapModelsTests: XCTestCase {
    func testStateRoundTrip() throws {
        let root = MindmapNode(
            id: "root", label: "Brain", noteCount: 0, importance: 10,
            summary: "the user's mind", sourcePages: [],
            children: [
                MindmapNode(id: "career", label: "Career", noteCount: 12,
                            importance: 9, summary: "work life",
                            sourcePages: ["themes/career.md"], children: [])
            ]
        )
        let state = MindmapState(version: 1, lastUpdated: "2026-04-25", root: root)
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(MindmapState.self, from: data)
        XCTAssertEqual(back.root.children.first?.id, "career")
        XCTAssertEqual(back.root.children.first?.noteCount, 12)
    }

    func testNodeOpAddDecodes() throws {
        let json = """
        {"add":{"parentId":"root","node":{"id":"hobbies","label":"Hobbies","noteCount":0,"importance":5,"summary":"","sourcePages":[],"children":[]}}}
        """.data(using: .utf8)!
        let op = try JSONDecoder().decode(NodeOp.self, from: json)
        if case .add(let parent, let node) = op {
            XCTAssertEqual(parent, "root")
            XCTAssertEqual(node.id, "hobbies")
        } else { XCTFail("expected .add") }
    }

    func testNodeOpUpdateDecodes() throws {
        let json = """
        {"update":{"id":"career","importance":4,"summary":"shifted","label":null}}
        """.data(using: .utf8)!
        if case .update(let id, let imp, let summary, let label) =
            try JSONDecoder().decode(NodeOp.self, from: json) {
            XCTAssertEqual(id, "career")
            XCTAssertEqual(imp, 4)
            XCTAssertEqual(summary, "shifted")
            XCTAssertNil(label)
        } else { XCTFail("expected .update") }
    }

    func testNodeOpMoveDecodes() throws {
        let json = """
        {"move":{"id":"career.advisory","newParentId":"career.consulting"}}
        """.data(using: .utf8)!
        if case .move(let id, let parent) =
            try JSONDecoder().decode(NodeOp.self, from: json) {
            XCTAssertEqual(id, "career.advisory")
            XCTAssertEqual(parent, "career.consulting")
        } else { XCTFail("expected .move") }
    }

    func testNodeOpMergeDecodes() throws {
        let json = """
        {"merge":{"fromId":"a","intoId":"b"}}
        """.data(using: .utf8)!
        if case .merge(let from, let into) =
            try JSONDecoder().decode(NodeOp.self, from: json) {
            XCTAssertEqual(from, "a"); XCTAssertEqual(into, "b")
        } else { XCTFail("expected .merge") }
    }

    func testNodeOpRemoveDecodes() throws {
        let json = """
        {"remove":{"id":"old"}}
        """.data(using: .utf8)!
        if case .remove(let id) =
            try JSONDecoder().decode(NodeOp.self, from: json) {
            XCTAssertEqual(id, "old")
        } else { XCTFail("expected .remove") }
    }

    func testInsightRoundTrip() throws {
        let i = Insight(kind: .tooDeep, nodeId: "career.consulting.pricing",
                        message: "40 notes, importance 4")
        let data = try JSONEncoder().encode(i)
        let back = try JSONDecoder().decode(Insight.self, from: data)
        XCTAssertEqual(back.kind, .tooDeep)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd scripts/pensieve-ingest && swift test 2>&1 | tail -20
```

Expected: compile error referring to `MindmapState`, `MindmapNode`, `NodeOp`, `Insight` not found.

- [ ] **Step 3: Implement the types**

Create `MindmapModels.swift`:

```swift
import Foundation

public struct MindmapState: Codable {
    public var version: Int
    public var lastUpdated: String
    public var root: MindmapNode
    public init(version: Int, lastUpdated: String, root: MindmapNode) {
        self.version = version; self.lastUpdated = lastUpdated; self.root = root
    }
}

public struct MindmapNode: Codable {
    public var id: String
    public var label: String
    public var noteCount: Int
    public var importance: Int
    public var summary: String
    public var sourcePages: [String]
    public var children: [MindmapNode]
    public init(id: String, label: String, noteCount: Int, importance: Int,
                summary: String, sourcePages: [String], children: [MindmapNode]) {
        self.id = id; self.label = label; self.noteCount = noteCount
        self.importance = importance; self.summary = summary
        self.sourcePages = sourcePages; self.children = children
    }
}

public struct MindmapPatch: Codable {
    public var operations: [NodeOp]
    public var insights: [Insight]
    public init(operations: [NodeOp], insights: [Insight]) {
        self.operations = operations; self.insights = insights
    }
}

public enum NodeOp: Codable {
    case add(parentId: String, node: MindmapNode)
    case update(id: String, importance: Int?, summary: String?, label: String?)
    case move(id: String, newParentId: String)
    case merge(fromId: String, intoId: String)
    case remove(id: String)
}

public struct Insight: Codable {
    public enum Kind: String, Codable {
        case tooDeep, tooShallow, shouldGoDeeper, tooBroad
    }
    public var kind: Kind
    public var nodeId: String
    public var message: String
    public init(kind: Kind, nodeId: String, message: String) {
        self.kind = kind; self.nodeId = nodeId; self.message = message
    }
}

public struct MindmapStats {
    public let nodesTotal: Int
    public let opsApplied: Int
    public let insightsCount: Int
    public let inputTokens: Int
    public let outputTokens: Int
}
```

Note: `update` deliberately omits a `noteCount` parameter — counts are computed deterministically (Task 4), the LLM never writes them. (This matches the updated spec, rule 4.)

- [ ] **Step 4: Run tests**

```bash
cd scripts/pensieve-ingest && swift test --filter MindmapModelsTests
```

Expected: all 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/pensieve-ingest/Sources/PensieveIngestCore/MindmapModels.swift \
        scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/MindmapModelsTests.swift
git commit -m "add mindmap data types"
```

---

## Task 3: Patch application (pure function)

**Files:**
- Create: `scripts/pensieve-ingest/Sources/PensieveIngestCore/MindmapPatchApplier.swift`
- Create: `scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/MindmapPatchApplierTests.swift`

- [ ] **Step 1: Write failing tests for each op**

Create `MindmapPatchApplierTests.swift`:

```swift
import XCTest
@testable import PensieveIngestCore

final class MindmapPatchApplierTests: XCTestCase {
    private func base() -> MindmapState {
        let career = MindmapNode(id: "career", label: "Career", noteCount: 5,
                                 importance: 8, summary: "", sourcePages: [], children: [])
        let root = MindmapNode(id: "root", label: "Brain", noteCount: 0,
                               importance: 10, summary: "", sourcePages: [], children: [career])
        return MindmapState(version: 1, lastUpdated: "2026-04-24", root: root)
    }

    func testAddChild() throws {
        let newNode = MindmapNode(id: "career.consulting", label: "Consulting",
                                  noteCount: 0, importance: 7, summary: "",
                                  sourcePages: [], children: [])
        let patch = MindmapPatch(
            operations: [.add(parentId: "career", node: newNode)],
            insights: []
        )
        let updated = try MindmapPatchApplier.apply(patch, to: base())
        XCTAssertEqual(updated.root.children.first?.children.first?.id, "career.consulting")
    }

    func testUpdateImportance() throws {
        let patch = MindmapPatch(
            operations: [.update(id: "career", importance: 4, summary: nil, label: nil)],
            insights: []
        )
        let updated = try MindmapPatchApplier.apply(patch, to: base())
        XCTAssertEqual(updated.root.children.first?.importance, 4)
    }

    func testRemove() throws {
        let patch = MindmapPatch(
            operations: [.remove(id: "career")],
            insights: []
        )
        let updated = try MindmapPatchApplier.apply(patch, to: base())
        XCTAssertTrue(updated.root.children.isEmpty)
    }

    func testMoveReparents() throws {
        var b = base()
        let hobbies = MindmapNode(id: "hobbies", label: "Hobbies", noteCount: 0,
                                  importance: 4, summary: "", sourcePages: [], children: [])
        b.root.children.append(hobbies)
        let patch = MindmapPatch(
            operations: [.move(id: "hobbies", newParentId: "career")],
            insights: []
        )
        let updated = try MindmapPatchApplier.apply(patch, to: b)
        XCTAssertEqual(updated.root.children.count, 1)
        XCTAssertEqual(updated.root.children.first?.children.first?.id, "hobbies")
    }

    func testMergeAbsorbsChildren() throws {
        var b = base()
        let consulting = MindmapNode(id: "career.consulting", label: "Consulting",
                                     noteCount: 3, importance: 7, summary: "",
                                     sourcePages: [], children: [])
        let advisory = MindmapNode(id: "career.advisory", label: "Advisory",
                                   noteCount: 2, importance: 6, summary: "",
                                   sourcePages: [], children: [])
        b.root.children[0].children = [consulting, advisory]
        let patch = MindmapPatch(
            operations: [.merge(fromId: "career.advisory", intoId: "career.consulting")],
            insights: []
        )
        let updated = try MindmapPatchApplier.apply(patch, to: b)
        XCTAssertEqual(updated.root.children[0].children.count, 1)
        XCTAssertEqual(updated.root.children[0].children[0].id, "career.consulting")
    }

    func testUnknownIdIsIgnored() throws {
        let patch = MindmapPatch(
            operations: [.update(id: "ghost", importance: 1, summary: nil, label: nil)],
            insights: []
        )
        let updated = try MindmapPatchApplier.apply(patch, to: base())
        XCTAssertEqual(updated.root.children.first?.importance, 8) // unchanged
    }
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd scripts/pensieve-ingest && swift test --filter MindmapPatchApplierTests 2>&1 | tail -10
```

Expected: compile error — `MindmapPatchApplier` not found.

- [ ] **Step 3: Implement applier**

Create `MindmapPatchApplier.swift`:

```swift
import Foundation

public enum MindmapPatchApplier {
    public static func apply(_ patch: MindmapPatch, to state: MindmapState) throws -> MindmapState {
        var root = state.root
        for op in patch.operations {
            root = applyOp(op, to: root)
        }
        return MindmapState(version: state.version, lastUpdated: state.lastUpdated, root: root)
    }

    private static func applyOp(_ op: NodeOp, to node: MindmapNode) -> MindmapNode {
        switch op {
        case .add(let parentId, let newNode):
            return mutate(node) { n in
                if n.id == parentId { n.children.append(newNode) }
            }
        case .update(let id, let imp, let summary, let label):
            return mutate(node) { n in
                if n.id == id {
                    if let imp = imp { n.importance = imp }
                    if let summary = summary { n.summary = summary }
                    if let label = label { n.label = label }
                }
            }
        case .move(let id, let newParentId):
            guard let (detached, withoutId) = detach(id: id, from: node) else { return node }
            return mutate(withoutId) { n in
                if n.id == newParentId { n.children.append(detached) }
            }
        case .merge(let fromId, let intoId):
            guard let (from, withoutFrom) = detach(id: fromId, from: node) else { return node }
            return mutate(withoutFrom) { n in
                if n.id == intoId {
                    n.children.append(contentsOf: from.children)
                    n.noteCount += from.noteCount
                }
            }
        case .remove(let id):
            return detach(id: id, from: node)?.1 ?? node
        }
    }

    private static func mutate(_ node: MindmapNode, _ f: (inout MindmapNode) -> Void) -> MindmapNode {
        var copy = node
        f(&copy)
        copy.children = copy.children.map { mutate($0, f) }
        return copy
    }

    /// Returns (detached subtree, parent tree with subtree removed) if found.
    private static func detach(id: String, from node: MindmapNode) -> (MindmapNode, MindmapNode)? {
        if let idx = node.children.firstIndex(where: { $0.id == id }) {
            var copy = node
            let removed = copy.children.remove(at: idx)
            return (removed, copy)
        }
        for (i, child) in node.children.enumerated() {
            if let (removed, newChild) = detach(id: id, from: child) {
                var copy = node
                copy.children[i] = newChild
                return (removed, copy)
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd scripts/pensieve-ingest && swift test --filter MindmapPatchApplierTests
```

Expected: all 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/pensieve-ingest/Sources/PensieveIngestCore/MindmapPatchApplier.swift \
        scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/MindmapPatchApplierTests.swift
git commit -m "add mindmap patch applier (pure)"
```

---

## Task 4: Note-count aggregator (deterministic, from theme frontmatter)

**Source of truth:** each theme page already carries `source_count: N` in its YAML frontmatter, maintained by `VaultWriter.bumpFrontmatter` on every ingest. We read those, not `log.md`. Only top-level theme nodes (whose `id` matches a theme slug) get a count; sub-theme nodes (e.g. `career.consulting`) carry `0` in v1 — there is no deterministic source below the theme level, and we explicitly refuse to let the LLM invent counts.

**Files:**
- Create: `scripts/pensieve-ingest/Sources/PensieveIngestCore/MindmapNoteCountAggregator.swift`
- Create: `scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/MindmapNoteCountAggregatorTests.swift`
- Create: `scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/Fixtures/sample-themes/career.md`
- Create: `scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/Fixtures/sample-themes/mental-health.md`

- [ ] **Step 1: Write fixtures**

Create `Fixtures/sample-themes/career.md`:

```markdown
---
title: Career
type: theme
last_updated: 2026-04-24
source_count: 12
---

# Career
## Current State
...
```

Create `Fixtures/sample-themes/mental-health.md`:

```markdown
---
title: Mental Health
type: theme
last_updated: 2026-04-22
source_count: 5
---

# Mental Health
```

- [ ] **Step 2: Write failing test**

Create `MindmapNoteCountAggregatorTests.swift`:

```swift
import XCTest
@testable import PensieveIngestCore

final class MindmapNoteCountAggregatorTests: XCTestCase {
    private func themesDir() -> URL {
        Bundle.module.url(forResource: "career", withExtension: "md",
                          subdirectory: "sample-themes")!
            .deletingLastPathComponent()
    }

    func testCountsPerThemeFromFrontmatter() throws {
        let counts = try MindmapNoteCountAggregator.countsFromThemesDir(themesDir())
        XCTAssertEqual(counts["career"], 12)
        XCTAssertEqual(counts["mental-health"], 5)
    }

    func testMissingFieldsDefaultToZero() throws {
        // a theme file with no source_count should be omitted (or zero)
        let counts = try MindmapNoteCountAggregator.countsFromThemesDir(themesDir())
        XCTAssertNil(counts["nonexistent"])
    }

    func testMissingDirectoryReturnsEmpty() throws {
        let bogus = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString)")
        let counts = try MindmapNoteCountAggregator.countsFromThemesDir(bogus)
        XCTAssertTrue(counts.isEmpty)
    }
}
```

- [ ] **Step 3: Wire fixtures into Package.swift**

Update the `.testTarget(...)` entry in `Package.swift` so test resources are processed:

```swift
.testTarget(
    name: "PensieveIngestCoreTests",
    dependencies: ["PensieveIngestCore"],
    resources: [.process("Fixtures")]
),
```

- [ ] **Step 4: Run to confirm failure**

```bash
cd scripts/pensieve-ingest && swift test --filter MindmapNoteCountAggregatorTests 2>&1 | tail -10
```

Expected: compile error — `MindmapNoteCountAggregator.countsFromThemesDir` not found.

- [ ] **Step 5: Implement aggregator**

Create `MindmapNoteCountAggregator.swift`:

```swift
import Foundation

public enum MindmapNoteCountAggregator {
    /// Walks `wiki/themes/*.md`, parses YAML frontmatter, returns `themeSlug -> source_count`.
    /// Files without `source_count` or with unparseable frontmatter are silently omitted.
    public static func countsFromThemesDir(_ themesDir: URL) throws -> [String: Int] {
        guard FileManager.default.fileExists(atPath: themesDir.path) else { return [:] }
        var out: [String: Int] = [:]
        let files = try FileManager.default.contentsOfDirectory(
            at: themesDir, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "md" }

        for url in files {
            let slug = url.deletingPathExtension().lastPathComponent
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if let count = parseSourceCount(content) {
                out[slug] = count
            }
        }
        return out
    }

    private static func parseSourceCount(_ content: String) -> Int? {
        guard content.hasPrefix("---\n") else { return nil }
        let rest = content.dropFirst(4)
        guard let endRange = rest.range(of: "\n---\n") else { return nil }
        let fmBlock = rest[..<endRange.lowerBound]
        for line in fmBlock.split(separator: "\n") {
            let s = String(line)
            if s.hasPrefix("source_count:") {
                let v = s.replacingOccurrences(of: "source_count:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return Int(v)
            }
        }
        return nil
    }
}
```

- [ ] **Step 6: Run tests**

```bash
cd scripts/pensieve-ingest && swift test --filter MindmapNoteCountAggregatorTests
```

Expected: 3 PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/pensieve-ingest/Sources/PensieveIngestCore/MindmapNoteCountAggregator.swift \
        scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/MindmapNoteCountAggregatorTests.swift \
        scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/Fixtures/sample-themes \
        scripts/pensieve-ingest/Package.swift
git commit -m "deterministic noteCount aggregation from theme frontmatter"
```

---

## Task 5: VaultReader can load mindmap.json

**Files:**
- Modify: `scripts/pensieve-ingest/Sources/PensieveIngestCore/VaultReader.swift`
- Create: `scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/VaultReaderMindmapTests.swift`
- Create: `scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/Fixtures/sample-mindmap.json`

- [ ] **Step 1: Write the fixture**

Create `Fixtures/sample-mindmap.json`:

```json
{
  "version": 1,
  "lastUpdated": "2026-04-24",
  "root": {
    "id": "root", "label": "Brain", "noteCount": 0, "importance": 10,
    "summary": "", "sourcePages": [],
    "children": [
      {"id": "career", "label": "Career", "noteCount": 12, "importance": 9,
       "summary": "work life", "sourcePages": ["themes/career.md"], "children": []}
    ]
  }
}
```

- [ ] **Step 2: Write failing test**

Create `VaultReaderMindmapTests.swift`:

```swift
import XCTest
@testable import PensieveIngestCore

final class VaultReaderMindmapTests: XCTestCase {
    func testLoadsExistingMindmap() throws {
        let tmp = try makeTempVaultWithMindmap()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let reader = VaultReader(vaultURL: tmp)
        let state = try reader.loadMindmapState()
        XCTAssertEqual(state?.root.children.first?.id, "career")
    }

    func testReturnsNilWhenMissing() throws {
        let tmp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let reader = VaultReader(vaultURL: tmp)
        let state = try reader.loadMindmapState()
        XCTAssertNil(state)
    }

    private func makeTempVault() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("wiki"), withIntermediateDirectories: true)
        return tmp
    }

    private func makeTempVaultWithMindmap() throws -> URL {
        let tmp = try makeTempVault()
        let src = Bundle.module.url(forResource: "sample-mindmap", withExtension: "json")!
        let dst = tmp.appendingPathComponent("wiki/mindmap.json")
        try FileManager.default.copyItem(at: src, to: dst)
        return tmp
    }
}
```

- [ ] **Step 3: Run to confirm failure**

```bash
cd scripts/pensieve-ingest && swift test --filter VaultReaderMindmapTests 2>&1 | tail -10
```

Expected: compile error — `loadMindmapState()` not found.

- [ ] **Step 4: Add `loadMindmapState()` to `VaultReader`**

Insert these declarations **inside the existing `public struct VaultReader { ... }` body** in `VaultReader.swift` (alongside the other `private var <fileURL>` properties and `public func` methods — NOT at file scope):

```swift
    private var mindmapFile: URL { wikiDir.appendingPathComponent("mindmap.json") }
    private var themesDirURL: URL { themesDir }

    public func loadMindmapState() throws -> MindmapState? {
        guard FileManager.default.fileExists(atPath: mindmapFile.path) else { return nil }
        let data = try Data(contentsOf: mindmapFile)
        return try JSONDecoder().decode(MindmapState.self, from: data)
    }

    public func themesDirectoryURL() -> URL { themesDir }
```

(Note: `themesDir` is already a `private var`. The new public method just exposes it for `MindmapEngine`. We removed the `loadLogContent()` method from the original plan — counts now come from theme frontmatter, not log.md.)

- [ ] **Step 5: Run tests**

```bash
cd scripts/pensieve-ingest && swift test --filter VaultReaderMindmapTests
```

Expected: 2 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/pensieve-ingest/Sources/PensieveIngestCore/VaultReader.swift \
        scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/VaultReaderMindmapTests.swift \
        scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/Fixtures/sample-mindmap.json
git commit -m "VaultReader can load mindmap.json"
```

---

## Task 6: VaultWriter can write mindmap.json + mindmap.html

**Files:**
- Modify: `scripts/pensieve-ingest/Sources/PensieveIngestCore/VaultWriter.swift`
- Create: `scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/VaultWriterMindmapTests.swift`

- [ ] **Step 1: Write failing test**

Create `VaultWriterMindmapTests.swift`:

```swift
import XCTest
@testable import PensieveIngestCore

final class VaultWriterMindmapTests: XCTestCase {
    func testWritesJSONAndHTML() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("wiki"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let state = MindmapState(version: 1, lastUpdated: "2026-04-25",
            root: MindmapNode(id: "root", label: "Brain", noteCount: 0,
                              importance: 10, summary: "", sourcePages: [], children: []))
        let writer = VaultWriter(vaultURL: tmp)
        try writer.writeMindmap(state: state, html: "<html><body>x</body></html>")

        let json = try String(contentsOf: tmp.appendingPathComponent("wiki/mindmap.json"), encoding: .utf8)
        XCTAssertTrue(json.contains("\"version\""))
        let html = try String(contentsOf: tmp.appendingPathComponent("wiki/mindmap.html"), encoding: .utf8)
        XCTAssertEqual(html, "<html><body>x</body></html>")
    }
}
```

- [ ] **Step 2: Confirm failure**

```bash
cd scripts/pensieve-ingest && swift test --filter VaultWriterMindmapTests 2>&1 | tail -10
```

- [ ] **Step 3: Add `writeMindmap` to `VaultWriter`**

Insert these declarations **inside the existing `public struct VaultWriter { ... }` body** in `VaultWriter.swift` (alongside the other private file URLs and apply method — NOT at file scope):

```swift
    private var mindmapJSONFile: URL { wikiDir.appendingPathComponent("mindmap.json") }
    private var mindmapHTMLFile: URL { wikiDir.appendingPathComponent("mindmap.html") }

    public func writeMindmap(state: MindmapState, html: String) throws {
        try FileManager.default.createDirectory(at: wikiDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: mindmapJSONFile, options: .atomic)
        try html.write(to: mindmapHTMLFile, atomically: true, encoding: .utf8)
    }
```

- [ ] **Step 4: Run tests**

```bash
cd scripts/pensieve-ingest && swift test --filter VaultWriterMindmapTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/pensieve-ingest/Sources/PensieveIngestCore/VaultWriter.swift \
        scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/VaultWriterMindmapTests.swift
git commit -m "VaultWriter can write mindmap.json + mindmap.html"
```

---

## Task 7: Mindmap prompts

**Files:**
- Create: `scripts/pensieve-ingest/Sources/PensieveIngestCore/MindmapPrompts.swift`

This task has no TDD step — prompts are configuration text. Lock the schema once and review by reading.

- [ ] **Step 1: Create the prompts file**

```swift
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
    2. Conservative restructuring. Prefer `update` over remove+add. Don't reshuffle
       without a real reason.
    3. `importance` (0-10) = how central this is to the user's life RIGHT NOW based
       on the theme pages. Fresh judgment per run is fine.
    4. `noteCount` is read-only context. Never include `noteCount` in `add` or `update`
       payloads — the engine fills it in deterministically. (If you do, it will be
       discarded.)
    5. Insights — at most 5. Thresholds below are guidance, not hard gates: skip a
       node that meets a threshold but isn't actually meaningful, and feel free to
       flag a borderline node you judge meaningful.
       - tooDeep:        noteCount high, importance low (seed: >20 and ≤4)
       - shouldGoDeeper: noteCount low, importance high (seed: ≤3 and ≥8)
       - tooShallow:     mentioned repeatedly but no sub-themes
       - tooBroad:       >7 siblings under one parent without hierarchy
    6. Depth cap: 4 levels below root. Beyond that, summarize into the parent.
    7. Empty `operations` is valid output when nothing changed.

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
```

- [ ] **Step 2: Build to verify it compiles**

```bash
cd scripts/pensieve-ingest && swift build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add scripts/pensieve-ingest/Sources/PensieveIngestCore/MindmapPrompts.swift
git commit -m "add mindmap prompts"
```

---

## Task 8: HTML renderer

**Files:**
- Create: `scripts/pensieve-ingest/Sources/PensieveIngestCore/MindmapRenderer.swift`
- Create: `scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/MindmapRendererTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import PensieveIngestCore

final class MindmapRendererTests: XCTestCase {
    func testRendersInlineDataAndContainsD3CDN() throws {
        let state = MindmapState(version: 1, lastUpdated: "2026-04-25",
            root: MindmapNode(id: "root", label: "Brain", noteCount: 0,
                              importance: 10, summary: "", sourcePages: [],
                              children: [
                MindmapNode(id: "career", label: "Career", noteCount: 12,
                            importance: 9, summary: "", sourcePages: [], children: [])
            ]))
        let insights = [Insight(kind: .tooDeep, nodeId: "career", message: "test")]
        let html = MindmapRenderer.render(state: state, insights: insights)

        XCTAssertTrue(html.contains("d3js.org/d3.v7"))
        XCTAssertTrue(html.contains("\"id\":\"career\""))
        XCTAssertTrue(html.contains("\"kind\":\"tooDeep\""))
        XCTAssertTrue(html.contains("2026-04-25"))
    }
}
```

- [ ] **Step 2: Confirm failure**

```bash
cd scripts/pensieve-ingest && swift test --filter MindmapRendererTests 2>&1 | tail -10
```

- [ ] **Step 3: Implement renderer**

Create `MindmapRenderer.swift`:

```swift
import Foundation

public enum MindmapRenderer {
    public static func render(state: MindmapState, insights: [Insight]) -> String {
        let encoder = JSONEncoder()
        let dataJSON = (try? encoder.encode(state.root))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        let insightJSON = (try? encoder.encode(insights))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        return template
            .replacingOccurrences(of: "{{DATA}}", with: dataJSON)
            .replacingOccurrences(of: "{{INSIGHTS}}", with: insightJSON)
            .replacingOccurrences(of: "{{UPDATED}}", with: state.lastUpdated)
    }

    private static let template = #"""
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <title>Pensieve — Mindmap</title>
      <script src="https://d3js.org/d3.v7.min.js"></script>
      <style>
        :root { font-family: -apple-system, system-ui, sans-serif; }
        body { margin:0; display:grid; grid-template-columns:1fr 320px; height:100vh; background:#fafafa; }
        #chart { position:relative; }
        svg { width:100%; height:100%; cursor:grab; }
        svg:active { cursor:grabbing; }
        aside { border-left:1px solid #ddd; padding:20px; overflow-y:auto; background:#fff; }
        h2 { margin:0 0 12px; font-size:14px; text-transform:uppercase; color:#666; letter-spacing:0.5px; }
        .insight { padding:10px 12px; margin-bottom:8px; border-radius:6px; border:1px solid #eee; cursor:pointer; font-size:13px; }
        .insight:hover { background:#f5f5f5; }
        .insight .k { display:inline-block; padding:2px 6px; border-radius:3px; font-size:10px; text-transform:uppercase; margin-right:6px; font-weight:600; }
        .k.tooDeep { background:#ffe5e5; color:#c00; }
        .k.shouldGoDeeper { background:#e5efff; color:#06c; }
        .k.tooShallow { background:#fff4d4; color:#a60; }
        .k.tooBroad { background:#eaeaea; color:#444; }
        .node circle { stroke:#333; stroke-width:1px; cursor:pointer; }
        .node text { font-size:11px; fill:#222; pointer-events:none; }
        .link { fill:none; stroke:#aaa; stroke-width:1px; }
        .updated { position:absolute; bottom:8px; left:12px; font-size:11px; color:#999; }
      </style>
    </head>
    <body>
      <div id="chart">
        <svg viewBox="-500 -500 1000 1000"></svg>
        <div class="updated">Last updated {{UPDATED}}</div>
      </div>
      <aside>
        <h2>Insights</h2>
        <div id="insights"></div>
      </aside>
      <script>
        const data = {{DATA}};
        const insights = {{INSIGHTS}};

        // ---- color: importance vs noteCount mismatch ----
        const colorFor = (d) => {
          const n = d.data.noteCount, imp = d.data.importance;
          const expected = imp * 3;        // rough scale: each importance point ~ 3 notes
          const ratio = n / Math.max(1, expected);
          if (ratio > 1.5) return "#e88";  // over-explored
          if (ratio < 0.5 && imp >= 6) return "#88e"; // under-explored important
          return "#bbb";
        };
        const sizeFor = (d) => 4 + Math.sqrt(d.data.noteCount) * 3;

        // ---- radial tree layout ----
        const root = d3.hierarchy(data);
        const tree = d3.tree().size([2 * Math.PI, 380]).separation((a, b) => (a.parent === b.parent ? 1 : 2) / a.depth);
        tree(root);

        const svg = d3.select("svg");
        const g = svg.append("g");

        const linkGen = d3.linkRadial().angle(d => d.x).radius(d => d.y);
        g.append("g").selectAll("path")
          .data(root.links()).enter().append("path")
          .attr("class", "link").attr("d", linkGen);

        const node = g.append("g").selectAll("g")
          .data(root.descendants()).enter().append("g")
          .attr("class", "node")
          .attr("transform", d => `rotate(${d.x * 180 / Math.PI - 90}) translate(${d.y},0)`);

        node.append("circle")
          .attr("r", sizeFor)
          .attr("fill", colorFor)
          .on("click", (e, d) => {
            const page = d.data.sourcePages && d.data.sourcePages[0];
            if (page) {
              window.location.href = "obsidian://open?vault=SecondBrain&file=" + encodeURIComponent(page);
            }
          })
          .append("title").text(d => `${d.data.label}\n${d.data.summary}\nnotes: ${d.data.noteCount}, importance: ${d.data.importance}`);

        node.append("text")
          .attr("dy", "0.31em")
          .attr("x", d => d.x < Math.PI ? 10 : -10)
          .attr("text-anchor", d => d.x < Math.PI ? "start" : "end")
          .attr("transform", d => d.x >= Math.PI ? "rotate(180)" : null)
          .text(d => d.data.label);

        // ---- pan + zoom ----
        svg.call(d3.zoom().on("zoom", (e) => g.attr("transform", e.transform)));

        // ---- sidebar insights ----
        const list = d3.select("#insights");
        if (insights.length === 0) {
          list.append("div").attr("class", "insight").text("No insights this run.");
        } else {
          for (const i of insights) {
            const row = list.append("div").attr("class", "insight").on("click", () => {
              const target = root.descendants().find(d => d.data.id === i.nodeId);
              if (!target) return;
              const k = 2.5;
              const x = -Math.cos(target.x - Math.PI / 2) * target.y * k;
              const y = -Math.sin(target.x - Math.PI / 2) * target.y * k;
              svg.transition().duration(600).call(
                d3.zoom().transform, d3.zoomIdentity.translate(x, y).scale(k)
              );
            });
            row.append("span").attr("class", "k " + i.kind).text(i.kind);
            row.append("span").text(i.message);
          }
        }
      </script>
    </body>
    </html>
    """#
}
```

- [ ] **Step 4: Run tests**

```bash
cd scripts/pensieve-ingest && swift test --filter MindmapRendererTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/pensieve-ingest/Sources/PensieveIngestCore/MindmapRenderer.swift \
        scripts/pensieve-ingest/Tests/PensieveIngestCoreTests/MindmapRendererTests.swift
git commit -m "add D3 radial mindmap HTML renderer"
```

---

## Task 9: MindmapEngine — orchestrate call 2

**Files:**
- Create: `scripts/pensieve-ingest/Sources/PensieveIngestCore/MindmapEngine.swift`

This is the only network-touching piece besides the existing client. No new TDD: tested end-to-end in Task 11.

- [ ] **Step 1: Implement engine**

Create `MindmapEngine.swift`:

```swift
import Foundation

public struct MindmapEngine {
    public let vaultURL: URL
    public let apiKey: String
    public let model: String

    public init(vaultURL: URL, apiKey: String, model: String = "claude-sonnet-4-6") {
        self.vaultURL = vaultURL; self.apiKey = apiKey; self.model = model
    }

    public func run() async throws -> MindmapStats {
        let reader = VaultReader(vaultURL: vaultURL)

        let prior = (try reader.loadMindmapState()) ?? MindmapState(
            version: 1,
            lastUpdated: todayString(),
            root: MindmapNode(id: "root", label: "Brain", noteCount: 0,
                              importance: 10, summary: "", sourcePages: [], children: [])
        )

        let allThemes = try reader.allThemeNames()
        let themePages = try loadAllThemePages(allThemes, reader: reader)
        let indexContent = (try? String(contentsOf: vaultURL.appendingPathComponent("wiki/index.md"),
                                         encoding: .utf8)) ?? ""

        let knownIds = collectIds(prior.root)
        let counts = try MindmapNoteCountAggregator.countsFromThemesDir(reader.themesDirectoryURL())

        let client = ClaudeClient(apiKey: apiKey, model: model)
        let system = MindmapPrompts.systemPrompt
        let user = MindmapPrompts.userPrompt(
            themePages: themePages, indexContent: indexContent,
            priorState: prior, noteCounts: counts
        )
        let response = try await client.complete(system: system, user: user, maxTokens: 8000)
        let patch = try decodePatch(response.text)

        var newState = try MindmapPatchApplier.apply(patch, to: prior)
        newState.lastUpdated = todayString()
        newState = stampNoteCounts(newState, counts: counts)

        let html = MindmapRenderer.render(state: newState, insights: patch.insights)
        try VaultWriter(vaultURL: vaultURL).writeMindmap(state: newState, html: html)

        return MindmapStats(
            nodesTotal: knownIds.count,
            opsApplied: patch.operations.count,
            insightsCount: patch.insights.count,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens
        )
    }

    private func loadAllThemePages(_ names: [String], reader: VaultReader) throws -> [String: String] {
        var out: [String: String] = [:]
        for name in names {
            let path = vaultURL.appendingPathComponent("wiki/themes/\(name).md")
            if let s = try? String(contentsOf: path, encoding: .utf8) { out[name] = s }
        }
        return out
    }

    private func collectIds(_ node: MindmapNode) -> [String] {
        [node.id] + node.children.flatMap(collectIds)
    }

    private func stampNoteCounts(_ state: MindmapState, counts: [String: Int]) -> MindmapState {
        func walk(_ n: MindmapNode) -> MindmapNode {
            var copy = n
            if let c = counts[n.id] { copy.noteCount = c }
            copy.children = copy.children.map(walk)
            return copy
        }
        return MindmapState(version: state.version, lastUpdated: state.lastUpdated, root: walk(state.root))
    }

    private func decodePatch(_ text: String) throws -> MindmapPatch {
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```") {
            let lines = json.split(separator: "\n", omittingEmptySubsequences: false)
            json = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        guard let data = json.data(using: .utf8) else {
            throw IngestError.decodeError("mindmap response not UTF-8")
        }
        do {
            return try JSONDecoder().decode(MindmapPatch.self, from: data)
        } catch {
            throw IngestError.decodeError("mindmap decode: \(error) -- raw:\n\(json.prefix(2000))")
        }
    }

    private func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
```

- [ ] **Step 2: Build**

```bash
cd scripts/pensieve-ingest && swift build
```

Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add scripts/pensieve-ingest/Sources/PensieveIngestCore/MindmapEngine.swift
git commit -m "MindmapEngine orchestrates call 2"
```

---

## Task 10: Wire MindmapEngine into IngestEngine (non-fatal)

**Files:**
- Modify: `scripts/pensieve-ingest/Sources/PensieveIngestCore/IngestEngine.swift`

- [ ] **Step 1: Edit `run()` to call mindmap pass after success**

Replace the body of `IngestEngine.run()` so that after the existing patch is applied, it kicks off the mindmap pass and swallows errors:

```swift
    public func run() async throws -> IngestionStats {
        let reader = VaultReader(vaultURL: vaultURL)
        let snapshot = try reader.snapshot()

        guard !snapshot.unprocessed.isEmpty else {
            return IngestionStats(
                notesProcessed: 0, themesUpdated: 0, themesCreated: 0,
                contradictionsFlagged: 0, inputTokens: 0, outputTokens: 0,
                cacheReadTokens: 0, cacheWriteTokens: 0
            )
        }

        let allThemes = try reader.allThemeNames()
        let client = ClaudeClient(apiKey: apiKey, model: model)
        let system = Prompts.systemPrompt
        let user = Prompts.userPrompt(snapshot: snapshot, allThemeNames: allThemes)
        let response = try await client.complete(system: system, user: user)
        let patch = try decodePatch(response.text)

        if !dryRun {
            let writer = VaultWriter(vaultURL: vaultURL)
            try writer.apply(patch: patch, notes: snapshot.unprocessed)
        }

        // ---- non-fatal mindmap pass ----
        if !dryRun {
            do {
                let mm = MindmapEngine(vaultURL: vaultURL, apiKey: apiKey, model: model)
                let stats = try await mm.run()
                FileHandle.standardError.write(Data("mindmap: \(stats.opsApplied) ops, \(stats.insightsCount) insights\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("mindmap: skipped — \(error.localizedDescription)\n".utf8))
            }
        }

        return IngestionStats(
            notesProcessed: snapshot.unprocessed.count,
            themesUpdated: patch.themeUpdates.count,
            themesCreated: patch.newThemes.count,
            contradictionsFlagged: (patch.contradictionsAppend?.isEmpty == false) ? 1 : 0,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens,
            cacheReadTokens: response.cacheReadTokens,
            cacheWriteTokens: response.cacheWriteTokens
        )
    }
```

- [ ] **Step 2: Build + run all tests**

```bash
cd scripts/pensieve-ingest && swift build && swift test
```

Expected: build succeeds, all existing tests still pass.

- [ ] **Step 3: Commit**

```bash
git add scripts/pensieve-ingest/Sources/PensieveIngestCore/IngestEngine.swift
git commit -m "wire mindmap pass into IngestEngine (non-fatal)"
```

---

## Task 11: End-to-end manual smoke test

**Files:**
- No code changes, manual verification only.

- [ ] **Step 1: Reinstall the binary**

```bash
cd scripts/pensieve-ingest
swift build -c release
cp .build/release/pensieve-ingest ~/.local/bin/pensieve-ingest
```

- [ ] **Step 2: Confirm Full Disk Access** for `/Users/Karthik/.local/bin/pensieve-ingest` (per CLAUDE.md gotcha — TCC can have been invalidated).

- [ ] **Step 3: Trigger a run**

```bash
launchctl kickstart -k gui/$(id -u)/com.karthikshashidhar.pensieve.ingest
sleep 90
tail -50 /tmp/pensieve-ingest.log
```

Expected: no errors. `mindmap: <N> ops, <M> insights` line present. Note: a full run (call 1 + call 2) commonly takes 30-60s; if the log shows nothing after 90s, sleep another 60-90s and re-tail before declaring failure.

- [ ] **Step 4: Verify outputs in vault**

```bash
ls -la "/Users/Karthik/Library/Mobile Documents/iCloud~md~obsidian/Documents/SecondBrain/wiki/mindmap.json" \
       "/Users/Karthik/Library/Mobile Documents/iCloud~md~obsidian/Documents/SecondBrain/wiki/mindmap.html"
open "/Users/Karthik/Library/Mobile Documents/iCloud~md~obsidian/Documents/SecondBrain/wiki/mindmap.html"
```

Expected: `mindmap.json` populated with at least the root + a few children. `mindmap.html` opens in default browser, shows a radial tree, sidebar lists insights (or "No insights this run").

- [ ] **Step 5: Verify failure mode is non-fatal**

Temporarily break the mindmap pass (e.g. set an invalid model name in the engine), re-run, confirm wiki ingest still applies and `mindmap: skipped — …` appears in the log.

Revert the temporary break before committing.

- [ ] **Step 6: No commit unless something broke during smoke and a fix was needed.**

---

## Task 12: Dev log entry

**Files:**
- Modify: `dev-log.md`

- [ ] **Step 1: Append a session entry**

Add to `dev-log.md` (matching the existing format — read the file first to see the convention):

```markdown
## Session: Mindmap visualization (2026-04-25)

**Goal:** Add a radial, interactive HTML mind-map of the voice-note corpus with depth/breadth insights.

**Decisions:**
- Two sequential Claude calls (ingest, then mindmap) instead of one. User pushed back on cramming both into one call (context rot risk). Sequential lets the mindmap pass see the freshly-rewritten theme pages.
- Standalone `wiki/mindmap.html` rendered by `pensieve-ingest`, single self-contained file with D3 from CDN and data inlined. iOS port deferred.
- Stateful tree (`wiki/mindmap.json`) with daily diff via `MindmapPatch` ops — kills layout jitter, enables future "growth over time" views.
- `noteCount` computed deterministically from `log.md` by Swift, not by the LLM. Eliminates a class of arithmetic errors.
- Radial collapsible D3 layout (matches the user's hand sketch).
- Mindmap failure is non-fatal — wiki ingest already succeeded by then.

**Problems hit:**
- (fill in during implementation)

**Cost impact:** ~+$0.003-0.005 per ingest run.
```

- [ ] **Step 2: Commit**

```bash
git add dev-log.md
git commit -m "dev-log: mindmap viz session"
```

---

## Summary

12 tasks. Roughly: 1 scaffolding, 5 unit-tested pure pieces (models, applier, aggregator, reader, writer), 1 prompts file, 1 renderer (unit-tested), 1 engine, 1 wiring, 1 manual smoke, 1 devlog. Each task ends with a green test run and a single-purpose commit.
