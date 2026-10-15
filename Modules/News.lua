local addonName, addonTable = ...
local L = addonTable.L

addonTable.News = {}
local newsModule = addonTable.News

-- Datos de la pestaña Resumen (sin frames): noticias de la hermandad del juego (logros,
-- jefes derrotados, botín), altas y bajas del historial del addon, próximas bandas de los
-- rosters y cifras generales.

local HISTORY_DAYS = 30   -- altas y bajas que entran en las noticias

-- Tipos de noticia del juego (constantes globales, con su valor por si faltan)
local NEWS = {
    ITEM_LOOTED = NEWS_ITEM_LOOTED or 0,
    ITEM_CRAFTED = NEWS_ITEM_CRAFTED or 1,
    ITEM_PURCHASED = NEWS_ITEM_PURCHASED or 2,
    GUILD_LEVEL = NEWS_GUILD_LEVEL or 3,
    GUILD_ACHIEVEMENT = NEWS_GUILD_ACHIEVEMENT or 4,
    PLAYER_ACHIEVEMENT = NEWS_PLAYER_ACHIEVEMENT or 5,
    DUNGEON_ENCOUNTER = NEWS_DUNGEON_ENCOUNTER or 6,
    GUILD_EVENT = NEWS_GUILD_EVENT or 7,
    GUILD_CREATE = NEWS_GUILD_CREATE or 8,
}

local ICONS = {
    boss = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    join = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",
    leave = "Interface\\Icons\\Ability_Rogue_FeignDeath",
    other = "Interface\\Icons\\INV_Misc_Note_01",
    achievement = "Interface\\Icons\\Achievement_GuildPerk_MobileBanking",
    loot = "Interface\\Icons\\INV_Misc_Bag_10",
}

-- Filtros de la pestaña: qué clases de noticia entran en cada uno
newsModule.FILTERS = {
    { key = "guildAchievement", label = "Logros hermandad", width = 120 },
    { key = "achievement", label = "Logros personajes", width = 120 },
    { key = "boss", label = "Jefes" },
    { key = "loot", label = "Botín" },
    { key = "join", label = "Altas" },
    { key = "leave", label = "Bajas" },
}
local FILTER_KINDS = {
    guildAchievement = { guildAchievement = true },
    achievement = { achievement = true },
    boss = { boss = true },
    loot = { loot = true },
    join = { join = true },
    leave = { leave = true },
}

local listeners = {}

function newsModule.AddListener(fn)
    table.insert(listeners, fn)
end

local function Notify()
    for _, fn in ipairs(listeners) do fn() end
end

-- Pide al servidor las noticias de la hermandad (llegan con GUILD_NEWS_UPDATE)
function newsModule.Request()
    if not IsInGuild() then return end
    if C_GuildInfo and C_GuildInfo.QueryGuildNews then
        pcall(C_GuildInfo.QueryGuildNews)
    elseif QueryGuildNews then
        pcall(QueryGuildNews)
    end
end

-- =========================================================================
-- NOTICIAS
-- =========================================================================
local function ShortName(name)
    if not name or name == "" then return L["Alguien"] end
    return string.match(name, "^([^-]+)") or name
end

local function ItemIcon(itemID)
    if not itemID then return nil end
    if C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok and icon then return icon end
    end
    return GetItemIcon and GetItemIcon(itemID) or nil
end

-- Fecha de una noticia del juego: día y mes empiezan en 0, el año cuenta desde 2000
local function NewsDate(info)
    if not info.day or not info.month then return "", "00000000" end
    local year = info.year or 0
    if year < 100 then year = 2000 + year end
    local day, month = info.day + 1, info.month + 1
    return string.format("%02d/%02d", day, month), string.format("%04d%02d%02d", year, month, day)
end

-- Índice nombre -> id de todos los logros (de hermandad y de personaje). Se construye una
-- sola vez, la primera vez que hace falta.
local achievementNameIndex = nil
function newsModule.FindAchievementByName(name)
    if not name or name == "" then return nil end
    if not achievementNameIndex then
        achievementNameIndex = {}
        local lists = {}
        if GetGuildCategoryList then table.insert(lists, GetGuildCategoryList()) end
        if GetCategoryList then table.insert(lists, GetCategoryList()) end
        for _, categories in ipairs(lists) do
            for _, categoryId in ipairs(categories or {}) do
                local num = GetCategoryNumAchievements(categoryId, true) or 0
                for i = 1, num do
                    local id, achName = GetAchievementInfo(categoryId, i)
                    if id and achName and not achievementNameIndex[achName] then achievementNameIndex[achName] = id end
                end
            end
        end
    end
    return achievementNameIndex[name]
end

