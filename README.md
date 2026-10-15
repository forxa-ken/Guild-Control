# GuildControl

**GuildControl** es un addon modular para World of Warcraft Retail diseñado para la gestión integral de hermandades, control de rosters de raid, seguimiento de miembros, anuncios automáticos y exportación de datos a Google Sheets.

## 🛠️ Arquitectura Modular

- **`Core.lua`**: Inicialización del addon, base de datos de SavedVariables, eventos principales y comandos de chat (`/gct`).
- **`Modules/UI.lua`**: Interfaz de usuario principal, tabla interactiva, ordenación por columnas, filtros en tiempo real, tooltips y panel de vista previa.
- **`Modules/Achievements.lua`**: Lógica de logros de hermandad (categorías, estadísticas, detalle, quién lo completó, apertura en la ventana de Blizzard y refresco por `ACHIEVEMENT_EARNED`).
- **`Modules/Announcements.lua`**: Sistema de configuración de anuncios múltiples periódicos en el canal de la hermandad.
- **`Modules/CSV.lua`**: Exportador e importador de listas masivas, altas del día y bajas en formato CSV compatibles con Google Sheets.
- **`Modules/Professions.lua`**: Módulo aislado para el escaneo y sincronización de profesiones de los miembros.
- **`Modules/GuildChat.lua`**: Historial del chat de hermandad para el panel inferior y saludo automático a quien salude.
- **`Modules/Roster.lua`**: Lógica de los rosters de banda: criterios, integrantes por rol, cobertura de utilidades, armaduras, anuncio, CSV e invitación al grupo.
- **`Modules/Profiles.lua`**: Perfiles de oficial y jugador, y roles que cada jugador declara desde Mi perfil.
- **`Modules/News.lua`**: Datos de la pestaña Resumen: noticias de la hermandad del juego, altas y bajas, próximas bandas, rosters y cifras.
- **`Modules/Blacklist.lua`**: Lista negra: datos, avisos (entrada en la hermandad o en tu grupo, tooltip), bloqueo de invitaciones y compartir con oficiales.
- **`Modules/MythicPlus.lua`**: Míticas+: puntuación de los miembros, llaves de quien usa GuildControl, afijos y mejores mazmorras propias.
- **`Modules/RaidEvents.lua`**: Bandas programadas al estilo de Raid-Helper: inscripciones con rol y estado, grupos y sincronización entre clientes.
- **`Locales/`**: Traducciones. `Locale.lua` crea la tabla `L` (el texto en español es la clave) y elige el idioma; `enUS.lua` es el inglés.

## 📰 Resumen

La pestaña **Resumen** funciona como un tablón de noticias:

- **Noticias de la hermandad**, agrupadas por semana: logros de la hermandad y de los personajes, jefes derrotados, botín y fabricaciones (las noticias oficiales del juego) y bajas de los últimos 30 días. Filtros: **Logros hermandad**, **Logros personajes**, Jefes, Botín, Altas y Bajas. Al pasar el ratón se ve el logro o el objeto, y al hacer clic su detalle en la vista previa; en los logros de personaje indica si tú ya lo has completado. **Clic derecho** en un logro lo abre en la ventana de logros del juego. En el botín muestra el nivel de objeto, el tipo y el **origen** (banda o mazmorra y jefe, si figura en el diario de encuentros). **Shift+clic** en una noticia comparte el objeto o el logro en el chat de hermandad.
- **Altas**: las 5 últimas incorporaciones a la hermandad bajo la cabecera «¡Bienvenidos a la hermandad!».
- **Mensaje del día** de la hermandad.
- **Próximas bandas** creadas en la pestaña Raid.
- **Rosters** con su dificultad, tamaño y titulares.
- **Oficiales**: todos los miembros con rango de oficial (el rango mínimo de Mi perfil o el permiso de chat de oficiales del juego), con su rango; conectados en verde.

## 🏆 Panel de logros

