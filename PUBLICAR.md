# Cómo publicar GuildControl en CurseForge

Este archivo no va dentro del addon (lo excluye `.pkgmeta`).

## Cómo funciona

Al subir a GitHub una etiqueta de versión, la Action `.github/workflows/release.yml` usa el empaquetador de BigWigsMods. Ese empaquetador:

1. Crea `GuildControl.zip` sin los archivos de desarrollo (`CLAUDE.md`, `PUBLICAR.md`, `versiones/`, `.github`).
2. Sustituye `@project-version@` del `.toc` por el número de la etiqueta. El addon muestra ese número en el chat y en la ventana.
3. Lo sube a CurseForge con el texto de `CHANGELOG.md`.
4. Crea también una release en GitHub con el mismo `.zip`.

El tipo de publicación sale del nombre de la etiqueta:

| Etiqueta | Tipo en CurseForge |
|---|---|
| `v5.0.0-beta1` | Beta: solo la reciben quienes eligen versiones beta |
| `v5.0.0-alpha1` | Alpha |
| `v5.0.0` | Release: la ven todos |

## Pasos (solo la primera vez)

### 1. Crear el proyecto en CurseForge

1. Entra en https://authors.curseforge.com con tu cuenta de CurseForge (o créala).
2. Pulsa **Create Project** y elige **World of Warcraft** → **Addons**.
3. Rellena:
   - **Name**: GuildControl
   - **Summary**: la frase de la sección "Resumen corto" de abajo.
   - **Description**: el texto de la sección "Descripción" de abajo.
   - **Categories**: Guild (principal), Chat & Communication, Raid Frames o Roleplay según prefieras.
   - **License**: All Rights Reserved.
   - **Logo**: una imagen cuadrada (400×400 o más), por ejemplo el lobo del encabezado.
4. Envía el proyecto. CurseForge lo revisa antes de hacerlo público; suele tardar de unas horas a un par de días.

### 2. Apuntar el ID del proyecto

En la página del proyecto (columna "About Project") aparece el **Project ID**, un número. Añade esta línea a `GuildControl.toc`, debajo de `## SavedVariables`:

```
## X-Curse-Project-ID: 123456
```

(cambiando `123456` por tu número) y haz commit.

### 3. Crear el token de la API

1. En https://authors.curseforge.com → tu cuenta → **API Tokens**, genera un token (por ejemplo "GitHub GuildControl").
2. En GitHub, en el repositorio `forxa-ken/Guild-Control`: **Settings → Secrets and variables → Actions → New repository secret**.
   - Name: `CF_API_KEY`
   - Secret: el token de CurseForge.

## Publicar una versión

1. Actualiza `CHANGELOG.md` con los cambios.
2. Sube los commits y crea la etiqueta:

```bash
git push origin main
git tag v5.0.0-beta1
git push origin v5.0.0-beta1
```

3. En GitHub → pestaña **Actions** puedes seguir el empaquetado. Al terminar, el archivo aparece en CurseForge (las primeras subidas también pasan revisión).

## Antes de la primera beta

- Prueba en el juego con `/console scriptErrors 1` (o BugSack) que no salen errores de Lua al abrir cada pestaña.
- Prueba con dos personajes de la hermandad conectados a la vez lo que se sincroniza: roles declarados, rosters compartidos, bandas e inscripciones, lista negra y llaves.
- Haz capturas de pantalla para la galería del proyecto (Resumen, Miembros, Raid, Míticas+...).

---

## Resumen corto (Summary)

Gestión completa de tu hermandad: bandas con inscripciones al estilo Raid-Helper, roster y asistencia sincronizados, miembros, Míticas+, profesiones, logros, avisos y lista negra. En español e inglés.

## Descripción

**GuildControl** reúne en una sola ventana (`/gct`) todo lo que necesita una hermandad para organizarse. La interfaz está en **español** e **inglés**: sigue el idioma del juego y se puede cambiar en Configuración.

**Para todos los miembros**
- **Resumen**: noticias de la hermandad agrupadas por semana (logros de hermandad y de personajes, jefes de banda y de mazmorra derrotados, botín con su origen y bajas), las últimas incorporaciones, el mensaje del día, las próximas bandas y los oficiales. Clic derecho en un logro para abrirlo en la ventana del juego.
- **Raid**: apúntate a las bandas que programan los oficiales como tanque, sanador o DPS, o indica si llegas tarde, eres tentativo, vas a la banca o faltas. Consulta tu grupo y quién del roster ha respondido.
- **Mi perfil**: indica tu rol, especialización y especialización off, enfoque (PvE, PvP o Social) y si es tu principal o un alter. Los oficiales lo reciben solo.
- **Favoritos**: marca a tus compañeros favoritos y recibe un aviso cuando se conectan. En la misma pestaña, tus amigos de Battle.net y BattleTag para susurrarles o invitarlos al grupo.
- **Míticas+**: clasificación de la hermandad por puntuación, llaves de los compañeros, afijos y tus mejores mazmorras.
- **Profesiones**: quién tiene cada profesión y con qué nivel, para pedirle un encargo.
- **Mis rosters**: los rosters en los que estás, tus próximas bandas y tu porcentaje de asistencia.
- **Chat de hermandad** contraíble, con pestañas por persona.

