# Eventually — Plan de mejoras

## Add Task — UI expandida (inspirado en KiteTasks)

**Referencia**: screenshot de KiteTasks con panel flotante

### Diseño propuesto
- Campo principal: "Task name" con hint `use # for list, @ for account`
- Campo secundario: "Description / Notes" (collapsible o siempre visible)
- Quick date buttons: **Today** · **Tomorrow** · 📅 (date picker)
- Footer: selector de lista `≡ My Tasks ▾` + cuenta `user@gmail.com`
- Botones: **Cancel** · **Add task** (primary)

### Comandos inline en el nombre de tarea
| Comando | Acción |
|---|---|
| `#nombre` | Cambia a esa lista (ej. `#Work`) |
| `@cuenta` | Selecciona cuenta (futuro multi-account) |
| `hoy` / `mañana` / `lunes` | Asigna fecha via NLP |

### Comportamiento
- Se abre como ventana flotante separada del popover (no dentro de la lista)
- Shortcut dedicado: ⌘+Shift+O
- Al presionar Enter en el campo de nombre → foco pasa a Description
- Tab navega entre campos
- Escape cancela y cierra
- ⌘+Enter confirma desde cualquier campo

---

## Multi-profile + multi-provider (futuro · GitHub issue)

**Idea**: el usuario crea perfiles (ej. **Personal**, **Work**) y elige qué proveedor de tareas usa cada uno: Google Tasks, Linear, TickTick, etc. Eventually se vuelve un front-end unificado sobre varios backends.

### Viabilidad de APIs investigada (mayo 2026)

| Proveedor | API pública | Auth | Veredicto |
|---|---|---|---|
| **Google Tasks** | REST oficial | OAuth 2.0 | ✅ Ya integrado |
| **Linear** | GraphQL completa | OAuth 2.0 + API keys | ✅ Viable — ideal para "Work" |
| **TickTick** | Open API (`api.ticktick.com/open/v1`) | OAuth 2.0 | ✅ Viable — scope limitado (CRUD básico de tareas/proyectos, rate limits) |
| **Google Keep** | Solo enterprise | Workspace admin + domain-wide delegation | ❌ No viable para cuentas personales (no hay API de consumidor) |

**Conclusión**: arrancar con Google Tasks + Linear + TickTick. Google Keep queda fuera salvo scraping no oficial (frágil, no recomendado).

### Arquitectura propuesta
- Protocolo `TaskProvider` (fetch/add/complete/update/delete/lists) que abstrae el backend.
- Implementaciones: `GoogleTasksProvider` (refactor del actual), `LinearProvider`, `TickTickProvider`.
- Modelo `Profile { name, provider, credentials }` — credenciales por perfil en el almacenamiento seguro.
- Selector de perfil en el header (junto al selector de vista).
- Onboarding por proveedor con su flow de OAuth y guía de cómo conseguir credenciales.

### Mapeo de conceptos
- Google Tasks: listas → proyectos; sin prioridad; solo fecha.
- Linear: teams/projects → "listas"; tiene estados, prioridad, assignees, labels.
- TickTick: projects → "listas"; prioridad (0/1/3/5), tags, due con hora.
- Normalizar a un modelo común y exponer lo específico de cada uno donde aplique.

---

## Backlog

> Menú ampliado de ideas (TickTick/Raycast/similares, con viabilidad y esfuerzo): ver [ideas.md](ideas.md).

- [ ] **Multi-profile + multi-provider** (ver sección arriba) — Google Tasks + Linear + TickTick
- [x] Add Task UI expandida (panel flotante estilo KiteTasks)
- [x] Parsing de `#lista` y fechas naturales en el campo de nombre
- [x] Subtareas
- [ ] Launch at login (SMAppService)
- [ ] Notificaciones locales para tareas vencidas
- [ ] Badge con contador de tareas en el icono del menu bar
- [ ] Soporte drag & drop para reordenar tareas
- [ ] Agrupado por fecha (Vencidas/Hoy/Mañana/Esta semana) estilo TickTick
- [ ] Wire del widget de escritorio (App Group + escritura de cache)
