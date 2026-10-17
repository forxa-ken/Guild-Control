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
    { key = "guildAchievement", label = "Logros hermandad" },
    { key = "achievement", label = "Logros personajes" },
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

local feedCache, feedCacheAt = nil, -1   -- noticias completas (ver BuildFullFeed)
local function Notify()
    feedCache = nil
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

-- Índice nombre -> id de todos los logros (de hermandad y de personaje). Son miles de
-- llamadas al juego: se construye poco a poco, una categoría por fotograma, la primera vez
-- que hace falta. Mientras tanto devuelve nil y, al terminar, refresca las noticias.
local achievementNameIndex = nil
local indexBuilding = false
local function BuildAchievementIndex()
    if indexBuilding then return end
    indexBuilding = true
    local pending = {}
    if GetGuildCategoryList then for _, id in ipairs(GetGuildCategoryList() or {}) do table.insert(pending, id) end end
    if GetCategoryList then for _, id in ipairs(GetCategoryList() or {}) do table.insert(pending, id) end end
    local index, position = {}, 1
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        local categoryId = pending[position]
        if not categoryId then
            ticker:Cancel()
            achievementNameIndex = index
            newsModule.InvalidateCache()
            return
        end
        position = position + 1
        local num = GetCategoryNumAchievements(categoryId, true) or 0
        for i = 1, num do
            local id, achName = GetAchievementInfo(categoryId, i)
            if id and achName and not index[achName] then index[achName] = id end
        end
    end)
end

function newsModule.FindAchievementByName(name)
    if not name or name == "" then return nil end
    if not achievementNameIndex then
        BuildAchievementIndex()
        return nil
    end
    return achievementNameIndex[name]
end

-- Las noticias del juego se leen una vez y se guardan hasta GUILD_NEWS_UPDATE (cada refresco
-- del Resumen las pedía varias veces)
local cachedNews = nil
function newsModule.InvalidateCache()
    cachedNews = nil
    feedCache = nil
    Notify()
end

local function ReadGuildNews()
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

local function GuildNewsItems()
    if not cachedNews then cachedNews = ReadGuildNews() end
    return cachedNews
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

