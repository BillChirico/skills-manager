# Architecture

Skills Manager is a small modular macOS application with an intentionally
simple boundary:

```text
SwiftUI app (SkillsManager)
        │
        ▼
domain package (SkillsCore)
        │
        ▼
injected filesystem and persistence adapters
```

`SkillsCore` must not import SwiftUI or AppKit. This keeps domain behavior
testable with `swift test`, makes background work easier to isolate, and leaves
the option to reuse the package in a command-line tool later.

## App layer

`SkillsManager/App` owns process-level composition and shared observable state.
`SkillsManager/Features` is organized by user-facing capability. Views may
depend on `SkillsCore`; they should not perform direct filesystem or network
work.

UI state is isolated to the main actor. The initial library model coordinates
source restoration, selection, scoped search, discovery, and mutations. Native
bookmark creation and security-scoped access live in the app layer because
those APIs are macOS-specific. The model receives persistence and discovery
dependencies through protocols rather than reaching for global state. A
separate catalog model coordinates debounced skills.sh searches and
installations so network and filesystem work remain independently testable.
Agent models expose their standard user skill-directory paths, which the app
uses as picker starting points without bypassing the sandbox’s user-consent
boundary. `SettingsView` owns folder-add, folder-remove, enabled-state, and
reconnect presentation, including the agent-aware picker menu, explicit list
selection, and destructive confirmation. Selection reconciliation preserves a
valid user selection but never chooses a folder on the user's behalf. The
library routes its empty states to the Settings scene; contextual relocation
also remains in the library for unavailable sources. All mutations still pass
through `SkillLibraryModel`.

## Domain layer

`Packages/SkillsCore` owns:

- `SkillSource`, a user-configured skill directory;
- `SkillAgent`, the agent associated with a configured directory;
- `AgentSkill`, a discovered skill with stable source-relative identity;
- `SkillDiscovering`, with a local `SKILL.md` scanner;
- `SkillSourceStore`, with an atomic JSON implementation;
- `SkillLibraryFilter`, which applies smart-group and source scopes;
- `SkillSearch` and `SkillLibrarySorter`, which provide deterministic relevance
  ranking and user-selected ordering;
- `SkillCatalogSearching`, with the skills.sh search client;
- `SkillPackageFetching`, with a GitHub tree and raw-content implementation; and
- `SkillPackageInstalling`, with a staged filesystem implementation.

Tests use in-memory fakes or temporary directories rather than a developer's
real skill folders.

## Remote discovery and installation

The skills.sh client uses the catalog's public `/api/search` endpoint and
converts results into domain-owned values. The GitHub fetcher resolves the
selected skill directory from the repository tree and downloads only blob
entries beneath it. A non-GitHub source remains browsable but is not installable.

Before writing, the installer validates the directory name and each path,
rejects traversal, duplicate paths, and missing manifests, and refuses to
overwrite an existing skill. Packages are limited to 200 files and 10 MiB,
assembled in memory, written to a staging directory, then moved into place.
This prevents a failed download or validation pass from leaving a partial
installed skill.

## Platform and visual policy

The deployment target is macOS 15. Liquid Glass is used through availability
checks on macOS 26 and newer; earlier systems receive a semantic material
fallback. New visual treatments must remain legible with increased contrast,
reduced transparency, and reduced motion.

The library window titles itself after the selected scope and subtitles itself
with the count in view, so the title bar reports state instead of repeating the
app name. Toolbar actions form two groups separated by a `ToolbarSpacer`:
prominent discovery and icon-only Settings utilities, then the sort and search
controls that change how the library is displayed. Settings is also available
through the app menu and `Command-,`. `SkillsCore` still owns no AppKit, but
`Shared/VisualStyle/ToolbarSearchFieldWidth.swift` bridges to
`NSSearchToolbarItem` because SwiftUI exposes no way to stop a toolbar search
field from growing wider than every action beside it. Prefer a native SwiftUI
API and add a bridge like this only when none exists.

Settings uses a grouped native `Form` and a resizable minimum/ideal frame. Its
static folder list uses semantic control and separator colors; Liquid Glass is
reserved for interactive controls on macOS 26. Healthy rows omit decorative
status icons. Paused, scanning, and missing states use readable text, and row
toggles remain distinct accessibility elements. Since macOS folds a secondary
button into a selectable list row, unavailable rows also expose Reconnect as a
source-specific named accessibility action on the row Toggle.

The app sandbox permits outbound network access, user-selected read/write
access, and app-scoped bookmarks. Directory grants are stored as
security-scoped bookmarks, resolved on launch, and held only while their source
remains configured. Failed resolution is surfaced as an unavailable source
instead of an empty library. A URL returned by the directory picker must be
opened with `startAccessingSecurityScopedResource()` before bookmark creation;
add and relocation operations release that access and roll back state if
bookmarking or persistence fails. Because `sources.json` carries those bookmark
blobs and the full map of configured directories, it is written owner-only
(`0600`) inside an owner-only directory rather than inheriting the process
umask, which matters for unsigned builds that run outside an app container.

Source mutations that roll back after a failed save re-resolve their target by
`SkillSource.ID`, never by an index captured before the `await`. `sources` is
main-actor isolated, but awaiting a save yields the actor, so a concurrent
mutation can reorder or shrink the array before the rollback runs.

## Project generation

`project.yml` is authoritative. `SkillsManager.xcodeproj` is generated and
committed for easy onboarding. Any target, build-setting, capability, or file
layout change should update the specification first and regenerate the project
with `make generate`.

## Planned extension points

1. Define authoritative on-disk update, remove, and conflict-resolution
   semantics behind an injected mutation protocol.
2. Add authenticated or alternate registry adapters without coupling them to
   app state.
3. Add UI automation with XCTest after the mutation workflows stabilize.
