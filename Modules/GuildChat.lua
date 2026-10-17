local addonName, addonTable = ...
local L = addonTable.L

addonTable.GuildChat = {}
local chatModule = addonTable.GuildChat

-- Guarda los mensajes de hermandad, susurros, banda y grupo/mazmorra para el panel de chat de
-- la UI (GuildControlDB.chatLog, así sobreviven a /reload) y responde automáticamente al
-- saludo de quien ACABA de conectarse (solo en el chat de hermandad).
--
-- Regla del saludo automático: solo se responde si quien saluda
--   1. se conectó hace poco (aviso "X se ha conectado" o cambio en el roster),
--   2. y nadie (ni yo, ni otro cliente con GuildControl, ni otro miembro) le ha
--      saludado desde esa conexión.
-- Así no se saluda a quien lleva rato conectado y contesta a otro recién llegado.

local MAX_MESSAGES = 500
local DEFAULT_GREET_COOLDOWN_MIN = 30   -- no volver a saludar a la misma persona (configurable)
local DEFAULT_LOGIN_WINDOW_MIN = 5      -- minutos tras conectarse en los que se le considera recién llegado
local GREET_GLOBAL_COOLDOWN = 20        -- como mucho un saludo automático cada 20 s
local DEFAULT_GREET_DELAY = 2           -- segundos antes de responder (configurable)
local GREET_DELAY_JITTER = 4            -- hasta 4 s extra aleatorios para que solo responda un cliente
local GREET_MAX_LENGTH = 40             -- mensajes más largos no se consideran un saludo

-- Lista por defecto de settings.greetWords (se edita en Configuración)
chatModule.DEFAULT_GREET_WORDS = "hola, holaa, holi, holis, ola, buenas, buenass, wenas, nas, buenos dias, "
    .. "buen dia, buenas tardes, buenas noches, nas noches, wenas noches, saludos, que tal, hey, hello, hi"

-- Historial persistente: { {at, channel, dir, sender, fullName, class, text, target}, ... }
-- (más antiguo primero). channel = "guild"|"whisper"|"raid"|"party"|"instance";
-- en los susurros dir = "in" (recibido) o "out" (enviado, target = destinatario)
local function Messages()
    if not GuildControlDB then return {} end
    if type(GuildControlDB.chatLog) ~= "table" then GuildControlDB.chatLog = {} end
    return GuildControlDB.chatLog
end
local listener = nil     -- función que la UI registra para recibir mensajes nuevos

local loginTimes = {}         -- [nombre corto] = GetTime() de su última conexión vista en esta sesión
local lastGreetByPlayer = {}  -- [nombre corto] = GetTime() del último saludo (de quien sea) a esa persona
local lastGreetTime = -GREET_GLOBAL_COOLDOWN
local pendingGreets = {}      -- [nombre corto] = timer pendiente
local pendingWelcomes = {}    -- [nombre corto] = timer de la bienvenida a un miembro nuevo
local newMembers = {}         -- [nombre corto] = true: entró en la hermandad en esta sesión (sin saludo automático)

local chatFrame = CreateFrame("Frame")
chatFrame:RegisterEvent("CHAT_MSG_GUILD")
-- Otros canales que se guardan en el historial (canal del panel para cada evento)
local CHANNEL_EVENTS = {
    CHAT_MSG_WHISPER = "whisper", CHAT_MSG_WHISPER_INFORM = "whisper",
    CHAT_MSG_RAID = "raid", CHAT_MSG_RAID_LEADER = "raid", CHAT_MSG_RAID_WARNING = "raid",
    CHAT_MSG_PARTY = "party", CHAT_MSG_PARTY_LEADER = "party",
    CHAT_MSG_INSTANCE_CHAT = "instance", CHAT_MSG_INSTANCE_CHAT_LEADER = "instance",
}
for event in pairs(CHANNEL_EVENTS) do chatFrame:RegisterEvent(event) end
chatFrame:RegisterEvent("CHAT_MSG_ADDON")
chatFrame:RegisterEvent("CHAT_MSG_SYSTEM")

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix("GuildControlGreet")
end

-- =========================================================================
-- UTILIDADES
-- =========================================================================
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function ShortName(name)
    if Ambiguate then return Ambiguate(name, "guild") end
    return (string.match(name, "^([^-]+)")) or name
