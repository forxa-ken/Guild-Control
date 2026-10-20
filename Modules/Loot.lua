local addonName, addonTable = ...
local L = addonTable.L

addonTable.Loot = {}
local lootModule = addonTable.Loot

-- Sistema de reparto de botín (sin frames): "+1" o "DKP" (lo eligen los oficiales; los saldos,
-- la antigüedad y el decay del DKP están en Dkp.lua). Con DKP, la tirada es una subasta abierta:
-- cada uno puja desde el addon (sin pasar de sus DKP), gana la puja más alta (a igualdad, más
-- antigüedad) y paga lo que pujó. Con +1:
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
--   grupo:     S;clave;dueño;enlace (abre tirada)   K;clave;tipo[;puja] (lo que pido)   E;clave (cancela)
--              V;clave;precio (precio DKP del objeto; se envía antes que S)
--              I;clave;dueño;dificultad;enlace (objeto añadido a mano: así el grupo ve la lista)
--              A;clave;ganador;tipo;tirada (asignado: el grupo lo ve aunque no sea de la hermandad)
--              L (pide la lista al entrar en el grupo o al recargar; responde el líder)
--              N;idSesión;inicio;título (sesión nueva: el grupo empieza la misma)
--              O (Mostrar: se abre el botín a todo el grupo; antes van las reglas y los objetos)
--              M;sistema;modo (reglas del botín de quien abre las tiradas: plusone|dkp, fixed|auction)
--              T;idObjeto;dueño;1|0 (el dueño dice si puede comerciarlo)
--              G;idObjeto;dueño;ganador (entregado: lo manda el dueño o el ganador al completar el comercio)
--
-- Botín personal (Retail): el objeto le cae a uno y solo puede dárselo a otro del grupo durante
-- 2 horas y si no le mejora su equipo. El cliente del dueño mira el tooltip al recibirlo
-- (item.tradeable, item.tradeUntil); no se abre tirada de lo que no se puede comerciar. Al
-- asignarlo a otro, al dueño le sale la ventana de entrega y, al completar el comercio, queda
-- como entregado (item.delivered) para todo el grupo.
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

lootModule.KINDS = { need = "Necesidad (+1)", offspec = "Off-spec", pass = "Pasar", bid = "Puja" }
lootModule.KIND_COLORS = { need = "00FF00", offspec = "66B3FF", pass = "808080", bid = "FFD100" }
lootModule.SYSTEMS = {
    { key = "plusone", label = "+1" },
    { key = "dkp", label = "DKP" },
}

-- Reglas recibidas de quien abre las tiradas en el grupo (líder, ayudante u oficial): mientras
-- dure el grupo mandan sobre las de la hermandad, así todos ven el mismo sistema aunque no
-- sean de la hermandad. Solo en memoria; se borran al salir del grupo o al mandar las mías.
local groupRules = nil   -- { system, mode, from }

-- Sistema activo: lo deciden los oficiales y se comparte con el estado del DKP; en un grupo,
-- el de quien abre las tiradas
function lootModule.GetSystem()
    if groupRules and IsInGroup() then return groupRules.system end
    return addonTable.Dkp and addonTable.Dkp.GetSystem() or "plusone"
end

local function IsDkp() return lootModule.GetSystem() == "dkp" end
lootModule.IsDkp = IsDkp

-- =========================================================================
-- DATOS
-- =========================================================================
local function Store()
    local db = GuildControlDB.loot
    if type(db) ~= "table" then
        db = {}
        GuildControlDB.loot = db
    end
    if type(db.points) ~= "table" then db.points = {} end
    if type(db.pointsAt) ~= "table" then db.pointsAt = {} end
    if type(db.history) ~= "table" then db.history = {} end
    return db
end

local function Notify()
    for _, fn in ipairs(listeners) do fn() end
end
lootModule.Notify = Notify

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

-- Cola de envío al grupo, en orden: si el juego frena los mensajes del prefijo (lista de
-- objetos, reglas, precio y tirada juntos), el que no sale se reintenta en el siguiente turno
-- en vez de perderse.
local sendQueue, sendTicker = {}, nil

local function TrySend(item)
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.msg, item.channel, item.target)
    return ok and (result == nil or result == true or result == 0
        or (Enum and Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.Success))
end

local function ProcessQueue()
    local item = sendQueue[1]
    if not item then
        if sendTicker then sendTicker:Cancel() end
        sendTicker = nil
        return
    end
    item.tries = (item.tries or 0) + 1
    if TrySend(item) or item.tries > 40 then table.remove(sendQueue, 1) end
end

local function QueueSend(item)
    if #sendQueue == 0 and TrySend(item) then return end
    table.insert(sendQueue, item)
    if not sendTicker then sendTicker = C_Timer.NewTicker(0.4, ProcessQueue) end
end

