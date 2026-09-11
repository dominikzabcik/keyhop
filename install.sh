#!/usr/bin/env bash
# Installs the latest Switchr release and opens it.
#
#   curl -fsSL https://raw.githubusercontent.com/dominikzabcik/switchr/main/install.sh | bash
#
# macOS: into Applications. Files downloaded by curl or the GitHub CLI carry no quarantine
# flag, so macOS opens Switchr without the unidentified-developer prompt.
# Linux: the RPM, DEB or Arch package through dnf, apt or pacman, or with SWITCHR_LOCAL=1
# (or no known package manager) the portable build into ~/.local, without root.
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
OS=$(uname -s)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/switchr.XXXXXX")
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

# Copies a release file into $TMP: from SWITCHR_INSTALL_FROM when set (a folder holding the release
# files and their SHA256SUMS, for testing unpublished builds), otherwise from GitHub.
fetch() {
  if [[ -n ${SWITCHR_INSTALL_FROM:-} ]]; then
    cp "$SWITCHR_INSTALL_FROM/$1" "$TMP/$1"
  else
    curl -fsSL "https://github.com/$REPO/releases/download/$TAG/$1" -o "$TMP/$1"
  fi
}

download() {
  if [[ $SOURCE == gh ]]; then
    gh release download "$TAG" --repo "$REPO" --pattern Switchr.zip --pattern SHA256SUMS --dir "$TMP"
  else
    fetch Switchr.zip
    fetch SHA256SUMS || true
  fi
}

# Links the app binary onto PATH as `switchr`, which makes it answer as the command.
link_command() {
  local app=$1 dir
  for dir in /opt/homebrew/bin /usr/local/bin; do
    if [[ -d $dir && -w $dir ]]; then
      ln -sf "$app/Contents/MacOS/Switchr" "$dir/switchr"
      echo "$dir/switchr" >"$TMP/command"
      return
    fi
  done
  mkdir -p "$HOME/.local/bin"
  ln -sf "$app/Contents/MacOS/Switchr" "$HOME/.local/bin/switchr"
  echo "$HOME/.local/bin/switchr" >"$TMP/command"
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

linux_architecture() {
  case "$(uname -m)" in
    x86_64) ARCH=x86_64 DEB_ARCH=amd64 ;;
    aarch64 | arm64) ARCH=aarch64 DEB_ARCH=arm64 ;;
    *) fail "Switchr builds for x86_64 and aarch64 Linux, not $(uname -m)." ;;
  esac
}

linux_choose_package() {
  local version=${TAG#v}
  if [[ -n ${SWITCHR_LOCAL:-} ]]; then
    KIND=local
  elif command -v dnf >/dev/null 2>&1; then
    KIND=rpm
  elif command -v apt-get >/dev/null 2>&1; then
    KIND=deb
  elif command -v pacman >/dev/null 2>&1; then
    KIND=pacman
  else
    KIND=local
  fi
  case $KIND in
    rpm) ASSET="switchr-$version-1.$ARCH.rpm" ;;
    deb) ASSET="switchr_${version}_$DEB_ARCH.deb" ;;
    pacman) ASSET="switchr-$version-1-$ARCH.pkg.tar.zst" ;;
    local) ASSET="switchr-$version-linux-$ARCH.tar.gz" ;;
  esac
  SUDO=""
  if [[ $KIND != local && $EUID -ne 0 ]]; then SUDO=sudo; fi
}

linux_download() {
  fetch "$ASSET"
  fetch SHA256SUMS
}

linux_verify() {
  (cd "$TMP" && grep " $ASSET\$" SHA256SUMS | sha256sum -c -)
}

linux_install() {
  case $KIND in
    rpm) $SUDO dnf install -y "$TMP/$ASSET" ;;
    deb) $SUDO apt-get install -y "$TMP/$ASSET" ;;
    pacman) $SUDO pacman -U --noconfirm "$TMP/$ASSET" ;;
    local) tar -xzf "$TMP/$ASSET" -C "$TMP" && sh "$TMP/switchr-${TAG#v}/install-local.sh" ;;
  esac
}

