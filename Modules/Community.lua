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
--     { [profesión] = { at, ids = { recipeID, ... } } }. Prefijo GuildControlCrft, troceado:
--       R;msgId;i;total;profesión;id,id,...

local LFG_PREFIX = "GuildControlLFG"
-- Máximo 16 caracteres: con "GuildControlCraft" (17) el juego no registraba el prefijo ni
-- enviaba los mensajes, así que las recetas de los demás nunca llegaban
local CRAFT_PREFIX = "GuildControlCrft"
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

-- Miembro de la hermandad de una unidad del grupo. Primero por GUID (no depende del nombre,
-- el apellido ni el reino), después mi propia clave y por último el nombre.
local function MemberForUnit(unit)
    local members = GuildControlDB.members or {}
    local guid = UnitGUID(unit)
    if guid and not (issecretvalue and issecretvalue(guid)) then
        for _, m in pairs(members) do
            if m.guid == guid then return m end
        end
    end
    if UnitIsUnit(unit, "player") then return members[MyName()] end
    local name, realm = UnitName(unit)
    if not name or (issecretvalue and issecretvalue(name)) then return nil end
    if realm and (issecretvalue and issecretvalue(realm)) then realm = nil end
    return members[NormalizeName((realm and realm ~= "") and (name .. "-" .. realm) or name)]
end

local ROLE_BY_NAME = { Tanque = "tank", Sanador = "healer", DPS = "dps" }

-- Roles de mi grupo actual (yo incluido): el de Mi perfil o el que fijó un oficial; si no hay,
-- el asignado en el grupo. Los de fuera de la hermandad sin rol cuentan como desconocidos.
local function UnitRole(unit)
    local m = MemberForUnit(unit)
    if m and (m.roleSource == "declared" or m.roleSource == "officer") then
        return ROLE_BY_NAME[m.role] or "dps"
    end
    -- Mi propio perfil (por si mi ficha de miembro todavía no lo tiene)
    if UnitIsUnit(unit, "player") and type(GuildControlDB.myProfiles) == "table" then
        local profile = GuildControlDB.myProfiles[MyName()]
        if profile and ROLE_BY_NAME[profile.main] then return ROLE_BY_NAME[profile.main] end
    end
    if UnitGroupRolesAssigned then
        local assigned = UnitGroupRolesAssigned(unit)
        if assigned == "TANK" then return "tank" elseif assigned == "HEALER" then return "healer" elseif assigned == "DAMAGER" then return "dps" end
    end
    return nil
end

