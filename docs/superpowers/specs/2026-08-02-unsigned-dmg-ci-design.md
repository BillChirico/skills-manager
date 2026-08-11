# Unsigned DMG CI Design

## Goal

Build an installable drag-and-drop DMG after every successful push to `main`,
validate its structure on the macOS runner, and publish it as a GitHub Actions
artifact. The first iteration is deliberately unsigned and unnotarized.

## Approved constraints

- Pull requests and pushes to `main` continue to run the existing generated-
  project, package-test, formatting, and app-test checks.
- Only a push to `main` builds and uploads the DMG.
- The Release app is built with `CODE_SIGNING_ALLOWED=NO`; no signing or Apple
  credentials are added.
- Documentation must state prominently that macOS Gatekeeper can block or warn
  about the artifact because it has neither a Developer ID signature nor an
  Apple notarization ticket.
- Packaging must be straightforward to extend with signing and notarization in
  a separately reviewed change.
- GitHub Actions permissions remain read-only, and third-party actions remain
  pinned to full commit SHAs.

## Approaches considered

### Repository-owned scripts invoked by Make and CI (selected)

Keep archive, DMG creation, and mounted-image validation in focused shell
scripts. Expose them as Make targets and let GitHub Actions invoke those targets.
This adds a small amount of repository code, but it gives macOS contributors the
same commands as CI, supports portable orchestration tests with controlled tool
fakes, and creates a clear boundary where signing can be inserted later.

### Inline packaging commands in the workflow

Putting every `xcodebuild` and `hdiutil` command directly in `ci.yml` minimizes
the file count. It makes the packaging behavior harder to exercise locally,
couples implementation details to GitHub Actions, and leaves no focused unit for
future signing/notarization work.

### Separate release workflow

A second workflow would isolate distribution from pull-request CI. For one
unsigned main-branch artifact, it would duplicate checkout, project generation,
and validation policy while making the required test-before-package ordering
less obvious. A separate release workflow is better reserved for a future
signed release process with tags, environments, and protected secrets.

## Architecture

`scripts/build-unsigned-dmg.sh` performs a Release archive into a private
temporary workspace, checks the app bundle, stages `Skills Manager.app` beside
an `/Applications` shortcut, and creates a compressed read-only DMG at a caller-
provided path. It never accepts remote content, interpolates shell commands, or
persists build intermediates.

`scripts/verify-unsigned-dmg.sh` verifies the disk image, mounts it read-only at
a private temporary mount point, and checks the expected app bundle, executable,
property list, unsigned-bundle marker, and `/Applications` symlink. Its cleanup
trap detaches the image and removes only the temporary directory it created.

`Tests/PackagingTests/unsigned-dmg.test.sh` runs both scripts with controlled
fakes for macOS-only tools. The fakes reproduce the filesystem effects the
scripts consume, so the test can exercise the orchestration, output layout,
Release archive settings, unsigned build setting, and cleanup behavior on any
host with Bash. The macOS CI path remains the integration test for real
`xcodebuild`, `hdiutil`, `ditto`, and `plutil` behavior.

The Makefile exposes `packaging-test`, `dmg`, and `verify-dmg`. `make check`
includes the portable packaging test. The existing CI job runs that test on
every event; after all normal checks pass, main-branch pushes run `make dmg`,
`make verify-dmg`, and a SHA-pinned artifact upload.

## Data flow

1. A pull request or push to `main` starts `.github/workflows/ci.yml`.
2. CI checks out without persisted credentials, regenerates the project, tests,
   and lints as it does today, then runs the portable packaging test.
3. On a `main` push only, the build script archives the Release app without code
   signing and creates `build/release/SkillsManager-unsigned.dmg`.
4. The verification script mounts that image read-only and validates the
   installer layout before detaching it.
5. GitHub uploads the already-compressed DMG with compression disabled at the
   artifact layer and fails if the file is absent.

## Error handling and cleanup

Both scripts use strict shell error handling and explicit dependency checks.
Missing tools, a failed archive, an invalid bundle, a failed image operation, or
an unexpected installer layout returns a nonzero exit code and prevents upload.
Temporary workspaces come from `mktemp`; cleanup targets only those exact paths.
The verifier always attempts to detach an attached image, and a detach failure
causes validation to fail rather than leaving a successful result with a mounted
volume.

## Security and distribution posture

The workflow uses no signing secrets and requests only `contents: read`. The
DMG name includes `unsigned`, and user-facing and contributor documentation says
that the artifact is not a trusted public release. Users must make an explicit
macOS security decision if Gatekeeper blocks it; documentation will not suggest
disabling Gatekeeper or stripping quarantine metadata.

The app's existing Hardened Runtime build setting remains enabled, but that is
not a substitute for Developer ID signing or notarization. A future production
release design can add signing after archive creation and notarization after DMG
creation without changing the CI trigger or artifact boundary.

## Validation

- RED/GREEN portable packaging test covering the observable artifact layout,
  command contract, and temporary-workspace cleanup.
- Shell syntax checks for all new scripts.
- Workflow linting with `actionlint`.
- Existing repository checks where the host toolchain supports them.
- On the macOS runner, a real Release archive, `hdiutil verify`, read-only mount,
  bundle validation, and detach before upload.

## Documentation

- `README.md`: artifact availability, drag-and-drop layout, Gatekeeper warning,
  and local packaging commands.
- `AGENTS.md`: required commands and unsigned-distribution invariants.
- `CLAUDE.md`: concise packaging command and security reminders.
- `docs/ARCHITECTURE.md`: build/distribution component boundary and flow.
- `docs/SECURITY.md`: explicit unsigned/unnotarized artifact risk and deferred
  signing/notarization boundary.
