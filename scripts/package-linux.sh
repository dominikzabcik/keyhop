#!/usr/bin/env bash
# Builds the Linux release for this machine's architecture into build/linux/:
#   switchr-<v>-linux-<arch>.tar.gz    any distribution; install-local.sh puts it in ~/.local
#   switchr-<v>-1.<arch>.rpm           Fedora, RHEL and derivatives
#   switchr_<v>_<debarch>.deb          Debian, Ubuntu and derivatives
#   switchr-<v>-1-<arch>.pkg.tar.zst   Arch Linux and derivatives
# The binary links everything statically (musl), so one build runs on every distribution.
# Needs Swift with the matching static Linux SDK, and nfpm for the packages (--no-packages skips them).
# SWITCHR_VERSION overrides the version in VERSION. A leading "v" is dropped.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${SWITCHR_VERSION:-$(cat VERSION)}"
VERSION="${VERSION#v}"
packages=true
[[ "${1:-}" == "--no-packages" ]] && packages=false

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) NFPM_ARCH=amd64 DEB_ARCH=amd64 ;;
  aarch64 | arm64) ARCH=aarch64 NFPM_ARCH=arm64 DEB_ARCH=arm64 ;;
  *) echo "Switchr builds for x86_64 and aarch64, not $ARCH." >&2; exit 1 ;;
esac

SCRATCH="${SWITCHR_SCRATCH:-.build}"
swift build -c release --scratch-path "$SCRATCH/musl" --swift-sdk "$ARCH-swift-linux-musl" --product Switchr -Xlinker -s
BIN="$SCRATCH/musl/$ARCH-swift-linux-musl/release/Switchr"

OUT=build/linux
STAGE="$OUT/switchr-$VERSION"
rm -rf "$OUT"
mkdir -p "$STAGE/icons"
install -m 0755 "$BIN" "$STAGE/switchr"
install -m 0755 packaging/linux/switchr-tray "$STAGE/switchr-tray"
install -m 0755 packaging/linux/install-local.sh "$STAGE/install-local.sh"
cp packaging/linux/dev.switchr.Switchr.desktop packaging/linux/dev.switchr.Switchr.metainfo.xml LICENSE README.md "$STAGE/"
cp packaging/icons/switchr-*.png "$STAGE/icons/"

"$STAGE/switchr" version
tar -C "$OUT" -czf "$OUT/switchr-$VERSION-linux-$ARCH.tar.gz" "switchr-$VERSION"

if $packages; then
  # nfpm expands variables in the version and arch, not in file paths, so the binary gets a fixed one.
  mkdir -p "$OUT/package-root"
  cp "$STAGE/switchr" "$OUT/package-root/switchr"
  export SWITCHR_VERSION="$VERSION" NFPM_ARCH
  nfpm package -f packaging/linux/nfpm.yaml -p rpm -t "$OUT/switchr-$VERSION-1.$ARCH.rpm"
  nfpm package -f packaging/linux/nfpm.yaml -p deb -t "$OUT/switchr_${VERSION}_$DEB_ARCH.deb"
  nfpm package -f packaging/linux/nfpm.yaml -p archlinux -t "$OUT/switchr-$VERSION-1-$ARCH.pkg.tar.zst"
fi

rm -rf "$STAGE" "$OUT/package-root"
ls -l "$OUT"
