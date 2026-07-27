# AGENTS.md

This file is the source of truth for coding agents working in this repository.
Read it before making changes. Human contributors should follow the same
engineering constraints.

## Product

Skills Manager is a native macOS SwiftUI app for installing, updating,
removing, searching, and organizing agent skills across user-selected
directories. It should feel at home on macOS, remain accessible, and adopt
Liquid Glass without dropping the macOS 15 deployment target.

## Project structure

- `SkillsManager/` contains the app target and feature UI.
- `Packages/SkillsCore/` contains models and domain logic that do not depend on
  SwiftUI or AppKit.
- `Tests/SkillsManagerTests/` contains unit tests for app-only state.
- `project.yml` is the source of truth for `SkillsManager.xcodeproj`.
- `docs/ARCHITECTURE.md` records dependency boundaries and extension points.

Keep feature code together under `SkillsManager/Features/<FeatureName>`.
Promote code to `SkillsCore` only when it represents reusable domain behavior.

## Required commands

```sh
make generate   # regenerate the Xcode project after project.yml changes
make lint       # check Swift formatting without modifying files
make test       # run SkillsCore tests with Swift Package Manager
make build      # build the macOS app without code signing
make check      # regenerate, test, verify generated files, and build
```

Run the narrowest relevant command while iterating and `make check` before
hand-off when full Xcode is available. If Xcode is unavailable, run
`make generate` and `make test`, then state that limitation clearly.

## Swift conventions

- Use Swift 6 language mode and strict concurrency.
- Isolate UI-owned mutable state to `@MainActor`.
- Prefer value types that conform to `Sendable` for domain models.
- Keep filesystem, network, persistence, and time dependencies injectable.
- Never add AppKit or SwiftUI imports to `SkillsCore`.
- Use native SwiftUI controls and semantic colors before custom drawing.
- Gate macOS 26-only Liquid Glass APIs with availability checks and retain a
  usable fallback for macOS 15 through 25.
- Treat accessibility labels, keyboard access, empty states, and reduced motion
  as part of feature completion.

## Testing conventions

- Write new unit and integration tests with Swift Testing.
- Use XCTest only for UI tests, which Swift Testing does not support.
- Mirror production folders in test folders where practical.
- Keep tests deterministic, parallel-safe, and independent of real user files.
- Prefer `#require` for preconditions and `#expect` for behavior assertions.

## Project-file policy

Do not hand-edit `SkillsManager.xcodeproj/project.pbxproj`. Update `project.yml`,
run `make generate`, and commit both the specification and generated project.
Do not add third-party dependencies without documenting the reason in the pull
request and `docs/ARCHITECTURE.md` when the choice affects architecture.

## Security

The app is sandboxed. Access files only through user-selected URLs and preserve
security-scoped access when work outlives a picker callback. Never log skill
contents, tokens, credentials, or user-specific absolute paths.

## Change checklist

1. Keep the change inside the existing dependency boundaries.
2. Format Swift with the checked-in `.swift-format` configuration.
3. Add or update focused tests for behavior.
4. Regenerate the Xcode project when its inputs change.
5. Run all checks available in the current environment.
6. Update documentation when commands, requirements, or architecture change.
