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
-- Asistencia (la pasan los oficiales): GuildControlDB.raidAttendance[id] = {
--   date, time, title, rosterName, raidId, raidName, difficulty, at,
--   marks = { [Nombre-Reino] = "present"|"late"|"absent"|"excused" },
--   bosses = { [encounterID] = { name, at } } }   (jefes que murieron en la banda; ver más abajo)
-- Se guarda aparte porque las bandas se borran a los 14 días y los porcentajes deben seguir.
-- Viaja junto al evento cuando un oficial lo publica.
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

-- Rol de una inscripción según la clase: uno que la clase no puede llevar pasa a DPS
local function RoleForClass(name, role)
    if not VALID_ROLES[role] then return nil end
    if addonTable.CanRole and not addonTable.CanRole(name, role) then return "dps" end
    return role
end

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

-- Todas las bandas guardadas (las próximas y las de los últimos 14 días), más recientes primero
function eventsModule.GetRecent()
    eventsModule.GetUpcoming()        -- de paso olvida las antiguas
    local list = {}
    for _, event in pairs(Store()) do table.insert(list, event) end
    table.sort(list, function(a, b) return (a.date .. a.time) > (b.date .. b.time) end)
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
    -- Un cazador no puede apuntarse de tanque ni un guerrero de sanador
    if VALID_ROLES[role] and addonTable.CanRole and not addonTable.CanRole(MyName(), role) then
        if addonTable.WarnClassRole then addonTable.WarnClassRole(MyName(), role) end
        return
    end
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
    -- Tampoco un oficial puede poner un rol que su clase no lleva
    if VALID_ROLES[role] and addonTable.CanRole and not addonTable.CanRole(name, role) then
        if addonTable.WarnClassRole then addonTable.WarnClassRole(name, role) end
        return
    end
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
-- ASISTENCIA
-- =========================================================================
eventsModule.ATTENDANCE = { "present", "late", "absent", "excused" }
eventsModule.ATTENDANCE_LABELS = { present = "Presente", late = "Tarde", absent = "Ausente", excused = "Justif." }
eventsModule.ATTENDANCE_COLORS = { present = "00FF00", late = "FFD100", absent = "FF3333", excused = "66B3FF" }
local VALID_ATTENDANCE = { present = true, late = true, absent = true, excused = true }

local function AttendanceStore()
    if type(GuildControlDB.raidAttendance) ~= "table" then GuildControlDB.raidAttendance = {} end
    return GuildControlDB.raidAttendance
end

-- Registro de asistencia de una banda (create = true lo crea al pasar lista)
local function Record(event, create)
    local store = AttendanceStore()
    local rec = store[event.id]
    if not rec and create then
        rec = { marks = {}, bosses = {}, at = 0 }
        store[event.id] = rec
    end
    if rec then
        rec.date, rec.time, rec.title, rec.rosterName = event.date, event.time, event.title, event.rosterName
        rec.raidId, rec.raidName, rec.difficulty = event.raidId, event.raidName, event.difficulty
        if type(rec.bosses) ~= "table" then rec.bosses = {} end
    end
    return rec
end

function eventsModule.GetMarks(event)
    local rec = event and AttendanceStore()[event.id]
    return rec and rec.marks or {}
end

-- La asistencia se publica sola unos segundos después del último cambio
local attendancePublishTimer = nil
local function AttendanceChanged(event)
    local rec = Record(event, true)
    rec.at = time()
    if attendancePublishTimer then attendancePublishTimer:Cancel() end
    attendancePublishTimer = C_Timer.NewTimer(5, function()
        attendancePublishTimer = nil
        eventsModule.Publish(event)
    end)
    Notify()
end

-- Un segundo clic en la misma marca la quita
function eventsModule.SetAttendance(event, fullName, status)
    if not event or not fullName or not VALID_ATTENDANCE[status] then return end
    local marks = Record(event, true).marks
    if marks[fullName] == status then marks[fullName] = nil else marks[fullName] = status end
    AttendanceChanged(event)
end

function eventsModule.ClearAttendance(event)
    if not event then return end
    wipe(Record(event, true).marks)
    AttendanceChanged(event)