end

local function IsMe(name)
    return addonTable.IsMe(name)
end

local ACCENTS = { ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ü"] = "u", ["ñ"] = "n",
                  ["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ú"] = "u", ["Ñ"] = "n" }

local function Simplify(text)
    text = string.gsub(text, "[\195][\128-\191]", function(c) return ACCENTS[c] or c end)
    text = string.lower(text)
    text = string.gsub(text, "[%p¡¿]", " ")
    text = string.gsub(text, "%s+", " ")
    return strtrim(text)
end

local function GetSettings()
    return GuildControlDB and GuildControlDB.settings or {}
end

local function GetGreetingWords()
    local raw = GetSettings().greetWords
    if type(raw) ~= "string" or strtrim(raw) == "" then raw = chatModule.DEFAULT_GREET_WORDS end
    local words = {}
    for word in string.gmatch(raw, "[^,\r\n]+") do
        word = Simplify(word)
        if word ~= "" then table.insert(words, word) end
    end
    return words
end

-- Un mensaje es un saludo si empieza por una de las palabras configuradas y es corto
local function IsGreeting(text)
    if #text > GREET_MAX_LENGTH then return false end
    local simple = " " .. Simplify(text) .. " "
    for _, word in ipairs(GetGreetingWords()) do
        if string.find(simple, "^ " .. word .. " ", 1) then return true end
    end
    return false
end

local function Mentions(text, name)
    return string.find(string.lower(text), string.lower(name), 1, true) ~= nil
end

local function SendGuild(msg)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(msg, "GUILD")
    else
        SendChatMessage(msg, "GUILD")
    end
end

