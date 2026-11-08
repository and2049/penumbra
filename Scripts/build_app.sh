#!/bin/sh
# Builds Build/Penumbra.app and signs it ad-hoc. Needs only the Command Line Tools.
set -eu
cd "$(dirname "$0")/.."

swift build -c release
bin="$(swift build -c release --show-bin-path)/Penumbra"

app="Build/Penumbra.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/Penumbra"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $app"
