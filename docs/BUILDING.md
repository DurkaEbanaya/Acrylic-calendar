# Building and Releasing

## Prerequisites

- macOS 13.0 or later.
- Full Xcode installation.
- Xcode selected as active developer directory:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

- Xcode license accepted:

```bash
sudo xcodebuild -license accept
```

## Debug Build

```bash
swift build
```

## Run From Source

```bash
swift run FluentCalendar
```

Running from source is useful for development, but login item registration only works reliably from a packaged `.app` bundle.

## App Bundle Build

```bash
bash scripts/build_app.sh
```

Output:

```text
.build/release/Acrylic calendar.app
```

## Full Release Artifact Build

```bash
bash scripts/build_release_artifacts.sh
```

Outputs:

```text
dist/Acrylic-calendar-macOS-universal.zip
dist/Acrylic-calendar-binaries.zip
dist/SHA256SUMS.txt
dist/bin/FluentCalendar-x86_64
dist/bin/FluentCalendar-arm64
dist/bin/FluentCalendar-universal
```

## Verify Architectures

```bash
file "dist/bin/FluentCalendar-x86_64" \
     "dist/bin/FluentCalendar-arm64" \
     "dist/bin/FluentCalendar-universal" \
     ".build/release/Acrylic calendar.app/Contents/MacOS/FluentCalendar"
```

Expected:

```text
FluentCalendar-x86_64: Mach-O 64-bit executable x86_64
FluentCalendar-arm64: Mach-O 64-bit executable arm64
FluentCalendar-universal: Mach-O universal binary with 2 architectures
Acrylic calendar.app executable: Mach-O universal binary with 2 architectures
```

## Signing

The build scripts use ad-hoc signing:

```bash
codesign --force --deep --sign - ".build/release/Acrylic calendar.app"
```

For public distribution outside GitHub source builds, replace this with Developer ID signing and notarization.

## GitHub Release Upload

After a successful artifact build, upload:

```text
dist/Acrylic-calendar-macOS-universal.zip
dist/Acrylic-calendar-binaries.zip
dist/SHA256SUMS.txt
```

Example release tag:

```text
v1.1.0
```

Example release title:

```text
Acrylic Calendar 1.1
```

## Clean Build

```bash
rm -rf .build dist
swift build
bash scripts/build_release_artifacts.sh
```
