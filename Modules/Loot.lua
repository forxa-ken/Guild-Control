local addonName, addonTable = ...
local L = addonTable.L

addonTable.Loot = {}
local lootModule = addonTable.Loot

-- Sistema de reparto de botín (sin frames). De momento solo "+1" (DKP vendrá después):
--   - Los objetos que salen en la banda (ENCOUNTER_LOOT_RECEIVED) se apuntan en la sesión.
--   - Un oficial o el líder abre la tirada de un objeto; cada jugador elige Necesidad (+1),
--     Off-spec o Pasar y el addon lanza el /roll. Quien no tiene el addon puede tirar a mano.
--   - Gana la Necesidad de quien tenga menos +1 y, a igualdad, la tirada más alta; si nadie
--     pide Necesidad, la Off-spec más alta (no suma +1).
--   - El ganador suma +1, queda en el historial y se avisa si ya ganó algo en esta banda.
--
-- GuildControlDB.loot = {
--   system = "plusone",
--   points = { [Nombre-Reino] = n }, pointsAt = { [Nombre-Reino] = hora },
--   history = { {id, at, link, winner, kind, roll, session, sessionTitle, by}, ... } (recientes primero),
--   session = { id, title, startedAt, items = { [clave] = item }, order = { clave, ... } },
-- }
-- item = { key, link, owner, at, state = "pending"|"rolling"|"done", winner, kind, roll,
--          rolls = { [Nombre-Reino] = { roll, kind } } }
--
-- Mensajes (prefijo GuildControlLoot):
--   grupo:     S;clave;dueño;enlace (abre tirada)   K;clave;tipo (lo que pido)   E;clave (cancela)
--   hermandad: W;id;clave;ganador;tipo;tirada;hora;sesión;enlace (asignado)   Z;hora (reinicio de +1)
--              Q (petición al entrar)   P;nombre;puntos;hora (puntos de un jugador, en respuesta)

local PREFIX = "GuildControlLoot"
local HISTORY_MAX = 500
local SESSION_MAX_AGE = 6 * 3600

local listeners = {}
local activeKey = nil          -- objeto con la tirada abierta
local myChoice = {}            -- [clave] = tipo que he elegido

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

lootModule.KINDS = { need = "Necesidad (+1)", offspec = "Off-spec", pass = "Pasar" }
lootModule.KIND_COLORS = { need = "00FF00", offspec = "66B3FF", pass = "808080" }
lootModule.SYSTEMS = {
    { key = "plusone", label = "+1" },
    { key = "dkp", label = "DKP (próximamente)", disabled = true },
}

-- =========================================================================
-- DATOS
-- =========================================================================
local function Store()
    local db = GuildControlDB.loot
    if type(db) ~= "table" then
        db = {}
        GuildControlDB.loot = db
    end
    if db.system ~= "plusone" then db.system = "plusone" end
    if type(db.points) ~= "table" then db.points = {} end
    if type(db.pointsAt) ~= "table" then db.pointsAt = {} end
    if type(db.history) ~= "table" then db.history = {} end
    return db
end

local function Notify()
    for _, fn in ipairs(listeners) do fn() end
end

function lootModule.AddListener(fn)
    table.insert(listeners, fn)
end

local function NormalizeName(name)
    if addonTable.Profiles and addonTable.Profiles.NormalizeName then return addonTable.Profiles.NormalizeName(name) end
    return name
end

local function MyName() return NormalizeName(UnitName("player")) end

local function GroupChannel()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

local function SendGroup(msg)
    local channel = GroupChannel()
    if channel and C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(PREFIX, msg, channel) end
end

local function SendGuild(msg)
    if IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD") end
end


-- Los mensajes de addon admiten 255 caracteres: un enlace muy largo (muchas bonificaciones)
-- se envía como el enlace básico del objeto o "item:ID"
local function ShortLink(link)
    if not link or #link <= 170 then return link end
    local itemID = tonumber(string.match(link, "item:(%d+)"))
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local basic = itemID and getInfo and select(2, getInfo(itemID))
    if basic and #basic <= 170 then return basic end
    return itemID and ("item:" .. itemID) or ""
