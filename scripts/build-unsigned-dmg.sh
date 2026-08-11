#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/.." && pwd -P)"
output_path="${1:-$repo_root/build/release/SkillsManager-unsigned.dmg}"

case "$output_path" in
  /*) ;;
  *) output_path="$repo_root/$output_path" ;;
esac

case "$output_path" in
  *.dmg) ;;
  *)
    echo "error: DMG output path must end in .dmg: $output_path" >&2
    exit 1
    ;;
esac

for required_command in xcodebuild ditto hdiutil plutil; do
  if ! command -v "$required_command" > /dev/null 2>&1; then
    echo "error: required command not found: $required_command" >&2
    exit 1
  fi
done

workspace="$(mktemp -d "${TMPDIR:-/tmp}/skills-manager-dmg-build.XXXXXX")"
cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$workspace"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

archive_path="$workspace/SkillsManager.xcarchive"
staging_root="$workspace/dmg-root"
archived_app="$archive_path/Products/Applications/SkillsManager.app"
archived_executable="$archived_app/Contents/MacOS/SkillsManager"
archived_info_plist="$archived_app/Contents/Info.plist"

mkdir -p "$staging_root" "$(dirname "$output_path")"

xcodebuild \
  -project "$repo_root/SkillsManager.xcodeproj" \
  -scheme SkillsManager \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  CODE_SIGNING_ALLOWED=NO \
  archive

if [[ ! -d "$archived_app" ]]; then
  echo "error: archive did not contain SkillsManager.app" >&2
  exit 1
fi
if [[ ! -x "$archived_executable" ]]; then
  echo "error: archived app executable is missing or not executable" >&2
  exit 1
fi
if [[ ! -f "$archived_info_plist" ]]; then
  echo "error: archived app Info.plist is missing" >&2
  exit 1
fi
plutil -lint "$archived_info_plist" > /dev/null

if [[ -e "$archived_app/Contents/_CodeSignature" ]]; then
  echo "error: unsigned archive unexpectedly contains a code-signature directory" >&2
  exit 1
fi

ditto "$archived_app" "$staging_root/Skills Manager.app"
ln -s /Applications "$staging_root/Applications"

hdiutil create \
  -volname 'Skills Manager' \
  -srcfolder "$staging_root" \
  -ov \
  -format UDZO \
  "$output_path"

if [[ ! -f "$output_path" ]]; then
  echo "error: hdiutil did not create the expected DMG" >&2
  exit 1
fi

echo "Created unsigned DMG: $output_path"
