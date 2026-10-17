local addonName, addonTable = ...
local L = addonTable.L

addonTable.Personal = {}
local personalModule = addonTable.Personal

-- Funciones para el jugador (sin frames; la UI está en UI.lua, pestaña "Para mí"):
--   - Avisos personales: objeto asignado, banda nueva, cambio de puesto en un roster, DKP,
--     llave, objeto de tu lista de deseos que cae y banda que empieza en 15 min.
--   - Lista de deseos (GuildControlDB.wishlists[Nombre-Reino] = { [itemID] = true }), que se
--     comparte con la hermandad (prefijo GuildControlWish: "W;id,id,...") para que los
--     oficiales vean quién quiere cada objeto.
--   - Historial personal de DKP (GuildControlDB.myLedger[Nombre-Reino] = { {at, delta, balance, reason} }).
--   - Insignias y récords de la hermandad, calculados con los datos que ya tiene el addon.

local WISH_PREFIX = "GuildControlWish"
local WISH_MAX = 40
local LEDGER_MAX = 200
local REMINDER_MINUTES = 15

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(WISH_PREFIX)
end

local listeners = {}
local function Notify()
    for _, fn in ipairs(listeners) do fn() end
end
function personalModule.AddListener(fn) table.insert(listeners, fn) end

local function MyName()
    if addonTable.Profiles and addonTable.Profiles.GetMyFullName then return addonTable.Profiles.GetMyFullName() end
    return UnitName("player")
end

local function NormalizeName(name)
    if addonTable.Profiles and addonTable.Profiles.NormalizeName then return addonTable.Profiles.NormalizeName(name) end
    return name
end

local function Store(key)
    if type(GuildControlDB[key]) ~= "table" then GuildControlDB[key] = {} end
    return GuildControlDB[key]
end

-- =========================================================================
-- AVISOS PERSONALES
-- =========================================================================
function personalModule.IsEnabled()
    return GuildControlDB and GuildControlDB.settings and GuildControlDB.settings.personalNotify ~= false
end

-- Aviso en pantalla (ventanita que se va sola) y en el chat
function personalModule.Alert(text, icon)
    if not personalModule.IsEnabled() then return end
    print("|cFF00FFFF[GuildControl]|r " .. text)
    if addonTable.UI and addonTable.UI.ShowToast then addonTable.UI.ShowToast(text, icon) end
end

-- =========================================================================
-- LISTA DE DESEOS
-- =========================================================================
-- Identificador del objeto a partir de un enlace del juego ("item:ID"), un enlace de Wowhead
-- ("...wowhead.com/es/item=ID/nombre") o el número solo
local function ItemIdFromLink(link)
    link = strtrim(tostring(link or ""))
    return tonumber(string.match(link, "item:(%d+)"))
        or tonumber(string.match(link, "[Ii][Tt][Ee][Mm]=(%d+)"))
        or tonumber(string.match(link, "^(%d+)$"))
end
personalModule.ItemIdFromLink = ItemIdFromLink

function personalModule.GetMyWishlist()
    local all = Store("wishlists")
    local me = MyName()
    all[me] = all[me] or {}
    return all[me]
end

-- Lista ordenada de mi lista de deseos: { itemID, ... }
function personalModule.GetMyWishIds()
    local ids = {}
    for id in pairs(personalModule.GetMyWishlist()) do table.insert(ids, id) end
    table.sort(ids)
    return ids
end

