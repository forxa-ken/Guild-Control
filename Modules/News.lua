local addonName, addonTable = ...

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
    { key = "achievement", label = "Logros" },
    { key = "boss", label = "Jefes" },
    { key = "loot", label = "Botín" },
    { key = "join", label = "Altas" },
    { key = "leave", label = "Bajas" },
}
local FILTER_KINDS = {
    achievement = { achievement = true, guildAchievement = true },
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
    if not name or name == "" then return "Alguien" end
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
                -- El identificador sale del enlace del logro; si no, de newsID
                local achievementId = tonumber(string.match(what, "achievement:(%d+)")) or info.newsID or 0
                local _, name, points, _, _, _, _, _, _, icon = GetAchievementInfo(achievementId)
                item.kind = (t == NEWS.GUILD_ACHIEVEMENT) and "guildAchievement" or "achievement"
                item.icon = icon or ICONS.achievement
                item.achievementId = achievementId
                item.name = name
                item.title = (t == NEWS.GUILD_ACHIEVEMENT) and "La hermandad ha conseguido un logro"
                    or (who .. " ha conseguido un logro")
                item.detail = "|cFFFFD100" .. (name or what) .. "|r" .. ((points and points > 0) and (" |cFF808080(" .. points .. " puntos)|r") or "")
            elseif t == NEWS.DUNGEON_ENCOUNTER then
                item.kind = "boss"
                item.icon = ICONS.boss
                item.title = "Victoria contra " .. what
                local present = info.guildMembersPresent
                item.detail = (present and present > 0) and ("Con " .. present .. " miembros de la hermandad") or ("Con " .. who)
            elseif t == NEWS.ITEM_LOOTED or t == NEWS.ITEM_CRAFTED or t == NEWS.ITEM_PURCHASED then
                item.kind = "loot"
                -- El icono sale del identificador del enlace del objeto
                item.link = what
                item.icon = ItemIcon(tonumber(string.match(what, "item:(%d+)"))) or ItemIcon(info.newsID) or ICONS.loot
                local verb = (t == NEWS.ITEM_CRAFTED) and "ha fabricado" or ((t == NEWS.ITEM_PURCHASED) and "ha comprado" or "ha obtenido")
                item.title = who .. " " .. verb
                item.detail = what   -- enlace del objeto con su color de calidad
            else
                item.kind = "other"
                item.title = what ~= "" and what or "Novedad en la hermandad"
                item.detail = who ~= "Alguien" and who or ""
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
                title = ShortName(log.name) .. (isJoin and " se ha unido a la hermandad" or " ha dejado la hermandad"),
                detail = isJoin and "|cFF00FF00Nuevo miembro|r" or "|cFFFF3333Baja|r",
                dateText = d and (d .. "/" .. mo) or "",
                sortKey = (y or "0000") .. (mo or "00") .. (d or "00") .. string.sub(log.date or "", 12),
            })
        end
    end
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
function newsModule.GetUpcomingRaids(limit)
    local R = addonTable.Roster
    local result = {}
    if not R then return result end
    local today = date("%Y-%m-%d")
    for _, roster in ipairs(VisibleRosters()) do
        for _, event in ipairs(R.GetEventsSorted(roster)) do
            if event.date >= today then table.insert(result, { roster = roster, event = event }) end
        end
    end
    table.sort(result, function(a, b) return (a.event.date .. a.event.time) < (b.event.date .. b.event.time) end)
    while limit and #result > limit do table.remove(result) end
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
    if not y then return "0", "Sin fecha" end
    local t = time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 })
    local weekday = tonumber(date("%w", t))           -- 0 = domingo
    local monday = t - ((weekday + 6) % 7) * 86400
    local sunday = monday + 6 * 86400
    local thisMonday = time() - ((tonumber(date("%w")) + 6) % 7) * 86400
    local label
    if date("%Y%m%d", monday) == date("%Y%m%d", thisMonday) then
        label = "Esta semana"
    elseif date("%Y%m%d", monday) == date("%Y%m%d", thisMonday - 7 * 86400) then
        label = "Semana pasada"
    else
        label = "Semana del " .. date("%d/%m", monday) .. " al " .. date("%d/%m", sunday)
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
