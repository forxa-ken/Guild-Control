local addonName, addonTable = ...

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
        table.insert(ranks, { index = i - 1, name = GuildControlGetRankName(i) or ("Rango " .. i) })
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

-- Para otros jugadores solo se puede comprobar el rango (member.rankIndex)
function profilesModule.IsOfficerName(fullName)
    local m = fullName and GuildControlDB.members[NormalizeName(fullName)]
    return m and m.rankIndex ~= nil and m.rankIndex <= profilesModule.GetOfficerRankIndex() or false
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

local function ApplyDeclared(fullName, main, secondary, spec, note)
    local m = GuildControlDB.members[fullName]
    if not m then return false end
    m.declared = { main = main, secondary = secondary, spec = spec, note = note, at = time() }
    if main and m.roleSource ~= "officer" then
        m.role = main
        m.roleSource = "declared"
    end
    return true
end

-- Guarda mi perfil, lo aplica a mi propia ficha y lo envía a la hermandad
function profilesModule.SaveMyProfile(main, secondary, spec, note)
    local profile = profilesModule.GetMyProfile()
    profile.main = VALID_ROLES[main] and main or nil
    profile.secondary = (VALID_ROLES[secondary] and secondary ~= profile.main) and secondary or nil
    profile.spec = Clean(spec, 30)
    profile.note = Clean(note, 80)
    ApplyDeclared(profilesModule.GetMyFullName(), profile.main, profile.secondary, profile.spec, profile.note)
    profilesModule.Broadcast(true)
    NotifyChange()
end

-- "v1;principal;secundario;especialización;nota"
function profilesModule.Broadcast(force)
    if not IsInGuild() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    if not force and GetTime() - lastBroadcast < BROADCAST_COOLDOWN then return end
    local profile = profilesModule.GetMyProfile()
    if not profile.main then return end
    lastBroadcast = GetTime()
    local msg = table.concat({ "v1", profile.main, profile.secondary or "", profile.spec or "", profile.note or "" }, ";")
    C_ChatInfo.SendAddonMessage(ROLE_PREFIX, msg, "GUILD")
end

function profilesModule.RequestRoles()
    if IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(REQUEST_PREFIX, "REQ", "GUILD")
    end
end

-- Texto para tooltips y vistas previas, o nil si no ha declarado nada
function profilesModule.GetDeclaredText(m)
    local d = m and m.declared
    if not d or not d.main then return nil end
    local text = d.main
    if d.secondary then text = text .. " (secundario " .. d.secondary .. ")" end
    if d.spec and d.spec ~= "" then text = text .. " · " .. d.spec end
    return text
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
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if not GuildControlDB or not GuildControlDB.members then return end

    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin or isReloadingUi then
            C_Timer.After(12, function()
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
    else
        local version, main, secondary, spec, note = strsplit(";", msg)
        if version ~= "v1" or not VALID_ROLES[main] then return end
        if not VALID_ROLES[secondary] or secondary == main then secondary = nil end
        if ApplyDeclared(fullSender, main, secondary, Clean(spec, 30), Clean(note, 80)) then
            NotifyChange()
        end
    end
end)