- Arriba puedes cambiar entre los logros de la **Hermandad** y los de tu **Personaje**.
- Pasa el ratón sobre un logro para ver su descripción, puntos, recompensa, fecha y quién lo completó.
- Clic izquierdo: muestra el detalle en el panel de vista previa (estado, fecha, completado por, participantes y criterios).
- Clic derecho o Shift+clic: abre el logro en la ventana de logros de Blizzard.
- **Logros de temporada**: muestra, de todas las categorías, los logros cuyo nombre o descripción menciona una temporada y los de eventos del mundo.

## ⚙️ Configuración

La pestaña **Configuración** está dividida en tres secciones: **Hermandad** (nombre, Discord e icono), **Ventana** (siempre por encima e idioma) y **Saludo automático** (mensaje, tiempos y palabras).

El encabezado muestra debajo del nombre el reino de la hermandad y la facción. Si configuras un **enlace de Discord**, aparece un botón junto al nombre que abre una ventanita con el enlace seleccionado para copiarlo con Ctrl+C.


- **Nombre de la hermandad**: escribe el nombre que quieres mostrar. Si lo dejas vacío (o pulsas "Usar nombre del juego") se usa el nombre real de la hermandad.
- **Icono**: elige uno de los iconos predefinidos o escribe el nombre del icono (por ejemplo `INV_Misc_QuestionMark`), su ID numérico o la ruta completa.
- **Saludo automático**: si está activado, cuando alguien de la hermandad saluda (hola, buenas, saludos...) y **acaba de conectarse** (por defecto, en los 5 minutos siguientes) sin que nadie le haya saludado todavía, el addon responde con el mensaje configurado tras 2-6 s. `{nombre}` se sustituye por su nombre. Los segundos de espera, los minutos sin repetir saludo, los minutos tras conectarse y las **palabras de saludo** se configuran en la columna derecha. A quien ya estaba conectado cuando entraste no se le saluda. Si varios miembros usan GuildControl, solo responde uno.
- **Siempre por encima**: muestra la ventana del addon por encima de las barras de acción y otros botones del juego.
- **Idioma**: Automático (el del juego), Español o English. El cambio se aplica al recargar la interfaz (botón **Recargar** o `/reload`).

## 👥 Miembros y chat

- Clic derecho sobre un miembro: menú para **susurrar** o **invitar al grupo**.
- **Actualizar** (junto a Sheets / CSV) vuelve a pedir la lista de la hermandad al servidor. Si al abrir la ventana la lista está vacía, se pide sola.
 y ordena haciendo clic en las cabeceras. La columna **Tipo** indica si es su personaje **Main** o un **Alter**, y **Enfoque** el que declaró (PvE, PvP o Social). Las profesiones, el roster, el tipo y el enfoque se ven vacíos si no hay dato. Al entrar en Miembros aparecen primero los conectados.
- Al seleccionar un miembro, la vista previa muestra sus profesiones por expansión (solo las tuyas y las de quien use GuildControl; abre cada profesión una vez para que se registren todas).
- Debajo de la ventana está el **chat de hermandad**, con campo para escribir. El botón Contraer/Expandir lo pliega y muestra los mensajes nuevos. Haz clic en el nombre de alguien para abrir una pestaña solo con su conversación (clic derecho en la pestaña la cierra).
- En el panel CSV el texto aparece siempre seleccionado: pulsa Ctrl+C para copiarlo.

## 🛡️ Roster de banda

La pestaña **Roster** sirve para montar las composiciones de banda:

- **Arriba**: selector de roster, nombre editable (Enter para guardar), botón **Banda** para elegir una banda del diario de encuentros del juego (el roster toma su nombre) y botones **Nuevo**, **Duplicar** y **Eliminar** (pide un segundo clic).
- **Criterios**: dificultad (Normal, Heroica o Mítica), tamaño de 10 a 25 (Mítica siempre 20), y número de tanques y sanadores; los DPS son el resto. Los contadores se ponen en verde al completarse.
- **Candidatos** (izquierda): miembros agrupados por rol (con su icono; quien no tiene rol definido va a "Sin rol definido") con el color de su clase, buscador y filtros de conectados y nivel máximo. Clic para añadirlo al roster en su rol; clic derecho para cambiarle el rol o añadirlo como suplente. **Añadirme** te añade a ti. Colocar a alguien sin rol como tanque, sanador o DPS le define ese rol.
- **Composición** (centro): columnas de Tanques, Sanadores y DPS, y la banca de suplentes. Clic sobre un integrante para moverlo o quitarlo.
- **Vista previa** (derecha): cobertura de utilidades de banda (ansia de sangre, resurrección en combate, beneficios de clase), reparto de armaduras de los titulares y media de asistencia en las bandas de Raid asociadas al roster.
- **Acciones**: invitar al grupo a los titulares conectados (con más de 4 se convierte en banda), anunciar el roster en el chat de hermandad (en una ventana donde puedes editar el anuncio antes de enviarlo), exportarlo a CSV y vaciarlo.

