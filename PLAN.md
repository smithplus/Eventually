# Eventually — Improvement Plan

## Add Task — Expanded UI (inspired by KiteTasks)

**Reference**: KiteTasks floating panel screenshot

### Proposed design
- Main field: "Task name" with hint `use # for list, @ for account`
- Secondary field: "Description / Notes" (collapsible or always visible)
- Quick date buttons: **Today** · **Tomorrow** · 📅 (date picker)
- Footer: list selector `≡ My Tasks ▾` + account `user@gmail.com`
- Buttons: **Cancel** · **Add task** (primary)

### Inline commands in task name
| Command | Action |
|---|---|
| `#name` | Switch to that list (e.g. `#Work`) |
| `@account` | Select account (future multi-account) |
| `today` / `tomorrow` / `monday` | Assign date via NLP |

### Behavior
- Opens as a floating window separate from the popover (not inside the list)
- Dedicated shortcut: ⌘+Shift+O
- Pressing Enter in the name field → focus moves to Description
- Tab navigates between fields
- Escape cancels and closes
- ⌘+Enter confirms from any field

---

## Multi-profile + multi-provider (future · GitHub issue)

**Idea**: the user creates profiles (e.g. **Personal**, **Work**) and chooses which task provider each one uses: Google Tasks, Linear, TickTick, etc. Eventually becomes a unified frontend over multiple backends.

### API feasibility research (May 2026)

| Provider | Public API | Auth | Verdict |
|---|---|---|---|
| **Google Tasks** | Official REST | OAuth 2.0 | ✅ Already integrated |
| **Linear** | Full GraphQL | OAuth 2.0 + API keys | ✅ Viable — ideal for "Work" |
| **TickTick** | Open API (`api.ticktick.com/open/v1`) | OAuth 2.0 | ✅ Viable — limited scope (basic task/project CRUD, rate limits) |
| **Google Keep** | Enterprise only | Workspace admin + domain-wide delegation | ❌ Not viable for personal accounts (no consumer API) |

**Conclusion**: start with Google Tasks + Linear + TickTick. Google Keep is out unless using unofficial scraping (fragile, not recommended).

### Proposed architecture
- `TaskProvider` protocol (fetch/add/complete/update/delete/lists) that abstracts the backend.
- Implementations: `GoogleTasksProvider` (refactor of current), `LinearProvider`, `TickTickProvider`.
- `Profile { name, provider, credentials }` model — per-profile credentials in secure storage.
- Profile selector in the header (next to the view selector).
- Per-provider onboarding with OAuth flow and guide on how to get credentials.

### Concept mapping
- Google Tasks: lists → projects; no priority; date only.
- Linear: teams/projects → "lists"; has states, priority, assignees, labels.
- TickTick: projects → "lists"; priority (0/1/3/5), tags, due with time.
- Normalize to a common model and expose provider-specific fields where applicable.

---

## Decided Roadmap (Jun 2026)

> Features confirmed from [ideas.md](ideas.md). **Each pending item has a GitHub issue for tracking.**

> **Current priority: refine Google Tasks to optimal state before Linear integration.**

---

## 🎯 Path to "Optimal State" (Google Tasks)

Critical refinements before starting Linear integration:

### P0 — Critical for production
- [ ] **Notifications** — reminder when a task is due today or overdue
- [ ] **Error handling UX** — what happens without internet, sync failures, offline mode
- [ ] **Performance polish** — lazy loading, smooth scrolling with many (100+) tasks
- [x] **Keyboard navigation refinement** — cursor nav removed, zero conflicts ✅

### P1 — High priority
- [x] **Drag & drop reorder** ✅ build 4
- [x] **Clickable URLs in notes** ✅ build 4
- [x] **Better description input** — Notion-style clean editor ✅ build 4
- [x] **Auto-updates (Sparkle)** — integrated Sparkle 2.9.2 ✅ build 4
- [x] **Full row tappable to expand** — no more "click the title" friction ✅
- [x] **Keyboard nav conflicts resolved** — removed cursor nav, zero input interference ✅
- [x] **UX audit** — 9 improvements (confirmations, hints, date picker, sort indicator) ✅
- [x] **Visual polish** — Linear + Raycast-inspired design system ✅ build 7

### P2 — Nice to have
- [ ] **Functional widget** — currently a placeholder; needs App Group + real cache
- [ ] **Calendar view** — tasks with dates in a monthly/weekly grid

---

## 🚀 Next: Linear Integration (Work Profile)

Once Google Tasks is in "optimal state":
1. Implement `TaskProvider` protocol
2. Refactor current service into `GoogleTasksProvider`
3. Add `LinearProvider` (GraphQL + OAuth)
4. Profile switching UI (Personal = Google, Work = Linear)
5. Concept mapping (Linear issues → tasks, states, priorities, labels)

**End goal:** Personal (Google Tasks) + Work (Linear) in Eventually with profile switching

---

### Pending (with issue) — ✅ feasible with the API
- [ ] **Group by date** (Overdue/Today/Tomorrow/This week) — #2
- [ ] **Completed tasks view** — #3
- [ ] **Full keyboard navigation + ⌘K actions** — #4
- [ ] **Calendar view** — #5
- [ ] **Real desktop widget** (App Group + cache) — #9
- [ ] **Drag & drop** task reorder — #10
- [ ] **Quick-capture (clipboard/snippets/aliases)** — #13

### Pending with ⚠️ API limitation (design decision)
- [ ] **Reminders/notifications** — #6 — date syncs, time would be local only
- [ ] **Recurrence** — #7 — API doesn't expose it; would need local management

### Pending refinements (from visual/UX audit)
- [ ] Click-outside monitor: verify window doesn't close when using popovers/menus
- [ ] Differentiated empty states (no session / offline / no lists / no tasks)
- [ ] Clean up `error` on success; error visibility in background auto-refresh

### Done
- [x] **Single UI**: Popover removed; everything in the Command Window (login included); menu bar icon optional
- [x] **Audit pass A**: `#list` routing, delete active list, rename guard, sortOrder persists, unified date color, double-fetch removed
- [x] **Optimized auto-refresh** (Settings → Sync) — #8 ✅
- [x] **Create / rename / delete / move lists** — #11 ✅
- [x] **Markdown in notes** + optional description in input — #12 ✅
- [x] Badge counter, Launch at login (real), sort in smart views, timezone fix (UTC)
- [x] `!date` marker (ES/EN, 18 tests), `#list` + natural dates, subtasks
- [x] Search, appearance (light/dark/system), draft retention, focus return
- [x] Persistent resize/position, group by list, list selector in input
- [x] **Comprehensive UX audit** — 12 keyboard/focus/state conflicts resolved (build 3)

### ⚠️ Google Tasks API limitations (important)
- [ ] **Reminders / notifications**: date syncs fine; **time does NOT** (API stores date only). A time-based notification would be **local to the app**, not synced with Google or mobile.
- [ ] **Recurrence**: ⚠️ **The Google Tasks API does NOT expose recurrence.** A recurring task created on mobile (Google app) **cannot be read or edited** via API — Eventually sees it as a standalone task. True bidirectional recurrence would require **managing it locally in Eventually** (generating instances ourselves), which wouldn't reflect in the official Google app. Design decision pending.

### Other
- [ ] **Multi-profile + multi-provider** (Google Tasks + Linear + TickTick) — see section above and issue #1
- [ ] **Clipboard → task**, **snippets/templates**, **list aliases** (Raycast-style quick-capture)
