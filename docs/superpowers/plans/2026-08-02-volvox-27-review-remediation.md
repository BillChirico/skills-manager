# VOLVOX-27 Review Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct the verified security and macOS UX gaps in update availability while preserving the approved isolated `skills@1.5.21` probe and leaving launch-consent policy unchanged pending a product decision.

**Architecture:** Keep process containment and parsing in `SkillsCore`, but remove the unused child-writable stdout artifact and only project lock results into the one shared global destination whose identity the v3 lock can truthfully imply. Keep refresh task ownership and user-facing state in the main-actor library model, then render persistent check/cancel controls, counted partial coverage, legible non-action status chips, and VoiceOver completion announcements in SwiftUI.

**Tech Stack:** Swift 6.2, Swift Testing, Observation, SwiftUI for macOS 15+, Foundation `Process`.

## Global Constraints

- Keep the exact command `npx --yes --package skills@1.5.21 -- skills check --global --yes` inside disposable `HOME`, `CODEX_HOME`, and `TMPDIR` directories.
- Preserve strict fail-closed lock and transcript parsing, the 1 MiB lock limit, 10,000-entry cap, 256 KiB output limit, and one-second inherited-writer drain deadline.
- Never assert update status for an installation whose identity cannot be proved from the v3 lock contract.
- Do not add Security finding 2's launch-check preference; document the residual low risk and pending product decision.
- Keep PR creation blocked pending QA, Security, and macOS build/test execution.

---

### Task 1: Harden the core probe contract

**Files:**
- Modify: `Packages/SkillsCore/Sources/SkillsCore/Installation/SkillsCLIManager.swift`
- Test: `Packages/SkillsCore/Tests/SkillsCoreTests/Installation/SkillsCLIManagerTests.swift`

**Interfaces:**
- Consumes: validated v3 `UpdateLockFile`, bounded stdout returned by `ProcessCommandRunning`.
- Produces: `SkillsCLIError.updateCheckLockMissing`, pipe-only `ProcessCommand.maximumStandardOutputBytes`, explicit `GIT_TERMINAL_PROMPT=0`, and `.agents/skills/<name>`-only `SkillUpdateAvailability` identities.

- [x] **Step 1: Write failing core regressions**

```swift
@Test("A missing global lock is distinct from a malformed lock")
func updateAvailabilityReportsMissingLock() async throws {
    await #expect(throws: SkillsCLIError.updateCheckLockMissing) {
        try await manager.checkForUpdates()
    }
}

@Test("Captured stdout remains in memory and creates no working-directory artifact")
func processOutputCaptureIsPipeOnly() async throws {
    let output = try #require(try await runner.run(command))
    #expect(output == Data("update-result".utf8))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
}
```

- [x] **Step 2: Run the focused core tests and verify the new expectations fail for the intended reasons**

Run the repository's focused `SkillsCLIManagerTests` harness. Expected failures: missing lock currently throws `.updateCheckLockInvalid`, `ProcessCommand` still requires an output URL and creates a file, five destination URLs are returned, and `GIT_TERMINAL_PROMPT` is absent.

- [x] **Step 3: Implement the minimal core changes**

```swift
case updateCheckLockMissing

let standardOutputCapture = command.maximumStandardOutputBytes.map {
    BoundedProcessOutputCapture(maximumBytes: $0)
}

environment["GIT_TERMINAL_PROMPT"] = "0"

private func updateDirectoryURLs(for skillNames: Set<String>) -> Set<URL> {
    let sharedDirectory = homeDirectory.appending(path: ".agents/skills", directoryHint: .isDirectory)
    return Set(skillNames.map { sharedDirectory.appending(path: $0, directoryHint: .isDirectory) })
}
```

- [x] **Step 4: Re-run the focused core tests**

Expected: the new regressions and all existing CLI-manager tests pass, with output-limit, cancellation, and inherited-writer behavior unchanged.

### Task 2: Make refresh state stable, cancellable, counted, and quiet for normal unavailability

**Files:**
- Modify: `SkillsManager/App/SkillLibraryModel.swift`
- Test: `Tests/SkillsManagerTests/App/SkillLibraryModelTests.swift`

**Interfaces:**
- Consumes: `SkillManaging.checkForUpdates()` and `SkillUpdateAvailability`.
- Produces: `UpdateCheckState.partial(checked:total:)`, `.unsupported`, `startUpdateAvailabilityRefresh() -> Task<Void, Never>`, `cancelUpdateAvailabilityRefresh()`, and a completion-announcement string.

- [x] **Step 1: Write failing model regressions**

```swift
@Test("A running refresh preserves the last trustworthy badges and count")
func refreshPreservesAvailabilityUntilCompletion() async throws {
    let task = model.startUpdateAvailabilityRefresh()
    await manager.waitUntilCheckStarted()
    #expect(model.updateCheckState == .checking)
    #expect(model.updatesAvailableCount == 1)
    model.cancelUpdateAvailabilityRefresh()
    await task.value
}

@Test("Partial state carries checked and total counts")
func partialUpdateCheckReportsCoverage() async {
    await model.refreshUpdateAvailability()
    #expect(model.updateCheckState == .partial(checked: 1, total: 2))
}
```

- [x] **Step 2: Run the focused model tests and verify they fail for the intended reasons**

Expected failures: refresh clears badges before awaiting, there is no owned cancellable task, partial has no counts, nil manager is idle, and missing lock or `npx` reports a modal error.

- [x] **Step 3: Implement model task ownership and state transitions**

