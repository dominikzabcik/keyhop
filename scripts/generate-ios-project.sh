#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

version="$(tr -d '[:space:]' < VERSION)"
if [[ -z "$version" ]]; then
  echo "VERSION is empty." >&2
  exit 1
fi

app_icon="ios/.generated/Assets.xcassets/AppIcon.appiconset"
rm -rf ios/.generated
mkdir -p "$app_icon"
cp docs/icon.png "$app_icon/AppIcon.png"
cat > "$app_icon/Contents.json" <<'JSON'
{
  "images": [
    {
      "filename": "AppIcon.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
JSON

KEYHOP_VERSION="$version" xcodegen generate --spec ios/project.yml
