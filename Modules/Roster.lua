local addonName, addonTable = ...

addonTable.Roster = {}
local rosterModule = addonTable.Roster

-- Lógica de los rosters de banda (sin frames). Datos en GuildControlDB.rosterData:
--   rosters[id] = { id, name, difficulty = "normal"|"heroic"|"mythic", size, tanks, healers,
--                   members = { [Nombre-Reino] = "tank"|"healer"|"dps"|"bench" } }
--   order = { id, ... }  (orden de creación), selected = id, nextId = n
-- El campo member.roster de cada miembro se mantiene con los rosters en los que está.

rosterModule.SLOTS = { "tank", "healer", "dps", "bench" }
rosterModule.SLOT_LABELS = { tank = "Tanques", healer = "Sanadores", dps = "DPS", bench = "Suplentes" }
rosterModule.DIFFICULTIES = {
    { key = "normal", label = "Normal" },
    { key = "heroic", label = "Heroica" },
    { key = "mythic", label = "Mítica" },
}
rosterModule.MIN_SIZE, rosterModule.MAX_SIZE, rosterModule.MYTHIC_SIZE = 10, 25, 20

-- Rol guardado en el miembro (columna Rol de Miembros) <-> hueco del roster
local ROLE_TO_SLOT = { ["Tanque"] = "tank", ["Sanador"] = "healer", ["DPS"] = "dps" }
local SLOT_TO_ROLE = { tank = "Tanque", healer = "Sanador", dps = "DPS" }

-- Utilidades de banda que aporta cada clase (por clase: el juego no da la especialización ajena)
local UTILITIES = {
    { label = "Ansia de sangre / Heroísmo", classes = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true } },
    { label = "Resurrección en combate", classes = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true } },
    { label = "Grito de batalla", classes = { WARRIOR = true } },
    { label = "Palabra de poder: entereza", classes = { PRIEST = true } },
    { label = "Intelecto Arcano", classes = { MAGE = true } },
    { label = "Marca de lo Salvaje", classes = { DRUID = true } },
    { label = "Toque místico", classes = { MONK = true } },
    { label = "Marca del caos", classes = { DEMONHUNTER = true } },
    { label = "Furia del cielo", classes = { SHAMAN = true } },
    { label = "Marca del cazador", classes = { HUNTER = true } },
    { label = "Bendición del bronce", classes = { EVOKER = true } },
}

local ARMOR_BY_CLASS = {
    MAGE = "cloth", PRIEST = "cloth", WARLOCK = "cloth",
    DRUID = "leather", ROGUE = "leather", MONK = "leather", DEMONHUNTER = "leather",
    HUNTER = "mail", SHAMAN = "mail", EVOKER = "mail",
    WARRIOR = "plate", PALADIN = "plate", DEATHKNIGHT = "plate",
}
rosterModule.ARMOR_TYPES = {
    { key = "cloth", label = "Tela" }, { key = "leather", label = "Cuero" },
    { key = "mail", label = "Malla" }, { key = "plate", label = "Placas" },
}

-- =========================================================================
-- DATOS
-- =========================================================================
local function Data()
    if type(GuildControlDB.rosterData) ~= "table" then GuildControlDB.rosterData = {} end
    local d = GuildControlDB.rosterData
    if type(d.rosters) ~= "table" then d.rosters = {} end
    if type(d.order) ~= "table" then d.order = {} end
    if type(d.nextId) ~= "number" then d.nextId = 1 end
    return d
end

local function SuggestedHealers(size)
    if size <= 12 then return 2 elseif size <= 17 then return 3 elseif size <= 22 then return 4 end
    return 5
end

local function ApplySuggestedTargets(roster)
    roster.tanks = 2
    roster.healers = SuggestedHealers(roster.size)
end

