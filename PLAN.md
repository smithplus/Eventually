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

## Roadmap decidido (jun 2026)

> Features confirmadas por el usuario desde [ideas.md](ideas.md). Orden sugerido por valor/esfuerzo.

### Listas para hacer (✅ factibles con la API)
- [ ] **Navegación 100% teclado** (flechas, Enter para completar/expandir, acciones ⌘K)
- [ ] **Agrupado por fecha** (Vencidas / Hoy / Mañana / Esta semana) — *distinto de subtareas*
- [ ] **Vista de completadas** (toggle ver/ocultar)
- [ ] **Vista calendario** (grilla mensual con tareas por fecha)
- [ ] **Badge con contador** en el menu bar + toggle en Settings
- [ ] **Launch at login** (SMAppService)
- [ ] **Auto-refresh optimizado** (al abrir + intervalo, con backoff/debounce)
- [ ] **Widget de escritorio real** (App Group + escritura de cache)
- [ ] **Drag & drop** para reordenar dentro de una lista
- [ ] **Crear / renombrar / borrar listas** desde la app
- [ ] **Markdown en notas/descripciones** (render básico)
- [ ] **Más idiomas/formatos de fecha** (ampliar parser ES/EN)

### Hechas
- [x] **Marcador `!fecha`** (`!4dias`, `!3d`, `!2semanas`, `!1mes`, `!manana`) — ES/EN, 18 tests
- [x] Add Task UI expandida (Command Window estilo KiteTasks)
- [x] Parsing de `#lista` y fechas naturales
- [x] Subtareas, search, appearance, draft retention, resize/posición persistente

### ⚠️ Con limitación de la API de Google Tasks (importante)
- [ ] **Recordatorios / notificaciones**: la fecha sí sincroniza; **la hora NO** (la API solo guarda fecha). Una notificación con hora sería **local en la app**, no sincronizada con Google ni con el celular.
- [ ] **Recurrencia**: ⚠️ **La API de Google Tasks NO expone recurrencia.** Una tarea recurrente creada en el celular (app de Google) **no se puede leer ni editar** vía API — Eventually la vería como una tarea suelta. Para tener recurrencia real y bidireccional habría que **gestionarla localmente en Eventually** (generar las instancias nosotros), lo cual no se reflejaría en la app oficial de Google. Decisión de diseño pendiente.

### Otras
- [ ] **Multi-profile + multi-provider** (Google Tasks + Linear + TickTick) — ver sección arriba e issue #1
- [ ] **Clipboard → task**, **snippets/templates**, **aliases de lista** (quick-capture estilo Raycast)
