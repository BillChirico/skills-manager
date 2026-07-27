# Skills Manager

Skills Manager is a native macOS app for finding and managing the agent skills
stored on your machine.

The current product surface includes:

- a SwiftUI three-column library with smart groups, scoped search, multi-select,
  detail tabs, and recovery-focused empty states;
- persistent user-selected directories backed by security-scoped bookmarks;
- one-click suggested locations for the shared `~/.agents/skills` folder, Claude
  Code, Codex, Cursor, Gemini, and GitHub Copilot, listed only while the folder
  exists, plus a picker for any other directory;
- per-directory agent assignments for Global, Claude Code, Codex, Cursor,
  Gemini, GitHub Copilot, and other tools;
- local `SKILL.md` discovery with stable skill identities across rescans;
- skills.sh search and one-click installation for GitHub-backed catalog skills;
- name, date-added, and agent sorting, with the agent and source shown on every
  skill row;
- right-click actions for updating, enabling, revealing, opening, copying the
  path of, and removing a skill;
- directory rename, agent assignment, enable, rescan, reveal, and remove
  controls;
- a resizable Settings folder list with native plus/minus management controls,
  per-folder enabled toggles, unavailable-folder reconnect actions, agent-aware
  suggested locations, and non-destructive removal;
- a prominent Discover toolbar action, icon-only Settings access, and the
  standard Settings app-menu command;
- independent enabled and update-availability state for each skill;
- a reusable `SkillsCore` Swift package for discovery, persistence, models,
  filtering, search, catalog access, and safe package installation;
- Swift Testing coverage for the core package and app state;
- an XcodeGen project specification and generated Xcode project; and
- contributor and AI-agent guidance.

The app deploys to macOS 15 and adopts Liquid Glass when running on macOS 26 or
newer, with a material-based fallback on earlier supported versions.

## Requirements

- macOS 15 or newer
- Xcode 26 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46 or newer

Install XcodeGen with Homebrew:

```sh
brew install xcodegen
```

## Getting started

Generate the Xcode project, then open it:

```sh
make generate
open SkillsManager.xcodeproj
```

The generated project is committed so that a fresh clone can also be opened
immediately. Run `make generate` after changing `project.yml`.

## Validation

```sh
make test
make build
make check
```

`make test` exercises the standalone domain package and does not require the
full Xcode app. `make build` and the app unit tests require Xcode. Swift sources
are formatted with the `swift format` command included in the Swift toolchain;
run `make lint` for a non-mutating style check.

## Catalog installation

The Discover Skills window searches skills.sh after two or more characters.
GitHub-backed results can be installed into any enabled, available agent
directory. Installation downloads only the selected skill directory, validates
every relative path, caps package size and file count, stages the files before
moving them into place, and never replaces an existing directory.

Skills are copied as data and are not executed during installation. Review a
skill on skills.sh or inspect its files before using it with an agent.

## Directory access

Settings lists every configured skill folder. Its plus menu suggests each
supported agent’s standard user location — `Global — ~/.agents/skills`,
`Claude Code — ~/.claude/skills`, and the rest — and lists a suggestion only
while that folder exists on the account home, so the menu never offers a folder
you have not created. Choosing one adds it directly, with no picker step. A
single `Add Folder…` action below the suggestions opens the system picker for
any other directory.

`Global` and `Codex` both resolve to `~/.agents/skills`, the cross-agent
convention Codex also reads, so both suggestions appear when that folder exists.
Adding the second one re-selects the folder the first one configured instead of
listing it twice.

Direct add works whenever Skills Manager already has access to the folder. A
sandboxed build only receives access to folders the user confirms, so when the
sandbox denies a suggestion the app falls back to the system directory picker
opened at that same location. Empty library states open Settings rather than
duplicating this picker flow. Settings itself includes an Add Folder action when
the list is empty.

Confirmed directories are opened as security-scoped resources before the app
creates and stores their bookmarks. This keeps the initial scan and access after
relaunch covered by the same user grant. Settings opens without selecting a
folder on the user's behalf. Each row can pause or resume scanning, unavailable
rows can reconnect through the system picker, and paths under the home directory
are abbreviated with `~`. Selecting a row and using the minus control removes
only the Skills Manager configuration after confirmation; the folder and its
files remain on disk.

## Repository layout

```text
SkillsManager/                  SwiftUI application target
  App/                          app entry point and shared app state
  Features/                     feature-oriented views
  Shared/                       reusable app-only presentation components
  Resources/                    asset catalogs
  Support/                      entitlements and target support files
Packages/SkillsCore/            platform-light domain package and tests
Tests/SkillsManagerTests/       app-state unit tests
docs/                           architecture and engineering decisions
project.yml                     source of truth for the Xcode project
SkillsManager.xcodeproj/        generated, committed Xcode project
```

See [Architecture](docs/ARCHITECTURE.md) for dependency boundaries and planned
extension points. See [AGENTS.md](AGENTS.md) for repository conventions that
apply to both human and AI contributors.

## License

Skills Manager is available under the [MIT License](LICENSE).
