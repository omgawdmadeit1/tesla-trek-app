#!/usr/bin/env bash
# Select Xcode 27.1 or newer when it is installed, so the archive links the
# iOS 27.1 SDK. That SDK is what makes an iPhone app full-bleed on iPhone Duo.
# When the toolchain is missing this script records the blocker and exits 0.
# The TestFlight workflow turns that record into a failed upload on purpose.
set -euo pipefail

note() { printf '%s\n' "$*"; }

write_env() {
  local key="$1"
  local value="$2"
  if [ -n "${GITHUB_ENV:-}" ]; then
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_ENV"
  fi
  export "${key}=${value}"
}

version_of() {
  local app="$1"
  local bin="${app}/Contents/Developer/usr/bin/xcodebuild"
  if [ ! -x "$bin" ]; then
    return 1
  fi
  "$bin" -version 2>/dev/null | awk 'NR==1 { print $2; exit }'
}

is_duo() {
  local version="$1"
  local major="${version%%.*}"
  local rest="${version#*.}"
  local minor="${rest%%.*}"
  case "$major" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$minor" in
    ''|*[!0-9]*) minor=0 ;;
  esac
  if [ "$major" -gt 27 ]; then
    return 0
  fi
  if [ "$major" -eq 27 ] && [ "$minor" -ge 1 ]; then
    return 0
  fi
  return 1
}

best_app=""
best_ver=""
shopt -s nullglob
for app in /Applications/Xcode.app /Applications/Xcode_*.app; do
  [ -d "$app" ] || continue
  ver="$(version_of "$app" || true)"
  [ -n "${ver}" ] || continue
  if ! is_duo "$ver"; then
    continue
  fi
  if [ -z "$best_ver" ]; then
    best_app="$app"
    best_ver="$ver"
    continue
  fi
  top="$(printf '%s\n%s\n' "$best_ver" "$ver" | sort -V | tail -n 1)"
  if [ "$top" = "$ver" ]; then
    best_app="$app"
    best_ver="$ver"
  fi
done

if [ -n "$best_app" ]; then
  dev="${best_app}/Contents/Developer"
  if ! xcode-select -s "$dev" 2>/dev/null; then
    if ! sudo xcode-select -s "$dev" 2>/dev/null; then
      note "Found ${best_app} (Xcode ${best_ver}) but xcode-select could not switch to it."
      best_app=""
      best_ver=""
    fi
  fi
fi

current="xcodebuild is not installed"
if command -v xcodebuild >/dev/null 2>&1; then
  current="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
fi

if [ -n "$best_app" ]; then
  write_env TR3K_XCODE_DUO 1
  write_env TR3K_XCODE_VERSION "$best_ver"
  note "Selected ${best_app} (Xcode ${best_ver}) for the iOS 27.1 Duo SDK."
  note "Active toolchain: ${current}"
  exit 0
fi

write_env TR3K_XCODE_DUO 0
write_env TR3K_XCODE_VERSION none
note "Xcode 27.1 or newer is not installed on this machine."
note "Active toolchain: ${current}"
note "An iPhone Duo archive has to be built with the iOS 27.1 SDK. Full-bleed layout, vertical system bars, and the Made for iPhone Duo treatment come from that SDK."
note "The deployment target stays iOS 15.0. Raising it is not how Duo support is turned on."
note "Archive steps are in docs/iphone-duo.md."
exit 0
