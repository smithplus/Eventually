# Eventually v1.0.0 (build 2)

## 🎯 What's Fixed

### Text Editing UX Improvements
- **Removed Space key for task selection** — was confusing and interfered with typing
- **Protected text inputs** — Enter/Return now respects when you're editing task details
- **Selection now via ⌘+Click only** — more intentional, less accidental

### User Experience
- Fixed: Space bar would select tasks while typing in description fields
- Fixed: Enter key would complete tasks while adding line breaks (Shift+Enter) in notes
- Improved: TaskRowView now notifies parent when in edit mode to prevent shortcuts

## 📋 What's Included

All features from build 1 plus the UX fixes above:
- ✅ Smart recurring task detection (Daily/Weekly/Monthly badges)
- ✅ Completed tasks section (collapsible with animations)
- ✅ Uncomplete tasks (click checkbox to undo)
- ✅ Draft persistence across app restarts
- ✅ Group by date/list with collapsible headers
- ✅ Keyboard-first navigation
- ✅ Natural language date parsing (!mañana, !4dias, etc.)
- ✅ Markdown rendering in task notes
- ✅ OAuth 2.0 with Google Tasks
- ✅ Auto-refresh (5/15/30 min)
- ✅ Menu bar app with badge count

## 🔧 Technical

- Shared editing state between QuickAddPanel ↔ TaskRowView
- ListNavKeyHandler checks `isAnyTaskBeingEdited` before handling shortcuts
- Version display in Settings → Account tab

---

**Full feature parity with Google Tasks web achieved.**
