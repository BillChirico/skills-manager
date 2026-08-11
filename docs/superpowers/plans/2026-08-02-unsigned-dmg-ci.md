# Unsigned DMG CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce, validate, and upload an unsigned installable DMG after successful pushes to `main` while retaining the existing pull-request CI checks.

**Architecture:** Repository-owned Bash scripts archive the app, create the drag-and-drop image, and validate a read-only mounted image. Make targets provide the stable local/CI interface; the existing GitHub Actions workflow invokes the portable test on every run and the real macOS packaging path only for `main` pushes.

**Tech Stack:** Xcode 26, XcodeGen, Bash 3.2-compatible scripts, `xcodebuild`, `hdiutil`, `ditto`, `plutil`, GNU Make, GitHub Actions, and `actions/upload-artifact@v7.0.1` pinned to commit `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a`.

## Global Constraints

- The DMG is unsigned and unnotarized; build with `CODE_SIGNING_ALLOWED=NO` and add no secrets.
- Only a successful push to `main` creates and uploads `build/release/SkillsManager-unsigned.dmg`.
- Pull requests still exercise packaging orchestration but never upload a DMG.
- Keep workflow permissions at `contents: read`, disable persisted checkout credentials, and pin actions to full commit SHAs.
- Keep scripts compatible with macOS's system Bash and clean only exact private temporary paths created by `mktemp`.
- Preserve macOS 15 deployment, Swift 6 strict concurrency, Hardened Runtime, and the existing App Sandbox decision.
- State the Gatekeeper limitation without recommending that users disable Gatekeeper or remove quarantine metadata.

---

### Task 1: Test and implement unsigned DMG packaging

**Files:**
- Create: `Tests/PackagingTests/unsigned-dmg.test.sh`
- Create: `scripts/build-unsigned-dmg.sh`
- Create: `scripts/verify-unsigned-dmg.sh`

**Interfaces:**
- Consumes: `SkillsManager.xcodeproj`, shared `SkillsManager` archive scheme, and standard macOS command-line tools.
- Produces: `scripts/build-unsigned-dmg.sh [output-path]` and `scripts/verify-unsigned-dmg.sh [dmg-path]`, both defaulting to `build/release/SkillsManager-unsigned.dmg` relative to the repository root.

- [x] **Step 1: Write the failing packaging behavior test**

Create a Bash test that gives the scripts a temporary `PATH` containing faithful filesystem fakes for `xcodebuild`, `ditto`, `plutil`, and `hdiutil`. The fake archive creates `SkillsManager.app/Contents/MacOS/SkillsManager` and `Info.plist`; fake image creation snapshots the staged source folder; fake attach restores that snapshot at the requested mount point. Execute both production scripts and assert these independently derived outcomes:

```bash
test -f "$dmg_path"
test -d "$dmg_path.contents/Skills Manager.app"
test -x "$dmg_path.contents/Skills Manager.app/Contents/MacOS/SkillsManager"
test "$(readlink "$dmg_path.contents/Applications")" = /Applications
grep -F -- '-configuration Release' "$fake_log/xcodebuild.args"
grep -F -- 'CODE_SIGNING_ALLOWED=NO' "$fake_log/xcodebuild.args"
grep -F -- 'archive' "$fake_log/xcodebuild.args"
test ! -e "$dmg_path.contents/Skills Manager.app/Contents/_CodeSignature"
test -f "$fake_log/detached"
```

Set `TMPDIR` to a test-owned directory and fail if either production script leaves a `skills-manager-dmg-*` directory behind. This catches a missing archive, wrong build mode, accidental signing, malformed installer layout, omitted detach, and incomplete cleanup.

- [x] **Step 2: Run the new test and verify RED**

Run from the repository root:

```bash
bash Tests/PackagingTests/unsigned-dmg.test.sh
```

Expected: nonzero exit because `scripts/build-unsigned-dmg.sh` does not exist.

- [x] **Step 3: Implement the archive and DMG builder**

Create `scripts/build-unsigned-dmg.sh` with strict mode. Resolve the repository from `BASH_SOURCE`, normalize a relative output beneath the repository root, require the four macOS tools, and create a private temporary workspace. Run this exact archive contract:

