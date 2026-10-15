local addonName, addonTable = ...
local L = addonTable.L

addonTable.RaidEvents = {}
local eventsModule = addonTable.RaidEvents

-- Eventos de banda al estilo de Raid-Helper (sin frames): los oficiales crean la banda y
-- los jugadores se apuntan con su rol y estado. Todo se sincroniza por mensajes de addon.
--
-- GuildControlDB.raidEvents[id] = {
--   id, title, raidId, raidName, difficulty, size, date = "AAAA-MM-DD", time = "HH:MM",
--   description, rosterName, createdBy, updatedAt,
--   signups = { [Nombre-Reino] = { status, role, spec, note, at } },
--   groups = { [Nombre-Reino] = 1..8 }, groupsAt
-- }
--
-- Mensajes (prefijo GuildControlEvt, canal GUILD):
--   D<msgId>:<i>:<total>:<datos>  evento completo troceado (solo de oficiales)
--   S;id;estado;rol;espec;nota;fecha  inscripción propia (de cualquiera, para sí mismo)
--   O;id;nombre;estado;rol;espec;fecha  inscripción cambiada por un oficial ("removed" = quitar)
--   X;id  evento eliminado (oficial)    Q  petición de eventos (al entrar)

local PREFIX = "GuildControlEvt"
local CHUNK_BYTES = 200
local SEND_INTERVAL = 0.3
local KEEP_PAST_DAYS = 14

eventsModule.STATUSES = {
    { key = "signed",    label = "Apuntado" },
    { key = "late",      label = "Tarde" },
    { key = "tentative", label = "Tentativo" },
    { key = "bench",     label = "Banca" },
    { key = "absent",    label = "Ausente" },
}
local STATUS_LABELS = {}
for _, s in ipairs(eventsModule.STATUSES) do STATUS_LABELS[s.key] = s.label end
eventsModule.STATUS_LABELS = STATUS_LABELS
eventsModule.STATUS_COLORS = { signed = "00FF00", late = "FFD100", tentative = "66B3FF", bench = "BFBFBF", absent = "FF3333" }
local VALID_ROLES = { tank = true, healer = true, dps = true }
local VALID_DIFFICULTY = { normal = true, heroic = true, mythic = true }

local listeners = {}

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

-- =========================================================================
-- UTILIDADES
-- =========================================================================
local function Store()
    if type(GuildControlDB.raidEvents) ~= "table" then GuildControlDB.raidEvents = {} end
    return GuildControlDB.raidEvents
end

local function Notify()
    for _, fn in ipairs(listeners) do fn() end
end

function eventsModule.AddListener(fn)
    table.insert(listeners, fn)
end

local function NormalizeName(name)
    if addonTable.Profiles and addonTable.Profiles.NormalizeName then return addonTable.Profiles.NormalizeName(name) end
    return name
end

local function MyName()
    return NormalizeName(UnitName("player"))
end

local function IsOfficer()
    return not addonTable.Profiles or addonTable.Profiles.IsOfficer()
end

local function IsOfficerName(name)
    return addonTable.Profiles and addonTable.Profiles.IsOfficerName(name)
end

local function Clean(text, maxLen)
    text = strtrim(tostring(text or ""))
    text = string.gsub(text, "[|;]", "")
    return string.sub(text, 1, maxLen)
end

local function SendRaw(msg)
    if IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD")
    end
end

-- =========================================================================
-- EVENTOS: CREAR, EDITAR, BORRAR Y LISTAR
-- =========================================================================
-- Próximas bandas (y las de ayer), más próximas primero
function eventsModule.GetUpcoming()
    local list = {}
    local yesterday = date("%Y-%m-%d", time() - 86400)
    local limit = date("%Y-%m-%d", time() - KEEP_PAST_DAYS * 86400)
    local store = Store()
    for id, event in pairs(store) do
        if event.date < limit then
            store[id] = nil           -- se olvidan las bandas de hace más de dos semanas
        elseif event.date >= yesterday then
            table.insert(list, event)
        end
    end
    table.sort(list, function(a, b) return (a.date .. a.time) < (b.date .. b.time) end)
    return list
end

function eventsModule.Get(id)
    return id and Store()[id] or nil
end

