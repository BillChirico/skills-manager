#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/.." && pwd -P)"
dmg_path="${1:-$repo_root/build/release/SkillsManager-unsigned.dmg}"

case "$dmg_path" in
  /*) ;;
  *) dmg_path="$repo_root/$dmg_path" ;;
esac

if [[ ! -f "$dmg_path" ]]; then
  echo "error: DMG does not exist: $dmg_path" >&2
  exit 1
fi

for required_command in hdiutil plutil; do
  if ! command -v "$required_command" > /dev/null 2>&1; then
    echo "error: required command not found: $required_command" >&2
    exit 1
  fi
done

hdiutil verify "$dmg_path" > /dev/null

mount_point="$(mktemp -d "${TMPDIR:-/tmp}/skills-manager-dmg-verify.XXXXXX")"
attached=0
cleanup() {
  status=$?
  trap - EXIT

  if ((attached == 1)); then
    if hdiutil detach "$mount_point" > /dev/null; then
      attached=0
    else
      echo "error: failed to detach DMG from $mount_point" >&2
      status=1
    fi
  fi

  if ((attached == 0)) && [[ -d "$mount_point" ]]; then
    if ! rmdir "$mount_point"; then
      echo "error: DMG mount point was not empty after detach: $mount_point" >&2
      status=1
    fi
  fi

  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

hdiutil attach \
  -nobrowse \
  -readonly \
  -mountpoint "$mount_point" \
  "$dmg_path" > /dev/null
attached=1

installed_app="$mount_point/Skills Manager.app"
installed_executable="$installed_app/Contents/MacOS/SkillsManager"
installed_info_plist="$installed_app/Contents/Info.plist"
applications_link="$mount_point/Applications"

if [[ ! -d "$installed_app" ]]; then
  echo "error: DMG does not contain Skills Manager.app" >&2
  exit 1
fi
if [[ ! -x "$installed_executable" ]]; then
  echo "error: DMG app executable is missing or not executable" >&2
  exit 1
fi
if [[ ! -f "$installed_info_plist" ]]; then
  echo "error: DMG app Info.plist is missing" >&2
  exit 1
fi
plutil -lint "$installed_info_plist" > /dev/null

if [[ -e "$installed_app/Contents/_CodeSignature" ]]; then
  echo "error: unsigned DMG unexpectedly contains a code-signature directory" >&2
  exit 1
fi
if [[ ! -L "$applications_link" ]]; then
  echo "error: DMG does not contain an Applications symlink" >&2
  exit 1
fi
if [[ "$(readlink "$applications_link")" != '/Applications' ]]; then
  echo "error: DMG Applications symlink does not target /Applications" >&2
  exit 1
fi

echo "Verified unsigned DMG: $dmg_path"