```swift
enum UpdateCheckState: Hashable {
    case idle, checking, current, unsupported, unavailable
    case partial(checked: Int, total: Int)
}

@discardableResult
func startUpdateAvailabilityRefresh() -> Task<Void, Never>

func cancelUpdateAvailabilityRefresh()
```

Keep existing statuses while `.checking`; replace statuses in one reconciled array only when a trustworthy result arrives. Clear statuses on cancellation or failure. Map missing lock to quiet `.unavailable`, missing `npx` or manager support to quiet `.unsupported`, and reserve modal errors for malformed input, failed execution, timeout, or invalid output. Return `.idle` for an empty library instead of `0 == 0` becoming `.current`.

- [x] **Step 4: Re-run the focused model tests**

Expected: cancellation, quiet-error, counted-partial, empty-library, rescan, and stale-badge regressions all pass.

### Task 3: Correct the SwiftUI interaction and accessibility presentation

**Files:**
- Modify: `SkillsManager/Features/Library/SkillLibraryView.swift`
- Modify: `SkillsManager/Features/Library/SkillList.swift`
- Modify: `SkillsManager/Features/Library/SkillDetail.swift`

**Interfaces:**
- Consumes: model refresh/cancel methods, counted check states, current update count, and completion-announcement text.
- Produces: an always-present command-R toolbar check control, visible cancel control while checking, progress presentation, counted partial copy, row-level “Not checked” status, non-action update indicator, scoped reorder animation, and a VoiceOver announcement.

- [x] **Step 1: Add the toolbar check and cancel controls**

```swift
Button("Check for Updates", systemImage: "arrow.clockwise") {
    model.startUpdateAvailabilityRefresh()
}
.keyboardShortcut("r", modifiers: .command)
.disabled(model.updateCheckState == .checking)
```

Render a small `ProgressView` in the check control and a separate Cancel button while `.checking`, so checking remains visible and cancellable even when prior update rows remain on screen.

- [x] **Step 2: Update empty and row presentation**

Render counted partial copy, `.unsupported` Node.js guidance, a progress indicator plus Cancel action for the checking empty state, and “Not checked” on explicit `.unknown` rows. Demote the update capsule to uppercase indicator text without a filled action symbol, use primary text over an accent-tinted background, and add a stronger selected-state fill plus stroke.

- [x] **Step 3: Remove misleading update actions**

Replace detail, context, and multi-select controls that always reach `scopedUpdateUnsupported` with non-actionable “Reinstall Required” presentation and explanatory help that tells users the pinned CLI cannot safely update one agent directory.

- [x] **Step 4: Add motion and completion accessibility**

```swift
.animation(
    accessibilityReduceMotion ? nil : .snappy(duration: 0.25),
    value: model.updateCheckState
)
.onChange(of: model.updateCheckState) { oldState, newState in
    guard oldState == .checking, newState != .checking else { return }
    AccessibilityNotification.Announcement(model.updateCheckCompletionAnnouncement).post()
}
```

Expected static verification: only modern value-scoped animation and dedicated accessibility APIs are used. Runtime VoiceOver, contrast, focus, and transition validation remains a macOS QA gate.

### Task 4: Update contributor, architecture, security, and user documentation

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/SECURITY.md`
- Modify: `docs/superpowers/specs/2026-08-02-update-availability-design.md`
- Modify: `docs/superpowers/plans/2026-08-02-update-availability.md`

**Interfaces:**
- Consumes: the final core/model/UI contracts from Tasks 1–3.
- Produces: accurate operational, contributor, architecture, UX, and residual-risk documentation.

- [x] **Step 1: Hand the documentation update to the repository documentation agent**

The brief must cover the one-destination truth boundary, pipe-only output capture, quiet missing-lock/Node states, persistent check/cancel UX, counted partial coverage, explicit unknown rows, unavailable scoped updates, and Security finding 2's deferred launch-consent decision.

- [x] **Step 2: Review the documentation diff against code**

Search for stale claims about five-destination projection, clearing badges before an await, creating or persisting `update-check.stdout`, action-like update chips, and modal alerts for normal absence. Correct every mismatch before verification.

### Task 5: Verify and commit the exact local revision

**Files:**
- Verify all files changed by Tasks 1–4.

**Interfaces:**
- Consumes: complete working tree diff.
- Produces: one exact local revision for QA and Security; no push or PR.

- [x] **Step 1: Run focused regressions**

Run the focused `SkillsCLIManagerTests`, `SkillLibraryModelTests`, and sorter suite using the available Swift harness. Record exact pass/fail counts.

- [x] **Step 2: Run formatting, parsing, and diff checks**

Run repository-configured strict Swift formatting on changed Swift files, parse/type checks available on this host, `git diff --check`, and a stale-contract documentation search.

- [x] **Step 3: Review the full diff**

Verify every requested Security finding (1, 3, 4, 5), every Designer finding (1–8), and the intentional deferral of Security finding 2. Confirm no unrelated files, generated artifacts, temp homes, stdout captures, or secrets remain.

- [x] **Step 4: Commit without pushing**

```text
fix: harden update availability feedback
```

Record the full SHA and keep PR creation blocked.

- [ ] **Step 5: Route the exact SHA to QA and Security**

Ask QA to run the full macOS build, core/app test suites, inherited-writer drain regression, live real-directory before/after snapshot, contrast, VoiceOver, keyboard, cancel, and animation checks. Ask Security to re-review identity projection, pipe-only capture, quiet normal-state handling, explicit Git non-interactivity, cleanup, and the documented residual launch-consent risk.
