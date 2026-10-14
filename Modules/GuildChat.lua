local addonName, addonTable = ...

addonTable.GuildChat = {}
local chatModule = addonTable.GuildChat

-- Guarda los últimos mensajes del chat de hermandad para el panel de la UI y
-- responde automáticamente a los saludos de otros miembros.

local MAX_MESSAGES = 200
local GREET_PLAYER_COOLDOWN = 30 * 60   -- no volver a saludar a la misma persona en 30 min
local GREET_GLOBAL_COOLDOWN = 20        -- como mucho un saludo automático cada 20 s
local GREET_MIN_DELAY, GREET_MAX_DELAY = 2, 6
local GREET_MAX_LENGTH = 40             -- mensajes más largos no se consideran un saludo

local messages = {}      -- { {time, sender, class, text}, ... } (más antiguo primero)
local listener = nil     -- función que la UI registra para recibir mensajes nuevos

local lastGreetByPlayer = {}
local lastGreetTime = -GREET_GLOBAL_COOLDOWN
local pendingGreets = {}  -- [nombre] = timer pendiente

-- Palabras que cuentan como saludo (en minúsculas, sin tildes)
local GREETING_WORDS = {
    "hola", "holaa", "holaaa", "holi", "holis", "ola", "buenas", "wenas", "buenos dias",
    "buenas tardes", "buenas noches", "saludos", "hey", "hello", "hi", "hii", "aloha",
    "que tal", "buen dia",
}

local chatFrame = CreateFrame("Frame")
chatFrame:RegisterEvent("CHAT_MSG_GUILD")
chatFrame:RegisterEvent("CHAT_MSG_ADDON")

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

-- Un mensaje es un saludo si empieza por una de las palabras y es corto
local function IsGreeting(text)
    if #text > GREET_MAX_LENGTH then return false end
    local simple = " " .. Simplify(text) .. " "
    for _, word in ipairs(GREETING_WORDS) do
        if string.find(simple, "^ " .. word .. " ") then return true end
    end
    return false
end

local function SendGuild(msg)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(msg, "GUILD")
    else
        SendChatMessage(msg, "GUILD")
    end
end

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
    local entry = { time = date("%H:%M"), sender = ShortName(sender), class = class, text = text }
    table.insert(messages, entry)
    if #messages > MAX_MESSAGES then table.remove(messages, 1) end
    if listener then listener(entry) end
end

-- =========================================================================
-- SALUDO AUTOMÁTICO
-- =========================================================================
local function GetSettings()
    return GuildControlDB and GuildControlDB.settings or {}
end

local function CancelPendingGreet(name)
    local timer = pendingGreets[name]
    if timer then
        timer:Cancel()
        pendingGreets[name] = nil
    end
end

local function ScheduleGreet(sender)
    local settings = GetSettings()
    if not settings.autoGreet then return end

    local name = ShortName(sender)
    local now = GetTime()
    if pendingGreets[name] then return end
    if lastGreetByPlayer[name] and now - lastGreetByPlayer[name] < GREET_PLAYER_COOLDOWN then return end
    if now - lastGreetTime < GREET_GLOBAL_COOLDOWN then return end

    -- Retraso aleatorio para parecer natural y para que solo responda un cliente con GuildControl
    local delay = GREET_MIN_DELAY + math.random() * (GREET_MAX_DELAY - GREET_MIN_DELAY)
    pendingGreets[name] = C_Timer.NewTimer(delay, function()
        pendingGreets[name] = nil
        if not IsInGuild() or not GetSettings().autoGreet then return end

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
        if IsMe(sender) then
            -- Si saludo yo a mano a alguien, no hace falta el saludo automático
            for pendingName in pairs(pendingGreets) do
                if string.find(string.lower(text), string.lower(pendingName), 1, true) then
                    CancelPendingGreet(pendingName)
                    lastGreetByPlayer[pendingName] = GetTime()
                end
            end
        else
            -- Si otro miembro ya ha saludado a esta persona, se cancela el nuestro
            local answeredSomeone = false
            for pendingName in pairs(pendingGreets) do
                if pendingName ~= name and string.find(string.lower(text), string.lower(pendingName), 1, true) then
                    CancelPendingGreet(pendingName)
                    lastGreetByPlayer[pendingName] = GetTime()
                    answeredSomeone = true
                end
            end
            -- "hola Pepe" en respuesta a otro saludo no es un saludo nuevo a la hermandad
            if not answeredSomeone and IsGreeting(text) then
                ScheduleGreet(sender)
            end
        end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if IsSecret(prefix) or IsSecret(msg) or IsSecret(sender) then return end
        -- Otro cliente con GuildControl ya ha saludado a esta persona
        if prefix == "GuildControlGreet" and channel == "GUILD" and msg and not IsMe(sender) then
            CancelPendingGreet(msg)
            lastGreetByPlayer[msg] = GetTime()
        end
    end
end)
