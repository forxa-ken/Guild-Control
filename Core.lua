local addonName, addonTable = ...
GuildControlDB = GuildControlDB or {}

addonTable.Core = {}
addonTable.UI = {}

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

function addonTable.GetClassColorHex(classFileName)
    if not classFileName or classFileName == "" then return "ffffff" end
    local formattedClass = string.upper(string.gsub(classFileName, "%s+", ""))
    if C_ClassColor and C_ClassColor.GetClassColor then
        local colorObj = C_ClassColor.GetClassColor(formattedClass)
        if colorObj and colorObj.GenerateHexColor then
            local hex = colorObj:GenerateHexColor()
            if string.len(hex) > 6 then
                hex = string.sub(hex, -6)
            end
            return hex
        end
    end
    return "ffffff"
end

function addonTable.InitDB()
    if type(GuildControlDB) ~= "table" then GuildControlDB = {} end
    if type(GuildControlDB.members) ~= "table" then GuildControlDB.members = {} end
    if type(GuildControlDB.history) ~= "table" then GuildControlDB.history = {} end

    if type(GuildControlDB.announcements) ~= "table" then
        GuildControlDB.announcements = {
            { enabled = false, message = "¡Bienvenidos a la hermandad! Revisa las normas.", interval = 15 },
            { enabled = false, message = "", interval = 30 },
            { enabled = false, message = "", interval = 45 },
            { enabled = false, message = "", interval = 60 },
            { enabled = false, message = "", interval = 90 },
        }
    end

    if type(GuildControlDB.ranks) ~= "table" or #GuildControlDB.ranks == 0 then
        GuildControlDB.ranks = { "Líder", "Oficial", "Core", "Recluta", "Social" }
    end

    if type(GuildControlDB.rosters) ~= "table" or #GuildControlDB.rosters == 0 then
        GuildControlDB.rosters = { "Sin Roster", "Roster Principal", "Roster Secundario", "Banca" }
    end

    if type(GuildControlDB.minimap) ~= "table" then
        GuildControlDB.minimap = { angle = 45, hide = false }
    end

    -- Personalización del encabezado: guildName vacío = nombre real de la hermandad
    if type(GuildControlDB.settings) ~= "table" then GuildControlDB.settings = {} end
    if type(GuildControlDB.settings.guildName) ~= "string" then GuildControlDB.settings.guildName = "" end
    if GuildControlDB.settings.guildIcon == nil then
        GuildControlDB.settings.guildIcon = "Interface\\Icons\\Achievement_GuildPerk_MobileBanking"
    end

    -- Panel de chat de hermandad y saludo automático
    if type(GuildControlDB.settings.windowOnTop) ~= "boolean" then GuildControlDB.settings.windowOnTop = false end
    if type(GuildControlDB.settings.chatCollapsed) ~= "boolean" then GuildControlDB.settings.chatCollapsed = false end
    if type(GuildControlDB.settings.autoGreet) ~= "boolean" then GuildControlDB.settings.autoGreet = true end
    if type(GuildControlDB.settings.greetDelay) ~= "number" then GuildControlDB.settings.greetDelay = 2 end        -- segundos
    if type(GuildControlDB.settings.greetCooldown) ~= "number" then GuildControlDB.settings.greetCooldown = 30 end -- minutos
    if type(GuildControlDB.settings.greetLoginWindow) ~= "number" then GuildControlDB.settings.greetLoginWindow = 5 end -- minutos
    -- Palabras de saludo separadas por comas; vacío = lista por defecto de GuildChat.lua
    if type(GuildControlDB.settings.greetWords) ~= "string" then GuildControlDB.settings.greetWords = "" end
    if type(GuildControlDB.settings.greetMessage) ~= "string" or GuildControlDB.settings.greetMessage == "" then
        GuildControlDB.settings.greetMessage = "¡Hola, {nombre}!"
    end

    -- Generador del mensaje de invitación para nuevos miembros (vista Invitar)
    if type(GuildControlDB.settings.recruit) ~= "table" then GuildControlDB.settings.recruit = {} end
    local recruit = GuildControlDB.settings.recruit
    if type(recruit.roles) ~= "table" then recruit.roles = { tank = true, healer = true, dps = true } end
    if type(recruit.activities) ~= "table" then recruit.activities = { raid = true, mplus = true, pvp = false, social = true, leveling = false } end
    if type(recruit.schedule) ~= "string" then recruit.schedule = "" end
    if type(recruit.extra) ~= "string" then recruit.extra = "¡Susúrrame para más información!" end
    if type(recruit.message) ~= "string" then recruit.message = "" end
    if type(recruit.massMessage) ~= "string" or recruit.massMessage == "" then
        recruit.massMessage = "¡Hola, {nombre}! {rt1} Te he invitado a <{hermandad}>. Si te interesa, acepta la invitación o susúrrame."
    end
    if type(recruit.massWhisper) ~= "boolean" then recruit.massWhisper = true end
    if recruit.mode ~= "single" and recruit.mode ~= "mass" then recruit.mode = "single" end

    -- Mensaje para los integrantes de un roster (botón Mensaje de la vista Roster)
    if type(GuildControlDB.settings.rosterMessage) ~= "string" or GuildControlDB.settings.rosterMessage == "" then
        GuildControlDB.settings.rosterMessage = "{rt1} {roster} ({dificultad}): banda el {fecha} a las {hora}. ¡Confirmad asistencia!"
    end

    -- Fecha (time()) de la última invitación masiva a cada jugador, para no repetirla
    if type(GuildControlDB.inviteHistory) ~= "table" then GuildControlDB.inviteHistory = {} end
