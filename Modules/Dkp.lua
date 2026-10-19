local addonName, addonTable = ...
local L = addonTable.L

addonTable.Dkp = {}
local dkpModule = addonTable.Dkp

-- Sistema DKP (sin frames). Lo llevan los oficiales y se comparte con toda la hermandad.
--   - Se gana DKP por cada jefe de banda derrotado de una banda programada en Raid (los miembros
--     de la hermandad presentes),
--     por banda completada (botón de un oficial) y por antigüedad (cada semana).
--   - La antigüedad empieza el día en que el jugador rellena Mi perfil con GuildControl
--     (since[nombre] = fecha de su declaración más antigua conocida) y desempata las pujas.
--   - Cada reinicio semanal los DKP pierden un % (decay) para evitar la inflación.
--   - Los objetos se subastan desde Botín (Loot.lua): gana la puja más alta y paga lo que pujó.
--
-- GuildControlDB.dkp = {
--   system = "plusone"|"dkp",  settings = { boss, raid, seniority, decay, minBid },
--   balances = { [Nombre-Reino] = DKP }, since = { [Nombre-Reino] = fecha },
--   log = { {id, at, amount, reason, who, by}, ... } (recientes primero),
--   bossKeys = { [encuentro:dificultad:día] = hora }, lastWeekly = reinicio semanal aplicado,
--   updatedAt = hora del servidor del último cambio,
-- }
--
-- Mensajes (prefijo GuildControlDkp, canal de hermandad):
--   "Q"                       petición al entrar (responde un oficial con el estado)
--   "D<id>:<n>:<total>:<trozo>" estado completo troceado (solo se acepta de oficiales y si es más reciente)

local PREFIX = "GuildControlDkp"
local CHUNK_BYTES = 200
local SEND_INTERVAL = 0.3
local LOG_MAX = 200
local LOG_SENT = 40
local BOSS_KEY_DAYS = 7
local WEEK = 7 * 86400

dkpModule.SYSTEMS = { plusone = true, dkp = true }
dkpModule.DEFAULTS = { boss = 10, raid = 20, seniority = 5, decay = 10, minBid = 1, offspec = 50, gate = 20, minAttendance = 0 }
dkpModule.LIMITS = { boss = { 0, 1000 }, raid = { 0, 1000 }, seniority = { 0, 1000 }, decay = { 0, 90 }, minBid = { 1, 1000 },
                     offspec = { 0, 100 }, gate = { 0, 10000 }, minAttendance = { 0, 100 } }

-- Reparto: "fixed" = precio fijo por objeto (Main-spec paga el precio, Off-spec un % si nadie lo
-- pide como Main-spec, gana quien tenga más DKP) o "auction" = subasta abierta (el precio es la
-- puja mínima)
dkpModule.MODES = { fixed = true, auction = true }

-- Precio predeterminado de un objeto: según su hueco (categoría) y la dificultad en la que cayó.
-- Valores de partida pensados para lo que se gana por defecto (unos 100 DKP por noche: 8 jefes x 10
-- + 20 de banda): una pieza normal cuesta media noche y un arma de Mítica unas dos noches.
dkpModule.ITEM_CATEGORIES = {
    { key = "weapon2h", label = "Armas de 2 manos" },
    { key = "weapon1h", label = "Armas de 1 mano y mano izquierda" },
    { key = "trinket", label = "Abalorios" },
    { key = "major", label = "Set, pecho, cabeza y piernas" },
    { key = "medium", label = "Hombros, guantes, botas y escudos" },
    { key = "minor", label = "Cinturón, brazales, capa y anillos" },
    { key = "other", label = "Cuello, reliquias y otros" },
}
dkpModule.TIERS = { "normal", "heroic", "mythic" }
dkpModule.DEFAULT_PRICES = {
    weapon2h = { normal = 100, heroic = 150, mythic = 220 },
    weapon1h = { normal = 60, heroic = 90, mythic = 130 },
    trinket = { normal = 80, heroic = 120, mythic = 180 },
    major = { normal = 50, heroic = 75, mythic = 110 },
    medium = { normal = 40, heroic = 60, mythic = 90 },
    minor = { normal = 25, heroic = 40, mythic = 60 },
    other = { normal = 15, heroic = 25, mythic = 40 },
}

