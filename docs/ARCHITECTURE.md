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
dependencies through protocols rather than reaching for global state.

## Domain layer

`Packages/SkillsCore` owns:

- `SkillSource`, a user-configured skill directory;
- `AgentSkill`, a discovered skill with stable source-relative identity;
- `SkillDiscovering`, with a local `SKILL.md` scanner;
- `SkillSourceStore`, with an atomic JSON implementation;
- `SkillLibraryFilter`, which applies smart-group and source scopes; and
- `SkillSearch`, which provides deterministic relevance ranking.

Future registries and install/update operations should enter the package behind
small injected protocols. Tests use in-memory fakes or temporary directories
rather than a developer's real skill folders.

## Platform and visual policy

The deployment target is macOS 15. Liquid Glass is used through availability
checks on macOS 26 and newer; earlier systems receive a semantic material
fallback. New visual treatments must remain legible with increased contrast,
reduced transparency, and reduced motion.

The app sandbox permits user-selected read/write access and app-scoped
bookmarks. Directory grants are stored as security-scoped bookmarks, resolved
on launch, and held only while their source remains configured. Failed
resolution is surfaced as an unavailable source instead of an empty library.

## Project generation

`project.yml` is authoritative. `SkillsManager.xcodeproj` is generated and
committed for easy onboarding. Any target, build-setting, capability, or file
layout change should update the specification first and regenerate the project
with `make generate`.

## Planned extension points

1. Define the authoritative install, update, remove, and conflict-resolution
   semantics behind an injected mutation protocol.
2. Add remote registry clients behind injected protocols once the update source
   is defined.
3. Add UI automation with XCTest after the mutation workflows stabilize.
