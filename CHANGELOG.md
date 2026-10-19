# GuildControl

## 5.0.0

- **Primera versión estable** (release) de GuildControl 5 para Retail: reúne todo lo de las betas 1 a 9.
- Se quita **Buscar grupo**: el buscador de grupos del juego ya lo hace mejor (roles, puntuación, llaves y entre reinos). El grupo Comunidad del menú queda con Profesiones y Míticas+; los artesanos, los pedidos y los récords siguen igual. Los anuncios de grupo guardados se borran al entrar.

## 5.0.0-beta9

- **Resumen**: **normas de la hermandad**. Los oficiales las escriben en Configuración > Normas de la hermandad y llegan a todos (aviso al cambiar) y se leen con el botón **Normas** del Resumen. «Ahora en la hermandad» dice cuántos conectados no tienen rol y qué roles hay conectados; «Esta semana» lleva la calavera en los jefes y las altas y bajas como insignias de color; sin bandas próximas, «Para ti» resume tu personaje (clase, nivel, especialización, rol, rango y DKP o +1). Las altas llevan el icono y el color de su clase bajo un banner con el icono de la hermandad.
- **Miembros**: la vista previa tiene una cabecera con el icono y el color de la clase, nivel, rango y estado, las insignias como iconos y una etiqueta por cada banda próxima en cuyo roster está (clic: abre el roster o la banda). La columna Roster desaparece de la lista.
- **Ayudante** (antes «modo minimalista», `/gct ayudante`): botones **Buff check** y **Pizarra**, y cada botón explica lo que hace al pasar el ratón. Raid ya no tiene los botones Buff check y Pizarra, y sus botones llevan tooltip. **Recordar al roster** pasa a la pestaña Roster.
- Corregido: la ventana de lista de deseos de los oficiales salía en blanco la primera vez y no avisaba de lo que caía nada más entrar.
- **Menú lateral por grupos** plegables (General, Banda, Comunidad, Personal y Gestión) con Resumen siempre arriba y **Expandir todo**; se pueden abrir varios a la vez y se recuerdan. Logros va en General y Míticas+ en Comunidad. Comunidad pasa a llamarse **Buscar grupo** y Tus novedades, **Mi diario**.
- **Resumen**: barra con **Noticias**, **Récords** (salen de Buscar grupo), **Normas** y **Actualizar**; las cajas de arriba y de la derecha se desplazan si no cabe todo.
- **Mi perfil**: subpestañas Perfil, **Lista de deseos** (viene de Mi diario) y **Disponibilidad** (días y horas en que puedes jugar, compartida con la hermandad); botón **Mis profesiones** (abre tu profesión) y asistencia por roster.
- **Mi diario**: panel **Mi semana** con jefes, DKP ganados y gastados, tus Míticas+ y mejor llave, objetos, insignias nuevas y deseos caídos. El aviso de un deseo que cae suena.
- **Invitar**: días de juego en el mensaje, 5 mensajes guardados, aviso periódico para publicar con un clic e invitación automática a quien te susurra.
- **Recordar al roster** deja el aviso a los desconectados, que lo ven en la ventana de tareas al entrar.
- Raid: el título de Nueva banda lo da la banda del diario. Ayudante: Buff check se cierra con otro clic.
- Configuración: subpestaña **Normas** con iconos de banda, viñetas y vista previa; cerrar la ventana al entrar en combate; ocultar el botón del minimapa. Canales del chat: solo el del idioma de tu juego, y lobosespañol ya no tiene pestaña propia (sus mensajes salen en Todo).
- Tooltips en los botones de Roster, Botín y Configuración.
- Corregido: los jugadores veían **Publicar de nuevo** en Raid.
- Corregido: los premios DKP de **Asesino de Mítica**, **Maestro de llaves** y **Coleccionista** no se podían añadir ni cambiar (ahora tienen premio predeterminado: 40, 20 y 15), y Asesino de Mítica salía sin icono.