end

function eventsModule.GetAttendanceCounts(event)
    local counts = { present = 0, late = 0, absent = 0, excused = 0 }
    for _, status in pairs(eventsModule.GetMarks(event)) do
        if counts[status] then counts[status] = counts[status] + 1 end
    end
    return counts
end

local function FindRoster(name)
    if not name or not addonTable.Roster then return nil end
    for _, roster in ipairs(addonTable.Roster.GetAll()) do
        if roster.name == name then return roster end
    end
    return nil
end

-- Hoja de una banda: inscritos, integrantes del roster asociado y quien ya tenga marca.
-- { {name, signup, slot}, ... } ordenada por rol
function eventsModule.GetAttendanceList(event)
    local list, seen = {}, {}
    local roster = FindRoster(event.rosterName)
    local function Add(name)
        if seen[name] then return end
        seen[name] = true
        table.insert(list, { name = name, signup = event.signups[name], slot = roster and roster.members[name] or nil })
    end
    for name in pairs(event.signups or {}) do Add(name) end
    if roster then for name in pairs(roster.members) do Add(name) end end
    for name in pairs(eventsModule.GetMarks(event)) do Add(name) end
    local order = { tank = 1, healer = 2, dps = 3, bench = 4 }
    local function Order(entry)
        local role = (entry.signup and entry.signup.role) or entry.slot
        return order[role or ""] or 5
    end
    table.sort(list, function(a, b)
        local oa, ob = Order(a), Order(b)
        if oa ~= ob then return oa < ob end
        return a.name < b.name
    end)
    return list
end

-- Nombres (Nombre-Reino) de quienes están ahora en mi grupo o banda
local function CurrentGroupNames()
    local names = {}
    local me = MyName()
    if me then names[me] = true end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local n = NormalizeName((GetRaidRosterInfo(i)))
            if n then names[n] = true end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local name, realm = UnitName("party" .. i)
            local n = name and NormalizeName((realm and realm ~= "") and (name .. "-" .. realm) or name)
            if n then names[n] = true end
        end
    end
    return names
end

-- Pasa lista según el grupo actual: en el grupo = presente (o tarde si avisó); quien avisó de
-- que faltaba = justificado; el resto de inscritos y titulares del roster = ausente. La banca
-- y los suplentes solo se marcan si están en el grupo. Devuelve cuántos están presentes.
function eventsModule.TakeAttendanceFromGroup(event)
    if not event then return 0 end
    local inGroup = CurrentGroupNames()
    local marks = Record(event, true).marks
    local present = 0
    for _, entry in ipairs(eventsModule.GetAttendanceList(event)) do
        local status = entry.signup and entry.signup.status
        if inGroup[entry.name] then
            marks[entry.name] = (status == "late") and "late" or "present"
            present = present + 1
        elseif status == "absent" then
            if marks[entry.name] ~= "absent" then marks[entry.name] = "excused" end
        elseif status ~= "bench" and entry.slot ~= "bench" and marks[entry.name] ~= "excused" then
            marks[entry.name] = "absent"
        end
    end
    AttendanceChanged(event)
    return present
end

-- Marca como presentes a los apuntados (y como tarde a los que avisaron de que llegaban tarde)
function eventsModule.MarkSignedPresent(event)
    if not event then return end
    local marks = Record(event, true).marks
    for name, s in pairs(event.signups or {}) do
        if s.status == "signed" then marks[name] = "present"
        elseif s.status == "late" then marks[name] = "late" end
    end
    AttendanceChanged(event)
end

-- Asistencia de un jugador en las bandas de un roster (rosterName nil = todas).
-- percent = (presente + tarde) / (presente + tarde + ausente); las justificadas no cuentan.
function eventsModule.GetAttendanceStats(rosterName, fullName)
    local stats = { present = 0, late = 0, absent = 0, excused = 0 }
    for _, rec in pairs(AttendanceStore()) do
        if not rosterName or rec.rosterName == rosterName then
            local status = rec.marks and rec.marks[fullName]
            if status and stats[status] then stats[status] = stats[status] + 1 end
        end
    end
    local counted = stats.present + stats.late + stats.absent
    stats.counted = counted
    stats.percent = counted > 0 and math.floor((stats.present + stats.late) * 100 / counted + 0.5) or nil
    return stats