-- Convierte una cadena de formato de Blizzard ("%s se ha conectado.") en patrón Lua
local function FormatToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local pattern = string.gsub(fmt, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    pattern = string.gsub(pattern, "%%%%s", "(.-)")
    return "^" .. pattern .. "$"
end

local ONLINE_PATTERN = FormatToPattern(ERR_FRIEND_ONLINE_SS)
local OFFLINE_PATTERN = FormatToPattern(ERR_FRIEND_OFFLINE_S)
local JOIN_PATTERN = FormatToPattern(ERR_GUILD_JOIN_S)

-- =========================================================================
-- MENSAJES PARA EL PANEL
-- =========================================================================
function chatModule.GetMessages()
    return Messages()
end

function chatModule.Clear()
    wipe(Messages())
end

function chatModule.SetListener(fn)
    listener = fn
end

-- Envía al canal indicado: "guild", "raid", "party", "instance" o "whisper" (con target)
function chatModule.Send(text, channel, target)
    text = strtrim(text or "")
    if text == "" then return false end
    channel = channel or "guild"
    local chatType
    if channel == "guild" then
        if not IsInGuild() then return false end
        chatType = "GUILD"
    elseif channel == "raid" then
        chatType = IsInRaid() and "RAID" or nil
    elseif channel == "party" or channel == "instance" then
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then chatType = "INSTANCE_CHAT"
        elseif IsInGroup() then chatType = "PARTY" end
    elseif channel == "whisper" and target and target ~= "" then
        chatType = "WHISPER"
        if addonTable.WarnIfBusy then addonTable.WarnIfBusy(target) end
    end
    if not chatType then return false end
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(text, chatType, nil, chatType == "WHISPER" and target or nil)
    else
        SendChatMessage(text, chatType, nil, chatType == "WHISPER" and target or nil)
    end
    return true
end

local function AddMessage(sender, text, guid, channel, dir, target)
    local class = nil
    if guid and guid ~= "" and GetPlayerInfoByGUID then
        local ok, _, englishClass = pcall(GetPlayerInfoByGUID, guid)
        if ok then class = englishClass end
    end
    local entry = { at = time(), channel = channel or "guild", dir = dir, sender = ShortName(sender), fullName = sender,
                    class = class, text = text, target = target and ShortName(target) or nil }
    local list = Messages()
    table.insert(list, entry)
    while #list > MAX_MESSAGES do table.remove(list, 1) end
    if listener then listener(entry) end
end

-- =========================================================================
-- CONEXIONES
-- =========================================================================
-- Core la llama cuando el roster pasa a un miembro de desconectado a conectado
function chatModule.MarkOnline(name)
    if not name or name == "" then return end
    local short = ShortName(name)
    -- El aviso del sistema suele llegar antes; no se pisa una hora ya registrada
    if not loginTimes[short] then loginTimes[short] = GetTime() end
end

function chatModule.MarkOffline(name)
    if not name or name == "" then return end
    loginTimes[ShortName(name)] = nil
end

-- Recién conectado y todavía sin saludar desde esa conexión
local function IsNewcomerWaitingGreeting(name)
    local loginAt = loginTimes[name]
    if not loginAt then return false end
    local window = (tonumber(GetSettings().greetLoginWindow) or DEFAULT_LOGIN_WINDOW_MIN) * 60
    if GetTime() - loginAt > window then return false end
    local greetedAt = lastGreetByPlayer[name]
    return not (greetedAt and greetedAt >= loginAt)
end

-- =========================================================================
-- SALUDO AUTOMÁTICO
-- =========================================================================
local function CancelPendingGreet(name)
    local timer = pendingGreets[name]
    if timer then
        timer:Cancel()
        pendingGreets[name] = nil
    end
end

local function MarkGreeted(name)
    CancelPendingGreet(name)
    lastGreetByPlayer[name] = GetTime()
end

local function ScheduleGreet(sender)
    local settings = GetSettings()
    if not settings.autoGreet then return end

    local name = ShortName(sender)
    local now = GetTime()
    if pendingGreets[name] then return end
    if newMembers[name] then return end
    if not IsNewcomerWaitingGreeting(name) then return end
    local cooldown = (tonumber(settings.greetCooldown) or DEFAULT_GREET_COOLDOWN_MIN) * 60
    if lastGreetByPlayer[name] and now - lastGreetByPlayer[name] < cooldown then return end
    if now - lastGreetTime < GREET_GLOBAL_COOLDOWN then return end

    -- Retraso aleatorio para parecer natural y para que solo responda un cliente con GuildControl
    local delay = math.max(1, tonumber(settings.greetDelay) or DEFAULT_GREET_DELAY) + math.random() * GREET_DELAY_JITTER
    pendingGreets[name] = C_Timer.NewTimer(delay, function()
        pendingGreets[name] = nil
        if not IsInGuild() or not GetSettings().autoGreet then return end
        if not IsNewcomerWaitingGreeting(name) then return end

        local template = GetSettings().greetMessage
        if not template or strtrim(template) == "" then template = L["¡Hola, {nombre}!"] end
        local reply = string.gsub(addonTable.NormalizeVars(template), "{nombre}", function() return name end)

        lastGreetByPlayer[name] = GetTime()
        lastGreetTime = GetTime()
        if C_ChatInfo and C_ChatInfo.SendAddonMessage then
            C_ChatInfo.SendAddonMessage("GuildControlGreet", name, "GUILD")
        end
        SendGuild(reply)
    end)
end

-- =========================================================================
-- BIENVENIDA A MIEMBROS NUEVOS
-- =========================================================================
-- Cuando el juego avisa de que alguien se ha unido a la hermandad, se le da la bienvenida
-- con settings.welcomeMessage ({nombre}, {hermandad}). Responde un solo cliente (prefijo
-- GuildControlGreet, "W:nombre") y no se envía si alguien le escribe antes mencionándolo.
local function CancelWelcome(name)
    local timer = pendingWelcomes[name]
    if timer then
        timer:Cancel()
        pendingWelcomes[name] = nil
    end
end

local function ScheduleWelcome(who)
    -- El nombre puede venir como enlace de jugador: |Hplayer:Nombre|h[Nombre]|h
    who = string.match(who, "|Hplayer:([^|:]+)") or string.match(who, "%[(.-)%]") or who
    local name = ShortName(who)
    if IsMe(name) then return end
    -- Sin bienvenida en este cliente, el saludo automático sigue funcionando para él (salvo
    -- que otro cliente le dé la bienvenida: llega "W:nombre" y entonces se le aparta)
    if not GetSettings().welcomeNew or pendingWelcomes[name] then return end
    newMembers[name] = true
    MarkGreeted(name)   -- el saludo automático no se le aplica
    pendingWelcomes[name] = C_Timer.NewTimer(3 + math.random() * GREET_DELAY_JITTER, function()
        pendingWelcomes[name] = nil
        if not IsInGuild() or not GetSettings().welcomeNew then return end
        local template = GetSettings().welcomeMessage
        if not template or strtrim(template) == "" then return end
        local reply = string.gsub(addonTable.NormalizeVars(template), "{nombre}", function() return name end)
        reply = string.gsub(reply, "{hermandad}", function() return addonTable.GetDisplayGuildName() end)
        if C_ChatInfo and C_ChatInfo.SendAddonMessage then
            C_ChatInfo.SendAddonMessage("GuildControlGreet", "W:" .. name, "GUILD")
        end
        SendGuild(reply)
    end)
end

-- =========================================================================
-- EVENTOS
-- =========================================================================
chatFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_GUILD" then
        local text, sender = ...
        local guid = select(12, ...)
        -- En contenido restringido los argumentos pueden ser secretos: no se pueden leer
        if IsSecret(text) or IsSecret(sender) or not text or not sender then return end

        AddMessage(sender, text, not IsSecret(guid) and guid or nil, "guild")

        local name = ShortName(sender)

        -- Cualquier mensaje que nombre a un recién llegado cuenta como saludo hacia él
        -- (lo escriba yo u otro miembro): así no se le saluda dos veces
        local answeredSomeone = false
        for newcomer in pairs(loginTimes) do
            if newcomer ~= name and Mentions(text, newcomer) then
                MarkGreeted(newcomer)
                answeredSomeone = true
            end
        end
        for pendingName in pairs(pendingWelcomes) do
            if pendingName ~= name and Mentions(text, pendingName) then CancelWelcome(pendingName) end
        end
        for pendingName in pairs(pendingGreets) do
            if pendingName ~= name and Mentions(text, pendingName) then
                MarkGreeted(pendingName)
                answeredSomeone = true
            end
        end

        -- Solo se responde al saludo de quien acaba de conectarse; "hola Pepe" no es un saludo nuevo
        if not IsMe(sender) and not answeredSomeone and IsGreeting(text) then
            ScheduleGreet(sender)
        end
    elseif CHANNEL_EVENTS[event] then
        local text, otherName = ...
        local guid = select(12, ...)
        if IsSecret(text) or IsSecret(otherName) or not text or not otherName then return end
        guid = not IsSecret(guid) and guid or nil
        if event == "CHAT_MSG_WHISPER_INFORM" then
            -- Susurro enviado: el remitente soy yo y otherName es el destinatario
            AddMessage(UnitName("player"), text, UnitGUID("player"), "whisper", "out", otherName)
        else
            AddMessage(otherName, text, guid, CHANNEL_EVENTS[event], event == "CHAT_MSG_WHISPER" and "in" or nil)
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local text = ...
        if IsSecret(text) or type(text) ~= "string" then return end
        -- "[Nombre] se ha conectado." (el nombre viene como enlace |Hplayer:Nombre|h[Nombre]|h)
        local who = ONLINE_PATTERN and string.match(text, ONLINE_PATTERN)
        if who then
            loginTimes[ShortName(who)] = GetTime()
            if addonTable.Favorites and addonTable.Favorites.OnOnline then addonTable.Favorites.OnOnline(who) end
            return
        end
        local joined = JOIN_PATTERN and string.match(text, JOIN_PATTERN)
        if joined then
            ScheduleWelcome(joined)
            return
        end
        local gone = OFFLINE_PATTERN and string.match(text, OFFLINE_PATTERN)
        if gone then chatModule.MarkOffline(gone) end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if IsSecret(prefix) or IsSecret(msg) or IsSecret(sender) then return end
        -- Otro cliente con GuildControl ya ha saludado a esta persona
        if prefix == "GuildControlGreet" and channel == "GUILD" and msg and not IsMe(sender) then
            local welcomed = string.match(msg, "^W:(.+)$")
            if welcomed then
                newMembers[welcomed] = true
                CancelWelcome(welcomed)
                MarkGreeted(welcomed)
            else
                MarkGreeted(msg)
            end
        end
    end
end)
