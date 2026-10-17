local addonName, addonTable = ...
local L = addonTable.L

addonTable.RaidTools = {}
local toolsModule = addonTable.RaidTools

-- Herramientas de banda (sin frames): comprobación de listos, cuenta atrás de pull y buff
-- check. Las marcas no están aquí: SetRaidTarget está protegida y se ponen con botones
-- seguros en UI.lua. La UI (modo minimalista y ventana de buffos) está en UI.lua.
--
-- Buff check: los buffos se leen de las auras de cada integrante (fuera de combate; en
-- combate el juego puede ocultarlas). Lo que llevan en las bolsas (pociones, frascos, comida,
-- runas o pergaminos) solo se sabe de quien usa GuildControl: al pedirlo, cada cliente cuenta
-- sus bolsas y lo envía al grupo con el prefijo GuildControlBuff:
--   "Q"                                   petición (la manda quien pulsa Buff check)
--   "C;pociones;frascos;comida;runas"     respuesta de cada cliente
-- Las respuestas se guardan en memoria (no en SavedVariables) en reports[Nombre-Reino].

local PREFIX = "GuildControlBuff"
local REPLY_JITTER = 1.5

local listeners = {}
local reports = {}      -- [Nombre-Reino] = { potions, flasks, food, runes, at }

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local function PrintGC(msg)
    print("|cFF00FFFF[GuildControl]|r " .. msg)
end

local function Notify()
    for _, fn in ipairs(listeners) do fn() end
end

function toolsModule.AddListener(fn)
    table.insert(listeners, fn)
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function FullName(name, realm)
    if not name then return nil end
    return addonTable.NormalizeName((realm and realm ~= "") and (name .. "-" .. realm) or name)
end

local function GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

local function SendGroup(msg)
    local channel = GroupChannel()
    if channel and C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(PREFIX, msg, channel) end
end

-- =========================================================================
-- MANDO DE LA BANDA: LISTOS, PULL Y MARCAS
-- =========================================================================
-- En banda hace falta ser líder o ayudante; en grupo, el juego decide (y avisa si no puede)
local function CanLead()
    if not IsInGroup() then
        PrintGC(L["|cFFFF3333No estás en un grupo.|r"])
        return false
    end
    if IsInRaid() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        PrintGC(L["|cFFFF3333Necesitas ser líder o ayudante de la banda.|r"])
        return false
    end
    return true
end

function toolsModule.ReadyCheck()
    if not CanLead() then return end
    if DoReadyCheck then DoReadyCheck() end
end

-- Cuenta atrás del juego (la misma que /countdown); 0 la cancela
function toolsModule.Pull(seconds)
    if not CanLead() then return end
    if C_PartyInfo and C_PartyInfo.DoCountdown then
        C_PartyInfo.DoCountdown(seconds or 0)
    else
        PrintGC(L["|cFFFF3333Este cliente no tiene la cuenta atrás del juego.|r"])
    end
end

function toolsModule.CancelPull()
    toolsModule.Pull(0)
end

-- Descanso: aviso de banda al empezar, a falta de 1 minuto y al terminar. La duración (en
-- minutos) se configura en Configuración (settings.breakMinutes, 5 por defecto). Pulsarlo
-- con un descanso en marcha lo cancela.
toolsModule.BREAK_DEFAULT, toolsModule.BREAK_MIN, toolsModule.BREAK_MAX = 5, 1, 30
local breakTimers = {}

function toolsModule.GetBreakMinutes()
    local value = GuildControlDB and GuildControlDB.settings and tonumber(GuildControlDB.settings.breakMinutes)
    return math.max(toolsModule.BREAK_MIN, math.min(toolsModule.BREAK_MAX, math.floor(value or toolsModule.BREAK_DEFAULT)))
end

function toolsModule.IsOnBreak()
    return #breakTimers > 0
end

