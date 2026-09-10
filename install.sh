#!/usr/bin/env bash
# Installs the latest Switchr release into Applications and opens it.
#
#   curl -fsSL https://raw.githubusercontent.com/dominikzabcik/switchr/main/install.sh | bash
#
# Files downloaded by curl or the GitHub CLI carry no quarantine flag, so macOS opens
# Switchr without the unidentified-developer prompt.
set -euo pipefail

REPO="dominikzabcik/switchr"

if [[ -t 1 ]]; then
  BONE=$'\033[38;2;237;231;217m'
  AMBER=$'\033[38;2;207;159;87m'
  GROOVE=$'\033[38;2;44;62;53m'
  DIM=$'\033[38;2;140;158;148m'
  RED=$'\033[38;2;214;124;108m'
  BOLD=$'\033[1m'
  RESET=$'\033[0m'
  CLEAR=$'\r\033[K'
else
  BONE="" AMBER="" GROOVE="" DIM="" RED="" BOLD="" RESET="" CLEAR=""
fi

CELLS=12
TMP=$(mktemp -d -t switchr)
LOG="$TMP/log"
trap 'rm -rf "$TMP"' EXIT

# A track like the one in Switchr's icon: cells from $1 to $2 filled with $3, the rest groove.
track() {
  local from=$1 to=$2 color=$3 out="" i
  for ((i = 0; i < CELLS; i++)); do
    if ((i >= from && i < to)); then out+="${color}━"; else out+="${GROOVE}━"; fi
  done
  printf '%s%s' "$out" "$RESET"
}

fail() {
  printf '%s  %s%s%s\n' "$CLEAR" "$RED" "$1" "$RESET" >&2
  [[ -s $LOG ]] && sed 's/^/    /' "$LOG" >&2
  exit 1
}

done_line() {
  printf '%s  %s  %s\n' "$CLEAR" "$(track 0 "$CELLS" "$AMBER")" "$1"
}

# Runs a step while its track fills and empties; leaves a full track when it finishes.
step() {
  local label=$1
  shift
  if [[ -z $CLEAR ]]; then
    "$@" >"$LOG" 2>&1 || fail "$label failed"
    printf '  done  %s\n' "$label"
    return
  fi
  "$@" >"$LOG" 2>&1 &
  local pid=$! i=0 lead
  while kill -0 "$pid" 2>/dev/null; do
    lead=$((i % (CELLS * 2)))
    if ((lead < CELLS)); then
      printf '%s  %s  %s%s%s' "$CLEAR" "$(track 0 $((lead + 1)) "$BONE")" "$DIM" "$label" "$RESET"
    else
      printf '%s  %s  %s%s%s' "$CLEAR" "$(track $((lead - CELLS + 1)) "$CELLS" "$BONE")" "$DIM" "$label" "$RESET"
    fi
    i=$((i + 1))
    sleep 0.05
  done
  wait "$pid" || fail "$label failed"
  done_line "$label"
}

check_mac() {
  local version major
  version=$(sw_vers -productVersion)
  major=${version%%.*}
  if ((major < 14)); then
    echo "Switchr needs macOS 14 or later. This Mac runs $version."
    return 1
  fi
}

download() {
  if [[ $SOURCE == gh ]]; then
    gh release download "$TAG" --repo "$REPO" --pattern Switchr.zip --pattern SHA256SUMS --dir "$TMP"
  else
    curl -fsSL "https://github.com/$REPO/releases/download/$TAG/Switchr.zip" -o "$TMP/Switchr.zip"
    curl -fsSL "https://github.com/$REPO/releases/download/$TAG/SHA256SUMS" -o "$TMP/SHA256SUMS" || true
  fi
}

verify() {
  if [[ ! -s $TMP/SHA256SUMS ]]; then
    echo "This release has no checksum file."
    return 1
  fi
  (cd "$TMP" && grep ' Switchr.zip$' SHA256SUMS | shasum -a 256 -c -)
}

install_app() {
  local destination=/Applications
  if [[ ! -w $destination ]]; then
    destination="$HOME/Applications"
    mkdir -p "$destination"
  fi
  if pgrep -x Switchr >/dev/null; then
    osascript -e 'quit app "Switchr"' || true
    sleep 1
    pkill -x Switchr || true
  fi
  ditto -x -k "$TMP/Switchr.zip" "$TMP/unpacked"
  rm -rf "$destination/Switchr.app"
  ditto "$TMP/unpacked/Switchr.app" "$destination/Switchr.app"
  xattr -dr com.apple.quarantine "$destination/Switchr.app" 2>/dev/null || true
  echo "$destination/Switchr.app" >"$TMP/installed"
}

# ---

printf '\n  %s   %sSwitchr%s\n' "$(track 0 7 "$BONE")" "$BOLD" "$RESET"
printf '  %s   %sYour AI accounts, one click apart.%s\n\n' "$(track 5 "$CELLS" "$AMBER")" "$DIM" "$RESET"

step "Checking this Mac" check_mac

if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  SOURCE=gh
  TAG=$(gh release view --repo "$REPO" --json tagName -q .tagName 2>"$LOG") || fail "Couldn't read the latest Switchr release."
elif curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" -o "$TMP/release.json" 2>"$LOG"; then
  SOURCE=curl
  TAG=$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' "$TMP/release.json" | head -n 1)
else
  fail "Couldn't reach GitHub to find the latest Switchr release. Check your connection and try again."
fi
[[ -n $TAG ]] || fail "Couldn't find a Switchr release."
done_line "Found Switchr ${TAG#v}"

step "Downloading" download
step "Verifying checksum" verify
step "Installing" install_app

APP_PATH=$(cat "$TMP/installed")
open "$APP_PATH"

found=()
if command -v claude >/dev/null 2>&1 || [[ -d $HOME/.claude ]]; then found+=("Claude Code"); fi
if [[ -d /Applications/Cursor.app || -d $HOME/Applications/Cursor.app ]]; then found+=("Cursor"); fi
if command -v codex >/dev/null 2>&1 || [[ -f $HOME/.codex/auth.json ]]; then found+=("Codex"); fi

printf '\n  %sSwitchr is in your menu bar%s %s↗%s\n' "$BOLD" "$RESET" "$AMBER" "$RESET"
if ((${#found[@]} > 0)); then
  list="${found[0]}"
  for ((i = 1; i < ${#found[@]}; i++)); do list+=", ${found[i]}"; done
  printf '  %sIt picks up the logins you already have in %s.%s\n' "$DIM" "$list" "$RESET"
fi
printf '  %sInstalled at %s%s\n\n' "$DIM" "$APP_PATH" "$RESET"
