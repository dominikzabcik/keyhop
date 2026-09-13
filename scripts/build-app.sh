#!/usr/bin/env bash
# Builds a universal build/Keyhop.app (Apple silicon + Intel).
#   --install   copy it to /Applications (or ~/Applications if that isn't writable) and open it
#   --zip       write build/Keyhop.zip
#   --dmg       write build/Keyhop.dmg (uses dmgbuild; installs it into .build/dmg-venv if missing)
#   --release   --zip, --dmg and build/SHA256SUMS
# KEYHOP_VERSION overrides the version in VERSION. A leading "v" is dropped.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${KEYHOP_VERSION:-$(cat VERSION)}"
VERSION="${VERSION#v}"
APP="build/Keyhop.app"

install=false zip=false dmg=false sums=false
for arg in "$@"; do
  case "$arg" in
    --install) install=true ;;
    --zip) zip=true ;;
    --dmg) dmg=true ;;
    --release) zip=true dmg=true sums=true ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

swift build -c release --arch arm64 --arch x86_64
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/Keyhop "$APP/Contents/MacOS/Keyhop"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Keyhop</string>
  <key>CFBundleIdentifier</key><string>app.keyhop.app</string>
  <key>CFBundleName</key><string>Keyhop</string>
  <key>CFBundleDisplayName</key><string>Keyhop</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- Lives in the menu bar; takes a Dock icon only while its window is open. -->
  <key>LSUIElement</key><true/>
  <!-- keyhop://open?section=usage, sent by the keyhop command to open the app's window. -->
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>app.keyhop.app</string>
      <key>CFBundleURLSchemes</key><array><string>keyhop</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP ($VERSION)"

if $zip; then
  rm -f build/Keyhop.zip
  ditto -c -k --keepParent "$APP" build/Keyhop.zip
  echo "Wrote build/Keyhop.zip"
fi

if $dmg; then
  DMGBUILD=$(command -v dmgbuild || true)
  if [[ -z $DMGBUILD ]]; then
    if [[ ! -x .build/dmg-venv/bin/dmgbuild ]]; then
      python3 -m venv .build/dmg-venv
      .build/dmg-venv/bin/pip install --quiet dmgbuild
    fi
    DMGBUILD=.build/dmg-venv/bin/dmgbuild
  fi
  rm -f build/Keyhop.dmg
  "$DMGBUILD" -s scripts/dmg-settings.py -D app="$APP" Keyhop build/Keyhop.dmg
  echo "Wrote build/Keyhop.dmg"
fi

if $sums; then
  (cd build && shasum -a 256 Keyhop.zip Keyhop.dmg > SHA256SUMS)
  echo "Wrote build/SHA256SUMS"
fi

if $install; then
  # Same place the installer uses, so there's only ever one copy.
  destination=/Applications
  if [[ ! -w $destination ]]; then
    destination="$HOME/Applications"
    mkdir -p "$destination"
  fi
  pkill -x Keyhop 2>/dev/null || true
  rm -rf "$destination/Keyhop.app"
  cp -R "$APP" "$destination/Keyhop.app"
  open "$destination/Keyhop.app"
  echo "Installed to $destination/Keyhop.app"
fi