local function GuildNewsItems()
    local items = {}
    local getInfo = C_GuildInfo and C_GuildInfo.GetGuildNewsInfo
    local num = GetNumGuildNews and GetNumGuildNews() or 0
    if not getInfo then return items end

    for i = 1, num do
        local ok, info = pcall(getInfo, i)
        if ok and info and not info.isHeader then
            local who = ShortName(info.whoText)
            local what = info.whatText or ""
            local item = { icon = ICONS.other, title = what, detail = "" , who = who }
            local t = info.newsType

            if t == NEWS.PLAYER_ACHIEVEMENT or t == NEWS.GUILD_ACHIEVEMENT then
                -- Identificador del logro: del enlace, de newsID y, si el nombre no cuadra,
                -- buscándolo por nombre en las categorías de logros
                local achievementId = tonumber(string.match(what, "achievement:(%d+)")) or info.newsID or 0
                local _, name, points, _, _, _, _, _, _, icon = GetAchievementInfo(achievementId)
                local whatName = string.match(what, "%[(.-)%]") or what
                if (not name or (whatName ~= "" and name ~= whatName)) and whatName ~= "" then
                    local foundId = newsModule.FindAchievementByName(whatName)
                    if foundId then
                        achievementId = foundId
                        _, name, points, _, _, _, _, _, _, icon = GetAchievementInfo(foundId)
                    end
                end
                item.kind = (t == NEWS.GUILD_ACHIEVEMENT) and "guildAchievement" or "achievement"
                item.icon = icon or ICONS.achievement
                item.achievementId = name and achievementId or nil
                item.name = name or whatName
                item.title = (t == NEWS.GUILD_ACHIEVEMENT) and L["La hermandad ha conseguido un logro"]
                    or (who .. L[" ha conseguido un logro"])
                item.detail = "|cFFFFD100" .. (name or what) .. "|r" .. ((points and points > 0) and (L[" |cFF808080("] .. points .. L[" puntos)|r"]) or "")
            elseif t == NEWS.DUNGEON_ENCOUNTER then
                item.kind = "boss"
                item.icon = ICONS.boss
                item.title = L["Victoria contra "] .. what
                local present = info.guildMembersPresent
                item.detail = (present and present > 0) and (L["Con "] .. present .. L[" miembros de la hermandad"]) or (L["Con "] .. who)
            elseif t == NEWS.ITEM_LOOTED or t == NEWS.ITEM_CRAFTED or t == NEWS.ITEM_PURCHASED then
                item.kind = "loot"
                item.lootType = (t == NEWS.ITEM_CRAFTED) and "crafted" or ((t == NEWS.ITEM_PURCHASED) and "purchased" or "looted")
                -- El icono sale del identificador del enlace del objeto
                item.link = what
                item.icon = ItemIcon(tonumber(string.match(what, "item:(%d+)"))) or ItemIcon(info.newsID) or ICONS.loot
                local verb = (t == NEWS.ITEM_CRAFTED) and L["ha fabricado"] or ((t == NEWS.ITEM_PURCHASED) and L["ha comprado"] or L["ha obtenido"])
                item.title = who .. " " .. verb
                item.detail = what   -- enlace del objeto con su color de calidad
            else
                item.kind = "other"
                item.title = what ~= "" and what or L["Novedad en la hermandad"]
                item.detail = who ~= L["Alguien"] and who or ""
            end
            item.dateText, item.sortKey = NewsDate(info)
            table.insert(items, item)
        end
    end
    return items
end

local function HistoryItems()
    local items = {}
    local limit = date("%Y-%m-%d", time() - HISTORY_DAYS * 86400)
    for _, log in ipairs(GuildControlDB.history or {}) do
        local day = log.date and string.sub(log.date, 1, 10) or ""
        if day >= limit and (log.action == "ALTA" or log.action == "BAJA") then
            local isJoin = log.action == "ALTA"
            local y, mo, d = string.match(day, "^(%d+)-(%d+)-(%d+)$")
            table.insert(items, {
                kind = isJoin and "join" or "leave",
                icon = isJoin and ICONS.join or ICONS.leave,
                title = ShortName(log.name) .. (isJoin and L[" se ha unido a la hermandad"] or L[" ha dejado la hermandad"]),
                detail = isJoin and L["|cFF00FF00Nuevo miembro|r"] or L["|cFFFF3333Baja|r"],
                dateText = d and (d .. "/" .. mo) or "",
                sortKey = (y or "0000") .. (mo or "00") .. (d or "00") .. string.sub(log.date or "", 12),
            })
        end
    end
    return items
end