end

-- Media de asistencia de los integrantes de un roster y cuántas bandas tienen lista pasada
function eventsModule.GetRosterAttendance(roster)
    local total, n = 0, 0
    for name in pairs(roster.members or {}) do
        local stats = eventsModule.GetAttendanceStats(roster.name, name)
        if stats.percent then
            total = total + stats.percent
            n = n + 1
        end
    end
    local events = 0
    for _, rec in pairs(AttendanceStore()) do
        if rec.rosterName == roster.name and next(rec.marks or {}) then events = events + 1 end
    end
    return n > 0 and math.floor(total / n + 0.5) or nil, events
end

-- Historial de un jugador en las bandas de un roster: { {date, time, title, status}, ... }, recientes primero
function eventsModule.GetAttendanceHistory(rosterName, fullName)
    local list = {}
    for _, rec in pairs(AttendanceStore()) do
        if rec.rosterName == rosterName and rec.marks and rec.marks[fullName] then
            table.insert(list, { date = rec.date, time = rec.time, title = rec.title, status = rec.marks[fullName] })
        end
    end
    table.sort(list, function(a, b) return ((a.date or "") .. (a.time or "")) > ((b.date or "") .. (b.time or "")) end)
    return list
end

-- Próximas bandas de un roster (todas si rosterName es nil), más próximas primero
function eventsModule.GetUpcomingForRoster(rosterName)
    local list = {}
    local today = date("%Y-%m-%d")
    for _, event in ipairs(eventsModule.GetUpcoming()) do
        if event.date >= today and (not rosterName or event.rosterName == rosterName) then table.insert(list, event) end
    end
    return list
end

-- Al renombrar un roster, sus bandas y su asistencia siguen asociadas
function eventsModule.RenameRoster(oldName, newName)
    if not oldName or not newName or oldName == newName then return end
    for _, event in pairs(Store()) do
        if event.rosterName == oldName then event.rosterName = newName end
    end
    for _, rec in pairs(AttendanceStore()) do
        if rec.rosterName == oldName then rec.rosterName = newName end
    end
end

-- Las fechas con asistencia que antes se pasaban en el Roster se conservan como historial
function eventsModule.MigrateRosterDates()
    local data = GuildControlDB.rosterData
    if type(data) ~= "table" or type(data.rosters) ~= "table" then return end
    local store = AttendanceStore()
    for _, roster in pairs(data.rosters) do
        if type(roster) == "table" and type(roster.events) == "table" then
            for _, old in pairs(roster.events) do
                if type(old) == "table" and type(old.attendance) == "table" and next(old.attendance) then
                    local id = "roster-" .. tostring(roster.id or roster.name) .. "-" .. tostring(old.id)
                    if not store[id] then
                        store[id] = { date = old.date, time = old.time, rosterName = roster.name,
                                      title = (old.note and old.note ~= "") and old.note or roster.name,
                                      at = 0, marks = old.attendance }
                    end
                end
            end
            roster.events, roster.nextEventId = nil, nil
        end
    end
    data.viewMode = nil
end

-- =========================================================================
-- SINCRONIZACIÓN
-- =========================================================================
local sendQueue, sendTicker = {}, nil

-- =========================================================================
-- JEFES DE LA BANDA PROGRAMADA E HISTORIAL DE BANDAS
-- =========================================================================
-- Cuando muere un jefe de banda, si hay una banda programada en el addon en ese momento
-- (desde 1 h antes de su hora hasta 8 h después), del mismo diario de encuentros y de la
-- misma dificultad, se apunta en su registro: rec.bosses[encounterID] = { name, at }. El
-- registro es el de la asistencia (no se borra con la banda) y viaja con ella al publicarla.
local DIFFICULTY_IDS = { normal = 14, heroic = 15, mythic = 16 }
local EVENT_WINDOW_BEFORE = 3600
local EVENT_WINDOW_AFTER = 8 * 3600
local encounterCache = {}

