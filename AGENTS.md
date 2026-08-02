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
- Inherit the user's macOS accent color. Do not add a global `AccentColor`
  asset or override the root scene's tint.
- Gate macOS 26-only Liquid Glass APIs with availability checks and retain a
  usable fallback for macOS 15 through 25.
- Reserve Liquid Glass for interactive controls; use semantic system
  backgrounds and separators for static Settings containers.
- Treat accessibility labels, keyboard access, empty states, and reduced motion
  as part of feature completion.
- Keep folder addition and the primary add/remove list in Settings. Route other
  entry points to the Settings scene instead of duplicating the folder picker;
  contextual relocation for unavailable sources may remain in the library.
- Suggest a standard agent location only while it exists on disk, and add it
  directly instead of reopening a picker the user already answered. Keep one
  generic picker action for every other folder rather than a per-agent list.
- Resolve the account home through `UserHomeDirectory`, never
  `FileManager.homeDirectoryForCurrentUser`, which reports the sandbox container
  instead of the user's folders. If account-home resolution fails, suppress
  home-based suggestions, picker defaults, and `~` abbreviation rather than
  substituting another directory.
- Keep Settings folder selection explicit: preserve a valid user selection,
  clear a stale one, and never auto-select the first row.
- Present paused, scanning, and unavailable folder states with text rather than
  opacity or icon-only cues. Keep row toggles and reconnect buttons separately
  operable by assistive technologies.
- Keep Discover visually prominent in the library toolbar and Settings as an
  icon-only utility.
- Send every folder add, enable, relocate, or remove mutation through
  `SkillLibraryModel` so security-scoped access, bookmarks, persistence, and
  rollback remain intact.
- Open Discover on the skills.sh download leaderboard, and order both the
  leaderboard and search results with `CatalogSkillSorter.byDownloads`. A search
  response arrives in relevance order, so skipping the sorter silently changes
  the ranking the product promises.

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

For directory add and relocation flows, start the selected URL’s security scope
before creating its bookmark. Keep the scope active while the source is
configured, and balance it on every bookmark or persistence failure.

Suggested agent locations add their folder straight through
`SkillLibraryModel.addSource(at:agent:)`. That succeeds only where the process
already holds access, so a sandboxed build falls back to the system picker
rooted at the suggestion when the model reports `SourceAccessError.accessDenied`.
Keep that fallback narrow: report every other failure instead of swallowing it,
and never widen the sandbox, add a temporary-exception entitlement, or weaken
`SecurityScopedSkillSourceAccess` to make a suggestion succeed.

When a source mutation rolls back after a failed save, re-resolve the target by
`SkillSource.ID` inside the `catch`. An index captured before the `await` can be
stale, because awaiting the save yields the main actor and lets another mutation
reorder or shrink `sources`. Persist bookmark data owner-only; never widen the
permissions of the store file.

When the account home is available, the abbreviated `~/…` display path keeps the
account name off screen. Do not pass a raw absolute path to a tooltip, label, or
accessibility string that renders next to an available abbreviation.
`UserHomeDirectory` reads the account home from the password database, which
yields a path and never access to the files beneath it. If that lookup fails,
leave persisted paths un-abbreviated instead of guessing at the account home.

### Remote catalog input

Never execute a command sourced from skills.sh, and never hand catalog text to a
shell, `Process`, `NSAppleScript`, or `NSWorkspace.open` for a non-`https` URL.
The install command in the detail view exists to be read and copied. Skills
Manager installs by downloading files over HTTPS and copying them; a spawned
`npx` would both execute arbitrary remote code and write outside the user's
directory grants. UI copy must distinguish that install-time behavior from later
use: an installed `SKILL.md` is instructions that an agent may follow with its
own permissions, so users must be told to review it before use.

Every field on `CatalogSkill` is untrusted. Route each one through
`CatalogIdentifier` before it becomes a URL path component
(`validatedPathComponent`) or a command argument (`validatedArgument`, which also
rejects a leading `-` so a slug cannot be read as a flag). A value that fails
validation makes the skill non-installable; it must not degrade into an
unvalidated fallback. Reject dot-prefixed installation slugs because the library
scanner skips hidden directories, while still allowing safe dot-prefixed
repository path components such as `.github`. Re-check installability at the
model boundary, and keep the filesystem installer responsible for refusing
hidden destination names even if a future caller bypasses the catalog UI. Build
`SkillInstallCommand` as a program plus an argument vector, never as one
interpolated string.

Repository tree paths are remote input too. `GitHubSkillPackageFetcher` drops any
entry containing an empty, `.`, or `..` component before it reaches a
`raw.githubusercontent.com` URL, in addition to the installer's own path checks.

Treat text extracted from an installed `SKILL.md` as untrusted presentation
input. Its library overview must remain non-interactive. Markdown styling may be
parsed only when every link attribute is stripped before rendering; never allow
a manifest-supplied destination to become clickable. Any intentional external
navigation must be a separately constructed, validated `https` action.

All catalog, repository-tree, and raw-file bodies must use the bounded streaming
HTTP loader. Do not replace a streaming ceiling with a size check that runs only
after `URLSession` has buffered the response. Keep skills.sh responses capped at
8 MiB, keep GitHub recursive tree responses capped at 8 MiB, and keep packages
capped at 200 files and 10 MiB aggregate. Pass the remaining aggregate byte
budget to each raw-file request so no individual response can cross the package
ceiling.

Resolve GitHub `HEAD` exactly once per package fetch and use the resulting commit
SHA for both recursive tree enumeration and every raw-content URL. Select a
nested manifest only when its immediate parent directory matches the requested
slug. A root `SKILL.md` is eligible only when it is the repository's sole
manifest and the validated repository name exactly matches that slug; otherwise
fail closed with no manifest fallback.

## Change checklist

1. Keep the change inside the existing dependency boundaries.
2. Format Swift with the checked-in `.swift-format` configuration.
3. Add or update focused tests for behavior.
4. Regenerate the Xcode project when its inputs change.
5. Run all checks available in the current environment.
6. Update documentation when commands, requirements, or architecture change.
