local addonName, addonTable = ...
local L = addonTable.L
-- Idioma del cliente hasta que ADDON_LOADED cargue el elegido en Configuración
addonTable.SetLanguage("auto")

-- Versión leída del .toc. El empaquetador de CurseForge sustituye @project-version@ por la
-- etiqueta de git; si se usa el addon directamente desde el repositorio se muestra "dev".
local tocVersion = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version"))
    or (GetAddOnMetadata and GetAddOnMetadata(addonName, "Version")) or ""
addonTable.VERSION = (tocVersion == "" or string.find(tocVersion, "@", 1, true)) and "dev" or tocVersion

-- Enlace de donación al autor (botón "Donar" del encabezado). Vacío = el botón avisa de que
-- aún no hay enlace.
addonTable.DONATE_URL = "https://paypal.me/Forxaken"
-- Perfil del autor en CurseForge (botón "Más addons" del encabezado)
addonTable.MORE_ADDONS_URL = "https://www.curseforge.com/members/forxa/projects"
-- Logo predeterminado del encabezado (viene con el addon en Media\logo.tga)
addonTable.DEFAULT_LOGO = "Interface\\AddOns\\GuildControl\\Media\\logo"
GuildControlDB = GuildControlDB or {}

addonTable.Core = {}
addonTable.UI = {}

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

function addonTable.GetClassColorHex(classFileName)
    if not classFileName or classFileName == "" then return "ffffff" end
    local formattedClass = string.upper(string.gsub(classFileName, "%s+", ""))
    if C_ClassColor and C_ClassColor.GetClassColor then
        local colorObj = C_ClassColor.GetClassColor(formattedClass)
        if colorObj and colorObj.GenerateHexColor then
            local hex = colorObj:GenerateHexColor()
            if string.len(hex) > 6 then
                hex = string.sub(hex, -6)
            end
            return hex
        end
    end
    return "ffffff"
end

