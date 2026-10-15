local addonName, addonTable = ...
local L = addonTable.L

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

-- Cada cambio de un oficial se envía solo a la hermandad, como las bandas de Raid: se
-- marca la hora (del servidor, para comparar entre clientes) y se publica unos segundos
-- después del último cambio
local autoPublishTimers = {}
local function Touch(roster)
    if not roster then return end
    roster.updatedAt = GetServerTime()
    if addonTable.Profiles and not addonTable.Profiles.IsOfficer() then return end
    local id = roster.id
    if autoPublishTimers[id] then autoPublishTimers[id]:Cancel() end
    autoPublishTimers[id] = C_Timer.NewTimer(2, function()
        autoPublishTimers[id] = nil
        local current = Data().rosters[id]
        if current and rosterModule.ShareRoster then rosterModule.ShareRoster(current, true) end
    end)
end
rosterModule.Touch = Touch

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

-- Un rol cuenta como definido si lo declaró el jugador o lo fijó un oficial;
-- el "DPS" que se pone por defecto al detectar un miembro no cuenta.
function rosterModule.HasDefinedRole(m)
    return m ~= nil and (m.roleSource == "declared" or m.roleSource == "officer") and ROLE_TO_SLOT[m.role] ~= nil
end

-- Hueco que le corresponde por su rol, o nil si no tiene rol definido
function rosterModule.GetDefinedSlot(fullName)
    local m = GuildControlDB.members[fullName]
    return rosterModule.HasDefinedRole(m) and ROLE_TO_SLOT[m.role] or nil
end

-- Para añadirlo al roster: sin rol definido entra como DPS
function rosterModule.GetMemberSlotForRole(fullName)
    return rosterModule.GetDefinedSlot(fullName) or "dps"
end

function rosterModule.SetMemberRole(fullName, slot)
    local m = GuildControlDB.members[fullName]
    if m and SLOT_TO_ROLE[slot] then m.role = SLOT_TO_ROLE[slot]; m.roleSource = "officer" end
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
        name = (name and strtrim(name) ~= "") and strtrim(name) or (L["Roster "] .. id),
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
        if addonTable.RaidEvents and addonTable.RaidEvents.RenameRoster then
            addonTable.RaidEvents.RenameRoster(roster.name, name)
        end
        roster.name = name
        rosterModule.SyncMemberRosterField()
        Touch(roster)
    end
end

-- =========================================================================
-- INTEGRANTES Y VARIANTES POR JEFE (FASE 3)
-- =========================================================================
-- La composición base está en roster.members. Cada jefe es una variante con
-- overrides[nombre] = "tank"|"healer"|"dps"|"bench" que se aplican sobre la base;
-- "bench" en una variante significa que no juega ese jefe.
--   roster.variants[id] = { id, name, overrides }, roster.variantOrder = {id...},
--   roster.selectedVariant = id (nil = base)

local function Variants(roster)
    if type(roster.variants) ~= "table" then roster.variants = {} end
    if type(roster.variantOrder) ~= "table" then roster.variantOrder = {} end
    if type(roster.nextVariantId) ~= "number" then roster.nextVariantId = 1 end
    return roster.variants
end

function rosterModule.GetVariants(roster)
    local variants = Variants(roster)
    local list = {}
    for _, id in ipairs(roster.variantOrder) do
        if variants[id] then table.insert(list, variants[id]) end
    end
    return list
end

function rosterModule.GetSelectedVariant(roster)
    local variant = roster.selectedVariant and Variants(roster)[roster.selectedVariant]
    if not variant then roster.selectedVariant = nil end
    return variant
end

function rosterModule.SelectVariant(roster, id)
    roster.selectedVariant = id and Variants(roster)[id] and id or nil
end

