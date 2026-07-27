# Folder Management Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Settings the primary folder-management entry point with a
Liquid Glass folder list and native plus/minus controls while preserving all
existing folder data and behavior.

**Architecture:** Keep `SkillLibraryModel` and persisted `SkillSource` values
unchanged. Move only picker ownership and add/remove presentation into
`SettingsView`; route the toolbar and empty states to the system Settings scene.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing, XcodeGen, macOS
15 deployment target with macOS 26 Liquid Glass availability checks.

## Global Constraints

- Preserve existing security-scoped bookmarks, source identities, storage path,
  scanning behavior, and sidebar actions.
- Use Swift Testing for unit coverage; XCTest remains reserved for UI tests.
- Use native SwiftUI controls, semantic colors, accessibility labels, keyboard
  selection, and reduced-transparency-compatible materials.
- Gate macOS 26-only Liquid Glass APIs and keep a usable macOS 15–25 fallback.
- Do not hand-edit `SkillsManager.xcodeproj/project.pbxproj`.

---

### Task 1: Drive folder selection state with tests

**Files:**
- Create: `Tests/SkillsManagerTests/Settings/FolderSettingsSelectionTests.swift`
- Modify: `SkillsManager/Features/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `[SkillSource]`.
- Produces: `FolderSettingsSelection.sourceID` and
  `mutating func reconcile(with sources: [SkillSource])`.

- [x] **Step 1: Write the failing test**

Create Swift Testing cases that preserve a valid selection, leave a populated
list unselected, and clear a selection after its source disappears.

- [x] **Step 2: Run the focused app test**

Run:

```sh
xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:SkillsManagerTests/FolderSettingsSelectionTests test
```

Expected before implementation: compilation fails because
`FolderSettingsSelection` does not exist.

- [x] **Step 3: Add the minimal selection value**

Add an internal `FolderSettingsSelection` value to `SettingsView.swift`. Its
`reconcile(with:)` method keeps an existing selected ID and clears it when the
source disappears without inventing a replacement selection.

- [x] **Step 4: Run the focused test again**

Run the same `xcodebuild` command. Expected: both selection tests pass.

- [x] **Step 5: Commit the behavior lock**

```sh
git add Tests/SkillsManagerTests/Settings/FolderSettingsSelectionTests.swift \
  SkillsManager/Features/Settings/SettingsView.swift \
  SkillsManager.xcodeproj/project.pbxproj
git commit -m "test: drive folder settings selection"
```

### Task 2: Move folder addition into Settings

**Files:**
- Modify: `SkillsManager/Features/Settings/SettingsView.swift`
- Modify: `SkillsManager/Features/Library/SkillLibraryView.swift`
- Modify: `SkillsManager/Features/Library/SkillList.swift`

**Interfaces:**
- Consumes: `SkillLibraryModel.sources`, `addSource(at:agent:)`,
  `removeSource(_:)`, `sourceState(for:)`, and `restoreSources()`.
- Produces: a selectable Settings folder list, `AgentDirectoryMenuContent`,
  Settings-owned directory importer, plus/minus controls, and Settings links
  from the toolbar and empty states.

- [x] **Step 1: Reduce the library picker to relocation**

Remove the add-purpose state and Add Directory toolbar menu from
`SkillLibraryView`. Keep `.fileImporter` for `relocateSource(_:to:)`. Keep the
`SettingsLink` as an icon-only `gearshape` utility and make Discover the
prominent primary action.

- [x] **Step 2: Route empty states to Settings**

Remove `SkillList.addDirectory` and replace `.addDirectory` empty-state actions
with a `SettingsLink` labeled "Manage Folders". Keep rescan and search actions
unchanged.

- [x] **Step 3: Build the Settings folder panel**

In `SettingsView`, use `FolderSettingsSelection` and add picker state, selected
agent, default picker URL, and pending-removal state. Render all `model.sources`
in a selectable list with folder name, agent, abbreviated path, enabled Toggle,
and readable available/scanning/unavailable state.

- [x] **Step 4: Add native plus/minus behavior**

Place the agent directory `Menu` and a disabled-until-selected minus `Button` in
the list footer. The plus menu opens the directory importer; the minus button
opens a destructive confirmation whose message explicitly says files remain on
disk.

- [x] **Step 5: Preserve error and restore paths**

Call `model.restoreSources()` from a Settings task, handle picker cancellation
without mutation, report add/remove errors through `model.report`, and attach
the existing model error alert to Settings.

- [x] **Step 6: Format and compile**

Run:

```sh
swift format --configuration .swift-format --in-place \
  SkillsManager/Features/Settings/SettingsView.swift \
  SkillsManager/Features/Library/SkillLibraryView.swift \
  SkillsManager/Features/Library/SkillList.swift
