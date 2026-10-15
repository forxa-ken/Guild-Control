# GuildControl

## 5.0.0-beta3

### Invitar, configuración y avisos
- Invitar: el mensaje de reclutamiento se puede **gritar** o publicar en el canal **General**, **Comercio** o **Mundo** (nombres configurables). La invitación masiva ya solo busca con /who.
- **Bienvenida a nuevos miembros**: mensaje automático en el chat de hermandad para quien se une (sin el saludo automático habitual).
- Sonido configurable al conectarse un favorito.
- Configuración con desplazamiento y cada sección en un panel con franja de título; los canales de reclutamiento van separados por líneas.
- La invitación masiva se organiza en contenedores: búsqueda /who, cola, susurro e invitar.
- Favoritos ya no muestra los amigos con Real ID, solo los amigos BattleTag.

### Chat
- El chat se guarda: el historial (500 mensajes) sobrevive a `/reload` y a cerrar el juego, y se puede limpiar.
- Ahora incluye susurros, chat de banda (y avisos) y de grupo o mazmorra, con pestañas por canal y por persona. Se escribe en el canal de la pestaña activa.

### Botín
- Nueva pestaña **Botín** con el sistema **+1**: los objetos de la banda aparecen solos, las tiradas se hacen desde el addon (Necesidad, Off-spec o Pasar con su /roll), gana quien tenga menos +1 y luego la tirada más alta, se avisa de quién ya ganó en la banda, y se guardan los +1 y el historial. El DKP queda para más adelante.

### Hermandad y apariencia
- El Discord y el icono de la hermandad los definen los oficiales y llegan a todos; los jugadores ya no pueden cambiarlos.
- El nombre de la hermandad ya no se personaliza: siempre es el del juego.
- Icono: emblema de la hermandad del juego, selector con todos los iconos del juego, más iconos rápidos o una imagen propia.
- Botón **Donar** junto al autor.
- **Mi perfil** reorganizado en paneles, todos en azul.

### Miembros
- Nueva columna **Zona** (también se puede buscar por zona).
- Las profesiones se muestran sin el nivel (está en la pestaña Profesiones y en la vista previa).
- Corregido el texto que se montaba en la barra de arriba.

### Resumen
- Nueva fila de cajas arriba: **Para ti** (tu próxima banda y respuesta, rol sin declarar, asistencia, llave y Míticas+ de la semana), **Ahora en la hermandad** (conectados, favoritos conectados y quién está en mazmorra o banda), **Esta semana** (jefes, logros, altas, bajas y la mejor llave de la hermandad) y, para oficiales, **Pendiente** (Warning por categoría y bandas a las que les faltan roles). Cada línea lleva a su pestaña.
- Se quita la caja Rosters del Resumen (están en Roster y en Mis rosters).
- Cada cliente comparte su mejor Mítica+ de la semana para calcular la mejor llave de la hermandad.
- Los filtros de noticias sin noticias ya no se muestran (tampoco Bajas). Los jefes se registran también con el aviso BOSS_KILL del juego.
- Los botones de filtro se ajustan al texto (en inglés "Char. achievements" se salía del botón).
- Warning avisa de baja asistencia desde 2 bandas con lista pasada (antes 3).

## 5.0.0-beta2

### Favoritos, rosters y noticias
- Pestaña **Favoritos**: gestión de favoritos (susurrar, invitar, quitar, añadir por nombre) y contenedores separados con los amigos de Battle.net (Real ID) y los amigos BattleTag.
- Roster: cada rol (tanques, sanadores, DPS y suplentes) se dibuja como un contenedor de su color. Se quita **Añadirme**.
- Raid: botón **Ver roster** con los integrantes del roster asociado y su respuesta.
- Rendimiento: menos memoria y sin picos de FPS. Las profesiones y las puntuaciones de Míticas+ de toda la hermandad se recorren como mucho una vez por minuto, el índice de logros del Resumen se construye poco a poco y las noticias del juego se guardan en caché.
- **Favoritos**: clic derecho en un miembro para añadirlo; aviso en el chat, en pantalla y con sonido cuando se conecta, y filtro Favoritos en Miembros.
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