function toolsModule.Break()
    if not CanLead() then return end
    local channel = (IsInRaid() and "RAID_WARNING") or "PARTY"
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local function Say(text) send(text, channel) end
    if #breakTimers > 0 then
        for _, timer in ipairs(breakTimers) do timer:Cancel() end
        wipe(breakTimers)
        Say(L["Descanso cancelado"])
        Notify()
        return
    end
    local minutes = toolsModule.GetBreakMinutes()
    Say(string.format(L["Descanso de %d minutos. Volvemos a las %s."], minutes, date("%H:%M", time() + minutes * 60)))
    if minutes > 1 then
        table.insert(breakTimers, C_Timer.NewTimer((minutes - 1) * 60, function() Say(L["Queda 1 minuto de descanso."]) end))
    end
    table.insert(breakTimers, C_Timer.NewTimer(minutes * 60, function()
        wipe(breakTimers)
        Say(L["¡Fin del descanso! Todos a sus puestos."])
        Notify()
    end))
    Notify()
end

-- =========================================================================
-- CONSUMIBLES EN LAS BOLSAS (SOLO EL PROPIO PERSONAJE)
-- =========================================================================
-- Subclases de consumibles (Enum.ItemConsumableSubclass): 1 poción, 3 frascos y viales,
-- 4 pergaminos, 5 comida y bebida, 8 otros (las runas de aumento)
local SUB_POTION, SUB_FLASK, SUB_SCROLL, SUB_FOOD, SUB_OTHER = 1, 3, 4, 5, 8
local RUNE_WORDS = { "augment", "aumento" }

local function HasWord(text, words)
    if not text or text == "" then return false end
    text = string.lower(text)
    for _, word in ipairs(words) do
        if string.find(text, word, 1, true) then return true end
    end
    return false
end

function toolsModule.CountMyConsumables()
    local counts = { potions = 0, flasks = 0, food = 0, runes = 0 }
    if not (C_Container and C_Container.GetContainerNumSlots and C_Item and C_Item.GetItemInfoInstant) then return counts end
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5   -- bolsas 0-4 y la de componentes
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(info.itemID)
                local stack = info.stackCount or 1
                if classID == 0 then
                    if subclassID == SUB_POTION then counts.potions = counts.potions + stack
                    elseif subclassID == SUB_FLASK then counts.flasks = counts.flasks + stack
                    elseif subclassID == SUB_FOOD then counts.food = counts.food + stack
                    elseif subclassID == SUB_SCROLL then counts.runes = counts.runes + stack
                    elseif subclassID == SUB_OTHER and HasWord(C_Item.GetItemNameByID and C_Item.GetItemNameByID(info.itemID), RUNE_WORDS) then
                        counts.runes = counts.runes + stack
                    end
                end
            end
        end
    end
    return counts
end

-- =========================================================================
-- BUFFOS DE CADA INTEGRANTE
-- =========================================================================
-- Buffos de banda: se buscan por el nombre del hechizo (vale en cualquier idioma y para las
-- variantes de Bendición del bronce) y solo cuentan si en el grupo hay una clase que lo da.
toolsModule.RAID_BUFFS = {
    { key = "int", spellID = 1459, class = "MAGE" },          -- Intelecto Arcano
    { key = "stamina", spellID = 21562, class = "PRIEST" },   -- Palabra de poder: entereza
    { key = "ap", spellID = 6673, class = "WARRIOR" },        -- Grito de batalla
    { key = "versatility", spellID = 1126, class = "DRUID" }, -- Marca de lo Salvaje
    { key = "bronze", spellID = 381748, class = "EVOKER" },   -- Bendición del bronce
    { key = "skyfury", spellID = 462854, class = "SHAMAN" },  -- Furia del cielo
}

local FLASK_WORDS = { "flask", "phial", "frasco", "vial" }
local FOOD_WORDS = { "well fed", "bien alimentad" }

local function SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
    return GetSpellInfo and (GetSpellInfo(spellID)) or nil
end

function toolsModule.GetBuffInfo(key)
    for _, buff in ipairs(toolsModule.RAID_BUFFS) do
        if buff.key == key then
            local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(buff.spellID) or nil
            return SpellName(buff.spellID) or key, icon
        end
    end
end

