#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Acrylic calendar.app"
BUNDLE_DIR="$ROOT_DIR/.build/release/$APP_NAME"

cd "$ROOT_DIR"

if swift build -c release --arch x86_64 --arch arm64; then
  BIN_DIR="$(swift build -c release --arch x86_64 --arch arm64 --show-bin-path)"
else
  printf 'Universal build failed; falling back to the current architecture.\n'
  swift build -c release
  BIN_DIR="$(swift build -c release --show-bin-path)"
fi

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp "$BIN_DIR/FluentCalendar" "$BUNDLE_DIR/Contents/MacOS/FluentCalendar"
cp "$ROOT_DIR/Resources/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$BUNDLE_DIR"

printf 'Built %s\n' "$BUNDLE_DIR"