function communityModule.GetGroupRoles()
    local have = { tank = 0, healer = 0, dps = 0, unknown = 0 }
    local function Count(unit)
        local role = UnitRole(unit)
        have[role or "unknown"] = have[role or "unknown"] + 1
    end
    Count("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then Count(unit) end
        end
    else
        for i = 1, GetNumSubgroupMembers() do Count("party" .. i) end
    end
    return have
end

-- "H;id;t1h0d2u1": cuántos tanques, sanadores, DPS y sin rol hay ya en el grupo del autor
local function SendHave(post)
    post.have = communityModule.GetGroupRoles()
    local h = post.have
    Send(LFG_PREFIX, "H;" .. post.id .. ";t" .. h.tank .. "h" .. h.healer .. "d" .. h.dps .. "u" .. h.unknown)
end

-- Invita a un jugador; con el grupo lleno (5) se convierte antes en banda
local function InviteName(name)
    local gameName = addonTable.GetGameName and addonTable.GetGameName(name) or name
    if IsInGroup() and not IsInRaid() and GetNumGroupMembers() >= 5 then
        if C_PartyInfo and C_PartyInfo.ConvertToRaid then C_PartyInfo.ConvertToRaid() elseif ConvertToRaid then ConvertToRaid() end
    end
    if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(gameName) elseif InviteUnit then InviteUnit(gameName) end
end

function communityModule.CreatePost(activity, slots, text, roles)
    text = Clean(text, 120)
    if text == "" then return nil end
    local post = {
        id = (string.match(UnitName("player") or "?", "^(%S+)") or "?") .. "-" .. GetServerTime(), author = MyName(), at = GetServerTime(),
        activity = VALID_ACTIVITY[activity] and activity or "other",
        slots = math.max(1, math.min(39, math.floor(tonumber(slots) or 4))), text = text, members = {}, accepted = {},
        roles = RolesFromString(RolesToString(roles)),
    }
    posts[post.id] = post
    SendPost(post)
    SendHave(post)
    Notify()
    return post
end

-- El autor acepta una solicitud: le invita al grupo y avisa a todos de que está aceptado
function communityModule.AcceptJoin(id, name)
    local post = posts[id]
    if not post or post.author ~= MyName() or not post.members[name] then return end
    post.accepted = post.accepted or {}
    post.accepted[name] = true
    InviteName(name)
    Send(LFG_PREFIX, "A;" .. id .. ";" .. name)
    Notify()
end

function communityModule.DeclineJoin(id, name)
    local post = posts[id]
    if not post or post.author ~= MyName() then return end
    post.members[name] = nil
    if post.accepted then post.accepted[name] = nil end
    Send(LFG_PREFIX, "K;" .. id .. ";" .. name)
    Notify()
end

function communityModule.IsAccepted(post, name)
    return post.accepted ~= nil and post.accepted[name] == true
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
        post = post or { id = id, members = {}, accepted = {} }
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
            -- Solicitud de unión: el autor la acepta (invita) o la rechaza
            local already = post.members[sender] ~= nil
            post.members[sender] = role
            if post.author == MyName() and not already then
                if addonTable.UI and addonTable.UI.ShowJoinRequest then
                    addonTable.UI.ShowJoinRequest(id, sender, role)
                elseif addonTable.Personal then
                    addonTable.Personal.Alert(string.format(L["%s se apunta a tu grupo."], Ambiguate(sender, "none")))
                end
                if communityModule.CountMembers(post) == post.slots and addonTable.Personal then
                    addonTable.Personal.Alert(L["Tu grupo está completo: invita a los apuntados desde Comunidad."])
                end
            end
        else
            post.members[sender] = nil
            if post.accepted then post.accepted[sender] = nil end
        end
        Notify()
    elseif kind == "A;" or kind == "K;" then
        -- El autor acepta (A) o rechaza (K) una solicitud
        local id, name = strsplit(";", string.sub(msg, 3), 2)
        local post = posts[id]
        if not post or post.author ~= sender or not name then return end
        post.accepted = post.accepted or {}
        local author = Ambiguate(sender, "none")
        if kind == "A;" then
            post.accepted[name] = true
            if name == MyName() and addonTable.Personal then
                addonTable.Personal.Alert(string.format(L["%s ha aceptado tu solicitud y te invita al grupo."], author))
            end
        else
            post.members[name] = nil
            post.accepted[name] = nil
            if name == MyName() and addonTable.Personal then
                addonTable.Personal.Alert(string.format(L["%s ha rechazado tu solicitud para su grupo."], author))
            end
        end
        Notify()
    elseif kind == "H;" then
        local id, have = strsplit(";", string.sub(msg, 3), 2)
        local post = posts[id]
        local t, h, d, u = string.match(have or "", "^t(%d+)h(%d+)d(%d+)u(%d+)$")
        if not post or post.author ~= sender or not t then return end
        post.have = { tank = tonumber(t), healer = tonumber(h), dps = tonumber(d), unknown = tonumber(u) }
        Notify()
    elseif kind == "M;" then
        -- Apuntados de un anuncio (los manda su autor al responder a Q)
        local id, list = strsplit(";", string.sub(msg, 3), 2)
        local post = posts[id]
        if not post or post.author ~= sender or not list then return end
        post.accepted = post.accepted or {}
        -- "Nombre=rol" (pendiente) o "Nombre=rol!" (aceptado)
        for name, role, accepted in string.gmatch(list, "([^,=]+)=(%a+)(!?)") do
            if ROLE_LETTER[role] then
                post.members[name] = role
                if accepted == "!" then post.accepted[name] = true end
            end
        end
        Notify()
    elseif msg == "Q" then
        -- Reenvía mis anuncios abiertos (y quién se ha apuntado) a quien acaba de entrar
        C_Timer.After(1 + math.random() * 4, function()
            for _, post in pairs(posts) do
                if post.author == MyName() then
                    SendPost(post)
                    SendHave(post)
                    -- Sin pasar de 255 bytes: con muchos apuntados se manda en varios mensajes
                    local chunk, size = {}, 0
                    local function Flush()
                        if #chunk > 0 then Send(LFG_PREFIX, "M;" .. post.id .. ";" .. table.concat(chunk, ",")) end
                        chunk, size = {}, 0
                    end
                    for name, role in pairs(post.members) do
                        if type(role) == "string" then
                            local part = name .. "=" .. role .. (communityModule.IsAccepted(post, name) and "!" or "")
                            if size + #part + 1 > 200 then Flush() end
                            table.insert(chunk, part)
                            size = size + #part + 1
                        end
                    end
                    Flush()
                end
            end
        end)
    end
end

-- Anuncia un grupo mío en el chat de hermandad (para quien no usa GuildControl)
function communityModule.AnnouncePost(id)
    local post = posts[id]
    if not post or post.author ~= MyName() or not IsInGuild() then return end
    local activity = L[VALID_ACTIVITY[post.activity] or "Otro"]
    -- Roles que se buscan: "Tanque y Sanador"; con los tres, "cualquier rol"
    local ROLE_NAMES = { tank = "Tanque", healer = "Sanador", dps = "DPS" }
    local wanted = {}
    for _, role in ipairs(communityModule.ROLES) do
        if post.roles and post.roles[role] then table.insert(wanted, L[ROLE_NAMES[role]]) end
    end
    local rolesText
    if #wanted == 0 or #wanted == 3 then
        rolesText = L["cualquier rol"]
    elseif #wanted == 1 then
        rolesText = wanted[1]
    else
        rolesText = wanted[1] .. L[" y "] .. wanted[2]
    end
    local text = string.format(L["[GuildControl] Busco %s (%s, %d/%d): %s · Apúntate en GuildControl > Comunidad o susúrrame."],
        rolesText, activity, communityModule.CountMembers(post), post.slots, post.text)
    if #text > 255 then
        -- Sin partir una letra de varios bytes (ñ, á...) al recortar
        text = string.gsub(string.sub(text, 1, 252), "[\192-\255][\128-\191]*$", "") .. "..."
    end
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(text, "GUILD")
    else
        SendChatMessage(text, "GUILD")
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
-- Al cambiar mi grupo, mis anuncios abiertos mandan de nuevo qué roles tengo ya (una sola
-- vez aunque lleguen muchos cambios seguidos)
local haveFrame = CreateFrame("Frame")
haveFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
haveFrame:SetScript("OnEvent", function(self)
    if self.pending or type(GuildControlDB) ~= "table" then return end
    self.pending = true
    C_Timer.After(2, function()
        self.pending = false
        local me = MyName()
        for _, post in pairs(posts) do
            if post.author == me then SendHave(post) end
        end
        Notify()
    end)
end)

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