-- fields: title, raidId, raidName, difficulty, size, dateText, timeText, description, rosterName
local function ApplyFields(event, fields)
    local R = addonTable.Roster
    local dateValue, timeValue, err = R.ParseDateTime(fields.dateText, fields.timeText)
    if not dateValue then return nil, err end
    local title = Clean(fields.title, 40)
    if title == "" then title = fields.raidName and Clean(fields.raidName, 40) or L["Banda"] end
    event.title = title
    event.raidId = tonumber(fields.raidId)
    event.raidName = fields.raidName and Clean(fields.raidName, 40) or nil
    event.difficulty = VALID_DIFFICULTY[fields.difficulty] and fields.difficulty or "heroic"
    event.size = math.max(5, math.min(40, math.floor(tonumber(fields.size) or 20)))
    event.date, event.time = dateValue, timeValue
    event.description = Clean(fields.description, 160)
    event.rosterName = fields.rosterName and Clean(fields.rosterName, 30) or nil
    event.updatedAt = time()
    return event
end

function eventsModule.Create(fields)
    local event = { id = (UnitName("player") or "?") .. "-" .. time(), createdBy = UnitName("player"),
                    signups = {}, groups = {}, groupsAt = 0 }
    local ok, err = ApplyFields(event, fields)
    if not ok then return nil, err end
    Store()[event.id] = event
    eventsModule.Publish(event)
    Notify()
    return event
end

function eventsModule.Update(event, fields)
    local ok, err = ApplyFields(event, fields)
    if not ok then return nil, err end
    eventsModule.Publish(event)
    Notify()
    return event
end

function eventsModule.Delete(event)
    if not event then return end
    Store()[event.id] = nil
    SendRaw("X;" .. event.id)
    Notify()
end

-- =========================================================================
-- INSCRIPCIONES
-- =========================================================================
function eventsModule.GetMySignup(event)
    return event and event.signups[MyName()] or nil
end

-- Me apunto (o cambio mi respuesta) y lo envío a la hermandad
function eventsModule.SignUp(event, status, role, spec, note)
    if not event or not STATUS_LABELS[status] then return end
    local signup = {
        status = status,
        role = VALID_ROLES[role] and role or nil,
        spec = Clean(spec, 30),
        note = Clean(note, 60),
        at = time(),
    }
    event.signups[MyName()] = signup
    SendRaw(table.concat({ "S", event.id, signup.status, signup.role or "", signup.spec, signup.note, tostring(signup.at) }, ";"))
    Notify()
end

-- Un oficial cambia o quita la inscripción de otro (status = "removed" para quitarla)
function eventsModule.SetSignup(event, name, status, role)
    if not event or not name then return end
    local at = time()
    if status == "removed" then
        event.signups[name] = nil
        if event.groups then event.groups[name] = nil end
    else
        local current = event.signups[name] or {}
        event.signups[name] = { status = STATUS_LABELS[status] and status or (current.status or "signed"),
                                role = VALID_ROLES[role] and role or current.role, spec = current.spec or "",
                                note = current.note or "", at = at }
    end
    local s = event.signups[name]
    SendRaw(table.concat({ "O", event.id, name, status, (s and s.role) or "", (s and s.spec) or "", tostring(at) }, ";"))
    Notify()
end

-- { tank = {{name, signup}}, healer = {...}, dps = {...}, other = { [estado] = {...} } }
function eventsModule.GetSignupsByRole(event)
    local result = { tank = {}, healer = {}, dps = {}, other = {} }
    for name, signup in pairs(event.signups or {}) do
        local entry = { name = name, signup = signup }
        if (signup.status == "signed" or signup.status == "late") and VALID_ROLES[signup.role] then
            table.insert(result[signup.role], entry)
        else
            result.other[signup.status] = result.other[signup.status] or {}
            table.insert(result.other[signup.status], entry)
        end
    end
    local function ByTime(a, b) return (a.signup.at or 0) < (b.signup.at or 0) end
    for _, key in ipairs({ "tank", "healer", "dps" }) do table.sort(result[key], ByTime) end
    for _, list in pairs(result.other) do table.sort(list, ByTime) end
    return result
end

function eventsModule.CountSignups(event)
    local counts = { total = 0, tank = 0, healer = 0, dps = 0, signed = 0, late = 0, tentative = 0, bench = 0, absent = 0 }
    for _, signup in pairs(event.signups or {}) do
        counts[signup.status] = (counts[signup.status] or 0) + 1
        if signup.status == "signed" or signup.status == "late" then
            counts.total = counts.total + 1
            if signup.role then counts[signup.role] = (counts[signup.role] or 0) + 1 end
        end
    end
    return counts
end

-- =========================================================================
-- GRUPOS
-- =========================================================================
function eventsModule.SetGroup(event, name, group)
    if not event then return end
    event.groups = event.groups or {}
    event.groups[name] = group
    event.groupsAt = time()
    Notify()
end

function eventsModule.ClearGroups(event)
    if not event then return end
    event.groups = {}
    event.groupsAt = time()
    Notify()
end