La columna Roster de Miembros muestra en qué rosters está cada uno.
La vista previa y el tooltip de cada integrante muestran su asistencia (de las bandas de Raid asociadas al roster), y el CSV del roster la incluye.
- **Mensaje**: abre una ventana con un mensaje editable para los integrantes del roster. Elige la banda (de las creadas en Raid, primero las asociadas al roster) y si incluyes a los suplentes, y envíalo a la hermandad o como **susurro personalizado a cada integrante conectado**. Variables: `{roster}`, `{jefe}`, `{dificultad}`, `{fecha}`, `{hora}`, `{nota}`, `{hermandad}` y, al susurrar, `{nombre}` y `{rol}`.
- **Compartir**: envía el roster completo a quien use GuildControl en la hermandad. Al recibirlo aparece el botón **Recibidos** en la barra de criterios para **actualizar** el roster enlazado, **importarlo como nuevo** o **descartarlo**. Nada se importa sin confirmación.

## 👤 Mi perfil y perfiles de oficial y jugador

- La pestaña **Mi perfil** (debajo de Logros) permite a cada jugador declarar su **rol principal**, un **rol secundario**, su **especialización** (elegida entre las de su clase, con icono; al elegirla se ajusta el rol principal), una **especialización off** (solo si tiene equipo para ella; se ve en la vista previa de Miembros), si es su **personaje principal o un alter** (y de quién), su **enfoque** (PvE, PvP o Social) y una **nota para los oficiales**. Al pulsar **Guardar y enviar** se envía a los miembros que usan GuildControl.
- Los oficiales ven el rol declarado en la vista previa de Miembros y en los candidatos del roster. Si un oficial no ha fijado el rol a mano, el rol de la ficha pasa a ser el declarado; si lo fijó, prevalece el del oficial (clic derecho en el candidato > **Usar rol declarado** para volver a él).
- **Perfil de oficial**: rango igual o superior al configurado en Mi perfil (por defecto el rango 1) o permiso de chat de oficiales del juego. Ve todas las pestañas.
- **Perfil de jugador**: ve Resumen, Miembros, Logros, Mi perfil, **Mis rosters** y Configuración. En lugar de la barra de anuncios ve su rango, su rol y sus rosters.
- **Cuándo llega el rol a los oficiales**: los mensajes del addon solo llegan a quien está conectado en ese momento. Si el oficial no lo está, lo recibe más tarde: al entrar pide los roles y le responde el propio jugador (si está conectado) u otro miembro con GuildControl que ya los tenga guardados. Los personajes de la misma cuenta lo ven al instante porque comparten datos.
- En **Miembros**, la columna Rol muestra el rol de cada uno: icono y nombre, en cian si lo declaró el propio jugador, en blanco si lo fijó un oficial y en naranja con `*` si el oficial puso uno distinto al declarado. Si nadie lo ha definido, queda vacía.
- **Mis rosters** (solo jugadores): muestra los rosters que publican los oficiales con **Compartir**, en solo lectura y con el jefe seleccionable. Resalta tu nombre e indica tu puesto, las próximas bandas de Raid asociadas al roster con tu respuesta y tu porcentaje de asistencia. Al entrar se piden a los oficiales conectados (también con **Actualizar**); si un oficial elimina un roster publicado, desaparece.
- El perfil solo cambia lo que se ve: los datos de cada cliente son locales y nadie puede modificar los de otro.

## ⚠️ Warning