```bash
xcodebuild \
  -project "$repo_root/SkillsManager.xcodeproj" \
  -scheme SkillsManager \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  CODE_SIGNING_ALLOWED=NO \
  archive
```

Require the archived app directory, executable, and valid `Info.plist`, and require `Contents/_CodeSignature` to be absent. Copy the app to `Skills Manager.app`, add `Applications -> /Applications`, then create the compressed image with:

```bash
hdiutil create \
  -volname 'Skills Manager' \
  -srcfolder "$staging_root" \
  -ov \
  -format UDZO \
  "$output_path"
```

The EXIT/INT/TERM trap must delete only the exact `mktemp` workspace.

- [x] **Step 4: Implement mounted-image verification**

Create `scripts/verify-unsigned-dmg.sh` with strict mode. Require a regular DMG, run `hdiutil verify`, create a private mount point, and attach with:

```bash
hdiutil attach -nobrowse -readonly -mountpoint "$mount_point" "$dmg_path"
```

Check `Skills Manager.app`, its executable and `Info.plist`, absence of `_CodeSignature`, and an `Applications` symlink whose target is exactly `/Applications`. The cleanup trap must detach an attached image; detach failure changes the result to failure and leaves the mount point intact rather than recursively deleting mounted contents.

- [x] **Step 5: Run the packaging test and verify GREEN**

```bash
bash Tests/PackagingTests/unsigned-dmg.test.sh
bash -n scripts/build-unsigned-dmg.sh
bash -n scripts/verify-unsigned-dmg.sh
bash -n Tests/PackagingTests/unsigned-dmg.test.sh
```

Expected: all commands exit 0, the test prints its success message, and no temporary test directories remain.

- [x] **Step 6: Commit the packaging boundary**

```bash
git add Tests/PackagingTests/unsigned-dmg.test.sh scripts/build-unsigned-dmg.sh scripts/verify-unsigned-dmg.sh
git commit -m "feat(ci): add tested unsigned DMG packaging (VOLVOX-28)"
```

### Task 2: Wire packaging into Make and GitHub Actions

**Files:**
- Modify: `Makefile`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the scripts from Task 1 and the existing CI test job.
- Produces: `make packaging-test`, `make dmg`, `make verify-dmg`, and a directly downloadable `SkillsManager-unsigned.dmg` artifact on successful `main` pushes.

- [x] **Step 1: Add Make targets**

Set the overridable output once and expose focused targets:

```make
DMG_OUTPUT ?= build/release/SkillsManager-unsigned.dmg

.PHONY: generate lint test build app-test packaging-test dmg verify-dmg check

packaging-test:
	bash Tests/PackagingTests/unsigned-dmg.test.sh

dmg:
	bash scripts/build-unsigned-dmg.sh "$(DMG_OUTPUT)"

verify-dmg:
	bash scripts/verify-unsigned-dmg.sh "$(DMG_OUTPUT)"
```

Add `packaging-test` to the prerequisites of `check` before the macOS app test.

- [x] **Step 2: Extend the existing CI job**

After Swift linting, run `make packaging-test` on pull requests and main pushes. After the existing macOS app test, add main-push-only build and validation steps using this condition on every distribution step:

```yaml
if: github.event_name == 'push' && github.ref == 'refs/heads/main'
```

Upload the single already-compressed file without wrapping it in another archive:

```yaml
- name: Upload unsigned DMG
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
  with:
    path: build/release/SkillsManager-unsigned.dmg
    if-no-files-found: error
    retention-days: 30
    archive: false
```

- [x] **Step 3: Validate the build interface and workflow syntax**

```bash
make packaging-test
actionlint .github/workflows/ci.yml
git diff --check
```

Expected: all commands exit 0. On a non-macOS host, do not run `make dmg` or `make verify-dmg`; record that the real `xcodebuild`/`hdiutil` integration path requires macOS and runs on the `macos-26` CI runner.

Windows execution used the test script directly because GNU Make was
unavailable; the script, `actionlint`, ShellCheck, and whitespace checks passed.

- [x] **Step 4: Commit CI wiring**

```bash
git add Makefile .github/workflows/ci.yml
git commit -m "ci: publish unsigned main-branch DMG (VOLVOX-28)"
```

