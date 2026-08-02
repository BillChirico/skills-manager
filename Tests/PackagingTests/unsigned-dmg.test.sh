#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/../.." && pwd -P)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/skills-manager-packaging-test.XXXXXX")"

cleanup() {
  status=$?
  trap - EXIT INT TERM
  rm -rf -- "$test_root" "$repo_root/build/packaging-test"
  exit "$status"
}
trap cleanup EXIT INT TERM

fake_bin="$test_root/bin"
fake_log="$test_root/log"
fake_tmp="$test_root/tmp"
dmg_path="$repo_root/build/packaging-test/SkillsManager-unsigned.dmg"
mkdir -p "$fake_bin" "$fake_log" "$fake_tmp" "$repo_root/build/packaging-test"

if bash "$repo_root/scripts/build-unsigned-dmg.sh" '../x.dmg' \
  > "$fake_log/traversal.stdout" \
  2> "$fake_log/traversal.stderr"; then
  echo 'build script accepted a DMG path outside the repository' >&2
  exit 1
fi
grep -F -- 'must remain inside the repository' "$fake_log/traversal.stderr" > /dev/null

if bash "$repo_root/scripts/verify-unsigned-dmg.sh" '../x.dmg' \
  > "$fake_log/verify-traversal.stdout" \
  2> "$fake_log/verify-traversal.stderr"; then
  echo 'verify script accepted a DMG path outside the repository' >&2
  exit 1
fi
grep -F -- 'must remain inside the repository' "$fake_log/verify-traversal.stderr" > /dev/null

cat > "$fake_bin/xcodebuild" <<'FAKE_XCODEBUILD'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" > "$FAKE_LOG_DIR/xcodebuild.args"

archive_path=''
while (($# > 0)); do
  case "$1" in
    -archivePath)
      archive_path="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -z "$archive_path" ]]; then
  echo 'fake xcodebuild: missing -archivePath' >&2
  exit 1
fi

app_path="$archive_path/Products/Applications/SkillsManager.app"
mkdir -p "$app_path/Contents/MacOS"
printf '#!/bin/sh\nexit 0\n' > "$app_path/Contents/MacOS/SkillsManager"
chmod +x "$app_path/Contents/MacOS/SkillsManager"
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict/></plist>' \
  > "$app_path/Contents/Info.plist"
FAKE_XCODEBUILD

cat > "$fake_bin/ditto" <<'FAKE_DITTO'
#!/usr/bin/env bash
set -euo pipefail

if (($# != 2)); then
  echo 'fake ditto: expected source and destination' >&2
  exit 1
fi

cp -R "$1" "$2"
FAKE_DITTO

cat > "$fake_bin/plutil" <<'FAKE_PLUTIL'
#!/usr/bin/env bash
set -euo pipefail

if (($# != 2)) || [[ "$1" != '-lint' ]] || [[ ! -f "$2" ]]; then
  echo 'fake plutil: expected -lint and an existing file' >&2
  exit 1
fi
FAKE_PLUTIL

cat > "$fake_bin/hdiutil" <<'FAKE_HDIUTIL'
#!/usr/bin/env bash
set -euo pipefail

subcommand="$1"
shift

case "$subcommand" in
  create)
    source_folder=''
    output_path="${!#}"
    while (($# > 0)); do
      case "$1" in
        -srcfolder)
          source_folder="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [[ -z "$source_folder" ]]; then
      echo 'fake hdiutil: missing -srcfolder' >&2
      exit 1
    fi
    mkdir -p "$(dirname "$output_path")"
    cp -R "$source_folder" "$output_path.contents"
    printf 'fake dmg\n' > "$output_path"
    ;;
  verify)
    test -f "$1"
    ;;
  attach)
    mount_point=''
    dmg_path="${!#}"
    while (($# > 0)); do
      case "$1" in
        -mountpoint)
          mount_point="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [[ -z "$mount_point" ]] || [[ ! -d "$dmg_path.contents" ]]; then
      echo 'fake hdiutil: missing mount point or image contents' >&2
      exit 1
    fi
    cp -R "$dmg_path.contents/." "$mount_point"
    ;;
  detach)
    mount_point="$1"
    rm -rf -- "$mount_point"
    mkdir -p "$mount_point"
    printf '%s\n' "$mount_point" > "$FAKE_LOG_DIR/detached"
    ;;
  *)
    echo "fake hdiutil: unsupported subcommand $subcommand" >&2
    exit 1
    ;;
esac
FAKE_HDIUTIL

chmod +x "$fake_bin/xcodebuild" "$fake_bin/ditto" "$fake_bin/plutil" "$fake_bin/hdiutil"

export FAKE_LOG_DIR="$fake_log"
export PATH="$fake_bin:$PATH"
export TMPDIR="$fake_tmp"
export MSYS='winsymlinks:sys'

cd "$repo_root"
bash scripts/build-unsigned-dmg.sh "$dmg_path"
bash scripts/verify-unsigned-dmg.sh "$dmg_path"

test -f "$dmg_path"
test -d "$dmg_path.contents/Skills Manager.app"
test -x "$dmg_path.contents/Skills Manager.app/Contents/MacOS/SkillsManager"
test -L "$dmg_path.contents/Applications"
test "$(readlink "$dmg_path.contents/Applications")" = '/Applications'
test ! -e "$dmg_path.contents/Skills Manager.app/Contents/_CodeSignature"
test -f "$fake_log/detached"

grep -F -- '-configuration Release' "$fake_log/xcodebuild.args" > /dev/null
grep -F -- 'CODE_SIGNING_ALLOWED=NO' "$fake_log/xcodebuild.args" > /dev/null
grep -F -- 'archive' "$fake_log/xcodebuild.args" > /dev/null

mkdir -p "$dmg_path.contents/Skills Manager.app/Contents/_CodeSignature"
rm -f "$fake_log/detached"
if bash scripts/verify-unsigned-dmg.sh "$dmg_path" \
  > "$fake_log/signed-verification.stdout" \
  2> "$fake_log/signed-verification.stderr"; then
  echo 'verifier accepted an unexpectedly signed app bundle' >&2
  exit 1
fi
grep -F -- 'unexpectedly contains a code-signature directory' \
  "$fake_log/signed-verification.stderr" > /dev/null
test -f "$fake_log/detached"
rmdir "$dmg_path.contents/Skills Manager.app/Contents/_CodeSignature"

rm -f "$dmg_path.contents/Applications" "$fake_log/detached"
if bash scripts/verify-unsigned-dmg.sh "$dmg_path" \
  > "$fake_log/layout-verification.stdout" \
  2> "$fake_log/layout-verification.stderr"; then
  echo 'verifier accepted a DMG without the Applications shortcut' >&2
  exit 1
fi
grep -F -- 'does not contain an Applications symlink' \
  "$fake_log/layout-verification.stderr" > /dev/null
test -f "$fake_log/detached"

if find "$fake_tmp" -mindepth 1 -maxdepth 1 -name 'skills-manager-dmg-*' -print -quit \
  | grep -q .; then
  echo 'packaging scripts left a temporary workspace behind' >&2
  exit 1
fi

echo 'unsigned DMG packaging tests passed'
