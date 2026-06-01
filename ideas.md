# Ideas — features de interés

> Investigación de TickTick, Raycast y apps similares (mayo 2026).
> **Esto es solo un menú de ideas. Qué se implementa lo decidís vos.**
> Marcado por viabilidad con la API pública de Google Tasks y esfuerzo estimado.

Leyenda de viabilidad:
- ✅ Factible con la API de Google Tasks
- ⚠️ Parcial — requiere almacenamiento local (la API no lo expone)
- ❌ Imposible con la API actual (Google Tasks no lo soporta)

---

## De Raycast (quick-capture / launcher)

| Idea | Qué es | Viabilidad | Esfuerzo |
|---|---|---|---|
| **Clipboard → task** | Botón/atajo que crea una tarea con lo que tengas en el portapapeles | ✅ | Bajo |
| **Snippets / templates** | Plantillas de tareas frecuentes (ej. "Reunión semanal #Work") insertables con un atajo | ⚠️ (local) | Bajo |
| **Aliases de listas** | Escribir `#w` → resuelve a "Work" (alias cortos configurables) | ⚠️ (local) | Bajo |
| **Quicklink "abrir en Google Tasks"** | Acción por tarea para abrirla en tasks.google.com | ✅ | Bajo |
| **Acciones rápidas con ⌘K** | Menú de acciones contextual sobre la tarea seleccionada (estilo Raycast) | ✅ | Medio |
| **Navegación 100% teclado** | Flechas para moverse por la lista, Enter para completar/expandir, sin mouse | ✅ Hecho (parcial) | — |
| **Hyperkey / atajo configurable** | Ya tenés shortcut global configurable | ✅ Hecho | — |

## De TickTick (gestión)

| Idea | Qué es | Viabilidad | Esfuerzo |
|---|---|---|---|
| **Agrupado por fecha** | Secciones Vencidas / Hoy / Mañana / Esta semana | ✅ Hecho | — |
| **Vista de completadas** | Toggle para ver/ocultar las tareas hechas | ✅ | Bajo |
| **Pomodoro timer** | Timer de foco 25/5 sobre una tarea, con stats | ⚠️ (local) | Medio |
| **Habit tracking** | Hábitos diarios con racha (separado de las tareas) | ⚠️ (local) | Alto |
| **Eisenhower Matrix** | Cuadrante urgente/importante por prioridad | ❌ (Google Tasks no tiene prioridad) | — |
| **Vista calendario** | Tareas con fecha en una grilla mensual/semanal | ✅ | Alto |
| **Recordatorios / notificaciones** | Notificación local cuando una tarea vence hoy | ✅ (fecha) / ⚠️ (hora) | Medio |
| **Recurrencia** | Tareas que se repiten (diaria/semanal) | ❌ vía API (no se puede leer/escribir) | — |
| **Prioridades** | Alta/Media/Baja | ❌ (no existe en Google Tasks) | — |
| **Hora de vencimiento** | "Mañana 8:00" | ❌ (la API solo guarda fecha) | — |

## De apps de menu bar / utilidad

| Idea | Qué es | Viabilidad | Esfuerzo |
|---|---|---|---|
| **Badge con contador** | Número de tareas de hoy en el ícono del menu bar | ✅ Hecho | — |
| **Launch at login** | Ya está el toggle, falta cablear `SMAppService` | ✅ Hecho | — |
| **Auto-refresh** | Refrescar cada X min y al abrir | ✅ Hecho | — |
| **Widget de escritorio real** | Cablear el App Group + escribir cache (hoy muestra placeholder) | ✅ | Medio |
| **Drag & drop reordenar** | Reordenar tareas dentro de una lista | ✅ | Medio |
| **Crear/renombrar/borrar listas** | Gestión de listas desde la app | ✅ Hecho | — |
| **Detección de URLs en notas** | Links clickeables en la descripción | ✅ | Bajo |
| **Markdown en notas** | Render básico de la descripción | ✅ Hecho | — |

## Input / parsing (convención)

| Idea | Qué es | Viabilidad | Esfuerzo |
|---|---|---|---|
| **Marcador explícito de fecha** | `!mañana` o `!viernes` (alternativa al lenguaje natural; evitar `@` por emails) | ✅ Hecho | — |
| **Multi-cuenta con prefijo seguro** | `>>Work` para rutear a una cuenta/proveedor (ver issue #1) | ✅ | Alto |
| **Más idiomas de fechas** | Ampliar el parser (fechas relativas tipo "en 3 días", "próximo mes") | ✅ | Bajo |

---

## Mi top 5 (relación valor / esfuerzo), para tu consideración
1. ~~**Agrupado por fecha**~~ ✅ Hecho
2. ~~**Badge con contador**~~ ✅ Hecho + **notificaciones de vencimiento** pendiente
3. ~~**Navegación por teclado**~~ ✅ Hecho + **acciones ⌘K** pendiente
4. ~~**Vista de completadas**~~ ✅ Hecho (sección colapsable + uncomplete)
5. ~~**Recurrencia**~~ ✅ Hecho (detección automática por patrón + badge ↻)

## Completado recientemente (Junio 2026)
- ✅ Recurring task detection (Weekly/Monthly/Daily badges)
- ✅ Completed tasks section (colapsable, animaciones)
- ✅ Uncomplete tasks (click checkbox para deshacer)
- ✅ Draft persistence (borrador sobrevive al cerrar)
- ✅ Concurrent mutation guards (no duplicate requests)
- ✅ Clear completed bulk action
- ✅ Keyboard edit shortcut ('E' key)
- ✅ Reliability audit completo (9 critical bugs fixed)
