#!/bin/zsh
# Builds "build/Phone Switcher.app" from the SwiftPM target. Personal use: ad-hoc signed only.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product PhoneSwitcherApp
app="build/Phone Switcher.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/PhoneSwitcherApp" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $app"
