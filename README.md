# GuildControl (v4.5.0)

**GuildControl** es un addon modular para World of Warcraft Retail diseñado para la gestión integral de hermandades, control de rosters de raid, seguimiento de miembros, anuncios automáticos y exportación de datos a Google Sheets.

## 🛠️ Arquitectura Modular

- **`Core.lua`**: Inicialización del addon, base de datos de SavedVariables, eventos principales y comandos de chat (`/gct`).
- **`Modules/UI.lua`**: Interfaz de usuario principal, tabla interactiva, ordenación por columnas, filtros en tiempo real, tooltips y panel de vista previa.
- **`Modules/Achievements.lua`**: Lógica de logros de hermandad (categorías, estadísticas, detalle, quién lo completó, apertura en la ventana de Blizzard y refresco por `ACHIEVEMENT_EARNED`).
- **`Modules/Announcements.lua`**: Sistema de configuración de anuncios múltiples periódicos en el canal de la hermandad.
- **`Modules/CSV.lua`**: Exportador e importador de listas masivas, altas del día y bajas en formato CSV compatibles con Google Sheets.
- **`Modules/Professions.lua`**: Módulo aislado para el escaneo y sincronización de profesiones de los miembros.

## 🏆 Panel de logros

- Pasa el ratón sobre un logro para ver su descripción, puntos, recompensa, fecha y quién lo completó.
- Clic izquierdo: muestra el detalle en el panel de vista previa (estado, fecha, completado por, participantes y criterios).
- Clic derecho o Shift+clic: abre el logro en la ventana de logros de Blizzard.

## 🚀 Comandos

- `/gct` - Abre o cierra la interfaz principal del addon.
- `/gct csv` - Abre directamente el panel de exportación a Google Sheets / CSV.
- `/gct bajas` - Abre el historial de bajas y salidas de la hermandad.