end

-- Enlace para mostrar: si llegó como "item:ID" se resuelve con la caché de objetos
function lootModule.DisplayLink(link)
    if not link then return "?" end
    local itemID = tonumber(string.match(link, "^item:(%d+)$"))
    if not itemID then return link end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    return (getInfo and select(2, getInfo(itemID))) or ("item:" .. itemID)
end

local function Announce(text)
    local channel = GroupChannel()
    if not channel then return end
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        pcall(C_ChatInfo.SendChatMessage, text, channel)
    else
        pcall(SendChatMessage, text, channel)
    end
end

-- Puede abrir y asignar tiradas: oficial, líder o ayudante del grupo
function lootModule.CanManage()
    if addonTable.Profiles and addonTable.Profiles.IsOfficer() then return true end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function CanManageName(fullName)
    if addonTable.Profiles and addonTable.Profiles.IsOfficerName and addonTable.Profiles.IsOfficerName(fullName) then return true end
    local short = Ambiguate(fullName, "none")
    return UnitIsGroupLeader(short) or UnitIsGroupAssistant(short)
end

function lootModule.GetPoints(fullName)
    return Store().points[fullName] or 0
end

-- Objetos ganados por un jugador en la sesión actual
function lootModule.GetSessionWins(fullName)
    local session = Store().session
    if not session then return 0 end
    local wins = 0
    for _, entry in ipairs(Store().history) do
        if entry.session == session.id and entry.winner == fullName then wins = wins + 1 end
    end
    return wins
end

-- =========================================================================
-- SESIÓN Y OBJETOS
-- =========================================================================
function lootModule.GetSession() return Store().session end

function lootModule.NewSession(title)
    local instanceName = GetInstanceInfo()
    local session = {
        id = (UnitName("player") or "?") .. "-" .. GetServerTime(),
        title = (title and title ~= "") and title or (instanceName or L["Banda"]),
        startedAt = GetServerTime(),
        items = {}, order = {},
    }
    Store().session = session
    activeKey = nil
    Notify()
    return session
end

local function EnsureSession()
    local session = Store().session
    if not session or GetServerTime() - (session.startedAt or 0) > SESSION_MAX_AGE then
        session = lootModule.NewSession()
    end
    return session
end

-- Objetos de la sesión en orden de llegada
function lootModule.GetItems()
    local session = Store().session
    local list = {}
    if not session then return list end
    for _, key in ipairs(session.order) do
        if session.items[key] then table.insert(list, session.items[key]) end
    end
    return list
end

function lootModule.GetItem(key)
    local session = Store().session
    return session and key and session.items[key] or nil
end

function lootModule.GetActiveKey() return activeKey end

local function AddItem(key, link, owner)
    local session = EnsureSession()
    if session.items[key] then return session.items[key] end
    local item = { key = key, link = link, owner = owner, at = GetServerTime(), state = "pending", rolls = {} }
    session.items[key] = item
    table.insert(session.order, key)
    return item
end

-- Añadir a mano (enlace de objeto pegado con Shift+clic)
function lootModule.AddManual(link, owner)
    if not link or not string.find(link, "|Hitem:", 1, true) then return nil end
    local itemID = string.match(link, "item:(%d+)") or "0"
    local item = AddItem(itemID .. ":" .. (owner or "?") .. ":" .. GetServerTime(), link, owner or "?")
    Notify()
    return item
end

