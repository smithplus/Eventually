# Eventually

> Google Tasks en tu menu bar de macOS. Nativo, rápido, sin Electron.

*"Get things done. Eventually."*

---

## Features

- **Command Window flotante** — quick-capture estilo Raycast con `⌘⇧O`
- **Smart views**: Today, Upcoming, All Tasks + listas personalizadas
- **Natural language input**: `#lista` y `!fecha` (`!mañana`, `!4dias`, etc.)
- **Keyboard-first**: navegación completa por teclado, multi-select, bulk actions
- **Markdown rendering** en notas (headings, bullets, inline styles)
- **Group by date / list** con headers colapsables
- **Auto-refresh** configurable (5/15/30 min)
- Widget de escritorio small y medium (WidgetKit)
- Login con Google OAuth 2.0 — tokens guardados localmente

## Cómo funciona el login

Eventually usa **tu cuenta de Google** para acceder a tus tareas. No necesitás crear ninguna API key ni cuenta de desarrollador — solo hacés click en "Sign in with Google", se abre el browser, autorizás la app y listo. El token queda guardado en el Keychain de tu Mac.

## Requisitos

- macOS 13 Ventura o superior
- Xcode 15+
- Cuenta de Google con Google Tasks activado

## Instalación (desde código)

```bash
git clone https://github.com/smithplus/Eventually.git
cd Eventually
brew install xcodegen
cp Config.template.swift Sources/Eventually/Config.swift   # luego pegá tus credenciales
xcodegen generate
open Eventually.xcodeproj
```

En Xcode: seleccionar signing team → `Cmd+R`

## Shortcuts

| Shortcut | Acción |
|---|---|
| `⌘⇧O` | Abrir / cerrar Command Window |
| `Tab` (en input) | Ir al list/date autocomplete (↑/↓ navegan, Enter acepta) |
| `Tab` (sin autocomplete) | Foco a la lista de tareas |
| `↑/↓` (en lista) | Navegar cursor |
| `Espacio` | Toggle selección |
| `Return` | Completar seleccionadas |
| `Delete` | Borrar seleccionadas |
| `⌘A` | Seleccionar todas visibles |
| `Esc` / `Tab` | Volver al input |

Customizables en **Settings**.

## Estructura del proyecto

```
Sources/
├── Eventually/
│   ├── EventuallyApp.swift              Entry point
│   ├── AppDelegate.swift                Menu bar + auto-refresh + badge
│   ├── QuickAddWindowController.swift   Command Window lifecycle
│   ├── Config.swift                     Credenciales OAuth (git-ignored)
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
    └── EventuallyWidget.swift            Widget WidgetKit (placeholder)
```

## Dependencias

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — shortcuts globales customizables

## Roadmap

Ver [PLAN.md](PLAN.md).
