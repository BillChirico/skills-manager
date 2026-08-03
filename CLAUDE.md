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
- `make packaging-test` exercises DMG orchestration; `make dmg` and
  `make verify-dmg` build and mount-check the real image on macOS.
- Successful `main` pushes publish `SkillsManager-unsigned.dmg` for 30 days.
  It is neither Developer ID signed nor notarized, so Gatekeeper can block it;
  keep the workflow secret-free, least-privileged, and pinned to full action
  SHAs until a separately reviewed signing design replaces this boundary.
- Node.js 22.20 or newer and `npx` are runtime requirements for lifecycle actions.
- Remote content is untrusted; preserve the validated shell-free CLI boundary,
  pinned package, absolute delimiter-safe executable search paths, scrubbed child
  environment, symlink containment, bounded and escaped "observed so far"
  install-delta reporting for nonzero, timeout, cancellation, and postcondition
  failures, direct-process-only timeout/cancellation disclosure, postcondition
  checks, bounded catalog responses, and non-clickable overview rules in
  `AGENTS.md` and
  `docs/SECURITY.md`.