-- Premio en DKP por cada insignia de Tus novedades (Personal.BADGES). Se da una sola vez por
-- jugador e insignia (badgeAwards["Nombre-Reino:clave"] = 1). Los oficiales pueden cambiar las
-- cantidades, quitar insignias del premio y volver a estas.
dkpModule.DEFAULT_BADGE_REWARDS = { veteran = 50, loyal = 30, lucky = 10, artisan = 15, upToDate = 10 }

-- Hueco del objeto -> categoría de precio
local SLOT_CATEGORY = {
    INVTYPE_2HWEAPON = "weapon2h", INVTYPE_RANGED = "weapon2h", INVTYPE_RANGEDRIGHT = "weapon2h",
    INVTYPE_WEAPON = "weapon1h", INVTYPE_WEAPONMAINHAND = "weapon1h", INVTYPE_WEAPONOFFHAND = "weapon1h",
    INVTYPE_TRINKET = "trinket",
    INVTYPE_CHEST = "major", INVTYPE_ROBE = "major", INVTYPE_HEAD = "major", INVTYPE_LEGS = "major",
    INVTYPE_SHOULDER = "medium", INVTYPE_HAND = "medium", INVTYPE_FEET = "medium", INVTYPE_SHIELD = "medium", INVTYPE_HOLDABLE = "medium",
    INVTYPE_WAIST = "minor", INVTYPE_WRIST = "minor", INVTYPE_CLOAK = "minor", INVTYPE_FINGER = "minor",
    INVTYPE_NECK = "other",
}

local listeners = {}

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local function PrintGC(msg)
    print("|cFF00FFFF[GuildControl]|r " .. msg)
end

local function IsOfficer()
    return addonTable.Profiles and addonTable.Profiles.IsOfficer() or false
end

local function IsOfficerName(name)
    return addonTable.Profiles and addonTable.Profiles.IsOfficerName and addonTable.Profiles.IsOfficerName(name) or false
end

local function NormalizeName(name)
    if addonTable.Profiles and addonTable.Profiles.NormalizeName then return addonTable.Profiles.NormalizeName(name) end
    return name
end

local function MyName() return NormalizeName(UnitName("player")) end

local function Notify()
    for _, fn in ipairs(listeners) do fn() end
end
dkpModule.Notify = Notify

function dkpModule.AddListener(fn)
    table.insert(listeners, fn)
end

-- =========================================================================
-- DATOS
-- =========================================================================
local function State()
    local db = GuildControlDB.dkp
    if type(db) ~= "table" then
        db = {}
        GuildControlDB.dkp = db
    end
    if not dkpModule.SYSTEMS[db.system] then db.system = "plusone" end
    if type(db.settings) ~= "table" then db.settings = {} end
    for key, value in pairs(dkpModule.DEFAULTS) do
        if type(db.settings[key]) ~= "number" then db.settings[key] = value end
    end
    if not dkpModule.MODES[db.settings.mode] then db.settings.mode = "fixed" end
    if type(db.settings.prices) ~= "table" then db.settings.prices = {} end
    for category, defaults in pairs(dkpModule.DEFAULT_PRICES) do
        local row = db.settings.prices[category]
        if type(row) ~= "table" then row = {}; db.settings.prices[category] = row end
        for tier, value in pairs(defaults) do
            if type(row[tier]) ~= "number" then row[tier] = value end
        end
    end
    if type(db.settings.badgeRewards) ~= "table" then
        db.settings.badgeRewards = {}
        for key, value in pairs(dkpModule.DEFAULT_BADGE_REWARDS) do db.settings.badgeRewards[key] = value end
    end
    if type(db.badgeAwards) ~= "table" then db.badgeAwards = {} end
    if type(db.balances) ~= "table" then db.balances = {} end
    if type(db.since) ~= "table" then db.since = {} end
    if type(db.log) ~= "table" then db.log = {} end
    if type(db.bossKeys) ~= "table" then db.bossKeys = {} end
    db.lastWeekly = tonumber(db.lastWeekly) or 0
    db.updatedAt = tonumber(db.updatedAt) or 0
    return db
