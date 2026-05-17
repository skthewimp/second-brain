# Pensieve TODO

Last updated: 2026-05-17

## Shareable App Architecture

Context: Pensieve started as a personal stack: iPhone capture writes raw
markdown into an Obsidian iCloud vault, then a Mac launchd job runs
`pensieve-ingest` to maintain the wiki, contradictions, and mindmap. That is
good for one trusted power user, but too fragile for sharing through TestFlight
or the App Store.

The product direction should be: keep zero-friction capture and local
transcription, but remove the Mac and Obsidian setup from the critical path.
Obsidian should become an export / browse target, not the required database.

### Architecture Decision

Prefer a local-first Apple-native architecture first:

```text
iPhone app
  capture, on-device transcription, lightweight local note state
        ↓
app-native store / CloudKit
  raw notes, processed notes, wiki state, mindmap state
        ↓
PensieveIngestCore in-app
  structured patch generation, provenance, mindmap, review artifacts
        ↓
export and browse layers
  in-app wiki, Obsidian markdown export, later MCP / backend if justified
```

Only move to a hosted backend if real usage proves this needs to become a
multi-user paid product with centralized ingestion, billing, retries, and web
surfaces.

### Phase 1: Shareable Without SaaS

- [ ] Import `PensieveIngestCore` into the iOS app as a local Swift package
      dependency.
- [ ] Add a storage abstraction so ingestion no longer assumes direct
      filesystem access to an Obsidian vault.
- [ ] Implement an app-native store for raw notes, wiki state, contradictions,
      frameworks, timeline, log, and mindmap state.
- [ ] Add optional CloudKit private database sync for a user's own devices.
- [ ] Move API key storage from `UserDefaults` to Keychain before sharing with
      other people.
- [ ] Add explicit privacy copy: audio stays on device, transcription text is
      sent to Claude, markdown export behavior is user-controlled.
- [ ] Add an in-app "Process Wiki Now" path that runs ingestion without the Mac
      launchd job.
- [ ] Add background ingestion with `BGProcessingTask` where possible, while
      keeping manual processing as the reliable fallback.
- [ ] Keep Obsidian support as optional export / vault writing for power users.
- [ ] Keep BYO Anthropic API key for TestFlight unless/until a backend exists.

### Phase 2: Product Backend, Only If Needed

- [ ] Decide whether Pensieve should become a hosted product rather than a
      local-first tool.
- [ ] If yes, design a backend that owns Claude calls, ingestion jobs, retry
      queues, usage limits, subscriptions, deletion, and export.
- [ ] Move canonical persistence to a server database, with generated markdown
      as an export format rather than source of truth.
- [ ] Add server-side observability for ingestion failures and costs.
- [ ] Add account deletion and full data export before any real external launch.

### Core Refactor

Introduce a storage boundary:

```swift
protocol PensieveStore {
    func saveRawNote(_ note: RawCapture) async throws
    func loadUnprocessedNotes() async throws -> [RawNote]
    func loadWikiState() async throws -> WikiState
    func applyPatch(_ patch: IngestionPatch) async throws
}
```

Initial implementations:

- [ ] `ObsidianVaultStore` for the current markdown vault behavior.
- [ ] `LocalAppStore` for app-native persistence.
- [ ] `CloudKitStore` once the local schema is stable.
- [ ] `BackendStore` only if Phase 2 happens.

### Guardrails

- [ ] Keep capture friction lower than any downstream architecture concern.
- [ ] Preserve raw notes and dated source links; interpretation must remain
      auditable.
- [ ] Treat contradictions as a trust-sensitive feature: source-backed,
      tagged, and easy to inspect.
- [ ] Do not require users to configure Obsidian, iCloud folder permissions,
      launchd, Full Disk Access, or a Mac script.
- [ ] Do not ship a shared developer-owned Claude API key in the app.
