# Acrylic Calendar Interface Reference

This document captures the reusable interface decisions and implementation lessons from Acrylic Calendar. Use it as a reference for future macOS/AppKit projects that need a Windows 10 Fluent/Acrylic visual language without copying Microsoft assets.

## Visual Direction

The project targets Windows 10-era Fluent Design, not Windows 11.

Use:

- Sharp rectangular geometry.
- Dense information layout.
- Segoe UI-like typography where available, with system font fallback.
- Windows 10 accent blue, primarily `#0078D7`.
- Acrylic-like translucent surfaces with tint, gradient, and subtle noise.
- Reveal hover effects: local glow and edge illumination near the cursor.
- UWP-like command bars, sidebars, and settings pages.

Avoid:

- Large rounded cards.
- Mica-style Windows 11 surfaces.
- macOS preference-pane/cards visual language when the product is supposed to feel Windows 10-like.
- Decorative blur everywhere. Acrylic works best on sidebars, flyouts, transient surfaces, and about panels.
- Microsoft trademarks, binaries, icons, or copied proprietary assets.

## App Structure Lessons

### Menu Bar Utility

For a macOS utility that should not appear in the Dock:

- Set `LSUIElement` to `true` in `Info.plist`.
- Set `NSApplication` activation policy to `.accessory`.
- Trigger all primary UI from `NSStatusItem`.

This combination keeps the app out of the Dock while still allowing custom panels and windows to appear from the menu bar.

### Menu Bar Flyout

Use a custom `NSPanel` rather than `NSPopover` when the flyout needs editable text fields and precise acrylic drawing.

Important panel behavior:

- Make the panel key-capable.
- Avoid `.nonactivatingPanel` if text input must work reliably.
- Activate the app before showing the panel.

### Full Calendar Window

Custom drawing in `NSView.draw(_:)` gives much tighter control than standard AppKit table/collection controls for this visual direction.

Useful patterns:

- Keep hit regions separate from drawing data.
- Clear hit regions at the start of every draw.
- Store event hit regions and date hit regions explicitly.
- Use optimistic insertion after creating an EventKit event, then reload from EventKit after a short delay.

## Acrylic Surface Recipe

Acrylic was approximated with:

- A translucent base fill.
- A directional gradient.
- A tint influenced by accent color or sidebar color.
- A procedural noise pattern.
- A subtle border.

This does not require private APIs and avoids shipping image textures.

Good targets:

- Menu bar flyout background.
- Full-calendar sidebar.
- About window.
- Overlay-style panels.

Use solid dark backgrounds for dense content areas such as the main month grid or Settings content page.

## Reveal Highlight Recipe

The successful reveal effect used two layers:

- A radial gradient centered on the mouse pointer.
- Short edge segments whose opacity falls off by distance from the pointer.

This avoids the bad look of a full permanent outline and better matches Windows 10 Reveal Highlight behavior.

Implementation guidance:

- Clip reveal drawing to the hovered rect.
- Use stronger blue glow in light mode.
- Use softer white/accent glow in dark mode.
- Do not draw reveal on every item constantly; only draw for hovered or focused targets.

## Calendar Grid Lessons

### Month Grid

The month grid should show only current-month days for this app style. Leading/trailing days from adjacent months should be empty cells.

Use regular UI fonts for date numbers. Monospaced digits looked too mechanical and less Windows 10-like.

### Week View

For this product, Week means seven day columns with event lists and add-event entry points, not a 24-hour timeline. The timeline made the view feel like seven narrow Day views and reduced discoverability.

### Year View

Year view needs adaptive layout:

- Wide window: 6 columns x 2 rows.
- Medium/narrow window: 4 columns x 3 rows.
- Avoid 3 columns x 4 rows unless the window is very tall, because month titles can collide with date rows.

Year view interactions:

- Click a month title to switch to Month view for that month.
- Click a day to switch to Day view for that date.
- Highlight event days with a brighter or heavier font rather than extra badges, to keep the year grid clean.

## Settings Window Redesign Lessons

The Settings window should preserve system window chrome unless there is time to implement a complete custom window frame. A partially custom frame looks broken on macOS.

Use:

- Standard macOS titlebar/frame.
- Black content background.
- Windows 10-style typography and spacing inside the content view.
- Rectangular popups/buttons.
- Custom Windows-like toggles instead of macOS checkbox visuals.
- Existing settings only. Do not add fake navigation sections if they do not correspond to real pages.

Avoid:

- macOS preference cards.
- Decorative Home/search/sidebar controls unless they are functional and requested.
- Hidden titlebar unless a full custom Windows frame is implemented.

### Adaptive Settings Layout

Frame-based AppKit views do not always re-run `layout()` the way Auto Layout views do. For this project, reliable resize behavior came from overriding `setFrameSize(_:)` and recalculating frames there.

Rules used:

- Wide window: two columns.
- Narrow window: one column.
- Control widths derive from current `bounds.width`, not a fixed width.
- Color swatches compress spacing based on available width.
- Labels and controls are recreated only when needed for localization changes; resize should primarily move/resize existing controls where possible.

## Localization Lessons

Localization must cover more than static labels:

- Month names.
- Weekday names.
- Date headers.
- Menu items.
- Empty states.
- Event editor labels.
- Settings choices.

Use the selected app language to drive `DateFormatter.locale`; do not rely only on `Locale.current`, or month/week names will ignore the app language selector.

## EventKit Lessons

Newly-created events may not appear immediately through a fresh fetch. Return a summary of the created event, insert it optimistically into the current visible event cache, post an events-changed notification, and schedule a delayed reload.

Do not use private or unstable Calendar.app URL schemes to open a specific event. If a URL fails, macOS shows a user-visible error. The safe fallback is opening Calendar.app.

## Release/Packaging Lessons

For distribution:

- Build universal with `swift build -c release --arch x86_64 --arch arm64`.
- Package a `.app` bundle manually from the SwiftPM executable.
- Ad-hoc sign local builds with `codesign --force --deep --sign -`.
- Create thin binaries with `lipo -thin` for verification and optional release artifacts.
- Include SHA-256 checksums in releases.

## Useful Defaults From This Project

- App name: `Acrylic calendar`.
- Bundle ID style: `dev.<author>.<app-name>`.
- Accent blue: `#0078D7`.
- Version label in About should be updated with every release.
- Release link in About should point directly to the GitHub releases page.
