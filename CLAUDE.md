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
- Pinned `skills@1.5.21` implements `check` with the same mutating updater as
  `update`, so availability must never be checked against a real home. Read and
  validate only `~/.agents/.skill-lock.json`, mirror only its canonical validated
  fields into an owner-only disposable `HOME`/`CODEX_HOME`/`TMPDIR`, run the
  exact global `npx --yes --package skills@1.5.21 -- skills check --global --yes`
  command with the scrubbed environment, `GIT_TERMINAL_PROMPT=0`, and bounded
  pipe-only stdout capture. Keep the bytes in memory and create no stdout
  artifact. Let only the capture task own and close the read descriptor; cancel
  and await it on caller cancellation or the one-second post-exit drain deadline.
  Accept only the reviewed transcript, fail closed on every ambiguity, and clean
  the canonical lock, working directory, and disposable home on every exit path.
  Never log or present raw lock or CLI output.
- Run availability after restored-source scans and carry checked canonical
  Global-directory URLs separately from the update-available subset. Version 3
  has no per-agent destination identity, and `skillFolderHash` describes
  remote-tree provenance rather than local copies, so project each validated
  name only to `<account-home>/.agents/skills/<validated-name>`. Canonicalize
  result and installed URLs and intersect them exactly; never match by name.
  Copies in every other agent or custom path remain unknown. Use explicit unknown/current/
  available status after probing, reserving nil for pre-probe or legacy fallback,
  so incomplete coverage suppresses stale version badges.
- Preserve trustworthy badges and counts while a refresh is checking, then
  replace them atomically or clear them on cancellation/failure. Keep the
  persistent toolbar check available through Command-R and show progress plus
  Cancel while it runs. Count partial coverage, keep an empty library out of the
  all-current state, render `Not checked` on unknown rows, announce completion
  and coverage to VoiceOver, and disable reorder animation for Reduce Motion.
  Missing lock is quiet unavailable; missing Node.js/`npx` is quiet unsupported.
  All row, detail, context, and multi-select update surfaces are non-actionable
  `Reinstall Required` guidance because release 1.5.21 cannot scope an update to
  one agent; users must reinstall from a trusted source.
- The automatic launch-time check is network-capable and currently has no
  consent prompt or preference. Security finding 2 remains a residual Low risk
  pending a product decision; do not document an opt-in or opt-out as implemented.
- Remote content is untrusted; preserve the validated shell-free CLI boundary,
  pinned package, absolute delimiter-safe executable search paths, scrubbed child
  environment, symlink containment, bounded and escaped "observed so far"
  install-delta reporting for nonzero, timeout, cancellation, and postcondition
  failures, direct-process-only timeout/cancellation disclosure, postcondition
  checks, bounded catalog responses, and non-clickable overview rules in
  `AGENTS.md` and
  `docs/SECURITY.md`.
