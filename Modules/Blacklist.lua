local addonName, addonTable = ...
local L = addonTable.L

addonTable.Blacklist = {}
local blacklistModule = addonTable.Blacklist

-- Lista negra de personajes no deseados (ninjas, racistas, tóxicos...). Sin frames.
-- GuildControlDB.blacklist[clave] = { name = "Nombre-Reino", reason, note, addedBy, date, sharedBy }
-- La clave es el nombre normalizado en minúsculas.
--
-- Avisos: al entrar en la hermandad o en tu grupo, en el tooltip del personaje, y se
-- bloquean las invitaciones a la hermandad (individual y masiva).

local SHARE_PREFIX = "GuildControlBL"
local SHARE_INTERVAL = 0.3

blacklistModule.REASONS = {
    { key = "ninja",  label = "Ninja (botín)" },
    { key = "racism", label = "Racismo" },
    { key = "toxic",  label = "Tóxico" },
    { key = "scam",   label = "Estafa" },
    { key = "other",  label = "Otro" },
}
local REASON_LABELS = {}
for _, r in ipairs(blacklistModule.REASONS) do REASON_LABELS[r.key] = r.label end

local listeners = {}
local alertedThisSession = {}

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(SHARE_PREFIX)
end

-- =========================================================================
-- UTILIDADES
-- =========================================================================
local function Store()
    if type(GuildControlDB.blacklist) ~= "table" then GuildControlDB.blacklist = {} end
    return GuildControlDB.blacklist
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function Normalize(name)
    if not name or IsSecret(name) then return nil end
    return addonTable.NormalizeName(name)   -- Core: "Nombre-Reino" sin apellido
end
blacklistModule.Normalize = Normalize

local function Key(name)
    local normalized = Normalize(name)
    return normalized and string.lower(normalized) or nil
end

local function Clean(text, maxLen)
    text = strtrim(tostring(text or ""))
    text = string.gsub(text, "[|;]", "")
    return string.sub(text, 1, maxLen)
end

local function Notify()
    for _, fn in ipairs(listeners) do fn() end
end

function blacklistModule.AddListener(fn)
    table.insert(listeners, fn)
end

function blacklistModule.GetReasonLabel(key)
    return L[REASON_LABELS[key or ""] or REASON_LABELS.other]
end

local function Alert(text)
    print("|cFF00FFFF[GuildControl]|r |cFFFF3333" .. text .. "|r")
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
end

-- =========================================================================
-- DATOS
-- =========================================================================
function blacklistModule.Get(name)
    local key = Key(name)
    return key and Store()[key] or nil
end

function blacklistModule.IsBlacklisted(name)
    return blacklistModule.Get(name) ~= nil
end

-- Devuelve la entrada o nil y un mensaje de error
function blacklistModule.Add(name, reason, note, addedBy, sharedBy, dateText)
    local normalized = Normalize(name)
    if not normalized or not string.find(normalized, "^[^%-]+%-.+$") then
        return nil, L["Escribe el nombre del personaje (Nombre o Nombre-Reino)."]
    end
    local entry = {
        name = normalized,
        reason = REASON_LABELS[reason] and reason or "other",
        note = Clean(note, 120),
        addedBy = Clean(addedBy or UnitName("player"), 40),
        date = dateText or date("%Y-%m-%d"),
        sharedBy = sharedBy,
    }
    Store()[string.lower(normalized)] = entry
    Notify()
    return entry
end

function blacklistModule.Remove(name)
    local key = Key(name)
    if key and Store()[key] then
        Store()[key] = nil
        Notify()
        return true
    end
    return false
end

-- Lista ordenada (más recientes primero), filtrada por texto en nombre, motivo o nota
function blacklistModule.GetAll(query)
    query = string.lower(strtrim(query or ""))
    local list = {}
    for _, entry in pairs(Store()) do
        local text = string.lower(entry.name .. " " .. blacklistModule.GetReasonLabel(entry.reason) .. " " .. (entry.note or ""))
        if query == "" or string.find(text, query, 1, true) then table.insert(list, entry) end
    end
    table.sort(list, function(a, b)
        if a.date ~= b.date then return a.date > b.date end
        return a.name < b.name
    end)
    return list
end

-- Cuántos de la lista negra están ahora mismo en la hermandad
function blacklistModule.CountInGuild()
    local count = 0
    for fullName in pairs(GuildControlDB.members or {}) do
        if blacklistModule.IsBlacklisted(fullName) then count = count + 1 end
    end
    return count