-- =========================================================================
-- TIRADAS
-- =========================================================================
-- Orden de prioridad: Necesidad antes que Off-spec; en Necesidad, menos +1 primero; luego la
-- tirada más alta. Devuelve la lista ordenada { {name, roll, kind, points, wins}, ... }
function lootModule.GetRollList(item)
    local list = {}
    for name, r in pairs(item and item.rolls or {}) do
        if r.kind ~= "pass" then
            table.insert(list, { name = name, roll = r.roll, kind = r.kind or "need",
                                 points = lootModule.GetPoints(name), wins = lootModule.GetSessionWins(name) })
        end
    end
    local kindOrder = { need = 1, offspec = 2 }
    table.sort(list, function(a, b)
        local ka, kb = kindOrder[a.kind] or 3, kindOrder[b.kind] or 3
        if ka ~= kb then return ka < kb end
        if a.kind == "need" and a.points ~= b.points then return a.points < b.points end
        local ra, rb = a.roll or 0, b.roll or 0
        if ra ~= rb then return ra > rb end
        return a.name < b.name
    end)
    return list
end

-- Quien ha pedido "Pasar" (para mostrarlo aparte)
function lootModule.GetPassList(item)
    local list = {}
    for name, r in pairs(item and item.rolls or {}) do
        if r.kind == "pass" then table.insert(list, name) end
    end
    table.sort(list)
    return list
end

local function OpenRoll(key)
    local item = lootModule.GetItem(key)
    if not item then return end
    if activeKey and activeKey ~= key then
        local previous = lootModule.GetItem(activeKey)
        if previous and previous.state == "rolling" then previous.state = "pending" end
    end
    activeKey = key
    item.state = "rolling"
    item.rolls = item.rolls or {}
    myChoice[key] = nil
end

-- Abre la tirada de un objeto (oficial, líder o ayudante)
function lootModule.StartRoll(key)
    local item = lootModule.GetItem(key)
    if not item or not lootModule.CanManage() then return false end
    OpenRoll(key)
    SendGroup(table.concat({ "S", key, item.owner or "?", ShortLink(item.link) }, ";"))
    if lootModule.OnRollStarted then lootModule.OnRollStarted(key) end
    Announce(L["Tirada por "] .. item.link .. L[": pulsa Necesidad (+1), Off-spec o Pasar en GuildControl, o escribe /roll."])
    Notify()
    return true
end

function lootModule.CancelRoll(key)
    local item = lootModule.GetItem(key)
    if not item or not lootModule.CanManage() then return end
    if item.state == "rolling" then item.state = "pending" end
    if activeKey == key then activeKey = nil end
    SendGroup("E;" .. key)
    Notify()
end

-- Mi respuesta: Necesidad u Off-spec lanzan el /roll; Pasar solo avisa
function lootModule.Choose(key, kind)
    local item = lootModule.GetItem(key)
    if not item or item.state ~= "rolling" or not lootModule.KINDS[kind] or myChoice[key] then return end
    myChoice[key] = kind
    local me = MyName()
    item.rolls[me] = item.rolls[me] or {}
    item.rolls[me].kind = kind
    SendGroup("K;" .. key .. ";" .. kind)
    if kind ~= "pass" then RandomRoll(1, 100) end
    Notify()
end

function lootModule.GetMyChoice(key) return myChoice[key] end

-- Asigna el objeto (al primero de la lista si no se dice a quién)
function lootModule.Award(key, winnerName)
    local item = lootModule.GetItem(key)
    if not item or not lootModule.CanManage() then return nil end
    local list = lootModule.GetRollList(item)
    local winner
    if winnerName then
        for _, entry in ipairs(list) do if entry.name == winnerName then winner = entry end end
    else
        winner = list[1]
    end
    if not winner then return nil end
    local session = EnsureSession()
    local at = GetServerTime()
    local id = (UnitName("player") or "?") .. "-" .. at .. "-" .. math.random(1000, 9999)
    local alreadyWon = lootModule.GetSessionWins(winner.name)
    lootModule.ApplyAward({ id = id, key = key, winner = winner.name, kind = winner.kind, roll = winner.roll,
                            at = at, session = session.id, sessionTitle = session.title, link = item.link, by = MyName() })
    SendGuild(table.concat({ "W", id, key, winner.name, winner.kind, tostring(winner.roll or 0), at, session.id, ShortLink(item.link) }, ";"))
    SendGroup("E;" .. key)
    local short = Ambiguate(winner.name, "none")
    local extra = winner.kind == "need" and L[" (+1, tirada "] or L[" (off-spec, tirada "]
    Announce(L["Ganador de "] .. item.link .. ": " .. short .. extra .. tostring(winner.roll or "-") .. ")."
        .. (alreadyWon > 0 and (L[" Ya había ganado "] .. alreadyWon .. L[" objeto(s) en esta banda."]) or ""))
    return winner
