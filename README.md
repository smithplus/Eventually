# Eventually

> Google Tasks in your macOS menu bar. Native, fast, no Electron.

*"Get things done. Eventually."*

---

## Features

- **Floating Command Window** — quick-capture Raycast-style with `⌘⇧O`
- **Smart views**: Today, Upcoming, All Tasks + custom lists
- **Natural language input**: `#list` and `!date` (`!tomorrow`, `!4days`, `!friday`, etc.)
- **Keyboard-first**: full keyboard navigation, multi-select, bulk actions
- **Markdown rendering** in notes (headings, bullets, inline styles)
- **Group by date / list** with collapsible headers
- **Recurring task detection** — detects patterns and shows ↻ Weekly/Monthly badge
- **Completed tasks section** — collapsible section with smooth animations
- **Uncomplete tasks** — click checkbox on completed tasks to undo
- **Auto-refresh** configurable (5/15/30 min)
- **Draft persistence** — draft survives closing the app
- Desktop widget small and medium (WidgetKit)
- Sign in with Google OAuth 2.0 — tokens stored locally in Keychain

## How login works

Eventually uses **your Google account** to access your tasks. You don't need to create any API key or developer account — just click "Sign in with Google", your browser opens, you authorize the app, and you're done. The token is saved in your Mac's Keychain.

## Requirements

- macOS 13 Ventura or later
- Xcode 15+
- Google account with Google Tasks enabled

## Installation (from source)

```bash
git clone https://github.com/smithplus/Eventually.git
cd Eventually
brew install xcodegen
cp Config.template.swift Sources/Eventually/Config.swift   # paste your OAuth credentials
xcodegen generate
open Eventually.xcodeproj
```

In Xcode: select your signing team → `Cmd+R`

## Shortcuts

| Shortcut | Action |
|---|---|
| `⌘⇧O` | Open / close Command Window |
| `Tab` (in input) | Go to list/date autocomplete (↑/↓ navigate, Enter accepts) |
| `Tab` (no autocomplete) | Focus task list for keyboard navigation |
| `↑/↓` (in list) | Move cursor |
| `⌘+Click` | Toggle individual task selection |
| `Return` | Complete selected tasks |
| `Delete` | Delete selected tasks |
| `⌘A` | Select all visible tasks |
| `Esc` / `Tab` | Return to input |

Customizable in **Settings**.

## Project structure

```
Sources/
├── Eventually/
│   ├── EventuallyApp.swift              Entry point
│   ├── AppDelegate.swift                Menu bar + auto-refresh + badge
│   ├── QuickAddWindowController.swift   Command Window lifecycle
│   ├── Config.swift                     OAuth credentials (git-ignored)
│   ├── Models/
│   │   └── TaskModels.swift             GTask, TaskList, dueDay (timezone fix)
│   ├── Services/
│   │   ├── AuthService.swift            OAuth 2.0 PKCE + token coalescing
│   │   ├── GoogleTasksService.swift     Tasks API + batch ops + grouping
│   │   └── QuickAddParser.swift         Natural-language #/! parsing (20 tests)
│   └── Views/
│       ├── QuickAddPanel.swift          Main UI: input + tabs + list + bulk actions
│       ├── TaskRowView.swift            Expandable row with markdown rendering
│       ├── MarkdownView.swift           Block-level markdown (headings/bullets)
│       ├── SettingsView.swift           Preferences + appearance + auto-refresh
│       └── LoginView.swift              OAuth flow UI
└── EventuallyWidget/
    └── EventuallyWidget.swift           WidgetKit widget (placeholder)
```

## Dependencies

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — customizable global shortcuts

## Roadmap

See [PLAN.md](PLAN.md).
