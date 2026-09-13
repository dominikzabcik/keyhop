#!/usr/bin/env bash
# Builds the Linux release for this machine's architecture into build/linux/:
#   keyhop-<v>-linux-<arch>.tar.gz    any distribution; install-local.sh puts it in ~/.local
#   keyhop-<v>-1.<arch>.rpm           Fedora, RHEL and derivatives
#   keyhop_<v>_<debarch>.deb          Debian, Ubuntu and derivatives
#   keyhop-<v>-1-<arch>.pkg.tar.zst   Arch Linux and derivatives
# The binary links everything statically (musl), so one build runs on every distribution.
# Needs Swift with the matching static Linux SDK, and nfpm for the packages (--no-packages skips them).
# KEYHOP_VERSION overrides the version in VERSION. A leading "v" is dropped.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${KEYHOP_VERSION:-$(cat VERSION)}"
VERSION="${VERSION#v}"
packages=true
[[ "${1:-}" == "--no-packages" ]] && packages=false

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) NFPM_ARCH=amd64 DEB_ARCH=amd64 ;;
  aarch64 | arm64) ARCH=aarch64 NFPM_ARCH=arm64 DEB_ARCH=arm64 ;;
  *) echo "Keyhop builds for x86_64 and aarch64, not $ARCH." >&2; exit 1 ;;
esac

SCRATCH="${KEYHOP_SCRATCH:-.build}"
swift build -c release --scratch-path "$SCRATCH/musl" --swift-sdk "$ARCH-swift-linux-musl" --product Keyhop -Xlinker -s
BIN="$SCRATCH/musl/$ARCH-swift-linux-musl/release/Keyhop"

OUT=build/linux
STAGE="$OUT/keyhop-$VERSION"
rm -rf "$OUT"
mkdir -p "$STAGE/icons"
install -m 0755 "$BIN" "$STAGE/keyhop"
install -m 0755 packaging/linux/keyhop-tray "$STAGE/keyhop-tray"
install -m 0755 packaging/linux/install-local.sh "$STAGE/install-local.sh"
cp packaging/linux/app.keyhop.Keyhop.desktop packaging/linux/app.keyhop.Keyhop.metainfo.xml LICENSE README.md "$STAGE/"
cp packaging/icons/keyhop-*.png "$STAGE/icons/"

"$STAGE/keyhop" version
tar -C "$OUT" -czf "$OUT/keyhop-$VERSION-linux-$ARCH.tar.gz" "keyhop-$VERSION"

if $packages; then
  # nfpm expands variables in the version and arch, not in file paths, so the binary gets a fixed one.
  mkdir -p "$OUT/package-root"
  cp "$STAGE/keyhop" "$OUT/package-root/keyhop"
  export KEYHOP_VERSION="$VERSION" NFPM_ARCH
  nfpm package -f packaging/linux/nfpm.yaml -p rpm -t "$OUT/keyhop-$VERSION-1.$ARCH.rpm"
  nfpm package -f packaging/linux/nfpm.yaml -p deb -t "$OUT/keyhop_${VERSION}_$DEB_ARCH.deb"
  nfpm package -f packaging/linux/nfpm.yaml -p archlinux -t "$OUT/keyhop-$VERSION-1-$ARCH.pkg.tar.zst"
fi

rm -rf "$STAGE" "$OUT/package-root"
ls -l "$OUT"