-- Claves de los filtros que tienen alguna noticia. Altas se ve si hay alguna alta guardada
-- (muestra las últimas aunque sean antiguas); los demás, solo si tienen noticias.
function newsModule.GetActiveFilters()
    local active = { join = #newsModule.GetLatestJoins(1) > 0 }
    for _, item in ipairs(newsModule.GetFeed("all")) do
        for key, kinds in pairs(FILTER_KINDS) do
            if kinds[item.kind] then active[key] = true end
        end
    end
    return active
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

-- =========================================================================
-- JEFES DERROTADOS (BANDAS Y MAZMORRAS)
-- =========================================================================
-- Las noticias del juego no incluyen todos los jefes (por ejemplo, los de mazmorra). El
-- addon registra cada jefe que derrota quien lo usa (ENCOUNTER_END) si en el grupo hay al
-- menos otro miembro de la hermandad, y lo comparte con el prefijo GuildControlBoss:
--   "B;encounterID;difficultyID;hora(servidor);miembros;party|raid;instancia;jefe"
-- GuildControlDB.bossKills = { {encounterID, difficultyID, at, members, instanceType, instance, boss}, ... }
local BOSS_PREFIX = "GuildControlBoss"
local BOSS_KEEP_DAYS = 30
local BOSS_SAME_KILL_SECONDS = 600   -- varios clientes avisan del mismo jefe: se unen

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(BOSS_PREFIX)
end

local function BossStore()
    if type(GuildControlDB.bossKills) ~= "table" then GuildControlDB.bossKills = {} end
    return GuildControlDB.bossKills
end

local function CleanText(text, maxLen)
    text = string.gsub(tostring(text or ""), "[|;]", "")
    return string.sub(strtrim(text), 1, maxLen)
end

-- Añade un jefe derrotado (o lo une al que ya había). Devuelve true si es nuevo.
local function AddBossKill(kill)
    local store = BossStore()
    local limit = GetServerTime() - BOSS_KEEP_DAYS * 86400
    for i = #store, 1, -1 do
        if (store[i].at or 0) < limit then table.remove(store, i) end
    end
    for _, k in ipairs(store) do
        if k.encounterID == kill.encounterID and k.difficultyID == kill.difficultyID
            and math.abs((k.at or 0) - kill.at) < BOSS_SAME_KILL_SECONDS then
            if kill.members > (k.members or 0) then k.members = kill.members end
            return false
        end
    end
    table.insert(store, kill)
    return true
end

-- Miembros de la hermandad en mi grupo (contándome)
local function GuildMembersInGroup()
    local count = IsInGuild() and 1 or 0
    local prefix = IsInRaid() and "raid" or "party"
    local total = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
    for i = 1, total do
        local unit = prefix .. i
        if not UnitIsUnit(unit, "player") and UnitIsInMyGuild and UnitIsInMyGuild(unit) then count = count + 1 end
    end
    return count
end

local function OnEncounterEnd(encounterID, encounterName, difficultyID, _, success)
    if issecretvalue and (issecretvalue(encounterID) or issecretvalue(encounterName) or issecretvalue(success)) then return end
    if success ~= 1 and success ~= true then return end
    if not IsInGuild() or not encounterID then return end
    local instanceName, instanceType = GetInstanceInfo()
    if not difficultyID then difficultyID = select(3, GetInstanceInfo()) end
    if instanceType ~= "party" and instanceType ~= "raid" then return end
    local members = GuildMembersInGroup()
    if members < 2 then return end
    local kill = {
        encounterID = encounterID, difficultyID = difficultyID or 0, at = GetServerTime(), members = members,
        instanceType = instanceType, instance = CleanText(instanceName, 40), boss = CleanText(encounterName, 40),
    }
    AddBossKill(kill)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(BOSS_PREFIX, table.concat({ "B", kill.encounterID, kill.difficultyID, kill.at,
            kill.members, kill.instanceType, kill.instance, kill.boss }, ";"), "GUILD")
    end
    Notify()
end

local function OnBossMessage(msg)
    local kind, encounterID, difficultyID, at, members, instanceType, instance, boss = strsplit(";", msg)
    encounterID, difficultyID, at, members = tonumber(encounterID), tonumber(difficultyID), tonumber(at), tonumber(members)
    if kind ~= "B" or not encounterID or not at or not boss or boss == "" then return end
    if instanceType ~= "party" and instanceType ~= "raid" then return end
    if at > GetServerTime() + 300 or at < GetServerTime() - BOSS_KEEP_DAYS * 86400 then return end
    if AddBossKill({ encounterID = encounterID, difficultyID = difficultyID or 0, at = at, members = members or 2,
                     instanceType = instanceType, instance = CleanText(instance, 40), boss = CleanText(boss, 40) }) then
        Notify()
    end
end

local function BossKillItems()
    local items = {}
    for _, k in ipairs(BossStore()) do
        local diffName = GetDifficultyInfo and GetDifficultyInfo(k.difficultyID) or nil
        local parts = { k.instance ~= "" and k.instance or nil, diffName,
                        L["Con "] .. (k.members or 2) .. L[" miembros de la hermandad"] }
        local detail = {}
        for _, p in pairs(parts) do if p then table.insert(detail, p) end end
        table.insert(items, {
            kind = "boss",
            icon = ICONS.boss,
            title = L["Victoria contra "] .. k.boss,
            detail = table.concat(detail, L[" · "]),
            bossName = k.boss,
            dateText = date("%d/%m", k.at),
            sortKey = date("%Y%m%d%H%M%S", k.at),
        })
    end
    return items
end

-- =========================================================================
-- LOGROS QUE SE VEN EN EL CHAT DE HERMANDAD
-- =========================================================================
-- Las noticias del juego no traen todos los logros de los miembros (ni al momento). El addon
-- apunta los avisos "X ha ganado el logro [Y]" del chat de hermandad (CHAT_MSG_GUILD_ACHIEVEMENT)
-- en GuildControlDB.memberAchievements = { {at, who, id}, ... } durante 30 días.
local ACH_KEEP_DAYS = 30
local ACH_MAX = 400

local function AchievementStore()
    if type(GuildControlDB.memberAchievements) ~= "table" then GuildControlDB.memberAchievements = {} end
    return GuildControlDB.memberAchievements
end

local function OnGuildAchievement(text, sender)
    if issecretvalue and (issecretvalue(text) or issecretvalue(sender)) then return end
    if type(text) ~= "string" or type(sender) ~= "string" then return end
    local id = tonumber(string.match(text, "|Hachievement:(%d+)"))
    if not id then return end
    local store = AchievementStore()
    local now = GetServerTime()
    for _, entry in ipairs(store) do
        if entry.id == id and entry.who == sender and now - (entry.at or 0) < 600 then return end
    end
    table.insert(store, 1, { at = now, who = sender, id = id })
    local limit = now - ACH_KEEP_DAYS * 86400
    for i = #store, 1, -1 do
        if i > ACH_MAX or (store[i].at or 0) < limit then table.remove(store, i) end
    end
    Notify()
end

local function ChatAchievementItems()
    local items = {}
    for _, entry in ipairs(AchievementStore()) do
        local _, name, points, _, _, _, _, _, _, icon, _, isGuild = GetAchievementInfo(entry.id)
        if name then
            local who = ShortName(entry.who)
            table.insert(items, {
                kind = isGuild and "guildAchievement" or "achievement",
                icon = icon or ICONS.achievement,
                achievementId = entry.id, name = name, who = who,
                title = isGuild and L["La hermandad ha conseguido un logro"] or (who .. L[" ha conseguido un logro"]),
                detail = "|cFFFFD100" .. name .. "|r" .. ((points and points > 0) and (L[" |cFF808080("] .. points .. L[" puntos)|r"]) or ""),
                dateText = date("%d/%m", entry.at),
                sortKey = date("%Y%m%d%H%M%S", entry.at),
            })
        end
    end
    return items
end

-- Lista completa sin filtrar (se guarda 1 s: la vista y los filtros la piden varias veces seguidas)
local function BuildFullFeed()
    if feedCache and GetTime() - feedCacheAt < 1 then return feedCache end
    local feed = {}
    local allowed = nil
    local bosses = BossKillItems()
    -- Un jefe que ya registró el addon no se repite con la noticia del juego del mismo día
    local seenBoss = {}
    for _, item in ipairs(bosses) do seenBoss[item.bossName .. "|" .. string.sub(item.sortKey, 1, 8)] = true end
    -- Un logro del chat que ya está en las noticias del juego no se repite
    local gameNews = GuildNewsItems()
    local seenAch = {}
    for _, item in ipairs(gameNews) do
        if item.achievementId then seenAch[item.achievementId .. "|" .. (item.who or "")] = true end
    end
    for _, list in ipairs({ gameNews, HistoryItems(), bosses, ChatAchievementItems() }) do
        for _, item in ipairs(list) do
            local duplicate = (item.kind == "boss" and not item.bossName
                and seenBoss[string.gsub(item.title, "^" .. L["Victoria contra "], "", 1) .. "|" .. string.sub(item.sortKey or "", 1, 8)])
                or (list ~= gameNews and item.achievementId and seenAch[item.achievementId .. "|" .. (item.who or "")])
            if (not allowed or allowed[item.kind]) and not duplicate then table.insert(feed, item) end
        end
    end
    table.sort(feed, function(a, b) return (a.sortKey or "") > (b.sortKey or "") end)
    feedCache, feedCacheAt = feed, GetTime()
    return feed
end

-- Noticias combinadas, más recientes primero, según el filtro ("all" por defecto)
function newsModule.GetFeed(filter)
    local all = BuildFullFeed()
    local allowed = FILTER_KINDS[filter or "all"]
    if not allowed then return all end
    local feed = {}
    for _, item in ipairs(all) do
        if allowed[item.kind] then table.insert(feed, item) end
    end
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
-- PRÓXIMAS BANDAS
-- =========================================================================
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
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("BOSS_KILL")
frame:RegisterEvent("CHAT_MSG_GUILD_ACHIEVEMENT")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if not GuildControlDB then return end
    if event == "GUILD_NEWS_UPDATE" then
        cachedNews = nil
        Notify()
    elseif event == "CHAT_MSG_GUILD_ACHIEVEMENT" then
        local text, sender = ...
        OnGuildAchievement(text, sender)
    elseif event == "ENCOUNTER_END" then
        OnEncounterEnd(...)
    elseif event == "BOSS_KILL" then
        -- Segundo aviso del mismo jefe (si ENCOUNTER_END llegó sin datos): se une al registro
        local encounterID, encounterName = ...
        OnEncounterEnd(encounterID, encounterName, nil, nil, true)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if prefix ~= BOSS_PREFIX or channel ~= "GUILD" then return end
        if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
        if msg and sender and not addonTable.IsMe(sender) then OnBossMessage(msg) end
    else
        Notify()
    end
end)