make lint
make app-test
```

Expected: formatting and lint pass, then all app tests pass.

- [x] **Step 7: Commit the UI migration**

```sh
git add SkillsManager/Features/Settings/SettingsView.swift \
  SkillsManager/Features/Library/SkillLibraryView.swift \
  SkillsManager/Features/Library/SkillList.swift
git commit -m "feat: manage folders from settings"
```

### Task 3: Update product and contributor documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `AGENTS.md`
- Add: `docs/superpowers/specs/2026-07-27-folder-settings-design.md`
- Add: `docs/superpowers/plans/2026-07-27-folder-settings.md`

**Interfaces:**
- Consumes: the completed Settings interaction and unchanged persistence
  architecture.
- Produces: current user instructions and a contributor contract that keeps
  folder addition in Settings.

- [x] **Step 1: Update user-facing documentation**

Describe the Settings folder list, plus/minus controls, agent-aware picker menu,
and toolbar Settings entry. Remove wording that locates Add Directory in the
library.

- [x] **Step 2: Update architecture and agent guidance**

Document that Settings owns add/remove presentation while
`SkillLibraryModel` owns source mutations. Add a contributor rule that future
folder-entry UI remains centralized in Settings without bypassing security
scope or bookmark creation.

- [x] **Step 3: Scan docs for stale copy**

Run:

```sh
rg -n "Add Directory|add menu|Library window" README.md docs AGENTS.md CLAUDE.md
```

Expected: no stale claim says the library toolbar or empty state adds folders
directly.

- [x] **Step 4: Commit documentation**

```sh
git add README.md docs/ARCHITECTURE.md AGENTS.md docs/superpowers
git commit -m "docs: describe settings folder management"
```

### Task 4: Verify the complete macOS flow

**Files:**
- Verify: `SkillsManager.xcodeproj`
- Verify: built `SkillsManager.app`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: passing checks, a native Settings screenshot, and PR-ready evidence.

- [x] **Step 1: Run repository checks**

Run:

```sh
make check
```

Expected: project generation is stable, formatting passes, package and app
tests pass, and the generated project has no diff.

- [x] **Step 2: Launch with isolated app data**

Build without signing, launch the Debug app with a task-specific
`CFFIXED_USER_HOME`, and open Settings through the gear toolbar button.

- [x] **Step 3: Exercise add and remove**

Use the plus menu and system picker to add a harmless repository test folder.
Verify its row appears with the full path and correct agent, select it, use
minus, confirm removal, and verify the row disappears while the directory
remains on disk.

- [x] **Step 4: Review the rendered UI**

Capture the Settings window and check hierarchy, row readability, selection,
status affordances, plus/minus discoverability, keyboard focus, contrast, and
the macOS 26 Liquid Glass treatment or macOS 15–25 material fallback.

- [x] **Step 5: Prepare the linked pull request**

Push the branch and create a PR titled
`VOLVOX-11: move folder management to Settings` with `Closes VOLVOX-11` in the
body. Include the validation commands and visual verification result.
