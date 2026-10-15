local addonName, addonTable = ...
local L = addonTable.L

addonTable.Profiles = {}
local profilesModule = addonTable.Profiles

-- Perfiles de uso y roles declarados por los propios jugadores.
--
-- Perfil: "officer" u "player". Es oficial quien tiene el permiso de chat de oficiales
-- del juego o un rango igual o superior al configurado (settings.officerRankIndex,
-- 0 = maestro de hermandad). El perfil solo decide qué partes de la interfaz se ven;
-- los datos de cada oficial siguen siendo locales.
--
-- Rol declarado: cada jugador indica en "Mi perfil" su rol principal, el secundario,
-- su especialización y una nota. Se envía a la hermandad con el prefijo GuildControlRole
-- y los demás clientes lo guardan en member.declared. Si ningún oficial ha fijado el rol
-- a mano (member.roleSource ~= "officer"), member.role pasa a ser el rol declarado.

local ROLE_PREFIX = "GuildControlRole"
local REQUEST_PREFIX = "GCRoleReq"
local BROADCAST_COOLDOWN = 10

profilesModule.ROLES = { "Tanque", "Sanador", "DPS" }
profilesModule.FOCUS = { "PvE", "PvP", "Social" }
local VALID_FOCUS = { PvE = true, PvP = true, Social = true }
local VALID_ROLES = { Tanque = true, Sanador = true, DPS = true }

local lastBroadcast = -BROADCAST_COOLDOWN
local changeListener = nil

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(ROLE_PREFIX)
    C_ChatInfo.RegisterAddonMessagePrefix(REQUEST_PREFIX)
end

-- =========================================================================
-- UTILIDADES
-- =========================================================================
local function GetRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then realm = string.gsub(GetRealmName() or "", "%s+", "") end
    return realm
end

local function NormalizeName(name)
    if not name or name == "" then return nil end
    if not string.find(name, "-", 1, true) then name = name .. "-" .. GetRealm() end
    return (string.gsub(name, "%s+", ""))
end
profilesModule.NormalizeName = NormalizeName

function profilesModule.GetMyFullName()
    return NormalizeName(UnitName("player"))
end

function profilesModule.SetChangeListener(fn)
    changeListener = fn
end

local function NotifyChange()
    if changeListener then changeListener() end
end

-- =========================================================================
-- PERFIL (OFICIAL O JUGADOR)
-- =========================================================================
function profilesModule.GetMyRankIndex()
    if not IsInGuild() then return nil end
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex
end

function profilesModule.GetOfficerRankIndex()
    local value = GuildControlDB.settings and GuildControlDB.settings.officerRankIndex
    return tonumber(value) or 1
end

-- Rangos de la hermandad: { {index = 0, name = "Maestro"}, ... } (0 = el más alto)
function profilesModule.GetGuildRanks()
    local ranks = {}
    local num = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    for i = 1, num do
        table.insert(ranks, { index = i - 1, name = GuildControlGetRankName(i) or (L["Rango "] .. i) })
    end
    return ranks
end

function profilesModule.IsOfficer()
    -- Sin hermandad todo queda disponible (no hay nada que proteger)
    if not IsInGuild() then return true end
    local isGameOfficer = (C_GuildInfo and C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer())
        or (IsGuildOfficer and IsGuildOfficer())
    if isGameOfficer then return true end
    local rankIndex = profilesModule.GetMyRankIndex()
    if rankIndex == nil then return true end   -- el roster aún no ha cargado
    return rankIndex <= profilesModule.GetOfficerRankIndex()
end

-- Rangos (rankIndex, 0 = maestro) con permiso de chat de oficiales según la configuración
-- de rangos del juego. Se cachea unos segundos porque se consulta para cada miembro.
local officerRanksCache, officerRanksCacheAt = nil, -60
function profilesModule.GetOfficerPermissionRanks()
    if officerRanksCache and GetTime() - officerRanksCacheAt < 30 then return officerRanksCache end
    local set = {}
    local num = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    if C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags then
        for rankOrder = 1, num do
            local ok, flags = pcall(C_GuildInfo.GuildControlGetRankFlags, rankOrder)
            -- Permisos 3 y 4: escuchar y hablar en el chat de oficiales
            if ok and type(flags) == "table" and (flags[3] or flags[4]) then set[rankOrder - 1] = true end
        end
    end
    officerRanksCache, officerRanksCacheAt = set, GetTime()
    return set