## 5.0.0-beta8

- **Lista de deseos**: cuando cae en la banda un objeto que alguien del grupo tiene en su lista, a los oficiales les sale una ventana flotante con quién lo quiere, **Abrir tirada** y **Ver en Botín**. Los avisos de lista de deseos ya no saltan con objetos antiguos de la sesión al entrar.
- **Precio fijo**: solo puede pedir un objeto quien tenga los DKP para pagarlo (el precio en Main-spec o lo de Off-spec). El botón al que no te llega sale desactivado y en la lista aparece «Sin DKP».
- Corregido: al cancelar o volver a abrir una tirada seguían las pujas y peticiones anteriores.
- Corregido: se aceptaban pujas por encima de los DKP del jugador o por debajo de la mínima.
- Corregido: error al abrir Comunidad (Récords).

## 5.0.0-beta7

- Corregido: la ventana no se abría (ni con `/gct` ni con el icono del minimapa) porque UI.lua pasaba del límite de 200 variables locales de Lua y el juego no lo cargaba.

## 5.0.0-beta6

Mejoras traídas de GuildControl Forever:

- **Roster por banda**: el desplegable del Roster muestra las bandas de Raid y cada una tiene su roster. Candidatos = los apuntados a la banda; abajo Banca, Tarde (se añaden con un clic) y Ausentes. Se quitan el nombre editable, Banda, Nuevo, Duplicar y las variantes. Sincronización en vivo entre oficiales sin pisarse (se combina jugador a jugador) y **Publicar a la hermandad** para los jugadores.
- **Raid**: sin Tentativo ni Banca, sin roster asociado ni Ver roster; la vista previa muestra el roster publicado de la banda. Se quita Mis rosters del menú.
- **Modo minimalista**: nuevo botón **Descanso** (3, 5, 10, 15 min u Otro…, con avisos a la banda) en lugar de Buff check (repetido con Buffos). En la ventana de buffos, **Avisar a los que faltan**.
- **Artesanos y pedidos** (en Profesiones, antes en Comunidad): busca por nombre, con Shift+clic en un objeto o con un enlace de Wowhead, y haz **pedidos** al artesano (aceptar, rechazar, hecho, cancelar; con nota y si aportas los materiales). Las recetas se piden a la hermandad al entrar y al abrir el panel. Nuevo `/gct recetas` para diagnosticarlo.
- **Comunidad**: en Buscar grupo se eligen los roles que se buscan y cada uno se apunta con su rol.
- **Chat**: canales de idioma (lobosenglish y lobosespañol) con sus pestañas, pestaña **Oficiales** (con permiso) y **Configuración > Canales del chat**. Shift+clic en un objeto con la caja del chat activa inserta el enlace.
- **Menú** reordenado (Resumen, Miembros, Raid, Roster, Comunidad, Profesiones, Tus novedades, Mi perfil...); el botón de la pestaña activa se ve gris. **Para mí** se llama ahora **Tus novedades**.
- **Logo** de la hermandad incluido y predeterminado. El enfoque de Mi perfil se aplica al pulsarlo. Amigos BattleTag: se invita con la invitación de Battle.net.
- Corregido: los prefijos «GuildControlCraft» y «GuildControlGreet» tenían 17 caracteres (el juego admite 16) y no se enviaban: las recetas de los demás no llegaban y el saludo y la bienvenida no se coordinaban entre clientes. Ahora son GuildControlCrft y GuildControlGrt. Los trozos de recetas y la lista de deseos se cortan por tamaño (255 bytes).

Segunda tanda desde GuildControl Forever:

