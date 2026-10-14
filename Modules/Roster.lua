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
    local lines = { "Roster,Dificultad,Puesto,Nombre,Clase,Nivel,Rango" }
    local bySlot = rosterModule.GetMembersBySlot(roster)
    for _, slot in ipairs(rosterModule.SLOTS) do
        for _, name in ipairs(bySlot[slot]) do
            local m = GuildControlDB.members[name] or {}
            table.insert(lines, string.format("%s,%s,%s,%s,%s,%s,%s",
                roster.name, DifficultyLabel(roster), rosterModule.SLOT_LABELS[slot], name,
                rosterModule.GetClassName(m.class), tostring(m.level or ""), m.rank or ""))
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
