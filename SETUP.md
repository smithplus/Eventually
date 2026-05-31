# TaskBar - Setup Guide

## Paso 1: Credenciales de Google

1. Ir a https://console.cloud.google.com
2. Crear un proyecto nuevo (ej. "TaskBar")
3. En "APIs & Services" > "Enable APIs" → habilitar **Google Tasks API**
4. En "APIs & Services" > "Credentials" → "Create Credentials" > **OAuth 2.0 Client ID**
5. Tipo de aplicación: **macOS**
6. Bundle ID: `app.tabella.TaskBar`
7. Copiar **Client ID** y **Client Secret**

Editar `Sources/TaskBar/Config.swift`:
```swift
enum GoogleConfig {
    static let clientId = "TU_CLIENT_ID.apps.googleusercontent.com"
    static let clientSecret = "TU_CLIENT_SECRET"
}
```

## Paso 2: URL Scheme en Xcode

En Xcode > Target TaskBar > Info > URL Types:
- Add: Identifier = `app.tabella.taskbar`, URL Schemes = `app.tabella.taskbar`

## Paso 3: Signing

En Xcode > Target TaskBar > Signing & Capabilities:
- Seleccionar tu equipo de desarrollo (puede ser Personal Team)

## Paso 4: Compilar y correr

`Cmd+R` en Xcode

---

## Shortcuts por defecto

| Shortcut | Acción |
|---|---|
| `⌘+Shift+T` | Abrir/cerrar TaskBar |
| `⌘+Shift+O` | Abrir con foco en "agregar tarea" |

Ambos son customizables en **Settings > Shortcuts**.

---

## Estructura del proyecto

```
Sources/
├── TaskBar/
│   ├── TaskBarApp.swift       — Entry point
│   ├── AppDelegate.swift      — Menu bar + shortcuts
│   ├── ShortcutManager.swift  — Global keyboard shortcuts
│   ├── Config.swift           — ⚠️ Poner tus credenciales aquí
│   ├── Models/
│   │   └── TaskModels.swift   — Task, TaskList structs
│   ├── Services/
│   │   ├── AuthService.swift  — OAuth 2.0 + Keychain
│   │   └── GoogleTasksService.swift — Google Tasks API
│   └── Views/
│       ├── PopoverView.swift  — Login / main switch
│       ├── TasksView.swift    — Lista de tareas + add
│       ├── TaskRowView.swift  — Fila individual con edición
│       └── SettingsView.swift — Preferencias + shortcuts
└── TaskBarWidget/
    └── TaskBarWidget.swift    — WidgetKit (small + medium)
```