end

function dkpModule.GetSystem() return State().system end
function dkpModule.IsActive() return State().system == "dkp" end
function dkpModule.GetSettings() return State().settings end
function dkpModule.GetBalance(name) return name and State().balances[name] or 0 end
function dkpModule.GetSince(name) return name and State().since[name] or nil end
function dkpModule.GetLog() return State().log end

-- Días de antigüedad (nil si todavía no ha rellenado Mi perfil)
function dkpModule.GetSeniorityDays(name)
    local since = dkpModule.GetSince(name)
    if not since then return nil end
    return math.max(0, math.floor((time() - since) / 86400))
end

-- Lista para la vista: { {name, balance, days}, ... } de más DKP a menos
function dkpModule.GetList()
    local db, seen, list = State(), {}, {}
    local function Add(name)
        if seen[name] then return end
        seen[name] = true
        table.insert(list, { name = name, balance = db.balances[name] or 0, days = dkpModule.GetSeniorityDays(name) })
    end
    for name in pairs(db.balances) do Add(name) end
    for name in pairs(db.since) do Add(name) end
    table.sort(list, function(a, b)
        if a.balance ~= b.balance then return a.balance > b.balance end
        local da, db2 = a.days or -1, b.days or -1
        if da ~= db2 then return da > db2 end
        return a.name < b.name
    end)
    return list
end

-- =========================================================================
-- ENVÍO DEL ESTADO
-- =========================================================================
local sendQueue, sendTicker = {}, nil
local publishTimer, replyTimer = nil, nil

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

