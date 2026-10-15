local addonName, addonTable = ...
local L = addonTable.L

addonTable.GuildConfig = {}
local cfgModule = addonTable.GuildConfig

-- Ajustes de la hermandad que definen los oficiales y ven todos: el enlace de Discord y el
-- icono del encabezado. Se guardan en GuildControlDB.settings (discordLink, guildIcon y
-- guildConfigAt, la hora del servidor del último cambio) y se comparten con el prefijo
-- GuildControlCfg en el canal de hermandad:
--   "C;hora;icono;discord"  configuración (solo se acepta de oficiales y si es más reciente)
--   "Q"                     petición al entrar (responde un oficial con la suya)

local PREFIX = "GuildControlCfg"
local listeners = {}
local replyTimer = nil

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local function Settings() return GuildControlDB.settings end

local function Notify()
    for _, fn in ipairs(listeners) do fn() end
    if addonTable.UI and addonTable.UI.UpdateHeader then addonTable.UI.UpdateHeader() end
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

-- Icono válido: "tabard" (emblema del juego), un fileID o una ruta de textura
function cfgModule.CleanIcon(value)
    if value == nil then return nil end
    if tonumber(value) then return tonumber(value) end
    value = strtrim(tostring(value))
    if value == "tabard" then return value end
    if value == "" or #value > 120 or not string.match(value, "^[%w_\\/%.%-]+$") then return nil end
    return value
end

local function Send(msg)
    if IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD")
    end
end

function cfgModule.Broadcast()
    local s = Settings()
    if not s.guildConfigAt or s.guildConfigAt == 0 then return end
    Send(table.concat({ "C", s.guildConfigAt, tostring(s.guildIcon or ""), s.discordLink or "" }, ";"))
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
    if not msg or not sender or Ambiguate(sender, "none") == UnitName("player") then return end
    local fullSender = addonTable.Profiles and addonTable.Profiles.NormalizeName(sender) or sender

    if msg == "Q" then
        -- Responde un solo oficial: el que espere menos; los demás se callan al ver su respuesta
        if not IsOfficer() or replyTimer or not Settings().guildConfigAt then return end
        replyTimer = C_Timer.NewTimer(2 + math.random() * 4, function()
            replyTimer = nil
            cfgModule.Broadcast()
        end)
    elseif string.sub(msg, 1, 2) == "C;" then
        if replyTimer then replyTimer:Cancel(); replyTimer = nil end
        OnConfig(fullSender, msg)
    end
end)
