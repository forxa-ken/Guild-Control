local addonName, addonTable = ...
local L = addonTable.L

addonTable.MythicPlus = {}
local mplusModule = addonTable.MythicPlus

-- Datos de Míticas+ (sin frames):
--   - Puntuación M+ de cada miembro: viene de la comunidad de hermandad (C_Club,
--     overallDungeonScore) y se guarda en member.mplusScore.
--   - Llave de cada miembro: solo de quien usa GuildControl; se envía con el prefijo
--     GuildControlKey ("K;mapID;nivel") y se guarda en GuildControlDB.keystones[nombre]
--     (aparte de members, para no perderla si el miembro aún no está en la lista).
--   - Afijos de la semana y mejores tiempos propios: API C_MythicPlus / C_ChallengeMode.

local KEY_PREFIX = "GuildControlKey"
local BROADCAST_COOLDOWN = 15
local REQUEST_COOLDOWN = 60

local listeners = {}
local lastBroadcast = -BROADCAST_COOLDOWN
local lastSentKey = nil
local lastRequest = -REQUEST_COOLDOWN

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(KEY_PREFIX)
end

local function Notify()
    for _, fn in ipairs(listeners) do fn() end
end

function mplusModule.AddListener(fn)
    table.insert(listeners, fn)
end

local function NormalizeName(name)
    if addonTable.Profiles and addonTable.Profiles.NormalizeName then return addonTable.Profiles.NormalizeName(name) end
    return name
end

-- =========================================================================
-- PUNTUACIÓN DE LOS MIEMBROS (C_Club)
-- =========================================================================
-- Recorre C_Club como mucho una vez por minuto (force = true al abrir la pestaña, si han
-- pasado 10 s): lo llama Core en cada escaneo de la lista
local SCORE_COOLDOWN, SCORE_FORCED_COOLDOWN = 60, 10
local lastScoreUpdate = -SCORE_COOLDOWN
function mplusModule.UpdateScores(force)
    local elapsed = GetTime() - lastScoreUpdate
    if elapsed < (force and SCORE_FORCED_COOLDOWN or SCORE_COOLDOWN) then return false end
    lastScoreUpdate = GetTime()
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers and C_Club.GetMemberInfo) then return false end
    local clubId = C_Club.GetGuildClubId()
    if not clubId then return false end
    local ok, memberIds = pcall(C_Club.GetClubMembers, clubId)
    if not ok or type(memberIds) ~= "table" then return false end

    local scoreByGuid = {}
    for _, memberId in ipairs(memberIds) do
        local okInfo, info = pcall(C_Club.GetMemberInfo, clubId, memberId)
        if okInfo and info and info.guid and info.overallDungeonScore then
            scoreByGuid[info.guid] = info.overallDungeonScore
        end
    end
    for _, m in pairs(GuildControlDB.members or {}) do
        if m.guid and scoreByGuid[m.guid] then m.mplusScore = scoreByGuid[m.guid] end
    end
    return true
end

-- Color de rareza de una puntuación (gris, verde, azul, morado, naranja...)
function mplusModule.ScoreColorHex(score)
    if C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and score and score > 0 then
        local ok, color = pcall(C_ChallengeMode.GetDungeonScoreRarityColor, score)
        if ok and color and color.GenerateHexColor then return string.sub(color:GenerateHexColor(), -6) end
    end
    return "BFBFBF"
end

