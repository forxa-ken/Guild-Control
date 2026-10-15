# GuildControl

## Próxima versión

### Idiomas
- El addon está disponible en inglés y en español. Por defecto usa el idioma del juego (español para clientes esES y esMX, inglés para el resto) y se puede elegir en Configuración > Ventana > Idioma (se aplica al recargar).
- Sistema de traducciones en `Locales/` preparado para añadir más idiomas copiando `enUS.lua`.
- Las variables de los mensajes también se pueden escribir en inglés: `{name}`, `{guild}`, `{date}`, `{time}`, `{difficulty}`, `{boss}`, `{note}` y `{role}`.
- `/gct leaves` funciona igual que `/gct bajas`.

### Correcciones
- El punto verde o gris de los oficiales del Resumen no se mostraba por una ruta de icono mal escrita.

## 5.0.0 (beta)

Primera versión pública. Todo el addon está en español.

### Hermandad y miembros
- Encabezado con el nombre, el icono, el reino y la facción de la hermandad, y botón de Discord configurable.
- Miembros: buscador, orden por columnas y conectados primero. Columnas de tipo (Main o Alter), rol con icono, enfoque y profesiones. Clic derecho para susurrar o invitar al grupo.
- Resumen como tablón de noticias: logros, jefes derrotados, botín (con su origen) y altas y bajas, agrupado por semanas. Además, mensaje del día, próximas bandas, rosters y oficiales.
- Chat de hermandad contraíble, con pestañas por persona y saludo automático opcional (desactivado por defecto).

### Perfiles
- Mi perfil: rol principal y secundario, especialización y especialización off de tu clase, enfoque (PvE, PvP o Social), si es tu principal o un alter, y una nota para los oficiales.
- Perfil de oficial y de jugador: cada uno ve sus pestañas.

### Bandas
- Roster: la lista de personas con las que cuenta la hermandad, con criterios, cobertura de utilidades por clase, fechas, asistencia y la opción de compartirlo con los jugadores.
- Raid, al estilo de Raid-Helper: los oficiales crean la banda y los jugadores se apuntan con su rol o indican si llegan tarde, son tentativos, van a la banca o faltan. Vista de grupos para repartirlos y aplicarlos en la banda.
- Míticas+: clasificación por puntuación, llaves de quien usa el addon, afijos y tus mejores mazmorras.

### Oficiales
- Warning: inactivos, sin rol declarado, alters sin principal, baja asistencia, titulares inactivos, rangos a revisar, notas públicas y miembros de la lista negra.
- Lista negra con avisos, línea en el tooltip y bloqueo de invitaciones.
- Invitación de nuevos miembros, individual o masiva, con mensaje editable.
- Anuncios periódicos y exportación a CSV para Google Sheets.
