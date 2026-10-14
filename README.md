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
- **`Modules/Roster.lua`**: Lógica de los rosters de banda: criterios, integrantes por rol, cobertura de utilidades, armaduras, anuncio, CSV e invitación al grupo.
- **`Modules/Profiles.lua`**: Perfiles de oficial y jugador, y roles que cada jugador declara desde Mi perfil.

## 🏆 Panel de logros

- Pasa el ratón sobre un logro para ver su descripción, puntos, recompensa, fecha y quién lo completó.
- Clic izquierdo: muestra el detalle en el panel de vista previa (estado, fecha, completado por, participantes y criterios).
- Clic derecho o Shift+clic: abre el logro en la ventana de logros de Blizzard.
- **Logros de temporada**: muestra, de todas las categorías, los logros cuyo nombre o descripción menciona una temporada y los de eventos del mundo.

## ⚙️ Configuración

En la pestaña **Configuración** puedes personalizar el encabezado del panel:

- **Nombre de la hermandad**: escribe el nombre que quieres mostrar. Si lo dejas vacío (o pulsas "Usar nombre del juego") se usa el nombre real de la hermandad.
- **Icono**: elige uno de los iconos predefinidos o escribe el nombre del icono (por ejemplo `INV_Misc_QuestionMark`), su ID numérico o la ruta completa.
- **Saludo automático**: si está activado, cuando alguien de la hermandad saluda (hola, buenas, saludos...) y **acaba de conectarse** (por defecto, en los 5 minutos siguientes) sin que nadie le haya saludado todavía, el addon responde con el mensaje configurado tras 2-6 s. `{nombre}` se sustituye por su nombre. Los segundos de espera, los minutos sin repetir saludo, los minutos tras conectarse y las **palabras de saludo** se configuran en la columna derecha. A quien ya estaba conectado cuando entraste no se le saluda. Si varios miembros usan GuildControl, solo responde uno.
- **Siempre por encima**: muestra la ventana del addon por encima de las barras de acción y otros botones del juego.

## 👥 Miembros y chat

- Clic derecho sobre un miembro: menú para **susurrar** o **invitar al grupo**.
- Busca por nombre, clase, rango, rol, profesión o roster y ordena haciendo clic en las cabeceras. Al entrar en Miembros aparecen primero los conectados.
- Al seleccionar un miembro, la vista previa muestra sus profesiones por expansión (solo las tuyas y las de quien use GuildControl; abre cada profesión una vez para que se registren todas).
- Debajo de la ventana está el **chat de hermandad**, con campo para escribir. El botón Contraer/Expandir lo pliega y muestra los mensajes nuevos. Haz clic en el nombre de alguien para abrir una pestaña solo con su conversación (clic derecho en la pestaña la cierra).
- En el panel CSV el texto aparece siempre seleccionado: pulsa Ctrl+C para copiarlo.

## 🛡️ Roster de banda

La pestaña **Roster** sirve para montar las composiciones de banda:

- **Arriba**: selector de roster, nombre editable (Enter para guardar), botón **Banda** para elegir una banda del diario de encuentros del juego (el roster toma su nombre) y botones **Nuevo**, **Duplicar** y **Eliminar** (pide un segundo clic).
- **Criterios**: dificultad (Normal, Heroica o Mítica), tamaño de 10 a 25 (Mítica siempre 20), y número de tanques y sanadores; los DPS son el resto. Los contadores se ponen en verde al completarse.
- **Candidatos** (izquierda): miembros agrupados por rol (con su icono; quien no tiene rol definido va a "Sin rol definido") con el color de su clase, buscador y filtros de conectados y nivel máximo. Clic para añadirlo al roster en su rol; clic derecho para cambiarle el rol o añadirlo como suplente. **Añadirme** te añade a ti. Colocar a alguien sin rol como tanque, sanador o DPS le define ese rol.
- **Composición** (centro): columnas de Tanques, Sanadores y DPS, y la banca de suplentes. Clic sobre un integrante para moverlo o quitarlo.
- **Vista previa** (derecha): cobertura de utilidades de banda (ansia de sangre, resurrección en combate, beneficios de clase) y reparto de armaduras de los titulares.
- **Acciones**: invitar al grupo a los titulares conectados (con más de 4 se convierte en banda), anunciar el roster en el chat de hermandad (en una ventana donde puedes editar el anuncio antes de enviarlo), exportarlo a CSV y vaciarlo.

