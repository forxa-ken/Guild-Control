# GuildControl (v4.5.0)

**GuildControl** es un addon modular para World of Warcraft Retail diseñado para la gestión integral de hermandades, control de rosters de raid, seguimiento de miembros, anuncios automáticos y exportación de datos a Google Sheets.

## 🛠️ Arquitectura Modular

- **`Core.lua`**: Inicialización del addon, base de datos de SavedVariables, eventos principales y comandos de chat (`/gct`).
- **`Modules/UI.lua`**: Interfaz de usuario principal, tabla interactiva, ordenación por columnas, filtros en tiempo real, tooltips y panel de vista previa.
- **`Modules/Achievements.lua`**: Lógica de logros de hermandad (categorías, estadísticas, detalle, quién lo completó, apertura en la ventana de Blizzard y refresco por `ACHIEVEMENT_EARNED`).
- **`Modules/Announcements.lua`**: Sistema de configuración de anuncios múltiples periódicos en el canal de la hermandad.
- **`Modules/CSV.lua`**: Exportador e importador de listas masivas, altas del día y bajas en formato CSV compatibles con Google Sheets.
- **`Modules/Professions.lua`**: Módulo aislado para el escaneo y sincronización de profesiones de los miembros.
- **`Modules/GuildChat.lua`**: Historial del chat de hermandad para el panel inferior y saludo automático a quien salude.

## 🏆 Panel de logros

- Pasa el ratón sobre un logro para ver su descripción, puntos, recompensa, fecha y quién lo completó.
- Clic izquierdo: muestra el detalle en el panel de vista previa (estado, fecha, completado por, participantes y criterios).
- Clic derecho o Shift+clic: abre el logro en la ventana de logros de Blizzard.
- **Logros de temporada**: muestra, de todas las categorías, los logros cuyo nombre o descripción menciona una temporada y los de eventos del mundo.

## ⚙️ Configuración

En la pestaña **Configuración** puedes personalizar el encabezado del panel:

- **Nombre de la hermandad**: escribe el nombre que quieres mostrar. Si lo dejas vacío (o pulsas "Usar nombre del juego") se usa el nombre real de la hermandad.
- **Icono**: elige uno de los iconos predefinidos o escribe el nombre del icono (por ejemplo `INV_Misc_QuestionMark`), su ID numérico o la ruta completa.
- **Saludo automático**: si está activado, cuando alguien de la hermandad saluda (hola, buenas, saludos...) el addon responde con el mensaje configurado tras 2-6 s. `{nombre}` se sustituye por su nombre. Los segundos de espera y los minutos sin repetir saludo a la misma persona se configuran en la columna derecha (por defecto 2 s y 30 min). Si varios miembros usan GuildControl, solo responde uno.
- **Siempre por encima**: muestra la ventana del addon por encima de las barras de acción y otros botones del juego.

## 👥 Miembros y chat

- Busca por nombre, clase, rango, rol, profesión o roster y ordena haciendo clic en las cabeceras. Al entrar en Miembros aparecen primero los conectados.
- Al seleccionar un miembro, la vista previa muestra sus profesiones por expansión (solo las tuyas y las de quien use GuildControl; abre cada profesión una vez para que se registren todas).
- Debajo de la ventana está el **chat de hermandad**, con campo para escribir. El botón Contraer/Expandir lo pliega y muestra los mensajes nuevos. Haz clic en el nombre de alguien para abrir una pestaña solo con su conversación (clic derecho en la pestaña la cierra).
- En el panel CSV el texto aparece siempre seleccionado: pulsa Ctrl+C para copiarlo.

## 🚀 Comandos

- `/gct` (o `/gct show`) - Abre o cierra la interfaz principal del addon.
- `/gct csv` - Abre directamente el panel de exportación a Google Sheets / CSV.
- `/gct bajas` - Abre el historial de bajas y salidas de la hermandad.

Todos los comandos funcionan también con el alias `/gctc` (por ejemplo, `/gctc csv`).
