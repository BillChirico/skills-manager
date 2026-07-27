# Architecture

Skills Manager starts as a small modular macOS application. The initial
boundary is intentionally simple:

```text
SwiftUI app (SkillsManager)
        │
        ▼
domain package (SkillsCore)
        │
        ▼
future injected filesystem, persistence, and registry adapters
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
selection, filtering, and user-added directory references. Durable bookmark
storage and skill discovery are explicit follow-up seams rather than hidden
global dependencies.

## Domain layer

`Packages/SkillsCore` owns:

- `SkillSource`, a user-configured skill directory;
- `AgentSkill`, a discovered skill and its management state; and
- `SkillSearch`, deterministic filtering and ordering.

Future filesystem scanners, manifest parsers, registries, and install/update
operations should enter the package behind small injected protocols. Tests must
use in-memory fakes or temporary directories rather than a developer's real
skill folders.

## Platform and visual policy

The deployment target is macOS 15. Liquid Glass is used through availability
checks on macOS 26 and newer; earlier systems receive a semantic material
fallback. New visual treatments must remain legible with increased contrast,
reduced transparency, and reduced motion.

The app sandbox permits user-selected read/write access and app-scoped
bookmarks. A directory picker grant is not automatically durable: persistence
work must store and resolve security-scoped bookmarks before accessing a folder
in a later launch.

## Project generation

`project.yml` is authoritative. `SkillsManager.xcodeproj` is generated and
committed for easy onboarding. Any target, build-setting, capability, or file
layout change should update the specification first and regenerate the project
with `make generate`.

## Planned extension points

1. Persist user-selected sources as security-scoped bookmarks.
2. Discover and validate `SKILL.md` manifests off the main actor.
3. Add install, update, remove, and conflict-resolution operations.
4. Add remote registry clients behind injected protocols.
5. Add UI automation with XCTest after core user flows stabilize.
