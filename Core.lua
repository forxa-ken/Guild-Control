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
    if GuildControlDB.settings.guildIcon == nil then GuildControlDB.settings.guildIcon = "tabard" end
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

function addonTable.CreateMinimapButton()
    if GuildControlMinimapButton then return end

    local button = CreateFrame("Button", "GuildControlMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\Achievement_GuildPerk_MobileBanking")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")

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
local clubCache, clubCacheAt = nil, -1000
function addonTable.GetClubMemberInfos(maxAge)
    if clubCache and GetTime() - clubCacheAt < (maxAge or 55) then return clubCache end
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers and C_Club.GetMemberInfo) then return nil end
    local clubId = C_Club.GetGuildClubId()
    if not clubId then return nil end
    local ok, memberIds = pcall(C_Club.GetClubMembers, clubId)
    if not ok or type(memberIds) ~= "table" then return nil end
    local list = {}
    for _, memberId in ipairs(memberIds) do
        local okInfo, info = pcall(C_Club.GetMemberInfo, clubId, memberId)
        if okInfo and info then list[#list + 1] = info end
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
        local fullName, rankName, rankIndex, level, _, zoneName, publicNote, officerNote, online, _, classFileName, achievementPoints, _, _, _, _, guid = GetGuildRosterInfo(i)
        
        if fullName then
            currentGuildOnlineMap[fullName] = true

            -- Años, meses y días desde la última conexión (antes solo se miraban los días)
            local years, months, days = GetGuildRosterLastOnline(i)
            days = (years or 0) * 365 + (months or 0) * 30 + (days or 0)
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
                    isOnline = isReallyOnline,
                    guid = guid,
                    rankIndex = rankIndex
                }
                addonTable.LogHistoryEvent("ALTA", fullName, "Ingreso detectado automáticamente del servidor")
                if addonTable.Blacklist and addonTable.Blacklist.CheckJoin then addonTable.Blacklist.CheckJoin(fullName) end
            else
                local m = GuildControlDB.members[fullName]
                if rankName and rankName ~= "" then m.rank = rankName end
                m.publicNote = publicNote or m.publicNote or ""
                m.level = level or m.level or 0
                m.class = classFileName or m.class or "Desconocida"
                m.zone = zoneName or m.zone or "Desconocida"
                m.lastOnline = lastOnlineStr
                m.offlineDays = isReallyOnline and 0 or days
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
    local name, realm = strsplit("-", sender, 2)
    if not realm or realm == "" then
        realm = GetNormalizedRealmName and GetNormalizedRealmName() or string.gsub(GetRealmName() or "", "%s+", "")
    end
    return name .. "-" .. string.gsub(realm, "%s+", "")
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
            if msg == "P" and Ambiguate(sender, "none") ~= UnitName("player") and GetTime() - lastHello > 60 then
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
    elseif cmd == "mini" or cmd == "banda" or cmd == "raid" then
        if addonTable.UI.EnterMiniMode then addonTable.UI.EnterMiniMode() end
    else
        print(L["|cFF00FFFF[GuildControl] Comandos disponibles:|r"])
        print(L[" /gct - Abre/Cierra la interfaz principal."])
        print(L[" /gct csv - Panel de exportación CSV para Google Sheets."])
        print(L[" /gct bajas - Historial de bajas registradas."])
        print(L[" /gct mini - Modo minimalista de banda."])
    end
end