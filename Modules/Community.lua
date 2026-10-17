local addonName, addonTable = ...
local L = addonTable.L

addonTable.Community = {}
local communityModule = addonTable.Community

-- Comunidad (sin frames; la UI está en UI.lua, pestaña "Comunidad"):
--   - Buscar grupo: anuncios de la hermandad ("Busco gente para +12") a los que apuntarse.
--     Viven en memoria (2 h) y se comparten con el prefijo GuildControlLFG:
--       N;id;hora;actividad;plazas;texto   anuncio nuevo o cambiado (del autor)
--       J;id   me apunto     L;id   me borro     X;id   el autor lo cierra
--       Q      petición al entrar (cada uno reenvía sus anuncios abiertos)
--   - Artesanos: cada jugador con GuildControl comparte las recetas que conoce de sus
--     profesiones (al cerrar la ventana de profesión). GuildControlDB.recipes[Nombre-Reino] =
--     { [profesión] = { at, ids = { recipeID, ... } } }. Prefijo GuildControlCraft, troceado:
--       R;msgId;i;total;profesión;id,id,...

local LFG_PREFIX = "GuildControlLFG"
local CRAFT_PREFIX = "GuildControlCraft"
local POST_MAX_AGE = 2 * 3600
local CHUNK_IDS = 30

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

local function SendPost(post)
    Send(LFG_PREFIX, table.concat({ "N", post.id, post.at, post.activity, post.slots, post.text }, ";"))
end

function communityModule.CreatePost(activity, slots, text)
    text = Clean(text, 120)
    if text == "" then return nil end
    local post = {
        id = (UnitName("player") or "?") .. "-" .. GetServerTime(), author = MyName(), at = GetServerTime(),
        activity = VALID_ACTIVITY[activity] and activity or "other",
        slots = math.max(1, math.min(39, math.floor(tonumber(slots) or 4))), text = text, members = {},
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

function communityModule.Join(id)
    local post = posts[id]
    if not post then return end
    post.members[MyName()] = true
    Send(LFG_PREFIX, "J;" .. id)
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
        local _, id, at, activity, slots, text = strsplit(";", msg, 6)
        at = tonumber(at)
        if not id or not at or not text or GetServerTime() - at > POST_MAX_AGE then return end
        local post = posts[id]
        local isNew = post == nil
        post = post or { id = id, members = {} }
        post.author, post.at = sender, at
        post.activity = VALID_ACTIVITY[activity] and activity or "other"
        post.slots = math.max(1, math.min(39, math.floor(tonumber(slots) or 4)))
        post.text = Clean(text, 120)
        posts[id] = post
        if isNew and addonTable.Personal and GetServerTime() - at < 120 then
            addonTable.Personal.Alert(string.format(L["%s busca gente: %s"], Ambiguate(sender, "none"), post.text))
        end
        Notify()
    elseif kind == "J;" or kind == "L;" or kind == "X;" then
        local id = string.sub(msg, 3)
        local post = posts[id]
        if not post then return end
        if kind == "X;" then
            if post.author == sender then posts[id] = nil end
        elseif kind == "J;" then
            post.members[sender] = true
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

local function SendRecipes(profession, ids)
    if not IsInGuild() then return end
    local msgId = tostring(math.random(100000, 999999))
    local total = math.max(1, math.ceil(#ids / CHUNK_IDS))
    local queue = {}
    for i = 1, total do
        local part = {}
        for j = (i - 1) * CHUNK_IDS + 1, math.min(#ids, i * CHUNK_IDS) do table.insert(part, tostring(ids[j])) end
        table.insert(queue, table.concat({ "R", msgId, i, total, Clean(profession, 40), table.concat(part, ",") }, ";"))
    end
    local ticker
    ticker = C_Timer.NewTicker(0.4, function()
        local msg = table.remove(queue, 1)
        if msg then Send(CRAFT_PREFIX, msg) end
        if #queue == 0 and ticker then ticker:Cancel() end
    end)
end

local pendingProfession, pendingIds = nil, nil
local collectTimer = nil
local function OnTradeSkillUpdate()
    local profession, ids = CollectOpenRecipes()
    if not profession then return end
    local mine = RecipeStore()[MyName()] or {}
    RecipeStore()[MyName()] = mine
    local old = mine[profession]
    local changed = not old or #old.ids ~= #ids
    mine[profession] = { at = time(), ids = ids }
    if changed then pendingProfession, pendingIds = profession, ids end
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
        if isInitialLogin or isReloadingUi then C_Timer.After(24, function() Send(LFG_PREFIX, "Q") end) end
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
            pendingProfession, pendingIds = nil, nil
        end
        return
    end
    local prefix, msg, channel, sender = ...
    if (prefix ~= LFG_PREFIX and prefix ~= CRAFT_PREFIX) or channel ~= "GUILD" then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    if type(msg) ~= "string" or not sender or addonTable.IsMe(sender) then return end
    local fullSender = NormalizeName(sender)
    if prefix == LFG_PREFIX then
        OnLfgMessage(fullSender, msg)
    elseif string.sub(msg, 1, 2) == "R;" then
        OnCraftMessage(fullSender, msg)
    end
end)
