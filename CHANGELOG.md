# GuildControl

## Próxima versión

### Novedades de esta tanda
- Pestaña **Favoritos**: gestión de favoritos (susurrar, invitar, quitar, añadir por nombre) y contenedores separados con los amigos de Battle.net (Real ID) y los amigos BattleTag.
- Roster: cada rol (tanques, sanadores, DPS y suplentes) se dibuja como un contenedor de su color. Se quita **Añadirme**.
- Raid: botón **Ver roster** con los integrantes del roster asociado y su respuesta.
- Rendimiento: menos memoria y sin picos de FPS. Las profesiones y las puntuaciones de Míticas+ de toda la hermandad se recorren como mucho una vez por minuto, el índice de logros del Resumen se construye poco a poco y las noticias del juego se guardan en caché.
- **Favoritos**: clic derecho en un miembro para añadirlo; aviso en el chat, en pantalla y con sonido cuando se conecta, y filtro Favoritos en Miembros.
- **Cambiar rango** desde la vista previa de un miembro (con confirmación y según los permisos de tu rango).
- Los **rosters se sincronizan en tiempo real** entre clientes, como las bandas de Raid: sin importar a mano y borrándose en todos.
- Resumen: los filtros sin noticias no se muestran y **Jefes** incluye los de mazmorra y de banda que derrota la hermandad (registrados por el addon).
- La caja **Warnings** del encabezado solo la ven los oficiales y con un clic abre Warning.

### Raid y Roster
- La asistencia pasa a la pestaña Raid, en el nuevo modo **Asistencia** (oficiales): se pasa lista de cada banda con sus inscritos y el roster asociado, se envía sola a la hermandad y se guarda aunque la banda se borre. La que ya había en el Roster se conserva.
- Se quita la vista Fechas del Roster. Las próximas bandas del Resumen, de Mis rosters y del mensaje del roster salen de las bandas de Raid.
- La categoría Baja asistencia de Warning cuenta las bandas de Raid.

### Resumen y logros
- Filtros separados para **Logros hermandad** y **Logros personajes**.
- La vista previa de un logro de personaje indica si ya lo has completado.
- Clic derecho en un logro lo abre en la ventana de logros del juego, en ese logro (antes solo abría la ventana).
- Se quita el botón «Ir al logro en Logros».
- **Altas** muestra las 5 últimas incorporaciones bajo una cabecera de bienvenida.
- El recuento de logros de hermandad completados ya no se queda corto cuando la interfaz de logros del juego no está cargada.

### Miembros y Míticas+
- Botón **Actualizar** en Miembros. Si al abrir la ventana la lista está vacía, se pide sola.
- Las llaves se guardan aunque el jugador aún no figure en la lista, se piden al abrir Míticas+ y caducan con el reinicio semanal.

### Idiomas
- El addon está disponible en inglés y en español. Por defecto usa el idioma del juego (español para clientes esES y esMX, inglés para el resto) y se puede elegir en Configuración > Ventana > Idioma (se aplica al recargar).
- Sistema de traducciones en `Locales/` preparado para añadir más idiomas copiando `enUS.lua`.
- Las variables de los mensajes también se pueden escribir en inglés: `{name}`, `{guild}`, `{date}`, `{time}`, `{difficulty}`, `{boss}`, `{note}` y `{role}`.
- `/gct leaves` funciona igual que `/gct bajas`.

### Correcciones
- Al conectar, si la lista de la hermandad llegaba vacía, el addon daba de baja a todos los miembros y luego los volvía a dar de alta, con lo que se perdían datos como las llaves. Ahora espera a que llegue la lista completa.
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