end

-- ¿Este rango es de oficial? Por el rango mínimo configurado o por permiso de chat de oficiales
function profilesModule.IsOfficerRank(rankIndex)
    if rankIndex == nil then return false end
    return rankIndex <= profilesModule.GetOfficerRankIndex() or profilesModule.GetOfficerPermissionRanks()[rankIndex] == true
end

-- Para otros jugadores solo se puede comprobar el rango (member.rankIndex)
function profilesModule.IsOfficerName(fullName)
    local m = fullName and GuildControlDB.members[NormalizeName(fullName)]
    return m ~= nil and profilesModule.IsOfficerRank(m.rankIndex)
end

function profilesModule.GetProfile()
    return profilesModule.IsOfficer() and "officer" or "player"
end

-- =========================================================================
-- MI PERFIL (POR PERSONAJE)
-- =========================================================================
function profilesModule.GetMyProfile()
    if type(GuildControlDB.myProfiles) ~= "table" then GuildControlDB.myProfiles = {} end
    local key = profilesModule.GetMyFullName()
    local profile = GuildControlDB.myProfiles[key]
    if not profile then
        profile = { main = nil, secondary = nil, spec = "", note = "" }
        GuildControlDB.myProfiles[key] = profile
    end
    return profile
end

local function Clean(text, maxLen)
    text = strtrim(tostring(text or ""))
    text = string.gsub(text, "[|;]", "")   -- separadores del mensaje
    return string.sub(text, 1, maxLen)
end

-- Guarda una declaración en la ficha del miembro. "at" es la fecha (time()) en que el
-- jugador la guardó: una declaración más antigua nunca pisa a una más nueva.
-- extra = { charType = "main"|"alt", mainName = "Nombre del principal", focus = "PvE"|"PvP"|"Social", offSpec = "Especialización" }
local function ApplyDeclared(fullName, main, secondary, spec, note, at, extra)
    local m = GuildControlDB.members[fullName]
    if not m or not main then return false end
    at = tonumber(at) or time()
    extra = extra or {}
    local charType = (extra.charType == "alt" or extra.charType == "main") and extra.charType or nil
    local mainName = charType == "alt" and extra.mainName ~= "" and extra.mainName or nil
    local focus = VALID_FOCUS[extra.focus] and extra.focus or nil
    local offSpec = (extra.offSpec and extra.offSpec ~= "") and extra.offSpec or nil
    local previous = m.declared
    if previous and previous.at and previous.at > at then return false end
    if previous and previous.at == at and previous.main == main and previous.secondary == secondary
        and previous.spec == spec and previous.note == note
        and previous.charType == charType and previous.mainName == mainName and previous.focus == focus and previous.offSpec == offSpec then
        return false
    end
    m.declared = { main = main, secondary = secondary, spec = spec, note = note, at = at,
                   charType = charType, mainName = mainName, focus = focus, offSpec = offSpec }
    -- El enfoque declarado es el que muestra la columna Enfoque
    if focus then m.focus = focus end
    if m.roleSource ~= "officer" then
        m.role = main
        m.roleSource = "declared"
    end
    return true
end

local function ProfileExtra(profile)
    return { charType = profile.charType, mainName = profile.mainName, focus = profile.focus, offSpec = profile.offSpec }
end

-- Los personajes de esta misma cuenta comparten SavedVariables: sus perfiles se aplican
-- directamente, sin depender de que estén conectados a la vez.
function profilesModule.ApplyAccountProfiles()
    if type(GuildControlDB.myProfiles) ~= "table" then return false end
    local changed = false
    for fullName, profile in pairs(GuildControlDB.myProfiles) do
        if profile.main and ApplyDeclared(fullName, profile.main, profile.secondary, profile.spec, profile.note,
            profile.savedAt or 0, ProfileExtra(profile)) then
            changed = true
        end
    end
    if changed then NotifyChange() end
    return changed
