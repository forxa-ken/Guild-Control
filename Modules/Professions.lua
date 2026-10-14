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
profFrame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
profFrame:RegisterEvent("TRADE_SKILL_CLOSE")

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix("GuildControlProf")
    C_ChatInfo.RegisterAddonMessagePrefix("GuildControlReq")
    C_ChatInfo.RegisterAddonMessagePrefix("GuildControlPExp")
end

-- Desglose por expansión (member.profExp): solo se conoce el propio y el de quien use
-- GuildControl, que lo envía con el prefijo GuildControlPExp ("Profesión:id=nivel/max,...").
-- El juego no ofrece este dato para el resto de miembros.
local MAX_ADDON_MSG_BYTES = 250
local expansionDirty = false

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

-- -------------------------------------------------------------------------
-- 1b. DESGLOSE POR EXPANSIÓN
-- -------------------------------------------------------------------------
local function ResolveSkillLineName(id)
    if C_TradeSkillUI then
        if C_TradeSkillUI.GetProfessionInfoBySkillLineID then
            local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, id)
            if ok and info and info.professionName and info.professionName ~= "" then return info.professionName end
        end
        if C_TradeSkillUI.GetTradeSkillDisplayName then
            local ok, name = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, id)
            if ok and name and name ~= "" then return name end
        end
    end
    return "Línea " .. tostring(id)
end

-- Añade una línea de expansión (ProfessionInfo) al mapa padre -> lista
local function AddExpansionEntry(map, info, id)
    if not info or not id or (info.skillLevel or 0) <= 0 then return end
    local parent = info.parentProfessionName
    if not parent or parent == "" then return end
    map[parent] = map[parent] or {}
    table.insert(map[parent], {
        id = id,
        name = info.professionName,
        level = info.skillLevel,
        max = info.maxSkillLevel or 0,
    })
end

local function SortExpansionEntries(map)
    for _, list in pairs(map) do
        table.sort(list, function(a, b) return a.id > b.id end)   -- expansiones recientes primero
    end
end

-- Lee todas las líneas aprendidas del personaje (no necesita la ventana de profesión abierta)
local function CollectMyExpansionSkills()
    local map = {}
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllProfessionTradeSkillLines and C_TradeSkillUI.GetProfessionInfoBySkillLineID) then
        return map
    end
    local ok, lines = pcall(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
    if not ok or type(lines) ~= "table" then return map end

    for _, id in ipairs(lines) do
        local okInfo, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, id)
        if okInfo and info and info.parentProfessionID and info.parentProfessionID ~= 0 then
            AddExpansionEntry(map, info, id)
        end
    end
    SortExpansionEntries(map)
    return map
end

-- Con la ventana de profesión abierta: GetChildProfessionInfos da todas las expansiones de esa profesión
local function CollectOpenProfessionChildren()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetChildProfessionInfos) then return nil end
    -- Ignorar profesiones enlazadas de otro jugador, de hermandad o de NPC
    for _, check in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting", "IsRuneforging" }) do
        local fn = C_TradeSkillUI[check]
        if fn then
            local ok, result = pcall(fn)
            if ok and result then return nil end
        end
    end

    local ok, children = pcall(C_TradeSkillUI.GetChildProfessionInfos)
    if not ok or type(children) ~= "table" or #children == 0 then return nil end

    local map = {}
    for _, info in ipairs(children) do
        AddExpansionEntry(map, info, info.professionID)
    end
    SortExpansionEntries(map)
    return map
end

-- Guarda el desglose propio en GuildControlDB. Devuelve true si cambió algo.
local function StoreMyExpansionSkills(map, replaceAll)
    local m = GuildControlDB.members[NormalizeName(UnitName("player"))]
    if not m or not map or next(map) == nil then return false end

    local before = m.profExp
    local merged = {}
    if not replaceAll and type(before) == "table" then
        for parent, list in pairs(before) do merged[parent] = list end
    end
    for parent, list in pairs(map) do merged[parent] = list end

    local function Serialize(t)
        local parts = {}
        for parent, list in pairs(t or {}) do
            for _, e in ipairs(list) do
                table.insert(parts, parent .. e.id .. "=" .. e.level .. "/" .. e.max)
            end
        end
        table.sort(parts)
        return table.concat(parts, ",")
    end

    if Serialize(before) == Serialize(merged) then return false end
    m.profExp = merged
    return true
end

function profModule.UpdateMyExpansionSkills()
    local changed = StoreMyExpansionSkills(CollectMyExpansionSkills(), true)
    local openMap = CollectOpenProfessionChildren()
    if openMap and StoreMyExpansionSkills(openMap, false) then changed = true end
    return changed
end