local wishSendTimer = nil
local function SendWishlist()
    if not IsInGuild() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local ids = personalModule.GetMyWishIds()
    local parts = {}
    for i = 1, math.min(#ids, WISH_MAX) do parts[i] = tostring(ids[i]) end
    pcall(C_ChatInfo.SendAddonMessage, WISH_PREFIX, "W;" .. table.concat(parts, ","), "GUILD")
end

local function ScheduleWishSend()
    if wishSendTimer then wishSendTimer:Cancel() end
    wishSendTimer = C_Timer.NewTimer(3, function()
        wishSendTimer = nil
        SendWishlist()
    end)
end

-- Añade (o quita) un objeto. Devuelve true si ahora está en la lista.
function personalModule.ToggleWish(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end
    local list = personalModule.GetMyWishlist()
    -- Pide los datos del objeto al juego (los enlaces de Wowhead llegan sin ellos)
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
    if list[itemID] then
        list[itemID] = nil
    else
        local count = 0
        for _ in pairs(list) do count = count + 1 end
        if count >= WISH_MAX then
            print("|cFF00FFFF[GuildControl]|r " .. string.format(L["|cFFFF3333Tu lista de deseos admite como mucho %d objetos.|r"], WISH_MAX))
            return false
        end
        list[itemID] = true
    end
    ScheduleWishSend()
    Notify()
    return list[itemID] == true
end

-- Quién de la hermandad quiere un objeto: { Nombre-Reino, ... }
function personalModule.WhoWants(itemID)
    itemID = tonumber(itemID)
    local names = {}
    if not itemID then return names end
    for name, list in pairs(Store("wishlists")) do
        if list[itemID] then table.insert(names, name) end
    end
    table.sort(names)
    return names
end

-- =========================================================================
-- HISTORIAL PERSONAL DE DKP
-- =========================================================================
function personalModule.GetLedger(name)
    local all = Store("myLedger")
    name = name or MyName()
    all[name] = all[name] or {}
    return all[name]
end

-- Mira si mis DKP han cambiado y lo apunta (con el motivo de la última entrada del registro)
local function CheckDkp()
    local D = addonTable.Dkp
    if not D or not D.IsActive() then return end
    local me = MyName()
    local balance = D.GetBalance(me)
    local last = Store("myLedgerLast")
    if last[me] == nil then
        last[me] = balance
        return
    end
    if balance == last[me] then return end
    local delta = balance - last[me]
    last[me] = balance
    local log = D.GetLog()
    local reason = log[1] and log[1].reason or ""
    local ledger = personalModule.GetLedger(me)
    table.insert(ledger, 1, { at = time(), delta = delta, balance = balance, reason = reason })
    while #ledger > LEDGER_MAX do table.remove(ledger) end
    personalModule.Alert(string.format(L["Tus DKP: %s%d|r (%s). Ahora tienes |cFFFFD100%d|r."],
        delta > 0 and "|cFF00FF00+" or "|cFFFF3333", delta, reason, balance))
    Notify()
end

-- =========================================================================
-- AVISOS AL CAMBIAR LOS DATOS
-- =========================================================================
local notifiedAwards = {}
local notifiedWishDrops = {}
local knownEvents = nil
local mySlots = nil
local myKey = nil
local reminded = {}

-- Objeto asignado a mí y objeto de mi lista de deseos que ha caído
local function CheckLoot()
    local LT = addonTable.Loot
    if not LT then return end
    local me = MyName()
    local history = LT.GetHistory()
    local award = history[1]
    if award and award.winner == me and award.id and not notifiedAwards[award.id] then
        notifiedAwards[award.id] = true
        if GetServerTime() - (award.at or 0) < 600 then
            personalModule.Alert(L["¡Te han asignado "] .. LT.DisplayLink(award.link) .. "!")
        end
    end
    local wishes = personalModule.GetMyWishlist()
    for _, item in ipairs(LT.GetItems()) do
        local id = ItemIdFromLink(item.link)
        if id and wishes[id] and not notifiedWishDrops[item.key] and item.state ~= "done" then
            notifiedWishDrops[item.key] = true
            personalModule.Alert(L["Ha caído un objeto de tu lista de deseos: "] .. LT.DisplayLink(item.link))
        end
    end
end

-- Bandas nuevas (creadas hace menos de 2 h)
local function CheckEvents()
    local E = addonTable.RaidEvents
    if not E then return end
    local events = E.GetUpcoming()
    if not knownEvents then
        knownEvents = {}
        for _, ev in ipairs(events) do knownEvents[ev.id] = true end
        return
    end
    for _, ev in ipairs(events) do
        if not knownEvents[ev.id] then
            knownEvents[ev.id] = true
            local created = tonumber(string.match(ev.id, "%-(%d+)$"))
            if created and time() - created < 7200 then
                personalModule.Alert(L["Nueva banda: "] .. "|cFFFFD100" .. ev.title .. "|r " .. ev.date .. " " .. ev.time)
            end
        end
    end
end

-- Mi puesto en los rosters (los míos de oficial y los publicados)
local SLOT_LABELS = { tank = "Tanque", healer = "Sanador", dps = "DPS", bench = "Suplente" }
local function CurrentSlots()
    local R = addonTable.Roster
    local slots = {}
    if not R then return slots end
    local me = MyName()
    for _, roster in ipairs(R.GetAll and R.GetAll() or {}) do
        if roster.members and roster.members[me] then slots[roster.name] = roster.members[me] end
    end
    for _, item in ipairs(R.GetSharedRosters and R.GetSharedRosters() or {}) do
        local roster = item.roster
        if roster and roster.members and roster.members[me] then slots[roster.name] = roster.members[me] end
    end
    return slots
end

local function CheckRosterAndKey()
    local slots = CurrentSlots()
    if mySlots then
        for name, slot in pairs(slots) do
            if mySlots[name] ~= slot then
                personalModule.Alert(string.format(L["Roster %s: ahora estás como %s."], "|cFFFFD100" .. name .. "|r", L[SLOT_LABELS[slot] or slot]))
            end
        end
        for name in pairs(mySlots) do
            if not slots[name] then personalModule.Alert(string.format(L["Ya no estás en el roster %s."], "|cFFFFD100" .. name .. "|r")) end
        end
    end
    mySlots = slots

    local M = addonTable.MythicPlus
    if M and M.GetMyKeystone then
        local mapID, level = M.GetMyKeystone()
        local current = (mapID and level) and (mapID .. ":" .. level) or nil
        if myKey ~= nil and current and current ~= myKey then
            personalModule.Alert(string.format(L["Tu llave ahora es %s +%d."], M.GetMapName(mapID) or "?", level))
        end
        if current then myKey = current end
    end
end

-- Banda en la que estoy apuntado que empieza en 15 minutos
local function CheckReminders()
    local E = addonTable.RaidEvents
    if not E or not E.EventStart then return end
    local me = MyName()
    local now = time()
    for _, ev in ipairs(E.GetUpcoming()) do
        local signup = ev.signups and ev.signups[me]
        local start = E.EventStart(ev)
        if signup and signup.status ~= "absent" and start and not reminded[ev.id]
            and start - now <= REMINDER_MINUTES * 60 and start - now > 0 then
            reminded[ev.id] = true
            personalModule.Alert(string.format(L["Tu banda %s empieza en %d minutos."], "|cFFFFD100" .. ev.title .. "|r", math.ceil((start - now) / 60)))
        end
    end
end

-- =========================================================================
-- INSIGNIAS
-- =========================================================================
-- { {key, label, icon, desc}, ... } para un miembro (con los datos de este cliente)
personalModule.BADGES = {
    { key = "veteran", label = "Veterano", icon = "Interface\\Icons\\Achievement_Guildperk_Honorablemention_Rank2", desc = "Un año o más en la hermandad." },
    { key = "loyal", label = "Nunca falta", icon = "Interface\\Icons\\Achievement_Bg_Winwsg", desc = "90 % o más de asistencia (al menos 5 bandas)." },
    { key = "mythicKiller", label = "Asesino de Mítica", icon = "Interface\\Icons\\Achievement_Boss_Archimonde", desc = "Ha matado un jefe de banda en Mítica con la hermandad." },
    { key = "keyMaster", label = "Maestro de llaves", icon = "Interface\\Icons\\Inv_Relics_Hourglass", desc = "Puntuación de Míticas+ de 2500 o más." },
    { key = "collector", label = "Coleccionista", icon = "Interface\\Icons\\Achievement_Quests_Completed_08", desc = "20.000 puntos de logro o más." },
    { key = "lucky", label = "Afortunado", icon = "Interface\\Icons\\Inv_Misc_Coin_02", desc = "Ha ganado 10 objetos o más en el reparto." },
    { key = "artisan", label = "Artesano", icon = "Interface\\Icons\\Trade_Blacksmithing", desc = "Comparte sus recetas en Comunidad." },
    { key = "upToDate", label = "Al día", icon = "Interface\\Icons\\Inv_Misc_Note_01", desc = "Usa GuildControl y tiene Mi perfil rellenado." },
}

local function JoinTime(name)
    local D = addonTable.Dkp
    local best = D and D.GetSince(name) or nil
    for _, log in ipairs(GuildControlDB.history or {}) do
        if log.action == "ALTA" and log.name == name and log.date then
            local y, m, d = string.match(log.date, "^(%d+)-(%d+)-(%d+)")
            if y then
                local t = time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
                if not best or t < best then best = t end
            end
        end
    end
    return best
end

function personalModule.GetBadges(name)
    local result = {}
    local m = GuildControlDB.members and GuildControlDB.members[name] or {}
    local has = {}
    local joined = JoinTime(name)
    if joined and time() - joined >= 365 * 86400 then has.veteran = true end
    local E = addonTable.RaidEvents
    local stats = E and E.GetAttendanceStats and E.GetAttendanceStats(nil, name)
    if stats and stats.percent and stats.counted >= 5 and stats.percent >= 90 then has.loyal = true end
    if E and E.GetHistory then
        for _, entry in ipairs(E.GetHistory()) do
            local mark = entry.marks[name]
            if entry.difficulty == "mythic" and next(entry.bosses) and (mark == "present" or mark == "late") then has.mythicKiller = true break end
        end
    end
    if (m.mplusScore or 0) >= 2500 then has.keyMaster = true end
    if (m.achievementPoints or 0) >= 20000 then has.collector = true end
    local LT = addonTable.Loot
    if LT then
        local won = 0
        for _, entry in ipairs(LT.GetHistory()) do if entry.winner == name then won = won + 1 end end
        if won >= 10 then has.lucky = true end
    end
    if addonTable.Community and addonTable.Community.HasRecipes and addonTable.Community.HasRecipes(name) then has.artisan = true end
    if addonTable.GetAddonUser and addonTable.GetAddonUser(name) and type(m.declared) == "table" and m.declared.main then has.upToDate = true end
    for _, badge in ipairs(personalModule.BADGES) do
        if has[badge.key] then table.insert(result, badge) end
    end
    return result
end

-- =========================================================================
-- RÉCORDS DE LA HERMANDAD
-- =========================================================================
local function Top(values, count)
    local list = {}
    for name, value in pairs(values) do
        if value and value > 0 then table.insert(list, { name = name, value = value }) end
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.name < b.name
    end)
    while #list > (count or 3) do table.remove(list) end
    return list
end

-- { {label, entries = { {name, value}, ... }, suffix}, ... }
function personalModule.GetRecords()
    local records = {}
    local members = GuildControlDB.members or {}
    local achievements, scores, attendance, items = {}, {}, {}, {}
    local E = addonTable.RaidEvents
    for name, m in pairs(members) do
        achievements[name] = m.achievementPoints
        scores[name] = m.mplusScore and math.floor(m.mplusScore) or nil
        local stats = E and E.GetAttendanceStats and E.GetAttendanceStats(nil, name)
        if stats then attendance[name] = (stats.present or 0) + (stats.late or 0) end
    end
    local LT = addonTable.Loot
    for _, entry in ipairs(LT and LT.GetHistory() or {}) do
        if entry.winner then items[entry.winner] = (items[entry.winner] or 0) + 1 end
    end
    table.insert(records, { label = "Puntos de logro", entries = Top(achievements) })
    table.insert(records, { label = "Puntuación de Míticas+", entries = Top(scores) })
    table.insert(records, { label = "Bandas asistidas", entries = Top(attendance) })
    table.insert(records, { label = "Objetos ganados", entries = Top(items) })
    local D = addonTable.Dkp
    if D and D.IsActive() then
        local dkp = {}
        for _, entry in ipairs(D.GetList()) do dkp[entry.name] = entry.balance end
        table.insert(records, { label = "DKP", entries = Top(dkp) })
    end
    local M = addonTable.MythicPlus
    if M and M.GetGuildWeeklyBest then
        local bestName, bestLevel, bestMap = M.GetGuildWeeklyBest()
        if bestName then
            table.insert(records, { label = "Mejor llave de la semana", entries = { { name = bestName, value = bestLevel } },
                suffix = M.GetMapName(bestMap) })
        end
    end
    return records
end

-- =========================================================================
-- EVENTOS
-- =========================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if type(GuildControlDB) ~= "table" then return end
    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if not (isInitialLogin or isReloadingUi) then return end
        -- Los avisos empiezan cuando el addon ya tiene sus datos (sin avisar de todo lo antiguo)
        C_Timer.After(30, function()
            if addonTable.Loot then
                for _, award in ipairs(addonTable.Loot.GetHistory()) do if award.id then notifiedAwards[award.id] = true end end
                addonTable.Loot.AddListener(CheckLoot)
            end
            if addonTable.Dkp then
                CheckDkp()
                addonTable.Dkp.AddListener(CheckDkp)
            end
            if addonTable.RaidEvents then
                CheckEvents()
                addonTable.RaidEvents.AddListener(CheckEvents)
            end
            CheckRosterAndKey()
            C_Timer.NewTicker(30, function()
                CheckRosterAndKey()
                CheckReminders()
            end)
            SendWishlist()
        end)
        return
    end
    local prefix, msg, channel, sender = ...
    if prefix ~= WISH_PREFIX or channel ~= "GUILD" or type(msg) ~= "string" or not sender then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    if addonTable.IsMe(sender) then return end
    if string.sub(msg, 1, 2) == "W;" then
        local list = {}
        local count = 0
        for id in string.gmatch(string.sub(msg, 3), "(%d+)") do
            count = count + 1
            if count > WISH_MAX then break end
            list[tonumber(id)] = true
        end
        Store("wishlists")[NormalizeName(sender)] = list
        Notify()
    end
end)
