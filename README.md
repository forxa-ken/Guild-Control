# GuildControl

**GuildControl** es un addon modular para World of Warcraft Retail para la gestión integral de hermandades: bandas con inscripciones al estilo Raid-Helper, roster y asistencia sincronizados entre clientes, miembros y favoritos, Míticas+, profesiones, logros, avisos, lista negra, anuncios automáticos y exportación a Google Sheets. Interfaz en español e inglés.

## 🛠️ Arquitectura Modular

- **`Core.lua`**: Inicialización del addon, base de datos de SavedVariables, eventos principales y comandos de chat (`/gct`).
- **`Modules/UI.lua`**: Interfaz de usuario principal, tabla interactiva, ordenación por columnas, filtros en tiempo real, tooltips y panel de vista previa.
- **`Modules/Achievements.lua`**: Lógica de logros de hermandad (categorías, estadísticas, detalle, quién lo completó, apertura en la ventana de Blizzard y refresco por `ACHIEVEMENT_EARNED`).
- **`Modules/Announcements.lua`**: Sistema de configuración de anuncios múltiples periódicos en el canal de la hermandad.
- **`Modules/CSV.lua`**: Exportador e importador de listas masivas, altas del día y bajas en formato CSV compatibles con Google Sheets.
- **`Modules/Professions.lua`**: Módulo aislado para el escaneo y sincronización de profesiones de los miembros.
- **`Modules/GuildChat.lua`**: Historial del chat de hermandad para el panel inferior y saludo automático a quien salude.
- **`Modules/Favorites.lua`**: Personajes favoritos y aviso cuando se conectan.
- **`Modules/GuildConfig.lua`**: Discord e icono de la hermandad que definen los oficiales y se comparten con todos.
- **`Modules/Loot.lua`**: Reparto de botín con el sistema +1 o DKP: tiradas y subastas desde el addon, +1 e historial.
- **`Modules/Dkp.lua`**: DKP: saldos, antigüedad desde Mi perfil, decay semanal, DKP por jefe, banda y antigüedad, y sincronización desde los oficiales.
- **`Modules/Personal.lua`**: Para mí: avisos personales, lista de deseos, historial de DKP, recordatorios de banda, insignias y récords.
- **`Modules/Community.lua`**: recetas compartidas de los artesanos y pedidos (en Profesiones).
- **`Modules/RaidTools.lua`**: Herramientas de banda: comprobación de listos, cuenta atrás de pull, marcas en el objetivo y buff check (buffos, frascos, comida, runas y pociones).
- **`Modules/Roster.lua`**: Lógica de los rosters de banda: criterios, integrantes por rol, cobertura de utilidades, armaduras, anuncio, CSV e invitación al grupo.
- **`Modules/Profiles.lua`**: Perfiles de oficial y jugador, y roles que cada jugador declara desde Mi perfil.
- **`Modules/News.lua`**: Datos de la pestaña Resumen: noticias de la hermandad del juego, altas y bajas, próximas bandas, rosters y cifras.
- **`Modules/Blacklist.lua`**: Lista negra: datos, avisos (entrada en la hermandad o en tu grupo, tooltip), bloqueo de invitaciones y compartir con oficiales.
- **`Modules/MythicPlus.lua`**: Míticas+: puntuación de los miembros, llaves de quien usa GuildControl, afijos y mejores mazmorras propias.
- **`Modules/RaidEvents.lua`**: Bandas programadas al estilo de Raid-Helper: inscripciones con rol y estado, grupos y sincronización entre clientes.
- **`Locales/`**: Traducciones. `Locale.lua` crea la tabla `L` (el texto en español es la clave) y elige el idioma; `enUS.lua` es el inglés.

## 🧭 Menú lateral

Resumen va siempre arriba, con **Expandir todo** / **Contraer todo** debajo. El resto de pestañas está en grupos plegables con fondo negro (clic en el grupo para abrirlo o cerrarlo; puede haber varios abiertos, se recuerdan y se abre solo el de la pestaña en la que estás): **General** (Miembros, Favoritos, Logros), **Banda** (Raid, Roster, Botín), **Comunidad** (Profesiones, Míticas+), **Personal** (Mi perfil, Mi diario) y **Gestión** (Warning, Invitar, Black list; solo lo que tu perfil puede ver). Configuración sigue abajo.

## 📰 Resumen

La pestaña **Resumen** es lo primero que se ve al abrir el addon. Arriba, una fila de cajas (cada línea lleva con un clic a su pestaña o filtro):

- **Para ti**: tu próxima banda y tu respuesta, aviso si no has declarado tu rol, tu llave y tus Míticas+ de esta semana (aviso si aún no has hecho ninguna) y tu asistencia en los rosters en los que estás (en rojo si baja del umbral de Warning). Si no hay bandas próximas, un resumen de tu personaje: clase, nivel y especialización, tu rol, tu rango y tus DKP o +1.
- **Ahora en la hermandad**: conectados (y cuántos sin rol), qué roles hay conectados («1 Tanque | 0 Sanadores | 3 DPS»), favoritos conectados y quién está en una mazmorra o banda de la expansión actual.
- **Esta semana** (desde el reinicio semanal): jefes derrotados (con calavera), logros de la hermandad y de personajes, altas y bajas como insignias de color (+ en verde, - en rojo) y la mejor llave de la hermandad (de quien usa GuildControl).
- **Pendiente** (solo oficiales): recuentos de Warning por categoría (abre esa categoría) y las bandas de los próximos 7 días con los roles que faltan.

Si lo que hay en una caja (también Mensaje del día, Próximas bandas y Oficiales) no cabe, sale una barra de desplazamiento (o usa la rueda del ratón).