# Opens the tray at login, as the Mac app's welcome window does, and starts it now.
linux_start() {
  local bin=/usr/bin autostart="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
  [[ $KIND == local ]] && bin="$HOME/.local/bin"
  mkdir -p "$autostart"
  if [[ ! -f $autostart/dev.switchr.Switchr.desktop ]]; then
    printf '[Desktop Entry]\nType=Application\nName=Switchr\nExec=%s\nIcon=dev.switchr.Switchr\nX-GNOME-Autostart-enabled=true\nNoDisplay=true\n' \
      "$bin/switchr-tray" >"$autostart/dev.switchr.Switchr.desktop"
  fi
  if [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
    pkill -f "$bin/switchr-tray" 2>/dev/null || true
    nohup "$bin/switchr-tray" >/dev/null 2>&1 &
    disown
    TRAY_STARTED=true
  fi
}

linux_main() {
  linux_choose_package
  if [[ -n $SUDO ]]; then
    printf '  %sInstalling the %s package needs your password.%s\n' "$DIM" "$KIND" "$RESET"
    sudo -v || fail "Switchr needs administrator rights for the package. Run with SWITCHR_LOCAL=1 to install into ~/.local instead."
  fi
  step "Downloading $ASSET" linux_download
  step "Verifying checksum" linux_verify
  step "Installing" linux_install
  TRAY_STARTED=false
  linux_start

  if $TRAY_STARTED; then
    printf '\n  %sSwitchr is in your tray%s %s↗%s\n' "$BOLD" "$RESET" "$AMBER" "$RESET"
  else
    printf '\n  %sSwitchr is installed%s\n' "$BOLD" "$RESET"
  fi
  printf '  %sRun %sswitchr status%s%s to see your accounts, or %sswitchr help%s%s for everything else.%s\n' \
    "$DIM" "$BONE" "$RESET" "$DIM" "$BONE" "$RESET" "$DIM" "$RESET"
  if [[ ${XDG_CURRENT_DESKTOP:-} == *GNOME* ]] && ! gnome-extensions list --enabled 2>/dev/null | grep -qi appindicator; then
    printf '  %sGNOME hides tray icons until you turn on the AppIndicator extension, then log out and back in.%s\n' "$DIM" "$RESET"
  fi
  printf '\n'
}

# ---

printf '\n  %s   %sSwitchr%s\n' "$(track 0 7 "$BONE")" "$BOLD" "$RESET"
printf '  %s   %sYour AI accounts, one click apart.%s\n\n' "$(track 5 "$CELLS" "$AMBER")" "$DIM" "$RESET"

if [[ $OS == Linux ]]; then
  linux_architecture
  done_line "Linux on $ARCH"
elif [[ $OS == Darwin ]]; then
  step "Checking this Mac" check_mac
else
  fail "Switchr runs on macOS, Linux and Windows. On Windows, use install.ps1 from the same repository."
fi

if [[ -n ${SWITCHR_INSTALL_FROM:-} ]]; then
  SOURCE=local
  version=""
  for archive in "$SWITCHR_INSTALL_FROM"/switchr-*-linux-*.tar.gz; do
    [[ -e $archive ]] || continue
    version=$(basename "$archive" | sed -n 's/^switchr-\(.*\)-linux-.*\.tar\.gz$/\1/p')
    break
  done
  TAG="v${SWITCHR_VERSION:-$version}"
  [[ $TAG != v ]] || fail "Set SWITCHR_VERSION to the version of the files in $SWITCHR_INSTALL_FROM."
elif command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
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

if [[ $OS == Linux ]]; then
  linux_main
  exit 0
fi

step "Downloading" download
step "Verifying checksum" verify
step "Installing" install_app

APP_PATH=$(cat "$TMP/installed")
link_command "$APP_PATH"
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
printf '  %sInstalled at %s, with the %sswitchr%s%s command at %s%s\n' "$DIM" "$APP_PATH" "$BONE" "$RESET" "$DIM" "$(cat "$TMP/command")" "$RESET"
case ":$PATH:" in
  *":$(dirname "$(cat "$TMP/command")"):"*) ;;
  *) printf '  %sAdd %s to your PATH to run switchr from a terminal.%s\n' "$DIM" "$(dirname "$(cat "$TMP/command")")" "$RESET" ;;
esac
printf '\n'
