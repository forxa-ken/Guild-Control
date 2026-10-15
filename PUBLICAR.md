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

Gestión completa de la hermandad: miembros, roster, bandas con inscripciones al estilo Raid-Helper, logros, profesiones, Míticas+, avisos y lista negra.

## Descripción

**GuildControl** reúne en una sola ventana (`/gct`) todo lo que necesita una hermandad para organizarse. Interfaz en español.

**Para todos los miembros**
- **Resumen**: noticias de la hermandad (logros, jefes derrotados, botín con su origen, altas y bajas), mensaje del día, próximas bandas y oficiales.
- **Mi perfil**: indica tu rol, especialización y especialización off, enfoque (PvE, PvP o Social) y si es tu principal o un alter. Los oficiales lo reciben solo.
- **Raid**: apúntate a las bandas que programan los oficiales como tanque, sanador o DPS, o indica si llegas tarde, eres tentativo o faltas. Consulta tu grupo.
- **Míticas+**: clasificación de la hermandad por puntuación, llaves de los compañeros, afijos y tus mejores mazmorras.
- **Profesiones**: quién tiene cada profesión y con qué nivel, para pedirle un encargo.
- **Chat de hermandad** contraíble, con pestañas por persona.

**Para oficiales**
- **Roster** con criterios de composición, cobertura de utilidades por clase, fechas, asistencia y la opción de compartirlo.
- **Raid** al estilo Raid-Helper: crea la banda, mira quién se apunta, reparte los grupos y aplícalos en la banda con un clic.
- **Warning**: inactivos, miembros sin rol, alters sin principal, baja asistencia, rangos a revisar y notas públicas.
- **Lista negra** con avisos al entrar en la hermandad o en tu grupo y bloqueo de invitaciones.
- **Invitación** de nuevos miembros, individual o masiva, con mensajes editables.
- Anuncios periódicos y exportación a CSV para Google Sheets.

Lo que se comparte entre jugadores (roles, rosters, bandas, llaves) solo llega a quien también tiene GuildControl instalado.

Comandos: `/gct` (o `/gctc`), `/gct csv`, `/gct bajas`.
