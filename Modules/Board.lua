local addonName, addonTable = ...
local L = addonTable.L

addonTable.Board = {}
local boardModule = addonTable.Board

-- Pizarra para explicar un jefe: un lienzo con marcas de banda, iconos de rol, texto y trazos
-- a mano alzada. Hay una pizarra por jefe (o una libre) y el líder, un ayudante o un oficial
-- la enseña a su grupo: a los demás se les abre con lo dibujado.
--
-- GuildControlDB.boards[clave] = { items = { ... }, at = hora, from = quién la envió }
--   clave = "idBanda:jefe" (jefes de Roster.GetRaidBosses) o "free"
--   item = { k = "m", x, y, v = 1..8 }        marca de banda
--          { k = "r", x, y, v = "tank"|"healer"|"dps" }
--          { k = "t", x, y, v = texto }
--          { k = "s", c = color, p = "x,y,x,y,..." }   trazo
--   Las coordenadas van de 0 a 1000 en los dos ejes (no dependen del tamaño de la ventana).
--
-- Mensajes (prefijo GuildControlBrd, canal del grupo):
--   "D<id>:<i>:<n>:<trozo>"  pizarra troceada (serializador de Roster): { key, title, items }

local PREFIX = "GuildControlBrd"
local CHUNK_BYTES = 200
local SEND_INTERVAL = 0.25
local MAX_ITEMS = 300
local MAX_POINTS = 2000          -- puntos de trazo en total
local CANVAS_W, CANVAS_H = 640, 440

boardModule.COLORS = {
    { 1, 1, 1 }, { 1, 0.25, 0.25 }, { 1, 0.85, 0.1 }, { 0.3, 1, 0.3 }, { 0.3, 0.6, 1 },
}

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local function PrintGC(msg)
    print("|cFF00FFFF[GuildControl]|r " .. msg)
end

-- =========================================================================
-- DATOS
-- =========================================================================
local function Boards()
    if type(GuildControlDB.boards) ~= "table" then GuildControlDB.boards = {} end
    return GuildControlDB.boards
end

function boardModule.Get(key)
    local boards = Boards()
    local board = boards[key]
    if type(board) ~= "table" then
        board = { items = {}, at = 0 }
        boards[key] = board
    end
    if type(board.items) ~= "table" then board.items = {} end
    return board
end

local PushOp, EncodeItem   -- en vivo (se definen más abajo)
local listeners = {}
function boardModule.AddListener(fn) table.insert(listeners, fn) end
local function Notify(key) for _, fn in ipairs(listeners) do fn(key) end end

local function Touch(key)
    local board = boardModule.Get(key)
    board.at = GetServerTime()
    board.from = nil
    Notify(key)
end

local function CountPoints(board)
    local total = 0
    for _, item in ipairs(board.items) do
        if item.k == "s" and type(item.p) == "string" then
            local _, commas = string.gsub(item.p, ",", "")
            total = total + (commas + 1) / 2
        end
    end
    return total
end

function boardModule.AddItem(key, item)
    local board = boardModule.Get(key)
    if #board.items >= MAX_ITEMS then
        PrintGC(L["|cFFFF3333La pizarra está llena: borra algo antes de añadir más.|r"])
        return false
    end
    table.insert(board.items, item)
    local op = EncodeItem(item)
    if op then PushOp(key, op) end
    Touch(key)
    return true
end

function boardModule.RemoveItem(key, index)
    local board = boardModule.Get(key)
    if not board.items[index] then return end
    table.remove(board.items, index)
    PushOp(key, "R," .. index)
    Touch(key)
end

