# Changelog

All notable changes to Eventually are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

> **Surface naming** (for clarity going forward):
> - **Popover** — the menu-bar dropdown opened with ⌘⇧T (compact, transient).
> - **Command Window** — the floating window opened with ⌘⇧O (full input + tabs + task list). This is becoming the primary surface.

### Added (latest)
- **Menu bar badge** with today's task count (toggle in Settings, now functional).
- **Launch at login** wired via `SMAppService` (was a stub).
- **Group tasks by list** in the smart views (Today/Upcoming/All), toggle in the sort menu.
- **Focus return** (Spotlight-style): closing the Command Window with Esc / ⌘⇧O hands focus back to the app you were using.

### Fixed (latest)
- **Timezone bug**: Google stores due dates at UTC midnight; Today/Upcoming buckets, overdue coloring, and the badge now compute the correct local calendar day (was off by the UTC offset). Writes are UTC-anchored from the picked local day.
- **Sort now works in the smart views** (was always due-sorted); the sort menu is flattened to one click (no "Sort by" submenu).

### Added (earlier)
- **Explicit `!` date markers** in quick-add: `!4dias`, `!3d`, `!2semanas`, `!1mes`, `!manana` (Spanish & English; time units like `!5min` resolve to today since the API is date-only). 18 parser unit tests.

### Changed (latest)
- **Compact date picker** — the popover is now just the accent-tinted calendar; picking a day closes it (no extra chrome).
- **Retired the Popover as a task surface** — the menu bar icon and the single global shortcut (⌘⇧O) now open the Command Window. The popover is kept only for sign-in. Settings shows one shortcut ("Open Command Window").
- **Nicer date picker**: accent-tinted graphical calendar in a framed popover with Clear / Done actions.

### Added
- **Search** across all lists from the Command Window (magnifying-glass toggle; Esc closes search first).
- **Appearance** setting: System / Light / Dark, applied app-wide.
- **Command Window default view** setting: opens to Today / Upcoming / All / Last used.
- **Command Window remembers its position and size** across launches and restarts; restored frames are clamped to stay on-screen. The position is anchored near the top (Spotlight-style).
- **Draft retention** (Raycast-style): the in-progress task survives click-outside; Esc clears it (then closes when empty).

### Internal (cleanup pass)
- `Selection` enum now owns `isSmart`, `icon`, and `storageKey`/`init(storageKey:)` — collapsed duplicated view↔string mapping and smart-view predicates across views.
- Added `Appearance` enum and a `DefaultsKey` constants namespace to replace scattered magic strings.
- Consolidated window-frame clamping into one `clampedToScreen` helper.

### Added
- **Command Window is resizable** (drag any edge); its size persists across launches. Position still follows the Settings preference (Left/Center/Right).
- **Feature parity** between the Popover and the Command Window: the Command Window now also has Today/Upcoming smart-view tabs, a sort menu, a refresh button, the account/Settings/Sign Out/Quit menu, and an error banner.
- **Rounded (capsule) buttons** across the floating UI via a reusable `CapsuleButton` style.
- Dedicated **Settings window** managed by the app (`SettingsWindowController`) so it reliably opens from the ⋯ menu on the menu-bar (LSUIElement) app.

### Changed (latest pass)
- **Accent color** switched from amber to the **system accent color** (blue by default, matching Google Tasks and native macOS controls) for visual consistency across tabs, buttons, and icons.
- Due-date chips keep a distinct warm-orange accent so dates stay visually separate from the primary accent.
- Unified hardcoded `.blue` usages to `Theme.accent`.

### Fixed (latest pass)
- **Settings window not opening** — replaced the unreliable `showSettingsWindow:` selector with a managed `NSWindow`.

### Build (latest pass)
- Adopted Xcode-recommended build settings in `project.yml` (so they survive `xcodegen` regeneration): `DEAD_CODE_STRIPPING`, `ENABLE_USER_SCRIPT_SANDBOXING`.
- Widget now derives `CFBundleIdentifier` from the `PRODUCT_BUNDLE_IDENTIFIER` build setting instead of a hardcoded value.

### Added
- **Smart views** in the menu bar popover: Today, Upcoming, All Tasks, plus each individual list.
- **List badges** with stable per-list colors when viewing aggregated tasks.
- **Sort options** (My order / Due date / Title) via the header sort menu.
- **Per-task options** through a hover action row and right-click context menu:
  - Edit due date (graphical date picker)
  - Clear due date
  - Add subtask (inline indented input)
  - Move to list
  - Delete
- **Subtasks**: parent/child nesting parsed from the API `parent` field, rendered with an indent guide.
- **Expandable task detail**: tap a task to reveal and edit its title and description inline.
- **Quick-add panel** (⌘⇧O) redesigned into a full floating window:
  - Header input with natural-language parsing (`#list` + Spanish/English dates)
  - `#list` autocomplete dropdown (substring match, Enter accepts top result)
  - Live date/list chips reflecting the parse
  - List filter tabs (All + each list) with the task list below
  - Stays open after adding so you can keep capturing
  - Configurable position (Left / Center / Right) in Settings
- **QuickAddParser** with natural-language date support (`hoy`/`today`, `mañana`/`tomorrow`, weekday names, accent-insensitive) — covered by 11 unit tests.
- **Settings**: connected account email + Sign Out, customizable shortcuts, quick-add panel position.
- **Design tokens** (`Theme`): warm amber accent, 8pt spacing grid, `Color(hex:)`.
- Backspace on an empty new-subtask input cancels it.

### Changed
- **OAuth flow** rewritten to use a localhost loopback server (matches the "installed app" client type) instead of a custom URL scheme.
- **Token storage** moved from Keychain to a user-only-readable file under Application Support, so sessions persist across unsigned rebuilds. (Revert to Keychain once the app is signed with a stable identity.)
- HTTP layer now validates response status and surfaces Google API errors (e.g. "Tasks API not enabled") instead of silently showing "No tasks".
- Date parsing handles RFC-3339 fractional seconds returned by the API.
- Popover enlarged (400 wide, taller scroll) for a TickTick-like density.
- Quick-add panel uses a custom `KeyablePanel` so a borderless window can accept keyboard input.
- Renamed project, targets, bundle id, and all sources from `TaskBar` to `Eventually`.
- Task model renamed `Task` → `GTask` to avoid colliding with Swift Concurrency's `Task`.

### Fixed
- Quick-add panel rendered blank/white after the redesign (caused by a `.titled` window style); reverted to borderless.
- Quick-add panel not accepting keyboard input (borderless panel couldn't become key).
- OAuth success page showed mojibake (`âœ"`) due to a missing UTF-8 charset header.
- Sign-in spinner hung forever when the browser tab was closed without finishing; it now resets on return to the app.

## [0.1.0] — Initial commit

### Added
- Native macOS menu bar app (Swift / SwiftUI / AppKit) for Google Tasks.
- OAuth 2.0 with PKCE, Google Tasks CRUD, global keyboard shortcuts.
- WidgetKit widget (small + medium).
