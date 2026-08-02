# Automatic Agent Folders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically persist existing standard agent folders while honoring a durable user removal choice.

**Architecture:** Extend source persistence with one atomic configuration that contains both sources and excluded automatic URLs. Inject account-home and filesystem checks into the main-actor library model, merge eligible standard locations during restore, and update the exclusion set transactionally during add/remove operations.

**Tech Stack:** Swift 6, Swift Testing, Observation, Foundation JSON persistence, macOS 15+

## Global Constraints

- Keep filesystem checks injectable and independent of real user files in tests.
- Resolve standard paths from `UserHomeDirectory`; never use `FileManager.homeDirectoryForCurrentUser`.
- De-duplicate sources by standardized URL, including the shared Global/Codex path.
- Keep configured path data owner-only and never log user-specific absolute paths.
- Do not create a pull request until QA and Security reviews are complete.

---

### Task 1: Persist automatic-folder exclusions atomically

**Files:**
- Modify: `Packages/SkillsCore/Sources/SkillsCore/Persistence/SkillSourceStore.swift`
- Modify: `Packages/SkillsCore/Tests/SkillsCoreTests/Persistence/JSONSkillSourceStoreTests.swift`

**Interfaces:**
- Consumes: existing `SkillSource` values and legacy top-level JSON arrays.
- Produces: `SkillSourceConfiguration`, `loadConfiguration()`, and `save(_ configuration:)` while retaining `loadSources()` and `save(_ sources:)`.

- [ ] **Step 1: Write failing configuration persistence tests**

```swift
let configuration = SkillSourceConfiguration(
    sources: [source],
    excludedAutomaticDirectoryURLs: [URL(filePath: "/skills/cursor")]
)
try await store.save(configuration)
#expect(try await store.loadConfiguration() == configuration)
```

Also write a literal legacy-array fixture and verify that it decodes with an
empty exclusion set, and verify a source-only save preserves existing
exclusions.

- [ ] **Step 2: Run the focused package test and verify RED**

Run: `swift test --package-path Packages/SkillsCore --filter JSONSkillSourceStoreTests`

Expected: compilation fails because `SkillSourceConfiguration` and the
configuration methods do not exist.

- [ ] **Step 3: Implement the configuration schema and JSON migration**

```swift
public struct SkillSourceConfiguration: Equatable, Sendable {
    public var sources: [SkillSource]
    public var excludedAutomaticDirectoryURLs: Set<URL>
}
```

Add protocol requirements with source-only defaults. Make the JSON actor decode
the object first, fall back to `[SkillSource]`, sort exclusion URLs before
encoding, and preserve `0700`/`0600` permissions.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `swift test --package-path Packages/SkillsCore --filter JSONSkillSourceStoreTests`

Expected: all persistence tests pass with zero failures.

- [ ] **Step 5: Commit the persistence slice**

```text
git add Packages/SkillsCore/Sources/SkillsCore/Persistence/SkillSourceStore.swift Packages/SkillsCore/Tests/SkillsCoreTests/Persistence/JSONSkillSourceStoreTests.swift
git commit -m "feat(persistence): store automatic folder exclusions (VOLVOX-25)"
```

### Task 2: Merge existing standard folders during restore

**Files:**
- Modify: `SkillsManager/App/SkillsManagerApp.swift`
- Modify: `SkillsManager/App/SkillLibraryModel.swift`
- Modify: `Tests/SkillsManagerTests/App/SkillLibraryModelTests.swift`

**Interfaces:**
- Consumes: `SkillAgent.defaultSkillsDirectory(in:)`, injected account home,
  injected `(URL) -> Bool`, and `SkillSourceConfiguration`.
- Produces: restore-time automatic source merging without changing
  `sidebarSelection`.

- [ ] **Step 1: Write failing restore regression tests**

```swift
let model = makeModel(
    sourceStore: store,
    homeDirectory: homeDirectory,
    directoryExists: existenceCheck(for: [.claudeCode, .cursor])
)
await model.restoreSources()
#expect(model.sources.map(\.agent) == [.claudeCode, .cursor])
```

Add separate tests for missing directories, a nil home, persisted URL
de-duplication, and Global/Codex sharing one URL assigned to Global.

- [ ] **Step 2: Run the app test and verify RED**