function rosterModule.GetClassName(classFile)
    return (LOCALIZED_CLASS_NAMES_MALE and classFile and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile or "?"
end

function rosterModule.GetMemberSlotForRole(fullName)
    local m = GuildControlDB.members[fullName]
    return (m and ROLE_TO_SLOT[m.role]) or "dps"
end

function rosterModule.SetMemberRole(fullName, slot)
    local m = GuildControlDB.members[fullName]
    if m and SLOT_TO_ROLE[slot] then m.role = SLOT_TO_ROLE[slot] end
end

-- Lista ordenada de rosters
function rosterModule.GetAll()
    local d = Data()
    local list = {}
    for _, id in ipairs(d.order) do
        if d.rosters[id] then table.insert(list, d.rosters[id]) end
    end
    return list
end

function rosterModule.Create(name)
    local d = Data()
    local id = d.nextId
    d.nextId = id + 1
    local roster = {
        id = id,
        name = (name and strtrim(name) ~= "") and strtrim(name) or ("Roster " .. id),
        difficulty = "heroic",
        size = 20,
        members = {},
    }
    ApplySuggestedTargets(roster)
    d.rosters[id] = roster
    table.insert(d.order, id)
    d.selected = id
    return roster
end

-- Roster seleccionado; si no hay ninguno se crea "Roster 1"
function rosterModule.GetSelected()
    local d = Data()
    local roster = d.selected and d.rosters[d.selected]
    if roster then return roster end
    local first = d.order[1] and d.rosters[d.order[1]]
    if first then
        d.selected = first.id
        return first
    end
    return rosterModule.Create()
end

function rosterModule.Select(id)
    local d = Data()
    if d.rosters[id] then d.selected = id end
end

function rosterModule.Rename(roster, name)
    name = strtrim(name or "")
    if roster and name ~= "" then
        roster.name = name
        rosterModule.SyncMemberRosterField()
    end
end

function rosterModule.Duplicate(roster)
    if not roster then return nil end
    local copy = rosterModule.Create(roster.name .. " (copia)")
    copy.difficulty, copy.size, copy.tanks, copy.healers = roster.difficulty, roster.size, roster.tanks, roster.healers
    for name, slot in pairs(roster.members) do copy.members[name] = slot end
    rosterModule.SyncMemberRosterField()
    return copy
end

function rosterModule.Delete(roster)
    if not roster then return end
    local d = Data()
    d.rosters[roster.id] = nil
    for i = #d.order, 1, -1 do
        if d.order[i] == roster.id then table.remove(d.order, i) end
    end
    if d.selected == roster.id then d.selected = d.order[1] end
    rosterModule.SyncMemberRosterField()
end

-- =========================================================================
-- CRITERIOS
-- =========================================================================
function rosterModule.SetDifficulty(roster, difficulty)
    roster.difficulty = difficulty
    if difficulty == "mythic" then roster.size = rosterModule.MYTHIC_SIZE end
    ApplySuggestedTargets(roster)
end

function rosterModule.SetSize(roster, size)
    if roster.difficulty == "mythic" then return end
    size = math.floor(tonumber(size) or roster.size)
    roster.size = math.max(rosterModule.MIN_SIZE, math.min(rosterModule.MAX_SIZE, size))
    ApplySuggestedTargets(roster)
end

function rosterModule.SetTarget(roster, slot, value)
    value = math.max(0, math.floor(tonumber(value) or 0))
    if slot == "tank" then roster.tanks = math.min(value, roster.size) end
    if slot == "healer" then roster.healers = math.min(value, roster.size - roster.tanks) end
end

-- Objetivo de cada rol: los DPS son el resto hasta el tamaño
function rosterModule.GetTargets(roster)
    local tanks, healers = roster.tanks or 2, roster.healers or SuggestedHealers(roster.size)
    return { tank = tanks, healer = healers, dps = math.max(0, roster.size - tanks - healers) }
end

-- =========================================================================
-- INTEGRANTES
-- =========================================================================
function rosterModule.AddMember(roster, fullName, slot)
    if not roster or not fullName then return end
    roster.members[fullName] = slot or rosterModule.GetMemberSlotForRole(fullName)
    rosterModule.SyncMemberRosterField()
end

function rosterModule.RemoveMember(roster, fullName)
    if not roster or not fullName then return end
    roster.members[fullName] = nil
    rosterModule.SyncMemberRosterField()
end

function rosterModule.Clear(roster)
    if not roster then return end
    wipe(roster.members)
    rosterModule.SyncMemberRosterField()
end

-- Quita del roster a quien ya no está en la hermandad
function rosterModule.Prune(roster)
    if not roster then return end
    local changed = false
    for name in pairs(roster.members) do
        if not GuildControlDB.members[name] then
            roster.members[name] = nil
            changed = true
        end
    end
    if changed then rosterModule.SyncMemberRosterField() end
end

-- { tank = {nombres}, healer = {...}, dps = {...}, bench = {...} } ordenados por clase y nombre
function rosterModule.GetMembersBySlot(roster)
    local result = { tank = {}, healer = {}, dps = {}, bench = {} }
    for name, slot in pairs(roster.members) do
        if result[slot] then table.insert(result[slot], name) end
    end
    for _, list in pairs(result) do
        table.sort(list, function(a, b)
            local ca = (GuildControlDB.members[a] or {}).class or ""
            local cb = (GuildControlDB.members[b] or {}).class or ""
            if ca ~= cb then return ca < cb end
            return a < b
        end)
    end
    return result
end

-- Titulares (todos menos la banca)
local function ForEachStarter(roster, fn)
    for name, slot in pairs(roster.members) do
        if slot ~= "bench" then
            local m = GuildControlDB.members[name]
            if m then fn(name, m) end
        end
    end
end

-- member.roster = nombres de los rosters en los que está ("Sin Roster" si ninguno)
function rosterModule.SyncMemberRosterField()
    local byMember = {}
    for _, roster in ipairs(rosterModule.GetAll()) do
        for name in pairs(roster.members) do
            byMember[name] = byMember[name] or {}
            table.insert(byMember[name], roster.name)
        end
    end
    for name, m in pairs(GuildControlDB.members) do
        m.roster = byMember[name] and table.concat(byMember[name], ", ") or "Sin Roster"
    end
end

-- =========================================================================
-- COBERTURA
-- =========================================================================
function rosterModule.GetCoverage(roster)
    local classCount = {}
    ForEachStarter(roster, function(_, m)
        if m.class then classCount[m.class] = (classCount[m.class] or 0) + 1 end
    end)
    local result = {}
    for _, utility in ipairs(UTILITIES) do
        local count = 0
        for class in pairs(utility.classes) do count = count + (classCount[class] or 0) end
        table.insert(result, { label = utility.label, count = count })
    end
    return result
end

function rosterModule.GetArmorCounts(roster)
    local counts = { cloth = 0, leather = 0, mail = 0, plate = 0 }
    ForEachStarter(roster, function(_, m)
        local armor = ARMOR_BY_CLASS[m.class or ""]
        if armor then counts[armor] = counts[armor] + 1 end
    end)
    return counts
end

-- =========================================================================
-- ANUNCIO, CSV E INVITACIÓN
-- =========================================================================
local function DifficultyLabel(roster)
    for _, diff in ipairs(rosterModule.DIFFICULTIES) do
        if diff.key == roster.difficulty then return diff.label end
    end
    return roster.difficulty
end
rosterModule.DifficultyLabel = DifficultyLabel

local function ShortName(name)
    return string.match(name, "^([^-]+)") or name
end

-- Mensajes de chat (máximo 255 bytes cada uno) con la composición
function rosterModule.BuildAnnounceLines(roster)
    local lines = { "Roster " .. roster.name .. " (" .. DifficultyLabel(roster) .. " " .. roster.size .. ")" }
    local bySlot = rosterModule.GetMembersBySlot(roster)
    for _, slot in ipairs(rosterModule.SLOTS) do
        local names = bySlot[slot]
        if #names > 0 then
            local line = rosterModule.SLOT_LABELS[slot] .. ": "
            local first = true
            for _, name in ipairs(names) do
                local piece = (first and "" or ", ") .. ShortName(name)
                if #line + #piece > 250 then
                    table.insert(lines, line)
                    line = rosterModule.SLOT_LABELS[slot] .. " (cont.): " .. ShortName(name)
                else
                    line = line .. piece
                end
                first = false
            end
            table.insert(lines, line)
        end
    end
    return lines
end

function rosterModule.BuildCSV(roster)
    local lines = { "Roster,Dificultad,Puesto,Nombre,Clase,Nivel,Rango,Asistencia" }
    local bySlot = rosterModule.GetMembersBySlot(roster)
    for _, slot in ipairs(rosterModule.SLOTS) do
        for _, name in ipairs(bySlot[slot]) do
            local m = GuildControlDB.members[name] or {}
            local stats = rosterModule.GetAttendanceStats(roster, name)
            table.insert(lines, string.format("%s,%s,%s,%s,%s,%s,%s,%s",
                roster.name, DifficultyLabel(roster), rosterModule.SLOT_LABELS[slot], name,
                rosterModule.GetClassName(m.class), tostring(m.level or ""), m.rank or "",
                stats.percent and (stats.percent .. "%") or ""))
        end
    end
    return table.concat(lines, "\n")
end

-- Invitar al grupo a los titulares conectados. Con más de 4 se invita a los primeros,
-- se convierte el grupo en banda cuando alguien acepta y después se invita al resto.
local pendingInvites = {}
local inviteFrame = CreateFrame("Frame")
inviteFrame:SetScript("OnEvent", function(self)
    if #pendingInvites == 0 then
        self:UnregisterEvent("GROUP_ROSTER_UPDATE")
        return
    end
    if not IsInRaid() and GetNumGroupMembers() > 1 and UnitIsGroupLeader("player") then
        if C_PartyInfo and C_PartyInfo.ConvertToRaid then C_PartyInfo.ConvertToRaid() end
    end
    if IsInRaid() then
        for _, name in ipairs(pendingInvites) do C_PartyInfo.InviteUnit(name) end
        wipe(pendingInvites)
        self:UnregisterEvent("GROUP_ROSTER_UPDATE")
    end
end)

function rosterModule.InviteRoster(roster)
    local me = UnitName("player")
    local targets = {}
    ForEachStarter(roster, function(name, m)
        if m.isOnline and ShortName(name) ~= me then table.insert(targets, name) end
    end)
    if #targets == 0 then return 0 end

    wipe(pendingInvites)
    local canInviteAll = IsInRaid() or #targets <= 4
    for i, name in ipairs(targets) do
        if canInviteAll or i <= 4 then
            C_PartyInfo.InviteUnit(name)
        else
            table.insert(pendingInvites, name)
        end
    end
    if #pendingInvites > 0 then inviteFrame:RegisterEvent("GROUP_ROSTER_UPDATE") end
    return #targets
end


-- =========================================================================
-- FECHAS DE BANDA Y ASISTENCIA (FASE 2)
-- =========================================================================
-- roster.events[id] = { id, date = "AAAA-MM-DD", time = "HH:MM", note,
--                       attendance = { [Nombre-Reino] = "present"|"late"|"absent"|"excused" } }
rosterModule.ATTENDANCE = { "present", "late", "absent", "excused" }
rosterModule.ATTENDANCE_LABELS = { present = "Presente", late = "Tarde", absent = "Ausente", excused = "Justif." }
rosterModule.ATTENDANCE_COLORS = { present = "00FF00", late = "FFD100", absent = "FF3333", excused = "66B3FF" }

local function Events(roster)
    if type(roster.events) ~= "table" then roster.events = {} end
    if type(roster.nextEventId) ~= "number" then roster.nextEventId = 1 end
    return roster.events
end

-- Valida y normaliza fecha y hora. Devuelve "AAAA-MM-DD", "HH:MM" o nil, nil y un error
function rosterModule.ParseDateTime(dateText, timeText)
    local y, mo, d = string.match(strtrim(dateText or ""), "^(%d%d%d%d)-(%d%d?)-(%d%d?)$")
    if not y then
        d, mo, y = string.match(strtrim(dateText or ""), "^(%d%d?)/(%d%d?)/(%d%d%d%d)$")
    end
    y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
    if not y or mo < 1 or mo > 12 or d < 1 or d > 31 then return nil, nil, "Fecha no válida (usa DD/MM/AAAA)." end
    local h, mi = string.match(strtrim(timeText or ""), "^(%d%d?):(%d%d)$")
    h, mi = tonumber(h), tonumber(mi)
    if not h or h > 23 or mi > 59 then return nil, nil, "Hora no válida (usa HH:MM)." end
    return string.format("%04d-%02d-%02d", y, mo, d), string.format("%02d:%02d", h, mi)
end

function rosterModule.FormatEventDate(event)
    local y, mo, d = string.match(event.date or "", "^(%d+)-(%d+)-(%d+)$")
    if not y then return event.date or "?" end
    return d .. "/" .. mo .. "/" .. y .. " " .. (event.time or "")
end

function rosterModule.AddEvent(roster, dateText, timeText, note)
    local date, time, err = rosterModule.ParseDateTime(dateText, timeText)
    if not date then return nil, err end
    local events = Events(roster)
    for _, event in pairs(events) do
        if event.date == date and event.time == time then return nil, "Ya existe una fecha con ese día y hora." end
    end
    local id = roster.nextEventId
    roster.nextEventId = id + 1
    local event = { id = id, date = date, time = time, note = strtrim(note or ""), attendance = {} }
    events[id] = event
    return event
end

function rosterModule.DeleteEvent(roster, event)
    if roster and event then Events(roster)[event.id] = nil end
end

-- Más reciente primero
function rosterModule.GetEventsSorted(roster)
    local list = {}
    for _, event in pairs(Events(roster)) do table.insert(list, event) end
    table.sort(list, function(a, b) return (a.date .. a.time) > (b.date .. b.time) end)
    return list
end

function rosterModule.GetEvent(roster, id)
    return id and Events(roster)[id]
end

function rosterModule.SetAttendance(event, fullName, status)
    if not event or not fullName then return end
    if event.attendance[fullName] == status then
        event.attendance[fullName] = nil      -- un segundo clic quita la marca
    else
        event.attendance[fullName] = status
    end
end

function rosterModule.GetEventCounts(event)
    local counts = { present = 0, late = 0, absent = 0, excused = 0 }
    for _, status in pairs(event.attendance or {}) do
        if counts[status] then counts[status] = counts[status] + 1 end
    end
    return counts
end

-- Asistencia de un jugador en las fechas de este roster.
-- percent = (presente + tarde) / (presente + tarde + ausente); las justificadas no cuentan.
function rosterModule.GetAttendanceStats(roster, fullName)
    local stats = { present = 0, late = 0, absent = 0, excused = 0 }
    for _, event in pairs(Events(roster)) do
        local status = event.attendance[fullName]
        if status and stats[status] then stats[status] = stats[status] + 1 end
    end
    local counted = stats.present + stats.late + stats.absent
    stats.counted = counted
    stats.percent = counted > 0 and math.floor((stats.present + stats.late) * 100 / counted + 0.5) or nil
    return stats
end

-- Media de asistencia de los integrantes actuales
function rosterModule.GetRosterAttendanceAverage(roster)
    local total, n = 0, 0
    for name in pairs(roster.members) do
        local stats = rosterModule.GetAttendanceStats(roster, name)
        if stats.percent then
            total = total + stats.percent
            n = n + 1
        end
    end
    return n > 0 and math.floor(total / n + 0.5) or nil
end

-- Integrantes a mostrar en la hoja de una fecha: los del roster y quien tenga marca en ella
function rosterModule.GetAttendanceList(roster, event)
    local slotOrder = { tank = 1, healer = 2, dps = 3, bench = 4 }
    local seen, list = {}, {}
    for name, slot in pairs(roster.members) do
        seen[name] = true
        table.insert(list, { name = name, slot = slot })
    end
    for name in pairs(event.attendance or {}) do
        if not seen[name] then table.insert(list, { name = name, slot = "gone" }) end
    end
    table.sort(list, function(a, b)
        local oa, ob = slotOrder[a.slot] or 5, slotOrder[b.slot] or 5
        if oa ~= ob then return oa < ob end
        return a.name < b.name
    end)
    return list
end

-- Nombres (Nombre-Reino) de quienes están ahora en mi grupo o banda
local function CurrentGroupNames()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or string.gsub(GetRealmName() or "", "%s+", "")
    local function Normalize(name, unitRealm)
        if not name then return nil end
        if string.find(name, "-", 1, true) then return (string.gsub(name, "%s+", "")) end
        local r = (unitRealm and unitRealm ~= "") and unitRealm or realm
        return (string.gsub(name .. "-" .. r, "%s+", ""))
    end

    local names = {}
    names[Normalize(UnitName("player"))] = true
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local n = Normalize((GetRaidRosterInfo(i)))
            if n then names[n] = true end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local n = Normalize(UnitName("party" .. i))
            if n then names[n] = true end
        end
    end
    return names
end

-- Marca la asistencia según el grupo actual: titulares presentes o ausentes (las
-- justificadas se respetan); los suplentes solo se marcan si están en el grupo.
function rosterModule.TakeAttendanceFromGroup(roster, event)
    local inGroup = CurrentGroupNames()
    local present = 0
    for name, slot in pairs(roster.members) do
        if inGroup[name] then
            event.attendance[name] = "present"
            present = present + 1
        elseif slot ~= "bench" and event.attendance[name] ~= "excused" then
            event.attendance[name] = "absent"
        end
    end
    return present
end

function rosterModule.MarkAllStarters(roster, event, status)
    for name, slot in pairs(roster.members) do
        if slot ~= "bench" then event.attendance[name] = status end
    end
end

function rosterModule.ClearAttendance(event)
    if event then wipe(event.attendance) end
end

-- Importa los eventos del calendario del juego (mes actual y siguiente), sin festividades
-- ni reinicios de banda. Devuelve cuántas fechas se añadieron (nil si no hay API).
function rosterModule.ImportCalendarEvents(roster)
    if not (C_Calendar and C_Calendar.GetNumDayEvents and C_Calendar.GetDayEvent and C_Calendar.GetMonthInfo) then
        return nil
    end
    local skip = { HOLIDAY = true, RAID_LOCKOUT = true, RAID_RESET = true }
    local added = 0
    for monthOffset = 0, 1 do
        local okInfo, info = pcall(C_Calendar.GetMonthInfo, monthOffset)
        if okInfo and info and info.numDays then
            for day = 1, info.numDays do
                local okNum, num = pcall(C_Calendar.GetNumDayEvents, monthOffset, day)
                for index = 1, (okNum and num or 0) do
                    local okEvent, event = pcall(C_Calendar.GetDayEvent, monthOffset, day, index)
                    if okEvent and event and event.startTime and not skip[event.calendarType or ""] then
                        local st = event.startTime
                        local dateText = string.format("%04d-%02d-%02d", st.year, st.month, st.monthDay)
                        local timeText = string.format("%02d:%02d", st.hour, st.minute)
                        if rosterModule.AddEvent(roster, dateText, timeText, event.title) then added = added + 1 end
                    end
                end
            end
        end
    end
    return added
end
