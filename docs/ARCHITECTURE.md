# Architecture

This document describes the internal structure of Acrylic Calendar.

## Application Model

Acrylic Calendar is a Swift Package Manager executable target. It creates a native AppKit application without storyboards, nibs, SwiftUI, or external UI dependencies.

The app is intentionally configured as a menu bar utility:

- `Resources/Info.plist` enables `LSUIElement`.
- `main.swift` sets the activation policy to `.accessory`.
- `AppDelegate` owns the `NSStatusItem`, menus, window controllers, and login item registration.

This keeps the app out of the Dock while allowing windows and panels to be shown from the menu bar item.

## Rendering Strategy

Most UI is custom-drawn in `NSView.draw(_:)` to match Windows 10-era Fluent visuals more closely than standard AppKit controls would allow.

The drawing code favors:

- Rectangular geometry.
- Acrylic-like translucency.
- Subtle noise and gradients.
- Reveal hover highlights.
- Dense grid layouts.
- Windows 10-like command bars and sidebars.

## Main Files

### `main.swift`

Creates `NSApplication.shared`, attaches `AppDelegate`, sets `.accessory`, and starts the run loop.

### `AppDelegate.swift`

Coordinates application lifecycle:

- Applies appearance settings.
- Registers login item automatically when allowed.
- Creates and updates the menu bar status item.
- Shows the flyout panel, full calendar window, Settings, and About window.
- Rebuilds localized app menus when the app language changes.

### `AppSettings.swift`

Centralized settings backed by `UserDefaults`:

- Theme mode.
- Menu bar date display.
- Hour cycle and seconds.
- App language and resolved locale.
- Accent color.
- Login-item manual-disable flag.

Settings changes post `.fluentCalendarSettingsChanged`.

### `LocalizedStrings.swift`

In-code localization table. The selected `AppLanguage` controls both text lookup and `DateFormatter` locale selection through `AppSettings.localizedLocale`.

### `CalendarPanelController.swift`

Owns the menu bar flyout `NSPanel`. The panel is key-capable so text fields in quick event creation can receive keyboard focus.

### `CalendarPanelView.swift`

Draws the menu bar flyout:

- Header date.
- Month grid.
- Today/previous/next controls.
- Agenda.
- Event indicators.
- Quick event editor.

It fetches visible events through `EventKitCalendarService`, groups them by day, and adds newly-created events optimistically before the next EventKit refresh finishes.

### `QuickEventEditorView.swift`

Inline quick event editor used by the flyout. It supports title, location, start/end date, start/end time, reminder, Save, More details, and close.

### `FullCalendarWindowController.swift`

Creates the resizable full calendar window and draws its content:

- Acrylic sidebar.
- Command bar.
- Day view.
- Week view.
- Month view.
- Year view.
- Event hit regions and day hit regions.

The Year view adapts between 6-column and 4-column layouts and highlights days that contain events. Clicking a year-view month switches to Month. Clicking a year-view day switches to Day.

### `EventKitCalendarService.swift`

Handles EventKit integration:

- Requests access.
- Fetches events in a date interval.
- Creates events with optional `EKAlarm` reminders.
- Converts `EKEvent` objects into lightweight `CalendarEventSummary` values.
- Opens Calendar.app as a safe fallback for event clicks.

### `SettingsWindowController.swift`

Builds the Settings window with AppKit controls:

- Theme.
- Language.
- Menu bar date display.
- Weekday and seconds toggles.
- Accent color.
- About button.
- Clock settings helper.
- Login item checkbox.

The Settings view rebuilds its labels when the selected language changes to avoid stale or clipped localized strings.

### `AboutWindowController.swift`

Custom acrylic About window with generated Fluent-style calendar icon and release URL.

### `AcrylicBackgroundView.swift`

Reusable acrylic-like view used by windows/panels that need translucent material styling.

## Event Refresh Flow

1. A visible date interval is computed for the current view mode.
2. `EventKitCalendarService.fetchEvents(in:)` loads events.
3. Events are grouped by day.
4. Drawing code renders day indicators, event blocks, or event lists.
5. Creating an event returns a `CalendarEventSummary`.
6. The UI inserts the event optimistically.
7. `.fluentCalendarEventsChanged` triggers a delayed EventKit reload.

This avoids requiring an app restart before a newly-created event appears.

## Login Item Flow

On app launch:

1. If running as a packaged `.app`, the app checks `SMAppService.mainApp.status`.
2. If the user has not manually disabled login item registration, the app calls `SMAppService.mainApp.register()`.
3. If registration fails, the app silently continues and leaves the Settings checkbox available.

From Settings:

- Turning the checkbox on registers the login item and clears the manual-disable flag.
- Turning it off unregisters the login item and stores the manual-disable flag.

## Release Artifacts

`scripts/build_release_artifacts.sh` creates:

- A universal `.app` bundle.
- Thin x86_64 binary.
- Thin arm64 binary.
- Universal binary.
- Zip archives.
- SHA-256 checksums.

The app bundle is ad-hoc signed with `codesign --sign -` for local distribution.