-- =========================================================================
-- LLAVES
-- =========================================================================
function mplusModule.GetMapName(mapID)
    if not mapID or not (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then return nil end
    local ok, name = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
    return ok and name or nil
end

-- Mi llave actual: mapID, nivel (o nil si no tengo)
function mplusModule.GetMyKeystone()
    if not (C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID) then return nil end
    local okMap, mapID = pcall(C_MythicPlus.GetOwnedKeystoneChallengeMapID)
    local okLevel, level = pcall(C_MythicPlus.GetOwnedKeystoneLevel)
    if okMap and okLevel and mapID and level and level > 0 then return mapID, level end
    return nil
end

-- Llaves conocidas por nombre (Nombre-Reino): { mapID, level, at }
local function KeyStore()
    if type(GuildControlDB.keystones) ~= "table" then GuildControlDB.keystones = {} end
    return GuildControlDB.keystones
end

local function SetKeystone(fullName, mapID, level)
    local value = (mapID and mapID > 0 and level and level > 0) and { mapID = mapID, level = level, at = time() } or nil
    KeyStore()[fullName] = value
    local m = GuildControlDB.members[fullName]
    if m then m.keystone = value end
end

-- Momento del último reinicio semanal (las llaves anteriores ya no valen)
local function LastWeeklyReset()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local ok, seconds = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
        if ok and type(seconds) == "number" then return time() + seconds - 7 * 86400 end
    end
    return time() - 7 * 86400
end

-- Llave de un miembro, o nil si no se conoce o es de antes del reinicio semanal
function mplusModule.GetKeystone(fullName)
    local key = KeyStore()[fullName]
    if not key then
        local m = GuildControlDB.members[fullName]
        key = m and m.keystone
    end
    if key and key.at and key.at < LastWeeklyReset() then return nil end
    return key
end

local function StoreMyKeystone()
    local me = NormalizeName(UnitName("player"))
    if not me then return end
    local mapID, level = mplusModule.GetMyKeystone()
    SetKeystone(me, mapID, level)
end

function mplusModule.BroadcastKeystone(force)
    if not IsInGuild() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local mapID, level = mplusModule.GetMyKeystone()
    local key = mapID and (mapID .. ":" .. level) or "none"
    if not force and (key == lastSentKey or GetTime() - lastBroadcast < BROADCAST_COOLDOWN) then return end
    lastSentKey, lastBroadcast = key, GetTime()
    C_ChatInfo.SendAddonMessage(KEY_PREFIX, mapID and ("K;" .. mapID .. ";" .. level) or "K;0;0", "GUILD")
end

-- throttled = true: no repite la petición si se hizo hace menos de un minuto (al abrir la vista)
function mplusModule.RequestKeystones(throttled)
    if throttled and GetTime() - lastRequest < REQUEST_COOLDOWN then return end
    lastRequest = GetTime()
    if IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(KEY_PREFIX, "Q", "GUILD")
    end
end

-- =========================================================================
-- AFIJOS Y MEJORES TIEMPOS PROPIOS
-- =========================================================================
function mplusModule.RequestData()
    if C_MythicPlus then
        if C_MythicPlus.RequestCurrentAffixes then pcall(C_MythicPlus.RequestCurrentAffixes) end
        if C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end
    end
end

-- { {name, description, icon}, ... }
function mplusModule.GetAffixes()
    local result = {}
    if not (C_MythicPlus and C_MythicPlus.GetCurrentAffixes and C_ChallengeMode and C_ChallengeMode.GetAffixInfo) then return result end
    local ok, affixes = pcall(C_MythicPlus.GetCurrentAffixes)
    if not ok or type(affixes) ~= "table" then return result end
    for _, affix in ipairs(affixes) do
        local okInfo, name, description, icon = pcall(C_ChallengeMode.GetAffixInfo, affix.id)
        if okInfo and name then table.insert(result, { name = name, description = description, icon = icon }) end
    end
    return result
end

-- { {name, level, score, inTime}, ... } mejores de la temporada por mazmorra
function mplusModule.GetMyBestRuns()
    local result = {}
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return result end
    local ok, maps = pcall(C_ChallengeMode.GetMapTable)
    if not ok or type(maps) ~= "table" then return result end
    for _, mapID in ipairs(maps) do
        local name = mplusModule.GetMapName(mapID) or (L["Mazmorra "] .. mapID)
        local level, inTime, score = 0, false, 0
        if C_MythicPlus.GetSeasonBestForMap then
            local okBest, intimeInfo, overtimeInfo = pcall(C_MythicPlus.GetSeasonBestForMap, mapID)
            if okBest then
                if intimeInfo and intimeInfo.level then level, inTime = intimeInfo.level, true end
                if overtimeInfo and overtimeInfo.level and overtimeInfo.level > level then level, inTime = overtimeInfo.level, false end
            end
        end
        if C_MythicPlus.GetSeasonBestAffixScoreInfoForMap then
            local okScore, _, bestScore = pcall(C_MythicPlus.GetSeasonBestAffixScoreInfoForMap, mapID)
            if okScore and bestScore then score = bestScore end
        end
        table.insert(result, { name = name, level = level, score = score, inTime = inTime })
    end
    table.sort(result, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.name < b.name
    end)
    return result
end

function mplusModule.GetMyScore()
    if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
        local ok, score = pcall(C_ChallengeMode.GetOverallDungeonScore)
        if ok and score then return score end
    end
    return 0
end

-- =========================================================================
-- EVENTOS
-- =========================================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
frame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
frame:RegisterEvent("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, ...)
    if not GuildControlDB or not GuildControlDB.members then return end

    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if isInitialLogin or isReloadingUi then
            C_Timer.After(14, function()
                mplusModule.RequestData()
                StoreMyKeystone()
                mplusModule.BroadcastKeystone(true)
                mplusModule.RequestKeystones()
            end)
            C_Timer.After(45, function()
                StoreMyKeystone()
                mplusModule.BroadcastKeystone(false)
                Notify()
            end)
        end
        return
    elseif event == "CHALLENGE_MODE_COMPLETED" or event == "BAG_UPDATE_DELAYED" then
        -- La llave cambia al terminar una mítica o al recibir una nueva
        StoreMyKeystone()
        mplusModule.BroadcastKeystone(false)
        Notify()
        return
    elseif event == "CHALLENGE_MODE_MAPS_UPDATE" or event == "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE" then
        Notify()
        return
    end

    local prefix, msg, channel, sender = ...
    if prefix ~= KEY_PREFIX or channel ~= "GUILD" then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    if not msg or not sender then return end
    local fullSender = NormalizeName(sender)
    if fullSender == NormalizeName(UnitName("player")) then return end

    if msg == "Q" then
        mplusModule.BroadcastKeystone(true)
        return
    end
    local kind, mapID, level = strsplit(";", msg)
    if kind == "K" then
        SetKeystone(fullSender, tonumber(mapID), tonumber(level))
        Notify()
    end
end)
