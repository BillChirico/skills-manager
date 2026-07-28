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
- Remote content is untrusted; preserve the bounded-streaming, exact-manifest,
  commit-pinning, and non-clickable-overview rules in `AGENTS.md`.
