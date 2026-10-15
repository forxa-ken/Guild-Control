local addonName, addonTable = ...
local L = addonTable.L

addonTable.Announcements = {}
local annModule = addonTable.Announcements

local currentSelectedAnnIndex = 1

function annModule.GetSelectedIndex()
    return currentSelectedAnnIndex
end

function annModule.SetSelectedIndex(idx)
    currentSelectedAnnIndex = idx
end

function annModule.GetAnnouncementData(idx)
    local targetIdx = idx or currentSelectedAnnIndex
    return GuildControlDB.announcements and GuildControlDB.announcements[targetIdx]
end

function annModule.UpdateAnnouncementData(idx, enabled, message, interval)
    if not GuildControlDB.announcements then return end
    local data = GuildControlDB.announcements[idx]
    if data then
        if enabled ~= nil then data.enabled = enabled end
        if message ~= nil then data.message = message end
        if interval ~= nil then data.interval = math.max(1, tonumber(interval) or 15) end
    end
end

-- =========================================================================
-- PUBLICACIÓN AUTOMÁTICA EN EL CANAL DE HERMANDAD
-- =========================================================================
local TICK_SECONDS = 10      -- resolución del ticker; el intervalo de cada anuncio va en minutos
local MAX_CHAT_BYTES = 255   -- límite de longitud de un mensaje de chat

local ticker = nil
local lastSent = {}          -- [índice de ranura] = GetTime() del último envío (o de la activación)

-- Recorta a 255 bytes sin partir un carácter UTF-8 multibyte
local function TruncateForChat(msg)
    if #msg <= MAX_CHAT_BYTES then return msg end
    local cut = MAX_CHAT_BYTES
    while cut > 0 do
        local nextByte = string.byte(msg, cut + 1)
        if not nextByte or nextByte < 0x80 or nextByte >= 0xC0 then break end
        cut = cut - 1
    end
    return string.sub(msg, 1, cut)
end

local function SendGuildMessage(msg)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(msg, "GUILD")
    else
        SendChatMessage(msg, "GUILD")
    end
end

function annModule.ProcessAnnouncements()
    if not IsInGuild() then return end
    if type(GuildControlDB) ~= "table" or type(GuildControlDB.announcements) ~= "table" then return end

    local now = GetTime()
    for idx, data in ipairs(GuildControlDB.announcements) do
        local msg = type(data.message) == "string" and data.message:match("^%s*(.-)%s*$") or ""

        if data.enabled and msg ~= "" then
            local intervalSeconds = math.max(1, tonumber(data.interval) or 15) * 60
            if not lastSent[idx] then
                -- Recién activado: el primer envío llega al cumplirse el intervalo, no al instante
                lastSent[idx] = now
            elseif now - lastSent[idx] >= intervalSeconds then
                lastSent[idx] = now
                SendGuildMessage(TruncateForChat(msg))
            end
        else
            -- Al desactivar o vaciar la ranura se reinicia su cuenta atrás
            lastSent[idx] = nil
        end
    end
end

function annModule.StartTicker()
    if ticker or not (C_Timer and C_Timer.NewTicker) then return end
    ticker = C_Timer.NewTicker(TICK_SECONDS, annModule.ProcessAnnouncements)
end

function annModule.StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    wipe(lastSent)
end

-- PLAYER_LOGIN llega después de cargar las SavedVariables, así que GuildControlDB ya existe
local annEventFrame = CreateFrame("Frame")
annEventFrame:RegisterEvent("PLAYER_LOGIN")
annEventFrame:SetScript("OnEvent", function()
    if addonTable.InitDB then addonTable.InitDB() end
    annModule.StartTicker()
end)
