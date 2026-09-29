#!/bin/zsh
# Double-click in Finder to build a Release copy of Pluck into Build/Pluck.app and open it.

cd "${0:A:h}" || exit 1

APP="Build/Pluck.app"
DERIVED="Build/DerivedData"
LOG="Build/build.log"

finish() {
    echo
    read -r "?Press Return to close…"
    exit "$1"
}

mkdir -p Build
echo "Building Pluck (Release)…"

if ! xcodebuild \
    -project Pluck.xcodeproj \
    -scheme Pluck \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    build > "$LOG" 2>&1; then
    echo
    echo "❌ Build failed. Errors:"
    grep -E "error:" "$LOG" | sort -u
    echo
    echo "Full log: $PWD/$LOG"
    finish 1
fi

# Quit a running copy so the new build (and its icon) replaces it cleanly.
if pgrep -xq Pluck; then
    osascript -e 'quit app "Pluck"'
    while pgrep -xq Pluck; do sleep 0.2; done
fi

rm -rf "$APP"
ditto "$DERIVED/Build/Products/Release/Pluck.app" "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
echo "✅ Built Pluck $VERSION ($BUILD) → $PWD/$APP"

open "$APP"
finish 0