function rosterModule.AddVariant(roster, name)
    local variants = Variants(roster)
    local id = roster.nextVariantId
    roster.nextVariantId = id + 1
    name = strtrim(name or "")
    if name == "" then name = L["Jefe "] .. (#roster.variantOrder + 1) end
    variants[id] = { id = id, name = name, overrides = {} }
    table.insert(roster.variantOrder, id)
    roster.selectedVariant = id
    return variants[id]
end

function rosterModule.DeleteVariant(roster, variant)
    if not variant then return end
    Variants(roster)[variant.id] = nil
    for i = #roster.variantOrder, 1, -1 do
        if roster.variantOrder[i] == variant.id then table.remove(roster.variantOrder, i) end
    end
    if roster.selectedVariant == variant.id then roster.selectedVariant = nil end
    rosterModule.SyncMemberRosterField()
end

-- Composición efectiva (base + variante seleccionada): { [nombre] = puesto }
function rosterModule.GetEffectiveMembers(roster, variant)
    variant = variant or rosterModule.GetSelectedVariant(roster)
    if not variant then return roster.members end
    local result = {}
    for name, slot in pairs(roster.members) do result[name] = slot end
    for name, slot in pairs(variant.overrides) do result[name] = slot end
    return result
end

-- Quién entra y quién sale respecto a la base en la variante seleccionada
function rosterModule.GetVariantDiff(roster)
    local variant = rosterModule.GetSelectedVariant(roster)
    if not variant then return nil end
    local effective = rosterModule.GetEffectiveMembers(roster, variant)
    local entering, leaving, roleChanges = {}, {}, {}
    local function IsStarter(slot) return slot and slot ~= "bench" end
    for name, slot in pairs(effective) do
        local baseSlot = roster.members[name]
        if IsStarter(slot) and not IsStarter(baseSlot) then table.insert(entering, name)
        elseif IsStarter(slot) and IsStarter(baseSlot) and slot ~= baseSlot then table.insert(roleChanges, name) end
    end
    for name, baseSlot in pairs(roster.members) do
        if IsStarter(baseSlot) and not IsStarter(effective[name]) then table.insert(leaving, name) end
    end
    table.sort(entering)
    table.sort(leaving)
    table.sort(roleChanges)
    return { entering = entering, leaving = leaving, roleChanges = roleChanges }
end

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = DeepCopy(v) end
    return copy
end
rosterModule.DeepCopy = DeepCopy

function rosterModule.Duplicate(roster)
    if not roster then return nil end
    local copy = rosterModule.Create(roster.name .. L[" (copia)"])
    copy.difficulty, copy.size, copy.tanks, copy.healers = roster.difficulty, roster.size, roster.tanks, roster.healers
    for name, slot in pairs(roster.members) do copy.members[name] = slot end
    -- Las variantes por jefe se copian; las fechas y la asistencia no
    copy.variants = DeepCopy(roster.variants or {})
    copy.variantOrder = DeepCopy(roster.variantOrder or {})
    copy.nextVariantId = roster.nextVariantId
    copy.selectedVariant = nil
    rosterModule.SyncMemberRosterField()
    Touch(copy)
    return copy
end

-- fromSync = true: lo borró otro oficial (no se vuelve a avisar)
function rosterModule.Delete(roster, fromSync)
    if not roster then return end
    -- Desaparece también en los demás clientes (oficiales y "Mis rosters")
    if not fromSync and roster.syncId and rosterModule.Unpublish then rosterModule.Unpublish(roster.syncId) end
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
    Touch(roster)
end

function rosterModule.SetSize(roster, size)
    if roster.difficulty == "mythic" then return end
    size = math.floor(tonumber(size) or roster.size)
    roster.size = math.max(rosterModule.MIN_SIZE, math.min(rosterModule.MAX_SIZE, size))
    ApplySuggestedTargets(roster)
    Touch(roster)
end

function rosterModule.SetTarget(roster, slot, value)
    value = math.max(0, math.floor(tonumber(value) or 0))
    if slot == "tank" then roster.tanks = math.min(value, roster.size) end
    if slot == "healer" then roster.healers = math.min(value, roster.size - roster.tanks) end
    Touch(roster)
end

-- Objetivo de cada rol: los DPS son el resto hasta el tamaño
function rosterModule.GetTargets(roster)
    local tanks, healers = roster.tanks or 2, roster.healers or SuggestedHealers(roster.size)
    return { tank = tanks, healer = healers, dps = math.max(0, roster.size - tanks - healers) }
end

-- =========================================================================
-- INTEGRANTES (actúan sobre la variante seleccionada o sobre la base)
-- =========================================================================
function rosterModule.AddMember(roster, fullName, slot)
    if not roster or not fullName then return end
    slot = slot or rosterModule.GetMemberSlotForRole(fullName)
    local variant = rosterModule.GetSelectedVariant(roster)
    if variant then
        -- Si coincide con la base no hace falta override
        variant.overrides[fullName] = (roster.members[fullName] ~= slot) and slot or nil
    else
        roster.members[fullName] = slot
        -- Colocarlo como tanque, sanador o DPS en la base define su rol si aún no tenía
        -- (y así se ve en la columna Rol de Miembros)
        if slot ~= "bench" and not rosterModule.GetDefinedSlot(fullName) then
            rosterModule.SetMemberRole(fullName, slot)
        end
    end
    rosterModule.SyncMemberRosterField()
    Touch(roster)
end

-- En una variante, quitar a alguien de la base = no juega ese jefe (banca)
function rosterModule.RemoveMember(roster, fullName)
    if not roster or not fullName then return end
    local variant = rosterModule.GetSelectedVariant(roster)
    if variant then
        variant.overrides[fullName] = roster.members[fullName] and "bench" or nil
    else
        roster.members[fullName] = nil
    end
    rosterModule.SyncMemberRosterField()
    Touch(roster)
end

-- Base: vacía el roster. Variante: la restablece a la base.
function rosterModule.Clear(roster)
    if not roster then return end
    local variant = rosterModule.GetSelectedVariant(roster)
    if variant then
        wipe(variant.overrides)
    else
        wipe(roster.members)
    end
    rosterModule.SyncMemberRosterField()
    Touch(roster)
end

-- Quita a quien ya no está en la hermandad (base y variantes)
function rosterModule.Prune(roster)
    if not roster then return end
    local changed = false
    for name in pairs(roster.members) do
        if not GuildControlDB.members[name] then
            roster.members[name] = nil
            changed = true
        end
    end
    for _, variant in pairs(Variants(roster)) do
        for name in pairs(variant.overrides) do
            if not GuildControlDB.members[name] then
                variant.overrides[name] = nil
                changed = true
            end
        end
    end
    if changed then
        rosterModule.SyncMemberRosterField()
        Touch(roster)
    end
end

-- { tank = {nombres}, healer = {...}, dps = {...}, bench = {...} } de la composición efectiva
function rosterModule.GetMembersBySlot(roster)
    local result = { tank = {}, healer = {}, dps = {}, bench = {} }
    for name, slot in pairs(rosterModule.GetEffectiveMembers(roster)) do
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

-- Titulares de la composición efectiva (todos menos la banca)
local function ForEachStarter(roster, fn)
    for name, slot in pairs(rosterModule.GetEffectiveMembers(roster)) do
        if slot ~= "bench" then
            local m = GuildControlDB.members[name]
            if m then fn(name, m) end
        end
    end
end

-- member.roster = nombres de los rosters en los que está ("Sin Roster" si ninguno).
-- Cuenta la base y a quien solo juega algún jefe.
function rosterModule.SyncMemberRosterField()
    local byMember = {}
    for _, roster in ipairs(rosterModule.GetAll()) do
        local inRoster = {}
        for name in pairs(roster.members) do inRoster[name] = true end
        for _, variant in pairs(Variants(roster)) do
            for name, slot in pairs(variant.overrides) do
                if slot ~= "bench" then inRoster[name] = true end
            end
        end
        for name in pairs(inRoster) do
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
        table.insert(result, { label = L[utility.label], count = count })
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
        if diff.key == roster.difficulty then return L[diff.label] end
    end
    return roster.difficulty
end
rosterModule.DifficultyLabel = DifficultyLabel

local function ShortName(name)
    return string.match(name, "^([^-]+)") or name
end

-- "Roster 1" o "Roster 1 · Jefe 2" si hay una variante seleccionada
function rosterModule.GetDisplayName(roster)
    local variant = rosterModule.GetSelectedVariant(roster)
    return roster.name .. (variant and (" · " .. variant.name) or "")
end

-- Mensajes de chat (máximo 255 bytes cada uno) con la composición
function rosterModule.BuildAnnounceLines(roster)
    local lines = { L["Roster "] .. rosterModule.GetDisplayName(roster) .. " (" .. DifficultyLabel(roster) .. " " .. roster.size .. ")" }
    local bySlot = rosterModule.GetMembersBySlot(roster)
    for _, slot in ipairs(rosterModule.SLOTS) do
        local names = bySlot[slot]
        if #names > 0 then
            local line = L[rosterModule.SLOT_LABELS[slot]] .. ": "
            local first = true
            for _, name in ipairs(names) do
                local piece = (first and "" or ", ") .. ShortName(name)
                if #line + #piece > 250 then
                    table.insert(lines, line)
                    line = L[rosterModule.SLOT_LABELS[slot]] .. L[" (cont.): "] .. ShortName(name)
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
    local lines = { L["Roster,Dificultad,Puesto,Nombre,Clase,Nivel,Rango,Asistencia"] }
    local bySlot = rosterModule.GetMembersBySlot(roster)
    for _, slot in ipairs(rosterModule.SLOTS) do
        for _, name in ipairs(bySlot[slot]) do
            local m = GuildControlDB.members[name] or {}
            local stats = addonTable.RaidEvents and addonTable.RaidEvents.GetAttendanceStats(roster.name, name) or {}
            table.insert(lines, string.format("%s,%s,%s,%s,%s,%s,%s,%s",
                rosterModule.GetDisplayName(roster), DifficultyLabel(roster), L[rosterModule.SLOT_LABELS[slot]], name,
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
-- FECHAS (las bandas y la asistencia viven en RaidEvents.lua)
-- =========================================================================
-- Valida y normaliza fecha y hora. Devuelve "AAAA-MM-DD", "HH:MM" o nil, nil y un error
function rosterModule.ParseDateTime(dateText, timeText)
    local y, mo, d = string.match(strtrim(dateText or ""), "^(%d%d%d%d)-(%d%d?)-(%d%d?)$")
    if not y then
        d, mo, y = string.match(strtrim(dateText or ""), "^(%d%d?)/(%d%d?)/(%d%d%d%d)$")
    end
    y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
    if not y or mo < 1 or mo > 12 or d < 1 or d > 31 then return nil, nil, L["Fecha no válida (usa DD/MM/AAAA)."] end
    local h, mi = string.match(strtrim(timeText or ""), "^(%d%d?):(%d%d)$")
    h, mi = tonumber(h), tonumber(mi)
    if not h or h > 23 or mi > 59 then return nil, nil, L["Hora no válida (usa HH:MM)."] end
    return string.format("%04d-%02d-%02d", y, mo, d), string.format("%02d:%02d", h, mi)
end

function rosterModule.FormatEventDate(event)
    local y, mo, d = string.match(event.date or "", "^(%d+)-(%d+)-(%d+)$")
    if not y then return event.date or "?" end
    return d .. "/" .. mo .. "/" .. y .. " " .. (event.time or "")
end


-- =========================================================================
-- COMPARTIR ROSTERS ENTRE OFICIALES (FASE 3)
-- =========================================================================
-- Un roster se serializa, se trocea en mensajes de addon (prefijo GuildControlRost,
-- canal GUILD) y el receptor lo guarda como "recibido" hasta que decide importarlo.
-- roster.syncId identifica el mismo roster en distintos clientes para poder actualizarlo.
local SYNC_PREFIX = "GuildControlRost"
local SYNC_CHUNK_BYTES = 200
local SYNC_SEND_INTERVAL = 0.3
local SYNC_PARTIAL_TIMEOUT = 120

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(SYNC_PREFIX)
end

-- Serializador propio: cadenas con longitud ("s5:Texto"), números, booleanos y tablas
local function Serialize(value, out)
    local t = type(value)
    if t == "string" then
        table.insert(out, "s" .. #value .. ":" .. value)
    elseif t == "number" then
        table.insert(out, "n" .. tostring(value) .. ";")
    elseif t == "boolean" then
        table.insert(out, value and "b1" or "b0")
    elseif t == "table" then
        table.insert(out, "t")
        for k, v in pairs(value) do
            local kt, vt = type(k), type(v)
            if (kt == "string" or kt == "number") and (vt == "string" or vt == "number" or vt == "boolean" or vt == "table") then
                Serialize(k, out)
                Serialize(v, out)
            end
        end
        table.insert(out, "e")
    end
end

local function Deserialize(text, pos, depth)
    if depth > 20 then error("anidamiento excesivo") end
    local tag = string.sub(text, pos, pos)
    if tag == "s" then
        local len, rest = string.match(text, "^(%d+):()", pos + 1)
        len = tonumber(len)
        if not len then error("cadena mal formada") end
        return string.sub(text, rest, rest + len - 1), rest + len
    elseif tag == "n" then
        local num, rest = string.match(text, "^([^;]+);()", pos + 1)
        if not tonumber(num) then error("número mal formado") end
        return tonumber(num), rest
    elseif tag == "b" then
        return string.sub(text, pos + 1, pos + 1) == "1", pos + 2
    elseif tag == "t" then
        local result = {}
        pos = pos + 1
        while string.sub(text, pos, pos) ~= "e" do
            if pos > #text then error("tabla sin cerrar") end
            local k, v
            k, pos = Deserialize(text, pos, depth + 1)
            v, pos = Deserialize(text, pos, depth + 1)
            result[k] = v
        end
        return result, pos + 1
    end
    error("tipo desconocido")
end

-- Para otros módulos (eventos de banda): tabla -> texto y texto -> tabla (o nil)
function rosterModule.SerializeTable(value)
    local out = {}
    Serialize(value, out)
    return table.concat(out)
end

function rosterModule.DeserializeTable(text)
    local ok, result = pcall(Deserialize, text or "", 1, 0)
    return ok and result or nil
end

-- Copia limpia de un roster recibido: solo campos conocidos y con tipos válidos
local VALID_SLOTS = { tank = true, healer = true, dps = true, bench = true }
local VALID_DIFFICULTY = { normal = true, heroic = true, mythic = true }

local function CleanString(value, maxLen)
    if type(value) ~= "string" then return nil end
    return string.sub(value, 1, maxLen or 60)
end

local function SanitizeRoster(raw)
    if type(raw) ~= "table" then return nil end
    local roster = {
        name = CleanString(raw.name, 30) or L["Roster recibido"],
        syncId = CleanString(raw.syncId, 80),
        difficulty = VALID_DIFFICULTY[raw.difficulty] and raw.difficulty or "heroic",
        size = math.max(rosterModule.MIN_SIZE, math.min(rosterModule.MAX_SIZE, math.floor(tonumber(raw.size) or 20))),
        tanks = math.max(0, math.floor(tonumber(raw.tanks) or 2)),
        healers = math.max(0, math.floor(tonumber(raw.healers) or 4)),
        updatedAt = tonumber(raw.updatedAt) or 0,
        members = {},
        variants = {}, variantOrder = {}, nextVariantId = 1,
    }
    if type(raw.members) == "table" then
        for name, slot in pairs(raw.members) do
            if type(name) == "string" and VALID_SLOTS[slot] then roster.members[CleanString(name)] = slot end
        end
    end
    if type(raw.variants) == "table" then
        local order = type(raw.variantOrder) == "table" and raw.variantOrder or {}
        for _, oldId in ipairs(order) do
            local v = raw.variants[oldId]
            if type(v) == "table" then
                local id = roster.nextVariantId
                roster.nextVariantId = id + 1
                local clean = { id = id, name = CleanString(v.name, 30) or (L["Jefe "] .. id), overrides = {} }
                if type(v.overrides) == "table" then
                    for name, slot in pairs(v.overrides) do
                        if type(name) == "string" and VALID_SLOTS[slot] then clean.overrides[CleanString(name)] = slot end
                    end
                end
                roster.variants[id] = clean
                table.insert(roster.variantOrder, id)
            end
        end
    end
    return roster
end

-- -------------------------------------------------------------------------
-- Envío
-- -------------------------------------------------------------------------
local sendQueue = {}
local sendTicker = nil

local function SendSucceeded(result)
    if result == nil or result == true or result == 0 then return true end
    if Enum and Enum.SendAddonMessageResult and result == Enum.SendAddonMessageResult.Success then return true end
    return false
end

local function ProcessSendQueue()
    local msg = sendQueue[1]
    if not msg then
        if sendTicker then sendTicker:Cancel() end
        sendTicker = nil
        return
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, SYNC_PREFIX, msg, "GUILD")
    -- Si el servidor limita el envío, se reintenta el mismo trozo en el siguiente tic
    if ok and SendSucceeded(result) then table.remove(sendQueue, 1) end
end

local function EnsureSyncId(roster)
    if not roster.syncId then
        roster.syncId = (UnitName("player") or "?") .. "-" .. time() .. "-" .. roster.id
    end
    return roster.syncId
end

-- Devuelve el número de mensajes que se enviarán
-- isRepublish = true: reenvío automático a quien lo pide (no cuenta como cambio nuevo)
function rosterModule.ShareRoster(roster, isRepublish)
    if not roster or not IsInGuild() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return 0 end
    EnsureSyncId(roster)
    if not isRepublish or not roster.updatedAt then roster.updatedAt = GetServerTime() end
    local payload = {
        version = 1,
        roster = {
            name = roster.name, syncId = roster.syncId, difficulty = roster.difficulty, size = roster.size,
            updatedAt = roster.updatedAt,
            tanks = roster.tanks, healers = roster.healers, members = roster.members,
            variants = roster.variants, variantOrder = roster.variantOrder,
        },
    }
    local out = {}
    Serialize(payload, out)
    local data = table.concat(out)

    local msgId = tostring(math.random(100000, 999999))
    local total = math.ceil(#data / SYNC_CHUNK_BYTES)
    for i = 1, total do
        local chunk = string.sub(data, (i - 1) * SYNC_CHUNK_BYTES + 1, i * SYNC_CHUNK_BYTES)
        table.insert(sendQueue, "D" .. msgId .. ":" .. i .. ":" .. total .. ":" .. chunk)
    end
    if not sendTicker then sendTicker = C_Timer.NewTicker(SYNC_SEND_INTERVAL, ProcessSendQueue) end
    return total
end

function rosterModule.GetPendingSendCount()
    return #sendQueue
end

-- -------------------------------------------------------------------------
-- Recepción
-- -------------------------------------------------------------------------
local partials = {}         -- [remitente:msgId] = { total, parts = {}, count, started }
local receivedListeners = {}   -- vistas que se refrescan al recibir o retirar un roster

function rosterModule.SetReceivedListener(fn)
    table.insert(receivedListeners, fn)
end

function rosterModule.FindBySyncId(syncId)
    if not syncId then return nil end
    for _, roster in ipairs(rosterModule.GetAll()) do
        if roster.syncId == syncId then return roster end
    end
    return nil
end

-- -------------------------------------------------------------------------
-- Rosters publicados: copia de solo lectura para todos (pestaña "Mis rosters")
-- GuildControlDB.sharedRosters[syncId] = { roster, from, fromRank, receivedAt }
-- -------------------------------------------------------------------------
local SHARED_MAX_AGE = 60 * 86400   -- se olvidan los publicados hace más de 60 días

local function SharedStore()
    if type(GuildControlDB.sharedRosters) ~= "table" then GuildControlDB.sharedRosters = {} end
    return GuildControlDB.sharedRosters
end

-- Lista de rosters publicados (más recientes primero)
function rosterModule.GetSharedRosters()
    local store = SharedStore()
    local now = time()
    local list = {}
    for syncId, item in pairs(store) do
        if now - (item.receivedAt or 0) > SHARED_MAX_AGE then
            store[syncId] = nil
        else
            table.insert(list, item)
        end
    end
    table.sort(list, function(a, b) return (a.roster.updatedAt or 0) > (b.roster.updatedAt or 0) end)
    return list
end

local function StoreShared(sender, roster)
    if not roster.syncId then return end
    local store = SharedStore()
    local existing = store[roster.syncId]
    if existing and (existing.roster.updatedAt or 0) > (roster.updatedAt or 0) then return end
    local m = GuildControlDB.members[sender] or GuildControlDB.members[(string.gsub(sender, "%s+", ""))]
    store[roster.syncId] = {
        roster = roster,
        from = string.match(sender, "^([^-]+)") or sender,
        fromRank = m and m.rank or nil,
        receivedAt = time(),
    }
end

-- Copia los datos recibidos sobre un roster local (sin volver a publicarlo)
local SYNC_FIELDS = { "name", "syncId", "difficulty", "size", "tanks", "healers",
                      "members", "variants", "variantOrder", "nextVariantId" }
local function ApplyIncoming(target, incoming)
    if target.name ~= incoming.name and addonTable.RaidEvents and addonTable.RaidEvents.RenameRoster then
        addonTable.RaidEvents.RenameRoster(target.name, incoming.name)
    end
    for _, field in ipairs(SYNC_FIELDS) do target[field] = incoming[field] end
    target.selectedVariant = nil
    target.updatedAt = incoming.updatedAt
    target.syncedAt = incoming.updatedAt
end

local function OnRosterReceived(sender, data)
    -- Solo se aceptan rosters de oficiales
    if addonTable.Profiles and addonTable.Profiles.IsOfficerName and not addonTable.Profiles.IsOfficerName(sender) then return end
    local ok, payload = pcall(Deserialize, data, 1, 0)
    if not ok or type(payload) ~= "table" or payload.version ~= 1 then return end
    local roster = SanitizeRoster(payload.roster)
    if not roster or not roster.syncId then return end

    -- Copia de solo lectura para "Mis rosters" (la ven también los jugadores)
    StoreShared(sender, rosterModule.DeepCopy(roster))

    -- Oficiales: el roster se actualiza solo si el recibido es más reciente; si es nuevo, se añade
    local isOfficer = not addonTable.Profiles or addonTable.Profiles.IsOfficer()
    if isOfficer then
        local localCopy = rosterModule.FindBySyncId(roster.syncId)
        if localCopy then
            if (roster.updatedAt or 0) > (localCopy.updatedAt or 0) then ApplyIncoming(localCopy, roster) end
        else
            local d = Data()
            local previous = d.selected
            ApplyIncoming(rosterModule.Create(roster.name), roster)
            if previous and d.rosters[previous] then d.selected = previous end
            print("|cFF00FFFF[GuildControl]|r |cFFFFD100" .. sender .. L["|r ha publicado el roster |cFFFFD100"] .. roster.name .. "|r.")
        end
        rosterModule.SyncMemberRosterField()
    end
    for _, fn in ipairs(receivedListeners) do fn() end
end

-- -------------------------------------------------------------------------
-- Petición de rosters publicados ("Q"): al entrar, cada cliente la envía y un oficial
-- conectado responde reenviando los rosters que ha publicado. Si otro oficial empieza
-- a responder antes (llegan trozos "D"), se cancela la respuesta propia.
-- -------------------------------------------------------------------------
local republishTimer = nil

local function CancelRepublish()
    if republishTimer then republishTimer:Cancel() end
    republishTimer = nil
end

local function ScheduleRepublish()
    if republishTimer then return end
    if addonTable.Profiles and not addonTable.Profiles.IsOfficer() then return end
    local published = {}
    for _, roster in ipairs(rosterModule.GetAll()) do table.insert(published, roster) end
    if #published == 0 then return end
    republishTimer = C_Timer.NewTimer(3 + math.random() * 5, function()
        republishTimer = nil
        for _, roster in ipairs(published) do rosterModule.ShareRoster(roster, true) end
    end)
end

local function SendControl(msg)
    if IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(SYNC_PREFIX, msg, "GUILD")
    end
end

function rosterModule.RequestPublishedRosters()
    SendControl("Q")
end

-- Al borrar un roster publicado se avisa para que desaparezca de "Mis rosters"
function rosterModule.Unpublish(syncId)
    if syncId then SendControl("X:" .. syncId) end
end

local syncFrame = CreateFrame("Frame")
syncFrame:RegisterEvent("CHAT_MSG_ADDON")
syncFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
syncFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin or isReloadingUi then
            C_Timer.After(15, rosterModule.RequestPublishedRosters)
        end
        return
    end

    local prefix, msg, channel, sender = ...
    if prefix ~= SYNC_PREFIX or channel ~= "GUILD" then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    if not msg or not sender or not GuildControlDB then return end
    -- Ignorar mis propios envíos
    local short = string.match(sender, "^([^-]+)") or sender
    if short == UnitName("player") then return end

    if msg == "Q" then
        ScheduleRepublish()
        return
    end

    local removedId = string.match(msg, "^X:(.+)$")
    if removedId then
        if addonTable.Profiles and addonTable.Profiles.IsOfficerName and not addonTable.Profiles.IsOfficerName(sender) then return end
        SharedStore()[removedId] = nil
        local localCopy = rosterModule.FindBySyncId(removedId)
        if localCopy then rosterModule.Delete(localCopy, true) end
        for _, fn in ipairs(receivedListeners) do fn() end
        return
    end

    local msgId, index, total, chunk = string.match(msg, "^D(%d+):(%d+):(%d+):(.*)$")
    index, total = tonumber(index), tonumber(total)
    if not msgId or not index or not total or total > 500 then return end

    -- Otro oficial ya está respondiendo a la petición
    CancelRepublish()

    local now = GetTime()
    for key, partial in pairs(partials) do
        if now - partial.started > SYNC_PARTIAL_TIMEOUT then partials[key] = nil end
    end

    local key = sender .. ":" .. msgId
    local partial = partials[key]
    if not partial then
        partial = { total = total, parts = {}, count = 0, started = now }
        partials[key] = partial
    end
    if not partial.parts[index] then
        partial.parts[index] = chunk
        partial.count = partial.count + 1
    end
    if partial.count == partial.total then
        partials[key] = nil
        OnRosterReceived(sender, table.concat(partial.parts))
    end
end)

-- =========================================================================
-- BANDAS Y JEFES DEL DIARIO DE ENCUENTROS DEL JUEGO
-- =========================================================================
-- El diario (EJ_*) da las bandas de cada expansión y sus jefes. Se consulta la
-- expansión actual y las anteriores (hasta "maxTiers") y se restaura la selección del
-- diario para no alterar la ventana del juego si está abierta.
local function WithEJTier(tier, fn)
    if not (EJ_GetNumTiers and EJ_SelectTier) then return nil end
    local previous = EJ_GetCurrentTier and EJ_GetCurrentTier()
    local ok, result = pcall(function()
        EJ_SelectTier(tier)
        return fn()
    end)
    if previous then pcall(EJ_SelectTier, previous) end
    return ok and result or nil
end

-- { {tier, name, raids = { {id, name}, ... }}, ... } empezando por la expansión actual
function rosterModule.GetRaidTiers(maxTiers)
    local result = {}
    if not (EJ_GetNumTiers and EJ_GetInstanceByIndex) then return result end
    local okNum, numTiers = pcall(EJ_GetNumTiers)
    if not okNum or not numTiers then return result end
    for tier = numTiers, math.max(1, numTiers - (maxTiers or 3) + 1), -1 do
        local raids = WithEJTier(tier, function()
            local list = {}
            local index = 1
            while true do
                local instanceID, name = EJ_GetInstanceByIndex(index, true)
                if not instanceID then break end
                table.insert(list, { id = instanceID, name = name })
                index = index + 1
            end
            return list
        end) or {}
        local tierName = EJ_GetTierInfo and select(1, EJ_GetTierInfo(tier)) or (L["Expansión "] .. tier)
        if #raids > 0 then table.insert(result, { tier = tier, name = tierName, raids = raids }) end
    end
    return result
end

-- Nombres de los jefes de una banda, en orden
function rosterModule.GetRaidBosses(instanceID)
    local bosses = {}
    if not instanceID or not EJ_GetEncounterInfoByIndex then return bosses end
    local index = 1
    while true do
        local ok, name = pcall(EJ_GetEncounterInfoByIndex, index, instanceID)
        if not ok or not name then break end
        table.insert(bosses, name)
        index = index + 1
    end
    return bosses
end

-- Asocia el roster a una banda del diario y le pone su nombre
function rosterModule.SetRaid(roster, raid)
    if not roster or not raid then return end
    roster.raidId = raid.id
    roster.raidName = raid.name
    rosterModule.Rename(roster, raid.name)
end
