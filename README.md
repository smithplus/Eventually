# Eventually

> Google Tasks en tu menu bar de macOS. Nativo, rápido, sin Electron.

*"Get things done. Eventually."*

---

## Features

- Icono en el menu bar con popover de tareas
- Shortcuts globales customizables
  - `⌘ Shift T` — abrir / cerrar
  - `⌘ Shift O` — abrir con foco en agregar tarea
- Soporte de múltiples listas de Google Tasks
- Agregar, completar, editar y eliminar tareas
- Widget de escritorio small y medium (WidgetKit)
- Login con Google en el browser — tokens guardados en Keychain

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
| `⌘ Shift T` | Abrir / cerrar Eventually |
| `⌘ Shift O` | Abrir con foco en "agregar tarea" |

Customizables en **Preferencias → Shortcuts**.

## Estructura del proyecto

```
Sources/
├── Eventually/
│   ├── EventuallyApp.swift           Entry point
│   ├── AppDelegate.swift             Menu bar + shortcuts globales
│   ├── ShortcutManager.swift         Definición de shortcuts
│   ├── Config.swift                  Credenciales OAuth (git-ignored)
│   ├── Models/
│   │   └── TaskModels.swift          Structs GTask, TaskList
│   ├── Services/
│   │   ├── AuthService.swift         OAuth 2.0 PKCE + servidor local + Keychain
│   │   └── GoogleTasksService.swift  Google Tasks API (CRUD)
│   └── Views/
│       ├── PopoverView.swift          Login / main container
│       ├── TasksView.swift            Lista + agregar tarea
│       ├── TaskRowView.swift          Fila con edición inline
│       └── SettingsView.swift         Preferencias + shortcuts
└── EventuallyWidget/
    └── EventuallyWidget.swift         Widget WidgetKit (small + medium)
```

## Dependencias

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — shortcuts globales customizables

## Roadmap

Ver [PLAN.md](PLAN.md).