end

-- Guarda mi perfil, lo aplica a mi propia ficha y lo envía a la hermandad.
-- charType = "main" (personaje principal) o "alt"; mainName = principal si es un alter.
function profilesModule.SaveMyProfile(main, secondary, spec, note, charType, mainName, focus, offSpec)
    local profile = profilesModule.GetMyProfile()
    profile.main = VALID_ROLES[main] and main or nil
    profile.secondary = (VALID_ROLES[secondary] and secondary ~= profile.main) and secondary or nil
    profile.spec = Clean(spec, 30)
    profile.note = Clean(note, 80)
    profile.charType = charType == "alt" and "alt" or "main"
    profile.mainName = profile.charType == "alt" and Clean(mainName, 40) or nil
    profile.focus = VALID_FOCUS[focus] and focus or nil
    profile.offSpec = Clean(offSpec, 30)
    if profile.offSpec == "" or profile.offSpec == profile.spec then profile.offSpec = nil end
    profile.savedAt = time()
    ApplyDeclared(profilesModule.GetMyFullName(), profile.main, profile.secondary, profile.spec, profile.note,
        profile.savedAt, ProfileExtra(profile))
    profilesModule.Broadcast(true)
    NotifyChange()
end

local function SendRole(msg)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(ROLE_PREFIX, msg, "GUILD")
    end
end

-- Mi declaración: "v2;principal;secundario;especialización;nota;fecha;main|alt;principal"
function profilesModule.Broadcast(force)
    if not IsInGuild() then return end
    if not force and GetTime() - lastBroadcast < BROADCAST_COOLDOWN then return end
    local profile = profilesModule.GetMyProfile()
    if not profile.main then return end
    lastBroadcast = GetTime()
    SendRole(table.concat({ "v2", profile.main, profile.secondary or "", profile.spec or "",
        profile.note or "", tostring(profile.savedAt or time()), profile.charType or "", profile.mainName or "", profile.focus or "", profile.offSpec or "" }, ";"))
end

function profilesModule.RequestRoles()
    if IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(REQUEST_PREFIX, "REQ", "GUILD")
    end
end

-- -------------------------------------------------------------------------
-- Reenvío: cuando alguien pide los roles, un cliente que los conozca reenvía
-- todas las declaraciones guardadas ("R;Nombre-Reino;principal;secundario;espec;nota;fecha").
-- Así un oficial recibe el rol aunque el jugador ya no esté conectado.
-- Espera un tiempo aleatorio y se cancela si otro cliente empieza a reenviar antes.
-- -------------------------------------------------------------------------
local RELAY_INTERVAL = 0.25
local relayTimer, relayTicker = nil, nil

local function CancelRelay()
    if relayTimer then relayTimer:Cancel() end
    relayTimer = nil
end