La pestaña **Warning** (oficiales) agrupa los avisos por categorías, cada una con su recuento y sus ajustes:

- **Inactivos**: sin conectarse desde hace 14 días a 1 año (con o sin alters). Clic derecho para expulsar, con confirmación.
- **Sin rol declarado**: miembros activos que no han rellenado Mi perfil; **Recordar a los conectados** les envía un susurro.
- **Alters sin principal**: se declaran alter de alguien que no está en la hermandad.
- **Baja asistencia**: titulares de roster por debajo del porcentaje elegido (70 % por defecto, con al menos 3 bandas con lista pasada en Raid).
- **Titulares inactivos**: titulares de roster que llevan días sin conectarse.
- **Rangos a revisar**: nivel bajo en un rango de raider o superior, y reclutas que llevan tiempo en la hermandad (posible ascenso).
- **Nota pública**: vacía o sin el texto obligatorio que configures.
- **Lista negra**: miembros de la hermandad que figuran en ella.

Cada lista se puede exportar a CSV y tiene clic derecho para susurrar o invitar al grupo. La caja **Warnings** del encabezado suma inactivos y lista negra.

## 🛠️ Profesiones

La pestaña **Profesiones** lista cada profesión con cuántos miembros la tienen. Al elegir una se ven sus miembros con su nivel de habilidad, su otra profesión y si están conectados; se puede ordenar por columnas, buscar y filtrar por conectados. Clic en un miembro para susurrarle o invitarlo al grupo.

## ⚔️ Raid

La pestaña **Raid** (debajo de Roster) funciona como Raid-Helper. El **Roster** es la lista de personas con las que se cuenta; en **Raid** se apuntan quienes quieren ir a cada banda.

- **Planning raid**: los oficiales crean la banda con **Nueva** (título, banda del diario de encuentros, dificultad, tamaño, fecha, hora, descripción y roster asociado) y se publica en la hermandad. Cada jugador responde con **Tanque**, **Sanador** o **DPS** (con su especialización actual), o **Tarde**, **Tentativo**, **Banca** o **Ausente**, y una nota. Se ven los apuntados por rol con el color de su clase y los recuentos. Los oficiales pueden editar, eliminar, **invitar a los apuntados**, **recordar al roster** (susurro a quien no ha respondido) y publicar de nuevo.
- **Asistencia** (oficiales): lista de las bandas próximas y de los últimos 14 días. Para la banda elegida aparecen los inscritos y los integrantes del roster asociado con su respuesta; márcalos como Presente, Tarde, Ausente o Justificada (un segundo clic quita la marca). **Tomar del grupo actual** marca presentes a los del grupo, justificados a quienes avisaron de que faltaban y ausentes al resto; **Apuntados presentes** marca a los apuntados. La asistencia se guarda aparte (no se pierde cuando se borra la banda), se envía sola a la hermandad y cuenta en el Roster, Mis rosters y Warning. Las justificadas no cuentan para el porcentaje.
- Al entrar en el juego se piden las bandas a los oficiales conectados y cada uno reenvía sus inscripciones, así nadie se pierde aunque no coincidan conectados.

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

1. Marca los roles y actividades que buscáis, el horario y un texto final, y pulsa **Generar mensaje**.
2. Retoca el mensaje a mano si quieres; el contador avisa si pasa de 255 caracteres. `{nombre}` se sustituye por el nombre del jugador al susurrar.
3. Escribe el nombre del jugador (o pulsa **Usar objetivo**) y elige **Susurrar mensaje**, **Invitar a la hermandad** o **Susurrar e invitar**. **Abrir en el chat** coloca el mensaje en tu caja de chat para publicarlo en el canal que quieras.

Invitar a la hermandad requiere que tu rango tenga ese permiso.

**Invitación masiva** (botón arriba a la derecha de la pestaña Invitar):

1. Llena la cola pegando nombres (uno por línea o separados por comas) o buscando con /who por rango de nivel y filtro extra (clase, zona...). De la búsqueda solo se añaden jugadores sin hermandad.
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

Todos los comandos funcionan también con el alias `/gctc` (por ejemplo, `/gctc csv`).
