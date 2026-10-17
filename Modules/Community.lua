local addonName, addonTable = ...
local L = addonTable.L

addonTable.Community = {}
local communityModule = addonTable.Community

-- Comunidad (sin frames; la UI está en UI.lua, pestaña "Comunidad"):
--   - Buscar grupo: anuncios de la hermandad ("Busco gente para +12") a los que apuntarse.
--     Viven en memoria (2 h) y se comparten con el prefijo GuildControlLFG:
--       N;id;hora;actividad;plazas;texto;roles   anuncio nuevo o cambiado (del autor);
--                                              roles = letras de los que se buscan: t, h, d
--       J;id;rol   me apunto (rol: tank|healer|dps)     L;id   me borro     X;id   el autor lo cierra
--       Q      petición al entrar (cada uno reenvía sus anuncios abiertos)
--   - Artesanos: cada jugador con GuildControl comparte las recetas que conoce de sus
--     profesiones (al cerrar la ventana de profesión). GuildControlDB.recipes[Nombre-Reino] =
--     { [profesión] = { at, ids = { recipeID, ... } } }. Prefijo GuildControlCraft, troceado:
--       R;msgId;i;total;profesión;id,id,...

local LFG_PREFIX = "GuildControlLFG"
local CRAFT_PREFIX = "GuildControlCraft"
local POST_MAX_AGE = 2 * 3600

communityModule.ACTIVITIES = {
    { key = "mplus", label = "Míticas+" },
    { key = "raid", label = "Banda" },
    { key = "pvp", label = "JcJ" },
    { key = "farm", label = "Farmeo" },
    { key = "other", label = "Otro" },
}
local VALID_ACTIVITY = {}
for _, a in ipairs(communityModule.ACTIVITIES) do VALID_ACTIVITY[a.key] = a.label end
communityModule.ACTIVITY_LABELS = VALID_ACTIVITY

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(LFG_PREFIX)
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

local function Send(prefix, msg)
    if not IsInGuild() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    pcall(C_ChatInfo.SendAddonMessage, prefix, msg, "GUILD")
end

-- =========================================================================
-- BUSCAR GRUPO
-- =========================================================================
local posts = {}   -- [id] = { id, author, at, activity, slots, text, members = { [nombre] = true } }

local function Expire()
    local now = GetServerTime()
    for id, post in pairs(posts) do
        if now - (post.at or 0) > POST_MAX_AGE then posts[id] = nil end
    end
end

-- Anuncios abiertos, los más nuevos primero
function communityModule.GetPosts()
    Expire()
    local list = {}
    for _, post in pairs(posts) do table.insert(list, post) end
    table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
    return list
end

function communityModule.CountMembers(post)
    local count = 0
    for _ in pairs(post.members or {}) do count = count + 1 end
    return count
end

-- Roles que se buscan en un anuncio: { tank = true, ... } <-> "thd"
communityModule.ROLES = { "tank", "healer", "dps" }
local ROLE_LETTER = { tank = "t", healer = "h", dps = "d" }
local LETTER_ROLE = { t = "tank", h = "healer", d = "dps" }
local function RolesToString(roles)
    local out = ""
    for _, role in ipairs(communityModule.ROLES) do
        if roles and roles[role] then out = out .. ROLE_LETTER[role] end
    end
    return out
end
local function RolesFromString(text)
    local roles = {}
    for letter in string.gmatch(text or "", "[thd]") do roles[LETTER_ROLE[letter]] = true end
    if not next(roles) then roles = { tank = true, healer = true, dps = true } end
    return roles
end

local function SendPost(post)
    Send(LFG_PREFIX, table.concat({ "N", post.id, post.at, post.activity, post.slots, post.text, RolesToString(post.roles) }, ";"))
end

function communityModule.CreatePost(activity, slots, text, roles)
    text = Clean(text, 120)
    if text == "" then return nil end
    local post = {
        id = (string.match(UnitName("player") or "?", "^(%S+)") or "?") .. "-" .. GetServerTime(), author = MyName(), at = GetServerTime(),
        activity = VALID_ACTIVITY[activity] and activity or "other",
        slots = math.max(1, math.min(39, math.floor(tonumber(slots) or 4))), text = text, members = {},
        roles = RolesFromString(RolesToString(roles)),
    }
    posts[post.id] = post
    SendPost(post)
    Notify()
    return post
end

function communityModule.ClosePost(id)
    local post = posts[id]
    if not post or post.author ~= MyName() then return end
    posts[id] = nil
    Send(LFG_PREFIX, "X;" .. id)
    Notify()
end

-- role: con qué rol me apunto (uno de los que busca el anuncio)
function communityModule.Join(id, role)
    local post = posts[id]
    if not post then return end
    role = ROLE_LETTER[role] and role or "dps"
    post.members[MyName()] = role
    Send(LFG_PREFIX, "J;" .. id .. ";" .. role)
    Notify()
end

function communityModule.Leave(id)
    local post = posts[id]
    if not post then return end
    post.members[MyName()] = nil
    Send(LFG_PREFIX, "L;" .. id)
    Notify()