### Task 3: Document distribution and extension boundaries

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/SECURITY.md`

**Interfaces:**
- Consumes: the commands, artifact path, trigger, and trust posture implemented in Tasks 1 and 2.
- Produces: consistent user, contributor, architecture, and security guidance.

- [x] **Step 1: Update user-facing documentation**

Add a `## Unsigned DMG artifacts` section to `README.md` that states:

```text
Every successful push to main uploads SkillsManager-unsigned.dmg for 30 days.
The image contains Skills Manager.app and an Applications shortcut for drag-and-drop installation.
The artifact is neither Developer ID signed nor notarized, so Gatekeeper can block or warn about it.
This workflow does not use Apple signing credentials and is not the final trusted release channel.
macOS contributors can run make packaging-test, make dmg, and make verify-dmg.
```

Describe downloading the file from the successful GitHub Actions run without recommending a Gatekeeper bypass.

- [x] **Step 2: Update agent and architecture documentation**

Add the three Make commands and their host requirements to `AGENTS.md`; state that distribution steps remain main-push-only, unsigned, minimally permissioned, and SHA-pinned. Add matching concise reminders to `CLAUDE.md`. Add a CI/distribution section to `docs/ARCHITECTURE.md` describing the script/Make/workflow boundaries and the future signing insertion points.

- [x] **Step 3: Update the security record**

Add an unsigned-build section to `docs/SECURITY.md` stating that Hardened Runtime does not authenticate an unsigned artifact, Gatekeeper may reject it, no signing secrets are present, and Developer ID signing plus Apple notarization require a separate security-reviewed workflow change.

- [x] **Step 4: Review documentation consistency**

```bash
rg -n "unsigned|notar|Gatekeeper|packaging-test|verify-dmg|SkillsManager-unsigned" README.md AGENTS.md CLAUDE.md docs/ARCHITECTURE.md docs/SECURITY.md
git diff --check
```

Expected: every required document names the unsigned boundary consistently, and whitespace validation exits 0.

- [x] **Step 5: Commit documentation**

```bash
git add README.md AGENTS.md CLAUDE.md docs/ARCHITECTURE.md docs/SECURITY.md docs/superpowers/plans/2026-08-02-unsigned-dmg-ci.md
git commit -m "docs(ci): explain unsigned DMG delivery (VOLVOX-28)"
```

### Task 4: Final verification and mandatory reviews

**Files:**
- Verify: all files changed since `origin/main`

**Interfaces:**
- Consumes: Tasks 1 through 3 and the repository review policy.
- Produces: a committed reviewable range, fresh validation evidence, and separate QA and Security review requests before PR creation.

- [x] **Step 1: Run all available verification**

On macOS with the required toolchain:

```bash
make check
make dmg
make verify-dmg
actionlint .github/workflows/ci.yml
```

On another host, run the portable equivalents and report the unavailable native commands explicitly:

```bash
make packaging-test
bash -n scripts/build-unsigned-dmg.sh
bash -n scripts/verify-unsigned-dmg.sh
bash -n Tests/PackagingTests/unsigned-dmg.test.sh
actionlint .github/workflows/ci.yml
git diff --check origin/main...HEAD
```

- [x] **Step 2: Audit the final range**

```bash
git status --short
git diff --stat origin/main...HEAD
git diff origin/main...HEAD
git log --oneline origin/main..HEAD
```

Confirm the workflow still has `contents: read`, no secret references, no PR artifact upload, the expected full action SHAs, and documentation matching the implemented command/path names.

- [ ] **Step 3: Request the two mandated reviews**

Post one Multica issue comment containing the exact base SHA, head SHA, requirement/design references, validation evidence and host limitation, then explicitly mention QA Reviewer and Security Reviewer. Do not mention GitHub PR Builder in that comment; PR creation is blocked until both reviewers approve the same head.

- [ ] **Step 4: Hand off after approvals**

After both reviewers return approval for the current head, incorporate any required findings with fresh tests and re-review as needed. Then mention GitHub PR Builder with the approved SHA and require a PR title or body containing `VOLVOX-28` (prefer `Closes VOLVOX-28` in the body so merge records close intent).
