#!/usr/bin/env bash
# Renders the app icon, disk image background and README banner.
# Outputs are committed, so this only needs to run after changing scripts/render-art.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

swiftc -O scripts/render-art.swift -o "$work/render-art"
"$work/render-art" "$work"

mkdir -p Assets docs
iconutil -c icns "$work/AppIcon.iconset" -o Assets/AppIcon.icns
tiffutil -cathidpicheck "$work/dmg-background.png" "$work/dmg-background@2x.png" -out Assets/dmg-background.tiff
cp "$work/banner.png" docs/banner.png
cp "$work/icon-1024.png" docs/icon.png
echo "Updated Assets/AppIcon.icns, Assets/dmg-background.tiff, docs/banner.png, docs/icon.png"