- **Pizarra** para explicar un jefe (botón en Raid o `/gct pizarra`): marcas de banda, iconos de rol, textos y dibujo a mano alzada en varios colores, con Deshacer, Limpiar y Borrar. Una pizarra por jefe de las bandas de la expansión actual y una libre. El líder, un ayudante o un oficial la enseña al grupo; con **En vivo**, el grupo ve cada cambio mientras lo haces.
- **Roles por clase**: tanque solo guerrero, paladín, druida, caballero de la muerte, monje y cazador de demonios; sanador solo paladín, druida, sacerdote, chamán, monje y evocador; cazador, pícaro, mago y brujo tienen el rol DPS fijo en Mi perfil. Se respeta en Raid, Buscar grupo y el roster de los oficiales. Al actualizar se corrigen una vez los roles guardados que la clase no puede llevar (los posibles se conservan).
- **Buscar grupo**: **Me apunto** es una solicitud que el autor acepta (invita al momento) o rechaza; cada anuncio muestra los roles que ya hay en el grupo, cuántos se han apuntado, hace cuánto se publicó y si está **Completo**; filtro por actividad y **Anunciar** en la hermandad con los roles buscados. Los anuncios sobreviven al relog, otros los reenvían si el autor está desconectado y caducan si lleva más de 30 minutos fuera.
- **Insignias**: premio en DKP por insignia (una vez por jugador), configurable por los oficiales; insignias nuevas creadas por los oficiales que se dan a mano (Configuración y clic derecho en Miembros > Insignias).
- **Anuncios periódicos comunes a todos los oficiales**: lo que cambia uno lo ven los demás y cada anuncio sale una sola vez.
- **Botín**: ventana flotante desde el modo minimalista (botón Botín) y barra deslizante para pujar. En el menú, Botín va justo debajo de Raid.
- **Profesiones**: las once principales siempre en la lista (las que nadie tiene, en gris); la profesión que miras y la segunda profesión en dos contenedores, sin la columna Conexión; cada profesión una sola vez aunque los demás jueguen en otro idioma.
- **Raid**: los apuntados en contenedores de color por rol (DPS más ancho, a dos columnas).
- **Chat**: se pueden ocultar también las pestañas Hermandad, Susurros, Banda y Grupo; los canales de idioma se ven en verde.
- **Encabezado**: botón Discord siempre visible (sin enlace, un oficial va a Configuración y un jugador lo ve en gris) y logo del addon en el botón del minimapa y en la lista de addons.
- **Configuración** del perfil jugador reordenada. Roster: se quita Anunciar y Mensaje pasa a llamarse Anuncio.
- **Rendimiento**: Miembros no se redibuja mientras está oculta; insignias de la hermandad con caché; cambios de grupo agrupados en la lista negra; los canales General y Comercio se descartan antes de leerlos.
- Corregido: error de Lua al recibir una entrada compartida de la lista negra; la tirada de botín solo enseñaba 4 jugadores; el mensaje del día daba ADDON_ACTION_BLOCKED en combate; la lista secreta de C_Club daba error durante un encuentro.

## 5.0.0-beta5

- **Anuncios**: solo se publican si tienes rango de oficial. Si pierdes el rango, tu cliente deja de enviarlos (se conservan por si lo recuperas).

## 5.0.0-beta4

