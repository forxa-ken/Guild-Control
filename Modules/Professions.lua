local addonName, addonTable = ...
local L = addonTable.L

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
-- Las fuentes de toda la hermandad (C_Club y lista de profesiones) se recorren como mucho
-- una vez por minuto: GUILD_ROSTER_UPDATE llega muy a menudo y cada vuelta crea tablas
local CLUB_SCAN_COOLDOWN = 60
local lastClubScan = -CLUB_SCAN_COOLDOWN
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
    return addonTable.NormalizeName(name)   -- Core: "Nombre-Reino" sin apellido
end

-- "Herrería 100" -> "Herrería"
local function BaseName(profText)
    if not profText then return nil end
    return (string.gsub(profText, "%s+%d+$", ""))
end

-- Nombre de una profesión en el idioma de este cliente a partir de su ID de línea de
-- habilidad (los demás pueden jugar en otro idioma: "Leatherworking" -> "Peletería")
local function LocalizedProfessionName(id)
    id = tonumber(id)
    if not id or not C_TradeSkillUI then return nil end
    if C_TradeSkillUI.GetTradeSkillDisplayName then
        local ok, name = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, id)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    if C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, id)
        if ok and info and info.professionName and info.professionName ~= "" then return info.professionName end
    end
    return nil
end
profModule.LocalizedProfessionName = LocalizedProfessionName

-- Profesiones principales por ID con sus nombres conocidos (inglés y variantes en español).
-- Las fuentes no siempre dan el nombre en el idioma del cliente (C_Club o la lista de
-- profesiones de la hermandad pueden dar "Herbalism" en un cliente en español): por el ID se
-- sabe que "Herbalism" y "Botánica" son la misma y se guarda con el nombre de este cliente.
profModule.PRIMARY = {
    { id = 171, en = "Alchemy", es = { "Alquimia" } },
    { id = 164, en = "Blacksmithing", es = { "Herrería" } },
    { id = 333, en = "Enchanting", es = { "Encantamiento" } },
    { id = 202, en = "Engineering", es = { "Ingeniería" } },
    { id = 182, en = "Herbalism", es = { "Herboristería", "Botánica", "Herbalismo" } },
    { id = 773, en = "Inscription", es = { "Inscripción" } },
    { id = 755, en = "Jewelcrafting", es = { "Joyería" } },
    { id = 165, en = "Leatherworking", es = { "Peletería" } },
    { id = 186, en = "Mining", es = { "Minería" } },
    { id = 393, en = "Skinning", es = { "Desuello", "Desollar" } },
    { id = 197, en = "Tailoring", es = { "Sastrería" } },
}

local idByName = nil
local function ProfessionIdByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if not idByName then
        idByName = {}
        for _, prof in ipairs(profModule.PRIMARY) do
            idByName[string.lower(prof.en)] = prof.id
            for _, esName in ipairs(prof.es) do idByName[string.lower(esName)] = prof.id end
            local localized = LocalizedProfessionName(prof.id)
            if localized then idByName[string.lower(localized)] = prof.id end
        end
    end
    return idByName[string.lower(name)]
end
profModule.ProfessionIdByName = ProfessionIdByName

-- Nombre con el que se guarda una profesión en este cliente
function profModule.DisplayName(id)
    local localized = LocalizedProfessionName(id)
    if localized then return localized end
    local isSpanish = GetLocale and string.sub(GetLocale(), 1, 2) == "es"
    for _, prof in ipairs(profModule.PRIMARY) do
        if prof.id == id then return isSpanish and prof.es[1] or prof.en end
    end
    return nil
end

-- Clave para comparar dos profesiones: su ID si se conoce; si no, el nombre
local function ProfKey(profText)
    local base = BaseName(profText)
    return ProfessionIdByName(base) or base
end

local function FormatProfession(name, rank)
    if not name or name == "" then return nil end
    -- Siempre con el nombre de este cliente (así no salen dos veces en dos idiomas)
    local id = ProfessionIdByName(name)
    if id then name = profModule.DisplayName(id) or name end
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
    -- La misma profesión dos veces: se queda una
    if new2 ~= NONE and ProfKey(new1) == ProfKey(new2) then new2 = NONE end
    if m.prof1 == new1 and m.prof2 == new2 then return false end
    m.prof1, m.prof2 = new1, new2
    return true
