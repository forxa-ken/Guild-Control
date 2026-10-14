local addonName, addonTable = ...

addonTable.Professions = {}
local profModule = addonTable.Professions

-- Las profesiones se combinan desde cuatro fuentes:
--   1. Las profesiones propias (GetProfessions), que además se anuncian al resto.
--   2. Mensajes de addon entre clientes con GuildControl (GuildControlReq / GuildControlProf).
--   3. La información de miembros de la comunidad de hermandad (C_Club), que incluye profesiones.
--   4. La lista de profesiones de hermandad (GetGuildTradeSkillInfo), solo de artesanía.
-- Las fuentes 1-3 traen las dos profesiones a la vez y sustituyen los valores; la 4 solo
-- completa huecos porque no incluye profesiones de recolección.

local NONE = "Ninguna"
local TRADESKILL_QUERY_COOLDOWN = 60   -- segundos entre peticiones QueryGuildTradeSkill
local BROADCAST_COOLDOWN = 10          -- segundos mínimos entre respuestas a GuildControlReq

local lastTradeSkillQuery = -TRADESKILL_QUERY_COOLDOWN
local lastBroadcast = -BROADCAST_COOLDOWN

local profFrame = CreateFrame("Frame")
profFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
profFrame:RegisterEvent("TRADE_SKILL_SHOW")
profFrame:RegisterEvent("SKILL_LINES_CHANGED")
profFrame:RegisterEvent("GUILD_TRADESKILL_UPDATE")
profFrame:RegisterEvent("CHAT_MSG_ADDON")

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix("GuildControlProf")
    C_ChatInfo.RegisterAddonMessagePrefix("GuildControlReq")
end

-- =========================================================================
-- UTILIDADES
-- =========================================================================
local function GetRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = string.gsub(GetRealmName() or "", "%s+", "")
    end
    return realm
end

-- Convierte "Nombre" o "Nombre-Reino" en la clave de GuildControlDB.members
local function NormalizeName(name)
    if not name or name == "" then return nil end
    if not string.find(name, "-", 1, true) then
        name = name .. "-" .. GetRealm()
    end
    return (string.gsub(name, "%s+", ""))
end

-- "Herrería 100" -> "Herrería"
local function BaseName(profText)
    if not profText then return nil end
    return (string.gsub(profText, "%s+%d+$", ""))
end

local function FormatProfession(name, rank)
    if not name or name == "" then return nil end
    rank = tonumber(rank)
    if rank and rank > 0 then
        return name .. " " .. rank
    end
    return name
end

local function RefreshUIIfShown()
    local ui = addonTable.UI
    if ui and ui.RefreshList and ui.IsShown and ui.IsShown() then
        ui.RefreshList()
    end
end

-- Sustituye las dos profesiones de un miembro (fuentes completas)
local function SetMemberProfessions(fullName, p1, p2)
    local m = fullName and GuildControlDB.members[fullName]
    if not m then return false end
    local new1, new2 = p1 or NONE, p2 or NONE
    if m.prof1 == new1 and m.prof2 == new2 then return false end
    m.prof1, m.prof2 = new1, new2
    return true
end

-- Añade o actualiza una profesión sin borrar la otra (fuentes parciales)
local function MergeMemberProfession(m, profText)
    local base = BaseName(profText)
    if BaseName(m.prof1) == base then
        if m.prof1 == profText then return false end
        m.prof1 = profText
    elseif BaseName(m.prof2) == base then
        if m.prof2 == profText then return false end
        m.prof2 = profText
    elseif not m.prof1 or m.prof1 == NONE then
        m.prof1 = profText
    elseif not m.prof2 or m.prof2 == NONE then
        m.prof2 = profText
    else
        return false
    end
    return true
end

-- =========================================================================
-- 1. PROFESIONES PROPIAS
-- =========================================================================
function profModule.GetMyProfessions()
    local prof1, prof2 = GetProfessions()
    local p1, p2
    if prof1 then
        local name, _, rank = GetProfessionInfo(prof1)
        p1 = FormatProfession(name, rank)
    end
    if prof2 then
        local name, _, rank = GetProfessionInfo(prof2)
        p2 = FormatProfession(name, rank)
    end
    return p1 or NONE, p2 or NONE
end

function profModule.BroadcastMyProfessions()
    if not IsInGuild() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local p1, p2 = profModule.GetMyProfessions()
    if p1 == NONE and p2 == NONE then return end
    lastBroadcast = GetTime()
    C_ChatInfo.SendAddonMessage("GuildControlProf", p1 .. "," .. p2, "GUILD")
end

function profModule.RequestGuildProfessions()
    if IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage("GuildControlReq", "REQ", "GUILD")
    end
end

-- Nada más entrar GetProfessions() puede venir vacío aunque el personaje tenga profesiones:
-- en ese caso no se pisa lo guardado. Devuelve true si cambió algo.
local function ApplyMyProfessions()
    local p1, p2 = profModule.GetMyProfessions()
    if p1 == NONE and p2 == NONE then return false end
    return SetMemberProfessions(NormalizeName(UnitName("player")), p1, p2)
end

function profModule.ScanMyProfessions()
    if not IsInGuild() then return end
    if ApplyMyProfessions() then
        RefreshUIIfShown()
    end
    profModule.BroadcastMyProfessions()