- **Invitar para jugadores**: un oficial puede permitir en Configuración > Hermandad que los jugadores usen la pestaña Invitar (se aplica a toda la hermandad).
- **Configuración del perfil jugador** reorganizada: Ventana y avisos arriba, canales de reclutamiento solo si pueden invitar, y sin huecos.
- **Rendimiento**: la ventana de buffos solo escucha los eventos de auras mientras está abierta; la llave solo se revisa cuando cambian las bolsas (con 2 s de espera) y si cambió; las noticias se calculan una vez por refresco; Warning y el buscador de recetas no se recalculan con cada mensaje o tecla.
- Nueva pestaña **Para mí**: lista de deseos (con Shift+clic o pegando un enlace de Wowhead) (avisa cuando cae y la ven los oficiales), próximas bandas con cuenta atrás y aviso 15 min antes, historial personal de DKP, objetos y bandas, e insignias.
- Nueva pestaña **Comunidad**: buscar grupo, récords de la hermandad y artesanos (quién conoce cada receta).
- **Avisos personales** en pantalla (objeto asignado, banda nueva, cambios de roster, DKP y llave), desactivables en Configuración.
- **Mi perfil**: panel **Tu progreso** con tus DKP (y tu puesto) o tus +1, tu antigüedad, los objetos ganados y tu asistencia.
- **Configuración**: los jugadores ya no ven la sección Hermandad (Discord e icono).
- **Resumen**: el filtro Bajas lleva la cabecera «¡Abandonan el barco!».
- **Ocupado en un jefe**: si susurras desde el addon a alguien que está con un jefe de mazmorra o banda, te avisa de con qué jefe está.
- **Anuncios**: la cuenta atrás ya no se reinicia con /reload ni al cambiar de personaje.
- **Profesiones**: botón **Mi profesión** que abre la ventana de profesiones del juego.
- La **vista previa** se desplaza cuando el texto no cabe. Explicación del DKP más clara.
- **Warning**: nuevas secciones **Sin GuildControl** y **Con GuildControl** (versión y última detección), con filtro de conectados y botón **Comprobar ahora**.
- **Resumen**: los logros que anuncia el chat de hermandad aparecen aunque las noticias del juego no los traigan.
- Explicación del **DKP** en Botín reescrita, más clara y por pasos.
- Enlace correcto del botón **Más addons**.
- **DKP con precio fijo** (reparto por defecto): tabla de precios por hueco y dificultad, botón Precio para cambiar el de un objeto, Main-spec / Off-spec (50 %), gana quien tenga más DKP, mínimo de 20 DKP para piezas de Mítica y asistencia mínima opcional. La subasta abierta sigue disponible en Ajustes.
- **Favoritos** de fuera de la hermandad (marcados aparte; si son tus amigos se ve si están conectados).
- Ayuda de **Botín** en la vista previa con viñetas, para +1 y para DKP.
- Con el sistema +1, el DKP queda en reposo (no gasta recursos).
- Botón **Más addons** con el perfil de CurseForge del autor.
- **Rendimiento al entrar**: los recorridos de la lista de la hermandad (profesiones y Míticas+) se hacen una sola vez, compartidos, y 20 s después de cargar, para evitar la caída de FPS al iniciar el juego.
- **Jefes de la banda programada**: el addon detecta los jefes que mueren en una banda programada en Raid y los apunta en ella. Los DKP por jefe solo se dan por esos jefes.
- **Historial de bandas** en Raid: bandas anteriores con sus jefes (muertos y pendientes) y la asistencia.
- El botón **Donar** ya tiene enlace: https://paypal.me/Forxaken
- **DKP** en Botín (lo eligen los oficiales): DKP por jefe de banda, por banda completada y semanales por antigüedad; decay semanal del 10 % (configurable); subasta abierta desde el addon (gana la puja más alta, a igualdad más antigüedad, y paga lo que pujó); ajustes y ajuste manual para oficiales.
- La **antigüedad** cuenta desde que cada jugador rellena **Mi perfil**. Quien no lo ha hecho ve una ventana de **tarea pendiente** nada más conectarse.
- Botín explica en la vista previa cómo funciona el sistema elegido (+1 o DKP).
- **Modo minimalista de banda** (Raid o `/gct mini`): panel pequeño con comprobación de listos, pull 10, pull 5, cancelar pull, marcas en el objetivo, buff check, ventana de buffos y vuelta al modo normal.
- **Buff check**: ventana con los integrantes del grupo y sus buffos de banda, frasco, comida, runa y pociones (las pociones, de quien usa GuildControl).
- **Invitar** individual organizado en paneles: qué buscáis, mensaje, enviar a un jugador y publicar en un canal.
- **Botín**: los cuatro paneles tienen el mismo tamaño y la vista previa explica cómo funciona cada uno.
- Configuración: el texto de ayuda de Bienvenida a nuevos miembros ya no se sale de su panel.

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
