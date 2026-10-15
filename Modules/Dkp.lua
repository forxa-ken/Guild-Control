local addonName, addonTable = ...
local L = addonTable.L

addonTable.Dkp = {}
local dkpModule = addonTable.Dkp

-- Sistema DKP (sin frames). Lo llevan los oficiales y se comparte con toda la hermandad.
--   - Se gana DKP por cada jefe de banda derrotado (los miembros de la hermandad presentes),
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
dkpModule.DEFAULTS = { boss = 10, raid = 20, seniority = 5, decay = 10, minBid = 1 }
dkpModule.LIMITS = { boss = { 0, 1000 }, raid = { 0, 1000 }, seniority = { 0, 1000 }, decay = { 0, 90 }, minBid = { 1, 1000 } }

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
-- ANTIGÜEDAD (DESDE QUE SE RELLENA MI PERFIL)
-- =========================================================================
-- Toma la fecha de la declaración de Mi perfil de cada miembro; se queda con la más antigua
function dkpModule.UpdateSeniority()
    if not IsOfficer() then return end
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
    local key = encounterID .. ":" .. (difficultyID or 0) .. ":" .. date("%Y%m%d", GetServerTime())
    if db.bossKeys[key] then return end
    local limit = GetServerTime() - BOSS_KEY_DAYS * 86400
    for k, at in pairs(db.bossKeys) do
        if at < limit then db.bossKeys[k] = nil end
    end
    db.bossKeys[key] = GetServerTime()
    local names = dkpModule.GetGroupGuildMembers()
    if #names > 0 then
        dkpModule.Adjust(names, db.settings.boss, L["Jefe: "] .. tostring(encounterName or "?"))
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
    end
    local balances, since, bossKeys = {}, {}, {}
    for name, value in pairs(type(payload.balances) == "table" and payload.balances or {}) do
        if type(name) == "string" and tonumber(value) then balances[string.sub(name, 1, 60)] = Num(value, -100000, 100000, 0) end
    end
    for name, value in pairs(type(payload.since) == "table" and payload.since or {}) do
        if type(name) == "string" and tonumber(value) then since[string.sub(name, 1, 60)] = Num(value, 0) end
    end
    for key, value in pairs(type(payload.bossKeys) == "table" and payload.bossKeys or {}) do
        if type(key) == "string" and tonumber(value) then bossKeys[string.sub(key, 1, 40)] = Num(value, 0) end
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
        -- Antigüedad y semanal: después de recibir el estado de otro oficial
        C_Timer.After(45, function()
            dkpModule.UpdateSeniority()
            ApplyWeekly()
        end)
        C_Timer.NewTicker(600, function()
            dkpModule.UpdateSeniority()
            ApplyWeekly()
        end)
    elseif event == "ENCOUNTER_END" then
        OnEncounterEnd(...)
    else
        local prefix, msg, channel, sender = ...
        if prefix ~= PREFIX or channel ~= "GUILD" or not msg or not sender then return end
        if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
        if Ambiguate(sender, "none") == UnitName("player") then return end
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
