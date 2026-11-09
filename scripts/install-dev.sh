#!/usr/bin/env bash
# Build and install the personal app without Sparkle replacing it with upstream releases.
set -euo pipefail
cd "$(dirname "$0")/.."

destination="${DINKY_APPLICATIONS_DIR:-/Applications}/Dinky Dev.app"
identity="${IDENTITY:--}"
version="${VERSION:-$(git describe --tags --match 'v*' --abbrev=0)}"
version="${version#v}"
build="$(git rev-list --count HEAD)"
stage=""
stopped=false
was_running=false
installed=false
cli_changed=false
previous_cli=""
if [[ -n "${DINKY_BIN_DIR:-}" ]]; then
  bin_dir="$DINKY_BIN_DIR"
elif [[ -d /opt/homebrew/bin ]]; then
  bin_dir=/opt/homebrew/bin
else
  bin_dir=/usr/local/bin
fi
cli="$bin_dir/dinky"
if [[ -L "$cli" ]]; then
  previous_cli="$(readlink "$cli")"
elif [[ -e "$cli" ]]; then
  echo "Refusing to replace a non-symlink CLI: $cli" >&2
  exit 1
fi

cleanup() {
  local status=$?
  trap - EXIT
  if [[ $status -ne 0 ]]; then
    if $installed; then rm -rf "$destination"; fi
    if [[ -n "$stage" && -d "$stage/previous.app" ]]; then
      mv "$stage/previous.app" "$destination"
    fi
    if $cli_changed; then
      if [[ -n "$previous_cli" ]]; then ln -sfn "$previous_cli" "$cli"
      else rm -f "$cli"
      fi
    fi
    if $stopped && $was_running; then
      if [[ -d "$destination" ]]; then open "$destination" || true
      elif [[ -d 'build/Dinky Dev.app' ]]; then open 'build/Dinky Dev.app' || true
      fi
    fi
  fi
  if [[ -n "$stage" ]]; then rm -rf "$stage"; fi
  exit "$status"
}
trap cleanup EXIT
mkdir -p "$bin_dir"
[[ -w "$bin_dir" ]] || { echo "CLI directory is not writable: $bin_dir" >&2; exit 1; }

# Leave the running app alone until compilation and signing have succeeded.
echo 'Building Dinky Dev...'
swift build -c debug --jobs 4
binary="$(swift build -c debug --jobs 4 --show-bin-path)/dinky"
[[ -x "$binary" ]] || { echo "Missing executable: $binary" >&2; exit 1; }
framework="$(find .build/artifacts -maxdepth 6 -path '*macos-arm64_x86_64/Sparkle.framework' -print -quit)"
[[ -n "$framework" ]] || { echo 'Sparkle.framework not found' >&2; exit 1; }

stage="$(mktemp -d "$(dirname "$destination")/.dinky-dev.XXXXXX")"
app="$stage/Dinky Dev.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
cp "$binary" "$app/Contents/MacOS/dinky"
cp Resources/Info.plist "$app/Contents/Info.plist"
plist="$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.brnbw.dinky.dev "$plist"
plutil -replace CFBundleName -string 'Dinky Dev' "$plist"
plutil -replace CFBundleDisplayName -string 'Dinky Dev' "$plist"
plutil -replace CFBundleShortVersionString -string "$version" "$plist"
plutil -replace CFBundleVersion -string "$build" "$plist"
plutil -remove SUFeedURL "$plist"
plutil -remove SUPublicEDKey "$plist"
# Keep an existing icon; a local dev build needs only the Command Line Tools, not actool/Xcode.
for old_app in "$destination" 'build/Dinky Dev.app'; do
  if [[ -d "$old_app/Contents/Resources" ]]; then
    ditto "$old_app/Contents/Resources" "$app/Contents/Resources"
    break
  fi
done
ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
sparkle="$app/Contents/Frameworks/Sparkle.framework"
for item in XPCServices/Downloader.xpc XPCServices/Installer.xpc Updater.app Autoupdate Sparkle; do
  codesign --force --sign "$identity" "$sparkle/Versions/Current/$item"
done
codesign --force --sign "$identity" "$sparkle"
codesign --force --sign "$identity" "$app"
codesign --verify --deep --strict "$app"

if pgrep -x dinky >/dev/null; then
  was_running=true
  echo 'Quitting Dinky cleanly...'
  pkill -TERM -x dinky || true
  stopped=true
  for ((attempt = 0; attempt < 100; attempt++)); do
    if ! pgrep -x dinky >/dev/null; then break; fi
    sleep 0.1
  done
  if pgrep -x dinky >/dev/null; then
    echo 'Dinky did not quit within 10 seconds; the installed app was left in place.' >&2
    exit 1
  fi
fi

if [[ -e "$destination" ]]; then mv "$destination" "$stage/previous.app"; fi
mv "$app" "$destination"
installed=true
# SketchyBar and other shell integrations call dinky through Homebrew's PATH.
ln -sfn "$destination/Contents/MacOS/dinky" "$cli"
cli_changed=true
open "$destination"
sleep 1
if ! pgrep -x dinky >/dev/null; then
  echo 'Dinky Dev exited during launch; restoring the previous app.' >&2
  exit 1
fi
if [[ -d "$stage/previous.app" ]]; then
  backup="build/dev-app-backups/$(date -u +%Y%m%dT%H%M%SZ)-$$"
  mkdir -p "$backup"
  mv "$stage/previous.app" "$backup/Dinky Dev.app"
  echo "Previous app: $PWD/$backup/Dinky Dev.app"
fi
echo "Started $destination ($version build $build)"
echo "CLI: $cli -> $destination/Contents/MacOS/dinky"
if [[ "$identity" == - ]]; then
  echo 'Ad-hoc signed: macOS may require granting Dinky Dev Accessibility again.'
fi