-- Las cuentas de prueba (Starter) no pueden escribir en el canal de banda, tampoco mensajes de
-- addon: en banda lo mandan a su subgrupo y susurrado a quien abre las tiradas (o al líder)
local function IsTrial()
    return (IsTrialAccount and IsTrialAccount()) or (IsVeteranTrialAccount and IsVeteranTrialAccount()) or false
end

local function RollMasterName()
    if groupRules and groupRules.from then return groupRules.from end
    for i = 1, GetNumGroupMembers() do
        if UnitIsGroupLeader("raid" .. i) then return GetUnitName("raid" .. i, true) end
    end
end

local function SendGroup(msg)
    local channel = GroupChannel()
    if not (channel and C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    if channel == "RAID" and IsTrial() then
        QueueSend({ msg = msg, channel = "PARTY" })
        local target = RollMasterName()
        if target and not addonTable.IsMe(target) then QueueSend({ msg = msg, channel = "WHISPER", target = target }) end
        return
    end
    QueueSend({ msg = msg, channel = channel })
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
    -- Herramientas de desarrollador: en el entorno de pruebas el anuncio solo se escribe en tu chat
    if addonTable.Dev and addonTable.Dev.IsSandbox and addonTable.Dev.IsSandbox() then
        print("|cFF00FFFF[GuildControl]|r |cFFFF7F00[Dev]|r " .. text)
        return
    end
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

-- received = { id, startedAt } cuando la sesión nueva llega del grupo (no se reenvía); auto =
-- la abre el addon al salir botín (cada cliente la suya, no se envía: borraría lo de los demás)
function lootModule.NewSession(title, received, auto)
    local instanceName = GetInstanceInfo()
    local session = {
        id = received and received.id or ((UnitName("player") or "?") .. "-" .. GetServerTime()),
        title = (title and title ~= "") and title or (instanceName or L["Banda"]),
        startedAt = received and received.startedAt or GetServerTime(),
        items = {}, order = {},
    }
    Store().session = session
    activeKey = nil
    if not received and not auto and lootModule.CanManage() and IsInGroup() then
        SendGroup("N;" .. session.id .. ";" .. session.startedAt .. ";" .. string.sub(string.gsub(session.title, ";", ""), 1, 80))
        lootModule.SendRules()
    end
    Notify()
    return session
end

local function EnsureSession()
    local session = Store().session
    if not session or GetServerTime() - (session.startedAt or 0) > SESSION_MAX_AGE then
        session = lootModule.NewSession(nil, nil, true)
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

-- =========================================================================
-- PRECIO DE LOS OBJETOS (DKP)
-- =========================================================================
local pendingPrices = {}   -- precio recibido antes que el objeto ("V" llega antes que "S")

local function IsFixed()
    if not IsDkp() then return false end
    if groupRules and IsInGroup() then return groupRules.mode == "fixed" end
    return addonTable.Dkp.GetMode() == "fixed"
end
lootModule.IsFixed = IsFixed

-- Precio del objeto: el que puso un oficial o el de la tabla (hueco y dificultad)
function lootModule.GetItemPrice(item)
    if not item then return 0 end
    if item.price then return item.price end
    if not addonTable.Dkp then return 0 end
    return (addonTable.Dkp.GetDefaultPrice(item.link, item.difficultyID))
end

-- ¿Es una pieza de Mítica? (para el mínimo de DKP de entrada)
function lootModule.GetItemTier(item)
    return addonTable.Dkp and addonTable.Dkp.GetTier(item and item.difficultyID) or "normal"
end

-- Precio fijo: ¿le llegan los DKP para pagar lo que pide? (Main-spec el precio, Off-spec su %)
-- Devuelve si puede y lo que pagaría.
function lootModule.CanAfford(name, item, kind)
    local D = addonTable.Dkp
    if not D or not item then return true, 0 end
    local price = lootModule.GetItemPrice(item)
    local pay = kind == "offspec" and D.GetOffspecPrice(price) or price
    return D.GetBalance(name) >= pay, pay
end

-- Un oficial cambia el precio (nil = volver al predeterminado). Si está en tirada se avisa al grupo.
function lootModule.SetItemPrice(key, price)
    local item = lootModule.GetItem(key)
    if not item or not (addonTable.Profiles and addonTable.Profiles.IsOfficer()) then return false end
    item.price = price and math.max(0, math.floor(tonumber(price) or 0)) or nil
    if item.state == "rolling" then SendGroup("V;" .. key .. ";" .. lootModule.GetItemPrice(item)) end
    Notify()
    return true
end

-- Precio fijo: Main-spec antes que Off-spec (que paga un %), entre los que pueden optar al
-- objeto; a igualdad gana quien tenga más DKP y luego más antigüedad.
-- { {name, kind, price, balance, days, valid, reason, wins}, ... }
local function GetFixedList(item)
    local D = addonTable.Dkp
    local price = lootModule.GetItemPrice(item)
    local tier = lootModule.GetItemTier(item)
    local list = {}
    for name, r in pairs(item and item.rolls or {}) do
        if r.kind == "need" or r.kind == "offspec" then
            local valid, reason = D.CheckEligible(name, tier)
            local balance = D.GetBalance(name)
            local pay = r.kind == "offspec" and D.GetOffspecPrice(price) or price
            if valid and balance < pay then valid, reason = false, "dkp" end
            table.insert(list, { name = name, kind = r.kind, price = pay, roll = pay, balance = balance, points = balance,
                                 days = D.GetSeniorityDays(name), valid = valid, reason = reason,
                                 wins = lootModule.GetSessionWins(name) })
        end
    end
    local kindOrder = { need = 1, offspec = 2 }
    table.sort(list, function(a, b)
        if a.valid ~= b.valid then return a.valid end
        if a.kind ~= b.kind then return kindOrder[a.kind] < kindOrder[b.kind] end
        if a.balance ~= b.balance then return a.balance > b.balance end
        local da, db = a.days or -1, b.days or -1
        if da ~= db then return da > db end
        return a.name < b.name
    end)
    return list
end

local function AddItem(key, link, owner)
    local session = EnsureSession()
    if session.items[key] then return session.items[key] end
    -- Dificultad en la que cayó (para el precio predeterminado del DKP)
    local _, instanceType, difficultyID = GetInstanceInfo()
    local item = { key = key, link = link, owner = owner, at = GetServerTime(), state = "pending", rolls = {},
                   difficultyID = (instanceType == "raid" or instanceType == "party") and difficultyID or nil }
    if pendingPrices[key] then item.price, pendingPrices[key] = pendingPrices[key], nil end
    session.items[key] = item
    table.insert(session.order, key)
    return item
end

-- Manda al grupo mis reglas del botín (al abrir una tirada, al responder a L y al cambiarlas)
function lootModule.SendRules()
    if not (IsInGroup() and lootModule.CanManage()) then return end
    groupRules = nil
    local D = addonTable.Dkp
    SendGroup("M;" .. (D and D.GetSystem() or "plusone") .. ";" .. (D and D.GetMode() or "fixed"))
end

local RULE_LABELS = { plusone = "+1", fixed = "DKP (precio fijo)", auction = "DKP (subasta)" }

-- Envía un objeto de la sesión al grupo (los que salen de la banda ya los ve cada cliente). Si
-- ya está asignado va seguido de su A: quien no estaba o hizo /reload ve también el ganador.
local function SendItem(item)
    SendGroup(table.concat({ "I", item.key, item.owner or "?", tostring(item.difficultyID or 0), ShortLink(item.link) }, ";"))
    if item.state == "done" and item.winner then
        SendGroup(table.concat({ "A", item.key, item.winner, item.kind or "need", tostring(item.roll or 0),
                                 item.awardId or "", tostring(item.awardAt or 0) }, ";"))
    end
end

-- Añadir a mano (enlace de objeto pegado con Shift+clic); difficultyID opcional
function lootModule.AddManual(link, owner, difficultyID)
    if not link or not string.find(link, "|Hitem:", 1, true) then return nil end
    local itemID = string.match(link, "item:(%d+)") or "0"
    local item = AddItem(itemID .. ":" .. (owner or "?") .. ":" .. GetServerTime(), link, owner or "?")
    if difficultyID then item.difficultyID = difficultyID end
    if lootModule.CanManage() then SendItem(item) end
    Notify()
    return item
end

-- Al pedirlo alguien del grupo, el líder le manda los objetos pendientes (como mucho cada 10 s)
local lastListSent = 0
local function SendItemList(force)
    if not force and (not UnitIsGroupLeader("player") or GetTime() - lastListSent < 10) then return end
    lastListSent = GetTime()
    lootModule.SendRules()
    for _, item in ipairs(lootModule.GetItems()) do SendItem(item) end
end

-- Mostrar: abre el botín (con la lista) a todos los del grupo con GuildControl
function lootModule.ShowToGroup()
    if not IsInGroup() then
        print("|cFF00FFFF[GuildControl]|r " .. L["|cFFFF3333No estás en un grupo.|r"])
        return false
    end
    if not lootModule.CanManage() then return false end
    SendItemList(true)
    SendGroup("O")
    print("|cFF00FFFF[GuildControl]|r " .. L["Enseñando el botín a tu grupo."])
    return true
end

-- =========================================================================
-- TIRADAS
-- =========================================================================
-- Orden de prioridad: Necesidad antes que Off-spec; en Necesidad, menos +1 primero; luego la
-- tirada más alta. Devuelve la lista ordenada { {name, roll, kind, points, wins}, ... }
-- Con DKP: pujas de más a menos (las que superan los DKP del jugador van al final), a igualdad
-- más antigüedad y luego el nombre. { {name, bid, kind, balance, days, valid, wins}, ... }
local function GetBidList(item)
    local D = addonTable.Dkp
    local list = {}
    for name, r in pairs(item and item.rolls or {}) do
        if r.kind == "bid" and r.bid then
            local balance = D and D.GetBalance(name) or 0
            table.insert(list, { name = name, kind = "bid", bid = r.bid, roll = r.bid, balance = balance,
                                 days = D and D.GetSeniorityDays(name), valid = r.bid <= balance,
                                 points = balance, wins = lootModule.GetSessionWins(name) })
        end
    end
    table.sort(list, function(a, b)
        if a.valid ~= b.valid then return a.valid end
        if a.bid ~= b.bid then return a.bid > b.bid end
        local da, db = a.days or -1, b.days or -1
        if da ~= db then return da > db end
        return a.name < b.name
    end)
    return list
end

function lootModule.GetRollList(item)
    if IsDkp() then
        if IsFixed() then return GetFixedList(item) end
        return GetBidList(item)
    end
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
    -- Cada vez que se abre empieza de cero (una tirada cancelada no deja pujas ni peticiones)
    item.rolls = {}
    myChoice[key] = nil
end

-- Abre la tirada de un objeto (oficial, líder o ayudante)
function lootModule.StartRoll(key)
    local item = lootModule.GetItem(key)
    if not item or not lootModule.CanManage() then return false end
    if item.tradeable == false then
        print("|cFF00FFFF[GuildControl]|r " .. string.format(L["|cFFFF3333%s no puede comerciar este objeto (le mejora el equipo): se lo queda.|r"],
            Ambiguate(item.owner or "?", "none")))
        return false
    end
    OpenRoll(key)
    lootModule.SendRules()
    -- Con DKP, el precio va antes que el objeto para que la ventanita ya lo muestre
    if IsDkp() then SendGroup("V;" .. key .. ";" .. lootModule.GetItemPrice(item)) end
    SendGroup(table.concat({ "S", key, item.owner or "?", ShortLink(item.link) }, ";"))
    if lootModule.OnRollStarted then lootModule.OnRollStarted(key) end
    if IsFixed() then
        local price = lootModule.GetItemPrice(item)
        Announce(item.link .. L[": Main-spec "] .. price .. L[" DKP, Off-spec "] .. addonTable.Dkp.GetOffspecPrice(price)
            .. L[" DKP. Pídelo en GuildControl."])
    elseif IsDkp() then
        local minBid = lootModule.GetMinBid(item)
        Announce(L["Subasta DKP por "] .. item.link .. L[": puja en GuildControl (mínimo "] .. minBid .. L[" DKP)."])
    else
        Announce(L["Tirada por "] .. item.link .. L[": pulsa Necesidad (+1), Off-spec o Pasar en GuildControl, o escribe /roll."])
    end
    Notify()
    return true
end

function lootModule.CancelRoll(key)
    local item = lootModule.GetItem(key)
    if not item or not lootModule.CanManage() then return end
    if item.state == "rolling" then item.state = "pending" end
    item.rolls = {}
    myChoice[key] = nil
    if activeKey == key then activeKey = nil end
    SendGroup("E;" .. key)
    Notify()
end

-- Mi respuesta: Necesidad u Off-spec lanzan el /roll; Pasar solo avisa
function lootModule.Choose(key, kind)
    local item = lootModule.GetItem(key)
    if not item or item.state ~= "rolling" or not lootModule.KINDS[kind] or myChoice[key] then return end
    if IsFixed() and (kind == "need" or kind == "offspec") then
        local ok, pay = lootModule.CanAfford(MyName(), item, kind)
        if not ok then
            print("|cFF00FFFF[GuildControl]|r " .. string.format(L["|cFFFF3333No tienes DKP suficientes: cuesta %d y tienes %d.|r"], pay, addonTable.Dkp.GetBalance(MyName())))
            return
        end
    end
    myChoice[key] = kind
    local me = MyName()
    item.rolls[me] = item.rolls[me] or {}
    item.rolls[me].kind = kind
    SendGroup("K;" .. key .. ";" .. kind)
    if kind ~= "pass" and not IsDkp() then RandomRoll(1, 100) end
    Notify()
end

function lootModule.GetMyChoice(key) return myChoice[key] end

-- Subasta: la puja mínima es el precio del objeto (o la de los ajustes si no tiene precio)
function lootModule.GetMinBid(item)
    local price = lootModule.GetItemPrice(item)
    if price and price > 0 then return price end
    return addonTable.Dkp and addonTable.Dkp.GetSettings().minBid or 1
end

-- Mi puja (DKP). Se puede subir mientras la subasta siga abierta.
function lootModule.Bid(key, amount)
    local item = lootModule.GetItem(key)
    if not item or item.state ~= "rolling" or not IsDkp() then return false end
    amount = math.floor(tonumber(amount) or 0)
    local D = addonTable.Dkp
    local me = MyName()
    local minBid, balance = lootModule.GetMinBid(item), D.GetBalance(me)
    if amount < minBid then
        print("|cFF00FFFF[GuildControl]|r " .. L["|cFFFF3333La puja mínima es "] .. minBid .. L[" DKP.|r"])
        return false
    end
    if amount > balance then
        print("|cFF00FFFF[GuildControl]|r " .. L["|cFFFF3333No tienes tantos DKP (tienes "] .. balance .. ").|r")
        return false
    end
    local previous = item.rolls[me]
    if previous and previous.kind == "bid" and previous.bid and amount <= previous.bid then
        print("|cFF00FFFF[GuildControl]|r " .. L["|cFFFF3333Para cambiar tu puja tiene que ser más alta.|r"])
        return false
    end
    myChoice[key] = "bid"
    item.rolls[me] = { kind = "bid", bid = amount }
    SendGroup("K;" .. key .. ";bid;" .. amount)
    Notify()
    return true
end

-- Asigna el objeto (al primero de la lista si no se dice a quién)
function lootModule.Award(key, winnerName)
    local item = lootModule.GetItem(key)
    if not item or not lootModule.CanManage() then return nil end
    -- Con DKP solo asignan los oficiales: son los que llevan los saldos
    if IsDkp() and not (addonTable.Profiles and addonTable.Profiles.IsOfficer()) then
        print("|cFF00FFFF[GuildControl]|r " .. L["|cFFFF3333Con DKP solo un oficial puede asignar el objeto.|r"])
        return nil
    end
    local list = lootModule.GetRollList(item)
    local winner
    if winnerName then
        for _, entry in ipairs(list) do if entry.name == winnerName then winner = entry end end
    else
        winner = list[1]
    end
    if not winner then return nil end
    if winner.kind == "bid" and not winner.valid then
        print("|cFF00FFFF[GuildControl]|r " .. L["|cFFFF3333Esa puja supera los DKP del jugador.|r"])
        return nil
    end
    if IsFixed() and not winner.valid then
        print("|cFF00FFFF[GuildControl]|r " .. (winner.reason == "dkp" and L["|cFFFF3333No tiene DKP suficientes para pagarlo.|r"]
            or winner.reason == "gate" and L["|cFFFF3333No llega al mínimo de DKP para piezas de Mítica.|r"]
            or L["|cFFFF3333No llega a la asistencia mínima.|r"]))
        return nil
    end
    -- Con DKP se guarda como "bid" con lo que pagó (puja o precio)
    local paid = IsDkp() and (winner.kind == "bid" and winner.bid or winner.price) or nil
    local session = EnsureSession()
    local at = GetServerTime()
    local id = (UnitName("player") or "?") .. "-" .. at .. "-" .. math.random(1000, 9999)
    local alreadyWon = lootModule.GetSessionWins(winner.name)
    local kind, roll = paid and "bid" or winner.kind, paid or winner.roll
    lootModule.ApplyAward({ id = id, key = key, winner = winner.name, kind = kind, roll = roll,
                            at = at, session = session.id, sessionTitle = session.title, link = item.link, by = MyName() })
    SendGuild(table.concat({ "W", id, key, winner.name, kind, tostring(roll or 0), at, session.id, ShortLink(item.link) }, ";"))
    -- Al grupo va antes que E: así no vuelve a pendiente en quien no recibe la W (fuera de la hermandad)
    SendGroup(table.concat({ "A", key, winner.name, kind, tostring(roll or 0), id, at }, ";"))
    SendGroup("E;" .. key)
    if paid and addonTable.Dkp then addonTable.Dkp.Spend(winner.name, paid, item.link) end
    local short = Ambiguate(winner.name, "none")
    local extra
    if paid then
        extra = " (" .. tostring(paid) .. " DKP" .. (winner.kind == "offspec" and ", off-spec" or "")
    else
        extra = (winner.kind == "need" and L[" (+1, tirada "] or L[" (off-spec, tirada "]) .. tostring(winner.roll or "-")
    end
    local deliver = ""
    if item.owner and item.owner ~= "?" and item.owner ~= winner.name then
        deliver = " " .. string.format(L["%s, entrégaselo por comercio."], Ambiguate(item.owner, "none"))
    end
    Announce(L["Ganador de "] .. item.link .. ": " .. short .. extra .. ")."
        .. (alreadyWon > 0 and (L[" Ya había ganado "] .. alreadyWon .. L[" objeto(s) en esta banda."]) or "") .. deliver)
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
        item.awardId, item.awardAt = award.id, award.at
        if lootModule.CheckDelivery then lootModule.CheckDelivery(item) end
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
    if IsDkp() then return end
    local name, roll, low, high = string.match(text, ROLL_PATTERN)
    roll, low, high = tonumber(roll), tonumber(low), tonumber(high)
    if not name or not roll or low ~= 1 or high ~= 100 then return end
    local item = lootModule.GetItem(activeKey)
    if not item or item.state ~= "rolling" then return end
    -- El mensaje de la tirada puede traer el nombre sin reino aunque sea de otro reino
    -- conectado: el reino se saca del integrante del grupo con ese nombre
    local unitName, unitRealm = UnitName(name)
    if unitName and not (issecretvalue and (issecretvalue(unitName) or issecretvalue(unitRealm))) then
        name = (unitRealm and unitRealm ~= "") and (unitName .. "-" .. unitRealm) or unitName
    end
    local fullName = NormalizeName(name)
    local entry = item.rolls[fullName] or {}
    if entry.roll then return end           -- solo cuenta la primera tirada
    entry.roll = roll
    entry.kind = entry.kind or "need"       -- quien tira sin el addon cuenta como Necesidad
    item.rolls[fullName] = entry
    Notify()
end

-- =========================================================================
-- BOTÍN PERSONAL: COMERCIABLE Y ENTREGA
-- =========================================================================
local TRADE_WINDOW = 2 * 3600
local tradePrefix = BIND_TRADE_TIME_REMAINING and string.match(BIND_TRADE_TIME_REMAINING, "^(.-)%%s")

-- Objeto de la sesión por id, dueño y (si se da) ganador: las claves pueden no coincidir entre
-- clientes, así que lo del botín personal se busca así
local function FindSessionItem(itemID, owner, winner)
    for _, item in ipairs(lootModule.GetItems()) do
        if item.owner == owner and tonumber(string.match(item.link or "", "item:(%d+)")) == itemID
            and (not winner or item.winner == winner) then
            return item
        end
    end
end

-- Hueco de las bolsas con ese objeto (el mismo enlace si puede ser)
local function FindInBags(itemID, link)
    if not (C_Container and C_Container.GetContainerNumSlots) then return nil end
    local fallbackBag, fallbackSlot
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID then
                if info.hyperlink == link then return bag, slot end
                fallbackBag, fallbackSlot = fallbackBag or bag, fallbackSlot or slot
            end
        end
    end
    return fallbackBag, fallbackSlot
end

-- true/false si se sabe (por la línea «Puedes comerciar con este objeto...» del tooltip)
local function IsTradeable(bag, slot)
    if not (tradePrefix and C_TooltipInfo and C_TooltipInfo.GetBagItem) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and not (issecretvalue and issecretvalue(text)) and string.find(text, tradePrefix, 1, true) then
            return true
        end
    end
    return false
end

local function SetTradeable(item, tradeable)
    item.tradeable = tradeable
    item.tradeUntil = tradeable and ((item.at or GetServerTime()) + TRADE_WINDOW) or nil
end

-- Al recibir yo un objeto: miro si puedo comerciarlo y lo digo al grupo (reintenta si aún
-- no está en las bolsas)
local function CheckMyLoot(itemID, link, tries)
    local bag, slot = FindInBags(itemID, link)
    local tradeable = nil
    if bag then tradeable = IsTradeable(bag, slot) end
    if tradeable == nil then
        if (tries or 0) < 4 then C_Timer.After(2, function() CheckMyLoot(itemID, link, (tries or 0) + 1) end) end
        return
    end
    local me = MyName()
    local item = FindSessionItem(itemID, me)
    if item then SetTradeable(item, tradeable); Notify() end
    SendGroup(table.concat({ "T", itemID, me, tradeable and "1" or "0" }, ";"))
end

-- Texto del estado del comercio para la lista de Botín
function lootModule.TradeText(item)
    local left = item.tradeUntil and (item.tradeUntil - GetServerTime()) or nil
    local clock = (left and left > 0) and string.format(" %d:%02d h", math.floor(left / 3600), math.floor(left % 3600 / 60)) or ""
    if item.state == "done" then
        if not item.owner or item.owner == "?" or item.owner == item.winner then return "" end
        if item.delivered then return L["|cFF00FF00entregado|r"] end
        if left and left <= 0 then return L["|cFFFF3333sin entregar|r"] end
        return L["|cFFFF8000pendiente de entregar|r"] .. clock
    end
    if item.tradeable == false then return L["|cFFFF3333no comerciable|r"] end
    if item.tradeable then
        if left and left <= 0 then return L["|cFFFF3333ya no se puede comerciar|r"] end
        return L["|cFF00FF00comerciable|r"] .. clock
    end
    return ""
end

StaticPopupDialogs["GUILDCONTROL_LOOT_DELIVER"] = {
    text = "%s",
    button1 = TRADE or "Comerciar",
    button2 = CANCEL,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function(self, data)
        if not data then return end
        local unit = Ambiguate(data.winner, "none")
        if not UnitExists(unit) then
            print("|cFF00FFFF[GuildControl]|r " .. L["|cFFFF3333No encuentro al ganador en tu grupo.|r"])
            return
        end
        if not pcall(InitiateTrade, unit) then
            print("|cFF00FFFF[GuildControl]|r " .. L["|cFFFF3333No se pudo abrir el comercio: acércate al ganador.|r"])
        end
    end,
}

-- Tras asignar: si el objeto es mío y lo gana otro, me sale la ventana de entrega
function lootModule.CheckDelivery(item)
    local me = MyName()
    if item.state ~= "done" or item.owner ~= me or not item.winner or item.winner == me or item.delivered then return end
    local popup = StaticPopup_Show("GUILDCONTROL_LOOT_DELIVER",
        string.format(L["%s es para %s. Ábrele el comercio y pon el objeto (tienes hasta 2 horas desde que cayó)."],
            lootModule.DisplayLink(item.link), Ambiguate(item.winner, "none")))
    if popup then popup.data = { winner = item.winner, key = item.key } end
end

-- Comercio: se apunta lo que hay en la ventana; al completarse, lo asignado queda entregado
local trade = { target = nil, given = {}, received = {} }

local function SnapshotTrade()
    for i = 1, (MAX_TRADE_ITEMS or 7) - 1 do
        trade.given[i] = GetTradePlayerItemLink and GetTradePlayerItemLink(i) or nil
        trade.received[i] = GetTradeTargetItemLink and GetTradeTargetItemLink(i) or nil
    end
end

local function MarkDelivered(owner, winner, links)
    for _, link in pairs(links) do
        local itemID = tonumber(string.match(link, "item:(%d+)"))
        local item = itemID and FindSessionItem(itemID, owner, winner)
        if item and item.state == "done" and not item.delivered then
            item.delivered = GetServerTime()
            SendGroup(table.concat({ "G", itemID, owner, winner }, ";"))
        end
    end
end

local function OnTradeComplete()
    if not trade.target then return end
    local me = MyName()
    MarkDelivered(me, trade.target, trade.given)      -- yo lo entrego
    MarkDelivered(trade.target, me, trade.received)   -- me lo entregan
    trade.target = nil
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
    if owner == MyName() and tonumber(itemID) then C_Timer.After(1, function() CheckMyLoot(tonumber(itemID), itemLink) end) end
end

-- Quien abre las tiradas ve en el chat la petición que no vale (sin DKP suficientes), una vez
-- por jugador y objeto: así sabe por qué no sale en la lista
local rejectedWarned = {}
local function WarnRejected(fullSender, item)
    if not lootModule.CanManage() or rejectedWarned[item.key .. fullSender] then return end
    rejectedWarned[item.key .. fullSender] = true
    local D = addonTable.Dkp
    print("|cFF00FFFF[GuildControl]|r " .. string.format(L["%s pide %s pero no tiene DKP suficientes (tiene %d): no entra en la lista."],
        Ambiguate(fullSender, "none"), lootModule.DisplayLink(item.link), D and D.GetBalance(fullSender) or 0))
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
            if id and key and winner and at and (wkind == "need" or wkind == "offspec" or wkind == "bid") then
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
    if msg == "L" then
        C_Timer.After(1 + math.random() * 2, SendItemList)
    elseif msg == "O" then
        if not CanManageName(fullSender) then return end
        if lootModule.OnShowRequested then lootModule.OnShowRequested(fullSender) end
    elseif kind == "N;" then
        if not CanManageName(fullSender) then return end
        local _, id, startedAt, title = strsplit(";", msg, 4)
        local current = Store().session
        if id and tonumber(startedAt) and not (current and current.id == id) then
            lootModule.NewSession(title, { id = id, startedAt = tonumber(startedAt) })
        end
    elseif kind == "T;" then
        local _, itemID, owner, flag = strsplit(";", msg)
        if owner ~= fullSender then return end   -- solo lo dice el dueño
        local item = FindSessionItem(tonumber(itemID), owner)
        if item then SetTradeable(item, flag == "1"); Notify() end
    elseif kind == "G;" then
        local _, itemID, owner, winner = strsplit(";", msg)
        if fullSender ~= owner and fullSender ~= winner then return end
        local item = FindSessionItem(tonumber(itemID), owner, winner)
        if item and not item.delivered then item.delivered = GetServerTime(); Notify() end
    elseif kind == "M;" then
        if not CanManageName(fullSender) then return end
        local _, system, mode = strsplit(";", msg)
        if system ~= "plusone" and system ~= "dkp" then return end
        if mode ~= "fixed" and mode ~= "auction" then mode = "fixed" end
        local changed = not groupRules or groupRules.system ~= system or groupRules.mode ~= mode
        groupRules = { system = system, mode = mode, from = fullSender }
        if changed then
            print("|cFF00FFFF[GuildControl]|r " .. string.format(L["El botín de este grupo usa %s (lo ha elegido %s)."],
                L[RULE_LABELS[system == "dkp" and mode or "plusone"]], Ambiguate(fullSender, "none")))
            Notify()
        end
    elseif kind == "I;" then
        if not CanManageName(fullSender) then return end
        local _, key, owner, difficultyID, link = strsplit(";", msg, 5)
        if not key or not link or not string.find(link, "item:", 1, true) then return end
        local item = AddItem(key, link, owner)
        difficultyID = tonumber(difficultyID)
        if difficultyID and difficultyID > 0 then item.difficultyID = difficultyID end
        Notify()
    elseif kind == "A;" then
        if not CanManageName(fullSender) then return end
        local _, key, winner, wkind, roll, id, at = strsplit(";", msg)
        local item = lootModule.GetItem(key)
        if not (item and winner and (wkind == "need" or wkind == "offspec" or wkind == "bid")) then return end
        at = tonumber(at)
        if id and id ~= "" and at and at > 0 then
            -- Con el id va también al historial (sin repetir la W de la hermandad): así lo ve quien no es de ella
            local session = Store().session
            lootModule.ApplyAward({ id = id, key = key, winner = winner, kind = wkind, roll = tonumber(roll), at = at,
                                    session = session and session.id, sessionTitle = session and session.title,
                                    link = item.link, by = fullSender })
        else
            item.state, item.winner, item.kind, item.roll = "done", winner, wkind, tonumber(roll)
            if activeKey == key then activeKey = nil end
            lootModule.CheckDelivery(item)
            Notify()
        end
    elseif kind == "S;" then
        if not CanManageName(fullSender) then return end
        local _, key, owner, link = strsplit(";", msg, 4)
        if not key or not link then return end
        AddItem(key, link, owner)
        OpenRoll(key)
        if lootModule.OnRollStarted then lootModule.OnRollStarted(key) end
        Notify()
    elseif kind == "V;" then
        if not CanManageName(fullSender) then return end
        local _, key, price = strsplit(";", msg)
        price = tonumber(price)
        if not key or not price then return end
        local item = lootModule.GetItem(key)
        if item then
            item.price = price
            Notify()
        else
            pendingPrices[key] = price
        end
    elseif kind == "K;" then
        local _, key, choice, amount = strsplit(";", msg)
        local item = lootModule.GetItem(key)
        if item and item.state == "rolling" and lootModule.KINDS[choice] then
            local bid
            if choice == "bid" then
                -- No se acepta una puja por debajo de la mínima ni por encima de los DKP del jugador
                bid = math.floor(tonumber(amount) or 0)
                local D = addonTable.Dkp
                if bid <= 0 or bid < lootModule.GetMinBid(item) or (D and bid > D.GetBalance(fullSender)) then
                    WarnRejected(fullSender, item)
                    return
                end
            elseif IsFixed() and (choice == "need" or choice == "offspec") and not lootModule.CanAfford(fullSender, item, choice) then
                WarnRejected(fullSender, item)   -- precio fijo: no le llegan los DKP para pagarlo
                return
            end
            item.rolls[fullSender] = item.rolls[fullSender] or {}
            item.rolls[fullSender].kind = choice
            if bid then item.rolls[fullSender].bid = math.max(bid, item.rolls[fullSender].bid or 0) end
            Notify()
        end
    elseif kind == "E;" then
        if not CanManageName(fullSender) then return end
        local key = string.sub(msg, 3)
        local item = lootModule.GetItem(key)
        if item and item.state == "rolling" then
            item.state = "pending"
            item.rolls = {}
            myChoice[key] = nil
        end
        if activeKey == key then activeKey = nil end
        Notify()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("GROUP_JOINED")
frame:RegisterEvent("GROUP_LEFT")
frame:RegisterEvent("TRADE_SHOW")
frame:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED")
frame:RegisterEvent("TRADE_TARGET_ITEM_CHANGED")
frame:RegisterEvent("TRADE_ACCEPT_UPDATE")
frame:RegisterEvent("UI_INFO_MESSAGE")
frame:SetScript("OnEvent", function(_, event, ...)
    if not GuildControlDB then return end
    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin or isReloadingUi then
            C_Timer.After(18, function() SendGuild("Q") end)
            C_Timer.After(20, function() if not UnitIsGroupLeader("player") then SendGroup("L") end end)
        end
    elseif event == "TRADE_SHOW" then
        local name, realm = UnitName("NPC")
        trade.target = (name and not (issecretvalue and issecretvalue(name)))
            and NormalizeName((realm and realm ~= "") and (name .. "-" .. realm) or name) or nil
        wipe(trade.given); wipe(trade.received)
    elseif event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_TARGET_ITEM_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then
        if trade.target then SnapshotTrade() end
    elseif event == "UI_INFO_MESSAGE" then
        local _, text = ...
        if trade.target and type(text) == "string" and not (issecretvalue and issecretvalue(text)) and text == ERR_TRADE_COMPLETE then
            OnTradeComplete()
        end
    elseif event == "GROUP_LEFT" then
        if groupRules then groupRules = nil; Notify() end
    elseif event == "GROUP_JOINED" then
        C_Timer.After(3, function() if not UnitIsGroupLeader("player") then SendGroup("L") end end)
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
        if addonTable.IsMe(sender) then return end
        OnAddonMessage(msg, channel, sender)
    end
end)
