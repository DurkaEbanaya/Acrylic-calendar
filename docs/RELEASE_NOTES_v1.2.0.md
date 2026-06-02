# Acrylic Calendar 1.2

Version 1.2 fixes startup/menu bar behavior and adds a bundled app icon.

## Fixed

- Fixed the menu bar date/time left-click path after login or relaunch.
- Left-clicking the menu bar item now opens the calendar flyout through the same path as `Open calendar panel`.
- Added a first-open retry to avoid the initial AppKit status button tracking issue.
- Stopped opening the full calendar window automatically at startup.
- Added a single-instance guard to prevent duplicate menu bar clocks when duplicate login items or running copies exist.
- Stopped automatically registering the app as a login item on every launch; launch-at-login is now controlled from Settings only.

## Added

- Added a bundled `AppIcon.icns` and connected it through `CFBundleIconFile`.
- Updated build scripts to include the app icon in packaged `.app` bundles.
- Added an icon generation script for the bundled app icon.

## Release Files

- `Acrylic-calendar-macOS-universal.zip`: universal macOS app bundle.
- `Acrylic-calendar-binaries.zip`: standalone binaries.
- `SHA256SUMS.txt`: checksums.
