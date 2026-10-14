local addonName, addonTable = ...

addonTable.GuildChat = {}
local chatModule = addonTable.GuildChat

-- Guarda los últimos mensajes del chat de hermandad para el panel de la UI y
-- responde automáticamente al saludo de quien ACABA de conectarse.
--
-- Regla del saludo automático: solo se responde si quien saluda
--   1. se conectó hace poco (aviso "X se ha conectado" o cambio en el roster),
--   2. y nadie (ni yo, ni otro cliente con GuildControl, ni otro miembro) le ha
--      saludado desde esa conexión.
-- Así no se saluda a quien lleva rato conectado y contesta a otro recién llegado.

local MAX_MESSAGES = 200
local DEFAULT_GREET_COOLDOWN_MIN = 30   -- no volver a saludar a la misma persona (configurable)
local DEFAULT_LOGIN_WINDOW_MIN = 5      -- minutos tras conectarse en los que se le considera recién llegado
local GREET_GLOBAL_COOLDOWN = 20        -- como mucho un saludo automático cada 20 s
local DEFAULT_GREET_DELAY = 2           -- segundos antes de responder (configurable)
local GREET_DELAY_JITTER = 4            -- hasta 4 s extra aleatorios para que solo responda un cliente
local GREET_MAX_LENGTH = 40             -- mensajes más largos no se consideran un saludo

-- Lista por defecto de settings.greetWords (se edita en Configuración)
chatModule.DEFAULT_GREET_WORDS = "hola, holaa, holi, holis, ola, buenas, buenass, wenas, nas, buenos dias, "
    .. "buen dia, buenas tardes, buenas noches, nas noches, wenas noches, saludos, que tal, hey, hello, hi"

local messages = {}      -- { {time, sender, fullName, class, text}, ... } (más antiguo primero)
local listener = nil     -- función que la UI registra para recibir mensajes nuevos

local loginTimes = {}         -- [nombre corto] = GetTime() de su última conexión vista en esta sesión
local lastGreetByPlayer = {}  -- [nombre corto] = GetTime() del último saludo (de quien sea) a esa persona
local lastGreetTime = -GREET_GLOBAL_COOLDOWN
local pendingGreets = {}      -- [nombre corto] = timer pendiente

local chatFrame = CreateFrame("Frame")
chatFrame:RegisterEvent("CHAT_MSG_GUILD")
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
    return ShortName(name) == UnitName("player")
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

-- =========================================================================
-- MENSAJES PARA EL PANEL
-- =========================================================================
function chatModule.GetMessages()
    return messages
end

function chatModule.SetListener(fn)
    listener = fn
end

function chatModule.Send(text)
    text = strtrim(text or "")
    if text == "" or not IsInGuild() then return end
    SendGuild(text)
end

local function AddMessage(sender, text, guid)
    local class = nil
    if guid and guid ~= "" and GetPlayerInfoByGUID then
        local ok, _, englishClass = pcall(GetPlayerInfoByGUID, guid)
        if ok then class = englishClass end
    end
    local entry = { time = date("%H:%M"), sender = ShortName(sender), fullName = sender, class = class, text = text }
    table.insert(messages, entry)
    if #messages > MAX_MESSAGES then table.remove(messages, 1) end
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
        if not template or strtrim(template) == "" then template = "¡Hola, {nombre}!" end
        local reply = string.gsub(template, "{nombre}", function() return name end)

        lastGreetByPlayer[name] = GetTime()
        lastGreetTime = GetTime()
        if C_ChatInfo and C_ChatInfo.SendAddonMessage then
            C_ChatInfo.SendAddonMessage("GuildControlGreet", name, "GUILD")
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

        AddMessage(sender, text, not IsSecret(guid) and guid or nil)

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
    elseif event == "CHAT_MSG_SYSTEM" then
        local text = ...
        if IsSecret(text) or type(text) ~= "string" then return end
        -- "[Nombre] se ha conectado." (el nombre viene como enlace |Hplayer:Nombre|h[Nombre]|h)
        local who = ONLINE_PATTERN and string.match(text, ONLINE_PATTERN)
        if who then
            loginTimes[ShortName(who)] = GetTime()
            return
        end
        local gone = OFFLINE_PATTERN and string.match(text, OFFLINE_PATTERN)
        if gone then chatModule.MarkOffline(gone) end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if IsSecret(prefix) or IsSecret(msg) or IsSecret(sender) then return end
        -- Otro cliente con GuildControl ya ha saludado a esta persona
        if prefix == "GuildControlGreet" and channel == "GUILD" and msg and not IsMe(sender) then
            MarkGreeted(msg)
        end
    end
end)