-- Jefes de una banda del diario de encuentros, en orden: { {id = encounterID, name}, ... }
function eventsModule.GetRaidEncounters(raidId)
    raidId = tonumber(raidId)
    if not raidId or not EJ_GetEncounterInfoByIndex then return {} end
    if encounterCache[raidId] then return encounterCache[raidId] end
    local list = {}
    for index = 1, 40 do
        local ok, name, _, _, _, _, _, encounterID = pcall(EJ_GetEncounterInfoByIndex, index, raidId)
        if not ok or not name then break end
        table.insert(list, { id = tonumber(encounterID), name = name })
    end
    if #list > 0 then encounterCache[raidId] = list end
    return list
end

-- Hora de inicio de una banda (hora local) o nil
local function EventStart(event)
    local y, m, d = string.match(event and event.date or "", "^(%d+)-(%d+)-(%d+)$")
    if not y then return nil end
    local hh, mm = string.match(event.time or "", "^(%d+):(%d+)$")
    return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = tonumber(hh) or 20, min = tonumber(mm) or 0 })
end
eventsModule.EventStart = EventStart

-- La banda programada a la que pertenece un jefe que acaba de morir (o nil)
function eventsModule.FindActiveEvent(encounterID, difficultyID)
    encounterID = tonumber(encounterID)
    if not encounterID then return nil end
    local now, best, bestGap = time(), nil, nil
    for _, event in pairs(Store()) do
        local start = EventStart(event)
        if start and now >= start - EVENT_WINDOW_BEFORE and now <= start + EVENT_WINDOW_AFTER then
            local wanted = DIFFICULTY_IDS[event.difficulty]
            local sameDifficulty = not wanted or not difficultyID or wanted == difficultyID
            local inRaid = true
            if event.raidId then
                inRaid = false
                for _, boss in ipairs(eventsModule.GetRaidEncounters(event.raidId)) do
                    if boss.id == encounterID then inRaid = true break end
                end
            end
            if sameDifficulty and inRaid then
                local gap = math.abs(now - start)
                if not bestGap or gap < bestGap then best, bestGap = event, gap end
            end
        end
    end
    return best
end

local bossPublishTimer = nil
local function RecordBossKill(event, encounterID, name)
    local rec = Record(event, true)
    if rec.bosses[encounterID] then return false end
    rec.bosses[encounterID] = { name = Clean(name, 40), at = GetServerTime() }
    -- Los oficiales lo publican (los demás clientes solo lo guardan)
    if IsOfficer() then
        if bossPublishTimer then bossPublishTimer:Cancel() end
        bossPublishTimer = C_Timer.NewTimer(5, function()
            bossPublishTimer = nil
            eventsModule.Publish(event)
        end)
    end
    Notify()
    return true
end

local function OnEncounterEnd(encounterID, encounterName, difficultyID, _, success)
    if issecretvalue and (issecretvalue(encounterID) or issecretvalue(encounterName) or issecretvalue(success)) then return end
    if success ~= 1 and success ~= true then return end
    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "raid" then return end
    local event = eventsModule.FindActiveEvent(encounterID, difficultyID)
    if event and RecordBossKill(event, tonumber(encounterID), encounterName) then
        print("|cFF00FFFF[GuildControl]|r " .. L["Jefe derrotado en "] .. "|cFFFFD100" .. event.title .. "|r: " .. tostring(encounterName or "?"))
    end
end

-- Bandas anteriores (las que ya empezaron), más recientes primero:
-- { {id, date, time, title, raidId, raidName, difficulty, rosterName, marks, bosses}, ... }
function eventsModule.GetHistory()
    local list, seen, now = {}, {}, time()
    for id, rec in pairs(AttendanceStore()) do
        if rec.date then
            seen[id] = true
            table.insert(list, { id = id, date = rec.date, time = rec.time or "", title = rec.title or "?", raidId = rec.raidId,
                raidName = rec.raidName, difficulty = rec.difficulty, rosterName = rec.rosterName,
                marks = rec.marks or {}, bosses = rec.bosses or {} })
        end
    end
    for id, event in pairs(Store()) do
        local start = EventStart(event)
        if not seen[id] and start and start <= now then
            table.insert(list, { id = id, date = event.date, time = event.time or "", title = event.title, raidId = event.raidId,
                raidName = event.raidName, difficulty = event.difficulty, rosterName = event.rosterName, marks = {}, bosses = {} })
        end
    end
    table.sort(list, function(a, b) return (a.date .. a.time) > (b.date .. b.time) end)
    return list