end

-- Nombre que muestra el encabezado: el personalizado, el de la hermandad o uno genérico
function addonTable.GetDisplayGuildName()
    local custom = GuildControlDB.settings and GuildControlDB.settings.guildName
    if custom and custom ~= "" then return custom end
    local guildName = IsInGuild() and GetGuildInfo("player")
    return guildName or "Sin hermandad"
end

-- Acepta un fileID, una ruta completa o solo el nombre del icono ("INV_Misc_QuestionMark")
function addonTable.ResolveIconTexture(value)
    if type(value) == "number" then return value end
    if type(value) ~= "string" or value == "" then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    local asNumber = tonumber(value)
    if asNumber then return asNumber end
    if string.find(value, "[\\/]") then return value end
    return "Interface\\Icons\\" .. value
end

function addonTable.LogHistoryEvent(actionType, characterName, details)
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    table.insert(GuildControlDB.history, 1, {
        date = timestamp,
        action = actionType,
        name = characterName,
        info = details or ""
    })
    if #GuildControlDB.history > 300 then
        table.remove(GuildControlDB.history)
    end
end

function addonTable.CreateMinimapButton()
    if GuildControlMinimapButton then return end

    local button = CreateFrame("Button", "GuildControlMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\Achievement_GuildPerk_MobileBanking")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", -1, 1)

    local function UpdatePosition()
        local angle = math.rad(GuildControlDB.minimap.angle or 45)
        local radius = (Minimap:GetWidth() / 2) + 2
        local x = math.cos(angle) * radius
        local y = math.sin(angle) * radius
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            GuildControlDB.minimap.angle = angle
            UpdatePosition()
        end)
    end)

    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" and addonTable.UI.ToggleUI then
            addonTable.UI.ToggleUI()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("GuildControl", 1, 1, 1)
        GameTooltip:AddLine("Clic izquierdo: Abrir/Cerrar panel", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Arrastrar: Mover alrededor del minimapa", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
end

local isSyncingRoster = false
local lastExecutionTimestamp = 0
-- El primer escaneo de la sesión solo fija el estado inicial: quien ya estaba conectado
-- antes de entrar no cuenta como recién conectado (saludo automático)
local rosterBaselineDone = false

function addonTable.ScanGuildRosterForChanges()
    local currentTime = GetTime()
    if not IsInGuild() or isSyncingRoster or (currentTime - lastExecutionTimestamp < 5) then return end
    
    isSyncingRoster = true
    lastExecutionTimestamp = currentTime

    local numMembers = GetNumGuildMembers()
    local currentGuildOnlineMap = {}

    for i = 1, numMembers do
        local fullName, rankName, rankIndex, level, _, zoneName, publicNote, officerNote, online, _, classFileName, _, _, _, _, _, guid = GetGuildRosterInfo(i)
        
        if fullName then
            currentGuildOnlineMap[fullName] = true

            local _, _, days = GetGuildRosterLastOnline(i)
            local isReallyOnline = (online == true or online == 1 or online == "true")
            local lastOnlineStr = "Online"
            
            if not isReallyOnline then
                if days and days > 0 then
                    lastOnlineStr = days .. " días"
                else
                    lastOnlineStr = "Desconectado"
                end
            end

            if not GuildControlDB.members[fullName] then
                GuildControlDB.members[fullName] = {
                    name = fullName,
                    rank = rankName or "Recluta",
                    publicNote = publicNote or "",
                    role = "DPS",
                    focus = "PvE",
                    prof1 = "Ninguna",
                    prof2 = "Ninguna",
                    roster = "Sin Roster",
                    level = level or 0,
                    class = classFileName or "Desconocida",
                    zone = zoneName or "Desconocida",
                    lastOnline = lastOnlineStr,
                    isOnline = isReallyOnline,
                    guid = guid,
                    rankIndex = rankIndex
                }
                addonTable.LogHistoryEvent("ALTA", fullName, "Ingreso detectado automáticamente del servidor")
            else
                local m = GuildControlDB.members[fullName]
                if rankName and rankName ~= "" then m.rank = rankName end
                m.publicNote = publicNote or m.publicNote or ""
                m.level = level or m.level or 0
                m.class = classFileName or m.class or "Desconocida"
                m.zone = zoneName or m.zone or "Desconocida"
                m.lastOnline = lastOnlineStr
                if rosterBaselineDone and addonTable.GuildChat then
                    if isReallyOnline and not m.isOnline and addonTable.GuildChat.MarkOnline then
                        addonTable.GuildChat.MarkOnline(fullName)
                    elseif not isReallyOnline and m.isOnline and addonTable.GuildChat.MarkOffline then
                        addonTable.GuildChat.MarkOffline(fullName)
                    end
                end
                m.isOnline = isReallyOnline
                m.guid = guid or m.guid
                m.rankIndex = rankIndex
            end
        end
    end

    rosterBaselineDone = true

    for existingMember, _ in pairs(GuildControlDB.members) do
        if not currentGuildOnlineMap[existingMember] then
            addonTable.LogHistoryEvent("BAJA", existingMember, "Purgado: Ya no se encuentra en el servidor oficial")
            GuildControlDB.members[existingMember] = nil
        end
    end

    if addonTable.Professions and addonTable.Professions.Scan then
        addonTable.Professions.Scan()
    end
    -- Roles declarados por otros personajes de esta cuenta (comparten SavedVariables)
    if addonTable.Profiles and addonTable.Profiles.ApplyAccountProfiles then
        addonTable.Profiles.ApplyAccountProfiles()
    end

    if addonTable.UI.RefreshList and addonTable.UI.IsShown and addonTable.UI.IsShown() then
        addonTable.UI.RefreshList()
    end
    if addonTable.UI.UpdateMemberCounter then
        addonTable.UI.UpdateMemberCounter()
    end
    -- El rango puede haber cambiado: actualizar las pestañas visibles según el perfil
    if addonTable.UI.ApplyProfile and addonTable.UI.IsShown and addonTable.UI.IsShown() then
        addonTable.UI.ApplyProfile()
    end

    isSyncingRoster = false
end

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        addonTable.InitDB()
        addonTable.CreateMinimapButton()
        C_GuildInfo.GuildRoster()
        print("|cFF00FFFF[GuildControl]|r v4.5.0 (Modular) cargado. Usa /gct para abrir la interfaz.")
    elseif event == "PLAYER_ENTERING_WORLD" or event == "GUILD_ROSTER_UPDATE" then
        addonTable.ScanGuildRosterForChanges()
    end
end)

SLASH_GUILDCONTROL1 = "/gct"
SLASH_GUILDCONTROL2 = "/gctc"

SlashCmdList["GUILDCONTROL"] = function(msg)
    local cleanMsg = string.trim and string.trim(msg) or msg:match("^%s*(.-)%s*$")
    local args = {}
    for word in string.gmatch(cleanMsg or "", "%S+") do table.insert(args, word) end
    local cmd = args[1] and string.lower(args[1]) or ""

    if cmd == "show" or cmd == "" then
        if addonTable.UI.ToggleUI then addonTable.UI.ToggleUI() end
    elseif cmd == "bajas" then
        if addonTable.UI.ShowBajas then addonTable.UI.ShowBajas() end
    elseif cmd == "csv" then
        if addonTable.CSV and addonTable.CSV.ShowFrame then addonTable.CSV.ShowFrame() end
    else
        print("|cFF00FFFF[GuildControl] Comandos disponibles:|r")
        print(" /gct - Abre/Cierra la interfaz principal.")
        print(" /gct csv - Panel de exportación CSV para Google Sheets.")
        print(" /gct bajas - Historial de bajas registradas.")
    end
end