end

-- =========================================================================
-- AVISOS
-- =========================================================================
-- Core la llama cuando detecta una alta en la hermandad
function blacklistModule.CheckJoin(fullName)
    local entry = blacklistModule.Get(fullName)
    if entry then
        Alert(fullName .. L[" (lista negra: "] .. blacklistModule.GetReasonLabel(entry.reason) .. L[") ha entrado en la hermandad."])
    end
end

local function CheckGroup()
    if not IsInGroup() or type(GuildControlDB.blacklist) ~= "table" or next(GuildControlDB.blacklist) == nil then return end
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do table.insert(units, "raid" .. i) end
    else
        for i = 1, GetNumSubgroupMembers() do table.insert(units, "party" .. i) end
    end
    for _, unit in ipairs(units) do
        local name, realm = UnitName(unit)
        if name and not IsSecret(name) and not IsSecret(realm) then
            local full = (realm and realm ~= "") and (name .. "-" .. realm) or name
            local entry = blacklistModule.Get(full)
            local key = Key(full)
            if entry and key and not alertedThisSession[key] then
                alertedThisSession[key] = true
                Alert(full .. L[" está en tu grupo y figura en la lista negra ("] .. blacklistModule.GetReasonLabel(entry.reason) .. ").")
            end
        end
    end
end

-- Línea en el tooltip de los personajes de la lista negra
local function HookTooltip()
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if not GuildControlDB or tooltip ~= GameTooltip then return end
        local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
        if not ok or not unit or IsSecret(unit) or not UnitIsPlayer(unit) then return end
        local name, realm = UnitName(unit)
        if not name or IsSecret(name) or IsSecret(realm) then return end
        local entry = blacklistModule.Get((realm and realm ~= "") and (name .. "-" .. realm) or name)
        if entry then
            tooltip:AddLine(L["[GuildControl] Lista negra: "] .. blacklistModule.GetReasonLabel(entry.reason), 1, 0.2, 0.2)
            if entry.note and entry.note ~= "" then tooltip:AddLine(entry.note, 1, 0.5, 0.5, true) end
        end
    end)
end

-- =========================================================================
-- COMPARTIR CON OTROS OFICIALES
-- =========================================================================
-- "A;Nombre-Reino;motivo;nota;añadidoPor;fecha" por entrada. Solo se aceptan de oficiales
-- y solo se añaden entradas nuevas (nunca se borra nada de otro cliente).
local shareTicker = nil
local receivedFrom = {}

function blacklistModule.Share()
    if not IsInGuild() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) or shareTicker then return 0 end
    local queue = {}
    for _, entry in pairs(Store()) do
        table.insert(queue, table.concat({ "A", entry.name, entry.reason, entry.note or "", entry.addedBy or "", entry.date or "" }, ";"))
    end
    if #queue == 0 then return 0 end
    local total = #queue
    shareTicker = C_Timer.NewTicker(SHARE_INTERVAL, function()
        local msg = table.remove(queue, 1)
        if msg then C_ChatInfo.SendAddonMessage(SHARE_PREFIX, msg, "GUILD") end
        if #queue == 0 then
            shareTicker:Cancel()
            shareTicker = nil
        end
    end)
    return total
end

-- =========================================================================
-- EVENTOS
-- =========================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        HookTooltip()
        return
    end
    if not GuildControlDB then return end

    if event == "GROUP_ROSTER_UPDATE" then
        CheckGroup()
        return
    end

    local prefix, msg, channel, sender = ...
    if prefix ~= SHARE_PREFIX or channel ~= "GUILD" then return end
    if IsSecret(msg) or IsSecret(sender) or not msg or not sender then return end
    if addonTable.IsMe(sender) then return end
    -- Solo se aceptan entradas de oficiales (según el rango configurado en este cliente)
    if not (addonTable.Profiles and addonTable.Profiles.IsOfficerName(sender)) then return end

    local kind, name, reason, note, addedBy, dateText = strsplit(";", msg)
    if kind ~= "A" or not name or blacklistModule.IsBlacklisted(name) then return end
    if blacklistModule.Add(name, reason, note, addedBy, short, dateText) then
        if not receivedFrom[short] then
            receivedFrom[short] = true
            print("|cFF00FFFF[GuildControl]|r |cFFFFD100" .. short .. L["|r ha compartido entradas de la lista negra."])
        end
    end
end)