- **Fechas** (botón arriba a la derecha, junto a Composición): añade fechas de banda (DD/MM/AAAA, hora y nota) o impórtalas del calendario del juego. Al seleccionar una fecha aparece la hoja de asistencia con Presente, Tarde, Ausente y Justificada por integrante (un segundo clic quita la marca), los botones **Tomar del grupo actual** (marca presentes a los del grupo y ausentes al resto de titulares), **Titulares presentes** y **Limpiar marcas**, y el historial de asistencia de cada uno. Las justificadas no cuentan para el porcentaje.

La columna Roster de Miembros muestra en qué rosters está cada uno.
La vista previa y el tooltip de cada integrante muestran su asistencia, y el CSV del roster la incluye.
- **Jefes**: encima de la composición, el selector **Base / Jefe** permite crear variantes por jefe (**Añadir jefe**, **Eliminar jefe**). Si el roster tiene banda y el nombre está vacío, **Añadir jefe** ofrece la lista de jefes de esa banda. Cada jefe parte de la base y solo guarda sus cambios: quién entra, quién se queda en la banca y quién cambia de rol. La vista previa muestra quién entra y quién sale respecto a la base, y Invitar, Anunciar y Exportar usan la composición del jefe seleccionado. En un jefe, **Restablecer jefe** vuelve a la base.
- **Mensaje**: abre una ventana con un mensaje editable para los integrantes del roster. Elige la fecha de banda y si incluyes a los suplentes, y envíalo a la hermandad o como **susurro personalizado a cada integrante conectado**. Variables: `{roster}`, `{jefe}`, `{dificultad}`, `{fecha}`, `{hora}`, `{nota}`, `{hermandad}` y, al susurrar, `{nombre}` y `{rol}`.
- **Compartir**: envía el roster completo (base, jefes, fechas y asistencia) a quien use GuildControl en la hermandad. Al recibirlo aparece el botón **Recibidos** en la barra de criterios para **actualizar** el roster enlazado, **importarlo como nuevo** o **descartarlo**. Nada se importa sin confirmación.

## 👤 Mi perfil y perfiles de oficial y jugador

- La pestaña **Mi perfil** (debajo de Logros) permite a cada jugador declarar su **rol principal**, un **rol secundario**, su **especialización**, si es su **personaje principal o un alter** (y de quién) y una **nota para los oficiales**. Al pulsar **Guardar y enviar** se envía a los miembros que usan GuildControl.
- Los oficiales ven el rol declarado en la vista previa de Miembros y en los candidatos del roster. Si un oficial no ha fijado el rol a mano, el rol de la ficha pasa a ser el declarado; si lo fijó, prevalece el del oficial (clic derecho en el candidato > **Usar rol declarado** para volver a él).
- **Perfil de oficial**: rango igual o superior al configurado en Mi perfil (por defecto el rango 1) o permiso de chat de oficiales del juego. Ve todas las pestañas.
- **Perfil de jugador**: ve Resumen, Miembros, Logros, Mi perfil, **Mis rosters** y Configuración. En lugar de la barra de anuncios ve su rango, su rol y sus rosters.
- **Cuándo llega el rol a los oficiales**: los mensajes del addon solo llegan a quien está conectado en ese momento. Si el oficial no lo está, lo recibe más tarde: al entrar pide los roles y le responde el propio jugador (si está conectado) u otro miembro con GuildControl que ya los tenga guardados. Los personajes de la misma cuenta lo ven al instante porque comparten datos.
- En **Miembros**, la columna Rol muestra el rol de cada uno: icono y nombre, en cian si lo declaró el propio jugador, en blanco si lo fijó un oficial y en naranja con `*` si el oficial puso uno distinto al declarado. Si nadie lo ha definido, queda vacía.
- **Mis rosters** (solo jugadores): muestra los rosters que publican los oficiales con **Compartir**, en solo lectura y con el jefe seleccionable. Resalta tu nombre e indica tu puesto, las próximas fechas con tu marca de asistencia y tu porcentaje. Al entrar se piden a los oficiales conectados (también con **Actualizar**); si un oficial elimina un roster publicado, desaparece.
- El perfil solo cambia lo que se ve: los datos de cada cliente son locales y nadie puede modificar los de otro.

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

## 🚀 Comandos

- `/gct` (o `/gct show`) - Abre o cierra la interfaz principal del addon.
- `/gct csv` - Abre directamente el panel de exportación a Google Sheets / CSV.
- `/gct bajas` - Abre el historial de bajas y salidas de la hermandad.

Todos los comandos funcionan también con el alias `/gctc` (por ejemplo, `/gctc csv`).
