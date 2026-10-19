local addonName, addonTable = ...
local L = addonTable.L

addonTable.Community = {}
local communityModule = addonTable.Community

-- Comunidad (sin frames; la UI está en UI.lua, pestaña Profesiones). En Retail no hay
-- Buscar grupo: el buscador de grupos del juego ya lo hace.
--   - Artesanos: cada jugador con GuildControl comparte las recetas que conoce de sus
--     profesiones (al cerrar la ventana de profesión). GuildControlDB.recipes[Nombre-Reino] =
--     { [profesión] = { at, ids = { recipeID, ... } } }. Prefijo GuildControlCrft, troceado:
--       R;msgId;i;total;profesión;id,id,...

-- Máximo 16 caracteres: con "GuildControlCraft" (17) el juego no registraba el prefijo ni
-- enviaba los mensajes, así que las recetas de los demás nunca llegaban
local CRAFT_PREFIX = "GuildControlCrft"

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(CRAFT_PREFIX)
end

local listeners = {}
local function Notify()
    for _, fn in ipairs(listeners) do fn() end
end
function communityModule.AddListener(fn) table.insert(listeners, fn) end

local function MyName()
    if addonTable.Profiles and addonTable.Profiles.GetMyFullName then return addonTable.Profiles.GetMyFullName() end
    return UnitName("player")
end

local function NormalizeName(name)
    if addonTable.Profiles and addonTable.Profiles.NormalizeName then return addonTable.Profiles.NormalizeName(name) end
    return name
end

local function Clean(text, maxLen)
    text = string.gsub(tostring(text or ""), "[;|]", "")
    return string.sub(strtrim(text), 1, maxLen)
end

-- Diagnóstico (/gct recetas): durante 2 minutos se avisa en el chat de cada petición y
-- respuesta de recetas
local recipeDebugUntil = 0
local function RecipeDebug(text)
    if GetTime() < recipeDebugUntil then print("|cFF00FFFF[GuildControl]|r |cFF808080[recetas]|r " .. text) end
end

local function Send(prefix, msg)
    if not IsInGuild() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    pcall(C_ChatInfo.SendAddonMessage, prefix, msg, "GUILD")
end

-- =========================================================================
-- ARTESANOS: RECETAS CONOCIDAS
-- =========================================================================
local function RecipeStore()
    if type(GuildControlDB.recipes) ~= "table" then GuildControlDB.recipes = {} end
    return GuildControlDB.recipes
end

function communityModule.HasRecipes(name)
    local entry = name and RecipeStore()[name]
    return entry ~= nil and next(entry) ~= nil
end

-- Recetas aprendidas de la profesión abierta: profesión, { recipeID, ... }
local function CollectOpenRecipes()
    if not (C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillReady and C_TradeSkillUI.IsTradeSkillReady()) then return nil end
    if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then return nil end
    if C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then return nil end
    local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    local profession = info and info.professionName
    if not profession or profession == "" then return nil end
    local ids = {}
    for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local ok, recipe = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and recipe and recipe.learned then table.insert(ids, recipeID) end
    end
    table.sort(ids)
    return profession, ids
end

-- Un mensaje de addon admite 255 bytes. En Forever los IDs de receta tienen hasta 7 cifras:
-- los trozos se cortan por tamaño (antes, 30 IDs por trozo pasaban del límite y el juego
-- descartaba el mensaje sin avisar, así que las recetas de los demás nunca llegaban)
local MAX_RECIPE_MSG_BYTES = 240