-- Mensajes "Profesión:id=nivel/max,..." (uno por profesión, recortados al límite de bytes)
local function BuildExpansionMessages()
    local m = GuildControlDB.members[NormalizeName(UnitName("player"))]
    local messages = {}
    if not m or type(m.profExp) ~= "table" then return messages end

    for parent, list in pairs(m.profExp) do
        local msg = parent .. ":"
        local first = true
        for _, e in ipairs(list) do
            local part = (first and "" or ",") .. e.id .. "=" .. e.level .. "/" .. e.max
            if #msg + #part > MAX_ADDON_MSG_BYTES then break end
            msg = msg .. part
            first = false
        end
        if not first then table.insert(messages, msg) end
    end
    return messages
end

local function ParseExpansionMessage(msg)
    local parent, body = string.match(msg, "^([^:]+):(.*)$")
    if not parent or not body then return nil end
    local list = {}
    for id, level, max in string.gmatch(body, "(%d+)=(%d+)/(%d+)") do
        table.insert(list, { id = tonumber(id), level = tonumber(level), max = tonumber(max) })
    end
    return parent, list
end

-- Para la vista previa: { {parent = "Minería", entries = { {name, level, max}, ... }}, ... } o nil
function profModule.GetExpansionBreakdown(fullName)
    local m = fullName and GuildControlDB.members[fullName]
    if not m or type(m.profExp) ~= "table" or next(m.profExp) == nil then return nil end

    local result = {}
    for parent, list in pairs(m.profExp) do
        local entries = {}
        for _, e in ipairs(list) do
            table.insert(entries, { name = e.name or ResolveSkillLineName(e.id), level = e.level, max = e.max })
        end
        table.insert(result, { parent = parent, entries = entries })
    end
    table.sort(result, function(a, b) return a.parent < b.parent end)
    return result
end

function profModule.BroadcastMyProfessions()
    if not IsInGuild() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local p1, p2 = profModule.GetMyProfessions()
    if p1 == NONE and p2 == NONE then return end
    lastBroadcast = GetTime()
    C_ChatInfo.SendAddonMessage("GuildControlProf", p1 .. "," .. p2, "GUILD")

    for _, msg in ipairs(BuildExpansionMessages()) do
        C_ChatInfo.SendAddonMessage("GuildControlPExp", msg, "GUILD")
    end
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

-- force = true: enviar al resto aunque no haya cambios (al entrar en el juego)
function profModule.ScanMyProfessions(force)
    if not IsInGuild() then return end
    local changed = ApplyMyProfessions()
    if profModule.UpdateMyExpansionSkills() then changed = true end
    if changed then
        RefreshUIIfShown()
    end
    if changed or force then
        profModule.BroadcastMyProfessions()
    end
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
                profModule.ScanMyProfessions(true)
                profModule.RequestGuildProfessions()
            end)
        end
    elseif event == "TRADE_SKILL_SHOW" or event == "SKILL_LINES_CHANGED" then
        profModule.ScanMyProfessions()
    elseif event == "TRADE_SKILL_LIST_UPDATE" then
        -- Con la ventana abierta se actualiza el desglose; se envía al cerrarla para no saturar el canal
        if StoreMyExpansionSkills(CollectOpenProfessionChildren(), false) then
            expansionDirty = true
            RefreshUIIfShown()
        end
    elseif event == "TRADE_SKILL_CLOSE" then
        if expansionDirty then
            expansionDirty = false
            profModule.BroadcastMyProfessions()
        end
    elseif event == "GUILD_TRADESKILL_UPDATE" then
        if profModule.ParseGuildTradeSkills() then RefreshUIIfShown() end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if IsSecret(prefix) or IsSecret(msg) or IsSecret(sender) then return end
        if channel ~= "GUILD" then return end

        local fullSender = NormalizeName(sender)
        local isSelf = fullSender == NormalizeName(UnitName("player"))

        if prefix == "GuildControlReq" then
            if GetTime() - lastBroadcast >= BROADCAST_COOLDOWN then
                profModule.BroadcastMyProfessions()
            end
        elseif prefix == "GuildControlProf" and msg and not isSelf then
            local p1, p2 = strsplit(",", msg)
            if p1 == "" then p1 = nil end
            if p2 == "" then p2 = nil end
            local changed = SetMemberProfessions(fullSender, p1, p2)

            -- Quitar del desglose las profesiones que ya no tiene
            local m = GuildControlDB.members[fullSender]
            if m and type(m.profExp) == "table" then
                local keep = { [BaseName(p1 or NONE)] = true, [BaseName(p2 or NONE)] = true }
                for parent in pairs(m.profExp) do
                    if not keep[parent] then
                        m.profExp[parent] = nil
                        changed = true
                    end
                end
            end
            if changed then RefreshUIIfShown() end
        elseif prefix == "GuildControlPExp" and msg and not isSelf then
            local m = GuildControlDB.members[fullSender]
            local parent, list = ParseExpansionMessage(msg)
            if m and parent and #list > 0 then
                if type(m.profExp) ~= "table" then m.profExp = {} end
                m.profExp[parent] = list
                RefreshUIIfShown()
            end
        end
    end
end)