Debajo, el tablón con su barra de botones (todos del mismo ancho y con tooltip): **Noticias**, **Récords**, **Normas** y **Actualizar**. **Récords** muestra los récords de la hermandad (puntos de logro, puntuación de Míticas+, bandas asistidas, objetos ganados, DKP y la mejor llave de la semana). **Normas** muestra las normas de la hermandad en su propio recuadro. Las noticias:

- **Noticias de la hermandad**, agrupadas por semana: logros de la hermandad y de los personajes, jefes derrotados, botín y fabricaciones (las noticias oficiales del juego) y bajas de los últimos 30 días. Filtros: **Logros hermandad**, **Logros personajes**, Jefes, Botín, Altas y Bajas; solo se ven los que tienen noticias (Altas, si hay alguna alta guardada). **Jefes** incluye, además de las noticias del juego, los jefes de banda y de mazmorra que derrota quien usa GuildControl con al menos otro miembro de la hermandad en el grupo (se comparten entre clientes y se guardan 30 días). Al pasar el ratón se ve el logro o el objeto, y al hacer clic su detalle en la vista previa; en los logros de personaje indica si tú ya lo has completado. **Clic derecho** en un logro lo abre en la ventana de logros del juego. En el botín muestra el nivel de objeto, el tipo y el **origen** (banda o mazmorra y jefe, si figura en el diario de encuentros). **Shift+clic** en una noticia comparte el objeto o el logro en el chat de hermandad. Los logros que el chat de hermandad anuncia ("X ha ganado el logro...") también entran, aunque las noticias del juego no los traigan.
- **Altas**: las 5 últimas incorporaciones a la hermandad bajo el banner «¡Bienvenidos a la hermandad!» (con el icono de la hermandad y las altas de los últimos 30 días); cada una con el icono de su clase y la fila del color de su clase.
- **Normas de la hermandad**: se ven en la subpestaña **Normas**. Las escriben los oficiales en Configuración > subpestaña **Normas de la hermandad** (hasta 1500 bytes, con botones para insertar iconos de banda y **viñetas** y una **Vista previa**; los iconos se ven como en el chat) y se comparten con la hermandad; al cambiar, los demás reciben un aviso.
- **Mensaje del día** de la hermandad.
- **Próximas bandas** creadas en la pestaña Raid.
- **Oficiales**: todos los miembros con rango de oficial (el rango mínimo de Mi perfil o el permiso de chat de oficiales del juego), con su rango; conectados en verde.

## 🏆 Panel de logros

- Arriba puedes cambiar entre los logros de la **Hermandad** y los de tu **Personaje**.
- Pasa el ratón sobre un logro para ver su descripción, puntos, recompensa, fecha y quién lo completó.
- Clic izquierdo: muestra el detalle en el panel de vista previa (estado, fecha, completado por, participantes y criterios).
- Clic derecho o Shift+clic: abre el logro en la ventana de logros de Blizzard.
- **Logros de temporada**: muestra, de todas las categorías, los logros cuyo nombre o descripción menciona una temporada y los de eventos del mundo.

## ⚙️ Configuración

La pestaña **Configuración** (con desplazamiento) tiene dos subpestañas para oficiales: **General** y **Normas de la hermandad**. General tiene las secciones **Hermandad** (Discord e icono), **Ventana** (siempre por encima, idioma, cerrar al entrar en combate y ocultar el botón del minimapa), **Saludo automático** (mensaje, tiempos y palabras), **Bienvenida a nuevos miembros**, **Canales de reclutamiento** y **Aviso de favoritos**.

El encabezado muestra el nombre de la hermandad del juego y, debajo, su reino y la facción. Junto al nombre está siempre el botón **Discord**: si los oficiales han puesto el enlace, abre una ventanita con él seleccionado para copiarlo con Ctrl+C; si no, a un oficial le lleva a Configuración > Hermandad para ponerlo y a un jugador le sale en gris. Junto al autor, el botón **Donar** muestra el enlace para apoyar el desarrollo del addon. El botón **Más addons** muestra el perfil de CurseForge del autor para descargar sus otros addons.