end

local function OnLfgMessage(sender, msg)
    local kind = string.sub(msg, 1, 2)
    if kind == "N;" then
        local _, id, at, activity, slots, text, roles = strsplit(";", msg, 7)
        at = tonumber(at)
        if not id or not at or not text or GetServerTime() - at > POST_MAX_AGE then return end
        local post = posts[id]
        local isNew = post == nil
        post = post or { id = id, members = {} }
        post.author, post.at = sender, at
        post.activity = VALID_ACTIVITY[activity] and activity or "other"
        post.slots = math.max(1, math.min(39, math.floor(tonumber(slots) or 4)))
        post.text = Clean(text, 120)
        post.roles = RolesFromString(roles)
        posts[id] = post
        if isNew and addonTable.Personal and GetServerTime() - at < 120 then
            addonTable.Personal.Alert(string.format(L["%s busca gente: %s"], Ambiguate(sender, "none"), post.text))
        end
        Notify()
    elseif kind == "J;" or kind == "L;" or kind == "X;" then
        local id, role = strsplit(";", string.sub(msg, 3), 2)
        role = ROLE_LETTER[role] and role or true
        local post = posts[id]
        if not post then return end
        if kind == "X;" then
            if post.author == sender then posts[id] = nil end
        elseif kind == "J;" then
            post.members[sender] = role
            if post.author == MyName() and addonTable.Personal then
                addonTable.Personal.Alert(string.format(L["%s se apunta a tu grupo."], Ambiguate(sender, "none")))
            end
        else
            post.members[sender] = nil
        end
        Notify()
    elseif msg == "Q" then
        -- Reenvía mis anuncios abiertos a quien acaba de entrar
        C_Timer.After(1 + math.random() * 4, function()
            for _, post in pairs(posts) do
                if post.author == MyName() then SendPost(post) end
            end
        end)
    end
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
function communityModule.RequestRecipes()
    if GetTime() - lastRecipeRequest < 60 then return end
    lastRecipeRequest = GetTime()
    Send(CRAFT_PREFIX, "Q")
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
                        entry = { recipeID = recipeID, name = name, profession = profession, crafters = {} }
                        byRecipe[recipeID] = entry
                    end
                    table.insert(entry.crafters, crafter)
                end
            end
        end
    end
    local list = {}
    for _, entry in pairs(byRecipe) do
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
--   O;id;artesano;recipeID;hora;nota   pedido nuevo (lo envía quien pide)
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
    Send(ORDER_PREFIX, table.concat({ "O", order.id, order.crafter, order.recipeID, order.at, order.note or "" }, ";"))
    if order.status ~= "pending" then
        Send(ORDER_PREFIX, table.concat({ "U", order.id, order.status, order.updatedAt or order.at }, ";"))
    end
end

-- Pide una receta a un artesano. Devuelve el pedido o nil
function communityModule.CreateOrder(crafter, recipeID, note)
    recipeID = tonumber(recipeID)
    crafter = NormalizeName(crafter)
    if not crafter or not recipeID or crafter == MyName() then return nil end
    local now = GetServerTime()
    local order = {
        id = (string.match(UnitName("player") or "?", "^(%S+)") or "?") .. "-" .. now .. "-" .. math.random(100, 999),
        requester = MyName(), crafter = crafter, recipeID = recipeID, note = Clean(note, 80),
        status = "pending", at = now, updatedAt = now,
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
        local _, id, crafter, recipeID, at, note = strsplit(";", msg, 6)
        crafter, recipeID, at = NormalizeName(crafter), tonumber(recipeID), tonumber(at)
        if not id or not crafter or not recipeID or not at then return end
        -- Solo me interesa si soy el artesano (o quien lo pidió, desde otro personaje)
        if crafter ~= me and sender ~= me then return end
        local store = OrderStore()
        local isNew = store[id] == nil
        store[id] = store[id] or { id = id, requester = sender, crafter = crafter, recipeID = recipeID,
                                    note = Clean(note, 80), status = "pending", at = at, updatedAt = at }
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
            C_Timer.After(24, function() Send(LFG_PREFIX, "Q") end)
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
    if (prefix ~= LFG_PREFIX and prefix ~= CRAFT_PREFIX and prefix ~= ORDER_PREFIX) or channel ~= "GUILD" then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    if type(msg) ~= "string" or not sender or addonTable.IsMe(sender) then return end
    local fullSender = NormalizeName(sender)
    if prefix == ORDER_PREFIX then
        OnOrderMessage(fullSender, msg)
    elseif prefix == LFG_PREFIX then
        OnLfgMessage(fullSender, msg)
    elseif string.sub(msg, 1, 2) == "R;" then
        OnCraftMessage(fullSender, msg)
    elseif prefix == CRAFT_PREFIX and msg == "Q" then
        -- Alguien pide las recetas: respondo con las mías un poco después (para no coincidir)
        C_Timer.After(1 + math.random() * 5, SendAllMyRecipes)
    end
end)