local function StartRelay()
    local queue = {}
    for fullName, m in pairs(GuildControlDB.members) do
        local d = m.declared
        if d and d.main then
            local function Build(note)
                return table.concat({ "R", fullName, d.main, d.secondary or "", d.spec or "",
                    note, tostring(d.at or 0), d.charType or "", d.mainName or "", d.focus or "", d.offSpec or "" }, ";")
            end
            -- Un mensaje de addon admite 255 bytes: si no cabe, se recorta la nota
            local msg = Build(d.note or "")
            if #msg > 250 then
                msg = Build(string.sub(d.note or "", 1, math.max(0, #(d.note or "") - (#msg - 250))))
            end
            table.insert(queue, msg)
        end
    end
    if #queue == 0 or relayTicker then return end
    relayTicker = C_Timer.NewTicker(RELAY_INTERVAL, function()
        local msg = table.remove(queue, 1)
        if msg then SendRole(msg) end
        if #queue == 0 then
            relayTicker:Cancel()
            relayTicker = nil
        end
    end)
end

local function ScheduleRelay()
    if relayTimer or relayTicker then return end
    relayTimer = C_Timer.NewTimer(2 + math.random() * 4, function()
        relayTimer = nil
        StartRelay()
    end)
end

-- Texto para tooltips y vistas previas, o nil si no ha declarado nada
function profilesModule.GetDeclaredText(m)
    local d = m and m.declared
    if not d or not d.main then return nil end
    local text = L[d.main]
    if d.secondary then text = text .. L[" (secundario "] .. L[d.secondary] .. ")" end
    if d.spec and d.spec ~= "" then text = text .. " · " .. d.spec end
    if d.offSpec and d.offSpec ~= "" then text = text .. L[" · Off: "] .. d.offSpec end
    return text
end

-- "Personaje principal", "Alter de Nombre" o nil si no lo indicó
function profilesModule.GetCharTypeText(m)
    local d = m and m.declared
    if not d or not d.charType then return nil end
    if d.charType == "alt" then
        return d.mainName and (L["Alter de "] .. d.mainName) or L["Alter"]
    end
    return L["Personaje principal"]
end

-- Un oficial fija el rol a mano: deja de seguir el declarado
function profilesModule.MarkRoleSetByOfficer(fullName)
    local m = GuildControlDB.members[fullName]
    if m then m.roleSource = "officer" end
end

-- Vuelve a usar el rol que declaró el jugador
function profilesModule.UseDeclaredRole(fullName)
    local m = GuildControlDB.members[fullName]
    if m and m.declared and m.declared.main then
        m.role = m.declared.main
        m.roleSource = "declared"
        return true
    end
    return false
end

-- Cuántos miembros han declarado su rol
function profilesModule.CountDeclared()
    local count, total = 0, 0
    for _, m in pairs(GuildControlDB.members or {}) do
        total = total + 1
        if m.declared and m.declared.main then count = count + 1 end
    end
    return count, total
end

-- =========================================================================
-- EVENTOS
-- =========================================================================
local function ParseRoleFields(main, secondary, spec, note)
    if not VALID_ROLES[main] then return nil end
    if not VALID_ROLES[secondary] or secondary == main then secondary = nil end
    return main, secondary, Clean(spec, 30), Clean(note, 80)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if not GuildControlDB or not GuildControlDB.members then return end

    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin or isReloadingUi then
            C_Timer.After(12, function()
                profilesModule.ApplyAccountProfiles()
                profilesModule.Broadcast(true)
                profilesModule.RequestRoles()
            end)
        end
        return
    end

    local prefix, msg, channel, sender = ...
    if prefix ~= ROLE_PREFIX and prefix ~= REQUEST_PREFIX then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    if channel ~= "GUILD" or not msg or not sender then return end
    local fullSender = NormalizeName(sender)
    if fullSender == profilesModule.GetMyFullName() then return end

    if prefix == REQUEST_PREFIX then
        profilesModule.Broadcast(false)
        ScheduleRelay()
        return
    end

    local fields = { strsplit(";", msg) }
    local changed = false
    if fields[1] == "R" then
        -- Otro cliente ya está reenviando: no hace falta que lo haga yo
        CancelRelay()
        local main, secondary, spec, note = ParseRoleFields(fields[3], fields[4], fields[5], fields[6])
        if main and fields[2] then
            changed = ApplyDeclared(NormalizeName(fields[2]), main, secondary, spec, note, tonumber(fields[7]) or 0,
                { charType = fields[8], mainName = Clean(fields[9], 40), focus = fields[10], offSpec = Clean(fields[11], 30) })
        end
    elseif fields[1] == "v1" or fields[1] == "v2" then
        local main, secondary, spec, note = ParseRoleFields(fields[2], fields[3], fields[4], fields[5])
        if main then
            -- v1 no llevaba fecha: se considera actual
            changed = ApplyDeclared(fullSender, main, secondary, spec, note, tonumber(fields[6]) or time(),
                { charType = fields[7], mainName = Clean(fields[8], 40), focus = fields[9], offSpec = Clean(fields[10], 30) })
        end
    end
    if changed then NotifyChange() end
end)
