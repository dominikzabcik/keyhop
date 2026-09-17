#!/usr/bin/env bash
# App Store screenshots for the iOS companion, taken from the app's own sample data.
#
#   bash scripts/ios-screenshots.sh [output folder]
#
# Uses a 6.9-inch iPhone simulator (1320 x 2868), the size App Store Connect asks for first; it
# scales those down for smaller phones. The status bar is set to Apple's usual 9:41 look.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-$root/ios/build/screenshots}"
mkdir -p "$out"

device="$(xcrun simctl list devices available | grep -m1 'iPhone 17 Pro Max' | grep -oE '[0-9A-F-]{36}' || true)"
if [[ -z "$device" ]]; then
  echo "No iPhone 17 Pro Max simulator is installed. Add one in Xcode > Settings > Components." >&2
  exit 1
fi

bash "$root/scripts/generate-ios-project.sh" >/dev/null
xcodebuild -project "$root/ios/Keyhop.xcodeproj" -scheme Keyhop -configuration Release \
  -destination "id=$device" -derivedDataPath "$root/ios/build" build >/dev/null
app="$root/ios/build/Build/Products/Release-iphonesimulator/Keyhop.app"

xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" >/dev/null
xcrun simctl status_bar "$device" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi
xcrun simctl install "$device" "$app"

shot() {
  local name="$1"; shift
  xcrun simctl terminate "$device" app.keyhop.ios >/dev/null 2>&1 || true
  xcrun simctl launch "$device" app.keyhop.ios "$@" >/dev/null
  sleep 4
  xcrun simctl io "$device" screenshot "$out/$name.png" >/dev/null 2>&1
  echo "$out/$name.png"
}

shot 1-season --sample
shot 2-leaderboard --sample --scroll-end
shot 3-link --sample-waiting

xcrun simctl status_bar "$device" clear