end

-- =========================================================================
-- 3. COMUNIDAD DE HERMANDAD (C_Club)
-- =========================================================================
-- Devuelve un mapa guid -> {p1, p2} con los miembros que tienen datos de profesión
local function BuildClubProfessionMap()
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers and C_Club.GetMemberInfo) then return nil end
    local clubId = C_Club.GetGuildClubId()
    if not clubId then return nil end

    local ok, memberIds = pcall(C_Club.GetClubMembers, clubId)
    if not ok or type(memberIds) ~= "table" then return nil end

    local map = {}
    for _, memberId in ipairs(memberIds) do
        local okInfo, info = pcall(C_Club.GetMemberInfo, clubId, memberId)
        if okInfo and info and info.guid then
            local p1 = FormatProfession(info.profession1Name, info.profession1Rank)
            local p2 = FormatProfession(info.profession2Name, info.profession2Rank)
            if p1 or p2 then
                map[info.guid] = { p1, p2 }
            end
        end
    end
    return map
end

function profModule.GetProfessionsFromClub(guid)
    local map = guid and BuildClubProfessionMap()
    local entry = map and map[guid]
    if entry then return entry[1], entry[2] end
    return nil, nil
end

local function ApplyClubProfessions()
    local map = BuildClubProfessionMap()
    if not map then return false end
    local changed = false
    for fullName, m in pairs(GuildControlDB.members) do
        local entry = m.guid and map[m.guid]
        if entry and SetMemberProfessions(fullName, entry[1], entry[2]) then
            changed = true
        end
    end
    return changed
end

-- =========================================================================
-- 4. LISTA DE PROFESIONES DE HERMANDAD (asíncrona: GUILD_TRADESKILL_UPDATE)
-- =========================================================================
local GetNumTradeSkills = GetNumGuildTradeSkill or GetNumGuildTradeSkills

function profModule.ParseGuildTradeSkills()
    if not GetNumTradeSkills or not GetGuildTradeSkillInfo then return false end

    local okNum, numSkills = pcall(GetNumTradeSkills)
    if not okNum or not numSkills or numSkills == 0 then return false end

    local changed = false
    local currentProf = nil
    for i = 1, numSkills do
        -- skillID, isCollapsed, iconTexture, headerName, numOnline, numVisible, numPlayers,
        -- playerName, playerNameWithRealm, class, online, zone, skill, ...
        local ok, skillID, isCollapsed, _, headerName, _, _, _, playerName, playerNameWithRealm, _, _, _, skill = pcall(GetGuildTradeSkillInfo, i)
        if ok then
            if headerName then
                currentProf = headerName
                -- Las cabeceras plegadas ocultan a sus jugadores: se despliegan y llega otro GUILD_TRADESKILL_UPDATE
                if isCollapsed and skillID and ExpandGuildTradeSkillHeader then
                    pcall(ExpandGuildTradeSkillHeader, skillID)
                end
            elseif currentProf then
                local fullName = NormalizeName(playerNameWithRealm or playerName)
                local m = fullName and GuildControlDB.members[fullName]
                local profText = FormatProfession(currentProf, skill)
                if m and profText and MergeMemberProfession(m, profText) then
                    changed = true
                end
            end
        end
    end
    return changed
end

-- =========================================================================
-- ESCANEO GENERAL (lo llama Core tras sincronizar el roster)
-- =========================================================================
function profModule.Scan()
    if not IsInGuild() then return end

    local now = GetTime()
    if QueryGuildTradeSkill and now - lastTradeSkillQuery >= TRADESKILL_QUERY_COOLDOWN then
        lastTradeSkillQuery = now
        QueryGuildTradeSkill()
    end

    profModule.ParseGuildTradeSkills()
    ApplyClubProfessions()

    -- Las profesiones propias siempre tienen prioridad
    ApplyMyProfessions()
end

-- =========================================================================
-- EVENTOS
-- =========================================================================
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

profFrame:SetScript("OnEvent", function(self, event, ...)
    if not GuildControlDB or not GuildControlDB.members then return end

    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin or isReloadingUi then
            -- Las profesiones y el canal de hermandad tardan unos segundos en estar listos
            C_Timer.After(10, function()
                profModule.ScanMyProfessions()
                profModule.RequestGuildProfessions()
            end)
        end
    elseif event == "TRADE_SKILL_SHOW" or event == "SKILL_LINES_CHANGED" then
        profModule.ScanMyProfessions()
    elseif event == "GUILD_TRADESKILL_UPDATE" then
        if profModule.ParseGuildTradeSkills() then RefreshUIIfShown() end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if IsSecret(prefix) or IsSecret(msg) or IsSecret(sender) then return end
        if channel ~= "GUILD" then return end

        if prefix == "GuildControlReq" then
            if GetTime() - lastBroadcast >= BROADCAST_COOLDOWN then
                profModule.BroadcastMyProfessions()
            end
        elseif prefix == "GuildControlProf" and sender and msg then
            local p1, p2 = strsplit(",", msg)
            if p1 == "" then p1 = nil end
            if p2 == "" then p2 = nil end
            if SetMemberProfessions(NormalizeName(sender), p1, p2) then
                RefreshUIIfShown()
            end
        end
    end
end)
