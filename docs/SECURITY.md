# Security

Skills Manager is a developer tool that reads and mutates agent skill folders in
the signed-in account. This document records the executable dependency and the
trust that remains after the app's local controls.

## Reviewed CLI release

Lifecycle operations select the exact npm package `skills@1.5.21`:

- upstream repository: <https://github.com/vercel-labs/skills>;
- signed tag: [`v1.5.21`](https://github.com/vercel-labs/skills/releases/tag/v1.5.21);
- tagged commit: [`7cb7db64dc1201052dea305e508a2fc490f7e5e2`](https://github.com/vercel-labs/skills/commit/7cb7db64dc1201052dea305e508a2fc490f7e5e2);
- npm release: <https://www.npmjs.com/package/skills/v/1.5.21>; and
- published tarball integrity:
  `sha512-CJ4wx692UkQAW+DLpjJg/ww6dJBojq5E8sQBOqP639GutO72v4EFiV/fq1etW2r9NhM/mwaIq8YoqKFJ9XV7ng==`.

The npm release metadata also advertises an SLSA provenance v1 attestation at
<https://registry.npmjs.org/-/npm/v1/attestations/skills@1.5.21>. This record is
review evidence; the app does not currently perform its own attestation
verification before `npx` runs.

The release declares Node.js `>=22.20.0`. Its package manifest contains no
`preinstall`, `install`, or `postinstall` script. Skills Manager additionally
sets `NPM_CONFIG_IGNORE_SCRIPTS=true`, fixes the registry to
`https://registry.npmjs.org/`, ignores user/global npm configuration, and invokes
the binary with an explicit package selector:

```text
npx --yes --package skills@1.5.21 -- skills <operation> ...
```

Each invocation starts in a newly created owner-only empty directory. This keeps
a project-local `node_modules/.bin/skills` or package configuration from
shadowing the selected package. During `npx` discovery, empty and non-absolute
entries from the parent `PATH` are ignored. Candidate directories containing the
`:` delimiter are also rejected. The child receives only a small environment and
a path made from the validated absolute Node directory plus fixed Homebrew and
system directories; no inherited entry is forwarded.

## Verified command semantics

The tagged implementation derives an install directory from the selected
agent's global base and the discovered skill's sanitized install name. A live
isolated-home probe of the published package confirmed that this command:

```text
skills add <source> --skill find-skills --global --agent codex --copy --yes
```

with `CODEX_HOME=~/.agents` creates
`~/.agents/skills/find-skills/SKILL.md`. This is the destination Skills Manager
validates for its Global and Codex sources. The other supported sources use the
CLI's documented global agent directories. The catalog slug is not an upstream
guarantee of the repository-controlled sanitized install name, so the manager
also snapshots the source's entry names. On a nonzero exit, timeout,
cancellation, or absent expected manifest, the error reports a bounded, escaped
delta of entries observed so far and leaves those entries on disk for review
rather than silently deleting untrusted content.

Update is deliberately unavailable in the production manager. In release
1.5.21, `skills update` accepts global/project scope, confirmation, and
positional skill filters, but no `--agent` selector. Its global path reads the
shared lock and reinstalls through `add`. Calling it from a source-scoped app
action could therefore mutate other agent directories. Skills Manager validates
the selected source and skill, then fails before process launch with an
actionable error. A reviewed reinstall is the safe refresh path until upstream
adds an agent-scoped update contract. A published-package probe also confirmed
that attempting `skills update --agent codex --global --yes` does not add an
agent boundary: `--agent` is ignored by the update parser and `codex` is treated
as a positional skill-name filter.

## Automatic source discovery and persistence

At launch, when `UserHomeDirectory` can resolve the signed-in account home from
the password database, Skills Manager checks only these fixed, home-relative
standard skill directories:

- Global and Codex: `~/.agents/skills`;
- Claude Code: `~/.claude/skills`;
- Cursor: `~/.cursor/skills`;
- GitHub Copilot: `~/.copilot/skills`; and
- Gemini: `~/.gemini/skills`.

Global and Codex intentionally share one directory and therefore produce one
configured source. Automatic discovery does not traverse the account home or
search outside these candidates. A candidate is configured only when it exists
as a directory. Scanning then enumerates one direct-child level, skips hidden
entries and non-directories, and accepts only child directories containing a
`SKILL.md`. Discovery reads skill metadata and content for presentation but does
not write, move, or delete skill contents.

The `sources.json` configuration stores both configured sources and durable
automatic-directory exclusions. Removing an automatically recognized standard
directory records its identity as an exclusion so it does not return at the next
launch. Explicitly adding the same physical directory removes that exclusion.

Automatic deduplication and exclusions use a canonical identity that resolves
symbolic links, normalizes the path, and applies directory URL semantics. This
means, for example, that a dotfiles target selected in the folder picker and a
standard path that is a symbolic link to that target represent the same physical
directory. Persisted source aliases that resolve to the same identity are
coalesced when loaded, preserving the first configured source and its
user-selected URL. Persisted exclusion identities are also canonicalized on
load, and restoration then attempts to save the normalized configuration.
Configured source URLs remain in their user-selected form for display and
filesystem access; canonicalization applies only to internal identity keys.

Restoration publishes a successfully loaded and reconciled configuration to the
in-memory library before attempting to save reconciliation changes. If that save
fails, the app reports the failure without discarding the loaded or automatically
detected sources. A later successful source mutation persists the complete
in-memory configuration, including those sources and exclusions.

## Local containment and availability

Only standard account-home-relative agent directories are mutable. Existing
components from the account home through a source, skill, and manifest must not
be symbolic links. Skill directories must resolve as real direct children of the
selected source.

An install destination must not exist before launch. Success requires that exact
destination to be a real directory containing a regular, non-symbolic
`SKILL.md`. Every install failure after process launch that represents a nonzero
exit, timeout, cancellation, or failed postcondition computes a best-effort
source-name delta. The error reports at most ten sorted names, escapes each name
with `String(reflecting:)`, includes the number of omitted names, and does not
remove entries automatically. Generic nonzero-exit errors also warn that partial
filesystem changes may remain. Removal success requires the exact directory
entry to be absent, so a stale directory or dangling symlink cannot satisfy the
check. The source boundary is checked again after a successful process exit.

Process execution has a five-minute deadline. Cancelling the calling task sends
termination immediately. Timeout and cancellation both escalate to a forced
stop after a one-second grace period, and the operation does not return until
Foundation reports that the directly launched `npx` process exited. This does
not establish that descendants have exited; they may continue previously started
work, and the user-facing errors state that limitation.

The app target enables Hardened Runtime. App Sandbox remains disabled because
the external Node/npm process requires executable, network, and standard agent
directory access; restoring App Sandbox requires a separately reviewed helper
design.

## Accepted residual risk

These controls deliberately do not claim a complete software-supply-chain or
content sandbox:

- npm registry TLS and registry-supplied integrity metadata remain trusted. The
  known top-level tarball hash is recorded for review, but the app does not
  independently download and attest the tarball or pin every transitive runtime
  dependency.
- The locally resolved `npx`, its sibling `node`, and fixed-path Git executable
  are part of the user's development environment and are not code-signature
  attested by the app.
- Community repositories and installed `SKILL.md` instructions remain untrusted.
  The official CLI's warning to review skills before use still applies.
- The upstream CLI chooses the final sanitized install name. If it differs from
  the catalog slug, the app reports a capped and escaped source-name delta and
  leaves observed entries on disk for review. This is explicitly an "entries
  observed so far" report: unsupervised descendants may write after it is
  computed, and a name-only snapshot cannot detect changes inside entries that
  existed before launch, attribute concurrent same-user writes, or roll back
  unexpected content.
- Path checks reduce accidental redirection and persistent symlink attacks, but
  they are path-based checks around an external process, not descriptor-based
  filesystem capabilities. A malicious process already running as the same user
  could race filesystem changes.
- Deadline and cancellation signals target the launched `npx` process. The app
  does not create and supervise a separate POSIX process group for every
  descendant the upstream CLI may spawn, so descendant work may continue after
  the direct process is reported stopped.
- Disabling App Sandbox gives the app and child process the signed-in user's
  ambient filesystem access. Hardened Runtime does not replace sandbox
  isolation.

Any CLI version change, registry change, update-scope change, independent package
attestation work, or sandbox/helper design requires a new security review and an
updated dependency record here.