end

-- Registra una asignación (propia o recibida de un oficial); no se repite si ya estaba
function lootModule.ApplyAward(award)
    local db = Store()
    for _, entry in ipairs(db.history) do
        if entry.id == award.id then return end
    end
    table.insert(db.history, 1, award)
    while #db.history > HISTORY_MAX do table.remove(db.history) end
    if award.kind == "need" then
        db.points[award.winner] = (db.points[award.winner] or 0) + 1
        db.pointsAt[award.winner] = award.at
    end
    local item = lootModule.GetItem(award.key)
    if item then
        item.state, item.winner, item.kind, item.roll = "done", award.winner, award.kind, award.roll
    end
    if activeKey == award.key then activeKey = nil end
    Notify()
end

-- Ranking de +1: { {name, points}, ... } de más a menos
function lootModule.GetPointsList()
    local list = {}
    for name, points in pairs(Store().points) do
        if points > 0 then table.insert(list, { name = name, points = points }) end
    end
    table.sort(list, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        return a.name < b.name
    end)
    return list
end

function lootModule.GetHistory() return Store().history end

-- Pone a cero los +1 de todos (oficiales); el historial se conserva
function lootModule.ResetPoints()
    if not (addonTable.Profiles and addonTable.Profiles.IsOfficer()) then return end
    local db = Store()
    local at = GetServerTime()
    wipe(db.points)
    db.pointsResetAt = at
    SendGuild("Z;" .. at)
    Notify()
end

-- =========================================================================
-- SINCRONIZACIÓN DE +1 AL ENTRAR
-- =========================================================================
local replyTimer, replyTicker = nil, nil
local function ReplyPoints()
    local queue = {}
    for name, points in pairs(Store().points) do
        table.insert(queue, table.concat({ "P", name, points, Store().pointsAt[name] or 0 }, ";"))
    end
    if #queue == 0 then return end
    replyTicker = C_Timer.NewTicker(0.2, function()
        local msg = table.remove(queue)
        if msg then SendGuild(msg) end
        if #queue == 0 and replyTicker then replyTicker:Cancel(); replyTicker = nil end
    end)
end

-- =========================================================================
-- EVENTOS
-- =========================================================================
-- "%s tira %d (%d-%d)" del idioma del cliente convertido en patrón
local ROLL_PATTERN = nil
if RANDOM_ROLL_RESULT then
    local pattern = string.gsub(RANDOM_ROLL_RESULT, "([%(%)%.%-%+%[%]%^%$%?%*])", "%%%1")
    pattern = string.gsub(pattern, "%%s", "(.+)")
    pattern = string.gsub(pattern, "%%d", "(%%d+)")
    ROLL_PATTERN = "^" .. pattern .. "$"
end

local function OnRollResult(text)
    if not activeKey or not ROLL_PATTERN then return end
    local name, roll, low, high = string.match(text, ROLL_PATTERN)
    roll, low, high = tonumber(roll), tonumber(low), tonumber(high)
    if not name or not roll or low ~= 1 or high ~= 100 then return end
    local item = lootModule.GetItem(activeKey)
    if not item or item.state ~= "rolling" then return end
    local fullName = NormalizeName(name)
    local entry = item.rolls[fullName] or {}
    if entry.roll then return end           -- solo cuenta la primera tirada
    entry.roll = roll
    entry.kind = entry.kind or "need"       -- quien tira sin el addon cuenta como Necesidad
    item.rolls[fullName] = entry
    Notify()