-- Lee las auras de una unidad. Devuelve nil si no se pueden leer (fuera de alcance o en
-- combate con valores secretos).
local function ScanUnit(unit)
    if not UnitIsConnected(unit) or not UnitIsVisible(unit) then return nil end
    local result = { buffs = {}, flask = false, food = false, rune = false }
    local buffNames = {}
    for _, buff in ipairs(toolsModule.RAID_BUFFS) do
        local name = SpellName(buff.spellID)
        if name then buffNames[name] = buff.key end
    end
    local foodName = SpellName(19705)   -- "Bien alimentado"
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    for i = 1, 255 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok or not aura then break end
        local name = aura.name
        if IsSecret(name) then return nil end
        if name then
            if buffNames[name] then result.buffs[buffNames[name]] = true end
            if HasWord(name, FLASK_WORDS) then result.flask = true end
            if name == foodName or HasWord(name, FOOD_WORDS) then result.food = true end
            if HasWord(name, RUNE_WORDS) then result.rune = true end
        end
    end
    return result
end

local function GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do table.insert(units, "raid" .. i) end
    else
        table.insert(units, "player")
        for i = 1, GetNumSubgroupMembers() do table.insert(units, "party" .. i) end
    end
    return units
end

-- Lista del grupo con sus buffos:
--   { {fullName, short, class, group, online, scan = {buffs, flask, food, rune} | nil, report}, ... }
-- y las claves de buffos de banda que alguien del grupo puede dar.
function toolsModule.GetGroupStatus()
    local members, classes = {}, {}
    for index, unit in ipairs(GroupUnits()) do
        local name, realm = UnitName(unit)
        if name and not IsSecret(name) and name ~= UNKNOWNOBJECT then
            local _, class = UnitClass(unit)
            local group = 1
            if IsInRaid() then group = select(3, GetRaidRosterInfo(index)) or 1 end
            local fullName = FullName(name, realm)
            local entry = {
                fullName = fullName, short = name, class = class, group = group,
                online = UnitIsConnected(unit), scan = ScanUnit(unit),
                report = reports[fullName],
            }
            if UnitIsUnit(unit, "player") then
                local own = toolsModule.CountMyConsumables()
                own.at = GetTime()
                entry.report = own
            end
            if class then classes[class] = true end
            table.insert(members, entry)
        end
    end
    table.sort(members, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.short < b.short
    end)
    local available = {}
    for _, buff in ipairs(toolsModule.RAID_BUFFS) do
        if classes[buff.class] then table.insert(available, buff.key) end
    end
    return members, available
end

-- Pide a los demás clientes lo que llevan en las bolsas
function toolsModule.RequestReports()
    wipe(reports)
    SendGroup("Q")
    Notify()
end

local function SendReport()
    local c = toolsModule.CountMyConsumables()
    SendGroup(table.concat({ "C", c.potions, c.flasks, c.food, c.runes }, ";"))
end

-- =========================================================================
-- EVENTOS
-- =========================================================================
local replyTimer = nil
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, prefix, msg, channel, sender)
    if prefix ~= PREFIX or not msg or not sender then return end
    if IsSecret(msg) or IsSecret(sender) then return end
    if channel ~= "RAID" and channel ~= "PARTY" and channel ~= "INSTANCE_CHAT" then return end
    local short, realm = strsplit("-", sender, 2)
    local fullName = FullName(short, realm)
    if addonTable.IsMe(sender) then return end

    if msg == "Q" then
        -- Pequeño retraso para no responder todos a la vez
        if replyTimer then replyTimer:Cancel() end
        replyTimer = C_Timer.NewTimer(math.random() * REPLY_JITTER, function()
            replyTimer = nil
            SendReport()
        end)
    elseif string.sub(msg, 1, 2) == "C;" then
        local _, potions, flasks, food, runes = strsplit(";", msg)
        reports[fullName] = {
            potions = tonumber(potions) or 0, flasks = tonumber(flasks) or 0,
            food = tonumber(food) or 0, runes = tonumber(runes) or 0, at = GetTime(),
        }
        Notify()
    end
end)