end

-- Jefes de una banda del historial: los del diario en orden (muertos o no) y, si no hay
-- diario, solo los muertos. { {id, name, at}, ... } y cuántos murieron.
function eventsModule.GetHistoryBosses(entry)
    local list, killed = {}, 0
    local known = {}
    for _, boss in ipairs(eventsModule.GetRaidEncounters(entry.raidId)) do
        local kill = boss.id and entry.bosses[boss.id]
        known[boss.id or 0] = true
        table.insert(list, { id = boss.id, name = boss.name, at = kill and kill.at })
        if kill then killed = killed + 1 end
    end
    for id, kill in pairs(entry.bosses) do
        if not known[id] then
            table.insert(list, { id = id, name = kill.name, at = kill.at })
            killed = killed + 1
        end
    end
    return list, killed
end

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
    local rec = AttendanceStore()[event.id]
    local attendance = (rec and (next(rec.marks or {}) or next(rec.bosses or {})))
        and { marks = rec.marks or {}, at = rec.at or 0, bosses = rec.bosses } or nil
    local data = R.SerializeTable({ version = 1, event = event, attendance = attendance })
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
        -- Asistencia que pasó un oficial (gana la más reciente)
        local att = payload.attendance
        if type(att) == "table" and type(att.marks) == "table" then
            local rec = Record(Store()[event.id], true)
            local at = tonumber(att.at) or 0
            if at >= (rec.at or 0) then
                local marks = {}
                for name, status in pairs(att.marks) do
                    if type(name) == "string" and VALID_ATTENDANCE[status] then marks[string.sub(name, 1, 60)] = status end
                end
                rec.marks, rec.at = marks, at
            end
            -- Jefes muertos: se juntan los de todos (gana la primera hora conocida)
            if type(att.bosses) == "table" then
                for id, kill in pairs(att.bosses) do
                    id = tonumber(id)
                    if id and type(kill) == "table" and not rec.bosses[id] then
                        rec.bosses[id] = { name = Clean(kill.name, 40), at = tonumber(kill.at) or 0 }
                    end
                end
            end
        end
        if isNew then
            print("|cFF00FFFF[GuildControl]|r " .. L["Nueva banda: "] .. "|cFFFFD100" .. event.title .. L["|r el "]
                .. string.gsub(event.date, "^(%d+)-(%d+)-(%d+)$", "%3/%2/%1") .. L[" a las "] .. event.time .. L[". Apúntate en Raid."])
        end
        Notify()
    end
end

local function ScheduleRepublish()
    if republishTimer or not IsOfficer() then return end
    local events = eventsModule.GetRecent()   -- también las pasadas, por su asistencia
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
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if not GuildControlDB then return end
    if event == "ENCOUNTER_END" then
        OnEncounterEnd(...)
        return
    end
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
                ev.signups[fullSender] = { status = fields[3], role = RoleForClass(fullSender, fields[4]),
                                           spec = Clean(fields[5], 30), note = Clean(fields[6], 60), at = at }
                Notify()
            end
        elseif kind == "O" and ev and IsOfficerName(fullSender) and fields[3] then
            local name, status, at = fields[3], fields[4], tonumber(fields[7]) or time()
            local current = ev.signups[name]
            if status == "removed" then
                if current and at >= (current.at or 0) then ev.signups[name] = nil end
            elseif STATUS_LABELS[status] and (not current or at >= (current.at or 0)) then
                ev.signups[name] = { status = status, role = RoleForClass(name, fields[5]),
                                     spec = Clean(fields[6], 30), note = current and current.note or "", at = at }
            end
            Notify()
        elseif kind == "X" and ev and IsOfficerName(fullSender) then
            Store()[eventId] = nil
            Notify()
        end
    end
end)