-- Reparto automático: tanques al grupo 1, sanadores repartidos y el resto rellena huecos
function eventsModule.AutoGroups(event)
    if not event then return end
    local byRole = eventsModule.GetSignupsByRole(event)
    local groups, counts = {}, {}
    local numGroups = math.max(1, math.ceil(event.size / 5))
    for g = 1, 8 do counts[g] = 0 end
    local function Place(name, preferred)
        local order = {}
        if preferred then table.insert(order, preferred) end
        for g = 1, numGroups do table.insert(order, g) end
        for _, g in ipairs(order) do
            if counts[g] < 5 then
                groups[name] = g
                counts[g] = counts[g] + 1
                return
            end
        end
    end
    for _, entry in ipairs(byRole.tank) do Place(entry.name, 1) end
    for i, entry in ipairs(byRole.healer) do Place(entry.name, ((i - 1) % numGroups) + 1) end
    for _, entry in ipairs(byRole.dps) do Place(entry.name) end
    event.groups = groups
    event.groupsAt = time()
    Notify()
end

-- =========================================================================
-- SINCRONIZACIÓN
-- =========================================================================
local sendQueue, sendTicker = {}, nil

local function ProcessQueue()
    local msg = sendQueue[1]
    if not msg then
        if sendTicker then sendTicker:Cancel() end
        sendTicker = nil
        return
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
    local success = ok and (result == nil or result == true or result == 0
        or (Enum and Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.Success))
    if success then table.remove(sendQueue, 1) end
end

