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

> Features confirmadas por el usuario desde [ideas.md](ideas.md). **Cada pendiente tiene un GitHub issue para tracking.**

> **Prioridad actual: refinar Google Tasks a estado óptimo antes de Linear integration.**

---

## 🎯 Path to "Estado Óptimo" (Google Tasks)

Refinamientos críticos antes de empezar Linear integration:

### P0 — Crítico para producción
- [ ] **Notificaciones** — reminder cuando tarea vence hoy/está overdue
- [ ] **Error handling UX** — qué pasa sin internet, sync failures, offline mode
- [ ] **Performance polish** — lazy loading, smooth scrolling con muchas (100+) tareas
- [ ] **Keyboard navigation refinement** — actualmente tropieza con input fields (Space/Enter conflicts resueltos, pero puede mejorar)

### P1 — Alta prioridad
- [ ] **Drag & drop reorder** — reordenar tareas dentro de lista (ideas.md: esfuerzo medio)
- [ ] **URLs clickeables en notas** — detectar links y hacerlos clickeables (ideas.md: esfuerzo bajo)
- [ ] **Mejorar input de data en descripciones** — mejor UX para editar notas largas con markdown

### P2 — Nice to have
- [ ] **Widget funcional** — actualmente es placeholder; necesita App Group + cache real
- [ ] **Vista calendario** — tareas en grilla mensual/semanal

---

## 🚀 Después: Linear Integration (Work Profile)

Una vez Google Tasks esté en "estado óptimo":
1. Implementar `TaskProvider` protocol
2. Refactor `GoogleTasksProvider` del servicio actual
3. Agregar `LinearProvider` (GraphQL + OAuth)
4. Profile switching UI (Personal = Google, Work = Linear)
5. Mapeo de conceptos (Linear issues → tareas, estados, prioridades, labels)

**Objetivo final:** Personal (Google Tasks) + Work (Linear) en Eventually con profile switching

---

### Pendientes (con issue) — ✅ factibles con la API
- [ ] **Agrupado por fecha** (Vencidas/Hoy/Mañana/Esta semana) — #2 — *distinto de subtareas*
- [ ] **Vista de completadas** — #3
- [ ] **Navegación 100% teclado + acciones ⌘K** — #4
- [ ] **Vista calendario** — #5
- [ ] **Widget de escritorio real** (App Group + cache) — #9
- [ ] **Drag & drop** para reordenar tareas — #10
- [ ] **Quick-capture (clipboard/snippets/aliases)** — #13

### Pendientes con ⚠️ limitación de API (decisión de diseño)
- [ ] **Recordatorios/notificaciones** — #6 — fecha sincroniza, hora sería local
- [ ] **Recurrencia** — #7 — la API no la expone; habría que gestionarla local

### Refinamiento pendiente (de la auditoría visual/UX)
- [ ] Click-outside monitor: verificar que no cierre la ventana al usar popovers/menús
- [ ] Empty state diferenciado (sin sesión / offline / sin listas / sin tareas)
- [ ] Navegación por teclado para completar/editar tareas
- [ ] Limpiar `error` al tener éxito; visibilidad de errores en auto-refresh de fondo

### Hechas
- [x] **Single UI**: Popover retirado; todo en el Command Window (login incluido); ícono de menu bar opcional
- [x] **Audit pass A**: routing de `#lista`, borrar lista activa, rename guard, sortOrder persiste, color de fecha unificado, doble-fetch removido
- [x] **Auto-refresh optimizado** (Settings → Sync) — #8 ✅
- [x] **Crear / renombrar / borrar / mover (local) listas** — #11 ✅
- [x] **Markdown en notas** + descripción opcional en el input — #12 ✅
- [x] Badge con contador, Launch at login (real), sort en smart views, fix timezone (UTC)
- [x] Marcador `!fecha` (ES/EN, 18 tests), `#lista` + fechas naturales, subtareas
- [x] Search, appearance (light/dark/system), draft retention (Raycast), retorno de foco
- [x] Resize/posición persistente, agrupar por lista, selector de lista en el input

### ⚠️ Con limitación de la API de Google Tasks (importante)
- [ ] **Recordatorios / notificaciones**: la fecha sí sincroniza; **la hora NO** (la API solo guarda fecha). Una notificación con hora sería **local en la app**, no sincronizada con Google ni con el celular.
- [ ] **Recurrencia**: ⚠️ **La API de Google Tasks NO expone recurrencia.** Una tarea recurrente creada en el celular (app de Google) **no se puede leer ni editar** vía API — Eventually la vería como una tarea suelta. Para tener recurrencia real y bidireccional habría que **gestionarla localmente en Eventually** (generar las instancias nosotros), lo cual no se reflejaría en la app oficial de Google. Decisión de diseño pendiente.

### Otras
- [ ] **Multi-profile + multi-provider** (Google Tasks + Linear + TickTick) — ver sección arriba e issue #1
- [ ] **Clipboard → task**, **snippets/templates**, **aliases de lista** (quick-capture estilo Raycast)
