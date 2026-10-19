local addonName, addonTable = ...
local L = addonTable.L

addonTable.GuildConfig = {}
local cfgModule = addonTable.GuildConfig

-- Ajustes de la hermandad que definen los oficiales y ven todos: el enlace de Discord, el
-- icono del encabezado y las normas. Se guardan en GuildControlDB.settings (discordLink, guildIcon y
-- guildConfigAt, la hora del servidor del último cambio) y se comparten con el prefijo
-- GuildControlCfg en el canal de hermandad:
--   "C;hora;icono;discord"  configuración (solo se acepta de oficiales y si es más reciente)
--   "P;hora;1|0"            los jugadores pueden usar Invitar (settings.playerInvite, playerInviteAt)
--   "R;hora;i;n;trozo"      normas (settings.guildRules, guildRulesAt), en n trozos de 200 bytes
--   "Q"                     petición al entrar (responde un oficial con la suya)

local PREFIX = "GuildControlCfg"
local listeners = {}
local replyTimer = nil
local RULES_MAX = 1500        -- bytes de las normas
local RULES_CHUNK = 200       -- bytes por mensaje (máximo 255 con la cabecera)
local rulesParts = {}         -- trozos recibidos: [remitente .. hora] = { n, parts }

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local function Settings() return GuildControlDB.settings end

local function Notify()
    for _, fn in ipairs(listeners) do fn() end
    if addonTable.UI and addonTable.UI.UpdateHeader then addonTable.UI.UpdateHeader() end
    -- El permiso de Invitar cambia las pestañas que ve el jugador
    if addonTable.UI and addonTable.UI.ApplyProfile and addonTable.UI.IsShown and addonTable.UI.IsShown() then addonTable.UI.ApplyProfile() end
end

function cfgModule.AddListener(fn)
    table.insert(listeners, fn)
end

local function IsOfficer()
    return not addonTable.Profiles or addonTable.Profiles.IsOfficer()
end

-- Limpia los valores: sin separadores de mensaje ni códigos de color
local function CleanDiscord(text)
    text = strtrim(string.gsub(tostring(text or ""), "[;|]", ""))
    return string.sub(text, 1, 120)
end

-- Icono válido: "tabard" (emblema del juego), un fileID o una ruta de textura.
-- Acepta también la ruta completa del disco (F:\...\Interface\AddOns\...\logo.tga): el juego
-- solo carga rutas que empiezan por Interface\ y sin extensión.
function cfgModule.CleanIcon(value)
    if value == nil then return nil end
    if tonumber(value) then return tonumber(value) end
    value = strtrim(tostring(value))
    if value == "tabard" then return value end
    value = string.gsub(value, "/", "\\")
    local start = string.find(string.lower(value), "interface\\", 1, true)
    if start then value = string.sub(value, start) end
    value = string.gsub(value, "%.[Tt][Gg][Aa]$", "")
    value = string.gsub(value, "%.[Bb][Ll][Pp]$", "")
    if value == "" or #value > 120 or not string.match(value, "^[%w_\\/%.%-]+$") then return nil end
    return value
end

local function Send(msg)
    if IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD")
    end
end

-- Normas: sin códigos de color y con un tope de bytes (sin cortar un carácter UTF-8)
local function CleanRules(text)
    text = string.gsub(tostring(text or ""), "|", "")
    text = string.gsub(text, "\r", "")
    text = strtrim(text)
    if #text > RULES_MAX then
        local cut = RULES_MAX
        while cut > 0 and string.byte(text, cut + 1) and string.byte(text, cut + 1) >= 128 and string.byte(text, cut + 1) < 192 do
            cut = cut - 1
        end
        text = string.sub(text, 1, cut)
    end
    return text
end
cfgModule.RULES_MAX = RULES_MAX

-- Los saltos de línea viajan como "~n" (y "~" como "~t")
local function EncodeRules(text)
    return (string.gsub(string.gsub(text, "~", "~t"), "\n", "~n"))
end
local function DecodeRules(text)
    return (string.gsub(text, "~(.)", function(c) return c == "n" and "\n" or (c == "t" and "~" or c) end))
end

