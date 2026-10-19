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

local SchedulePublish   -- declaración adelantada (sección de sincronización)

-- Solo cuenta como cambio (y se comparte con los demás oficiales) si el valor es distinto
function annModule.UpdateAnnouncementData(idx, enabled, message, interval)
    if not GuildControlDB.announcements then return end
    local data = GuildControlDB.announcements[idx]
    if not data then return end
    local changed = false
    if enabled ~= nil and (data.enabled and true or false) ~= (enabled and true or false) then
        data.enabled = enabled and true or false
        changed = true
    end
    if message ~= nil and message ~= (data.message or "") then
        data.message = message
        changed = true
    end
    if interval ~= nil then
        interval = math.max(1, math.floor(tonumber(interval) or 15))
        if interval ~= data.interval then
            data.interval = interval
            changed = true
        end
    end
    if changed then
        data.updatedAt = GetServerTime()
        SchedulePublish(idx)
    end
end

-- =========================================================================
-- PUBLICACIÓN AUTOMÁTICA EN EL CANAL DE HERMANDAD
-- =========================================================================
local TICK_SECONDS = 10      -- resolución del ticker; el intervalo de cada anuncio va en minutos
local MAX_CHAT_BYTES = 255   -- límite de longitud de un mensaje de chat

local ticker = nil
local LOGIN_GRACE = 60       -- tras entrar, nunca se publica antes de este margen
-- La hora del último envío se guarda en la ranura (data.lastSentAt, hora del servidor), así un
-- /reload o cambiar de personaje no reinicia la cuenta atrás

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

-- =========================================================================
-- ANUNCIOS COMUNES A TODOS LOS OFICIALES
-- =========================================================================
-- Las 5 ranuras son las mismas para todos los oficiales: cada cambio lleva su hora
-- (data.updatedAt, hora del servidor) y se envía a la hermandad; gana el más reciente.
-- Para que cada anuncio salga una sola vez aunque haya varios oficiales conectados, quien lo
-- publica avisa a los demás de la hora del envío y ellos reinician su cuenta atrás.
-- Mensajes (prefijo GuildControlAnn, canal de hermandad; solo se aceptan de oficiales):
--   "A<id>:<i>:<n>:<trozo>"  ranura troceada: "ranura;hora;activo(1/0);intervalo;texto"
--   "S;ranura;hora"          la ranura se acaba de publicar a esa hora
--   "Q"                      petición al entrar (responde un oficial con las ranuras)
local PREFIX = "GuildControlAnn"
local CHUNK_BYTES = 200
local SEND_INTERVAL = 0.3
local SEND_JITTER = 8   -- segundos al azar antes de publicar: así lo publica un solo cliente

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local function IsOfficer()
    return not addonTable.Profiles or not addonTable.Profiles.IsOfficer or addonTable.Profiles.IsOfficer()
end

local function IsOfficerName(name)
    return addonTable.Profiles and addonTable.Profiles.IsOfficerName and addonTable.Profiles.IsOfficerName(name) or false
end

local function CanSend()
    return IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage and IsOfficer()
end

local function NotifyUI()
    if addonTable.UI and addonTable.UI.RefreshAnnouncementFields then addonTable.UI.RefreshAnnouncementFields() end
end

-- Cola de envío (un trozo cada 0,3 s)
local sendQueue, sendTicker = {}, nil
local function ProcessQueue()
    local msg = table.remove(sendQueue, 1)
    if not msg then
        if sendTicker then sendTicker:Cancel() end
        sendTicker = nil
        return
    end
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
end

local function Queue(msg)
    table.insert(sendQueue, msg)
    if not sendTicker then sendTicker = C_Timer.NewTicker(SEND_INTERVAL, ProcessQueue) end
end