function addonTable.InitDB()
    if type(GuildControlDB) ~= "table" then GuildControlDB = {} end
    if type(GuildControlDB.members) ~= "table" then GuildControlDB.members = {} end
    if type(GuildControlDB.history) ~= "table" then GuildControlDB.history = {} end

    if type(GuildControlDB.announcements) ~= "table" then
        GuildControlDB.announcements = {
            { enabled = false, message = L["¡Bienvenidos a la hermandad! Revisa las normas."], interval = 15 },
            { enabled = false, message = "", interval = 30 },
            { enabled = false, message = "", interval = 45 },
            { enabled = false, message = "", interval = 60 },
            { enabled = false, message = "", interval = 90 },
        }
    end

    if type(GuildControlDB.ranks) ~= "table" or #GuildControlDB.ranks == 0 then
        GuildControlDB.ranks = { "Líder", "Oficial", "Core", "Recluta", "Social" }
    end

    if type(GuildControlDB.rosters) ~= "table" or #GuildControlDB.rosters == 0 then
        GuildControlDB.rosters = { "Sin Roster", "Roster Principal", "Roster Secundario", "Banca" }
    end

    if type(GuildControlDB.minimap) ~= "table" then
        GuildControlDB.minimap = { angle = 45, hide = false }
    end

    -- Icono del encabezado: "tabard" (emblema de la hermandad), un fileID o una ruta. Lo
    -- definen los oficiales y se comparte (GuildConfig.lua), igual que el Discord.
    if type(GuildControlDB.settings) ~= "table" then GuildControlDB.settings = {} end
    GuildControlDB.settings.guildName = nil   -- el nombre ya no se personaliza: es el del juego
    -- Por defecto, el logo que viene con el addon (Media\logo.tga). Una sola vez se cambia
    -- también el emblema ("tabard") que era el predeterminado antes.
    if GuildControlDB.settings.guildIcon == nil
        or (GuildControlDB.settings.guildIcon == "tabard" and not GuildControlDB.settings.defaultLogoApplied) then
        GuildControlDB.settings.guildIcon = addonTable.DEFAULT_LOGO
    end
    GuildControlDB.settings.defaultLogoApplied = true
    if type(GuildControlDB.settings.guildConfigAt) ~= "number" then GuildControlDB.settings.guildConfigAt = 0 end

    -- Idioma de la interfaz: "auto" (el del cliente) o un código de Locales/ (esES, enUS...)
    if type(GuildControlDB.settings.language) ~= "string" then GuildControlDB.settings.language = "auto" end
    -- Enlace de Discord de la hermandad (botón junto al nombre; vacío = sin botón)
    if type(GuildControlDB.settings.discordLink) ~= "string" then GuildControlDB.settings.discordLink = "" end

    -- Panel de chat de hermandad y saludo automático
    if type(GuildControlDB.settings.windowOnTop) ~= "boolean" then GuildControlDB.settings.windowOnTop = false end
    if type(GuildControlDB.settings.chatCollapsed) ~= "boolean" then GuildControlDB.settings.chatCollapsed = false end
    -- Desactivado por defecto: el addon no escribe en el chat por su cuenta hasta que se active
    if type(GuildControlDB.settings.autoGreet) ~= "boolean" then GuildControlDB.settings.autoGreet = false end
    if type(GuildControlDB.settings.greetDelay) ~= "number" then GuildControlDB.settings.greetDelay = 2 end        -- segundos
    if type(GuildControlDB.settings.greetCooldown) ~= "number" then GuildControlDB.settings.greetCooldown = 30 end -- minutos
    if type(GuildControlDB.settings.greetLoginWindow) ~= "number" then GuildControlDB.settings.greetLoginWindow = 5 end -- minutos
    -- Palabras de saludo separadas por comas; vacío = lista por defecto de GuildChat.lua
    if type(GuildControlDB.settings.greetWords) ~= "string" then GuildControlDB.settings.greetWords = "" end
    if type(GuildControlDB.settings.greetMessage) ~= "string" or GuildControlDB.settings.greetMessage == "" then
        GuildControlDB.settings.greetMessage = L["¡Hola, {nombre}!"]
    end

    -- Generador del mensaje de invitación para nuevos miembros (vista Invitar)
    if type(GuildControlDB.settings.recruit) ~= "table" then GuildControlDB.settings.recruit = {} end
    local recruit = GuildControlDB.settings.recruit
    if type(recruit.roles) ~= "table" then recruit.roles = { tank = true, healer = true, dps = true } end
    if type(recruit.activities) ~= "table" then recruit.activities = { raid = true, mplus = true, pvp = false, social = true, leveling = false } end
    if type(recruit.schedule) ~= "string" then recruit.schedule = "" end
    if type(recruit.extra) ~= "string" then recruit.extra = L["¡Susúrrame para más información!"] end
    if type(recruit.message) ~= "string" then recruit.message = "" end
    if type(recruit.massMessage) ~= "string" or recruit.massMessage == "" then
        recruit.massMessage = L["¡Hola, {nombre}! {rt1} Te he invitado a <{hermandad}>. Si te interesa, acepta la invitación o susúrrame."]
    end
    if type(recruit.massWhisper) ~= "boolean" then recruit.massWhisper = true end
    if recruit.mode ~= "single" and recruit.mode ~= "mass" then recruit.mode = "single" end
    -- Dónde se publica el mensaje de reclutamiento: "yell" (grito) o un canal de recruitChannels
    if recruit.publishChannel ~= "yell" and recruit.publishChannel ~= "general" and recruit.publishChannel ~= "trade"
        and recruit.publishChannel ~= "world" then recruit.publishChannel = "trade" end
    -- Nombres de los canales (se cambian en Configuración; dependen del idioma del cliente)
    if type(GuildControlDB.settings.recruitChannels) ~= "table" then GuildControlDB.settings.recruitChannels = {} end
    local channels = GuildControlDB.settings.recruitChannels
    if type(channels.general) ~= "string" or channels.general == "" then channels.general = L["General"] end
    if type(channels.trade) ~= "string" or channels.trade == "" then channels.trade = L["Comercio"] end
    if type(channels.world) ~= "string" or channels.world == "" then channels.world = L["Mundo"] end

    -- Aviso de favoritos conectados: sonido activado y cuál (Favorites.SOUNDS)
    if type(GuildControlDB.settings.favoriteSoundEnabled) ~= "boolean" then GuildControlDB.settings.favoriteSoundEnabled = true end
    if type(GuildControlDB.settings.favoriteSound) ~= "string" then GuildControlDB.settings.favoriteSound = "toast" end

    -- Bienvenida a quien entra nuevo en la hermandad (desactivada por defecto)
    if type(GuildControlDB.settings.welcomeNew) ~= "boolean" then GuildControlDB.settings.welcomeNew = false end
    if type(GuildControlDB.settings.welcomeMessage) ~= "string" or GuildControlDB.settings.welcomeMessage == "" then
        GuildControlDB.settings.welcomeMessage = L["¡Bienvenido/a a <{hermandad}>, {nombre}! Si tienes cualquier duda, pregunta por aquí."]
    end

    -- Mensaje para los integrantes de un roster (botón Mensaje de la vista Roster)
    if type(GuildControlDB.settings.rosterMessage) ~= "string" or GuildControlDB.settings.rosterMessage == "" then
        GuildControlDB.settings.rosterMessage = L["{rt1} {roster} ({dificultad}): banda el {fecha} a las {hora}. ¡Confirmad asistencia!"]
    end

    -- Los mensajes que siguen con el texto por defecto en español pasan al idioma activo
    local function LocalizeDefault(current, default)
        if current == default then return L[default] end
        return current
    end
    local s = GuildControlDB.settings
    s.greetMessage = LocalizeDefault(s.greetMessage, "¡Hola, {nombre}!")
    recruit.extra = LocalizeDefault(recruit.extra, "¡Susúrrame para más información!")
    recruit.massMessage = LocalizeDefault(recruit.massMessage, "¡Hola, {nombre}! {rt1} Te he invitado a <{hermandad}>. Si te interesa, acepta la invitación o susúrrame.")
    s.rosterMessage = LocalizeDefault(s.rosterMessage, "{rt1} {roster} ({dificultad}): banda el {fecha} a las {hora}. ¡Confirmad asistencia!")
    if GuildControlDB.announcements[1] then
        GuildControlDB.announcements[1].message = LocalizeDefault(GuildControlDB.announcements[1].message, "¡Bienvenidos a la hermandad! Revisa las normas.")
    end

    -- Roles puestos antes de existir roleSource: si no es el "DPS" por defecto, lo fijó un oficial
    for _, m in pairs(GuildControlDB.members) do
        if not m.roleSource and m.role and m.role ~= "DPS" then m.roleSource = "officer" end
    end

    -- Fecha (time()) de la última invitación masiva a cada jugador, para no repetirla
    if type(GuildControlDB.inviteHistory) ~= "table" then GuildControlDB.inviteHistory = {} end

    -- Las fechas del Roster pasaron a Raid: su asistencia se conserva como historial
    if addonTable.RaidEvents and addonTable.RaidEvents.MigrateRosterDates then
        addonTable.RaidEvents.MigrateRosterDates()
    end

    addonTable.MigrateNameKeys()
    addonTable.ResetRolesForClasses()