-- Envía el evento completo (con inscripciones y grupos). Solo lo aceptan si lo envía un oficial.
function eventsModule.Publish(event)
    if not event or not IsInGuild() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local R = addonTable.Roster
    local data = R.SerializeTable({ version = 1, event = event })
    local msgId = tostring(math.random(100000, 999999))
    local total = math.ceil(#data / CHUNK_BYTES)
    for i = 1, total do
        table.insert(sendQueue, "D" .. msgId .. ":" .. i .. ":" .. total .. ":" .. string.sub(data, (i - 1) * CHUNK_BYTES + 1, i * CHUNK_BYTES))
    end
    if not sendTicker then sendTicker = C_Timer.NewTicker(SEND_INTERVAL, ProcessQueue) end
end

local function SanitizeEvent(raw)
    if type(raw) ~= "table" or type(raw.id) ~= "string" then return nil end
    local R = addonTable.Roster
    local dateValue, timeValue = R.ParseDateTime(raw.date, raw.time)
    if not dateValue then return nil end
    local event = {
        id = string.sub(raw.id, 1, 60), title = Clean(raw.title, 40), raidId = tonumber(raw.raidId),
        raidName = raw.raidName and Clean(raw.raidName, 40) or nil,
        difficulty = VALID_DIFFICULTY[raw.difficulty] and raw.difficulty or "heroic",
        size = math.max(5, math.min(40, math.floor(tonumber(raw.size) or 20))),
        date = dateValue, time = timeValue, description = Clean(raw.description, 160),
        rosterName = raw.rosterName and Clean(raw.rosterName, 30) or nil,
        createdBy = Clean(raw.createdBy, 40), updatedAt = tonumber(raw.updatedAt) or 0,
        signups = {}, groups = {}, groupsAt = tonumber(raw.groupsAt) or 0,
    }
    for name, s in pairs(type(raw.signups) == "table" and raw.signups or {}) do
        if type(name) == "string" and type(s) == "table" and STATUS_LABELS[s.status] then
            event.signups[string.sub(name, 1, 60)] = { status = s.status, role = VALID_ROLES[s.role] and s.role or nil,
                spec = Clean(s.spec, 30), note = Clean(s.note, 60), at = tonumber(s.at) or 0 }
        end
    end
    for name, g in pairs(type(raw.groups) == "table" and raw.groups or {}) do
        g = tonumber(g)
        if type(name) == "string" and g and g >= 1 and g <= 8 then event.groups[string.sub(name, 1, 60)] = g end
    end
    return event
end

-- Combina un evento recibido con la copia local: datos del más reciente, inscripciones una a
-- una (gana la más reciente) y grupos del que se repartió más tarde
local function MergeEvent(incoming)
    local store = Store()
    local existing = store[incoming.id]
    if not existing then
        store[incoming.id] = incoming
        return
    end
    if incoming.updatedAt >= (existing.updatedAt or 0) then
        for _, key in ipairs({ "title", "raidId", "raidName", "difficulty", "size", "date", "time", "description", "rosterName", "createdBy", "updatedAt" }) do
            existing[key] = incoming[key]
        end
    end
    for name, signup in pairs(incoming.signups) do
        local current = existing.signups[name]
        if not current or (signup.at or 0) > (current.at or 0) then existing.signups[name] = signup end
    end
    if (incoming.groupsAt or 0) > (existing.groupsAt or 0) then
        existing.groups, existing.groupsAt = incoming.groups, incoming.groupsAt
    end
end

local partials = {}
local republishTimer = nil

local function OnChunk(sender, msg)
    local msgId, index, total, chunk = string.match(msg, "^D(%d+):(%d+):(%d+):(.*)$")
    index, total = tonumber(index), tonumber(total)
    if not msgId or not index or not total or total > 300 then return end
    -- Otro oficial ya está respondiendo a la petición de eventos
    if republishTimer then republishTimer:Cancel(); republishTimer = nil end

    local key = sender .. ":" .. msgId
    local partial = partials[key] or { total = total, parts = {}, count = 0, started = GetTime() }
    partials[key] = partial
    if not partial.parts[index] then
        partial.parts[index] = chunk
        partial.count = partial.count + 1
    end
    if partial.count < partial.total then return end
    partials[key] = nil

    if not IsOfficerName(sender) then return end   -- los eventos solo los publican oficiales
    local payload = addonTable.Roster.DeserializeTable(table.concat(partial.parts))
    local event = payload and payload.version == 1 and SanitizeEvent(payload.event)
    if event then
        local isNew = Store()[event.id] == nil
        MergeEvent(event)
        if isNew then
            print("|cFF00FFFF[GuildControl]|r " .. L["Nueva banda: "] .. "|cFFFFD100" .. event.title .. L["|r el "]
                .. string.gsub(event.date, "^(%d+)-(%d+)-(%d+)$", "%3/%2/%1") .. L[" a las "] .. event.time .. L[". Apúntate en Raid."])
        end
        Notify()
    end
end

local function ScheduleRepublish()
    if republishTimer or not IsOfficer() then return end
    local events = eventsModule.GetUpcoming()
    if #events == 0 then return end
    republishTimer = C_Timer.NewTimer(3 + math.random() * 5, function()
        republishTimer = nil
        for _, event in ipairs(events) do eventsModule.Publish(event) end
    end)
end

function eventsModule.RequestEvents()
    SendRaw("Q")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if not GuildControlDB then return end
    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin or isReloadingUi then C_Timer.After(16, eventsModule.RequestEvents) end
        return
    end

    local prefix, msg, channel, sender = ...
    if prefix ~= PREFIX or channel ~= "GUILD" then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    if not msg or not sender then return end
    local fullSender = NormalizeName(sender)
    if fullSender == MyName() then return end

    if msg == "Q" then
        ScheduleRepublish()
        -- Cada cliente reenvía sus propias inscripciones: así el oficial que acaba de entrar
        -- recibe las que se hicieron mientras no estaba
        C_Timer.After(1 + math.random() * 4, function()
            for _, ev in ipairs(eventsModule.GetUpcoming()) do
                local s = ev.signups[MyName()]
                if s then SendRaw(table.concat({ "S", ev.id, s.status, s.role or "", s.spec or "", s.note or "", tostring(s.at or 0) }, ";")) end
            end
        end)
    elseif string.sub(msg, 1, 1) == "D" then
        OnChunk(fullSender, msg)
    else
        local fields = { strsplit(";", msg) }
        local kind, eventId = fields[1], fields[2]
        local ev = eventsModule.Get(eventId)
        if kind == "S" and ev and STATUS_LABELS[fields[3]] then
            -- Inscripción del propio remitente
            local at = tonumber(fields[7]) or time()
            local current = ev.signups[fullSender]
            if not current or at >= (current.at or 0) then
                ev.signups[fullSender] = { status = fields[3], role = VALID_ROLES[fields[4]] and fields[4] or nil,
                                           spec = Clean(fields[5], 30), note = Clean(fields[6], 60), at = at }
                Notify()
            end
        elseif kind == "O" and ev and IsOfficerName(fullSender) and fields[3] then
            local name, status, at = fields[3], fields[4], tonumber(fields[7]) or time()
            local current = ev.signups[name]
            if status == "removed" then
                if current and at >= (current.at or 0) then ev.signups[name] = nil end
            elseif STATUS_LABELS[status] and (not current or at >= (current.at or 0)) then
                ev.signups[name] = { status = status, role = VALID_ROLES[fields[5]] and fields[5] or nil,
                                     spec = Clean(fields[6], 30), note = current and current.note or "", at = at }
            end
            Notify()
        elseif kind == "X" and ev and IsOfficerName(fullSender) then
            Store()[eventId] = nil
            Notify()
        end
    end
end)