function dkpModule.Publish()
    if not IsInGuild() or not IsOfficer() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local R = addonTable.Roster
    if not (R and R.SerializeTable) then return end
    local db = State()
    if db.updatedAt == 0 then return end
    local log = {}
    for i = 1, math.min(#db.log, LOG_SENT) do log[i] = db.log[i] end
    local data = R.SerializeTable({
        version = 1, system = db.system, settings = db.settings, balances = db.balances, since = db.since,
        bossKeys = db.bossKeys, lastWeekly = db.lastWeekly, updatedAt = db.updatedAt, log = log,
        badgeAwards = db.badgeAwards,
    })
    -- Un envío nuevo sustituye al que estuviera a medias
    wipe(sendQueue)
    local msgId = tostring(math.random(100000, 999999))
    local total = math.ceil(#data / CHUNK_BYTES)
    for i = 1, total do
        table.insert(sendQueue, "D" .. msgId .. ":" .. i .. ":" .. total .. ":" .. string.sub(data, (i - 1) * CHUNK_BYTES + 1, i * CHUNK_BYTES))
    end
    if not sendTicker then sendTicker = C_Timer.NewTicker(SEND_INTERVAL, ProcessQueue) end
end

-- Marca un cambio y lo publica unos segundos después (varios cambios seguidos, un solo envío)
local function Touch()
    State().updatedAt = GetServerTime()
    if publishTimer then publishTimer:Cancel() end
    publishTimer = C_Timer.NewTimer(3, function()
        publishTimer = nil
        dkpModule.Publish()
    end)
    Notify()
end

local function AddLog(amount, reason, who)
    local db = State()
    table.insert(db.log, 1, {
        id = (UnitName("player") or "?") .. "-" .. GetServerTime() .. "-" .. math.random(1000, 9999),
        at = GetServerTime(), amount = amount, reason = reason, who = who, by = MyName(),
    })
    while #db.log > LOG_MAX do table.remove(db.log) end
end

-- =========================================================================
-- CAMBIOS (SOLO OFICIALES)
-- =========================================================================
function dkpModule.SetSystem(system)
    if not IsOfficer() or not dkpModule.SYSTEMS[system] then return false end
    local db = State()
    if db.system == system then return true end
    db.system = system
    -- Al activar el DKP, la semana en curso no aplica decay
    if system == "dkp" and db.lastWeekly == 0 then db.lastWeekly = dkpModule.GetLastWeeklyReset() end
    Touch()
    if system == "dkp" then dkpModule.UpdateSeniority() end
    return true
end

function dkpModule.SetSettings(values)
    if not IsOfficer() then return false end
    local settings = State().settings
    for key, limits in pairs(dkpModule.LIMITS) do
        local value = tonumber(values[key])
        if value then settings[key] = math.max(limits[1], math.min(limits[2], math.floor(value))) end
    end
    Touch()
    return true
end

-- Suma (o resta) DKP a una lista de jugadores
function dkpModule.Adjust(names, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if not IsOfficer() or amount == 0 or #names == 0 then return false end
    local db = State()
    for _, name in ipairs(names) do
        db.balances[name] = (db.balances[name] or 0) + amount
    end
    AddLog(amount, reason or L["Ajuste manual"], #names == 1 and names[1] or (#names .. L[" jugadores"]))
    Touch()
    return true
end

-- Paga un objeto ganado en subasta
function dkpModule.Spend(name, amount, link)
    amount = math.floor(tonumber(amount) or 0)
    if not IsOfficer() or amount <= 0 then return false end
    local db = State()
    db.balances[name] = (db.balances[name] or 0) - amount
    AddLog(-amount, link or L["Objeto"], name)
    Touch()
    return true
end

-- Miembros de la hermandad conectados en mi grupo
function dkpModule.GetGroupGuildMembers()
    local names = {}
    if not IsInGroup() then return names end
    local prefix = IsInRaid() and "raid" or "party"
    local total = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()
    if not IsInRaid() and IsInGuild() then table.insert(names, MyName()) end
    for i = 1, total do
        local unit = prefix .. i
        if UnitExists(unit) and UnitIsConnected(unit) and (UnitIsUnit(unit, "player") or (UnitIsInMyGuild and UnitIsInMyGuild(unit))) then
            local name, realm = UnitName(unit)
            if name and not (issecretvalue and issecretvalue(name)) then
                table.insert(names, NormalizeName(realm and realm ~= "" and (name .. "-" .. realm) or name))
            end
        end
    end
    return names
end

-- DKP de banda completada para los miembros de la hermandad del grupo
function dkpModule.AwardRaid()
    local amount = State().settings.raid
    local names = dkpModule.GetGroupGuildMembers()
    if #names == 0 then
        PrintGC(L["|cFFFF3333No hay miembros de la hermandad en tu grupo.|r"])
        return false
    end
    if dkpModule.Adjust(names, amount, L["Banda completada"]) then
        PrintGC(L["DKP de banda: |cFFFFD100+"] .. amount .. L["|r para "] .. #names .. L[" jugadores."])
        return true
    end
    return false
end

-- =========================================================================
-- PRECIOS DE LOS OBJETOS
-- =========================================================================
function dkpModule.GetMode() return State().settings.mode end
function dkpModule.GetPrices() return State().settings.prices end

-- Categoría de precio de un objeto (por su hueco; las piezas de set y las fichas de set van con
-- las piezas grandes)
function dkpModule.GetItemCategory(link)
    if not link or not (C_Item and C_Item.GetItemInfoInstant) then return "other" end
    local ok, _, _, _, equipLoc, _, classID = pcall(C_Item.GetItemInfoInstant, link)
    if not ok then return "other" end
    local getInfo = C_Item.GetItemInfo or GetItemInfo
    local setID = getInfo and select(16, getInfo(link))
    if setID and setID > 0 and (equipLoc == "INVTYPE_CHEST" or equipLoc == "INVTYPE_ROBE" or equipLoc == "INVTYPE_HEAD"
        or equipLoc == "INVTYPE_LEGS" or equipLoc == "INVTYPE_SHOULDER" or equipLoc == "INVTYPE_HAND") then
        return "major"
    end
    if SLOT_CATEGORY[equipLoc or ""] then return SLOT_CATEGORY[equipLoc] end
    -- Fichas de set (Misceláneo) cuentan como piezas de set
    if classID == 15 then return "major" end
    return "other"
end

-- Dificultad de la banda -> nivel de precio
function dkpModule.GetTier(difficultyID)
    if difficultyID == 16 then return "mythic" end
    if difficultyID == 15 then return "heroic" end
    return "normal"
end

-- Precio predeterminado: tabla de precios (categoría x dificultad)
function dkpModule.GetDefaultPrice(link, difficultyID)
    local category, tier = dkpModule.GetItemCategory(link), dkpModule.GetTier(difficultyID)
    local row = State().settings.prices[category] or {}
    return row[tier] or 0, category, tier
end

-- Lo que paga quien lo pide como Off-spec
function dkpModule.GetOffspecPrice(price)
    return math.floor((price or 0) * State().settings.offspec / 100 + 0.5)
end

-- ¿Puede optar al objeto? (asistencia mínima y mínimo de DKP para piezas de Mítica)
function dkpModule.CheckEligible(name, tier)
    local settings = State().settings
    if settings.minAttendance > 0 and addonTable.RaidEvents and addonTable.RaidEvents.GetAttendanceStats then
        local stats = addonTable.RaidEvents.GetAttendanceStats(nil, name)
        if stats.percent and stats.percent < settings.minAttendance then return false, "attendance" end
    end
    if tier == "mythic" and settings.gate > 0 and dkpModule.GetBalance(name) < settings.gate then
        return false, "gate"
    end
    return true
end

function dkpModule.SetMode(mode)
    if not IsOfficer() or not dkpModule.MODES[mode] then return false end
    State().settings.mode = mode
    Touch()
    return true
end

-- prices = { [categoría] = { normal, heroic, mythic } } (nil = valores recomendados)
function dkpModule.SetPrices(prices)
    if not IsOfficer() then return false end
    local settings = State().settings
    settings.prices = {}
    for _, category in ipairs(dkpModule.ITEM_CATEGORIES) do
        local source = prices and prices[category.key] or dkpModule.DEFAULT_PRICES[category.key]
        local row = {}
        for _, tier in ipairs(dkpModule.TIERS) do
            row[tier] = math.max(0, math.min(100000, math.floor(tonumber(source[tier]) or dkpModule.DEFAULT_PRICES[category.key][tier])))
        end
        settings.prices[category.key] = row
    end
    Touch()
    return true
end

-- =========================================================================
-- ANTIGÜEDAD (DESDE QUE SE RELLENA MI PERFIL)
-- =========================================================================
-- Toma la fecha de la declaración de Mi perfil de cada miembro; se queda con la más antigua
function dkpModule.UpdateSeniority()
    if not IsOfficer() or not dkpModule.IsActive() then return end
    local db = State()
    local changed = false
    local function Consider(name, at)
        at = tonumber(at)
        if not name or not at or at <= 0 then return end
        if not db.since[name] or at < db.since[name] then
            db.since[name] = at
            changed = true
        end
    end
    for fullName, m in pairs(GuildControlDB.members or {}) do
        if type(m.declared) == "table" and m.declared.main then Consider(fullName, m.declared.at) end
    end
    for fullName, profile in pairs(GuildControlDB.myProfiles or {}) do
        if profile.main then Consider(fullName, profile.firstSavedAt or profile.savedAt) end
    end
    if changed then Touch() end
end

-- =========================================================================
-- PREMIOS POR INSIGNIA
-- =========================================================================
function dkpModule.GetBadgeRewards() return State().settings.badgeRewards end

function dkpModule.GetBadgeReward(key)
    local amount = State().settings.badgeRewards[key]
    return amount and amount > 0 and amount or nil
end

function dkpModule.SetBadgeReward(key, amount)
    if not IsOfficer() or not dkpModule.DEFAULT_BADGE_REWARDS[key] then return false end
    State().settings.badgeRewards[key] = math.max(0, math.min(1000, math.floor(tonumber(amount) or 0)))
    Touch()
    return true
end

function dkpModule.RemoveBadgeReward(key)
    if not IsOfficer() then return false end
    State().settings.badgeRewards[key] = nil
    Touch()
    return true
end

function dkpModule.ResetBadgeRewards()
    if not IsOfficer() then return false end
    local rewards = {}
    for key, value in pairs(dkpModule.DEFAULT_BADGE_REWARDS) do rewards[key] = value end
    State().settings.badgeRewards = rewards
    Touch()
    return true
end

-- Los premios los da un solo oficial: el primero por orden alfabético de los oficiales
-- conectados que usan GuildControl (así no se dan dos veces antes de sincronizar)
local function IsBadgeAwarder()
    local me = MyName()
    for name, m in pairs(GuildControlDB.members or {}) do
        if name < me and m.isOnline and IsOfficerName(name) and addonTable.GetAddonUser and addonTable.GetAddonUser(name) then
            return false
        end
    end
    return true
end

-- Da el premio de cada insignia nueva (una vez por jugador e insignia)
function dkpModule.ApplyBadgeRewards()
    if not IsOfficer() or not dkpModule.IsActive() or not IsBadgeAwarder() then return end
    local PM = addonTable.Personal
    if not (PM and PM.GetBadges and PM.BADGES) then return end
    local db = State()
    local given = {}   -- [clave de insignia] = nº de jugadores premiados
    for name in pairs(GuildControlDB.members or {}) do
        for _, badge in ipairs(PM.GetBadges(name)) do
            local amount = dkpModule.GetBadgeReward(badge.key)
            local awardKey = name .. ":" .. badge.key
            if amount and not db.badgeAwards[awardKey] then
                db.badgeAwards[awardKey] = 1
                db.balances[name] = (db.balances[name] or 0) + amount
                given[badge.key] = (given[badge.key] or 0) + 1
            end
        end
    end
    local changed = false
    for _, badge in ipairs(PM.BADGES) do
        local count = given[badge.key]
        if count then
            AddLog(dkpModule.GetBadgeReward(badge.key), L["Insignia: "] .. L[badge.label], count .. L[" jugadores"])
            changed = true
        end
    end
    if changed then Touch() end
end

-- =========================================================================
-- SEMANAL: DECAY Y DKP POR ANTIGÜEDAD
-- =========================================================================
function dkpModule.GetLastWeeklyReset()
    if addonTable.MythicPlus and addonTable.MythicPlus.GetLastWeeklyReset then
        local reset = addonTable.MythicPlus.GetLastWeeklyReset()
        if reset and reset > 0 then return reset end
    end
    local untilReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
    if not untilReset then return 0 end
    return GetServerTime() + untilReset - WEEK
end

local function ApplyWeekly()
    if not IsOfficer() then return end
    local db = State()
    if db.system ~= "dkp" then return end
    local reset = dkpModule.GetLastWeeklyReset()
    if reset == 0 or db.lastWeekly >= reset - 60 then return end
    if db.lastWeekly == 0 then
        db.lastWeekly = reset
        Touch()
        return
    end
    -- 1. Decay: cada saldo positivo pierde el % configurado
    local decay = db.settings.decay
    if decay > 0 then
        for name, balance in pairs(db.balances) do
            if balance > 0 then db.balances[name] = math.floor(balance * (100 - decay) / 100) end
        end
        AddLog(0, L["Decay semanal "] .. decay .. "%", L["Todos"])
    end
    -- 2. Antigüedad: DKP para quien ya tenía Mi perfil rellenado antes del reinicio
    local bonus = db.settings.seniority
    if bonus > 0 then
        local count = 0
        for name, since in pairs(db.since) do
            if since < reset and (GuildControlDB.members or {})[name] then
                db.balances[name] = (db.balances[name] or 0) + bonus
                count = count + 1
            end
        end
        if count > 0 then AddLog(bonus, L["Antigüedad semanal"], count .. L[" jugadores"]) end
    end
    db.lastWeekly = reset
    Touch()
end

-- =========================================================================
-- DKP POR JEFE
-- =========================================================================
-- Da los puntos un solo cliente: el líder si es oficial; si no, el primer oficial del grupo
-- por orden alfabético
local function IsAwarder()
    if not IsOfficer() or not IsInRaid() then return false end
    if UnitIsGroupLeader("player") then return true end
    local officers = {}
    for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        local name, realm = UnitName(unit)
        if name and not (issecretvalue and issecretvalue(name)) and UnitIsConnected(unit) then
            local fullName = NormalizeName(realm and realm ~= "" and (name .. "-" .. realm) or name)
            if UnitIsGroupLeader(unit) and IsOfficerName(fullName) then return false end
            if IsOfficerName(fullName) then table.insert(officers, fullName) end
        end
    end
    table.sort(officers)
    return officers[1] == MyName()
end

local function OnEncounterEnd(encounterID, encounterName, difficultyID, _, success)
    if issecretvalue and (issecretvalue(encounterID) or issecretvalue(encounterName) or issecretvalue(success)) then return end
    if success ~= 1 and success ~= true then return end
    local db = State()
    if db.system ~= "dkp" or db.settings.boss <= 0 or not encounterID then return end
    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "raid" or not IsAwarder() then return end
    -- Solo cuentan los jefes de una banda programada en el addon (Raid)
    local E = addonTable.RaidEvents
    local event = E and E.FindActiveEvent and E.FindActiveEvent(encounterID, difficultyID)
    if not event then return end
    local key = event.id .. ":" .. encounterID
    if db.bossKeys[key] then return end
    local limit = GetServerTime() - BOSS_KEY_DAYS * 86400
    for k, at in pairs(db.bossKeys) do
        if at < limit then db.bossKeys[k] = nil end
    end
    db.bossKeys[key] = GetServerTime()
    local names = dkpModule.GetGroupGuildMembers()
    if #names > 0 then
        dkpModule.Adjust(names, db.settings.boss, L["Jefe: "] .. tostring(encounterName or "?") .. " (" .. event.title .. ")")
        PrintGC(L["DKP por jefe: |cFFFFD100+"] .. db.settings.boss .. L["|r para "] .. #names .. L[" jugadores."])
    end
end

-- =========================================================================
-- RECEPCIÓN
-- =========================================================================
local function Num(value, low, high, default)
    value = tonumber(value)
    if not value then return default end
    value = math.floor(value)
    if low and value < low then value = low end
    if high and value > high then value = high end
    return value
end

local function CleanText(text, maxLen)
    return string.sub(string.gsub(tostring(text or ""), "[;]", ""), 1, maxLen)
end

local function ApplyIncoming(payload, sender)
    if type(payload) ~= "table" or payload.version ~= 1 then return end
    local db = State()
    local updatedAt = tonumber(payload.updatedAt) or 0
    if updatedAt <= db.updatedAt then return end
    db.system = dkpModule.SYSTEMS[payload.system] and payload.system or db.system
    if type(payload.settings) == "table" then
        for key, limits in pairs(dkpModule.LIMITS) do
            db.settings[key] = Num(payload.settings[key], limits[1], limits[2], db.settings[key])
        end
        if dkpModule.MODES[payload.settings.mode] then db.settings.mode = payload.settings.mode end
        if type(payload.settings.prices) == "table" then
            for _, category in ipairs(dkpModule.ITEM_CATEGORIES) do
                local row = payload.settings.prices[category.key]
                if type(row) == "table" then
                    for _, tier in ipairs(dkpModule.TIERS) do
                        db.settings.prices[category.key][tier] = Num(row[tier], 0, 100000, db.settings.prices[category.key][tier])
                    end
                end
            end
        end
        -- Premios por insignia (solo las claves conocidas; las que faltan se quitaron)
        if type(payload.settings.badgeRewards) == "table" then
            local rewards = {}
            for key in pairs(dkpModule.DEFAULT_BADGE_REWARDS) do
                if tonumber(payload.settings.badgeRewards[key]) then rewards[key] = Num(payload.settings.badgeRewards[key], 0, 1000, 0) end
            end
            db.settings.badgeRewards = rewards
        end
    end
    if type(payload.badgeAwards) == "table" then
        local awards = {}
        for key in pairs(payload.badgeAwards) do
            if type(key) == "string" then awards[string.sub(key, 1, 80)] = 1 end
        end
        -- Se unen con los propios: un premio dado no se pierde
        for key in pairs(db.badgeAwards) do awards[key] = 1 end
        db.badgeAwards = awards
    end
    local balances, since, bossKeys = {}, {}, {}
    for name, value in pairs(type(payload.balances) == "table" and payload.balances or {}) do
        if type(name) == "string" and tonumber(value) then balances[string.sub(name, 1, 60)] = Num(value, -100000, 100000, 0) end
    end
    for name, value in pairs(type(payload.since) == "table" and payload.since or {}) do
        if type(name) == "string" and tonumber(value) then since[string.sub(name, 1, 60)] = Num(value, 0) end
    end
    for key, value in pairs(type(payload.bossKeys) == "table" and payload.bossKeys or {}) do
        if type(key) == "string" and tonumber(value) then bossKeys[string.sub(key, 1, 90)] = Num(value, 0) end
    end
    db.balances, db.since, db.bossKeys = balances, since, bossKeys
    db.lastWeekly = Num(payload.lastWeekly, 0, nil, db.lastWeekly)
    db.updatedAt = updatedAt
    -- Historial: se añaden las entradas que no estaban
    local known = {}
    for _, entry in ipairs(db.log) do known[entry.id or ""] = true end
    for _, entry in ipairs(type(payload.log) == "table" and payload.log or {}) do
        if type(entry) == "table" and type(entry.id) == "string" and not known[entry.id] then
            table.insert(db.log, { id = string.sub(entry.id, 1, 60), at = Num(entry.at, 0, nil, 0), amount = Num(entry.amount, -100000, 100000, 0),
                reason = CleanText(entry.reason, 120), who = CleanText(entry.who, 60), by = CleanText(entry.by or sender, 60) })
        end
    end
    table.sort(db.log, function(a, b) return (a.at or 0) > (b.at or 0) end)
    while #db.log > LOG_MAX do table.remove(db.log) end
    Notify()
end

local partials = {}
local function OnChunk(sender, msg)
    local msgId, index, total, chunk = string.match(msg, "^D(%d+):(%d+):(%d+):(.*)$")
    index, total = tonumber(index), tonumber(total)
    if not msgId or not index or not total or total > 400 then return end
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
    if not IsOfficerName(sender) then return end
    local R = addonTable.Roster
    local payload = R and R.DeserializeTable and R.DeserializeTable(table.concat(partial.parts))
    ApplyIncoming(payload, sender)
end

-- =========================================================================
-- EVENTOS
-- =========================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if not GuildControlDB then return end
    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if not (isInitialLogin or isReloadingUi) then return end
        C_Timer.After(20, function()
            if IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(PREFIX, "Q", "GUILD") end
        end)
        -- Antigüedad y semanal: después de recibir el estado de otro oficial. Con el sistema +1
        -- no se hace nada (el DKP queda en reposo hasta que un oficial lo active).
        local function Periodic()
            if not dkpModule.IsActive() or not IsOfficer() then return end
            dkpModule.UpdateSeniority()
            ApplyWeekly()
            dkpModule.ApplyBadgeRewards()
        end
        C_Timer.After(45, Periodic)
        C_Timer.NewTicker(600, Periodic)
    elseif event == "ENCOUNTER_END" then
        OnEncounterEnd(...)
    else
        local prefix, msg, channel, sender = ...
        if prefix ~= PREFIX or channel ~= "GUILD" or not msg or not sender then return end
        if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
        if addonTable.IsMe(sender) then return end
        local fullSender = NormalizeName(sender)
        if msg == "Q" then
            -- Responde un oficial (el que espere menos); los demás se callan al ver su envío
            if not IsOfficer() or replyTimer or State().updatedAt == 0 then return end
            replyTimer = C_Timer.NewTimer(2 + math.random() * 5, function()
                replyTimer = nil
                dkpModule.Publish()
            end)
        elseif string.sub(msg, 1, 1) == "D" then
            OnChunk(fullSender, msg)
        end
    end
end)