end

-- Una sola vez al llegar los roles por clase: los roles guardados que la clase no puede llevar
-- (rol del miembro, lo declarado en Mi perfil y Mi perfil de mis personajes) se quitan o pasan a
-- DPS; los posibles se conservan. En rosters e inscripciones de banda, un tanque o sanador que su
-- clase no puede llevar pasa a DPS.
function addonTable.ResetRolesForClasses()
    if GuildControlDB.rolesByClassV1 then return end
    GuildControlDB.rolesByClassV1 = true
    for name, m in pairs(GuildControlDB.members or {}) do
        local class = m.class
        if m.role and m.role ~= "DPS" and not addonTable.ClassCanRole(class, m.role) then m.role = "DPS" end
        if type(m.declared) == "table" then
            if m.declared.main and not addonTable.ClassCanRole(class, m.declared.main) then m.declared.main = "DPS" end
            if m.declared.secondary and not addonTable.ClassCanRole(class, m.declared.secondary) then m.declared.secondary = nil end
        end
    end
    for name, profile in pairs(type(GuildControlDB.myProfiles) == "table" and GuildControlDB.myProfiles or {}) do
        local class = addonTable.GetMemberClass(name)
        if profile.main and not addonTable.ClassCanRole(class, profile.main) then profile.main = "DPS" end
        if profile.secondary and not addonTable.ClassCanRole(class, profile.secondary) then profile.secondary = nil end
    end
    local function FixSlots(map)
        for name, slot in pairs(type(map) == "table" and map or {}) do
            if (slot == "tank" or slot == "healer") and not addonTable.ClassCanRole(addonTable.GetMemberClass(name), slot) then
                map[name] = "dps"
            end
        end
    end
    local data = GuildControlDB.rosterData
    for _, roster in pairs(type(data) == "table" and type(data.rosters) == "table" and data.rosters or {}) do
        FixSlots(roster.members)
        for _, variant in pairs(type(roster.variants) == "table" and roster.variants or {}) do FixSlots(variant.overrides) end
    end
    for _, event in pairs(type(GuildControlDB.raidEvents) == "table" and GuildControlDB.raidEvents or {}) do
        for name, signup in pairs(type(event.signups) == "table" and event.signups or {}) do
            if (signup.role == "tank" or signup.role == "healer") and not addonTable.ClassCanRole(addonTable.GetMemberClass(name), signup.role) then
                signup.role = "dps"
            end
        end
    end
end

-- Una sola vez: pasa a "Nombre-Reino" sin apellido las claves de jugador guardadas con otros
-- formatos ("Peppa Pic", "PeppaPic-Reino"). Si dos claves acaban en la misma, se queda la que
-- ya tenía el formato nuevo.
local function RekeyNames(map)
    if type(map) ~= "table" then return end
    local moves = {}
    for key, value in pairs(map) do
        if type(key) == "string" then
            local normalized = addonTable.NormalizeName(key)
            if normalized and normalized ~= key then moves[key] = { normalized, value } end
        end
    end
    for old, move in pairs(moves) do
        map[old] = nil
        if map[move[1]] == nil then map[move[1]] = move[2] end
    end
end

function addonTable.MigrateNameKeys()
    local db = GuildControlDB
    if db.nameKeysVersion == 2 then return end
    for _, key in ipairs({ "members", "favorites", "myProfiles", "addonUsers", "wishlists", "recipes",
                           "myLedgerLast", "keystones" }) do
        RekeyNames(db[key])
    end
    for _, m in pairs(db.members or {}) do
        if type(m) == "table" and m.name then m.name = addonTable.NormalizeName(m.name) or m.name end
    end
    if type(db.loot) == "table" then RekeyNames(db.loot.points); RekeyNames(db.loot.pointsAt) end
    if type(db.dkp) == "table" then RekeyNames(db.dkp.balances); RekeyNames(db.dkp.since) end
    if type(db.rosterData) == "table" then
        for _, roster in pairs(db.rosterData.rosters or {}) do
            if type(roster) == "table" then
                RekeyNames(roster.members)
                for _, variant in pairs(roster.variants or {}) do
                    if type(variant) == "table" then RekeyNames(variant.overrides) end
                end
            end
        end
    end
    for _, item in pairs(db.sharedRosters or {}) do
        if type(item) == "table" and type(item.roster) == "table" then RekeyNames(item.roster.members) end
    end
    for _, event in pairs(db.raidEvents or {}) do
        if type(event) == "table" then RekeyNames(event.signups); RekeyNames(event.groups) end
    end
    for _, rec in pairs(db.raidAttendance or {}) do
        if type(rec) == "table" then RekeyNames(rec.marks) end
    end
    db.nameKeysVersion = 2
end

-- Nombre de la hermandad que da el juego (o uno genérico sin hermandad)
function addonTable.GetDisplayGuildName()
    local guildName = IsInGuild() and GetGuildInfo("player")
    return guildName or L["Sin hermandad"]