local function SendRecipes(profession, ids)
    if not IsInGuild() then return end
    local msgId = tostring(math.random(100000, 999999))
    profession = Clean(profession, 40)
    -- Cabecera: "R;msgId;iii;ttt;profesión;" (con margen para i y total de tres cifras)
    local room = MAX_RECIPE_MSG_BYTES - (#"R;" + #msgId + #";999;999;" + #profession + 1)
    local chunks, current = {}, {}
    local size = 0
    for _, id in ipairs(ids) do
        local text = tostring(id)
        local extra = #text + (#current > 0 and 1 or 0)
        if #current > 0 and size + extra > room then
            table.insert(chunks, table.concat(current, ","))
            current, size, extra = {}, 0, #text
        end
        table.insert(current, text)
        size = size + extra
    end
    if #current > 0 or #chunks == 0 then table.insert(chunks, table.concat(current, ",")) end
    local total = #chunks
    local queue = {}
    for i, chunk in ipairs(chunks) do
        table.insert(queue, table.concat({ "R", msgId, i, total, profession, chunk }, ";"))
    end
    local ticker
    ticker = C_Timer.NewTicker(0.4, function()
        local msg = table.remove(queue, 1)
        if msg then Send(CRAFT_PREFIX, msg) end
        if #queue == 0 and ticker then ticker:Cancel() end
    end)
end

local pendingProfession, pendingIds = nil, nil
local sentThisSession = {}   -- [profesión] = true: ya enviada en esta sesión
local collectTimer = nil
local function OnTradeSkillUpdate()
    local profession, ids = CollectOpenRecipes()
    if not profession then return end
    local mine = RecipeStore()[MyName()] or {}
    RecipeStore()[MyName()] = mine
    local old = mine[profession]
    local changed = not old or #old.ids ~= #ids
    mine[profession] = { at = time(), ids = ids }
    -- También la primera vez en cada sesión, aunque no haya cambiado: quien no estaba
    -- conectado la última vez no la tiene
    if changed or not sentThisSession[profession] then pendingProfession, pendingIds = profession, ids end
end

-- Envía todas mis recetas guardadas (respuesta a una petición "Q")
local lastRecipeReply = -60
local function SendAllMyRecipes()
    if GetTime() - lastRecipeReply < 30 then return end
    RecipeDebug(L["Alguien ha pedido las recetas: enviando las mías."])
    lastRecipeReply = GetTime()
    local delay = 0
    for profession, data in pairs(RecipeStore()[MyName()] or {}) do
        if type(data) == "table" and type(data.ids) == "table" and #data.ids > 0 then
            C_Timer.After(delay, function() SendRecipes(profession, data.ids) end)
            sentThisSession[profession] = true
            delay = delay + 3
        end
    end
end

-- Pide a la hermandad las recetas de todos (al entrar y al abrir Artesanos y pedidos).
-- Cada cliente con GuildControl responde con las suyas.
local lastRecipeRequest = -120
function communityModule.RequestRecipes(force)
    if not force and GetTime() - lastRecipeRequest < 60 then return end
    lastRecipeRequest = GetTime()
    RecipeDebug(L["Pidiendo las recetas a la hermandad..."])
    Send(CRAFT_PREFIX, "Q")
end

function communityModule.DebugRecipes()
    recipeDebugUntil = GetTime() + 120
    local mine, crafters = 0, 0
    for profession, data in pairs(RecipeStore()[MyName()] or {}) do
        if type(data) == "table" and type(data.ids) == "table" then mine = mine + #data.ids end
    end
    for name, professions in pairs(RecipeStore()) do
        if name ~= MyName() and next(professions) then crafters = crafters + 1 end
    end
    print("|cFF00FFFF[GuildControl]|r " .. string.format(L["Recetas: tienes %d guardadas; de otros jugadores, %d."], mine, crafters))
    local myVersion = tostring(addonTable.VERSION)
    for name, user in pairs(GuildControlDB.addonUsers or {}) do
        if name ~= MyName() then
            local ago = math.floor((time() - (user.at or 0)) / 60)
            local same = user.version == myVersion
            print("   " .. name .. ": " .. (same and "|cFF00FF00" or "|cFFFF7F00") .. tostring(user.version or "?") .. "|r"
                .. string.format(L[" · último mensaje hace %d min"], ago))
        end
    end
    print("   " .. L["Tu versión: "] .. myVersion .. L[". Todos deben tener la misma versión del addon."])
    communityModule.RequestRecipes(true)
end

local partials = {}
local function OnCraftMessage(sender, msg)
    local _, msgId, index, total, profession, chunk = strsplit(";", msg, 6)
    index, total = tonumber(index), tonumber(total)
    if not msgId or not index or not total or total > 100 or not profession then return end
    local key = sender .. ":" .. msgId
    local partial = partials[key] or { total = total, parts = {}, count = 0 }
    partials[key] = partial
    if not partial.parts[index] then
        partial.parts[index] = chunk or ""
        partial.count = partial.count + 1
    end
    if partial.count < partial.total then return end
    partials[key] = nil
    local ids = {}
    for i = 1, partial.total do
        for id in string.gmatch(partial.parts[i] or "", "(%d+)") do table.insert(ids, tonumber(id)) end
    end
    local entry = RecipeStore()[sender] or {}
    RecipeStore()[sender] = entry
    entry[profession] = { at = time(), ids = ids }
    RecipeDebug(string.format(L["Recibidas %d recetas de %s (%s)."], #ids, sender, profession))
    Notify()
end

local recipeNameCache = {}
local function RecipeName(recipeID)
    local name = recipeNameCache[recipeID]
    if name == nil then
        name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(recipeID))
            or (C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and (C_TradeSkillUI.GetRecipeInfo(recipeID) or {}).name) or false
        recipeNameCache[recipeID] = name
    end
    return name or nil
end
communityModule.RecipeName = RecipeName

-- Busca recetas por nombre: { {recipeID, name, profession, crafters = { nombre, ... }}, ... }
function communityModule.SearchRecipes(query, limit)
    query = string.lower(strtrim(query or ""))
    if #query < 3 then return {} end
    local byRecipe = {}
    for crafter, professions in pairs(RecipeStore()) do
        for profession, data in pairs(professions) do
            for _, recipeID in ipairs(data.ids or {}) do
                local name = RecipeName(recipeID)
                if name and string.find(string.lower(name), query, 1, true) then
                    local entry = byRecipe[recipeID]
                    if not entry then
                        entry = { recipeID = recipeID, name = name, profession = profession, crafters = {}, seen = {} }
                        byRecipe[recipeID] = entry
                    end
                    -- Cada artesano una sola vez por receta: la misma receta puede estar en
                    -- varias listas suyas (la profesión recibida con otro nombre, o repetida)
                    local key = NormalizeName(crafter) or crafter
                    if not entry.seen[key] then
                        entry.seen[key] = true
                        table.insert(entry.crafters, key)
                    end
                end
            end
        end
    end
    local list = {}
    for _, entry in pairs(byRecipe) do
        entry.seen = nil
        table.sort(entry.crafters)
        table.insert(list, entry)
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    while #list > (limit or 50) do table.remove(list) end
    return list
end

-- Cuántos artesanos han compartido recetas
function communityModule.CountCrafters()
    local count = 0
    for _, professions in pairs(RecipeStore()) do
        if next(professions) then count = count + 1 end
    end
    return count
end

-- =========================================================================
-- PEDIDOS A ARTESANOS
-- =========================================================================
-- Un jugador pide una receta a un artesano. GuildControlDB.craftOrders[id] =
--   { id, requester, crafter, recipeID, note, status, at, updatedAt }
-- status: "pending" (pedido), "accepted" (aceptado), "done" (hecho), "rejected" (rechazado),
-- "cancelled" (cancelado por quien lo pidió). Prefijo GuildControlOrd en la hermandad:
--   O;id;artesano;recipeID;hora;materiales;nota   pedido nuevo (lo envía quien pide);
--                                     materiales = 1 si quien pide los aporta, 0 si no
--   U;id;estado;hora                    cambio de estado (artesano o quien pide)
--   Q                                   al entrar: cada uno reenvía sus pedidos abiertos
-- Solo guardan el pedido el artesano y quien lo pide. Los cerrados se borran a los 3 días y
-- los abiertos a los 14.
local ORDER_PREFIX = "GuildControlOrd"
local ORDER_OPEN = { pending = true, accepted = true }
local ORDER_STATUSES = { pending = true, accepted = true, done = true, rejected = true, cancelled = true }
communityModule.ORDER_LABELS = { pending = "Pedido", accepted = "Aceptado", done = "Hecho",
                                 rejected = "Rechazado", cancelled = "Cancelado" }
communityModule.ORDER_COLORS = { pending = "FFD100", accepted = "66B3FF", done = "00FF00",
                                 rejected = "FF3333", cancelled = "808080" }
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(ORDER_PREFIX)
end

local function OrderStore()
    if type(GuildControlDB.craftOrders) ~= "table" then GuildControlDB.craftOrders = {} end
    local store, now = GuildControlDB.craftOrders, GetServerTime()
    for id, order in pairs(store) do
        local age = now - (order.updatedAt or order.at or 0)
        if (ORDER_OPEN[order.status] and age > 14 * 86400) or (not ORDER_OPEN[order.status] and age > 3 * 86400) then
            store[id] = nil
        end
    end
    return store
end

local function SendOrder(order)
    Send(ORDER_PREFIX, table.concat({ "O", order.id, order.crafter, order.recipeID, order.at, order.materials and "1" or "0", order.note or "" }, ";"))
    if order.status ~= "pending" then
        Send(ORDER_PREFIX, table.concat({ "U", order.id, order.status, order.updatedAt or order.at }, ";"))
    end
end

-- Pide una receta a un artesano (materials = true si quien pide aporta los materiales).
-- Devuelve el pedido o nil
function communityModule.CreateOrder(crafter, recipeID, note, materials)
    recipeID = tonumber(recipeID)
    crafter = NormalizeName(crafter)
    if not crafter or not recipeID or crafter == MyName() then return nil end
    local now = GetServerTime()
    local order = {
        id = (string.match(UnitName("player") or "?", "^(%S+)") or "?") .. "-" .. now .. "-" .. math.random(100, 999),
        requester = MyName(), crafter = crafter, recipeID = recipeID, note = Clean(note, 80),
        materials = materials and true or false, status = "pending", at = now, updatedAt = now,
    }
    OrderStore()[order.id] = order
    SendOrder(order)
    Notify()
    return order
end

-- El artesano acepta, termina o rechaza; quien lo pidió lo cancela
function communityModule.SetOrderStatus(id, status)
    local order = OrderStore()[id]
    if not order or not ORDER_STATUSES[status] then return end
    local me = MyName()
    local allowed = (order.crafter == me and (status == "accepted" or status == "done" or status == "rejected"))
        or (order.requester == me and status == "cancelled")
    if not allowed then return end
    order.status, order.updatedAt = status, GetServerTime()
    Send(ORDER_PREFIX, table.concat({ "U", order.id, status, order.updatedAt }, ";"))
    Notify()
end

-- { forMe = {pedidos que me hacen}, mine = {mis pedidos} }, abiertos primero y luego por fecha
function communityModule.GetOrders()
    local me = MyName()
    local forMe, mine = {}, {}
    for _, order in pairs(OrderStore()) do
        if order.crafter == me then table.insert(forMe, order) end
        if order.requester == me then table.insert(mine, order) end
    end
    local function Sort(a, b)
        local openA, openB = ORDER_OPEN[a.status] and 1 or 0, ORDER_OPEN[b.status] and 1 or 0
        if openA ~= openB then return openA > openB end
        return (a.updatedAt or 0) > (b.updatedAt or 0)
    end
    table.sort(forMe, Sort)
    table.sort(mine, Sort)
    return { forMe = forMe, mine = mine }
end

-- Quita de mi lista los pedidos cerrados (hechos, rechazados o cancelados). which = "forMe"
-- (los que me hacen) o "mine" (los míos). Solo afecta a este cliente.
function communityModule.ClearClosedOrders(which)
    local me, removed = MyName(), 0
    local store = OrderStore()
    for id, order in pairs(store) do
        local mine = (which == "forMe" and order.crafter == me) or (which == "mine" and order.requester == me)
        if mine and not ORDER_OPEN[order.status] then
            store[id] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then Notify() end
    return removed
end

-- Pedidos abiertos que me han hecho (para avisos)
function communityModule.CountOpenOrdersForMe()
    local count = 0
    for _, order in ipairs(communityModule.GetOrders().forMe) do
        if ORDER_OPEN[order.status] then count = count + 1 end
    end
    return count
end

local function OrderAlert(text)
    if addonTable.Personal and addonTable.Personal.Alert then addonTable.Personal.Alert(text) end
end

local function OnOrderMessage(sender, msg)
    local me = MyName()
    local kind = string.sub(msg, 1, 2)
    if kind == "O;" then
        local _, id, crafter, recipeID, at, materials, note = strsplit(";", msg, 7)
        crafter, recipeID, at = NormalizeName(crafter), tonumber(recipeID), tonumber(at)
        if not id or not crafter or not recipeID or not at then return end
        -- Solo me interesa si soy el artesano (o quien lo pidió, desde otro personaje)
        if crafter ~= me and sender ~= me then return end
        local store = OrderStore()
        local isNew = store[id] == nil
        store[id] = store[id] or { id = id, requester = sender, crafter = crafter, recipeID = recipeID,
                                    note = Clean(note, 80), materials = materials == "1",
                                    status = "pending", at = at, updatedAt = at }
        if isNew and crafter == me and GetServerTime() - at < 600 then
            OrderAlert(string.format(L["%s te pide: %s"], Ambiguate(addonTable.GetGameName(sender), "none"),
                communityModule.RecipeName(recipeID) or ("#" .. recipeID)))
        end
        Notify()
    elseif kind == "U;" then
        local _, id, status, at = strsplit(";", msg, 4)
        at = tonumber(at)
        local order = id and OrderStore()[id]
        if not order or not ORDER_STATUSES[status] or not at or at < (order.updatedAt or 0) then return end
        -- Solo el artesano cambia el estado (y quien lo pidió, para cancelarlo)
        local valid = (sender == order.crafter and status ~= "cancelled") or (sender == order.requester and status == "cancelled")
        if not valid then return end
        local changed = order.status ~= status
        order.status, order.updatedAt = status, at
        if changed and order.requester == me then
            OrderAlert(string.format(L["Tu pedido de %s: %s"], communityModule.RecipeName(order.recipeID) or ("#" .. order.recipeID),
                L[communityModule.ORDER_LABELS[status]]))
        elseif changed and order.crafter == me and status == "cancelled" then
            OrderAlert(string.format(L["%s ha cancelado el pedido de %s."], Ambiguate(addonTable.GetGameName(sender), "none"),
                communityModule.RecipeName(order.recipeID) or ("#" .. order.recipeID)))
        end
        Notify()
    elseif msg == "Q" then
        -- Reenvío mis pedidos abiertos (como artesano o como quien pide) a quien acaba de entrar
        C_Timer.After(2 + math.random() * 4, function()
            for _, order in pairs(OrderStore()) do
                if ORDER_OPEN[order.status] and (order.requester == me or order.crafter == me)
                    and (order.requester == sender or order.crafter == sender) then
                    SendOrder(order)
                end
            end
        end)
    end
end

-- =========================================================================
-- EVENTOS
-- =========================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
frame:RegisterEvent("TRADE_SKILL_CLOSE")
frame:SetScript("OnEvent", function(_, event, ...)
    if type(GuildControlDB) ~= "table" then return end
    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin or isReloadingUi then
            -- Anuncios del antiguo Buscar grupo: ya no se usan
            GuildControlDB.lfgPosts = nil
            C_Timer.After(27, function() Send(ORDER_PREFIX, "Q") end)
            C_Timer.After(30, communityModule.RequestRecipes)
        end
        return
    elseif event == "TRADE_SKILL_LIST_UPDATE" then
        -- Se recorre la lista 2 s después del último aviso (llegan muchos seguidos)
        if collectTimer then collectTimer:Cancel() end
        collectTimer = C_Timer.NewTimer(2, function()
            collectTimer = nil
            OnTradeSkillUpdate()
        end)
        return
    elseif event == "TRADE_SKILL_CLOSE" then
        -- Se envía al cerrar la ventana (y solo si cambió) para no saturar el canal
        if pendingProfession then
            SendRecipes(pendingProfession, pendingIds)
            sentThisSession[pendingProfession] = true
            pendingProfession, pendingIds = nil, nil
        end
        return
    end
    local prefix, msg, channel, sender = ...
    if (prefix ~= CRAFT_PREFIX and prefix ~= ORDER_PREFIX) or channel ~= "GUILD" then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    if type(msg) ~= "string" or not sender or addonTable.IsMe(sender) then return end
    local fullSender = NormalizeName(sender)
    if prefix == ORDER_PREFIX then
        OnOrderMessage(fullSender, msg)
    elseif string.sub(msg, 1, 2) == "R;" then
        OnCraftMessage(fullSender, msg)
    elseif prefix == CRAFT_PREFIX and msg == "Q" then
        -- Alguien pide las recetas: respondo con las mías un poco después (para no coincidir)
        C_Timer.After(1 + math.random() * 5, SendAllMyRecipes)
    end
end)