-- Trozos de 200 bytes cada 0,3 s (sin partir un carácter UTF-8)
local function SendRules()
    local s = Settings()
    if not (s.guildRulesAt and s.guildRulesAt > 0) then return end
    local data = EncodeRules(s.guildRules or "")
    local chunks, pos = {}, 1
    repeat
        local last = math.min(#data, pos + RULES_CHUNK - 1)
        while last < #data and last > pos and string.byte(data, last + 1) >= 128 and string.byte(data, last + 1) < 192 do
            last = last - 1
        end
        table.insert(chunks, string.sub(data, pos, last))
        pos = last + 1
    until pos > #data
    local at = s.guildRulesAt
    for i, chunk in ipairs(chunks) do
        C_Timer.After((i - 1) * 0.3, function()
            Send(table.concat({ "R", at, i, #chunks, chunk }, ";"))
        end)
    end
end

function cfgModule.Broadcast()
    local s = Settings()
    if s.guildConfigAt and s.guildConfigAt > 0 then
        Send(table.concat({ "C", s.guildConfigAt, tostring(s.guildIcon or ""), s.discordLink or "" }, ";"))
    end
    if s.playerInviteAt and s.playerInviteAt > 0 then
        Send("P;" .. s.playerInviteAt .. ";" .. (s.playerInvite and "1" or "0"))
    end
    SendRules()
end

function cfgModule.GetRules()
    return Settings().guildRules or ""
end

-- Solo oficiales: cambia las normas y las envía a la hermandad
function cfgModule.SetRules(text)
    if not IsOfficer() then return false end
    local s = Settings()
    s.guildRules = CleanRules(text)
    s.guildRulesAt = GetServerTime()
    SendRules()
    Notify()
    return true
end

-- Solo oficiales: los jugadores pueden (o no) usar la pestaña Invitar
function cfgModule.SetPlayerInvite(enabled)
    if not IsOfficer() then return false end
    local s = Settings()
    s.playerInvite = enabled and true or false
    s.playerInviteAt = GetServerTime()
    Send("P;" .. s.playerInviteAt .. ";" .. (s.playerInvite and "1" or "0"))
    Notify()
    return true
end

function cfgModule.CanPlayersInvite()
    return Settings().playerInvite == true
end

-- Solo oficiales: cambia el Discord o el icono (nil = no se toca) y lo envía a la hermandad
function cfgModule.Set(discord, icon)
    if not IsOfficer() then return false end
    local s = Settings()
    if discord ~= nil then s.discordLink = CleanDiscord(discord) end
    if icon ~= nil then
        local clean = cfgModule.CleanIcon(icon)
        if clean then s.guildIcon = clean end
    end
    s.guildConfigAt = GetServerTime()
    cfgModule.Broadcast()
    Notify()
    return true
end

local function OnConfig(sender, msg)
    if addonTable.Profiles and addonTable.Profiles.IsOfficerName and not addonTable.Profiles.IsOfficerName(sender) then return end
    local _, at, icon, discord = strsplit(";", msg, 4)
    at = tonumber(at)
    local s = Settings()
    if not at or at <= (s.guildConfigAt or 0) then return end
    s.guildConfigAt = at
    s.discordLink = CleanDiscord(discord)
    s.guildIcon = cfgModule.CleanIcon(icon) or s.guildIcon
    Notify()
end

local function OnRules(sender, msg)
    if addonTable.Profiles and addonTable.Profiles.IsOfficerName and not addonTable.Profiles.IsOfficerName(sender) then return end
    local _, at, index, count, chunk = strsplit(";", msg, 5)
    at, index, count = tonumber(at), tonumber(index), tonumber(count)
    local s = Settings()
    if not (at and index and count) or count < 1 or count > 20 or index < 1 or index > count then return end
    if at <= (s.guildRulesAt or 0) then return end
    local key = sender .. ":" .. at
    local entry = rulesParts[key]
    if not entry then
        entry = { n = count, parts = {} }
        rulesParts[key] = entry
        C_Timer.After(30, function() rulesParts[key] = nil end)
    end
    entry.parts[index] = chunk or ""
    for i = 1, entry.n do
        if not entry.parts[i] then return end
    end
    rulesParts[key] = nil
    local text = CleanRules(DecodeRules(table.concat(entry.parts)))
    local changed = text ~= (s.guildRules or "")
    s.guildRulesAt = at
    s.guildRules = text
    Notify()
    if changed and text ~= "" and addonTable.UI and addonTable.UI.ShowToast then
        addonTable.UI.ShowToast(L["Las normas de la hermandad han cambiado. Míralas en el Resumen."], "Interface\\Icons\\INV_Misc_Note_01")
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if not GuildControlDB or not GuildControlDB.settings then return end
    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin or isReloadingUi then C_Timer.After(12, function() Send("Q") end) end
        return
    end

    local prefix, msg, channel, sender = ...
    if prefix ~= PREFIX or channel ~= "GUILD" then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    if not msg or not sender or addonTable.IsMe(sender) then return end
    local fullSender = addonTable.Profiles and addonTable.Profiles.NormalizeName(sender) or sender

    if msg == "Q" then
        -- Responde un solo oficial: el que espere menos; los demás se callan al ver su respuesta
        if not IsOfficer() or replyTimer or not (Settings().guildConfigAt or Settings().playerInviteAt or Settings().guildRulesAt) then return end
        replyTimer = C_Timer.NewTimer(2 + math.random() * 4, function()
            replyTimer = nil
            cfgModule.Broadcast()
        end)
    elseif string.sub(msg, 1, 2) == "C;" then
        if replyTimer then replyTimer:Cancel(); replyTimer = nil end
        OnConfig(fullSender, msg)
    elseif string.sub(msg, 1, 2) == "R;" then
        if replyTimer then replyTimer:Cancel(); replyTimer = nil end
        OnRules(fullSender, msg)
    elseif string.sub(msg, 1, 2) == "P;" then
        if replyTimer then replyTimer:Cancel(); replyTimer = nil end
        if addonTable.Profiles and addonTable.Profiles.IsOfficerName and not addonTable.Profiles.IsOfficerName(fullSender) then return end
        local _, at, value = strsplit(";", msg)
        at = tonumber(at)
        local s = Settings()
        if at and at > (s.playerInviteAt or 0) then
            s.playerInviteAt = at
            s.playerInvite = value == "1"
            Notify()
        end
    end
end)
