#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Acrylic calendar.app"
APP_DIR="$ROOT_DIR/.build/release/$APP_NAME"
DIST_DIR="$ROOT_DIR/dist"

cd "$ROOT_DIR"

swift build -c release --arch x86_64 --arch arm64
BIN_DIR="$(swift build -c release --arch x86_64 --arch arm64 --show-bin-path)"
UNIVERSAL_BIN="$BIN_DIR/FluentCalendar"

rm -rf "$APP_DIR" "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$DIST_DIR/bin"

cp "$UNIVERSAL_BIN" "$APP_DIR/Contents/MacOS/FluentCalendar"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"

lipo "$UNIVERSAL_BIN" -thin x86_64 -output "$DIST_DIR/bin/FluentCalendar-x86_64"
lipo "$UNIVERSAL_BIN" -thin arm64 -output "$DIST_DIR/bin/FluentCalendar-arm64"
cp "$UNIVERSAL_BIN" "$DIST_DIR/bin/FluentCalendar-universal"
chmod +x "$DIST_DIR/bin/FluentCalendar-x86_64" "$DIST_DIR/bin/FluentCalendar-arm64" "$DIST_DIR/bin/FluentCalendar-universal"

ditto -c -k --keepParent "$APP_DIR" "$DIST_DIR/Acrylic-calendar-macOS-universal.zip"
ditto -c -k "$DIST_DIR/bin" "$DIST_DIR/Acrylic-calendar-binaries.zip"

shasum -a 256 "$DIST_DIR/Acrylic-calendar-macOS-universal.zip" "$DIST_DIR/Acrylic-calendar-binaries.zip" "$DIST_DIR/bin/FluentCalendar-x86_64" "$DIST_DIR/bin/FluentCalendar-arm64" "$DIST_DIR/bin/FluentCalendar-universal" > "$DIST_DIR/SHA256SUMS.txt"

printf 'Built release artifacts in %s\n' "$DIST_DIR"