-- Las últimas altas de la hermandad (sin límite de días), más recientes primero
local LATEST_JOINS = 5
function newsModule.GetLatestJoins(count)
    local items = {}
    for _, log in ipairs(GuildControlDB.history or {}) do
        if log.action == "ALTA" then
            local day = log.date and string.sub(log.date, 1, 10) or ""
            local y, mo, d = string.match(day, "^(%d+)-(%d+)-(%d+)$")
            table.insert(items, {
                kind = "join",
                icon = ICONS.join,
                title = ShortName(log.name) .. L[" se ha unido a la hermandad"],
                detail = L["|cFF00FF00Nuevo miembro|r"],
                dateText = d and (d .. "/" .. mo .. "/" .. y) or "",
                sortKey = (y or "0000") .. (mo or "00") .. (d or "00") .. string.sub(log.date or "", 12),
            })
        end
    end
    table.sort(items, function(a, b) return (a.sortKey or "") > (b.sortKey or "") end)
    while #items > (count or LATEST_JOINS) do table.remove(items) end
    return items
end

-- Noticias combinadas, más recientes primero, según el filtro ("all" por defecto)
function newsModule.GetFeed(filter)
    local feed = {}
    local allowed = FILTER_KINDS[filter or "all"]
    for _, list in ipairs({ GuildNewsItems(), HistoryItems() }) do
        for _, item in ipairs(list) do
            if not allowed or allowed[item.kind] then table.insert(feed, item) end
        end
    end
    table.sort(feed, function(a, b) return (a.sortKey or "") > (b.sortKey or "") end)
    return feed
end

-- =========================================================================
-- ORIGEN DE UN OBJETO (DIARIO DE ENCUENTROS)
-- =========================================================================
-- El juego no dice de dónde salió un objeto de las noticias. Se busca en el diario de
-- encuentros (EJ_SetSearch, asíncrono): si es botín de una banda o mazmorra, devuelve la
-- instancia y el jefe. Los vendedores y el botín de mundo no figuran en el diario.
local sourceCache = {}
local searchBusy = false

local function ItemIdFromLink(link)
    return tonumber(string.match(link or "", "item:(%d+)"))
end

-- Datos básicos del objeto: nivel, tipo y hueco
function newsModule.GetItemDetails(link)
    local details = {}
    if not link then return details end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if getInfo then
        local ok, _, _, _, itemLevel, _, itemType, itemSubType, _, equipLoc = pcall(getInfo, link)
        if ok then
            details.itemLevel = itemLevel
            details.type = itemSubType or itemType
            details.slot = (equipLoc and equipLoc ~= "" and _G[equipLoc]) or nil
        end
    end
    local getLevel = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    if getLevel then
        local ok, level = pcall(getLevel, link)
        if ok and level then details.itemLevel = level end
    end
    return details
end

-- callback(source) con source = { instance, encounter } o false si no figura en el diario
function newsModule.LookupItemSource(link, callback)
    local itemID = ItemIdFromLink(link)
    if not itemID then callback(false) return end
    if sourceCache[itemID] ~= nil then callback(sourceCache[itemID]) return end
    if searchBusy or not (EJ_SetSearch and EJ_GetNumSearchResults and EJ_GetSearchResult) then callback(nil) return end

    local name = string.match(link, "%[(.-)%]")
    if not name or #name < 3 then callback(false) return end

    searchBusy = true
    pcall(EJ_SetSearch, name)
    local tries = 0
    local ticker
    ticker = C_Timer.NewTicker(0.25, function()
        tries = tries + 1
        local finished = not EJ_IsSearchFinished or EJ_IsSearchFinished()
        if not finished and tries < 16 then return end
        ticker:Cancel()

        local result = false
        local okNum, num = pcall(EJ_GetNumSearchResults)
        for i = 1, (okNum and num or 0) do
            local ok, _, _, _, instanceID, encounterID, resultLink = pcall(EJ_GetSearchResult, i)
            if ok and ItemIdFromLink(resultLink) == itemID then
                local instanceName = instanceID and EJ_GetInstanceInfo and EJ_GetInstanceInfo(instanceID)
                local encounterName = encounterID and EJ_GetEncounterInfo and EJ_GetEncounterInfo(encounterID)
                result = { instance = instanceName, encounter = encounterName }
                break
            end
        end
        if EJ_ClearSearch then pcall(EJ_ClearSearch) end
        searchBusy = false
        -- Solo se guarda un resultado definitivo (si la búsqueda no terminó, se reintentará)
        if result or finished then sourceCache[itemID] = result end
        callback(result)
    end)
end