end

-- Acepta un fileID, una ruta completa o solo el nombre del icono ("INV_Misc_QuestionMark")
function addonTable.ResolveIconTexture(value)
    if type(value) == "number" then return value end
    if type(value) ~= "string" or value == "" then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    local asNumber = tonumber(value)
    if asNumber then return asNumber end
    if string.find(value, "[\\/]") then return value end
    return "Interface\\Icons\\" .. value
end

function addonTable.LogHistoryEvent(actionType, characterName, details)
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    table.insert(GuildControlDB.history, 1, {
        date = timestamp,
        action = actionType,
        name = characterName,
        info = details or ""
    })
    if #GuildControlDB.history > 300 then
        table.remove(GuildControlDB.history)
    end
end

-- Clave única de un jugador: "Nombre-Reino" (el reino sin espacios; si falta, el propio).
-- Si el nombre trae más de una palabra solo cuenta la primera (en Classic Forever los
-- personajes llevan apellido). Todos los NormalizeName de los módulos usan esta función.
local function NormalizedRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then realm = GetRealmName() or "" end
    return (string.gsub(realm, "%s+", ""))
end

function addonTable.NormalizeName(name)
    if type(name) ~= "string" then return nil end
    if issecretvalue and issecretvalue(name) then return nil end
    name = strtrim(name)
    if name == "" then return nil end
    local base, realm = strsplit("-", name, 2)
    base = string.match(base or "", "^(%S+)")
    if not base then return nil end
    if not realm or strtrim(realm) == "" then realm = NormalizedRealm() end
    return base .. "-" .. string.gsub(realm, "%s+", "")
end

-- ¿Es este nombre el del propio personaje? (para ignorar los mensajes propios del addon)
function addonTable.IsMe(name)
    local me = addonTable.NormalizeName(UnitName("player"))
    return me ~= nil and addonTable.NormalizeName(name) == me
end

-- =========================================================================
-- ROLES POSIBLES DE CADA CLASE (RETAIL)
-- =========================================================================
-- Tanque: guerrero, paladín, druida, caballero de la muerte, monje y cazador de demonios.
-- Sanador: paladín, druida, sacerdote, chamán, monje y evocador. DPS: todas.
-- Cazador, pícaro, mago y brujo solo pueden ser DPS.
addonTable.CLASS_ROLES = {
    WARRIOR = { tank = true, dps = true },
    PALADIN = { tank = true, healer = true, dps = true },
    DRUID = { tank = true, healer = true, dps = true },
    DEATHKNIGHT = { tank = true, dps = true },
    MONK = { tank = true, healer = true, dps = true },
    DEMONHUNTER = { tank = true, dps = true },
    PRIEST = { healer = true, dps = true },
    SHAMAN = { healer = true, dps = true },
    EVOKER = { healer = true, dps = true },
    HUNTER = { dps = true }, ROGUE = { dps = true }, MAGE = { dps = true }, WARLOCK = { dps = true },
}
-- Acepta el rol guardado ("Tanque", "Sanador", "DPS") o el de hueco ("tank", "healer", "dps")
local ROLE_KEYS = { Tanque = "tank", Sanador = "healer", DPS = "dps", tank = "tank", healer = "healer", dps = "dps" }
function addonTable.RoleKey(role) return ROLE_KEYS[role] end

-- Clase de un miembro (la mía con UnitClass, por si mi ficha aún no está)
function addonTable.GetMemberClass(fullName)
    if fullName and addonTable.IsMe(fullName) then return select(2, UnitClass("player")) end
    local m = fullName and GuildControlDB and GuildControlDB.members and GuildControlDB.members[addonTable.NormalizeName(fullName) or fullName]
    return m and m.class or nil
end

function addonTable.ClassCanRole(class, role)
    local key = ROLE_KEYS[role]
    if not key then return false end
    if key == "dps" then return true end
    local allowed = class and addonTable.CLASS_ROLES[class]
    if not allowed then return true end   -- clase desconocida: no se limita
    return allowed[key] == true
end

-- ¿Puede este jugador llevar ese rol? Las herramientas de desarrollador pueden quitar el
-- límite para el propio personaje (solo en este cliente, para hacer pruebas)
function addonTable.CanRole(fullName, role)
    if fullName and addonTable.Dev and addonTable.Dev.IgnoreClassRoles and addonTable.Dev.IgnoreClassRoles()
        and addonTable.IsMe(fullName) and ROLE_KEYS[role] then
        return true
    end
    return addonTable.ClassCanRole(addonTable.GetMemberClass(fullName), role)
end

function addonTable.IsDpsOnlyClass(class)
    local allowed = class and addonTable.CLASS_ROLES[class]
    return allowed ~= nil and not allowed.tank and not allowed.healer
end

