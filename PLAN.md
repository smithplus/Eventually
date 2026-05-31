# TaskBar — Plan de mejoras

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

## Backlog

- [ ] Add Task UI expandida (panel flotante estilo KiteTasks)
- [ ] Parsing de `#lista` y fechas naturales en el campo de nombre  
- [ ] Launch at login (SMAppService)
- [ ] Notificaciones locales para tareas vencidas
- [ ] Badge con contador de tareas en el icono del menu bar
- [ ] Soporte drag & drop para reordenar tareas
- [ ] Subtareas