- **Discord e icono de la hermandad** (solo oficiales; los jugadores ven lo que definen): el Discord y el icono se envían a todos los que usan GuildControl. El icono puede ser el **emblema de la hermandad del juego**, cualquiera de los **iconos del juego** (selector con todos ellos), uno de los iconos rápidos o una **imagen propia** (archivo TGA o BLP en `Interface\AddOns\GuildControl\Media\`; cada jugador necesita el archivo para verla). El nombre de la hermandad ya no se puede cambiar: siempre es el del juego.
- **Saludo automático**: si está activado, cuando alguien de la hermandad saluda (hola, buenas, saludos...) y **acaba de conectarse** (por defecto, en los 5 minutos siguientes) sin que nadie le haya saludado todavía, el addon responde con el mensaje configurado tras 2-6 s. `{nombre}` se sustituye por su nombre. Los segundos de espera, los minutos sin repetir saludo, los minutos tras conectarse y las **palabras de saludo** se configuran en la columna derecha. A quien ya estaba conectado cuando entraste no se le saluda. Si varios miembros usan GuildControl, solo responde uno.
- **Siempre por encima**: muestra la ventana del addon por encima de las barras de acción y otros botones del juego.
- **Cerrar al entrar en combate**: cierra la ventana del addon en cuanto entras en combate.
- **Ocultar el botón del minimapa**: lo quita del minimapa; el addon se abre con `/gct`.
- **Bienvenida a nuevos miembros**: si está activada, cuando el juego avisa de que alguien se ha unido a la hermandad se le da la bienvenida en el chat de hermandad con el mensaje configurado (`{nombre}`, `{hermandad}`). A esa persona no se le aplica el saludo automático. Si varios usan GuildControl, solo responde uno, y no se envía si alguien le escribe antes mencionándolo.
- **Canales de reclutamiento**: el nombre con el que empiezan en tu chat los canales General, Comercio y Mundo (para Invitar > Publicar en).
- **Aviso de favoritos**: activa o desactiva el sonido cuando se conecta un favorito y elige cuál (con **Probar**).
- **Canales del chat**: para cada canal (idioma, Oficiales...), unirse o no, verlo o no en la ventana de chat del juego y mostrar u ocultar su pestaña en GuildControl.
- **Idioma**: Automático (el del juego), Español o English. El cambio se aplica al recargar la interfaz (botón **Recargar** o `/reload`).

## 👥 Miembros y chat

- Clic derecho sobre un miembro: menú para **susurrar** o **invitar al grupo**, y para **añadirlo a favoritos** o quitarlo. El botón **Favoritos** filtra la lista (con estrella junto al nombre) y, cuando un favorito se conecta, se avisa en el chat, en el centro de la pantalla y con un sonido.
- **Actualizar** (junto a Sheets / CSV) vuelve a pedir la lista de la hermandad al servidor. Si al abrir la ventana la lista está vacía, se pide sola.
- Columnas: nivel, clase, nombre, rango, tipo, rol, enfoque, profesiones (solo el nombre; el nivel está en la pestaña Profesiones y en la vista previa), **zona** (la última conocida si está desconectado) y conexión.
- Busca por nombre, clase, rango, rol, profesión, roster o zona y ordena haciendo clic en las cabeceras. La columna **Tipo** indica si es su personaje **Main** o un **Alter**, y **Enfoque** el que declaró (PvE, PvP o Social). Las profesiones, el tipo y el enfoque se ven vacíos si no hay dato. Al entrar en Miembros aparecen primero los conectados.
- **Vista previa de un miembro**: arriba, un bloque con el icono de su clase, el nombre en el color de su clase, nivel, rango y estado (en línea y zona, o su última conexión); debajo, sus insignias como iconos (con tooltip) y una etiqueta por cada banda próxima (que no ha pasado) en cuyo roster está, con el icono y el color de su puesto. Clic en una etiqueta: abre ese roster en Roster (oficiales) o la banda en Raid (jugadores).
- Debajo de la cabecera, sus profesiones por expansión (solo las tuyas y las de quien use GuildControl; abre cada profesión una vez para que se registren todas).
- Debajo de la ventana está el **chat**: hermandad, susurros (recibidos y enviados), banda (con los avisos de banda) y grupo o mazmorra, cada canal con su color. También los canales de idioma **lobosenglish** (pestaña **English**) y **lobosespañol** (pestaña **Español**): entras solo en el del idioma de tu juego y se escribe en ellos desde su pestaña. Se ven en verde, como la hermandad, en el chat del addon y en el del juego. Los oficiales tienen además la pestaña **Oficiales** (el chat de oficiales del juego). En Configuración > Canales del chat eliges, para cada canal, si te unes, si lo ves en la ventana de chat del juego y si sale su pestaña en GuildControl (al ocultarla, sus mensajes tampoco salen en Todo). Los canales se unen por nombre, igual en cualquier idioma del cliente; el número (/5, /6) lo pone cada cliente y puede ser distinto. El historial se guarda (los últimos 500 mensajes, con fecha) y sigue ahí tras `/reload` o al volver a entrar; **Limpiar** lo borra. Pestañas **Todo**, **Hermandad**, **Susurros**, **Banda** y **Grupo** (en Configuración > Canales del chat se puede ocultar cualquiera menos Todo), y una por persona al hacer clic en su nombre (su conversación: lo que escribe, los susurros con ella y lo tuyo que la menciona). Lo que escribes va al canal de la pestaña activa (en la de una persona, por susurro; en Susurros, al último con quien hablaste); a la izquierda se indica el destino. El botón Contraer/Expandir lo pliega y muestra los mensajes nuevos.
- En el panel CSV el texto aparece siempre seleccionado: pulsa Ctrl+C para copiarlo.

## 🙋 Mi diario

La pestaña **Mi diario** (antes «Tus novedades») reúne lo que le interesa a cada jugador:

- **Mi semana** (desde el reinicio semanal): jefes derrotados en las bandas a las que fuiste, DKP ganados y gastados, tus Míticas+ de la semana con la mejor llave, objetos ganados, insignias nuevas y lo que ha caído de tu lista de deseos.
- **Mi lista de deseos** (ahora en Mi perfil > Lista de deseos): los objetos que buscas (Shift+clic en el objeto o pegando un enlace de Wowhead, hasta 40). Cuando caen en la banda te avisa (en pantalla, en el chat y con un sonido), se comparten con la hermandad y en Botín aparece una estrella `*` junto a quien los quiere. A los oficiales les sale además una ventana con el objeto, quién lo quiere (los que no están en la banda, aparte), **Abrir tirada** y **Ver en Botín**.
- **Mis próximas bandas**: con cuenta atrás, tu respuesta y un botón **Apuntarme** (con el rol de Mi perfil). Si estás apuntado, te avisa 15 minutos antes.
- **Mi historial**: tus DKP ganados y gastados línea a línea, los objetos que has ganado y las bandas a las que has ido.
- **Mis insignias**: Veterano, Nunca falta, Asesino de Mítica, Maestro de llaves, Coleccionista, Afortunado, Artesano y Al día. Las que te faltan se ven en gris como objetivo; las de los demás salen en la vista previa de Miembros. Con el sistema DKP, cada insignia da un premio en DKP una sola vez por jugador (se ve junto a la insignia); los oficiales lo configuran en Configuración > Premios DKP por insignia, donde pueden cambiar las cantidades, quitar insignias del premio o restablecer las predeterminadas. Los oficiales también pueden crear **insignias nuevas** (nombre, descripción, icono y premio) en Configuración > Insignias y premios DKP y darlas a mano con **Dar a…** o con clic derecho en Miembros > Insignias.
- **Avisos personales** (se pueden desactivar en Configuración > Ventana): objeto asignado, objeto de tu lista de deseos que cae, banda nueva, banda a punto de empezar, cambios de tu puesto en un roster, de tus DKP y de tu llave.

## 🏆 Récords de la hermandad

- Los **Récords de la hermandad** (puntos de logro, puntuación de Míticas+, bandas asistidas, objetos ganados, DKP y la mejor llave de la semana) están en el Resumen, botón **Récords**. Para buscar grupo se usa el buscador de grupos del juego: GuildControl ya no tiene Buscar grupo en Retail.

## ⭐ Favoritos

La pestaña **Favoritos** (debajo de Miembros) reúne:

- **Favoritos de la hermandad**: conectados primero, con su zona o su última conexión, y botones para **susurrar**, **invitar al grupo** o **quitar**. Se añaden escribiendo el nombre abajo o con clic derecho en Miembros. También se pueden añadir jugadores **de fuera de la hermandad** (Nombre o Nombre-Reino): salen marcados como «[fuera de la hermandad]» y, si están en tu lista de amigos, se ve si están conectados. Cuando uno se conecta, el addon avisa en el chat, en pantalla y con el sonido elegido en Configuración.
- **Amigos BattleTag** (los de Real ID no se muestran): conectados primero, con el personaje y la zona si están en WoW, y botones para susurrar (Battle.net) e invitar al grupo (si están jugando a WoW).

## 🛡️ Roster de banda

La pestaña **Roster** (oficiales) sirve para elegir quién va a cada banda. Cada banda creada en **Raid** tiene su propio roster:

- **Arriba**: el desplegable muestra las bandas programadas en Raid (fecha, hora y título); al elegir una se abre su roster. **Publicar a la hermandad** lo envía a los jugadores, y al lado se ve si está publicado y cuándo. **Eliminar roster** (dos clics) lo borra y lo retira de Mis rosters.
- **Criterios**: el tamaño es el de la banda (se elige al crearla en Raid y aquí no se edita) y el número de tanques y sanadores; los DPS son el resto. Los contadores se ponen en verde al completarse.
- **Candidatos** (izquierda): todos los que se apuntaron en Raid como Tanque, Sanador o DPS y aún no están en el roster (conectados o no), agrupados por el rol con el que se apuntaron. Clic para añadirlo con su rol; clic derecho para cambiarle el rol o mandarlo a la banca.
- **Composición** (centro): un contenedor por rol (Tanques en azul, Sanadores en verde, DPS en rojo). Clic sobre un integrante para moverlo o quitarlo.
- **Abajo**: **Banca** (los que el oficial deja de reserva), **Tarde** (los que avisaron de que llegan tarde; clic para meterlos en el roster) y **Ausentes** (solo informativo).
- **Vista previa** (derecha): cobertura de utilidades de banda, reparto de armaduras de los titulares y asistencia.
- **Acciones**: invitar al grupo a los titulares conectados (con más de 4 se convierte en banda), anunciar el roster en el chat de hermandad, exportarlo a CSV, mensaje a los integrantes, vaciarlo y **Recordar al roster** (susurra a los integrantes conectados que aún no se han apuntado a la banda en Raid; los desconectados lo ven en una ventana al entrar en el juego, junto a la tarea de Mi perfil).
- **En vivo entre oficiales**: cada cambio llega a los demás oficiales a los pocos segundos. Se combina jugador a jugador, así que si dos oficiales lo tocan a la vez no se pisan.
- **Jugadores**: ven el roster en la vista previa de **Raid** (al elegir la banda) cuando un oficial lo publica, tal como estaba en ese momento. Si se cambia después, hay que volver a publicarlo.

La vista previa de Miembros muestra en qué rosters está cada uno, como etiquetas.

## 👤 Mi perfil y perfiles de oficial y jugador

La pestaña **Mi perfil** tiene tres subpestañas: **Perfil**, **Lista de deseos** y **Disponibilidad** (los **días** que puedes jugar con hora de inicio y fin; se envía a la hermandad y los oficiales la ven en la vista previa y el tooltip de Miembros). Perfil se organiza en paneles azules: **Roles**, **Personaje** (principal o alter y enfoque), **Especialización**, **Nota y envío**, y a la derecha **Tu ficha en la hermandad**, **Tu progreso** (tus DKP y tu puesto, o tus +1; tu antigüedad; los objetos que has ganado y tu asistencia, en general y en cada roster); el botón **Mis profesiones** muestra tus profesiones y recetas compartidas al pasar el ratón y abre tu primera profesión (o el libro de profesiones) y, para oficiales, **Oficiales**.

- La pestaña **Mi perfil** (debajo de Logros) permite a cada jugador declarar su **rol principal**, un **rol secundario**, su **especialización** (elegida entre las de su clase, con icono; al elegirla se ajusta el rol principal), una **especialización off** (solo si tiene equipo para ella; se ve en la vista previa de Miembros), si es su **personaje principal o un alter** (y de quién), su **enfoque** (PvE, PvP o Social) y una **nota para los oficiales**. Al pulsar **Guardar y enviar** se envía a los miembros que usan GuildControl. Los roles dependen de la clase: tanque solo guerrero, paladín, druida, caballero de la muerte, monje y cazador de demonios; sanador solo paladín, druida, sacerdote, chamán, monje y evocador; cazador, pícaro, mago y brujo tienen el rol DPS fijo. Raid y el roster de los oficiales tampoco permiten un rol que la clase no puede llevar.
- Los oficiales ven el rol declarado en la vista previa de Miembros y en los candidatos del roster. Si un oficial no ha fijado el rol a mano, el rol de la ficha pasa a ser el declarado; si lo fijó, prevalece el del oficial (clic derecho en el candidato > **Usar rol declarado** para volver a él).
- **Perfil de oficial**: rango igual o superior al configurado en Mi perfil (por defecto el rango 1) o permiso de chat de oficiales del juego. Ve todas las pestañas.
- **Perfil de jugador**: ve Resumen, Miembros, Favoritos, Logros, Profesiones, Míticas+, Mi perfil, Mi diario y Configuración. Si un oficial lo permite (Configuración > Hermandad), también ve **Invitar**. En lugar de la barra de anuncios ve su rango, su rol y sus rosters.
- **Cuándo llega el rol a los oficiales**: los mensajes del addon solo llegan a quien está conectado en ese momento. Si el oficial no lo está, lo recibe más tarde: al entrar pide los roles y le responde el propio jugador (si está conectado) u otro miembro con GuildControl que ya los tenga guardados. Los personajes de la misma cuenta lo ven al instante porque comparten datos.
- En **Miembros**, la columna Rol muestra el rol de cada uno: icono y nombre, en cian si lo declaró el propio jugador, en blanco si lo fijó un oficial y en naranja con `*` si el oficial puso uno distinto al declarado. Si nadie lo ha definido, queda vacía.
- **Mis rosters** (solo jugadores): muestra los rosters que publican los oficiales con **Compartir**, en solo lectura y con el jefe seleccionable. Resalta tu nombre e indica tu puesto, las próximas bandas de Raid asociadas al roster con tu respuesta y tu porcentaje de asistencia. Al entrar se piden a los oficiales conectados (también con **Actualizar**); si un oficial elimina un roster publicado, desaparece.
- El perfil solo cambia lo que se ve: los datos de cada cliente son locales y nadie puede modificar los de otro.

## ⚠️ Warning

La pestaña **Warning** (oficiales) agrupa los avisos por categorías, cada una con su recuento y sus ajustes:

- **Inactivos**: sin conectarse desde hace 14 días a 1 año (con o sin alters). Clic derecho para expulsar, con confirmación.
- **Sin GuildControl** y **Con GuildControl**: quién no usa el addon y quién sí (con su versión y cuándo se detectó), con filtro **Solo conectados** y el botón **Comprobar ahora**, que pregunta a los conectados. Se detecta con cualquier mensaje del addon.
- **Sin rol declarado**: miembros activos que no han rellenado Mi perfil; **Recordar a los conectados** les envía un susurro.
- **Alters sin principal**: se declaran alter de alguien que no está en la hermandad.
- **Baja asistencia**: titulares de roster por debajo del porcentaje elegido (70 % por defecto, con al menos 2 bandas con lista pasada en Raid).
- **Titulares inactivos**: titulares de roster que llevan días sin conectarse.
- **Rangos a revisar**: nivel bajo en un rango de raider o superior, y reclutas que llevan tiempo en la hermandad (posible ascenso).
- **Nota pública**: vacía o sin el texto obligatorio que configures.
- **Lista negra**: miembros de la hermandad que figuran en ella.

Cada lista se puede exportar a CSV y tiene clic derecho para susurrar o invitar al grupo. La caja **Warnings** del encabezado suma inactivos y lista negra; solo la ven los oficiales y al hacer clic abre esta pestaña.

## 🛠️ Profesiones

El botón **Mi profesión** (abajo a la izquierda) abre la ventana de profesiones del juego; si tienes varias, eliges cuál (o el libro de profesiones).

La pestaña **Profesiones** lista cada profesión con cuántos miembros la tienen. La lista muestra las once profesiones principales (las que nadie tiene todavía, en gris con 0) y cada profesión sale una sola vez aunque los demás jueguen en otro idioma. Al elegir una se ven sus miembros en dos contenedores: la profesión que miras (nombre y nivel) y su segunda profesión (profesión y nivel); se puede ordenar por columnas, buscar y filtrar por conectados. Clic en un miembro para susurrarle o invitarlo al grupo.

**Artesanos y pedidos** (botón encima de Mi profesión):

- **¿Quién me lo hace?**: busca una receta escribiendo su nombre o haciendo **Shift+clic en un objeto** (en las bolsas, el chat o un enlace) con el buscador activo o pegando un **enlace de Wowhead** (de objeto o de receta). Te dice qué miembros la conocen, con su nombre y si están conectados. Las recetas las comparte cada jugador con GuildControl al abrir y cerrar su ventana de profesión, y se piden a la hermandad al entrar en el juego y al abrir este panel.
- **Pedir**: encarga la receta a un artesano (eliges a quién si hay varios) con una nota opcional y la casilla **Aporto los materiales**; el artesano ve en el pedido si los aportas o no. Al artesano le llega un aviso.
- **Me piden**: los pedidos que te han hecho. Puedes **Aceptar** o **Rechazar**, y después marcarlo como **Hecho**.
- **Mis pedidos**: los que has hecho tú, con su estado (Pedido, Aceptado, Hecho, Rechazado, Cancelado). Puedes **Cancelar** los abiertos. Te avisa cuando cambian. **Limpiar cerrados** (en cada lista) quita los hechos, rechazados y cancelados.
- Los pedidos se sincronizan entre el artesano y quien pide (también si uno estaba desconectado: se reenvían al entrar). Los cerrados se borran a los 3 días y los abiertos a los 14.

## ⚔️ Raid

La pestaña **Raid** (debajo de Miembros; Botín va justo debajo) funciona como Raid-Helper. El **Roster** es la lista de personas con las que se cuenta; en **Raid** se apuntan quienes quieren ir a cada banda. Los apuntados se ven en tres contenedores de color: **Tanques** (azul), **Sanadores** (verde) y **DPS** (rojo, más ancho y con dos columnas). El botón **Pizarra** del **Ayudante** (o `/gct pizarra`) abre una pizarra para explicar cada jefe: marcas de banda, iconos de rol, textos y dibujo a mano alzada en varios colores, con Deshacer, Limpiar y Borrar (también con clic derecho). Hay una pizarra por jefe de las bandas de la expansión actual (diario de encuentros) y una libre; el líder, un ayudante o un oficial la puede **Enseñar al grupo** y se abre a todos los del grupo con GuildControl. Con **En vivo** el grupo ve cada cambio mientras lo haces y sigue la pizarra si cambias de jefe; mientras dura, ellos no pueden tocarla.

- **Planning raid**: los oficiales crean la banda con **Nueva** (banda del diario de encuentros, que da el título, dificultad, tamaño, fecha, hora, descripción) y se publica en la hermandad. Cada jugador responde con **Tanque**, **Sanador** o **DPS** (con su especialización actual), o **Tarde** o **Ausente**, y una nota. Al elegir una banda, la vista previa muestra su roster publicado. Se ven los apuntados por rol con el color de su clase y los recuentos. Los oficiales pueden editar, eliminar, **invitar a los apuntados** y publicar de nuevo (**Recordar al roster**, el susurro a quien no ha respondido, está en la pestaña Roster; a los desconectados les sale al entrar en la ventana de tareas). Cada botón de Raid explica lo que hace al pasar el ratón.
- **Vista de grupos**: los apuntados se colocan en los 8 grupos de 5 (clic en el jugador y en el hueco; clic derecho para sacarlo), con **Repartir automáticamente**, **Publicar grupos** para que todos los vean y **Aplicar en la banda** para mover a cada uno a su grupo si eres líder o ayudante.
- **Asistencia** (oficiales): lista de las bandas próximas y de los últimos 14 días. Para la banda elegida aparecen los inscritos y los integrantes del roster asociado con su respuesta; márcalos como Presente, Tarde, Ausente o Justificada (un segundo clic quita la marca). **Tomar del grupo actual** marca presentes a los del grupo, justificados a quienes avisaron de que faltaban y ausentes al resto; **Apuntados presentes** marca a los apuntados. La asistencia se guarda aparte (no se pierde cuando se borra la banda), se envía sola a la hermandad y cuenta en el Roster, Mis rosters y Warning. Las justificadas no cuentan para el porcentaje.
- Al entrar en el juego se piden las bandas a los oficiales conectados y cada uno reenvía sus inscripciones, así nadie se pierde aunque no coincidan conectados.
- **Jefes de la banda**: cuando muere un jefe de la banda programada (misma banda del diario y dificultad, desde 1 h antes de la hora hasta 8 h después), el addon lo apunta en esa banda y se comparte al publicarla.
- **Historial** (todos): lista de las bandas ya jugadas, por páginas, con los jefes de la banda (muertos con su hora y los que faltaron) y la asistencia de cada jugador. No se borra a los 14 días como las bandas programadas.
- **Ayudante** (antes «modo minimalista»; botón junto al título de Raid o `/gct ayudante`, también `/gct mini`): cambia la ventana por un panel pequeño para la banda con **Listos** (comprobación de listos), **Pull 10**, **Pull 5**, **Cancelar** (cuenta atrás del juego; en banda hace falta ser líder o ayudante), las **8 marcas** y quitar marca para tu objetivo, **Descanso** (eliges la duración: 3, 5, 10, 15 minutos u Otro…; avisa a la banda al empezar, a falta de 1 minuto y al terminar, muestra arriba de la pantalla una barra con el tiempo que queda (también al grupo con GuildControl; se puede mover y cerrar), y con un descanso en marcha permite cancelarlo), **Buff check** (otro clic lo cierra), **Botín** (abre el botín en una ventana flotante sin salir del Ayudante; si estabas en Botín al abrir el Ayudante, se abre solo), **Pizarra** y **Modo normal**. Lo pueden usar los oficiales, el líder del grupo y, en banda, el líder y los ayudantes; a los demás la pizarra y las tiradas se les abren cuando ellos las abren. Cada botón explica lo que hace al pasar el ratón. Se puede mover y recuerda dónde estaba; si lo dejas activo, vuelve al entrar en el juego. `/gct` también vuelve al modo normal.
- **Buff check** (botón del Ayudante): abre la **ventana de buffos** de la banda sin salir del Ayudante. Cada integrante sale con su grupo, los **buffos de banda** que le faltan (solo los que alguien del grupo puede dar: Intelecto Arcano, Entereza, Grito de batalla, Marca de lo Salvaje, Bendición del bronce y Furia del cielo), **frasco**, **comida** y **runa** (de sus auras) y las **pociones** que lleva. Las pociones y el resto de las bolsas solo se ven de quien usa GuildControl (al pasar el ratón por la fila). En combate o fuera de alcance los buffos no se pueden leer. **Avisar a los que faltan** susurra a cada uno los buffos de banda, el frasco o la comida que le faltan.

## 💰 Botín (+1 o DKP)

La pestaña **Botín** reparte los objetos de banda con el sistema **+1** o con **DKP**. El sistema lo eligen los oficiales en el selector de arriba y llega a toda la hermandad. Tiene cuatro paneles del mismo tamaño (Objetos de la banda, Tirada, Historial de botín y +1 de la hermandad) y, al entrar, la vista previa explica cómo funciona cada uno.

- **Objetos de la banda**: aparecen solos al derrotar a un jefe en grupo (con quién se lo llevó), o se añaden con Shift+clic en un objeto. Los que añade a mano el líder, un ayudante o un oficial los ve todo el grupo con GuildControl (también quien no es de la hermandad, que además ve quién ganó cada objeto); quien entra en el grupo o recarga pide la lista al líder. El sistema (+1, DKP con precio fijo o subasta) lo pone quien abre las tiradas: al abrir una o al cambiarlo, el resto del grupo pasa a usar el mismo mientras siga en ese grupo. El DKP es solo de la hermandad: si en el grupo hay alguien de fuera, el botín se reparte con +1 para todos (y vuelve a DKP cuando ya solo queda gente de la hermandad). **Mostrar** (líder, ayudante u oficial) abre el botín con la lista a todos los del grupo con GuildControl. Al salir botín se abre una sesión, o se crea una con **Nueva sesión** (si la crea el líder, un ayudante o un oficial, el grupo con GuildControl empieza la misma).
- **Tirada**: un oficial, el líder o un ayudante pulsa **Tirar**. A todos los del grupo con GuildControl les aparece una ventanita con **Necesidad (+1)**, **Off-spec** o **Pasar**; el addon lanza el `/roll` y apunta la tirada. Quien no tiene el addon puede escribir `/roll` (cuenta como Necesidad).
- **Ganador**: Necesidad antes que Off-spec; entre Necesidad, el que tiene **menos +1** y, si empatan, la tirada más alta. La lista avisa de quién **ya ganó algo en esta banda**. **Asignar al ganador** (o clic derecho en un jugador para elegir otro) suma **+1** si era Necesidad, lo anuncia en el chat de banda y lo guarda en el **historial**.
- **Botín personal y entrega**: en Retail no hay maestro despojador; el objeto le cae a uno y solo puede comerciarlo durante 2 horas y si no le mejora el equipo. Si quien lo recibe tiene GuildControl, su cliente lo comprueba y la lista marca el objeto como **comerciable** (con el tiempo que queda) o **no comerciable** (no se abre tirada: se lo queda). Al asignarlo a otro, el anuncio le pide al dueño que lo entregue y a él le sale una ventana con **Comerciar**; al completar el comercio queda **entregado** para todo el grupo, y si no, **pendiente de entregar** o **sin entregar** al pasar las 2 horas.
- **+1 de la hermandad**: ranking de +1, compartido con los demás clientes (los oficiales pueden reiniciarlo). El historial muestra fecha, ganador y objeto.

### DKP

- **Cómo se gana**: por cada **jefe** derrotado de una **banda programada en Raid** (de esa banda del diario y su dificultad, desde 1 h antes de la hora hasta 8 h después; a los miembros de la hermandad del grupo; lo da el líder si es oficial o, si no, el primer oficial del grupo), por **banda completada** (botón **DKP de banda** de un oficial, con dos clics) y cada semana por **antigüedad**.
- **Antigüedad**: empieza a contar el día en que el jugador rellena **Mi perfil** con GuildControl. Da DKP cada semana y **desempata** las pujas. Quien no ha rellenado Mi perfil ve al entrar una ventana de **tarea pendiente** que lo lleva a Mi perfil.
- **Decay**: en cada reinicio semanal los DKP pierden un % (10 % por defecto) para evitar la inflación.
- **Precio fijo** (reparto por defecto): cada objeto tiene un precio según su **hueco** y la **dificultad** en la que cayó (botón **Precios**: tabla de 7 tipos de pieza × Normal/Heroica/Mítica, con valores recomendados). Un oficial puede cambiar el de un objeto con **Precio** (o volver al predeterminado). Cada jugador pide **Main-spec** (paga el precio) u **Off-spec** (paga un 50 % si nadie lo pide como Main-spec). Gana quien tenga **más DKP** (a igualdad, más antigüedad). Las piezas de **Mítica** piden un mínimo de **20 DKP** y se puede exigir una **asistencia mínima** (los dos en Ajustes). Solo puede pedir quien tenga los DKP para pagar lo que pide (el precio en Main-spec o lo de Off-spec).
- **Subasta abierta** (se elige en Ajustes; el precio del objeto es la puja mínima): al abrir la subasta de un objeto, a todos los del grupo con GuildControl les sale una ventanita para **pujar** (con una barra deslizante desde la puja mínima hasta sus DKP, o escribiendo la cantidad) o **pasar**. Se ve quién puja y cuánto, y se puede subir la puja. Gana la más alta (a igualdad, más antigüedad) y **paga lo que pujó**. Con DKP solo un oficial asigna el objeto.
- **DKP de la hermandad**: lista de saldos con los días de antigüedad. Clic derecho de un oficial en un jugador para sumar o restar DKP a mano. **Ajustes** (oficiales): reparto (precio fijo o subasta), DKP por jefe, por banda, semanales por antigüedad, decay, puja mínima, % que paga Off-spec, DKP mínimos para Mítica y asistencia mínima.
- Los saldos los llevan los oficiales y se comparten con toda la hermandad (al entrar se pide la última versión).
- Con el sistema **+1** el DKP queda en reposo: no calcula antigüedad, decay ni DKP por jefe hasta que un oficial elige DKP.

## 🗝️ Míticas+

La pestaña **Míticas+** clasifica a los miembros por puntuación M+ (de la lista de la hermandad del juego) e incluye la llave de quien usa GuildControl (no hace falta estar en grupo). Las llaves se piden al entrar en el juego y al abrir la pestaña, se guardan aunque el jugador aún no aparezca en la lista y caducan con el reinicio semanal. A la derecha, los afijos de la semana, tu llave y tu puntuación, y tus mejores mazmorras de la temporada. **Pedir llaves** las solicita a los conectados.

## ⛔ Lista negra

La pestaña **Black list** (oficiales) guarda los personajes no deseados: ninjas, racistas, tóxicos, estafadores...

- Añade el personaje (o usa tu **objetivo**), el motivo y una nota. Clic derecho en una entrada para editarla o quitarla.
- **Avisos**: mensaje y sonido si alguno entra en la hermandad o en tu grupo, línea roja en su tooltip y aviso en la vista previa de Miembros. La caja **Warnings** del encabezado cuenta cuántos están en la hermandad.
- **Nunca se les invita**: la invitación individual y la masiva los saltan.
- **Compartir con oficiales** envía la lista a los oficiales conectados con GuildControl; ellos solo añaden las entradas que no tenían.

## ✉️ Invitar nuevos miembros

La pestaña **Invitar** (debajo de Warning) genera el mensaje de reclutamiento:

1. Marca los roles y actividades que buscáis, los **días** de juego (Lu a Do), el horario y un texto final, y pulsa **Generar mensaje**.
2. Retoca el mensaje a mano si quieres; el contador avisa si pasa de 255 caracteres. `{nombre}` se sustituye por el nombre del jugador al susurrar. La vista previa de la derecha muestra el mensaje completo. **Mensajes guardados** guarda hasta 5 mensajes: al elegir uno se carga en el editor.
3. Escribe el nombre del jugador (o pulsa **Usar objetivo**) y elige **Susurrar mensaje**, **Invitar a la hermandad** o **Susurrar e invitar**. **Abrir en el chat** coloca el mensaje en tu caja de chat para publicarlo en el canal que quieras.
4. **Publicar en**: elige **Gritar** o el canal **General**, **Comercio** o **Mundo** y pulsa **Publicar** para enviar el mensaje allí (tienes que estar en ese canal). Los nombres de los canales se cambian en Configuración. **Avisarme para publicar cada N min** (mínimo 5): cada vez que pasa ese tiempo sale una ventana para publicar el mensaje con un clic (el juego no deja que un addon escriba solo en canales públicos ni grite); **Desactivar** lo apaga.

**Invitar a la hermandad a quien me susurre**: quien te susurra y no es de la hermandad recibe una invitación al momento (salvo la lista negra y quien ya se invitó en los últimos 7 días; si ya tiene hermandad, el juego la rechaza).

Invitar a la hermandad requiere que tu rango tenga ese permiso.

**Invitación masiva** (botón arriba a la derecha de la pestaña Invitar):

1. Llena la cola buscando con /who por rango de nivel y filtro extra (clase, zona...). Solo se añaden jugadores sin hermandad.
2. Edita el susurro que recibe cada jugador. Admite `{nombre}`, `{hermandad}` e iconos de banda.
3. **Invitar siguiente** procesa un jugador; **Invitar lote** procesa 10, uno cada 3 s (**Detener** lo corta). Se omiten los miembros y a quien ya se invitó en los últimos 7 días.

En los dos modos, la fila **Iconos** inserta los iconos de banda (`{rt1}` a `{rt8}`: estrella, círculo, diamante...) en el mensaje y la vista previa los muestra como se verán en el chat. Muchos susurros a desconocidos pueden acabar en denuncias por spam: usa la invitación masiva con moderación.

## 🌐 Idiomas

GuildControl está en **español** e **inglés**. Por defecto usa el idioma del juego: español en clientes esES y esMX, e inglés en el resto. Se puede cambiar en **Configuración > Ventana > Idioma**.

Las variables de los mensajes (`{nombre}`, `{hermandad}`, `{fecha}`, `{hora}`, `{dificultad}`, `{jefe}`, `{nota}`, `{rol}`) también se pueden escribir en inglés: `{name}`, `{guild}`, `{date}`, `{time}`, `{difficulty}`, `{boss}`, `{note}` y `{role}`.

**Añadir otro idioma**: copia `Locales/enUS.lua` con el código del idioma (por ejemplo `frFR.lua`), cambia la llamada `RegisterLocale` del final, traduce los textos de la derecha y añade el archivo a `GuildControl.toc` después de `enUS.lua`. Un texto sin traducir se muestra en español.

## 🚀 Comandos

- `/gct` (o `/gct show`) - Abre o cierra la interfaz principal del addon.
- `/gct csv` - Abre directamente el panel de exportación a Google Sheets / CSV.
- `/gct bajas` (o `/gct leaves`) - Abre el historial de bajas y salidas de la hermandad.
- `/gct recetas` - Diagnóstico de recetas: muestra quién usa el addon y con qué versión, pide las recetas a la hermandad y durante 2 minutos avisa en el chat de cada respuesta.
- `/gct ayudante` (o `/gct mini`) - Abre el Ayudante de banda.
- `/gct pizarra` - Abre la pizarra para explicar un jefe.

Todos los comandos funcionan también con el alias `/gctc` (por ejemplo, `/gctc csv`).