-- Mensaje al intentar un rol que la clase no puede llevar
function addonTable.WarnClassRole(fullName, role)
    local class = addonTable.GetMemberClass(fullName)
    local className = (class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class or "?"
    local roleNames = { tank = L["Tanque"], healer = L["Sanador"], dps = "DPS" }
    print("|cFF00FFFF[GuildControl]|r " .. string.format(L["|cFFFF3333Un %s no puede ser %s.|r"], className, roleNames[ROLE_KEYS[role]] or tostring(role)))
end

-- Nombre que entiende el juego para invitar o susurrar. En Classic Forever la clave interna
-- ("Peppa-Reino") no vale: el personaje se llama con su apellido ("Peppa Pic"). Se usa el nombre tal
-- como lo da la lista de la hermandad (member.displayName) y el reino solo si es otro.
-- Sin ficha (alguien de fuera de la hermandad) se usa lo que se escribió.
function addonTable.GetGameName(name)
    if type(name) ~= "string" or name == "" then return name end
    local key = addonTable.NormalizeName(name)
    local m = key and GuildControlDB and GuildControlDB.members and GuildControlDB.members[key]
    local base, realm = strsplit("-", name, 2)
    -- displayName puede traer ya el reino (Retail): solo se toma el nombre
    local gameName = (m and m.displayName and (strsplit("-", m.displayName))) or base
    local _, keyRealm = strsplit("-", key or "", 2)
    realm = (realm and realm ~= "") and realm or keyRealm
    if realm and realm ~= "" and string.gsub(realm, "%s+", "") ~= NormalizedRealm() then
        gameName = gameName .. "-" .. realm
    end
    return gameName
end

-- Registra eventos que quizá no existan en todos los clientes: el juego da error con un
-- evento desconocido, así que se registran uno a uno con pcall y se ignoran los que faltan
function addonTable.RegisterEvents(frame, ...)
    for i = 1, select("#", ...) do
        pcall(frame.RegisterEvent, frame, (select(i, ...)))
    end
end

-- Momento del último reinicio semanal (caja Esta semana del Resumen)
function addonTable.GetLastWeeklyReset()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local ok, seconds = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
        if ok and type(seconds) == "number" then return time() + seconds - 7 * 86400 end
    end
    return time() - 7 * 86400
end

function addonTable.CreateMinimapButton()
    if GuildControlMinimapButton then return end

    local button = CreateFrame("Button", "GuildControlMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- El logo del addon (Media\logo.tga), recortado en círculo como los demás botones del minimapa
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(addonTable.DEFAULT_LOGO)
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER")
    if button.CreateMaskTexture then
        local mask = button:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", -1, 1)

    local function UpdatePosition()
        local angle = math.rad(GuildControlDB.minimap.angle or 45)
        local radius = (Minimap:GetWidth() / 2) + 2
        local x = math.cos(angle) * radius
        local y = math.sin(angle) * radius
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            GuildControlDB.minimap.angle = angle
            UpdatePosition()
        end)
    end)

    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" and addonTable.UI.ToggleUI then
            addonTable.UI.ToggleUI()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("GuildControl", 1, 1, 1)
        GameTooltip:AddLine(L["Clic izquierdo: Abrir/Cerrar panel"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Arrastrar: Mover alrededor del minimapa"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
    addonTable.ApplyMinimapButton()
end

-- Configuración > Ocultar el botón del minimapa (GuildControlDB.minimap.hide)
function addonTable.ApplyMinimapButton()
    if not GuildControlMinimapButton then return end
    GuildControlMinimapButton:SetShown(not (GuildControlDB.minimap and GuildControlDB.minimap.hide))
end

local isSyncingRoster = false
local lastExecutionTimestamp = 0
-- El primer escaneo de la sesión solo fija el estado inicial: quien ya estaba conectado
-- antes de entrar no cuenta como recién conectado (saludo automático)
local rosterBaselineDone = false

-- Escaneo pendiente: los avisos que llegan durante el throttle no se pierden, se aplazan
local pendingScanTimer = nil
local function ScheduleScan(delay)
    if pendingScanTimer then return end
    pendingScanTimer = C_Timer.NewTimer(delay, function()
        pendingScanTimer = nil
        addonTable.ScanGuildRosterForChanges()
    end)
end

-- Miembros de la hermandad en C_Club (puntuación M+ y profesiones). Recorrer la lista es caro
-- en hermandades grandes: se hace una vez y la usan los dos módulos. maxAge = segundos que
-- vale la copia (55 por defecto).
local CLUB_FIELDS = { "guid", "profession1Name", "profession1Rank", "profession2Name", "profession2Rank", "overallDungeonScore" }
local function IsSecret(value) return issecretvalue ~= nil and issecretvalue(value) == true end
local clubCache, clubCacheAt = nil, -1000
function addonTable.GetClubMemberInfos(maxAge)
    if clubCache and GetTime() - clubCacheAt < (maxAge or 55) then return clubCache end
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers and C_Club.GetMemberInfo) then return nil end
    local clubId = C_Club.GetGuildClubId()
    if not clubId then return nil end
    local ok, memberIds = pcall(C_Club.GetClubMembers, clubId)
    -- En 12.x, durante un encuentro o en momentos restringidos, C_Club puede devolver valores
    -- secretos (no se pueden recorrer ni comparar): se usa la copia anterior y se reintenta luego
    if not ok or IsSecret(memberIds) or type(memberIds) ~= "table" then return clubCache end
    local list = {}
    for _, memberId in ipairs(memberIds) do
        if not IsSecret(memberId) then
            local okInfo, info = pcall(C_Club.GetMemberInfo, clubId, memberId)
            if okInfo and info and not IsSecret(info) then
                -- Solo los campos que usan Profesiones y Míticas+, y solo si no son secretos
                local copy = {}
                for _, field in ipairs(CLUB_FIELDS) do
                    local value = info[field]
                    if not IsSecret(value) then copy[field] = value end
                end
                if copy.guid then list[#list + 1] = copy end
            end
        end
    end
    clubCache, clubCacheAt = list, GetTime()
    return list
end

-- Al entrar en el juego se hace lo mínimo: los recorridos caros (C_Club para profesiones y
-- Míticas+) esperan unos segundos para no provocar una caída de FPS al cargar
local LOGIN_QUIET_SECONDS = 20
local loadedAt = GetTime()
local function IsLoginQuiet() return GetTime() - loadedAt < LOGIN_QUIET_SECONDS end

function addonTable.ScanGuildRosterForChanges()
    local currentTime = GetTime()
    if not IsInGuild() or isSyncingRoster then return end
    if currentTime - lastExecutionTimestamp < 5 then
        ScheduleScan(5 - (currentTime - lastExecutionTimestamp) + 0.1)
        return
    end

    -- Al conectar, la lista de la hermandad puede llegar vacía o a medias: sin datos no se
    -- toca nada (antes se purgaba a todos los miembros y se volvían a dar de alta)
    local numMembers = GetNumGuildMembers()
    if not numMembers or numMembers == 0 then
        C_GuildInfo.GuildRoster()
        ScheduleScan(3)
        return
    end

    isSyncingRoster = true
    lastExecutionTimestamp = currentTime

    local currentGuildOnlineMap = {}

    for i = 1, numMembers do
        local rawName, rankName, rankIndex, level, _, zoneName, publicNote, officerNote, online, _, classFileName, achievementPoints, _, _, _, _, guid = GetGuildRosterInfo(i)
        -- Forever da "Nombre Apellido" sin reino: la clave es "Nombre-Reino", la misma que
        -- llega en los mensajes del addon. Los datos guardados con la clave antigua se mueven.
        local fullName = addonTable.NormalizeName(rawName)

        if fullName then
            if rawName ~= fullName and GuildControlDB.members[rawName] and not GuildControlDB.members[fullName] then
                GuildControlDB.members[fullName] = GuildControlDB.members[rawName]
                GuildControlDB.members[rawName] = nil
            end
            currentGuildOnlineMap[fullName] = true

            -- Años, meses y días desde la última conexión (antes solo se miraban los días)
            local years, months, days, hours = GetGuildRosterLastOnline(i)
            days = (years or 0) * 365 + (months or 0) * 30 + (days or 0)
            -- Horas desconectado
            local offlineHours = days * 24 + (hours or 0)
            local isReallyOnline = (online == true or online == 1 or online == "true")
            local lastOnlineStr = "Online"
            
            if not isReallyOnline then
                if days and days > 0 then
                    lastOnlineStr = days .. " días"
                else
                    lastOnlineStr = "Desconectado"
                end
            end

            if not GuildControlDB.members[fullName] then
                GuildControlDB.members[fullName] = {
                    name = fullName,
                    displayName = (strsplit("-", rawName)),   -- sin reino; con apellido si el juego lo da (Forever)
                    rank = rankName or "Recluta",
                    publicNote = publicNote or "",
                    role = "DPS",
                    focus = "PvE",
                    prof1 = "Ninguna",
                    prof2 = "Ninguna",
                    roster = "Sin Roster",
                    level = level or 0,
                    class = classFileName or "Desconocida",
                    zone = zoneName or "Desconocida",
                    lastOnline = lastOnlineStr,
                    offlineDays = isReallyOnline and 0 or days,
                    offlineHours = isReallyOnline and 0 or offlineHours,
                    isOnline = isReallyOnline,
                    guid = guid,
                    rankIndex = rankIndex
                }
                addonTable.LogHistoryEvent("ALTA", fullName, "Ingreso detectado automáticamente del servidor")
                if addonTable.Blacklist and addonTable.Blacklist.CheckJoin then addonTable.Blacklist.CheckJoin(fullName) end
            else
                local m = GuildControlDB.members[fullName]
                m.name = fullName
                m.displayName = (strsplit("-", rawName))
                if rankName and rankName ~= "" then m.rank = rankName end
                m.publicNote = publicNote or m.publicNote or ""
                m.level = level or m.level or 0
                m.class = classFileName or m.class or "Desconocida"
                m.zone = zoneName or m.zone or "Desconocida"
                m.lastOnline = lastOnlineStr
                m.offlineDays = isReallyOnline and 0 or days
                m.offlineHours = isReallyOnline and 0 or offlineHours
                if rosterBaselineDone and addonTable.GuildChat then
                    if isReallyOnline and not m.isOnline and addonTable.GuildChat.MarkOnline then
                        addonTable.GuildChat.MarkOnline(fullName)
                        if addonTable.Favorites and addonTable.Favorites.OnOnline then addonTable.Favorites.OnOnline(fullName) end
                    elseif not isReallyOnline and m.isOnline and addonTable.GuildChat.MarkOffline then
                        addonTable.GuildChat.MarkOffline(fullName)
                    end
                end
                m.isOnline = isReallyOnline
                m.guid = guid or m.guid
                m.achievementPoints = tonumber(achievementPoints) or m.achievementPoints
                m.rankIndex = rankIndex
            end
        end
    end

    rosterBaselineDone = true

    -- Solo se purga si la lista del juego trae a todos los miembros que dice tener
    local scanned = 0
    for _ in pairs(currentGuildOnlineMap) do scanned = scanned + 1 end
    local rosterComplete = scanned >= numMembers

    for existingMember, _ in pairs(GuildControlDB.members) do
        if rosterComplete and not currentGuildOnlineMap[existingMember] then
            addonTable.LogHistoryEvent("BAJA", existingMember, "Purgado: Ya no se encuentra en el servidor oficial")
            GuildControlDB.members[existingMember] = nil
        end
    end

    if not IsLoginQuiet() then
        if addonTable.Professions and addonTable.Professions.Scan then
            addonTable.Professions.Scan()
        end
        -- Puntuación Mítica+ de cada miembro (lista de la hermandad del juego)
        if addonTable.MythicPlus and addonTable.MythicPlus.UpdateScores then
            addonTable.MythicPlus.UpdateScores()
        end
    end

    -- Roles declarados por otros personajes de esta cuenta (comparten SavedVariables)
    if addonTable.Profiles and addonTable.Profiles.ApplyAccountProfiles then
        addonTable.Profiles.ApplyAccountProfiles()
    end

    if addonTable.UI.RefreshList and addonTable.UI.IsShown and addonTable.UI.IsShown() then
        addonTable.UI.RefreshList()
    end
    if addonTable.UI.UpdateMemberCounter then
        addonTable.UI.UpdateMemberCounter()
    end
    -- El rango puede haber cambiado: actualizar las pestañas visibles según el perfil
    if addonTable.UI.ApplyProfile and addonTable.UI.IsShown and addonTable.UI.IsShown() then
        addonTable.UI.ApplyProfile()
    end

    isSyncingRoster = false
end

-- Pide la lista al servidor y escanea sin esperar al throttle (botón Actualizar de Miembros)
function addonTable.ForceRosterScan()
    if not IsInGuild() then return end
    C_GuildInfo.GuildRoster()
    lastExecutionTimestamp = 0
    addonTable.ScanGuildRosterForChanges()
    -- La respuesta del servidor llega con GUILD_ROSTER_UPDATE; por si tarda, otro intento
    ScheduleScan(2)
end

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        addonTable.SetLanguage(type(GuildControlDB) == "table" and type(GuildControlDB.settings) == "table" and GuildControlDB.settings.language or "auto")
        addonTable.InitDB()
        addonTable.CreateMinimapButton()
        C_GuildInfo.GuildRoster()
        -- Profesiones y Míticas+ pasado el arranque (ver LOGIN_QUIET_SECONDS)
        C_Timer.After(LOGIN_QUIET_SECONDS + 2, function()
            lastExecutionTimestamp = 0
            addonTable.ScanGuildRosterForChanges()
        end)
        print("|cFF00FFFF[GuildControl]|r v" .. addonTable.VERSION .. L[" cargado. Usa /gct para abrir la interfaz."])
    elseif event == "PLAYER_ENTERING_WORLD" or event == "GUILD_ROSTER_UPDATE" then
        addonTable.ScanGuildRosterForChanges()
    end
end)

-- =========================================================================
-- QUIÉN USA GUILDCONTROL
-- =========================================================================
-- GuildControlDB.addonUsers[Nombre-Reino] = { version, at (time()) }
-- Cuenta cualquier mensaje de addon de GuildControl (roles, llaves, bandas...). Además, al
-- entrar cada cliente dice "H;versión" con el prefijo GuildControlHi, y "P" (botón Comprobar
-- ahora de Warning) pide que respondan todos los conectados que lo usan.
local HI_PREFIX = "GuildControlHi"
local lastHello = 0
local warningsRefreshPending = false
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(HI_PREFIX)
end

local function FullSenderName(sender)
    return addonTable.NormalizeName(sender)
end

function addonTable.MarkAddonUser(fullName, version)
    if not fullName or type(GuildControlDB) ~= "table" then return end
    if type(GuildControlDB.addonUsers) ~= "table" then GuildControlDB.addonUsers = {} end
    local entry = GuildControlDB.addonUsers[fullName] or {}
    entry.at = time()
    if version and version ~= "" then entry.version = version end
    GuildControlDB.addonUsers[fullName] = entry
end

function addonTable.GetAddonUser(fullName)
    return fullName and type(GuildControlDB.addonUsers) == "table" and GuildControlDB.addonUsers[fullName] or nil
end

local function SendHello()
    if not IsInGuild() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    lastHello = GetTime()
    C_ChatInfo.SendAddonMessage(HI_PREFIX, "H;" .. tostring(addonTable.VERSION), "GUILD")
end

-- Pide a todos los conectados con GuildControl que respondan
function addonTable.PingAddonUsers()
    if not IsInGuild() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    C_ChatInfo.SendAddonMessage(HI_PREFIX, "P", "GUILD")
end

-- Ocupado en un encuentro: al empezar un jefe de mazmorra o banda se avisa a la hermandad
-- ("B;jefe") y al terminar ("F"). Quien le susurre desde el addon ve que está ocupado.
local busyPlayers = {}      -- [Nombre-Reino] = { boss, at = GetTime() }
local BUSY_MAX_SECONDS = 20 * 60

local function SendBusy(msg)
    if not IsInGuild() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    pcall(C_ChatInfo.SendAddonMessage, HI_PREFIX, msg, "GUILD")
end

-- Jefe con el que está ese jugador (o nil)
function addonTable.GetBusyBoss(name)
    if not name or name == "" then return nil end
    local entry = busyPlayers[FullSenderName(name)]
    if not entry then return nil end
    if GetTime() - entry.at > BUSY_MAX_SECONDS then
        busyPlayers[FullSenderName(name)] = nil
        return nil
    end
    return entry.boss
end

-- Avisa en el chat si el jugador al que vas a susurrar está con un jefe
function addonTable.WarnIfBusy(name)
    local boss = addonTable.GetBusyBoss(name)
    if not boss then return false end
    local short = string.match(name, "^([^-]+)") or name
    print("|cFF00FFFF[GuildControl]|r " .. string.format(L["|cFFFF7F00%s está en un encuentro con %s y ahora está ocupado.|r"], short, boss))
    return true
end

local presenceFrame = CreateFrame("Frame")
presenceFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
presenceFrame:RegisterEvent("ENCOUNTER_START")
presenceFrame:RegisterEvent("ENCOUNTER_END")
presenceFrame:RegisterEvent("CHAT_MSG_ADDON")
presenceFrame:SetScript("OnEvent", function(_, event, ...)
    if type(GuildControlDB) ~= "table" then return end
    if event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then
        local _, instanceType = GetInstanceInfo()
        if instanceType ~= "party" and instanceType ~= "raid" then return end
        if event == "ENCOUNTER_START" then
            local _, encounterName = ...
            if issecretvalue and issecretvalue(encounterName) then encounterName = nil end
            SendBusy("B;" .. string.gsub(tostring(encounterName or L["un jefe"]), "[;|]", ""))
        else
            SendBusy("F")
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin or isReloadingUi then
            addonTable.MarkAddonUser(FullSenderName(UnitName("player")), addonTable.VERSION)
            C_Timer.After(18, SendHello)
        end
        return
    end
    local prefix, msg, channel, sender = ...
    -- Barato: solo los prefijos del addon
    if type(prefix) ~= "string" or (string.sub(prefix, 1, 12) ~= "GuildControl" and prefix ~= "GCRoleReq") then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    if not sender or sender == "" then return end
    local fullName = FullSenderName(sender)
    if prefix == HI_PREFIX and type(msg) == "string" then
        if string.sub(msg, 1, 2) == "B;" then
            addonTable.MarkAddonUser(fullName)
            busyPlayers[fullName] = { boss = string.sub(msg, 3, 60), at = GetTime() }
            return
        elseif msg == "F" then
            busyPlayers[fullName] = nil
            return
        elseif string.sub(msg, 1, 2) == "H;" then
            addonTable.MarkAddonUser(fullName, string.sub(msg, 3, 30))
        else
            addonTable.MarkAddonUser(fullName)
            -- Petición: se responde con un pequeño retraso (y no más de una vez por minuto)
            if msg == "P" and not addonTable.IsMe(sender) and GetTime() - lastHello > 60 then
                lastHello = GetTime()
                C_Timer.After(1 + math.random() * 6, SendHello)
            end
        end
        -- Tras "Comprobar ahora" llegan muchas respuestas: Warning se refresca una sola vez
        if not warningsRefreshPending and addonTable.UI and addonTable.UI.RefreshWarnings then
            warningsRefreshPending = true
            C_Timer.After(1, function()
                warningsRefreshPending = false
                if addonTable.UI.RefreshWarnings then addonTable.UI.RefreshWarnings() end
            end)
        end
    else
        addonTable.MarkAddonUser(fullName)
    end
end)

SLASH_GUILDCONTROL1 = "/gct"
SLASH_GUILDCONTROL2 = "/gctc"

SlashCmdList["GUILDCONTROL"] = function(msg)
    local cleanMsg = string.trim and string.trim(msg) or msg:match("^%s*(.-)%s*$")
    local args = {}
    for word in string.gmatch(cleanMsg or "", "%S+") do table.insert(args, word) end
    local cmd = args[1] and string.lower(args[1]) or ""

    if cmd == "show" or cmd == "" then
        if addonTable.UI.ToggleUI then addonTable.UI.ToggleUI() end
    elseif cmd == "bajas" or cmd == "leaves" then
        if addonTable.UI.ShowBajas then addonTable.UI.ShowBajas() end
    elseif cmd == "csv" then
        if addonTable.CSV and addonTable.CSV.ShowFrame then addonTable.CSV.ShowFrame() end
    elseif cmd == "ayudante" or cmd == "helper" or cmd == "mini" or cmd == "banda" or cmd == "raid" then
        if addonTable.UI.EnterMiniMode then addonTable.UI.EnterMiniMode() end
    elseif cmd == "pizarra" or cmd == "board" then
        if addonTable.Board then addonTable.InitDB(); addonTable.Board.Toggle() end
    elseif cmd == "recetas" or cmd == "recipes" then
        if addonTable.Community and addonTable.Community.DebugRecipes then addonTable.Community.DebugRecipes() end
    elseif cmd == "dev" and addonTable.Dev and addonTable.Dev.Toggle then
        addonTable.Dev.Toggle()   -- solo en la copia del autor (Dev/ no se empaqueta)
    else
        print(L["|cFF00FFFF[GuildControl] Comandos disponibles:|r"])
        print(L[" /gct - Abre/Cierra la interfaz principal."])
        print(L[" /gct csv - Panel de exportación CSV para Google Sheets."])
        print(L[" /gct bajas - Historial de bajas registradas."])
        print(L[" /gct ayudante - Ayudante de banda (panel pequeño)."])
        print(L[" /gct pizarra - Pizarra para explicar un jefe."])
        print(L[" /gct recetas - Diagnóstico: quién usa el addon y pide las recetas a la hermandad."])
    end
end