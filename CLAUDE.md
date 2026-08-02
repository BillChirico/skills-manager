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
- Node.js 22.20 or newer and `npx` are runtime requirements for lifecycle actions.
- Pinned `skills@1.5.21` implements `check` with the same mutating updater as
  `update`, so availability must never be checked against a real home. Read and
  validate only `~/.agents/.skill-lock.json`, mirror only its canonical validated
  fields into an owner-only disposable `HOME`/`CODEX_HOME`/`TMPDIR`, run the
  exact global `npx --yes --package skills@1.5.21 -- skills check --global --yes`
  command with the scrubbed environment and bounded, pre-opened private stdout
  capture, parse those bytes without reopening the child-writable path, accept
  only the reviewed transcript, fail closed on every ambiguity, and clean the
  canonical lock, output, working directory, and disposable home on every exit
  path. Never log or present raw lock or CLI output.
- Run availability after restored-source scans, make a completed detection
  authoritative, clear positive claims on errors or cancellation, keep updates
  first within every selected sort, and expose the status with text, a symbol,
  and an explicit accessibility label. The actual update action still fails
  closed because release 1.5.21 cannot scope a mutation to one agent.
- Remote content is untrusted; preserve the validated shell-free CLI boundary,
  pinned package, absolute delimiter-safe executable search paths, scrubbed child
  environment, symlink containment, bounded and escaped "observed so far"
  install-delta reporting for nonzero, timeout, cancellation, and postcondition
  failures, direct-process-only timeout/cancellation disclosure, postcondition
  checks, bounded catalog responses, and non-clickable overview rules in
  `AGENTS.md` and
  `docs/SECURITY.md`.