Run: `xcodebuild test -project SkillsManager.xcodeproj -scheme SkillsManager -destination 'platform=macOS' -only-testing:SkillsManagerTests/SkillLibraryModelTests`

Expected: compilation fails because the model has no automatic-discovery
dependencies and restore does not merge candidates.

- [ ] **Step 3: Implement minimal restore-time discovery**

Add `homeDirectory` and `directoryExists` injected dependencies. Derive unique
standard candidates in `SkillAgent.allCases` order, filter to existing and
non-excluded URLs, append them before the single persistence write, initialize
their state as available, and scan through the existing source loop.

Production composition passes `UserHomeDirectory.current` and
`AgentDirectorySuggestion.directoryExists(at:)`.

- [ ] **Step 4: Run the focused app test and verify GREEN**

Run the same `xcodebuild test` command.

Expected: every `SkillLibraryModelTests` test passes.

- [ ] **Step 5: Commit the restore slice**

```text
git add SkillsManager/App/SkillsManagerApp.swift SkillsManager/App/SkillLibraryModel.swift Tests/SkillsManagerTests/App/SkillLibraryModelTests.swift
git commit -m "feat(library): discover existing agent folders (VOLVOX-25)"
```

### Task 3: Make removal a durable opt-out

**Files:**
- Modify: `SkillsManager/App/SkillLibraryModel.swift`
- Modify: `Tests/SkillsManagerTests/App/SkillLibraryModelTests.swift`

**Interfaces:**
- Consumes: normalized standard-directory URLs and the configuration exclusion set.
- Produces: atomic exclusion on remove, exclusion clearing on manual add, and rollback on save failure.

- [ ] **Step 1: Write failing removal and re-add tests**

```swift
try await firstModel.removeSource(automaticallyAdded.id)
let secondModel = makeModel(sourceStore: store, homeDirectory: homeDirectory, directoryExists: { _ in true })
await secondModel.restoreSources()
#expect(secondModel.sources.isEmpty)
```

Add tests proving manual `addSource` clears the exclusion, custom removal does
not add one, and a failed save restores both the source and prior exclusion set.

- [ ] **Step 2: Run the focused app test and verify RED**

Run the Task 2 `xcodebuild test` command.

Expected: a removed standard folder is automatically restored by a fresh model.

- [ ] **Step 3: Implement transactional add/remove behavior**

Normalize standard URLs independent of current disk existence. Add the URL to
the exclusion set before the removal configuration save; remove it before the
manual-add save. Extend existing snapshots and catch blocks to restore the prior
set when persistence fails.

- [ ] **Step 4: Run the focused app test and verify GREEN**

Run the Task 2 `xcodebuild test` command.

Expected: every focused test passes with zero failures.

- [ ] **Step 5: Commit the opt-out slice**

```text
git add SkillsManager/App/SkillLibraryModel.swift Tests/SkillsManagerTests/App/SkillLibraryModelTests.swift
git commit -m "feat(settings): remember removed agent folders (VOLVOX-25)"
```

### Task 4: Documentation and final verification

**Files:**
- Modify: `README.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: the completed startup-discovery, persistence, removal, and manual re-add behavior.
- Produces: current user and agent documentation plus verification evidence for review.

- [ ] **Step 1: Update affected documentation**

Document automatic startup addition, durable removal exclusions, manual opt-in,
shared Global/Codex de-duplication, the combined owner-only JSON schema, and
injected filesystem-test policy.

- [ ] **Step 2: Run formatting and full checks**

```text
make lint
make check
git diff --check
```

Expected: all available commands exit zero with no test, generation, build, or
whitespace failures.

- [ ] **Step 3: Review the final diff and requirement coverage**

Verify every design behavior has a regression test and that no production path
reads a test user's real home or exposes absolute paths in UI copy.

- [ ] **Step 4: Commit documentation**

```text
git add README.md docs/ARCHITECTURE.md AGENTS.md CLAUDE.md
git commit -m "docs: explain automatic agent folders (VOLVOX-25)"
```

- [ ] **Step 5: Push for QA and Security review without creating a PR**

Push `agent/big-builder/volvox-25-auto-detect-folders`, report the commit and
available verification evidence on VOLVOX-25, and request the required QA and
Security reviews. Do not create a pull request in this task.
