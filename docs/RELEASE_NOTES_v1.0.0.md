# Acrylic Calendar 1.0

Initial public release.

## Features

- Native Swift/AppKit menu bar calendar.
- Windows 10 Fluent/Acrylic-inspired visual style.
- Menu bar flyout with month grid, agenda, quick event creation, and reveal effects.
- Full calendar window with Day, Week, Month, and Year views.
- Adaptive Year view with event-day highlighting and direct navigation.
- Seven-day Week view with per-day event lists and add-event entry points.
- EventKit calendar reading and event creation.
- Optional reminders using `EKAlarm`.
- Localized UI and date formatting for English, Russian, Ukrainian, German, French, Japanese, and Tatar.
- Menu bar date/time controls.
- Acrylic About window with generated app icon.
- Automatic login item registration with Settings control.
- Runs without a Dock icon.

## Release Files

- `Acrylic-calendar-macOS-universal.zip`: universal macOS app bundle.
- `Acrylic-calendar-binaries.zip`: standalone binaries.
- `SHA256SUMS.txt`: checksums.

## Notes

- The app is ad-hoc signed by the build script.
- Calendar permissions are requested by macOS when EventKit access is needed.
- Event clicks open Calendar.app safely; macOS does not provide a stable public URL for opening a specific event editor.
