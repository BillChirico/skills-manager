# Update Availability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect available updates through a contained `skills@1.5.21` probe,
prioritize them in the library, and communicate their state accessibly.

**Architecture:** Extend the actor-backed CLI boundary with a read-only public
result produced by running the upstream mutating check inside a disposable
home. Parse only the pinned release's reviewed output grammar. Apply the result
on the main-actor library model, then sort and render from `AgentSkill.hasUpdate`.

**Tech Stack:** Swift 6, Foundation `Process`, Observation, SwiftUI, Swift
Testing, macOS 15+

---

### Task 1: Specify the isolated CLI probe with focused tests

**Files:**

- Modify: `Packages/SkillsCore/Tests/SkillsCoreTests/Installation/SkillsCLIManagerTests.swift`
- Modify: `Packages/SkillsCore/Sources/SkillsCore/Installation/SkillsCLIManager.swift`

- [ ] Write tests first for the exact pinned command, isolated `HOME` and
  `CODEX_HOME`, canonical lock copy, zero/update output, strict rejection,
  input/output size limits, process errors, cancellation, and cleanup.
- [ ] Add a capture destination to the direct process command while keeping
  lifecycle stdout/stderr disconnected.
- [ ] Add strict version-3 lock validation and canonical encoding.
- [ ] Add the pinned output parser and `SkillManaging.checkForUpdates()`.
- [ ] Run the focused SkillsCore suite on a Swift-capable host.

### Task 2: Integrate availability into model state

**Files:**

- Modify: `Packages/SkillsCore/Sources/SkillsCore/Models/AgentSkill.swift`
- Modify: `Packages/SkillsCore/Tests/SkillsCoreTests/Models/AgentSkillTests.swift`
- Modify: `SkillsManager/App/SkillLibraryModel.swift`
- Modify: `Tests/SkillsManagerTests/App/SkillLibraryModelTests.swift`

- [ ] Write tests first for authoritative detected availability, successful
  name mapping after restore, fail-closed errors, cancellation, and detection
  preservation across rescans.
- [ ] Add optional detected availability with backward-compatible decoding.
- [ ] Run one check after initial source restoration and expose check state for
  honest empty-state messaging and retry.
- [ ] Apply results atomically and never expose raw CLI output.
- [ ] Run focused core and app model suites on macOS.

### Task 3: Prioritize and communicate updates

**Files:**

- Modify: `Packages/SkillsCore/Sources/SkillsCore/Library/SkillLibrarySorter.swift`
- Modify: `Packages/SkillsCore/Tests/SkillsCoreTests/Library/SkillLibrarySorterTests.swift`
- Modify: `SkillsManager/Features/Library/SkillList.swift`

- [ ] Write parameterized tests proving update-first partitioning for name,
  date-added, and agent order plus deterministic ties.
- [ ] Make update availability the primary comparator and preserve the selected
  sort order inside each partition.
- [ ] Replace the icon-only row state with a visible `Update` label and retain
  an explicit row accessibility announcement.
- [ ] Distinguish current/checking/unavailable update empty states and add retry.

### Task 4: Keep durable documentation current

**Files:**

- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/SECURITY.md`

- [ ] Assign documentation to the documentation agent after APIs stabilize.
- [ ] Document the temporary-home mutation boundary, strict parser, cleanup,
  sorting, UI state, test seam, and unchanged fail-closed update action.
- [ ] Review the documentation changes against production code.

### Task 5: Verify and hand off without a PR

- [ ] Run formatting/lint/tests available on the current host and record exact
  unavailable macOS checks without claiming success.
- [ ] Review `git diff --check`, changed-file scope, sensitive output handling,
  cleanup paths, and pinned package usage.
- [ ] Commit a coherent revision and record branch plus full SHA.
- [ ] Hand the revision to macOS QA and Security Reviewer through one issue
  reply. Do not create or push a PR before both reviews complete.
