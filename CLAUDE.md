# CLAUDE.md

Read and follow [AGENTS.md](AGENTS.md) before changing this repository.
`AGENTS.md` is the canonical contributor guide; this file intentionally does
not duplicate it.

At a glance:

- `project.yml` generates `SkillsManager.xcodeproj`.
- `SkillsManager/` is the SwiftUI app.
- `Packages/SkillsCore/` is the UI-independent domain package.
- `make test` runs package tests.
- `make check` is the preferred pre-handoff validation when Xcode is installed.
- Node.js 18 or newer and `npx` are runtime requirements for lifecycle actions.
- Remote content is untrusted; preserve the validated shell-free CLI boundary,
  scrubbed child environment, postcondition checks, bounded catalog responses,
  and non-clickable overview rules in `AGENTS.md`.
