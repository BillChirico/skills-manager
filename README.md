# Skills Manager

Skills Manager is a native macOS app for finding and managing the agent skills
stored on your machine.

The current product surface includes:

- a SwiftUI three-column library with smart groups, scoped search, multi-select,
  detail tabs, and recovery-focused empty states;
- persistent user-selected directories backed by security-scoped bookmarks;
- per-directory agent assignments for Claude Code, Codex, Cursor, Gemini,
  GitHub Copilot, and other tools;
- local `SKILL.md` discovery with stable skill identities across rescans;
- skills.sh search and one-click installation for GitHub-backed catalog skills;
- name, date-added, and agent sorting, with the agent and source shown on every
  skill row;
- right-click actions for updating, enabling, revealing, opening, copying the
  path of, and removing a skill;
- directory rename, agent assignment, enable, rescan, reveal, and remove
  controls;
- Settings access from the toolbar and the standard app menu;
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
