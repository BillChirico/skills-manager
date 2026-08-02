# Update Availability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect available updates through a contained `skills@1.5.21` probe,
prioritize them in the library, and communicate their state accessibly.

**Architecture:** Extend the actor-backed CLI boundary with a structured public
result produced by running the upstream mutating check inside a disposable
home. Parse only the pinned release's reviewed output grammar and map validated
names only into exact Global URL identities under
`<account-home>/.agents/skills`; the v3 remote-tree hash cannot prove local
copies elsewhere. Apply explicit unknown/current/available state only to unique
canonical installed-URL matches on the main-actor library model, then sort and
render from `AgentSkill.hasUpdate`.

**Tech Stack:** Swift 6, Foundation `Process`, Observation, SwiftUI, Swift
Testing, macOS 15+

---

### Task 1: Specify the isolated CLI probe with focused tests

**Files:**

- Modify: `Packages/SkillsCore/Tests/SkillsCoreTests/Installation/SkillsCLIManagerTests.swift`
- Modify: `Packages/SkillsCore/Sources/SkillsCore/Installation/SkillsCLIManager.swift`

- [x] Write tests first for the exact
  `npx --yes --package skills@1.5.21 -- skills check --global --yes` command,
  isolated `HOME`, `CODEX_HOME`, and `TMPDIR`, canonical lock copy, zero/update
  output, strict rejection, input/output size limits, process errors,
  cancellation, and cleanup on every exit path.
- [x] Add pipe-only bounded in-memory stdout capture with one nonblocking reader
  and no working-directory artifact while keeping lifecycle stdout/stderr
  disconnected; cancel and await capture on caller cancellation or the
  one-second post-exit drain deadline.
- [x] Add strict version-3 lock validation and canonical encoding.
- [x] Set `GIT_TERMINAL_PROMPT=0` in the scrubbed child environment.
- [x] Add the pinned output parser and `SkillManaging.checkForUpdates()` result
  with separate checked and update-available URL sets. Because v3 records no
  per-agent identity and `skillFolderHash` is remote-tree provenance, project
  each validated name only to `.agents/skills/<validated-name>`.
- [x] Run the focused SkillsCore regressions available on a Swift-capable host,
  including real output limits and readiness-marked capture cancellation.

### Task 2: Integrate availability into model state

**Files:**

- Modify: `Packages/SkillsCore/Sources/SkillsCore/Models/AgentSkill.swift`
- Modify: `Packages/SkillsCore/Tests/SkillsCoreTests/Models/AgentSkillTests.swift`
- Modify: `SkillsManager/App/SkillLibraryModel.swift`
- Modify: `Tests/SkillsManagerTests/App/SkillLibraryModelTests.swift`

- [x] Write tests first for separate checked/update URL sets, one-URL Global
  projection, other-agent and custom same-name isolation, suppression of stale
  legacy badges on incomplete checks, canonical-identity ambiguity, successful
  URL mapping, fail-closed errors, cancellation, rescan preservation, and
  downgrade when a rescan discovers an unchecked skill.
- [x] Add explicit `SkillUpdateStatus.unknown`, `.current`, and `.available`,
  keeping nil only for pre-probe and backward-compatible legacy decoding.
- [x] Run one check after initial source restoration; preserve trustworthy
  badges while checking; expose idle, checking, counted partial, current,
  unsupported, and unavailable state; map missing lock and missing Node.js/`npx`
  to quiet normal-absence states; and keep an empty library out of all-current.
- [x] Normalize and store the last successful URL result, apply it atomically
  only to unique canonical checked-URL matches, and reapply it after successful
  rescans without exposing raw CLI output.
- [x] Add focused core and app model suite coverage; macOS execution remains the
  consolidated QA gate in Task 5.

### Task 3: Prioritize and communicate updates

**Files:**

- Modify: `Packages/SkillsCore/Sources/SkillsCore/Library/SkillLibrarySorter.swift`
- Modify: `Packages/SkillsCore/Tests/SkillsCoreTests/Library/SkillLibrarySorterTests.swift`
- Modify: `SkillsManager/Features/Library/SkillLibraryView.swift`
- Modify: `SkillsManager/Features/Library/SkillList.swift`
- Modify: `SkillsManager/Features/Library/SkillDetail.swift`

- [x] Write parameterized tests proving update-first partitioning for name,
  date-added, and agent order plus deterministic ties.
- [x] Make update availability the primary comparator and preserve the selected
  sort order inside each partition.
- [x] Keep a persistent toolbar `Check for Updates` control with Command-R and
  show a spinner plus Cancel while checking.
- [x] Replace the icon-only row state with a visible non-action `Update`
  indicator, add row-level `Not checked`, and make row, detail, context, and
  multi-select update surfaces inert `Reinstall Required` guidance that directs
  users to reinstall from a trusted source.
- [x] Distinguish idle/checking/counted-partial/current/unsupported/unavailable
  update empty states and add appropriate retry or Node.js guidance.
- [x] Post a VoiceOver completion announcement with update and coverage counts,
  and disable update-driven reorder animation when Reduce Motion is enabled.

### Task 4: Keep durable documentation current

**Files:**

- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/SECURITY.md`
- Modify: `docs/superpowers/specs/2026-08-02-update-availability-design.md`
- Modify: `docs/superpowers/plans/2026-08-02-update-availability.md`

- [x] Assign documentation to the documentation agent after APIs stabilize.
- [x] Document the temporary-home mutation boundary, strict parser, capture
  ownership and drain deadline, cleanup, URL-identity result, explicit status,
  counted partial state, other-agent/custom same-name isolation, rescan
  reconciliation, persistent check/cancel UX, quiet normal absence, accessible
  non-action update guidance, test seam, unchanged fail-closed update action,
  and Security finding 2's residual Low launch-consent risk pending a product
  decision.
- [x] Review the documentation changes against production code.

### Task 5: Verify and hand off without a PR

- [x] Run focused checks available on the current host and record the remaining
  macOS limitations without treating them as passed.
- [x] Review `git diff --check`, changed-file scope, sensitive output handling,
  cleanup paths, and pinned package usage.
- [ ] Run the complete macOS build, core/app suites, and the macOS-only inherited-
  writer drain regression. **macOS QA gate**
- [ ] Obtain QA Reviewer acceptance on the final revision. **Review gate**
- [ ] Obtain Security Reviewer acceptance on the final revision. **Security gate**
- [x] Commit the review-remediated revision; record its branch and full SHA in
  the review handoff.
- [ ] Hand the revision to macOS QA and Security Reviewer through one issue
  reply. Do not create or push a PR before both reviews complete.
- [ ] Create or push a PR only after macOS QA and both reviewer acceptances.
  **No-PR gate**