function boardModule.Undo(key)
    local board = boardModule.Get(key)
    if #board.items == 0 then return end
    PushOp(key, "R," .. #board.items)
    table.remove(board.items)
    Touch(key)
end

function boardModule.Clear(key)
    local board = boardModule.Get(key)
    wipe(board.items)
    PushOp(key, "C")
    Touch(key)
end

function boardModule.Changed(key) Touch(key) end

function boardModule.CanAddPoints(key, count)
    return CountPoints(boardModule.Get(key)) + count <= MAX_POINTS
end

-- Bandas y jefes para elegir (los de Roster, sacados del diario de encuentros)
function boardModule.GetRaids()
    local R = addonTable.Roster
    local tiers = R and R.GetRaidTiers and R.GetRaidTiers() or {}
    return tiers[1] and tiers[1].raids or {}
end

function boardModule.GetBosses(raidId)
    local R = addonTable.Roster
    return R and R.GetRaidBosses and R.GetRaidBosses(raidId) or {}
end

-- =========================================================================
-- ENVÍO AL GRUPO
-- =========================================================================
local function GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

local function IsOfficer()
    return addonTable.Profiles and addonTable.Profiles.IsOfficer and addonTable.Profiles.IsOfficer() or false
end

-- Pueden enseñar la pizarra el líder, los ayudantes y los oficiales
function boardModule.CanShow()
    if not GroupChannel() then return false end
    return UnitIsGroupLeader("player") or (IsInRaid() and UnitIsGroupAssistant("player")) or IsOfficer()
end

-- Cola de envío en orden. Si el juego frena los mensajes (límite por prefijo), el mensaje se
-- queda y se reintenta en el siguiente turno.
local sendQueue, sendTicker = {}, nil
local function ProcessQueue()
    local item = sendQueue[1]
    if not item then
        if sendTicker then sendTicker:Cancel() end
        sendTicker = nil
        return
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.msg, item.channel)
    local sent = ok and (result == nil or result == true or result == 0
        or (Enum and Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.Success))
    item.tries = (item.tries or 0) + 1
    if sent or item.tries > 40 then table.remove(sendQueue, 1) end
end

local function Queue(msg, channel)
    table.insert(sendQueue, { channel = channel, msg = msg })
    if not sendTicker then sendTicker = C_Timer.NewTicker(SEND_INTERVAL, ProcessQueue) end
end

-- =========================================================================
-- EN VIVO
-- =========================================================================
-- Quien enseña la pizarra puede ponerla en vivo: primero manda la pizarra entera y después
-- cada cambio (cada medio segundo se juntan en un mensaje). Los demás la ven moverse y no
-- pueden tocarla mientras dura. Si a alguien le falta un mensaje, pide la pizarra entera.
--   "O<n>;op~op~..."   cambios (n = número de envío): "A,m,x,y,v" "A,r,x,y,v" "A,t,x,y,texto"
--                      "A,s,color,x,y" (añadir), "P,i,x,y,x,y..." (puntos al trazo i),
--                      "R,i" (quitar), "M,i,x,y" (mover), "C" (limpiar)
--   "E"                fin del directo        "G"   alguien pide la pizarra entera
local live = { key = nil, seq = 0, ops = {}, flushTimer = nil, lastResync = 0 }
local watching = nil   -- { sender, short, key, seq } cuando veo el directo de otro

function boardModule.IsLive() return live.key ~= nil end
function boardModule.GetWatching() return watching end

local function FlushOps()
    live.flushTimer = nil
    if not live.key or #live.ops == 0 then return end
    local channel = GroupChannel()
    if not channel then wipe(live.ops); return end
    -- Mensajes de 240 bytes como mucho: si no caben, se reparten en varios
    local batch, size = {}, 0
    local function Send()
        if #batch == 0 then return end
        live.seq = live.seq + 1
        Queue("O" .. live.seq .. ";" .. table.concat(batch, "~"), channel)
        batch, size = {}, 0
    end
    for _, op in ipairs(live.ops) do
        if size + #op + 1 > 230 then Send() end
        table.insert(batch, op)
        size = size + #op + 1
    end
    Send()
    wipe(live.ops)
end

PushOp = function(key, op)
    if live.key ~= key then return end
    table.insert(live.ops, op)
    if not live.flushTimer then live.flushTimer = C_Timer.NewTimer(0.5, FlushOps) end
end

EncodeItem = function(item)
    if item.k == "m" or item.k == "r" then return "A," .. item.k .. "," .. item.x .. "," .. item.y .. "," .. item.v end
    if item.k == "t" then return "A,t," .. item.x .. "," .. item.y .. "," .. string.gsub(item.v, "[~;|]", "") end
    if item.k == "s" then return "A,s," .. item.c .. "," .. item.p end
end

-- Para la ventana: avisar de un cambio en vivo (mover y puntos nuevos de un trazo)
function boardModule.LiveMove(key, index, x, y) PushOp(key, "M," .. index .. "," .. x .. "," .. y) end
function boardModule.LivePoints(key, index, points) PushOp(key, "P," .. index .. "," .. points) end