**Para oficiales**
- **Raid** al estilo Raid-Helper: crea la banda, mira quién se apunta, reparte los grupos y aplícalos en la banda con un clic. Pasa lista en el modo **Asistencia** (también tomándola del grupo actual); se envía sola a los demás oficiales.
- **Ayudante de banda**: un panel pequeño con comprobación de listos, pull 10/5, marcas de banda, descanso con aviso, buff check (buffos, frascos, comida, runas y pociones), el botín en una ventana flotante y la pizarra de jefes.
- **Roster** con contenedores por rol, criterios de composición, cobertura de utilidades por clase y armaduras. Los cambios llegan **al momento** a los demás oficiales, como las bandas.
- **Warning**: inactivos, miembros sin rol, alters sin principal, baja asistencia, titulares inactivos, rangos a revisar, notas públicas y lista negra. Clic en la caja Warnings del encabezado para abrirlo.
- **Lista negra** con avisos al entrar en la hermandad o en tu grupo, marca en el tooltip y bloqueo de invitaciones.
- **Invitación** de nuevos miembros, individual o masiva, con mensajes editables.
- Anuncios periódicos y exportación a CSV para Google Sheets.

Lo que se comparte entre jugadores (roles, rosters, bandas, asistencia, llaves y jefes derrotados) solo llega a quien también tiene GuildControl instalado.

Comandos: `/gct` (o `/gctc`), `/gct ayudante` (ayudante de banda), `/gct pizarra` (pizarra de jefes), `/gct csv`, `/gct bajas`.

Es una **beta**: si encuentras un error, deja un comentario explicando qué estabas haciendo. Un addon como BugSack ayuda a copiar el error completo.

---

## Summary (English)

Complete guild management: Raid-Helper style sign-ups, synced roster and attendance, members, Mythic+, professions, achievements, warnings and blacklist. English and Spanish.

## Description (English)

**GuildControl** brings everything your guild needs to stay organized into a single window (`/gct`). The interface is available in **English** and **Spanish**: it follows your game language and can be changed in Settings.

**For every member**
- **Overview**: guild news grouped by week (guild and character achievements, raid and dungeon bosses defeated, loot with its source and members who left), the latest members to join, the message of the day, upcoming raids and officers. Right-click an achievement to open it in the game's achievement window.
- **Raid**: sign up for the raids your officers schedule as tank, healer or DPS, or mark yourself as late, tentative, bench or absent. Check your group and who from the roster has answered.
- **My profile**: set your role, specialization and off-spec, focus (PvE, PvP or Social) and whether it's your main or an alt. Officers receive it automatically.
- **Favorites**: mark your favorite guildmates and get an alert when they log in. The same tab lists your Battle.net and BattleTag friends so you can whisper them or invite them to your group.
- **Mythic+**: guild ranking by score, guildmates' keystones, affixes and your best dungeons.
- **Professions**: who has each profession and at what skill level, so you can ask for a craft.
- **My rosters**: the rosters you're in, your upcoming raids and your attendance percentage.
- Collapsible **guild chat** with per-person tabs.

**For officers**
- Raid-Helper style **Raid**: create the raid, see who signs up, sort the groups and apply them to your raid with one click. Take attendance in **Attendance** mode (you can take it from your current group); it's sent to the other officers automatically.
- **Roster** with per-role containers, composition targets, class utility coverage and armor types. Changes reach the other officers **instantly**, just like raids.
- **Warnings**: inactive members, members without a role, alts without a main, low attendance, inactive starters, ranks to review, public notes and blacklist. Click the Warnings box in the header to open it.
- **Blacklist** with alerts when someone on it joins the guild or your group, a tooltip mark, and invites to them blocked.
- **Recruitment** of new members, single or mass, with editable messages.
- Recurring announcements and CSV export for Google Sheets.

Shared data (roles, rosters, raids, attendance, keystones and bosses defeated) only reaches players who also have GuildControl installed.

Commands: `/gct` (or `/gctc`), `/gct csv`, `/gct leaves`.

This is a **beta**: if you find a bug, please leave a comment explaining what you were doing. An addon like BugSack helps you copy the full error.