end

local function OnLootReceived(...)
    local _, itemID, itemLink, _, playerName = ...
    if issecretvalue and (issecretvalue(itemLink) or issecretvalue(playerName)) then return end
    if not itemLink or not playerName or not IsInGroup() then return end
    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "raid" and instanceType ~= "party" then return end
    local owner = NormalizeName(playerName)
    -- La misma entrega puede llegar dos veces: clave por objeto, dueño y minuto
    AddItem(tostring(itemID) .. ":" .. owner .. ":" .. math.floor(GetServerTime() / 60), itemLink, owner)
    Notify()
end

local function OnAddonMessage(msg, channel, sender)
    local fullSender = NormalizeName(sender)
    local kind = string.sub(msg, 1, 2)
    if channel == "GUILD" then
        if msg == "Q" then
            if not (addonTable.Profiles and addonTable.Profiles.IsOfficer()) or replyTimer then return end
            replyTimer = C_Timer.NewTimer(3 + math.random() * 5, function() replyTimer = nil; ReplyPoints() end)
            return
        end
        if not (addonTable.Profiles and addonTable.Profiles.IsOfficerName(fullSender)) then return end
        if kind == "W;" then
            local _, id, key, winner, wkind, roll, at, session, link = strsplit(";", msg, 9)
            at = tonumber(at)
            if id and key and winner and at and (wkind == "need" or wkind == "offspec") then
                lootModule.ApplyAward({ id = id, key = key, winner = winner, kind = wkind, roll = tonumber(roll),
                                        at = at, session = session, link = link, by = fullSender })
            end
        elseif kind == "Z;" then
            local at = tonumber(string.sub(msg, 3))
            local db = Store()
            if at and at > (db.pointsResetAt or 0) then
                wipe(db.points)
                db.pointsResetAt = at
                Notify()
            end
        elseif kind == "P;" then
            if replyTimer then replyTimer:Cancel(); replyTimer = nil end
            local _, name, points, at = strsplit(";", msg)
            points, at = tonumber(points), tonumber(at) or 0
            local db = Store()
            if name and points and at >= (db.pointsResetAt or 0) and at > (db.pointsAt[name] or -1) then
                db.points[name], db.pointsAt[name] = points, at
                Notify()
            end
        end
        return
    end

    -- Mensajes del grupo
    if kind == "S;" then
        if not CanManageName(fullSender) then return end
        local _, key, owner, link = strsplit(";", msg, 4)
        if not key or not link then return end
        AddItem(key, link, owner)
        OpenRoll(key)
        if lootModule.OnRollStarted then lootModule.OnRollStarted(key) end
        Notify()
    elseif kind == "K;" then
        local _, key, choice = strsplit(";", msg)
        local item = lootModule.GetItem(key)
        if item and item.state == "rolling" and lootModule.KINDS[choice] then
            item.rolls[fullSender] = item.rolls[fullSender] or {}
            item.rolls[fullSender].kind = choice
            Notify()
        end
    elseif kind == "E;" then
        if not CanManageName(fullSender) then return end
        local key = string.sub(msg, 3)
        local item = lootModule.GetItem(key)
        if item and item.state == "rolling" then item.state = "pending" end
        if activeKey == key then activeKey = nil end
        Notify()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if not GuildControlDB then return end
    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin or isReloadingUi then C_Timer.After(18, function() SendGuild("Q") end) end
    elseif event == "ENCOUNTER_LOOT_RECEIVED" then
        OnLootReceived(...)
    elseif event == "CHAT_MSG_SYSTEM" then
        local text = ...
        if issecretvalue and issecretvalue(text) then return end
        if type(text) == "string" then OnRollResult(text) end
    else
        local prefix, msg, channel, sender = ...
        if prefix ~= PREFIX or not msg or not sender then return end
        if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
        if Ambiguate(sender, "none") == UnitName("player") then return end
        OnAddonMessage(msg, channel, sender)
    end
end)
