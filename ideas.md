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
| **Navegación 100% teclado** | Flechas para moverse por la lista, Enter para completar/expandir, sin mouse | ✅ | Medio |
| **Hyperkey / atajo configurable** | Ya tenés shortcut global configurable | ✅ Hecho | — |

## De TickTick (gestión)

| Idea | Qué es | Viabilidad | Esfuerzo |
|---|---|---|---|
| **Agrupado por fecha** | Secciones Vencidas / Hoy / Mañana / Esta semana | ✅ | Medio |
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
| **Badge con contador** | Número de tareas de hoy en el ícono del menu bar | ✅ | Bajo |
| **Launch at login** | Ya está el toggle, falta cablear `SMAppService` | ✅ | Bajo |
| **Auto-refresh** | Refrescar cada X min y al abrir | ✅ | Bajo |
| **Widget de escritorio real** | Cablear el App Group + escribir cache (hoy muestra placeholder) | ✅ | Medio |
| **Drag & drop reordenar** | Reordenar tareas dentro de una lista | ✅ | Medio |
| **Crear/renombrar/borrar listas** | Gestión de listas desde la app | ✅ | Medio |
| **Detección de URLs en notas** | Links clickeables en la descripción | ✅ | Bajo |
| **Markdown en notas** | Render básico de la descripción | ✅ | Medio |

## Input / parsing (convención)

| Idea | Qué es | Viabilidad | Esfuerzo |
|---|---|---|---|
| **Marcador explícito de fecha** | `!mañana` o `!viernes` (alternativa al lenguaje natural; evitar `@` por emails) | ✅ | Bajo |
| **Multi-cuenta con prefijo seguro** | `>>Work` para rutear a una cuenta/proveedor (ver issue #1) | ✅ | Alto |
| **Más idiomas de fechas** | Ampliar el parser (fechas relativas tipo "en 3 días", "próximo mes") | ✅ | Bajo |

---

## Mi top 5 (relación valor / esfuerzo), para tu consideración
1. **Agrupado por fecha** — el mayor salto visual vs TickTick
2. **Badge con contador** + **notificaciones de vencimiento** — utilidad de menu bar
3. **Navegación por teclado + acciones ⌘K** — el alma de Raycast
4. **Clipboard → task** + **snippets** — captura ultrarrápida
5. **Wire del widget real** — ya está el 80%, falta el App Group

Lo decidís vos. Nada de esto está empezado.