end

-- Nivel de "Herrería 100" (0 si no lo tiene)
local function ProfLevel(profText)
    return tonumber(string.match(profText or "", "(%d+)$")) or 0
end

-- Arregla las profesiones guardadas de un miembro: nombre en el idioma de este cliente y sin
-- repetir la misma en las dos columnas (se queda la de más nivel)
function profModule.CleanMember(m)
    local changed = false
    for _, field in ipairs({ "prof1", "prof2" }) do
        local text = m[field]
        if text and text ~= NONE then
            local fixed = FormatProfession(BaseName(text), ProfLevel(text))
            if fixed and fixed ~= text then
                m[field] = fixed
                changed = true
            end
        end
    end
    if m.prof1 and m.prof2 and m.prof1 ~= NONE and m.prof2 ~= NONE and ProfKey(m.prof1) == ProfKey(m.prof2) then
        if ProfLevel(m.prof2) > ProfLevel(m.prof1) then m.prof1 = m.prof2 end
        m.prof2 = NONE
        changed = true
    end
    return changed
end

-- Añade o actualiza una profesión sin borrar la otra (fuentes parciales)
local function MergeMemberProfession(m, profText)
    profText = FormatProfession(BaseName(profText), ProfLevel(profText)) or profText
    local base = ProfKey(profText)
    if ProfKey(m.prof1) == base then
        if m.prof1 == profText then return false end
        m.prof1 = profText
    elseif ProfKey(m.prof2) == base then
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
    return L["Línea "] .. tostring(id)
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
    local me = NormalizeName(UnitName("player"))
    if GuildControlDB.members[me] then GuildControlDB.members[me].profFromAddon = time() end   -- datos propios: mandan
    return SetMemberProfessions(me, p1, p2)
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
    -- Lista compartida con Míticas+ (Core): un solo recorrido de C_Club por minuto
    local infos = addonTable.GetClubMemberInfos and addonTable.GetClubMemberInfos()
    if not infos then return nil end

    local map = {}
    for _, info in ipairs(infos) do
        if info.guid then
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

-- Nivel de un texto "Profesión nivel" (0 si no lo lleva)
local function RankOf(profText)
    return tonumber(string.match(profText or "", "(%d+)$")) or 0
end

-- La comunidad de la hermandad (C_Club) solo rellena: no pisa lo que envía el propio jugador
-- con GuildControl (member.profFromAddon) ni baja el nivel de una profesión ya conocida.
-- En Forever esta fuente puede dar nivel 1 aunque el personaje tenga más.
local function ApplyClubProfessions()
    local map = BuildClubProfessionMap()
    if not map then return false end
    local changed = false
    for fullName, m in pairs(GuildControlDB.members) do
        local entry = m.guid and map[m.guid]
        if entry and not m.profFromAddon then
            for _, profText in ipairs({ entry[1], entry[2] }) do
                if profText then
                    local base = BaseName(profText)
                    local current = (BaseName(m.prof1) == base and m.prof1) or (BaseName(m.prof2) == base and m.prof2)
                    if not current or RankOf(profText) > RankOf(current) then
                        if MergeMemberProfession(m, profText) then changed = true end
                    end
                end
            end
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
                -- Solo rellena: no pisa lo que envía el jugador ni baja un nivel conocido
                local base = profText and BaseName(profText)
                local current = m and base and ((BaseName(m.prof1) == base and m.prof1) or (BaseName(m.prof2) == base and m.prof2))
                if m and profText and not m.profFromAddon and (not current or RankOf(profText) > RankOf(current))
                    and MergeMemberProfession(m, profText) then
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

    if now - lastClubScan >= CLUB_SCAN_COOLDOWN then
        lastClubScan = now
        profModule.ParseGuildTradeSkills()
        ApplyClubProfessions()
        -- Lo ya guardado: mismo idioma y sin la misma profesión en las dos columnas
        local cleaned = false
        for _, m in pairs(GuildControlDB.members or {}) do
            if profModule.CleanMember(m) then cleaned = true end
        end
        if cleaned then RefreshUIIfShown() end
    end

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
            -- Lo que envía el propio jugador manda sobre la comunidad y la lista de la hermandad
            if GuildControlDB.members[fullSender] then GuildControlDB.members[fullSender].profFromAddon = time() end

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