-- =========================================================================
-- PRÓXIMAS BANDAS, ROSTERS Y CIFRAS
-- =========================================================================
-- Rosters visibles: los propios (oficiales) o los publicados por los oficiales (jugadores)
local function VisibleRosters()
    local R = addonTable.Roster
    if not R then return {} end
    local isOfficer = not addonTable.Profiles or addonTable.Profiles.IsOfficer()
    if isOfficer then return R.GetAll() end
    local list = {}
    for _, item in ipairs(R.GetSharedRosters()) do table.insert(list, item.roster) end
    return list
end

-- { {roster, event}, ... } ordenadas por fecha, solo las de hoy en adelante
-- Próximas bandas de la pestaña Raid: { {event}, ... }, más próximas primero
function newsModule.GetUpcomingRaids(limit)
    local result = {}
    local E = addonTable.RaidEvents
    if not E then return result end
    for _, event in ipairs(E.GetUpcomingForRoster(nil)) do
        table.insert(result, { event = event })
        if limit and #result >= limit then break end
    end
    return result
end

-- { {name, difficulty, size, starters, bench, published}, ... }
function newsModule.GetRosterSummaries()
    local R = addonTable.Roster
    local result = {}
    if not R then return result end
    for _, roster in ipairs(VisibleRosters()) do
        local starters, bench = 0, 0
        for _, slot in pairs(roster.members or {}) do
            if slot == "bench" then bench = bench + 1 else starters = starters + 1 end
        end
        table.insert(result, {
            name = roster.name, difficulty = R.DifficultyLabel(roster), size = roster.size,
            starters = starters, bench = bench, published = roster.syncId ~= nil,
        })
    end
    return result
end

function newsModule.GetStats()
    local stats = { members = 0, online = 0, joins = 0, leaves = 0, declared = 0, achievementPoints = 0 }
    for _, m in pairs(GuildControlDB.members or {}) do
        stats.members = stats.members + 1
        if m.isOnline then stats.online = stats.online + 1 end
        if m.declared and m.declared.main then stats.declared = stats.declared + 1 end
    end
    local weekAgo = date("%Y-%m-%d", time() - 7 * 86400)
    for _, log in ipairs(GuildControlDB.history or {}) do
        if log.date and string.sub(log.date, 1, 10) >= weekAgo then
            if log.action == "ALTA" then stats.joins = stats.joins + 1 end
            if log.action == "BAJA" then stats.leaves = stats.leaves + 1 end
        end
    end
    if GetTotalAchievementPoints then
        local ok, points = pcall(GetTotalAchievementPoints, true)
        if ok and points then stats.achievementPoints = points end
    end
    return stats
end

function newsModule.GetMOTD()
    local motd = GetGuildRosterMOTD and GetGuildRosterMOTD() or ""
    return motd or ""
end

-- Semana (lunes a domingo) de una clave de fecha "AAAAMMDD...": devuelve clave y texto
function newsModule.GetWeek(sortKey)
    local y, mo, d = string.match(sortKey or "", "^(%d%d%d%d)(%d%d)(%d%d)")
    if not y then return "0", L["Sin fecha"] end
    local t = time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 })
    local weekday = tonumber(date("%w", t))           -- 0 = domingo
    local monday = t - ((weekday + 6) % 7) * 86400
    local sunday = monday + 6 * 86400
    local thisMonday = time() - ((tonumber(date("%w")) + 6) % 7) * 86400
    local label
    if date("%Y%m%d", monday) == date("%Y%m%d", thisMonday) then
        label = L["Esta semana"]
    elseif date("%Y%m%d", monday) == date("%Y%m%d", thisMonday - 7 * 86400) then
        label = L["Semana pasada"]
    else
        label = L["Semana del "] .. date("%d/%m", monday) .. L[" al "] .. date("%d/%m", sunday)
    end
    return date("%Y%m%d", monday), label
end

-- Oficiales de la hermandad (rango igual o superior al configurado), por rango y nombre
function newsModule.GetOfficers()
    local P = addonTable.Profiles
    local list = {}
    for fullName, m in pairs(GuildControlDB.members or {}) do
        -- Rango mínimo configurado o permiso de chat de oficiales del juego
        local isOfficer = m.rankIndex and (P and P.IsOfficerRank(m.rankIndex) or m.rankIndex <= 1)
        if isOfficer then
            table.insert(list, { name = fullName, rank = m.rank or "-", rankIndex = m.rankIndex,
                                 class = m.class, online = m.isOnline })
        end
    end
    table.sort(list, function(a, b)
        if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
        return a.name < b.name
    end)
    return list
end

-- =========================================================================
-- EVENTOS
-- =========================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("GUILD_NEWS_UPDATE")
frame:RegisterEvent("GUILD_MOTD")
frame:SetScript("OnEvent", function()
    if GuildControlDB then Notify() end
end)
