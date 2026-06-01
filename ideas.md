# Ideas — features of interest

> Research from TickTick, Raycast, and similar apps (May 2026).
> **This is just a menu of ideas. What gets built is your call.**
> Marked by feasibility with the public Google Tasks API and estimated effort.

Feasibility legend:
- ✅ Feasible with Google Tasks API
- ⚠️ Partial — requires local storage (API doesn't expose it)
- ❌ Not possible with current API (Google Tasks doesn't support it)

---

## From Raycast (quick-capture / launcher)

| Idea | What it is | Feasibility | Effort |
|---|---|---|---|
| **Clipboard → task** | Button/shortcut that creates a task from clipboard contents | ✅ | Low |
| **Snippets / templates** | Frequent task templates (e.g. "Weekly meeting #Work") insertable with a shortcut | ⚠️ (local) | Low |
| **List aliases** | Type `#w` → resolves to "Work" (configurable short aliases) | ⚠️ (local) | Low |
| **Quicklink "open in Google Tasks"** | Per-task action to open it at tasks.google.com | ✅ | Low |
| **Quick actions with ⌘K** | Contextual action menu on selected task (Raycast-style) | ✅ | Medium |
| **Full keyboard navigation** | Arrow keys to move through list, Enter to complete/expand, no mouse | ✅ Done (partial) | — |
| **Hyperkey / configurable shortcut** | Already have a configurable global shortcut | ✅ Done | — |

## From TickTick (task management)

| Idea | What it is | Feasibility | Effort |
|---|---|---|---|
| **Group by date** | Sections: Overdue / Today / Tomorrow / This week | ✅ Done | — |
| **Completed tasks view** | Toggle to show/hide completed tasks | ✅ Done | — |
| **Pomodoro timer** | 25/5 focus timer on a task, with stats | ⚠️ (local) | Medium |
| **Habit tracking** | Daily habits with streak (separate from tasks) | ⚠️ (local) | High |
| **Eisenhower Matrix** | Urgent/important quadrant by priority | ❌ (Google Tasks has no priority) | — |
| **Calendar view** | Tasks with dates in a monthly/weekly grid | ✅ | High |
| **Reminders / notifications** | Local notification when a task is due today | ✅ (date) / ⚠️ (time) | Medium |
| **Recurrence** | Repeating tasks (daily/weekly) | ❌ via API (can't read/write) | — |
| **Priorities** | High/Medium/Low | ❌ (doesn't exist in Google Tasks) | — |
| **Due time** | "Tomorrow 8:00am" | ❌ (API stores date only) | — |

## From menu bar / utility apps

| Idea | What it is | Feasibility | Effort |
|---|---|---|---|
| **Badge counter** | Number of today's tasks on the menu bar icon | ✅ Done | — |
| **Launch at login** | Toggle is there, wired to `SMAppService` | ✅ Done | — |
| **Auto-refresh** | Refresh every X min and on open | ✅ Done | — |
| **Real desktop widget** | Wire App Group + write cache (currently shows placeholder) | ✅ | Medium |
| **Drag & drop reorder** | Reorder tasks within a list | ✅ | Medium |
| **Create/rename/delete lists** | List management from the app | ✅ Done | — |
| **Clickable URLs in notes** | Clickable links in the description | ✅ | Low |
| **Markdown in notes** | Basic rendering of the description | ✅ Done | — |

## Input / parsing (conventions)

| Idea | What it is | Feasibility | Effort |
|---|---|---|---|
| **Explicit date marker** | `!tomorrow` or `!friday` (alternative to natural language; avoid `@` due to emails) | ✅ Done | — |
| **Multi-account with safe prefix** | `>>Work` to route to an account/provider (see issue #1) | ✅ | High |
| **More date languages** | Expand the parser (relative dates like "in 3 days", "next month") | ✅ | Low |

---

## Top 5 (best value / effort ratio)
1. ~~**Group by date**~~ ✅ Done
2. ~~**Badge counter**~~ ✅ Done + **due date notifications** pending
3. ~~**Keyboard navigation**~~ ✅ Done + **⌘K actions** pending
4. ~~**Completed tasks view**~~ ✅ Done (collapsible section + uncomplete)
5. ~~**Recurrence**~~ ✅ Done (auto-detection by pattern + ↻ badge)

## Recently completed (June 2026)
- ✅ Recurring task detection (Weekly/Monthly/Daily badges)
- ✅ Completed tasks section (collapsible, animations)
- ✅ Uncomplete tasks (click checkbox to undo)
- ✅ Draft persistence (draft survives app close)
- ✅ Concurrent mutation guards (no duplicate requests)
- ✅ Clear completed bulk action
- ✅ Keyboard edit shortcut ('E' key)
- ✅ Reliability audit (9 critical bugs fixed)
- ✅ Text editing UX fix (Space/Enter respect active text fields)
- ✅ Comprehensive UX audit — 12 keyboard/focus/state conflicts resolved (build 3)
- ✅ Clickable URLs in notes (auto-detected, build 4)
- ✅ Better description input — monospaced editor + format toolbar + preview toggle (build 4)
- ✅ Drag & drop reorder — tasks reorder via Google Tasks API (build 4)
- ✅ Auto-updates via Sparkle 2.9.2 — "Check for Updates" in Settings (build 4)