function boardModule.ShowToGroup(key, title)
    local channel = GroupChannel()
    if not channel then
        PrintGC(L["|cFFFF3333No estás en un grupo.|r"])
        return false
    end
    if not boardModule.CanShow() then
        PrintGC(L["|cFFFF3333Solo el líder, un ayudante o un oficial pueden enseñar la pizarra.|r"])
        return false
    end
    local R = addonTable.Roster
    if not (R and R.SerializeTable) then return false end
    -- Los cambios pendientes van antes: así la pizarra entera llega ya con ellos
    if live.key then
        if live.flushTimer then live.flushTimer:Cancel() end
        FlushOps()
    end
    local isLive = live.key == key
    local data = R.SerializeTable({ key = key, title = title, items = boardModule.Get(key).items,
        live = isLive or nil, seq = isLive and live.seq or nil })
    -- Una pizarra entera nueva sustituye a la que estuviera a medio enviar
    for i = #sendQueue, 1, -1 do
        if string.sub(sendQueue[i].msg, 1, 1) == "D" then table.remove(sendQueue, i) end
    end
    local msgId = tostring(math.random(100000, 999999))
    local total = math.ceil(#data / CHUNK_BYTES)
    for i = 1, total do
        Queue("D" .. msgId .. ":" .. i .. ":" .. total .. ":" .. string.sub(data, (i - 1) * CHUNK_BYTES + 1, i * CHUNK_BYTES), channel)
    end
    if not isLive then PrintGC(string.format(L["Enseñando la pizarra a tu grupo (%d mensajes)."], total)) end
    return true
end

-- Empieza o termina el directo de la pizarra que tengo abierta
function boardModule.StartLive(key, title)
    if not boardModule.CanShow() then
        PrintGC(L["|cFFFF3333Solo el líder, un ayudante o un oficial pueden enseñar la pizarra.|r"])
        return false
    end
    live.key, live.seq = key, 0
    wipe(live.ops)
    boardModule.ShowToGroup(key, title)
    PrintGC(L["Pizarra |cFFFF3333en vivo|r: tu grupo ve cada cambio que hagas."])
    Notify(key)
    return true
end

function boardModule.StopLive()
    if not live.key then return end
    local key = live.key
    if live.flushTimer then live.flushTimer:Cancel() end
    FlushOps()
    live.key = nil
    local channel = GroupChannel()
    if channel then Queue("E", channel) end
    PrintGC(L["Fin del directo de la pizarra."])
    Notify(key)
end

-- Cambiar de jefe en vivo: el grupo pasa a ver la nueva pizarra
function boardModule.FollowLive(key, title)
    if not live.key or live.key == key then return end
    live.key = key
    wipe(live.ops)
    boardModule.ShowToGroup(key, title)
end

-- Limpieza de lo recibido: solo campos conocidos y dentro de los límites
local function Clamp(value)
    value = math.floor(tonumber(value) or 0)
    return math.max(0, math.min(1000, value))
end

local function SanitizeItems(items)
    local clean = {}
    if type(items) ~= "table" then return clean end
    for _, item in ipairs(items) do
        if #clean >= MAX_ITEMS then break end
        if type(item) == "table" then
            if item.k == "m" and tonumber(item.v) then
                table.insert(clean, { k = "m", x = Clamp(item.x), y = Clamp(item.y), v = math.max(1, math.min(8, math.floor(tonumber(item.v)))) })
            elseif item.k == "r" and (item.v == "tank" or item.v == "healer" or item.v == "dps") then
                table.insert(clean, { k = "r", x = Clamp(item.x), y = Clamp(item.y), v = item.v })
            elseif item.k == "t" and type(item.v) == "string" then
                table.insert(clean, { k = "t", x = Clamp(item.x), y = Clamp(item.y), v = string.sub(string.gsub(item.v, "|", ""), 1, 60) })
            elseif item.k == "s" and type(item.p) == "string" and string.match(item.p, "^[%d,]+$") then
                table.insert(clean, { k = "s", c = math.max(1, math.min(#boardModule.COLORS, math.floor(tonumber(item.c) or 1))), p = string.sub(item.p, 1, 12000) })
            end
        end
    end
    return clean
end

local function IsTrustedSender(sender)
    local fullName = addonTable.NormalizeName and addonTable.NormalizeName(sender) or sender
    if addonTable.Profiles and addonTable.Profiles.IsOfficerName and addonTable.Profiles.IsOfficerName(fullName) then return true end
    local short = string.match(sender, "^([^-]+)") or sender
    for _, unit in ipairs({ short, sender }) do
        if UnitExists(unit) and (UnitIsGroupLeader(unit) or (IsInRaid() and UnitIsGroupAssistant(unit))) then return true end
    end
    return false
end

local partials = {}
local function OnChunk(sender, msg)
    local msgId, index, total, chunk = string.match(msg, "^D(%d+):(%d+):(%d+):(.*)$")
    index, total = tonumber(index), tonumber(total)
    if not msgId or not index or not total or total > 600 then return end
    local key = sender .. ":" .. msgId
    local partial = partials[key] or { total = total, parts = {}, count = 0 }
    partials[key] = partial
    if not partial.parts[index] then
        partial.parts[index] = chunk
        partial.count = partial.count + 1
    end
    if partial.count < partial.total then return end
    partials[key] = nil
    if not IsTrustedSender(sender) then return end
    local R = addonTable.Roster
    local payload = R and R.DeserializeTable and R.DeserializeTable(table.concat(partial.parts))
    if type(payload) ~= "table" or type(payload.key) ~= "string" or #payload.key > 80 then return end
    local board = boardModule.Get(payload.key)
    board.items = SanitizeItems(payload.items)
    board.at = GetServerTime()
    board.from = string.match(sender, "^([^-]+)") or sender
    -- En vivo: a partir de aquí llegan solo los cambios
    local wasWatching = watching and watching.sender == sender and watching.key == payload.key
    if payload.live then
        watching = { sender = sender, short = board.from, key = payload.key, seq = tonumber(payload.seq) or 0 }
    elseif watching and watching.sender == sender then
        watching = nil
    end
    Notify(payload.key)
    if boardModule.Open then
        boardModule.Open(payload.key)
        if not wasWatching then
            PrintGC(string.format(payload.live and L["%s te enseña la pizarra en vivo: %s"] or L["%s te enseña la pizarra: %s"],
                board.from, type(payload.title) == "string" and string.sub(payload.title, 1, 60) or payload.key))
        end
    end
end

-- Aplica los cambios en vivo de quien enseña la pizarra
local lastResyncRequest = 0
local function OnOps(sender, msg)
    if not watching or watching.sender ~= sender then return end
    local seq, ops = string.match(msg, "^O(%d+);(.*)$")
    seq = tonumber(seq)
    if not seq or seq <= watching.seq then return end
    if seq ~= watching.seq + 1 then
        -- Falta algún cambio: se pide la pizarra entera (como mucho cada 5 s)
        if GetTime() - lastResyncRequest > 5 and GroupChannel() then
            lastResyncRequest = GetTime()
            pcall(C_ChatInfo.SendAddonMessage, PREFIX, "G", GroupChannel())
        end
        return
    end
    watching.seq = seq
    local items = boardModule.Get(watching.key).items
    for op in string.gmatch(ops, "[^~]+") do
        local kind = string.sub(op, 1, 1)
        if kind == "A" then
            local itemKind, rest = string.match(op, "^A,(%a),(.*)$")
            local clean
            if itemKind == "m" or itemKind == "r" then
                local x, y, v = string.match(rest or "", "^(%d+),(%d+),(%w+)$")
                clean = SanitizeItems({ { k = itemKind, x = x, y = y, v = itemKind == "m" and tonumber(v) or v } })[1]
            elseif itemKind == "t" then
                local x, y, text = string.match(rest or "", "^(%d+),(%d+),(.*)$")
                clean = SanitizeItems({ { k = "t", x = x, y = y, v = text } })[1]
            elseif itemKind == "s" then
                local c, points = string.match(rest or "", "^(%d+),([%d,]+)$")
                clean = SanitizeItems({ { k = "s", c = c, p = points } })[1]
            end
            if clean and #items < MAX_ITEMS then table.insert(items, clean) end
        elseif kind == "P" then
            local index, points = string.match(op, "^P,(%d+),([%d,]+)$")
            local item = items[tonumber(index) or 0]
            if item and item.k == "s" and #item.p < 12000 then item.p = item.p .. "," .. points end
        elseif kind == "R" then
            local index = tonumber(string.match(op, "^R,(%d+)$"))
            if index and items[index] then table.remove(items, index) end
        elseif kind == "M" then
            local index, x, y = string.match(op, "^M,(%d+),(%d+),(%d+)$")
            local item = items[tonumber(index) or 0]
            if item and item.k ~= "s" then item.x, item.y = Clamp(x), Clamp(y) end
        elseif kind == "C" then
            wipe(items)
        end
    end
    Notify(watching.key)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event, prefix, msg, channel, sender)
    if event == "GROUP_ROSTER_UPDATE" then
        -- Sin grupo no hay directo
        if not GroupChannel() then
            if live.key then local key = live.key; live.key = nil; Notify(key) end
            if watching then local key = watching.key; watching = nil; Notify(key) end
        end
        return
    end
    if prefix ~= PREFIX or type(msg) ~= "string" or not sender or not GuildControlDB then return end
    if channel ~= "RAID" and channel ~= "PARTY" and channel ~= "INSTANCE_CHAT" then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    if addonTable.IsMe and addonTable.IsMe(sender) then return end
    local kind = string.sub(msg, 1, 1)
    if kind == "D" then
        OnChunk(sender, msg)
    elseif kind == "O" then
        OnOps(sender, msg)
    elseif msg == "E" then
        if watching and watching.sender == sender then
            local key = watching.key
            watching = nil
            PrintGC(string.format(L["%s ha terminado el directo de la pizarra."], string.match(sender, "^([^-]+)") or sender))
            Notify(key)
        end
    elseif msg == "G" then
        -- A alguien le falta un cambio: se manda la pizarra entera (como mucho cada 3 s)
        if live.key and GetTime() - live.lastResync > 3 then
            live.lastResync = GetTime()
            boardModule.ShowToGroup(live.key, nil)
        end
    end
end)

-- =========================================================================
-- VENTANA
-- =========================================================================
local boardFrame = nil
local currentKey = "free"
local tool, toolValue, penColor = "move", nil, 2

local function KeyTitle(key)
    if key == "free" then return L["Pizarra libre"] end
    local raidId, boss = string.match(key, "^(%d+):(.+)$")
    for _, raid in ipairs(boardModule.GetRaids()) do
        if tostring(raid.id) == raidId then return raid.name .. " · " .. (boss or "") end
    end
    return boss or key
end

-- Posición del ratón en el lienzo, de 0 a 1000
local function CursorOnCanvas(canvas)
    local x, y = GetCursorPosition()
    local scale = canvas:GetEffectiveScale()
    x, y = x / scale, y / scale
    local left, top = canvas:GetLeft(), canvas:GetTop()
    if not left or not top then return nil end
    local nx = (x - left) / canvas:GetWidth() * 1000
    local ny = (top - y) / canvas:GetHeight() * 1000
    if nx < 0 or nx > 1000 or ny < 0 or ny > 1000 then return nil end
    return math.floor(nx), math.floor(ny)
end

local function ToPixels(nx, ny)
    return nx / 1000 * CANVAS_W, -(ny / 1000 * CANVAS_H)
end

-- Elemento (marca, rol o texto) más cercano a un punto; los trazos se buscan por sus puntos
local function FindItemAt(items, nx, ny)
    local best, bestDist = nil, 45 * 45
    for index, item in ipairs(items) do
        if item.k == "s" then
            for px, py in string.gmatch(item.p, "(%d+),(%d+)") do
                local dx, dy = tonumber(px) - nx, tonumber(py) - ny
                local dist = dx * dx + dy * dy
                if dist < bestDist then best, bestDist = index, dist end
            end
        else
            local dx, dy = item.x - nx, item.y - ny
            local dist = dx * dx + dy * dy
            if dist < bestDist then best, bestDist = index, dist end
        end
    end
    return best
end

local function Render()
    if not boardFrame or not boardFrame:IsShown() then return end
    local canvas = boardFrame.canvas
    local board = boardModule.Get(currentKey)
    for _, widget in ipairs(canvas.icons) do widget:Hide() end
    for _, widget in ipairs(canvas.texts) do widget:Hide() end
    for _, widget in ipairs(canvas.lines) do widget:Hide() end
    local nIcon, nText, nLine = 0, 0, 0
    for _, item in ipairs(board.items) do
        if item.k == "m" or item.k == "r" then
            nIcon = nIcon + 1
            local tex = canvas.icons[nIcon]
            if not tex then
                tex = canvas:CreateTexture(nil, "OVERLAY")
                tex:SetSize(28, 28)
                canvas.icons[nIcon] = tex
            end
            if item.k == "m" then
                tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. item.v)
                tex:SetTexCoord(0, 1, 0, 1)
            else
                tex:SetAtlas("roleicon-tiny-" .. item.v)
            end
            local px, py = ToPixels(item.x, item.y)
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", canvas, "TOPLEFT", px, py)
            tex:Show()
        elseif item.k == "t" then
            nText = nText + 1
            local fs = canvas.texts[nText]
            if not fs then
                fs = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
                canvas.texts[nText] = fs
            end
            local px, py = ToPixels(item.x, item.y)
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", canvas, "TOPLEFT", px, py)
            fs:SetText(item.v)
            fs:Show()
        elseif item.k == "s" then
            local color = boardModule.COLORS[item.c] or boardModule.COLORS[1]
            local lastX, lastY
            for px, py in string.gmatch(item.p, "(%d+),(%d+)") do
                local x, y = ToPixels(tonumber(px), tonumber(py))
                if lastX then
                    nLine = nLine + 1
                    local line = canvas.lines[nLine]
                    if not line then
                        line = canvas:CreateLine(nil, "ARTWORK")
                        line:SetThickness(3)
                        canvas.lines[nLine] = line
                    end
                    line:SetColorTexture(color[1], color[2], color[3], 1)
                    line:SetStartPoint("TOPLEFT", canvas, lastX, lastY)
                    line:SetEndPoint("TOPLEFT", canvas, x, y)
                    line:Show()
                end
                lastX, lastY = x, y
            end
        end
    end
    local title = KeyTitle(currentKey)
    local viewing = watching and watching.key == currentKey
    local suffix = ""
    if viewing then
        suffix = " |cFFFF3333● " .. L["en vivo con "] .. watching.short .. "|r"
    elseif live.key == currentKey then
        suffix = " |cFFFF3333● " .. L["EN VIVO"] .. "|r"
    elseif board.from then
        suffix = " |cFF808080· " .. L["enviada por "] .. board.from .. "|r"
    end
    boardFrame.subtitle:SetText(title .. suffix)
    boardFrame.btnShow:SetEnabled(boardModule.CanShow())
    boardFrame.btnLive:SetEnabled(live.key ~= nil or boardModule.CanShow())
    boardFrame.btnLive:SetText(live.key and L["|cFFFF3333Parar directo|r"] or L["En vivo"])
    for name, btn in pairs(boardFrame.toolButtons) do
        btn:SetAlpha((name == tool .. ":" .. tostring(toolValue)) and 1 or 0.55)
    end
end

boardModule.AddListener(function(key) if key == currentKey then Render() end end)

StaticPopupDialogs["GUILDCONTROL_BOARD_TEXT"] = {
    text = "%s",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 60,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self)
        local box = self.EditBox or self.editBox
        if box then box:SetText(""); box:SetFocus() end
    end,
    OnAccept = function(self, data)
        local box = self.EditBox or self.editBox
        local text = box and strtrim(string.gsub(box:GetText() or "", "|", "")) or ""
        if text ~= "" and data then boardModule.AddItem(data.key, { k = "t", x = data.x, y = data.y, v = text }) end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["GUILDCONTROL_BOARD_TEXT"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

local function CreateWindow()
    local frame = CreateFrame("Frame", "GuildControlBoardFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(CANVAS_W + 120, CANVAS_H + 112)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "GuildControlBoardFrame")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
    title:SetText(L["Pizarra"])

    -- Barra de arriba: elegir banda y jefe, y enseñar al grupo
    local btnBoss = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnBoss:SetSize(200, 22)
    btnBoss:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -30)
    btnBoss:SetText(L["Elegir jefe"])
    btnBoss:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateButton(L["Pizarra libre"], function() boardModule.Open("free") end)
            for _, raid in ipairs(boardModule.GetRaids()) do
                local sub = root:CreateButton(raid.name)
                for _, boss in ipairs(boardModule.GetBosses(raid.id)) do
                    sub:CreateButton(boss, function() boardModule.Open(raid.id .. ":" .. boss) end)
                end
            end
        end)
    end)
    -- Banda y jefe en su propia línea, a todo el ancho, para que quepan los nombres largos
    frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -58)
    frame.subtitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -58)
    frame.subtitle:SetJustifyH("LEFT")
    frame.subtitle:SetWordWrap(false)

    frame.btnShow = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.btnShow:SetSize(130, 22)
    frame.btnShow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -30)
    frame.btnShow:SetText(L["Enseñar al grupo"])
    frame.btnShow:SetMotionScriptsWhileDisabled(true)
    frame.btnShow:SetScript("OnClick", function() boardModule.ShowToGroup(currentKey, KeyTitle(currentKey)) end)
    frame.btnShow:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Enseñar al grupo"], 1, 1, 1)
        GameTooltip:AddLine(L["Se abre a todos los del grupo con GuildControl. Puede hacerlo el líder, un ayudante o un oficial."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame.btnShow:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- En vivo: el grupo ve cada cambio mientras dure
    frame.btnLive = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.btnLive:SetSize(110, 22)
    frame.btnLive:SetPoint("RIGHT", frame.btnShow, "LEFT", -6, 0)
    frame.btnLive:SetMotionScriptsWhileDisabled(true)
    frame.btnLive:SetScript("OnClick", function()
        if live.key then boardModule.StopLive() else boardModule.StartLive(currentKey, KeyTitle(currentKey)) end
        Render()
    end)
    frame.btnLive:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["En vivo"], 1, 1, 1)
        GameTooltip:AddLine(L["Tu grupo ve la pizarra mientras dibujas, mueves o borras, y la sigue si cambias de jefe. Mientras dura, ellos no pueden tocarla."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame.btnLive:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Lienzo: fondo oscuro con cuadrícula
    local canvas = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    canvas:SetSize(CANVAS_W, CANVAS_H)
    canvas:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -82)
    canvas:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    canvas:SetBackdropColor(0.06, 0.07, 0.09, 0.95)
    canvas:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    canvas:SetClipsChildren(true)
    for i = 1, 15 do
        local v = canvas:CreateTexture(nil, "BACKGROUND", nil, 1)
        v:SetColorTexture(1, 1, 1, 0.04)
        v:SetSize(1, CANVAS_H)
        v:SetPoint("TOPLEFT", canvas, "TOPLEFT", i * CANVAS_W / 16, 0)
    end
    for i = 1, 10 do
        local h = canvas:CreateTexture(nil, "BACKGROUND", nil, 1)
        h:SetColorTexture(1, 1, 1, 0.04)
        h:SetSize(CANVAS_W, 1)
        h:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -i * CANVAS_H / 11)
    end
    canvas.icons, canvas.texts, canvas.lines = {}, {}, {}
    frame.canvas = canvas

    -- Ratón: según la herramienta se pone, se mueve, se dibuja o se borra
    local drag = nil   -- { index } al mover; { item, points, lastX, lastY } al dibujar
    canvas:EnableMouse(true)
    canvas:SetScript("OnMouseDown", function(self, button)
        local nx, ny = CursorOnCanvas(self)
        if not nx then return end
        -- Viendo el directo de otro no se puede tocar (se perdería con su siguiente cambio)
        if watching and watching.key == currentKey then
            PrintGC(string.format(L["Estás viendo la pizarra en vivo de %s: no se puede cambiar mientras dura."], watching.short))
            return
        end
        local board = boardModule.Get(currentKey)
        if button == "RightButton" or tool == "erase" then
            local index = FindItemAt(board.items, nx, ny)
            if index then boardModule.RemoveItem(currentKey, index) end
        elseif tool == "move" then
            local index = FindItemAt(board.items, nx, ny)
            if index and board.items[index].k ~= "s" then drag = { index = index } end
        elseif tool == "mark" or tool == "role" then
            boardModule.AddItem(currentKey, { k = tool == "mark" and "m" or "r", x = nx, y = ny, v = toolValue })
        elseif tool == "text" then
            local popup = StaticPopup_Show("GUILDCONTROL_BOARD_TEXT", L["Texto para la pizarra:"])
            if popup then popup.data = { key = currentKey, x = nx, y = ny } end
        elseif tool == "pen" then
            if not boardModule.CanAddPoints(currentKey, 2) then
                PrintGC(L["|cFFFF3333La pizarra está llena: borra algo antes de añadir más.|r"])
                return
            end
            local item = { k = "s", c = penColor, p = nx .. "," .. ny }
            if boardModule.AddItem(currentKey, item) then
                drag = { item = item, itemIndex = #board.items, count = 1, lastX = nx, lastY = ny }
            end
        end
    end)
    -- Al soltar: se guarda y, en vivo, se manda la posición final de lo que se movía
    local function EndDrag()
        if not drag then return end
        if drag.index then
            local item = boardModule.Get(currentKey).items[drag.index]
            if item then boardModule.LiveMove(currentKey, drag.index, item.x, item.y) end
        end
        boardModule.Changed(currentKey)
        drag = nil
    end
    canvas:SetScript("OnMouseUp", EndDrag)
    canvas:SetScript("OnUpdate", function(self)
        if not drag then return end
        if not IsMouseButtonDown("LeftButton") then
            EndDrag()
            return
        end
        local nx, ny = CursorOnCanvas(self)
        if not nx then return end
        if drag.index then
            local item = boardModule.Get(currentKey).items[drag.index]
            if item and (item.x ~= nx or item.y ~= ny) then
                item.x, item.y = nx, ny
                Render()
                -- En vivo, la posición se manda como mucho cada 0,2 s
                if GetTime() - (drag.lastSent or 0) > 0.2 then
                    drag.lastSent = GetTime()
                    boardModule.LiveMove(currentKey, drag.index, nx, ny)
                end
            end
        elseif drag.item then
            -- Un punto nuevo cada pocos píxeles: trazos suaves sin miles de puntos
            local dx, dy = nx - drag.lastX, ny - drag.lastY
            if dx * dx + dy * dy >= 144 and boardModule.CanAddPoints(currentKey, 1) then
                drag.item.p = drag.item.p .. "," .. nx .. "," .. ny
                drag.lastX, drag.lastY = nx, ny
                boardModule.LivePoints(currentKey, drag.itemIndex, nx .. "," .. ny)
                Render()
            end
        end
    end)

    -- Herramientas (columna de la izquierda)
    frame.toolButtons = {}
    local y = -84
    local function ToolButton(name, value, texture, atlas, tooltip, col)
        local btn = CreateFrame("Button", nil, frame)
        btn:SetSize(26, 26)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 14 + (col or 0) * 30, y)
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        if atlas then tex:SetAtlas(atlas) else tex:SetTexture(texture) end
        btn.tex = tex
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        btn:SetScript("OnClick", function()
            tool, toolValue = name, value
            if name == "pen" and value then penColor = value end
            Render()
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame.toolButtons[name .. ":" .. tostring(value)] = btn
        return btn
    end
    ToolButton("move", nil, "Interface\\CURSOR\\UI-Cursor-Move", nil, L["Mover (arrastra marcas, roles y textos)"], 0)
    ToolButton("erase", nil, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", nil, L["Borrar (clic en lo que quieras quitar; también con clic derecho)"], 1)
    ToolButton("text", nil, "Interface\\Icons\\INV_Inscription_Parchment", nil, L["Texto"], 2)
    y = y - 34
    for i = 1, 8 do
        ToolButton("mark", i, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i, nil, L["Marca de banda"], (i - 1) % 3)
        if i % 3 == 0 then y = y - 30 end
    end
    y = y - 34
    ToolButton("role", "tank", nil, "roleicon-tiny-tank", L["Tanque"], 0)
    ToolButton("role", "healer", nil, "roleicon-tiny-healer", L["Sanador"], 1)
    ToolButton("role", "dps", nil, "roleicon-tiny-dps", "DPS", 2)
    y = y - 40
    local penLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    penLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
    penLabel:SetText(L["Lápiz"])
    y = y - 16
    for i, color in ipairs(boardModule.COLORS) do
        local btn = ToolButton("pen", i, "Interface\\Buttons\\WHITE8X8", nil, L["Dibujar a mano alzada"], (i - 1) % 3)
        btn.tex:SetVertexColor(color[1], color[2], color[3])
        if i % 3 == 0 then y = y - 30 end
    end
    y = y - 40

    local function ActionButton(text, onClick)
        local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btn:SetSize(90, 22)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y)
        btn:SetText(text)
        btn:SetScript("OnClick", onClick)
        y = y - 26
        return btn
    end
    ActionButton(L["Deshacer"], function() boardModule.Undo(currentKey) end)
    local clearArmed = 0
    local btnClear
    btnClear = ActionButton(L["Limpiar"], function()
        if GetTime() < clearArmed then
            clearArmed = 0
            btnClear:SetText(L["Limpiar"])
            boardModule.Clear(currentKey)
        else
            clearArmed = GetTime() + 4
            btnClear:SetText(L["|cFFFF3333¿Seguro?|r"])
            C_Timer.After(4, function() if GetTime() >= clearArmed then btnClear:SetText(L["Limpiar"]) end end)
        end
    end)

    frame:SetScript("OnShow", Render)
    return frame
end

function boardModule.Open(key)
    if not GuildControlDB then return end
    if not boardFrame then boardFrame = CreateWindow() end
    currentKey = key or currentKey
    -- En vivo, si cambio de jefe el grupo pasa a ver ese
    if live.key and live.key ~= currentKey then boardModule.FollowLive(currentKey, KeyTitle(currentKey)) end
    boardFrame:Show()
    boardFrame:Raise()
    Render()
end

function boardModule.Toggle()
    if boardFrame and boardFrame:IsShown() then
        boardFrame:Hide()
    else
        boardModule.Open()
    end
end