local function SendSlot(idx)
    local data = GuildControlDB.announcements and GuildControlDB.announcements[idx]
    if not data or not CanSend() then return end
    local payload = idx .. ";" .. (tonumber(data.updatedAt) or 0) .. ";" .. (data.enabled and 1 or 0) .. ";"
        .. (tonumber(data.interval) or 15) .. ";" .. (data.message or "")
    local msgId = tostring(math.random(100000, 999999))
    local total = math.max(1, math.ceil(#payload / CHUNK_BYTES))
    for i = 1, total do
        Queue("A" .. msgId .. ":" .. i .. ":" .. total .. ":" .. string.sub(payload, (i - 1) * CHUNK_BYTES + 1, i * CHUNK_BYTES))
    end
end

-- Varios cambios seguidos (cada tecla del texto) se envían una sola vez
local publishTimers = {}
SchedulePublish = function(idx)
    if publishTimers[idx] then publishTimers[idx]:Cancel() end
    publishTimers[idx] = C_Timer.NewTimer(3, function()
        publishTimers[idx] = nil
        SendSlot(idx)
    end)
end

local function ApplySlot(payload)
    local idx, at, enabled, interval, message = string.match(payload, "^(%d+);(%d+);([01]);(%d+);(.*)$")
    idx, at, interval = tonumber(idx), tonumber(at), tonumber(interval)
    local data = idx and GuildControlDB.announcements and GuildControlDB.announcements[idx]
    if not data or not at or at <= (tonumber(data.updatedAt) or 0) then return end
    data.updatedAt = at
    data.enabled = enabled == "1"
    data.interval = math.max(1, math.min(10000, interval or 15))
    data.message = string.sub(message or "", 1, 255)
    NotifyUI()
end

local partials = {}
local replyTimer = nil
local function OnChunk(sender, msg)
    local msgId, index, total, chunk = string.match(msg, "^A(%d+):(%d+):(%d+):(.*)$")
    index, total = tonumber(index), tonumber(total)
    if not msgId or not index or not total or total > 10 then return end
    -- Otro oficial ya está respondiendo a la petición
    if replyTimer then replyTimer:Cancel(); replyTimer = nil end
    local key = sender .. ":" .. msgId
    local partial = partials[key] or { total = total, parts = {}, count = 0 }
    partials[key] = partial
    if not partial.parts[index] then
        partial.parts[index] = chunk
        partial.count = partial.count + 1
    end
    if partial.count < partial.total then return end
    partials[key] = nil
    if IsOfficerName(sender) then ApplySlot(table.concat(partial.parts)) end
end

-- =========================================================================
-- PUBLICACIÓN AUTOMÁTICA EN EL CANAL DE HERMANDAD
-- =========================================================================
local pendingSends = {}   -- [ranura] = timer del envío con espera al azar

function annModule.ProcessAnnouncements()
    if not IsInGuild() then return end
    -- Los anuncios son cosa de oficiales: si pierdes el rango, tu cliente deja de publicarlos
    -- (se conservan y vuelven a salir si lo recuperas)
    if not IsOfficer() then return end
    if type(GuildControlDB) ~= "table" or type(GuildControlDB.announcements) ~= "table" then return end

    local now = GetServerTime()
    for idx, data in ipairs(GuildControlDB.announcements) do
        local msg = type(data.message) == "string" and data.message:match("^%s*(.-)%s*$") or ""

        if data.enabled and msg ~= "" then
            local intervalSeconds = math.max(1, tonumber(data.interval) or 15) * 60
            local last = tonumber(data.lastSentAt)
            if not last or last > now then
                -- Recién activado: el primer envío llega al cumplirse el intervalo, no al instante
                data.lastSentAt = now
            elseif now - last >= intervalSeconds and not pendingSends[idx] then
                -- Espera al azar y vuelve a mirar: si otro oficial lo ha publicado, no se repite
                pendingSends[idx] = C_Timer.NewTimer(math.random() * SEND_JITTER, function()
                    pendingSends[idx] = nil
                    local sentAt = GetServerTime()
                    local current = tonumber(data.lastSentAt) or 0
                    if not data.enabled or sentAt - current < intervalSeconds then return end
                    data.lastSentAt = sentAt
                    SendGuildMessage(TruncateForChat(msg))
                    if CanSend() then pcall(C_ChatInfo.SendAddonMessage, PREFIX, "S;" .. idx .. ";" .. sentAt, "GUILD") end
                end)
            end
        else
            -- Al desactivar o vaciar la ranura se reinicia su cuenta atrás
            data.lastSentAt = nil
        end
    end
end

function annModule.StartTicker()
    if ticker or not (C_Timer and C_Timer.NewTicker) then return end
    -- Si al entrar ya tocaba publicar (por ejemplo, tras días sin conectarse), se espera el margen
    local now = GetServerTime()
    for _, data in ipairs(type(GuildControlDB.announcements) == "table" and GuildControlDB.announcements or {}) do
        local last = tonumber(data.lastSentAt)
        local intervalSeconds = math.max(1, tonumber(data.interval) or 15) * 60
        if last and now - last > intervalSeconds - LOGIN_GRACE then data.lastSentAt = now - intervalSeconds + LOGIN_GRACE end
    end
    ticker = C_Timer.NewTicker(TICK_SECONDS, annModule.ProcessAnnouncements)
end

function annModule.StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- PLAYER_LOGIN llega después de cargar las SavedVariables, así que GuildControlDB ya existe
local annEventFrame = CreateFrame("Frame")
annEventFrame:RegisterEvent("PLAYER_LOGIN")
annEventFrame:RegisterEvent("CHAT_MSG_ADDON")
annEventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if addonTable.InitDB then addonTable.InitDB() end
        annModule.StartTicker()
        -- Los oficiales piden las ranuras al entrar (llegan antes del margen de LOGIN_GRACE)
        C_Timer.After(20, function()
            if CanSend() then pcall(C_ChatInfo.SendAddonMessage, PREFIX, "Q", "GUILD") end
        end)
        return
    end
    local prefix, msg, channel, sender = ...
    if prefix ~= PREFIX or channel ~= "GUILD" or type(msg) ~= "string" or not sender then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    if not GuildControlDB or type(GuildControlDB.announcements) ~= "table" then return end
    if addonTable.IsMe and addonTable.IsMe(sender) then return end
    local fullSender = addonTable.NormalizeName and addonTable.NormalizeName(sender) or sender
    local kind = string.sub(msg, 1, 1)
    if kind == "A" then
        OnChunk(fullSender, msg)
    elseif kind == "S" then
        local idx, at = string.match(msg, "^S;(%d+);(%d+)$")
        idx, at = tonumber(idx), tonumber(at)
        local data = idx and GuildControlDB.announcements[idx]
        if data and at and IsOfficerName(fullSender) and at > (tonumber(data.lastSentAt) or 0) then
            data.lastSentAt = at
            if pendingSends[idx] then pendingSends[idx]:Cancel(); pendingSends[idx] = nil end
        end
    elseif msg == "Q" then
        -- Responde un oficial (el que espere menos) con las ranuras que se han tocado alguna vez
        if not CanSend() or replyTimer then return end
        replyTimer = C_Timer.NewTimer(2 + math.random() * 4, function()
            replyTimer = nil
            for idx, data in ipairs(GuildControlDB.announcements) do
                if (tonumber(data.updatedAt) or 0) > 0 then SendSlot(idx) end
            end
        end)
    end
end)
