local addonName, addonTable = ...

addonTable.UI = {}
local uiModule = addonTable.UI

local GC_UI = nil
local activeTab = "Miembros"
local selectedMember = nil
local selectedAchievementId = nil

-- Referencias a los contenedores principales
local containers = {
    header = nil,
    announcements = nil,
    sidebar = nil,
    mainContent = nil,
    preview = nil,
    views = {} -- Vistas específicas (Resumen, Miembros, Logros, etc.)
}

local PREVIEW_DEFAULT_TEXT = "Selecciona un elemento para ver su información detallada."

-- Pestañas del menú lateral y las que solo ve el perfil de oficial
local SIDEBAR_TABS = { "Resumen", "Miembros", "Logros", "Profesiones", "Míticas+", "Mi perfil", "Mis rosters", "Roster", "Warning", "Invitar", "Black list" }
local OFFICER_ONLY_TABS = { ["Roster"] = true, ["Warning"] = true, ["Invitar"] = true, ["Black list"] = true }
local PLAYER_ONLY_TABS = { ["Mis rosters"] = true }   -- los oficiales ya tienen la pestaña Roster completa

-- Iconos de rol del juego (atlas) para usar dentro de textos
local ROLE_ICON_ATLAS = {
    Tanque = "roleicon-tiny-tank", Sanador = "roleicon-tiny-healer", DPS = "roleicon-tiny-dps",
    tank = "roleicon-tiny-tank", healer = "roleicon-tiny-healer", dps = "roleicon-tiny-dps",
}

local function RoleIcon(role, size)
    local atlas = ROLE_ICON_ATLAS[role or ""]
    if not atlas then return "" end
    size = size or 14
    return "|A:" .. atlas .. ":" .. size .. ":" .. size .. "|a"
end

local function CreateBackdropBox(parent, width, height, point, relativeTo, relativePoint, x, y)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(width, height)
    if point then
        frame:SetPoint(point, relativeTo or parent, relativePoint or point, x or 0, y or 0)
    end
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    return frame
end

function uiModule.GetMainFrame()
    return GC_UI
end

function uiModule.IsShown()
    return GC_UI and GC_UI:IsShown()
end

-- =========================================================================
-- 1. HEADER (BARRA SUPERIOR)
-- =========================================================================
local HEADER_HEIGHT = 64
local ANN_BAR_HEIGHT = 64
local CELL_HEIGHT = 52   -- alto de las cajas planas dentro del header y de la barra de anuncios

-- Caja plana (fondo oscuro y borde de 1 px) con una etiqueta pequeña abajo.
-- El contenido (número, campo de texto, etc.) se ancla a su parte superior.
local function CreateCellBox(parent, label, width)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(width, CELL_HEIGHT)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0.08, 0.08, 0.1, 0.95)
    box:SetBackdropBorderColor(0.3, 0.3, 0.32, 1)

    box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.label:SetPoint("BOTTOM", box, "BOTTOM", 0, 6)
    box.label:SetTextColor(0.75, 0.75, 0.75)
    box.label:SetText(label)

    return box
end

-- Caja de estadística: número grande arriba y etiqueta pequeña debajo
local function CreateStatBox(parent, label, width)
    local box = CreateCellBox(parent, label, width)

    box.value = box:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    box.value:SetPoint("TOP", box, "TOP", 0, -6)
    box.value:SetText("0")

    return box
end

local function BuildHeader(parent)
    local header = CreateBackdropBox(parent, 1280, HEADER_HEIGHT, "TOPLEFT", parent, "TOPLEFT", 10, -25)

    local logo = header:CreateTexture(nil, "OVERLAY")
    logo:SetSize(44, 44)
    logo:SetPoint("LEFT", header, "LEFT", 12, 0)
    header.logo = logo

    local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    titleText:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -2)
    header.titleText = titleText

    -- Debajo del nombre: reino de la hermandad y facción
    local subText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 1, -4)
    subText:SetTextColor(0.7, 0.7, 0.7)
    header.subText = subText

    -- Discord de la hermandad: abre una ventanita con el enlace listo para copiar
    local btnDiscord = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    btnDiscord:SetSize(84, 22)
    btnDiscord:SetPoint("LEFT", titleText, "RIGHT", 14, 0)
    btnDiscord:SetText("Discord")
    btnDiscord:SetScript("OnClick", function() uiModule.ShowDiscordCopy() end)
    btnDiscord:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Discord de la hermandad", 1, 1, 1)
        GameTooltip:AddLine(GuildControlDB.settings.discordLink or "", 0.6, 0.8, 1)
        GameTooltip:AddLine("Clic para copiar el enlace", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    btnDiscord:SetScript("OnLeave", function() GameTooltip:Hide() end)
    header.btnDiscord = btnDiscord

    -- Cajas de estadísticas alineadas a la derecha
    local statWidth, statGap = 170, 6
    local onlineBox = CreateStatBox(header, "En línea", statWidth)
    onlineBox:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    header.onlineBox = onlineBox

    local membersBox = CreateStatBox(header, "Miembros", statWidth)
    membersBox:SetPoint("RIGHT", onlineBox, "LEFT", -statGap, 0)
    header.membersBox = membersBox

    local warningsBox = CreateStatBox(header, "Warnings", statWidth)
    warningsBox:SetPoint("RIGHT", membersBox, "LEFT", -statGap, 0)
    warningsBox.value:SetTextColor(1, 0.25, 0.25)
    header.warningsBox = warningsBox

    local verText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    verText:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -30, -6)
    verText:SetText("v4.5.0")

    local authorText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    authorText:SetPoint("RIGHT", verText, "LEFT", -12, 0)
    authorText:SetText("|cFF808080Autor:|r Forxaken  |cFF808080·  Guild:|r Lobo Gélido")

    containers.header = header
    uiModule.UpdateHeader()
end

-- Aplica el nombre y el icono configurados (GuildControlDB.settings)
function uiModule.UpdateHeader()
    local header = containers.header
    if not header then return end
    local settings = GuildControlDB.settings or {}

    header.logo:SetTexture(addonTable.ResolveIconTexture(settings.guildIcon))
    header.titleText:SetText("|cFFFFD100" .. addonTable.GetDisplayGuildName() .. "|r")

    -- Reino de la hermandad (GetGuildInfo lo da si es distinto del del personaje) y facción
    local parts = {}
    local guildRealm = IsInGuild() and select(4, GetGuildInfo("player")) or nil
    table.insert(parts, "Reino: |cFFFFFFFF" .. (guildRealm or GetRealmName() or "-") .. "|r")
    local _, localizedFaction = UnitFactionGroup("player")
    if localizedFaction then table.insert(parts, "Facción: |cFFFFFFFF" .. localizedFaction .. "|r") end
    header.subText:SetText(table.concat(parts, "   ·   "))

    header.btnDiscord:SetShown((settings.discordLink or "") ~= "")
end

-- Ventanita con el enlace de Discord seleccionado para copiarlo con Ctrl+C
local GC_DiscordFrame = nil
function uiModule.ShowDiscordCopy()
    local link = GuildControlDB.settings.discordLink or ""
    if link == "" or not GC_UI then return end
    if not GC_DiscordFrame then
        local frame = CreateFrame("Frame", "GuildControlDiscordFrame", GC_UI, "BasicFrameTemplateWithInset")
        frame:SetSize(420, 110)
        frame:SetPoint("TOP", GC_UI, "TOP", 0, -100)
        frame:SetFrameStrata("DIALOG")
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
        frame.title:SetText("Discord de la hermandad")

        local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        edit:SetSize(380, 22)
        edit:SetPoint("TOP", frame, "TOP", 0, -36)
        edit:SetAutoFocus(false)
        -- Siempre el enlace completo y seleccionado, aunque se intente editar
        edit:SetScript("OnTextChanged", function(self, userInput)
            if userInput then self:SetText(frame.link or ""); self:HighlightText() end
        end)
        edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        edit:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        edit:SetScript("OnEscapePressed", function() frame:Hide() end)
        edit:SetScript("OnEnterPressed", function() frame:Hide() end)
        frame.edit = edit

        local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOP", edit, "BOTTOM", 0, -10)
        hint:SetText("|cFF00FF00Enlace seleccionado.|r Pulsa |cFFFFD100Ctrl+C|r para copiarlo.")
        GC_DiscordFrame = frame
    end
    GC_DiscordFrame.link = link
    GC_DiscordFrame:Show()
    GC_DiscordFrame.edit:SetText(link)
    GC_DiscordFrame.edit:SetFocus()
    GC_DiscordFrame.edit:HighlightText()
end

-- =========================================================================
-- 2. SUB-HEADER (ANUNCIOS MÚLTIPLES)
-- =========================================================================
local function BuildAnnouncementsBar(parent)
    local annBar = CreateBackdropBox(parent, 1280, ANN_BAR_HEIGHT, "TOPLEFT", containers.header, "BOTTOMLEFT", 0, -5)

    -- Mismo esquema que las estadísticas del header: una caja por campo con su etiqueta debajo
    local gap = 6
    local slotWidth, timeWidth, stateWidth = 180, 130, 150
    local msgWidth = 1280 - 2 * gap - slotWidth - timeWidth - stateWidth - 3 * gap

    local slotBox = CreateCellBox(annBar, "Anuncio", slotWidth)
    slotBox:SetPoint("LEFT", annBar, "LEFT", gap, 0)

    local msgBox = CreateCellBox(annBar, "Texto que se publica en el chat de hermandad", msgWidth)
    msgBox:SetPoint("LEFT", slotBox, "RIGHT", gap, 0)

    local timeBox = CreateCellBox(annBar, "Intervalo (min)", timeWidth)
    timeBox:SetPoint("LEFT", msgBox, "RIGHT", gap, 0)

    local stateBox = CreateCellBox(annBar, "Estado", stateWidth)
    stateBox:SetPoint("LEFT", timeBox, "RIGHT", gap, 0)

    local dropAnn = CreateFrame("DropdownButton", "GC_DropAnnSelect_New", slotBox, "WowStyle1DropdownTemplate")
    dropAnn:SetPoint("TOP", slotBox, "TOP", 0, -5)
    dropAnn:SetWidth(slotWidth - 20)

    local msgInput = CreateFrame("EditBox", "GC_AnnMsgInput_New", msgBox, "InputBoxTemplate")
    msgInput:SetSize(msgWidth - 30, 20)
    msgInput:SetPoint("TOP", msgBox, "TOP", 0, -8)
    msgInput:SetAutoFocus(false)

    local timeInput = CreateFrame("EditBox", "GC_AnnTimeInput_New", timeBox, "InputBoxTemplate")
    timeInput:SetSize(60, 20)
    timeInput:SetPoint("TOP", timeBox, "TOP", 0, -8)
    timeInput:SetJustifyH("CENTER")
    timeInput:SetNumeric(true)
    timeInput:SetAutoFocus(false)

    local chkEnable = CreateFrame("CheckButton", "GC_AnnEnable_New", stateBox, "UICheckButtonTemplate")
    chkEnable:SetSize(26, 26)
    chkEnable:SetPoint("TOP", stateBox, "TOP", -24, -3)
    _G[chkEnable:GetName() .. "Text"]:SetText("Activar")

    -- La etiqueta de la caja Estado indica si el anuncio seleccionado se está publicando
    local function UpdateStateLabel(enabled)
        if enabled then
            stateBox.label:SetText("|cFF00FF00Publicando|r")
        else
            stateBox.label:SetText("Desactivado")
        end
    end

    local function RefreshFields()
        if addonTable.Announcements then
            local data = addonTable.Announcements.GetAnnouncementData()
            if data then
                chkEnable:SetChecked(data.enabled)
                UpdateStateLabel(data.enabled)
                msgInput:SetText(data.message or "")
                timeInput:SetText(tostring(data.interval or 15))
            end
        end
    end

    dropAnn:SetupMenu(function(owner, rootDescription)
        for i = 1, 5 do
            rootDescription:CreateRadio("Mensaje " .. i,
                function() return addonTable.Announcements and addonTable.Announcements.GetSelectedIndex() == i end,
                function()
                    if addonTable.Announcements then addonTable.Announcements.SetSelectedIndex(i) end
                    RefreshFields()
                end
            )
        end
    end)
    dropAnn:SetText("Mensaje 1")

    chkEnable:SetScript("OnClick", function(self)
        if addonTable.Announcements then
            addonTable.Announcements.UpdateAnnouncementData(addonTable.Announcements.GetSelectedIndex(), self:GetChecked(), nil, nil)
        end
        UpdateStateLabel(self:GetChecked())
    end)
    msgInput:SetScript("OnTextChanged", function(self)
        if addonTable.Announcements then
            addonTable.Announcements.UpdateAnnouncementData(addonTable.Announcements.GetSelectedIndex(), nil, self:GetText(), nil)
        end
    end)
    timeInput:SetScript("OnTextChanged", function(self)
        if addonTable.Announcements then
            addonTable.Announcements.UpdateAnnouncementData(addonTable.Announcements.GetSelectedIndex(), nil, nil, tonumber(self:GetText()) or 15)
        end
    end)

    RefreshFields()

    -- Perfil de jugador: en lugar de los anuncios se muestra un resumen de su ficha
    local playerInfo = CreateFrame("Frame", nil, annBar)
    playerInfo:SetAllPoints()
    playerInfo:Hide()
    playerInfo.text = playerInfo:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    playerInfo.text:SetPoint("LEFT", playerInfo, "LEFT", 16, 0)
    playerInfo.text:SetPoint("RIGHT", playerInfo, "RIGHT", -16, 0)
    playerInfo.text:SetJustifyH("LEFT")
    annBar.playerInfo = playerInfo

    containers.announcements = annBar
end

function uiModule.UpdatePlayerInfoBar()
    local annBar = containers.announcements
    if not annBar or not annBar.playerInfo or not addonTable.Profiles then return end
    local P = addonTable.Profiles
    local m = GuildControlDB.members[P.GetMyFullName()] or {}
    local profile = P.GetMyProfile()
    local roleText = profile.main and ("|cFF00FF00" .. profile.main .. "|r" .. (profile.secondary and (" / " .. profile.secondary) or ""))
        or "|cFFFF7F00sin declarar (ve a Mi perfil)|r"
    -- Los rosters del jugador vienen de los que publican los oficiales
    local rosterNames = uiModule.GetMySharedRosterNames and uiModule.GetMySharedRosterNames() or {}
    local rosterText = #rosterNames > 0 and table.concat(rosterNames, ", ") or "ninguno publicado"
    annBar.playerInfo.text:SetText("|cFF00FFFFPerfil de jugador|r   ·   Rango: |cFFFFD100" .. (m.rank or "-")
        .. "|r   ·   Tu rol: " .. roleText .. "   ·   Rosters: |cFFFFD100" .. rosterText .. "|r")
end

-- =========================================================================
-- 3. CAMBIO DE PESTAÑAS Y NAVEGACIÓN
-- =========================================================================
local function SetPreviewText(text)
    if containers.preview and containers.preview.infoText then
        containers.preview.infoText:SetText(text or PREVIEW_DEFAULT_TEXT)
        -- Cada vista previa nueva empieza sin botón de acción
        if containers.preview.actionButton then containers.preview.actionButton:Hide() end
    end
end

-- Botón opcional al pie de la vista previa (por ejemplo "Ver en la interfaz del juego")
local function SetPreviewAction(label, onClick)
    local btn = containers.preview and containers.preview.actionButton
    if not btn then return end
    btn:SetText(label)
    btn:SetScript("OnClick", onClick)
    btn:Show()
end

local function SwitchTab(tabName)
    activeTab = tabName
    for name, viewFrame in pairs(containers.views) do
        if name == tabName then
            viewFrame:Show()
        else
            viewFrame:Hide()
        end
    end

    -- La vista previa se reinicia al cambiar de pestaña para no mostrar datos de otra sección
    if tabName ~= "Logros" then
        selectedAchievementId = nil
    end
    SetPreviewText(PREVIEW_DEFAULT_TEXT)

    if tabName == "Miembros" and uiModule.RefreshList then
        -- Al entrar en Miembros siempre se vuelve al orden por defecto: conectados primero
        if uiModule.ResetMembersSort then uiModule.ResetMembersSort() end
        uiModule.RefreshList()
    elseif tabName == "Logros" and uiModule.RefreshAchievements then
        uiModule.RefreshAchievements()
    elseif tabName == "Roster" and uiModule.RefreshRoster then
        uiModule.RefreshRoster()
    end
end

-- =========================================================================
-- 4. MENÚ LATERAL IZQUIERDO (SIDEBAR)
-- =========================================================================
local function BuildSidebar(parent)
    local sidebar = CreateBackdropBox(parent, 150, 520, "TOPLEFT", containers.announcements, "BOTTOMLEFT", 0, -5)

    -- Los botones se crean todos y ApplyProfile decide cuáles se ven y en qué posición
    sidebar.tabButtons = {}
    for _, tabName in ipairs(SIDEBAR_TABS) do
        local btn = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
        btn:SetSize(130, 25)
        btn:SetText(tabName)
        btn:SetScript("OnClick", function() SwitchTab(tabName) end)
        sidebar.tabButtons[tabName] = btn
    end

    sidebar.profileText = sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sidebar.profileText:SetPoint("BOTTOM", sidebar, "BOTTOM", 0, 46)

    local btnConfig = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    btnConfig:SetSize(130, 25)
    btnConfig:SetPoint("BOTTOM", sidebar, "BOTTOM", 0, 15)
    btnConfig:SetText("Configuración")
    btnConfig:SetScript("OnClick", function() SwitchTab("Configuracion") end)

    containers.sidebar = sidebar
end

-- Muestra solo las pestañas del perfil actual (oficial o jugador)
function uiModule.ApplyProfile()
    local sidebar = containers.sidebar
    if not sidebar then return end
    local isOfficer = not addonTable.Profiles or addonTable.Profiles.IsOfficer()

    local yOffset = -15
    for _, tabName in ipairs(SIDEBAR_TABS) do
        local btn = sidebar.tabButtons[tabName]
        local allowed = (isOfficer and not PLAYER_ONLY_TABS[tabName]) or (not isOfficer and not OFFICER_ONLY_TABS[tabName])
        btn:SetShown(allowed)
        if allowed then
            btn:ClearAllPoints()
            btn:SetPoint("TOP", sidebar, "TOP", 0, yOffset)
            yOffset = yOffset - 32
        end
    end
    sidebar.profileText:SetText(isOfficer and "Perfil: |cFFFFD100Oficial|r" or "Perfil: |cFF00FFFFJugador|r")

    -- La barra de anuncios es de oficiales; los jugadores ven un resumen de su ficha
    if containers.announcements then
        for _, child in ipairs({ containers.announcements:GetChildren() }) do child:SetShown(isOfficer) end
        if containers.announcements.playerInfo then
            containers.announcements.playerInfo:SetShown(not isOfficer)
            if not isOfficer and uiModule.UpdatePlayerInfoBar then uiModule.UpdatePlayerInfoBar() end
        end
    end

    if (not isOfficer and OFFICER_ONLY_TABS[activeTab]) or (isOfficer and PLAYER_ONLY_TABS[activeTab]) then SwitchTab("Miembros") end
end

-- =========================================================================
-- 5. PANEL LATERAL DERECHO (PREVIEW)
-- =========================================================================
local function BuildPreviewPanel(parent)
    local preview = CreateBackdropBox(parent, 220, 520, "TOPRIGHT", containers.announcements, "BOTTOMRIGHT", 0, -5)

    local title = preview:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", preview, "TOP", 0, -15)
    title:SetText("Vista Previa")

    local infoText = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", preview, "TOPLEFT", 15, -45)
    infoText:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -15, 44)
    infoText:SetJustifyH("LEFT")
    infoText:SetJustifyV("TOP")
    infoText:SetText(PREVIEW_DEFAULT_TEXT)

    preview.infoText = infoText

    local actionButton = CreateFrame("Button", nil, preview, "UIPanelButtonTemplate")
    actionButton:SetSize(190, 22)
    actionButton:SetPoint("BOTTOM", preview, "BOTTOM", 0, 14)
    actionButton:Hide()
    preview.actionButton = actionButton
    containers.preview = preview
end

-- Construye el texto de detalle de un logro para la vista previa
local function BuildAchievementPreviewText(id)
    local ach = addonTable.Achievements
    if not ach then return PREVIEW_DEFAULT_TEXT end

    local d = ach.GetDetails(id)
    if not d then return PREVIEW_DEFAULT_TEXT end

    local lines = {}
    table.insert(lines, "|cFFFFD100" .. d.name .. "|r")
    table.insert(lines, "")

    if d.description ~= "" then
        table.insert(lines, d.description)
        table.insert(lines, "")
    end

    table.insert(lines, "Puntos: |cFFFFD100" .. d.points .. "|r")

    if d.completed then
        table.insert(lines, "Estado: |cFF00FF00Completado|r")
        table.insert(lines, "Fecha: " .. (d.date or "-"))
        table.insert(lines, "Completado por: |cFF00FFFF" .. (d.earnedBy or "No disponible") .. "|r")
    else
        table.insert(lines, "Estado: |cFFFF3333Pendiente|r")
    end

    if d.rewardText ~= "" then
        table.insert(lines, "")
        table.insert(lines, "|cFF66FF66Recompensa:|r " .. d.rewardText)
    end

    -- Participantes (si la API del cliente lo permite)
    -- (solo en logros de hermandad: los del personaje no tienen participantes)
    if d.completed and ach.IsGuildMode() then
        local names, total, available = ach.GetMembers(id)
        table.insert(lines, "")
        if not available then
            table.insert(lines, "|cFF808080Participantes: no disponible|r")
        elseif #names == 0 then
            table.insert(lines, "|cFF808080Participantes: sin datos aún|r")
        else
            local maxShown = ach.GetMaxMembersShown()
            local shown = {}
            for i = 1, math.min(#names, maxShown) do
                table.insert(shown, names[i])
            end
            table.insert(lines, "Participantes (" .. #names .. "):")
            local extra = #names > maxShown and (" |cFF808080y " .. (#names - maxShown) .. " más|r") or ""
            table.insert(lines, "|cFF00FFFF" .. table.concat(shown, ", ") .. "|r" .. extra)
        end
    end

    -- Criterios
    if #d.criteria > 0 then
        table.insert(lines, "")
        table.insert(lines, "Criterios: " .. d.criteriaDone .. "/" .. #d.criteria)
        for i = 1, math.min(#d.criteria, 8) do
            local c = d.criteria[i]
            local mark = c.done and "|cFF00FF00+|r " or "|cFFFF3333-|r "
            local progress = (c.req > 1) and (" (" .. c.qty .. "/" .. c.req .. ")") or ""
            table.insert(lines, mark .. c.name .. progress)
        end
        if #d.criteria > 8 then
            table.insert(lines, "|cFF808080... y " .. (#d.criteria - 8) .. " más|r")
        end
    end

    table.insert(lines, "")
    table.insert(lines, "|cFF808080Clic derecho: abrir en Blizzard|r")

    return table.concat(lines, "\n")
end

-- Vista previa de un logro con el botón para abrirlo en la ventana de logros del juego
local function ShowAchievementPreviewWithButton(id)
    SetPreviewText(BuildAchievementPreviewText(id))
    SetPreviewAction("Ver en la interfaz del juego", function()
        if addonTable.Achievements then addonTable.Achievements.OpenAchievement(id) end
    end)
end

function uiModule.ShowAchievementPreview(id)
    if not id then return end
    selectedAchievementId = id

    if addonTable.Achievements then
        addonTable.Achievements.RequestMembers(id)
    end
    ShowAchievementPreviewWithButton(id)

    -- La lista de participantes puede tardar en llegar del servidor: reintento único
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function()
            if selectedAchievementId == id and activeTab == "Logros" then
                ShowAchievementPreviewWithButton(id)
            end
        end)
    end
end

-- =========================================================================
-- ACCIONES SOBRE JUGADORES (susurrar, invitar al grupo o a la hermandad)
-- =========================================================================
local function PrintGC(msg)
    print("|cFF00FFFF[GuildControl]|r " .. msg)
end

-- Abre la caja de chat del juego con el texto indicado (el jugador decide cuándo enviarlo)
local function OpenChatWith(text)
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        ChatFrameUtil.OpenChat(text)
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat(text)
    end
end

local function WhisperTo(name)
    if name and name ~= "" then OpenChatWith("/w " .. name .. " ") end
end

local function SendWhisper(name, msg)
    if not name or name == "" or not msg or msg == "" then return end
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(msg, "WHISPER", nil, name)
    else
        SendChatMessage(msg, "WHISPER", nil, name)
    end
end

local function InviteToGroup(name)
    if not name or name == "" then return end
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    end
end

-- quiet = true: sin mensaje de confirmación en el chat (invitación masiva)
local function InviteToGuild(name, quiet)
    if not name or name == "" then return false end
    -- Nunca se invita a alguien de la lista negra
    local blacklisted = addonTable.Blacklist and addonTable.Blacklist.Get(name)
    if blacklisted then
        PrintGC("|cFFFF3333No se invita a " .. name .. ": está en la lista negra (" .. addonTable.Blacklist.GetReasonLabel(blacklisted.reason) .. ").|r")
        return false
    end
    if not IsInGuild() or (CanGuildInvite and not CanGuildInvite()) then
        PrintGC("|cFFFF3333Tu rango no tiene permiso para invitar a la hermandad.|r")
        return false
    end
    if C_GuildInfo and C_GuildInfo.Invite then
        C_GuildInfo.Invite(name)
    elseif GuildInvite then
        GuildInvite(name)
    end
    if not quiet then PrintGC("Invitación a la hermandad enviada a |cFFFFD100" .. name .. "|r.") end
    return true
end

-- Menú contextual de un jugador (clic derecho)
local function ShowPlayerMenu(owner, name)
    if not MenuUtil or not MenuUtil.CreateContextMenu then
        WhisperTo(name)
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
        rootDescription:CreateTitle(name)
        rootDescription:CreateButton("Susurrar", function() WhisperTo(name) end)
        rootDescription:CreateButton("Invitar al grupo", function() InviteToGroup(name) end)
    end)
end

-- =========================================================================
-- 6. VISTA DE MIEMBROS
-- =========================================================================
local MEMBER_ROW_HEIGHT = 24

-- Columnas de la tabla de miembros. "key" es el criterio de orden (nil = no ordenable)
local MEMBER_COLUMNS = {
    { title = "Nº",       x = 5,   w = 25 },
    { title = "Nivel",    x = 30,  w = 48,  key = "level" },
    { title = "Clase",    x = 78,  w = 62,  key = "class" },
    { title = "Nombre",   x = 140, w = 130, key = "name" },
    { title = "Rango",    x = 270, w = 72,  key = "rank" },
    { title = "Tipo",     x = 342, w = 48,  key = "charType" },
    { title = "Rol",      x = 390, w = 70,  key = "role" },
    { title = "Enfoque",  x = 460, w = 66,  key = "focus" },
    { title = "Prof. 1",  x = 526, w = 88,  key = "prof1" },
    { title = "Prof. 2",  x = 614, w = 88,  key = "prof2" },
    { title = "Roster",   x = 702, w = 60,  key = "roster" },
    { title = "Conexión", x = 762, w = 88,  key = "lastOnline" },
}

-- Orden por defecto: conectados primero y después por días desde la última conexión
local DEFAULT_SORT_KEY = "lastOnline"

-- Conectado = -1, desconectado hoy = 0, "N días" = N
local function OnlineSortValue(data)
    if data.isOnline then return -1 end
    return tonumber(string.match(data.lastOnline or "", "(%d+)")) or 0
end

-- Un rol solo se muestra si lo declaró el jugador o lo fijó un oficial
local function HasDefinedRole(data)
    return data.roleSource == "declared" or data.roleSource == "officer"
end

-- Columna Rol: icono y rol; vacía si nadie lo ha definido. Colores:
--   cian = lo declaró el jugador · blanco = lo fijó un oficial · naranja con * = el oficial puso otro distinto al declarado
local function RoleCellText(data)
    if not HasDefinedRole(data) then return "" end
    local role = data.role or "DPS"
    local declared = data.declared and data.declared.main
    return RoleIcon(role, 12) .. " " .. role .. ((declared and declared ~= role) and "*" or "")
end

local function RoleCellColor(data, isOnline)
    local declared = data.declared and data.declared.main
    if data.roleSource == "declared" then return isOnline and "00FFFF" or "4D9999" end
    if declared and declared ~= data.role then return isOnline and "FF7F00" or "996633" end
    return isOnline and "FFFFFF" or "888888"
end

-- Valores que se muestran vacíos cuando no hay dato (profesiones, roster, enfoque y tipo)
local function ProfessionCell(value)
    return (value and value ~= "Ninguna") and value or ""
end

local function RosterCell(value)
    return (value and value ~= "Sin Roster") and value or ""
end

-- El enfoque solo se muestra si el jugador lo declaró en Mi perfil
local function FocusCell(data)
    return data.declared and data.declared.focus or ""
end

local function CharTypeCell(data)
    local charType = data.declared and data.declared.charType
    if charType == "alt" then return "Alter" elseif charType == "main" then return "Main" end
    return ""
end

local function MemberSortValue(entry, key)
    local data = entry.data
    if key == "level" then return tonumber(data.level) or 0 end
    if key == "lastOnline" then return OnlineSortValue(data) end
    if key == "name" then return string.lower(entry.name) end

    -- Las celdas vacías van siempre al final en orden ascendente
    local value
    if key == "role" then value = HasDefinedRole(data) and data.role or ""
    elseif key == "prof1" or key == "prof2" then value = ProfessionCell(data[key])
    elseif key == "roster" then value = RosterCell(data.roster)
    elseif key == "focus" then value = FocusCell(data)
    elseif key == "charType" then value = CharTypeCell(data)
    else value = tostring(data[key] or "") end
    if value == "" then return "\255" end
    return string.lower(value)
end

local function BuildMembersView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()

    local showOnlyOnline = false
    local searchQuery = ""
    local sortKey, sortAsc = DEFAULT_SORT_KEY, true

    -- Barra de filtros (todo dentro del contenedor)
    local searchLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", view, "TOPLEFT", 12, -10)
    searchLabel:SetText("Buscar miembros")

    local searchBox = CreateFrame("EditBox", "GC_NewSearchBox", view, "InputBoxTemplate")
    searchBox:SetSize(260, 20)
    searchBox:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 5, -4)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- Texto de ayuda dentro de la caja mientras está vacía
    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
    searchPlaceholder:SetText("Nombre, clase, rango, profesión, roster...")

    local btnShowAll = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnShowAll:SetSize(90, 22)
    btnShowAll:SetPoint("LEFT", searchBox, "RIGHT", 15, 0)
    btnShowAll:SetText("Todos")

    local btnShowOnline = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnShowOnline:SetSize(90, 22)
    btnShowOnline:SetPoint("LEFT", btnShowAll, "RIGHT", 8, 0)
    btnShowOnline:SetText("En línea")

    local countText = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("LEFT", btnShowOnline, "RIGHT", 15, 0)
    countText:SetTextColor(0.75, 0.75, 0.75)

    local btnCSV = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnCSV:SetSize(110, 22)
    btnCSV:SetPoint("RIGHT", view, "RIGHT", -12, 0)
    btnCSV:SetPoint("TOP", searchBox, "TOP", 0, 1)
    btnCSV:SetText("Sheets / CSV")

    -- Misma tipografía y separación que la etiqueta "Buscar miembros"
    local exportLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    exportLabel:SetPoint("BOTTOMLEFT", btnCSV, "TOPLEFT", 2, 3)
    exportLabel:SetText("Exportar")
    btnCSV:SetScript("OnClick", function()
        if addonTable.CSV and addonTable.CSV.ShowFrame then addonTable.CSV.ShowFrame() end
    end)

    -- Encabezados ordenables
    local headerBg = CreateFrame("Frame", nil, view)
    headerBg:SetSize(850, 20)
    headerBg:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -10, -12)

    local headerButtons = {}

    local function UpdateSortIndicators()
        for _, hb in ipairs(headerButtons) do
            if hb.key == sortKey then
                hb.text:SetTextColor(1, 1, 1)
                hb.arrow:Show()
                if sortAsc then
                    hb.arrow:SetTexCoord(0, 0.5625, 1, 0)
                else
                    hb.arrow:SetTexCoord(0, 0.5625, 0, 1)
                end
            else
                hb.text:SetTextColor(1, 0.82, 0)
                hb.arrow:Hide()
            end
        end
    end

    for _, col in ipairs(MEMBER_COLUMNS) do
        local hb = CreateFrame("Button", nil, headerBg)
        hb:SetPoint("LEFT", headerBg, "LEFT", col.x, 0)
        hb:SetSize(col.w, 20)
        hb.key = col.key

        hb.text = hb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hb.text:SetPoint("LEFT", hb, "LEFT", 0, 0)
        hb.text:SetText(col.title)

        hb.arrow = hb:CreateTexture(nil, "OVERLAY")
        hb.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
        hb.arrow:SetSize(9, 8)
        hb.arrow:SetPoint("LEFT", hb.text, "RIGHT", 3, 0)
        hb.arrow:Hide()

        if col.key then
            hb:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            hb:SetScript("OnClick", function(self)
                if sortKey == self.key then
                    sortAsc = not sortAsc
                else
                    sortKey, sortAsc = self.key, true
                end
                UpdateSortIndicators()
                uiModule.RefreshList()
            end)
        end
        table.insert(headerButtons, hb)
    end

    local scrollFrame = CreateFrame("ScrollFrame", "GC_NewMembersScroll", view, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", headerBg, "BOTTOMLEFT", 0, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -28, 10)

    local scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(850, 1)
    scrollFrame:SetScrollChild(scrollChild)

    searchBox:SetScript("OnTextChanged", function(self)
        searchQuery = string.lower(strtrim(self:GetText() or ""))
        searchPlaceholder:SetShown((self:GetText() or "") == "")
        uiModule.RefreshList()
    end)

    btnShowAll:SetScript("OnClick", function()
        showOnlyOnline = false
        uiModule.RefreshList()
    end)

    btnShowOnline:SetScript("OnClick", function()
        showOnlyOnline = true
        uiModule.RefreshList()
    end)

    local function MatchesSearch(fullName, data)
        if searchQuery == "" then return true end
        local fields = { fullName, data.class, data.rank, data.role, data.focus, data.prof1, data.prof2, data.roster }
        for _, value in ipairs(fields) do
            if value and string.find(string.lower(tostring(value)), searchQuery, 1, true) then
                return true
            end
        end
        return false
    end

    -- Desglose de profesiones por expansión (solo propio o de miembros con GuildControl)
    local function BuildExpansionText(fullName)
        local lines = { "", "|cFFFFD100Profesiones por expansión|r" }
        local breakdown = addonTable.Professions and addonTable.Professions.GetExpansionBreakdown
            and addonTable.Professions.GetExpansionBreakdown(fullName)
        if not breakdown then
            table.insert(lines, "|cFF808080Sin datos. Solo está disponible para miembros que usan GuildControl.|r")
            return table.concat(lines, "\n")
        end
        for _, prof in ipairs(breakdown) do
            table.insert(lines, "|cFF00FFFF" .. prof.parent .. "|r")
            for _, e in ipairs(prof.entries) do
                local color = (e.max > 0 and e.level >= e.max) and "|cFF00FF00" or "|cFFFFFFFF"
                table.insert(lines, "  " .. e.name .. ": " .. color .. e.level .. "/" .. e.max .. "|r")
            end
        end
        return table.concat(lines, "\n")
    end

    local selectedFullName = nil

    -- Rol declarado por el propio jugador desde "Mi perfil" (si usa GuildControl)
    local function BuildDeclaredText(data)
        local declaredText = addonTable.Profiles and addonTable.Profiles.GetDeclaredText(data)
        if not declaredText then return "|cFF808080Rol declarado: no lo ha indicado|r\n" end
        local text = "Rol declarado: |cFF00FFFF" .. declaredText .. "|r\n"
        if data.declared.note and data.declared.note ~= "" then
            text = text .. "Nota: |cFFBFBFBF" .. data.declared.note .. "|r\n"
        end
        if data.roleSource == "officer" then text = text .. "|cFF808080(un oficial fijó el rol a mano)|r\n" end
        return text
    end

    -- Aviso en la vista previa si el miembro está en la lista negra
    local function BlacklistPreviewLine(fullName)
        local entry = addonTable.Blacklist and addonTable.Blacklist.Get(fullName)
        if not entry then return "" end
        return "|cFFFF3333¡En la lista negra! " .. addonTable.Blacklist.GetReasonLabel(entry.reason)
            .. ((entry.note and entry.note ~= "") and (": " .. entry.note) or "") .. "|r\n\n"
    end

    local function ShowMemberPreview(fullName, data)
        selectedMember = data
        selectedFullName = fullName
        SetPreviewText(
            "|cFFFFD100" .. fullName .. "|r\n\n" ..
            BlacklistPreviewLine(fullName) ..
            "Nivel: " .. (data.level or 0) .. "\n" ..
            "Clase: " .. (data.class or "Desconocida") .. "\n" ..
            "Rango: " .. (data.rank or "Recluta") .. "\n" ..
            "Rol: " .. (HasDefinedRole(data) and (RoleIcon(data.role) .. " " .. data.role) or "|cFF808080sin definir|r") .. "\n" ..
            ((addonTable.Profiles and addonTable.Profiles.GetCharTypeText(data)) and
                ("Personaje: |cFFFFD100" .. addonTable.Profiles.GetCharTypeText(data) .. "|r\n") or "") ..
            BuildDeclaredText(data) ..
            "Enfoque: " .. (FocusCell(data) ~= "" and FocusCell(data) or "|cFF808080sin definir|r") .. "\n" ..
            "Roster: " .. (data.roster or "Sin Roster") .. "\n\n" ..
            "Prof. 1: " .. (data.prof1 or "Ninguna") .. "\n" ..
            "Prof. 2: " .. (data.prof2 or "Ninguna") .. "\n\n" ..
            "Estado: " .. (data.isOnline and "|cFF00FF00En línea|r" or ("|cFF888888" .. (data.lastOnline or "Desconectado") .. "|r")) .. "\n" ..
            BuildExpansionText(fullName)
        )
    end

    -- Pool de filas: se reutilizan en cada refresco
    local rows = {}

    local function AcquireRow(index)
        local row = rows[index]
        if row then return row end

        row = CreateFrame("Button", nil, scrollChild)
        row:SetSize(850, MEMBER_ROW_HEIGHT - 2)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.05)

        row.cells = {}
        for i, col in ipairs(MEMBER_COLUMNS) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
            fs:SetWidth(col.w - 4)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            row.cells[i] = fs
        end

        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, button)
            if not self.fullName then return end
            ShowMemberPreview(self.fullName, self.data)
            if button == "RightButton" then ShowPlayerMenu(self, self.fullName) end
        end)

        rows[index] = row
        return row
    end

    uiModule.ResetMembersSort = function()
        selectedFullName = nil
        sortKey, sortAsc = DEFAULT_SORT_KEY, true
        UpdateSortIndicators()
    end

    uiModule.RefreshList = function()
        local list, total = {}, 0
        for fullName, data in pairs(GuildControlDB.members or {}) do
            total = total + 1
            if ((not showOnlyOnline) or data.isOnline) and MatchesSearch(fullName, data) then
                table.insert(list, { name = fullName, data = data })
            end
        end

        table.sort(list, function(a, b)
            local va, vb = MemberSortValue(a, sortKey), MemberSortValue(b, sortKey)
            if va ~= vb then
                if sortAsc then return va < vb end
                return va > vb
            end
            return a.name < b.name
        end)

        for _, r in ipairs(rows) do r:Hide() end

        for i, entry in ipairs(list) do
            local data = entry.data
            local row = AcquireRow(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -5 - (i - 1) * MEMBER_ROW_HEIGHT)
            row.bg:SetShown(i % 2 == 0)
            row.fullName, row.data = entry.name, data

            local isOnline = data.isOnline
            local hex = isOnline and addonTable.GetClassColorHex(data.class) or "888888"
            local dim = "888888"
            local values = {
                { i, dim },
                { data.level or 0, hex },
                { data.class or "Desconocida", hex },
                { entry.name, hex },
                { data.rank or "Recluta", isOnline and "FFFFFF" or dim },
                { CharTypeCell(data), isOnline and "FFD100" or dim },
                { RoleCellText(data), RoleCellColor(data, isOnline) },
                { FocusCell(data), isOnline and "FFFFFF" or dim },
                { ProfessionCell(data.prof1), isOnline and "FFFFFF" or dim },
                { ProfessionCell(data.prof2), isOnline and "FFFFFF" or dim },
                { RosterCell(data.roster), isOnline and "00FFFF" or dim },
                { data.lastOnline or "Online", isOnline and "00FF00" or dim },
            }
            for c, v in ipairs(values) do
                row.cells[c]:SetText("|cFF" .. v[2] .. tostring(v[1]) .. "|r")
            end
            row:Show()
        end

        scrollChild:SetHeight(math.max(1, #list * MEMBER_ROW_HEIGHT + 10))
        countText:SetText("Mostrando " .. #list .. " de " .. total)

        -- Mantener al día la vista previa del miembro seleccionado (p. ej. al llegar su desglose)
        local selectedData = selectedFullName and GuildControlDB.members[selectedFullName]
        if selectedData and activeTab == "Miembros" then
            ShowMemberPreview(selectedFullName, selectedData)
        end
    end

    UpdateSortIndicators()
    containers.views["Miembros"] = view
end

-- =========================================================================
-- 7. VISTA DE LOGROS (CONSUME MODULES/ACHIEVEMENTS.LUA)
-- =========================================================================
local function ShowAchievementTooltip(row)
    if not row.achId or not addonTable.Achievements then return end
    local d = addonTable.Achievements.GetDetails(row.achId)
    if not d then return end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(d.name, 1, 0.82, 0)

    if d.description ~= "" then
        GameTooltip:AddLine(d.description, 1, 1, 1, true)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Puntos", tostring(d.points), 0.7, 0.7, 0.7, 1, 0.82, 0)

    if d.rewardText ~= "" then
        GameTooltip:AddLine("Recompensa: " .. d.rewardText, 0.4, 1, 0.4, true)
    end

    if d.completed then
        GameTooltip:AddDoubleLine("Completado", d.date or "-", 0.7, 0.7, 0.7, 0, 1, 0)
        if d.earnedBy then
            GameTooltip:AddDoubleLine("Por", d.earnedBy, 0.7, 0.7, 0.7, 0, 1, 1)
        end
    else
        if #d.criteria > 0 then
            GameTooltip:AddDoubleLine("Criterios", d.criteriaDone .. "/" .. #d.criteria, 0.7, 0.7, 0.7, 1, 1, 1)
        end
        GameTooltip:AddLine("Pendiente", 1, 0.2, 0.2)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Clic: vista previa  |  Clic derecho: abrir en Blizzard", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function BuildAchievementsView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local currentCategoryId = nil
    local searchQuery = ""
    local filterState = "TODOS"
    local filterSeason = false

    local achRows = {}      -- pool de filas de logros
    local catButtons = {}   -- pool de botones de categoría

    -- 7.1 Encabezado de estadísticas de Hermandad
    local headerFrame = CreateBackdropBox(view, 880, 45, "TOPLEFT", view, "TOPLEFT", 10, -10)

    local pointsText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pointsText:SetPoint("LEFT", headerFrame, "LEFT", 15, 0)
    pointsText:SetText("Puntos: |cFFFFD1000|r")

    local completedText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    completedText:SetPoint("LEFT", pointsText, "RIGHT", 30, 0)
    completedText:SetText("Completados: |cFF00FF000/0|r")

    local lastAchText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lastAchText:SetPoint("RIGHT", headerFrame, "RIGHT", -15, 0)
    lastAchText:SetWidth(290)
    lastAchText:SetJustifyH("RIGHT")
    lastAchText:SetWordWrap(false)
    lastAchText:SetText("Último logro: |cFF808080Ninguno|r")

    -- Ver los logros de la hermandad o los del personaje (los scripts se asignan más abajo)
    local btnModeGuild = CreateFrame("Button", nil, headerFrame, "UIPanelButtonTemplate")
    btnModeGuild:SetSize(100, 22)
    btnModeGuild:SetPoint("LEFT", headerFrame, "LEFT", 380, 0)
    btnModeGuild:SetText("Hermandad")

    local btnModePlayer = CreateFrame("Button", nil, headerFrame, "UIPanelButtonTemplate")
    btnModePlayer:SetSize(100, 22)
    btnModePlayer:SetPoint("LEFT", btnModeGuild, "RIGHT", 6, 0)
    btnModePlayer:SetText("Personaje")

    -- 7.2 Panel Izquierdo: Categorías de Hermandad
    local catPanel = CreateBackdropBox(view, 200, 445, "TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -5)

    local catScroll = CreateFrame("ScrollFrame", "GC_AchCatScroll", catPanel, "UIPanelScrollFrameTemplate")
    catScroll:SetPoint("TOPLEFT", catPanel, "TOPLEFT", 5, -5)
    catScroll:SetPoint("BOTTOMRIGHT", catPanel, "BOTTOMRIGHT", -25, 5)

    local catChild = CreateFrame("Frame")
    catChild:SetSize(165, 1)
    catScroll:SetScrollChild(catChild)

    -- 7.3 Panel Derecho: Buscador, Filtros y Lista de Logros
    local rightPanel = CreateBackdropBox(view, 675, 445, "TOPRIGHT", headerFrame, "BOTTOMRIGHT", 0, -5)

    -- Etiqueta y caja dentro del panel (antes la etiqueta quedaba por encima del borde)
    local searchLabel = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 12, -8)
    searchLabel:SetText("Buscar logros")

    local searchBox = CreateFrame("EditBox", "GC_AchSearchBox", rightPanel, "InputBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 5, -4)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
    searchPlaceholder:SetText("Nombre del logro...")

    local btnFilterAll = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    btnFilterAll:SetSize(65, 22)
    btnFilterAll:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    btnFilterAll:SetText("Todos")

    local btnFilterDone = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    btnFilterDone:SetSize(85, 22)
    btnFilterDone:SetPoint("LEFT", btnFilterAll, "RIGHT", 4, 0)
    btnFilterDone:SetText("Completados")

    local btnFilterPending = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    btnFilterPending:SetSize(75, 22)
    btnFilterPending:SetPoint("LEFT", btnFilterDone, "RIGHT", 4, 0)
    btnFilterPending:SetText("Pendientes")

    -- Logros de temporada: busca en todas las categorías de hermandad
    local chkSeason = CreateFrame("CheckButton", "GC_ChkSeasonAch", rightPanel, "UICheckButtonTemplate")
    chkSeason:SetPoint("LEFT", btnFilterPending, "RIGHT", 8, 0)
    _G[chkSeason:GetName() .. "Text"]:SetText("Logros de temporada")
    chkSeason:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Logros de temporada", 1, 0.82, 0)
        GameTooltip:AddLine("Muestra, de todas las categorías, los logros de temporada (Mítica+, bandas, JcJ) y los de eventos del mundo.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    chkSeason:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Encabezados de la Tabla
    local achHeader = CreateFrame("Frame", nil, rightPanel)
    achHeader:SetSize(655, 20)
    achHeader:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -5, -12)

    local function AddAchHeader(t, x, w)
        local fs = achHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", achHeader, "LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetText(t)
    end
    AddAchHeader("Estado", 5, 80)
    AddAchHeader("Título del Logro", 90, 360)
    AddAchHeader("Fecha / Progreso", 460, 180)

    -- ScrollFrame de Logros
    local achScroll = CreateFrame("ScrollFrame", "GC_AchScrollFrame", rightPanel, "UIPanelScrollFrameTemplate")
    achScroll:SetPoint("TOPLEFT", achHeader, "BOTTOMLEFT", 0, -5)
    achScroll:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -25, 10)

    local achChild = CreateFrame("Frame")
    achChild:SetSize(650, 1)
    achScroll:SetScrollChild(achChild)

    -- ---------------------------------------------------------------------
    -- Pool de filas de logros (se reutilizan, no se recrean)
    -- ---------------------------------------------------------------------
    local function AcquireAchRow(index)
        local row = achRows[index]
        if row then return row end

        row = CreateFrame("Button", nil, achChild)
        row:SetSize(650, 24)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.05)

        -- Marca del logro seleccionado (por ejemplo al llegar desde el Resumen)
        row.selected = row:CreateTexture(nil, "BORDER")
        row.selected:SetAllPoints()
        row.selected:SetColorTexture(1, 0.82, 0, 0.18)
        row.selected:Hide()

        row.statusFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.statusFs:SetPoint("LEFT", row, "LEFT", 5, 0)
        row.statusFs:SetWidth(80)
        row.statusFs:SetJustifyH("LEFT")

        row.iconTex = row:CreateTexture(nil, "ARTWORK")
        row.iconTex:SetSize(20, 20)
        row.iconTex:SetPoint("LEFT", row, "LEFT", 90, 0)

        row.titleFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.titleFs:SetPoint("LEFT", row.iconTex, "RIGHT", 8, 0)
        row.titleFs:SetWidth(330)
        row.titleFs:SetJustifyH("LEFT")

        row.dateFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.dateFs:SetPoint("LEFT", row, "LEFT", 460, 0)
        row.dateFs:SetWidth(180)
        row.dateFs:SetJustifyH("LEFT")

        row:SetScript("OnClick", function(self, button)
            if not self.achId then return end
            if button == "RightButton" or IsShiftKeyDown() then
                if addonTable.Achievements then
                    addonTable.Achievements.OpenAchievement(self.achId)
                end
            else
                uiModule.ShowAchievementPreview(self.achId)
            end
        end)

        row:SetScript("OnEnter", ShowAchievementTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        achRows[index] = row
        return row
    end

    -- ---------------------------------------------------------------------
    -- Categorías de hermandad
    -- ---------------------------------------------------------------------
    local function UpdateCategorySelection()
        for _, btn in ipairs(catButtons) do
            if btn:IsShown() then
                btn:SetEnabled(btn.catId ~= currentCategoryId)
            end
        end
    end

    local function BuildGuildCategories()
        for _, b in ipairs(catButtons) do b:Hide() end

        if not addonTable.Achievements then return end
        local categories = addonTable.Achievements.GetCategories()
        local yOffset = -5

        for i, cat in ipairs(categories) do
            local btn = catButtons[i]
            if not btn then
                btn = CreateFrame("Button", nil, catChild, "UIPanelButtonTemplate")
                btn:SetSize(165, 22)
                btn:SetScript("OnClick", function(self)
                    currentCategoryId = self.catId
                    selectedAchievementId = nil
                    SetPreviewText(PREVIEW_DEFAULT_TEXT)
                    uiModule.RefreshAchievements()
                end)
                catButtons[i] = btn
            end

            btn.catId = cat.id
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", catChild, "TOPLEFT", cat.isChild and 15 or 5, yOffset)
            btn:SetWidth(cat.isChild and 150 or 165)
            btn:SetText(cat.title)
            btn:Show()

            if not currentCategoryId then currentCategoryId = cat.id end
            yOffset = yOffset - 25
        end

        catChild:SetHeight(math.max(1, #categories * 25 + 10))
        UpdateCategorySelection()
    end

    -- ---------------------------------------------------------------------
    -- Encabezado de estadísticas
    -- ---------------------------------------------------------------------
    local function UpdateGuildSummary()
        local stats = addonTable.Achievements and addonTable.Achievements.GetStats()
        if not stats then return end

        pointsText:SetText("Puntos: |cFFFFD100" .. (stats.totalPoints or 0) .. "|r")
        completedText:SetText("Completados: |cFF00FF00" .. (stats.completedCount or 0) .. "/" .. (stats.totalCount or 0) .. "|r")

        if stats.latestName and stats.latestName ~= "Ninguno" then
            local dateStr = (stats.latestDate and stats.latestDate ~= "") and (" (" .. stats.latestDate .. ")") or ""
            lastAchText:SetText("Último logro: |cFFFFD100" .. stats.latestName .. "|r" .. dateStr)
        else
            lastAchText:SetText("Último logro: |cFF808080Ninguno|r")
        end
    end

    -- ---------------------------------------------------------------------
    -- Renderizado de la tabla de logros
    -- ---------------------------------------------------------------------
    uiModule.RefreshAchievements = function()
        if not achChild or not addonTable.Achievements then return end

        addonTable.Achievements.EnsureLoaded()

        if #catButtons == 0 or not catButtons[1]:IsShown() then
            BuildGuildCategories()
        else
            UpdateCategorySelection()
        end

        UpdateGuildSummary()

        for _, r in ipairs(achRows) do r:Hide() end
        if not currentCategoryId and not filterSeason then
            achChild:SetHeight(1)
            return
        end

        -- Con el filtro de temporada se recorren todas las categorías de hermandad
        local categoriesToScan = {}
        if filterSeason then
            for _, cat in ipairs(addonTable.Achievements.GetCategories()) do
                table.insert(categoriesToScan, cat)
            end
        else
            categoriesToScan[1] = { id = currentCategoryId }
        end

        local yOffset = -5
        local rowIndex = 0
        local seen = {}

        for _, cat in ipairs(categoriesToScan) do
            local numAchievements = GetCategoryNumAchievements(cat.id, true) or 0
            for i = 1, numAchievements do
                local id, name, points, completed, month, day, year, description, _, icon = GetAchievementInfo(cat.id, i)

                if id and not seen[id] then
                    seen[id] = true
                    local passSearch = (searchQuery == "") or string.find(string.lower(name or ""), searchQuery, 1, true)

                    local passState = true
                    if filterState == "COMPLETADOS" and not completed then passState = false end
                    if filterState == "PENDIENTES" and completed then passState = false end

                    local passSeason = (not filterSeason)
                        or addonTable.Achievements.IsSeasonal(name, description, cat.title)

                    if passSearch and passState and passSeason then
                        rowIndex = rowIndex + 1
                        local row = AcquireAchRow(rowIndex)

                        row.achId = id
                        row.selected:SetShown(id == selectedAchievementId)
                        row:ClearAllPoints()
                        row:SetPoint("TOPLEFT", achChild, "TOPLEFT", 0, yOffset)
                        row.bg:SetShown(rowIndex % 2 == 0)
                        row.iconTex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                        row.titleFs:SetText(name or "Desconocido")
                        row.statusFs:SetText(completed and "|cFF00FF00Completado|r" or "|cFFFF3333Pendiente|r")
                        row.dateFs:SetText(completed and addonTable.Achievements.FormatDate(day, month, year) or "|cFF808080En progreso|r")
                        row:Show()

                        yOffset = yOffset - 26
                    end
                end
            end
        end

        achChild:SetHeight(math.max(1, rowIndex * 26 + 10))

        -- Si hay un logro seleccionado, mantener la vista previa actualizada (con su botón)
        if selectedAchievementId and activeTab == "Logros" then
            ShowAchievementPreviewWithButton(selectedAchievementId)
        end
    end

    searchBox:SetScript("OnTextChanged", function(self)
        searchQuery = string.lower(self:GetText() or "")
        searchPlaceholder:SetShown((self:GetText() or "") == "")
        uiModule.RefreshAchievements()
    end)

    btnFilterAll:SetScript("OnClick", function() filterState = "TODOS"; uiModule.RefreshAchievements() end)
    btnFilterDone:SetScript("OnClick", function() filterState = "COMPLETADOS"; uiModule.RefreshAchievements() end)
    btnFilterPending:SetScript("OnClick", function() filterState = "PENDIENTES"; uiModule.RefreshAchievements() end)
    chkSeason:SetScript("OnClick", function(self) filterSeason = self:GetChecked() and true or false; uiModule.RefreshAchievements() end)

    -- Cambio entre logros de la hermandad y del personaje: se reconstruyen las categorías
    local function SetAchievementMode(newMode)
        if not addonTable.Achievements then return end
        addonTable.Achievements.SetMode(newMode)
        currentCategoryId = nil
        selectedAchievementId = nil
        SetPreviewText(PREVIEW_DEFAULT_TEXT)
        BuildGuildCategories()
        btnModeGuild:SetEnabled(newMode ~= "guild")
        btnModePlayer:SetEnabled(newMode ~= "player")
        uiModule.RefreshAchievements()
    end
    btnModeGuild:SetScript("OnClick", function() SetAchievementMode("guild") end)
    btnModePlayer:SetScript("OnClick", function() SetAchievementMode("player") end)
    btnModeGuild:SetEnabled(false)

    -- Abre un logro concreto: modo, categoría, filtros limpios, desplazamiento y vista previa.
    -- Lo usa el Resumen para llevar a la sección Logros al hacer clic en una noticia.
    uiModule.FocusAchievement = function(id, mode)
        if not id or not addonTable.Achievements then return end
        SetAchievementMode(mode or "guild")
        filterState, filterSeason = "TODOS", false
        chkSeason:SetChecked(false)
        searchBox:SetText("")
        local categoryId = GetAchievementCategory and GetAchievementCategory(id)
        if categoryId then currentCategoryId = categoryId end
        selectedAchievementId = id
        uiModule.RefreshAchievements()
        UpdateCategorySelection()

        for index, row in ipairs(achRows) do
            if row:IsShown() and row.achId == id then
                local maxScroll = achScroll:GetVerticalScrollRange() or 0
                achScroll:SetVerticalScroll(math.min(maxScroll, math.max(0, (index - 3) * 26)))
                break
            end
        end
        uiModule.ShowAchievementPreview(id)
    end

    containers.views["Logros"] = view
end

-- =========================================================================
-- 8. VISTAS PLACEHOLDER
-- =========================================================================
local function BuildPlaceholderView(parent, tabName)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local text = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER", view, "CENTER", 0, 0)
    text:SetText("Sección: |cFFFFD100" .. tabName .. "|r\n\n(En desarrollo)")

    containers.views[tabName] = view
end

-- =========================================================================
-- 8a. VISTA ROSTER (CONSUME MODULES/ROSTER.LUA)
-- =========================================================================
local ROSTER_ROW_HEIGHT = 18

-- Nombre corto con el color de su clase (gris si está desconectado)
local function ColoredMemberName(fullName)
    local m = GuildControlDB.members[fullName] or {}
    local short = string.match(fullName, "^([^-]+)") or fullName
    local hex = addonTable.GetClassColorHex(m.class)
    if not m.isOnline then return "|cFF" .. hex .. short .. "|r|cFF808080 ·|r" end
    return "|cFF" .. hex .. short .. "|r"
end

local function ShowMemberTooltip(owner, fullName)
    local R = addonTable.Roster
    local m = GuildControlDB.members[fullName] or {}
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(fullName, 1, 0.82, 0)
    GameTooltip:AddDoubleLine("Clase", R.GetClassName(m.class), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("Nivel", tostring(m.level or "?"), 0.7, 0.7, 0.7, 1, 1, 1)
    local hasRole = R.HasDefinedRole(m)
    GameTooltip:AddDoubleLine("Rol", hasRole and (RoleIcon(m.role) .. " " .. m.role) or "sin definir", 0.7, 0.7, 0.7, 1, 1, 1)
    local charType = addonTable.Profiles and addonTable.Profiles.GetCharTypeText(m)
    if charType then GameTooltip:AddDoubleLine("Personaje", charType, 0.7, 0.7, 0.7, 1, 0.82, 0) end
    local declaredText = addonTable.Profiles and addonTable.Profiles.GetDeclaredText(m)
    if declaredText then
        GameTooltip:AddDoubleLine("Declarado", declaredText, 0.7, 0.7, 0.7, 0, 1, 1)
        if m.declared.note and m.declared.note ~= "" then
            GameTooltip:AddLine(m.declared.note, 0.75, 0.75, 0.75, true)
        end
    end
    GameTooltip:AddDoubleLine("Rango", m.rank or "-", 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("Estado", m.isOnline and "En línea" or (m.lastOnline or "Desconectado"),
        0.7, 0.7, 0.7, m.isOnline and 0 or 0.6, m.isOnline and 1 or 0.6, m.isOnline and 0 or 0.6)
    -- Asistencia en las fechas del roster seleccionado
    local stats = R.GetAttendanceStats(R.GetSelected(), fullName)
    if stats.percent then
        GameTooltip:AddDoubleLine("Asistencia", stats.percent .. "% (" .. (stats.present + stats.late) .. "/" .. stats.counted .. ")",
            0.7, 0.7, 0.7, 1, 1, 1)
    end
    GameTooltip:Show()
end

-- Modo "Fechas" del roster: lista de fechas de banda y hoja de asistencia.
-- onChanged() se llama tras cada cambio para refrescar el resumen de la vista previa.
local function BuildRosterDatesPanel(parent, onChanged)
    local R = addonTable.Roster
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -40)
    panel:SetSize(880, 470)
    panel:Hide()

    local selectedEventId = nil
    local currentRoster = nil
    local RefreshPanel   -- declaración adelantada

    -- ---------------------------------------------------------------------
    -- Izquierda: alta de fechas y lista
    -- ---------------------------------------------------------------------
    local left = CreateBackdropBox(panel, 270, 470, "TOPLEFT", panel, "TOPLEFT", 0, 0)

    local leftTitle = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftTitle:SetPoint("TOPLEFT", left, "TOPLEFT", 10, -10)
    leftTitle:SetText("Fechas de banda")

    local function SmallInput(labelText, width, anchor, x, y)
        local label = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
        label:SetText(labelText)
        local input = CreateFrame("EditBox", nil, left, "InputBoxTemplate")
        input:SetSize(width, 20)
        input:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 5, -2)
        input:SetAutoFocus(false)
        input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return label, input
    end

    local dateLabel, dateInput = SmallInput("Fecha (DD/MM/AAAA)", 100, leftTitle, 0, -10)
    local timeLabel, timeInput = SmallInput("Hora", 50, leftTitle, 130, -10)
    timeInput:SetMaxLetters(5)
    local noteLabel, noteInput = SmallInput("Nota (opcional)", 240, dateInput, -5, -8)
    noteInput:SetMaxLetters(40)

    local btnAdd = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    btnAdd:SetSize(110, 22)
    btnAdd:SetPoint("TOPLEFT", noteInput, "BOTTOMLEFT", -5, -8)
    btnAdd:SetText("Añadir fecha")

    local btnImport = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    btnImport:SetSize(134, 22)
    btnImport:SetPoint("LEFT", btnAdd, "RIGHT", 6, 0)
    btnImport:SetText("Importar calendario")

    local listScroll = CreateFrame("ScrollFrame", "GC_RosterDatesScroll", left, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", btnAdd, "BOTTOMLEFT", 0, -10)
    listScroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -26, 24)
    local listChild = CreateFrame("Frame")
    listChild:SetSize(234, 1)
    listScroll:SetScrollChild(listChild)

    local listHint = left:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listHint:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 10, 8)
    listHint:SetText("Clic: ver asistencia · Clic derecho: eliminar")

    local function ResetForm()
        dateInput:SetText(date("%d/%m/%Y"))
        timeInput:SetText("21:00")
        noteInput:SetText("")
    end

    btnAdd:SetScript("OnClick", function()
        local event, err = R.AddEvent(currentRoster, dateInput:GetText(), timeInput:GetText(), noteInput:GetText())
        if not event then
            PrintGC("|cFFFF3333" .. err .. "|r")
            return
        end
        selectedEventId = event.id
        noteInput:SetText("")
        RefreshPanel()
    end)

    -- El calendario carga sus datos de forma asíncrona: se reintenta al llegar CALENDAR_UPDATE_EVENT_LIST
    local calendarFrame = CreateFrame("Frame")
    local waitingCalendar = false
    local function DoImport(silentIfNone)
        local added = R.ImportCalendarEvents(currentRoster)
        if added == nil then
            PrintGC("|cFFFF3333El calendario no está disponible.|r")
        elseif added > 0 or not silentIfNone then
            PrintGC("Fechas importadas del calendario: |cFFFFD100" .. added .. "|r.")
        end
        RefreshPanel()
        return added
    end
    calendarFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("CALENDAR_UPDATE_EVENT_LIST")
        if waitingCalendar then
            waitingCalendar = false
            DoImport(false)
        end
    end)
    btnImport:SetScript("OnClick", function()
        if C_Calendar and C_Calendar.OpenCalendar then
            pcall(C_Calendar.OpenCalendar)
            local added = DoImport(true)
            if added == 0 then
                waitingCalendar = true
                calendarFrame:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
            end
        else
            DoImport(false)
        end
    end)

    local eventRows = {}
    local function AcquireEventRow(index)
        local row = eventRows[index]
        if row then return row end
        row = CreateFrame("Button", nil, listChild)
        row:SetSize(234, 30)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 0.82, 0, 0.15)
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)
        row.dateFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.dateFs:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -3)
        row.countFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.countFs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -3)
        row.noteFs = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.noteFs:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 3)
        row.noteFs:SetWidth(226)
        row.noteFs:SetJustifyH("LEFT")
        row.noteFs:SetWordWrap(false)
        row:SetScript("OnClick", function(self, button)
            local event = R.GetEvent(currentRoster, self.eventId)
            if not event then return end
            if button == "RightButton" then
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(R.FormatEventDate(event))
                    root:CreateButton("|cFFFF3333Eliminar fecha|r", function()
                        R.DeleteEvent(currentRoster, event)
                        if selectedEventId == event.id then selectedEventId = nil end
                        RefreshPanel()
                    end)
                end)
            else
                selectedEventId = event.id
                RefreshPanel()
            end
        end)
        eventRows[index] = row
        return row
    end

    -- ---------------------------------------------------------------------
    -- Derecha: hoja de asistencia de la fecha seleccionada
    -- ---------------------------------------------------------------------
    local right = CreateBackdropBox(panel, 604, 470, "TOPLEFT", left, "TOPRIGHT", 6, 0)

    local sheetTitle = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sheetTitle:SetPoint("TOPLEFT", right, "TOPLEFT", 10, -10)
    sheetTitle:SetWidth(584)
    sheetTitle:SetJustifyH("LEFT")
    sheetTitle:SetWordWrap(false)

    local function SheetButton(text, width, anchor, onClick)
        local btn = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
        btn:SetSize(width, 22)
        if anchor then
            btn:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
        else
            btn:SetPoint("TOPLEFT", sheetTitle, "BOTTOMLEFT", 0, -8)
        end
        btn:SetText(text)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    local function SelectedEvent()
        return currentRoster and R.GetEvent(currentRoster, selectedEventId)
    end

    local btnFromGroup = SheetButton("Tomar del grupo actual", 170, nil, function()
        local event = SelectedEvent()
        if not event then return end
        local present = R.TakeAttendanceFromGroup(currentRoster, event)
        PrintGC("Asistencia tomada del grupo: |cFFFFD100" .. present .. "|r integrantes presentes.")
        RefreshPanel()
    end)
    local btnAllPresent = SheetButton("Titulares presentes", 140, btnFromGroup, function()
        local event = SelectedEvent()
        if not event then return end
        R.MarkAllStarters(currentRoster, event, "present")
        RefreshPanel()
    end)
    SheetButton("Limpiar marcas", 120, btnAllPresent, function()
        local event = SelectedEvent()
        if not event then return end
        R.ClearAttendance(event)
        RefreshPanel()
    end)

    -- Cabeceras de la tabla
    local COLS = { name = 6, slot = 170, status = 236, statusWidth = 64, history = 500 }
    local headerRow = CreateFrame("Frame", nil, right)
    headerRow:SetSize(584, 16)
    headerRow:SetPoint("TOPLEFT", btnFromGroup, "BOTTOMLEFT", 0, -10)
    local function Header(text, x)
        local fs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", headerRow, "LEFT", x, 0)
        fs:SetText(text)
    end
    Header("Integrante", COLS.name)
    Header("Puesto", COLS.slot)
    Header("Marca", COLS.status)
    Header("Historial", COLS.history)

    local sheetScroll = CreateFrame("ScrollFrame", "GC_RosterSheetScroll", right, "UIPanelScrollFrameTemplate")
    sheetScroll:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -4)
    sheetScroll:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -26, 28)
    local sheetChild = CreateFrame("Frame")
    sheetChild:SetSize(568, 1)
    sheetScroll:SetScrollChild(sheetChild)

    local sheetSummary = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sheetSummary:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 10, 9)

    local emptyText = right:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", right, "CENTER", 0, 0)

    local SLOT_SHORT = { tank = "Tanque", healer = "Sanador", dps = "DPS", bench = "Suplente", gone = "Fuera" }

    local sheetRows = {}
    local function AcquireSheetRow(index)
        local row = sheetRows[index]
        if row then return row end
        row = CreateFrame("Frame", nil, sheetChild)
        row:SetSize(568, 20)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.05)
        row.nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.nameFs:SetPoint("LEFT", row, "LEFT", COLS.name, 0)
        row.nameFs:SetWidth(160)
        row.nameFs:SetJustifyH("LEFT")
        row.nameFs:SetWordWrap(false)
        row.slotFs = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.slotFs:SetPoint("LEFT", row, "LEFT", COLS.slot, 0)
        row.historyFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.historyFs:SetPoint("LEFT", row, "LEFT", COLS.history, 0)

        row.statusButtons = {}
        for i, status in ipairs(R.ATTENDANCE) do
            local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            btn:SetSize(COLS.statusWidth - 2, 18)
            btn:SetPoint("LEFT", row, "LEFT", COLS.status + (i - 1) * COLS.statusWidth, 0)
            btn.status = status
            btn:SetScript("OnClick", function(self)
                local event = SelectedEvent()
                if not event or not row.fullName then return end
                R.SetAttendance(event, row.fullName, self.status)
                RefreshPanel()
            end)
            row.statusButtons[status] = btn
        end
        sheetRows[index] = row
        return row
    end

    local function HistoryText(fullName)
        local stats = R.GetAttendanceStats(currentRoster, fullName)
        if not stats.percent then return "|cFF808080-|r" end
        local color = stats.percent >= 90 and "00FF00" or (stats.percent >= 70 and "FFD100" or "FF3333")
        return "|cFF" .. color .. stats.percent .. "%|r |cFF808080(" .. (stats.present + stats.late) .. "/" .. stats.counted .. ")|r"
    end

    local function RefreshSheet()
        for _, row in ipairs(sheetRows) do row:Hide() end
        local event = SelectedEvent()
        if not event then
            sheetTitle:SetText("Asistencia")
            emptyText:SetText("Añade o selecciona una fecha para pasar lista.")
            emptyText:Show()
            sheetSummary:SetText("")
            sheetChild:SetHeight(1)
            return
        end
        emptyText:Hide()
        local note = (event.note and event.note ~= "") and ("  |cFFBFBFBF" .. event.note .. "|r") or ""
        sheetTitle:SetText("Asistencia · " .. R.FormatEventDate(event) .. note)

        local list = R.GetAttendanceList(currentRoster, event)
        for i, entry in ipairs(list) do
            local row = AcquireSheetRow(i)
            row:SetPoint("TOPLEFT", sheetChild, "TOPLEFT", 0, -(i - 1) * 21)
            row.bg:SetShown(i % 2 == 0)
            row.fullName = entry.name
            row.nameFs:SetText(ColoredMemberName(entry.name))
            row.slotFs:SetText(SLOT_SHORT[entry.slot] or entry.slot)
            row.historyFs:SetText(HistoryText(entry.name))
            local current = event.attendance[entry.name]
            for status, btn in pairs(row.statusButtons) do
                local label = R.ATTENDANCE_LABELS[status]
                if current == status then
                    btn:SetText("|cFF" .. R.ATTENDANCE_COLORS[status] .. label .. "|r")
                else
                    btn:SetText("|cFF808080" .. label .. "|r")
                end
            end
            row:Show()
        end
        sheetChild:SetHeight(math.max(1, #list * 21))

        local counts = R.GetEventCounts(event)
        sheetSummary:SetText(string.format("|cFF00FF00Presentes %d|r   |cFFFFD100Tarde %d|r   |cFFFF3333Ausentes %d|r   |cFF66B3FFJustificadas %d|r   |cFF808080Sin marcar %d|r",
            counts.present, counts.late, counts.absent, counts.excused,
            math.max(0, #list - counts.present - counts.late - counts.absent - counts.excused)))
    end

    local function RefreshList()
        for _, row in ipairs(eventRows) do row:Hide() end
        local events = R.GetEventsSorted(currentRoster)
        if selectedEventId and not R.GetEvent(currentRoster, selectedEventId) then selectedEventId = nil end
        if not selectedEventId and events[1] then selectedEventId = events[1].id end

        for i, event in ipairs(events) do
            local row = AcquireEventRow(i)
            row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -(i - 1) * 32)
            row.eventId = event.id
            row.bg:SetShown(event.id == selectedEventId)
            row.dateFs:SetText(R.FormatEventDate(event))
            local counts = R.GetEventCounts(event)
            row.countFs:SetText("|cFF00FF00" .. (counts.present + counts.late) .. "|r|cFF808080 / |r|cFFFF3333" .. counts.absent .. "|r")
            row.noteFs:SetText(event.note or "")
            row:Show()
        end
        listChild:SetHeight(math.max(1, #events * 32))
    end

    RefreshPanel = function()
        if not currentRoster then return end
        RefreshList()
        RefreshSheet()
        if onChanged then onChanged() end
    end

    -- La vista Roster llama a esto al cambiar de roster o de modo
    function panel.SetRoster(roster)
        if currentRoster ~= roster then selectedEventId = nil end
        currentRoster = roster
        RefreshList()
        RefreshSheet()
    end

    ResetForm()
    return panel
end

local function BuildRosterView(parent)
    local R = addonTable.Roster
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local Refresh   -- declaración adelantada

    -- ---------------------------------------------------------------------
    -- Barra superior: selector, nombre y crear/duplicar/eliminar
    -- ---------------------------------------------------------------------
    local dropRoster = CreateFrame("DropdownButton", "GC_RosterSelect", view, "WowStyle1DropdownTemplate")
    dropRoster:SetPoint("TOPLEFT", view, "TOPLEFT", 10, -10)
    dropRoster:SetWidth(150)

    local nameInput = CreateFrame("EditBox", nil, view, "InputBoxTemplate")
    nameInput:SetSize(150, 20)
    nameInput:SetPoint("LEFT", dropRoster, "RIGHT", 16, 0)
    nameInput:SetAutoFocus(false)
    nameInput:SetMaxLetters(30)
    -- La ayuda va en el tooltip (antes una etiqueta encima se salía del marco)
    nameInput:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Nombre del roster", 1, 1, 1)
        GameTooltip:AddLine("Escríbelo y pulsa Enter para guardarlo, o elige una banda con el botón Banda.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    nameInput:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function SaveName()
        R.Rename(R.GetSelected(), nameInput:GetText())
        nameInput:ClearFocus()
        Refresh()
    end
    nameInput:SetScript("OnEnterPressed", SaveName)
    nameInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetText(R.GetSelected().name)
    end)

    -- Bandas del diario de encuentros del juego: al elegir una, el roster toma su nombre
    -- y "Añadir jefe" ofrece sus jefes
    local btnRaid = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnRaid:SetSize(64, 22)
    btnRaid:SetPoint("LEFT", nameInput, "RIGHT", 6, 0)
    btnRaid:SetText("Banda")
    btnRaid:SetScript("OnClick", function(self)
        local tiers = R.GetRaidTiers(3)
        if #tiers == 0 then
            PrintGC("|cFFFF3333No se pudo leer el diario de encuentros del juego.|r")
            return
        end
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle("Bandas del diario de encuentros")
            for i, tier in ipairs(tiers) do
                -- La expansión actual se muestra directamente; las anteriores en submenú
                local parentMenu = root
                if i > 1 then parentMenu = root:CreateButton(tier.name) else root:CreateTitle(tier.name) end
                for _, raid in ipairs(tier.raids) do
                    parentMenu:CreateButton(raid.name, function()
                        R.SetRaid(R.GetSelected(), raid)
                        Refresh()
                    end)
                end
            end
        end)
    end)

    local btnNew = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnNew:SetSize(70, 22)
    btnNew:SetPoint("LEFT", btnRaid, "RIGHT", 8, 0)
    btnNew:SetText("Nuevo")
    btnNew:SetScript("OnClick", function()
        R.Create()
        Refresh()
        nameInput:SetFocus()
        nameInput:HighlightText()
    end)

    local btnDuplicate = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnDuplicate:SetSize(80, 22)
    btnDuplicate:SetPoint("LEFT", btnNew, "RIGHT", 6, 0)
    btnDuplicate:SetText("Duplicar")
    btnDuplicate:SetScript("OnClick", function()
        R.Duplicate(R.GetSelected())
        Refresh()
    end)

    -- Eliminar pide un segundo clic en 4 s para confirmar
    local btnDelete = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnDelete:SetSize(90, 22)
    btnDelete:SetPoint("LEFT", btnDuplicate, "RIGHT", 6, 0)
    btnDelete:SetText("Eliminar")
    local deleteArmedUntil = 0
    btnDelete:SetScript("OnClick", function(self)
        if GetTime() < deleteArmedUntil then
            deleteArmedUntil = 0
            self:SetText("Eliminar")
            R.Delete(R.GetSelected())
            Refresh()
        else
            deleteArmedUntil = GetTime() + 4
            self:SetText("|cFFFF3333¿Seguro?|r")
            C_Timer.After(4, function()
                if GetTime() >= deleteArmedUntil then self:SetText("Eliminar") end
            end)
        end
    end)

    -- Modos de la vista: composición (fase 1) o fechas y asistencia (fase 2)
    local btnModeDates = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnModeDates:SetSize(100, 22)
    btnModeDates:SetPoint("TOPRIGHT", view, "TOPRIGHT", -10, -11)
    btnModeDates:SetText("Fechas")

    local btnModeComp = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnModeComp:SetSize(110, 22)
    btnModeComp:SetPoint("RIGHT", btnModeDates, "LEFT", -6, 0)
    btnModeComp:SetText("Composición")

    local function SetViewMode(mode)
        GuildControlDB.rosterData.viewMode = mode
        Refresh()
    end
    btnModeComp:SetScript("OnClick", function() SetViewMode("comp") end)
    btnModeDates:SetScript("OnClick", function() SetViewMode("dates") end)

    dropRoster:SetupMenu(function(_, rootDescription)
        for _, roster in ipairs(R.GetAll()) do
            local id = roster.id
            rootDescription:CreateRadio(roster.name,
                function() return R.GetSelected().id == id end,
                function()
                    R.Select(id)
                    Refresh()
                end)
        end
    end)

    -- ---------------------------------------------------------------------
    -- Criterios: dificultad, tamaño y objetivos por rol
    -- ---------------------------------------------------------------------
    local criteria = CreateBackdropBox(view, 880, 34, "TOPLEFT", view, "TOPLEFT", 10, -40)

    local dropDifficulty = CreateFrame("DropdownButton", "GC_RosterDifficulty", criteria, "WowStyle1DropdownTemplate")
    dropDifficulty:SetPoint("LEFT", criteria, "LEFT", 8, 0)
    dropDifficulty:SetWidth(110)
    dropDifficulty:SetupMenu(function(_, rootDescription)
        for _, diff in ipairs(R.DIFFICULTIES) do
            local key = diff.key
            rootDescription:CreateRadio(diff.label,
                function() return R.GetSelected().difficulty == key end,
                function()
                    R.SetDifficulty(R.GetSelected(), key)
                    Refresh()
                end)
        end
    end)

    local sizeLabel = criteria:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sizeLabel:SetPoint("LEFT", dropDifficulty, "RIGHT", 14, 0)
    sizeLabel:SetText("Tamaño:")

    local btnSizeDown = CreateFrame("Button", nil, criteria, "UIPanelButtonTemplate")
    btnSizeDown:SetSize(22, 20)
    btnSizeDown:SetPoint("LEFT", sizeLabel, "RIGHT", 6, 0)
    btnSizeDown:SetText("-")

    local sizeText = criteria:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeText:SetPoint("LEFT", btnSizeDown, "RIGHT", 4, 0)
    sizeText:SetWidth(26)

    local btnSizeUp = CreateFrame("Button", nil, criteria, "UIPanelButtonTemplate")
    btnSizeUp:SetSize(22, 20)
    btnSizeUp:SetPoint("LEFT", sizeText, "RIGHT", 4, 0)
    btnSizeUp:SetText("+")

    btnSizeDown:SetScript("OnClick", function()
        local roster = R.GetSelected()
        R.SetSize(roster, roster.size - 1)
        Refresh()
    end)
    btnSizeUp:SetScript("OnClick", function()
        local roster = R.GetSelected()
        R.SetSize(roster, roster.size + 1)
        Refresh()
    end)

    -- Objetivos editables de tanques y sanadores; los DPS son el resto
    local function CreateTargetInput(anchor, labelText, slot)
        local label = criteria:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", anchor, "RIGHT", 18, 0)
        label:SetText(labelText)
        local input = CreateFrame("EditBox", nil, criteria, "InputBoxTemplate")
        input:SetSize(28, 20)
        input:SetPoint("LEFT", label, "RIGHT", 8, 0)
        input:SetAutoFocus(false)
        input:SetNumeric(true)
        input:SetMaxLetters(2)
        input:SetJustifyH("CENTER")
        local function Save(self)
            R.SetTarget(R.GetSelected(), slot, self:GetText())
            self:ClearFocus()
            Refresh()
        end
        input:SetScript("OnEnterPressed", Save)
        input:SetScript("OnEditFocusLost", function(self)
            local roster = R.GetSelected()
            R.SetTarget(roster, slot, self:GetText())
            Refresh()
        end)
        input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return input
    end

    local tankTarget = CreateTargetInput(btnSizeUp, "Tanques:", "tank")
    local healerTarget = CreateTargetInput(tankTarget, "Sanadores:", "healer")

    local dpsTargetText = criteria:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dpsTargetText:SetPoint("LEFT", healerTarget, "RIGHT", 18, 0)

    local criteriaStatus = criteria:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    criteriaStatus:SetPoint("RIGHT", criteria, "RIGHT", -10, 0)

    -- Rosters que otros oficiales han compartido (solo visible si hay alguno)
    local btnReceived = CreateFrame("Button", nil, criteria, "UIPanelButtonTemplate")
    btnReceived:SetSize(120, 22)
    btnReceived:SetPoint("RIGHT", criteriaStatus, "LEFT", -14, 0)
    btnReceived:Hide()
    btnReceived:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle("Rosters recibidos")
            for index, item in ipairs(R.GetReceived()) do
                local label = item.roster.name .. " |cFF808080(" .. item.from .. ", " .. item.at .. ")|r"
                local sub = root:CreateButton(label)
                local existing = R.FindBySyncId(item.roster.syncId)
                if existing then
                    sub:CreateButton("Actualizar \"" .. existing.name .. "\"", function()
                        R.ImportReceived(index, "replace")
                        Refresh()
                    end)
                end
                sub:CreateButton("Importar como roster nuevo", function()
                    R.ImportReceived(index, "new")
                    Refresh()
                end)
                sub:CreateButton("|cFFFF3333Descartar|r", function()
                    R.DiscardReceived(index)
                    Refresh()
                end)
            end
        end)
    end)
    R.SetReceivedListener(function() Refresh() end)

    -- ---------------------------------------------------------------------
    -- Candidatos (izquierda)
    -- ---------------------------------------------------------------------
    local candPanel = CreateBackdropBox(view, 230, 404, "TOPLEFT", criteria, "BOTTOMLEFT", 0, -6)

    local candTitle = candPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    candTitle:SetPoint("TOPLEFT", candPanel, "TOPLEFT", 10, -8)
    candTitle:SetText("Candidatos")

    -- Añadir mi propio personaje (busca su clave en la lista de la hermandad del addon)
    local btnAddMe = CreateFrame("Button", nil, candPanel, "UIPanelButtonTemplate")
    btnAddMe:SetSize(90, 20)
    btnAddMe:SetPoint("TOPRIGHT", candPanel, "TOPRIGHT", -8, -6)
    btnAddMe:SetText("Añadirme")
    btnAddMe:SetScript("OnClick", function()
        local myName = UnitName("player")
        local key = addonTable.Profiles and addonTable.Profiles.GetMyFullName()
        if not (key and GuildControlDB.members[key]) then
            key = nil
            local prefix = string.lower(myName .. "-")
            for fullName in pairs(GuildControlDB.members) do
                if string.sub(string.lower(fullName), 1, #prefix) == prefix then key = fullName break end
            end
        end
        if not key then
            PrintGC("|cFFFF3333Tu personaje no está en la lista de la hermandad del addon. Abre la ventana de hermandad del juego para actualizarla e inténtalo de nuevo.|r")
            if IsInGuild() then C_GuildInfo.GuildRoster() end
            return
        end
        local roster = R.GetSelected()
        if R.GetEffectiveMembers(roster)[key] then
            PrintGC("Ya estás en este roster.")
            return
        end
        R.AddMember(roster, key)
        Refresh()
    end)

    local candSearch = CreateFrame("EditBox", nil, candPanel, "InputBoxTemplate")
    candSearch:SetSize(200, 20)
    candSearch:SetPoint("TOPLEFT", candTitle, "BOTTOMLEFT", 4, -6)
    candSearch:SetAutoFocus(false)
    candSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    candSearch:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local candPlaceholder = candSearch:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    candPlaceholder:SetPoint("LEFT", candSearch, "LEFT", 2, 0)
    candPlaceholder:SetText("Nombre o clase...")

    local chkOnline = CreateFrame("CheckButton", "GC_RosterOnlyOnline", candPanel, "UICheckButtonTemplate")
    chkOnline:SetSize(22, 22)
    chkOnline:SetPoint("TOPLEFT", candSearch, "BOTTOMLEFT", -8, -2)
    _G[chkOnline:GetName() .. "Text"]:SetText("Conectados")

    local chkMaxLevel = CreateFrame("CheckButton", "GC_RosterOnlyMaxLevel", candPanel, "UICheckButtonTemplate")
    chkMaxLevel:SetSize(22, 22)
    chkMaxLevel:SetPoint("LEFT", chkOnline, "RIGHT", 82, 0)
    _G[chkMaxLevel:GetName() .. "Text"]:SetText("Nivel máx.")
    chkMaxLevel:SetChecked(true)

    local candScroll = CreateFrame("ScrollFrame", "GC_RosterCandScroll", candPanel, "UIPanelScrollFrameTemplate")
    candScroll:SetPoint("TOPLEFT", chkOnline, "BOTTOMLEFT", 4, -4)
    candScroll:SetPoint("BOTTOMRIGHT", candPanel, "BOTTOMRIGHT", -26, 24)
    local candChild = CreateFrame("Frame")
    candChild:SetSize(190, 1)
    candScroll:SetScrollChild(candChild)

    local candHint = candPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    candHint:SetPoint("BOTTOMLEFT", candPanel, "BOTTOMLEFT", 10, 8)
    candHint:SetText("Clic: añadir · Clic derecho: rol")

    local candQuery = ""
    candSearch:SetScript("OnTextChanged", function(self)
        candQuery = string.lower(strtrim(self:GetText() or ""))
        candPlaceholder:SetShown((self:GetText() or "") == "")
        Refresh()
    end)
    chkOnline:SetScript("OnClick", function() Refresh() end)
    chkMaxLevel:SetScript("OnClick", function() Refresh() end)

    local function MaxPlayerLevel()
        if GetMaxLevelForPlayerExpansion then
            local ok, level = pcall(GetMaxLevelForPlayerExpansion)
            if ok and level then return level end
        end
        return nil
    end

    local candRows = {}
    local function AcquireCandRow(index)
        local row = candRows[index]
        if row then return row end
        row = CreateFrame("Button", nil, candChild)
        row:SetSize(190, ROSTER_ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.text:SetWidth(150)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.level = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.level:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)

        row:SetScript("OnClick", function(self, button)
            if not self.fullName then return end
            if button == "RightButton" then
                local name = self.fullName
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(name)
                    for _, slot in ipairs({ "tank", "healer", "dps" }) do
                        root:CreateButton("Rol: " .. R.SLOT_LABELS[slot], function()
                            R.SetMemberRole(name, slot)
                            Refresh()
                        end)
                    end
                    local m = GuildControlDB.members[name]
                    if m and m.declared and m.declared.main and addonTable.Profiles then
                        root:CreateButton("Usar rol declarado (" .. m.declared.main .. ")", function()
                            addonTable.Profiles.UseDeclaredRole(name)
                            Refresh()
                        end)
                    end
                    root:CreateButton("Añadir como suplente", function()
                        R.AddMember(R.GetSelected(), name, "bench")
                        Refresh()
                    end)
                    root:CreateButton("Susurrar", function() WhisperTo(name) end)
                end)
            else
                R.AddMember(R.GetSelected(), self.fullName)
                Refresh()
            end
        end)
        row:SetScript("OnEnter", function(self) if self.fullName then ShowMemberTooltip(self, self.fullName) end end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        candRows[index] = row
        return row
    end

    local function RefreshCandidates(roster)
        for _, row in ipairs(candRows) do row:Hide() end
        local maxLevel = chkMaxLevel:GetChecked() and MaxPlayerLevel() or nil
        local groups = { tank = {}, healer = {}, dps = {}, none = {} }
        local effective = R.GetEffectiveMembers(roster)
        for fullName, m in pairs(GuildControlDB.members) do
            local pass = not effective[fullName]
                and ((not chkOnline:GetChecked()) or m.isOnline)
                and ((not maxLevel) or (tonumber(m.level) or 0) >= maxLevel)
            if pass and candQuery ~= "" then
                local className = string.lower(R.GetClassName(m.class))
                pass = string.find(string.lower(fullName), candQuery, 1, true) or string.find(className, candQuery, 1, true)
            end
            -- Agrupados por su rol definido; quien no lo tiene va a "Sin rol"
            if pass then table.insert(groups[R.GetDefinedSlot(fullName) or "none"], fullName) end
        end

        local index, y = 0, 0
        local GROUP_LABELS = { tank = "Tanques", healer = "Sanadores", dps = "DPS", none = "Sin rol definido" }
        for _, slot in ipairs({ "tank", "healer", "dps", "none" }) do
            local list = groups[slot]
            table.sort(list, function(a, b)
                local ma, mb = GuildControlDB.members[a], GuildControlDB.members[b]
                if (ma.isOnline and true or false) ~= (mb.isOnline and true or false) then return ma.isOnline and true or false end
                return a < b
            end)
            -- Cabecera del grupo
            index = index + 1
            local header = AcquireCandRow(index)
            header.fullName = nil
            header:SetPoint("TOPLEFT", candChild, "TOPLEFT", 0, -y)
            header.text:SetText(RoleIcon(slot, 14) .. " |cFFFFD100" .. GROUP_LABELS[slot] .. " (" .. #list .. ")|r")
            header.level:SetText("")
            header:Show()
            y = y + ROSTER_ROW_HEIGHT
            for _, fullName in ipairs(list) do
                index = index + 1
                local row = AcquireCandRow(index)
                row.fullName = fullName
                row:SetPoint("TOPLEFT", candChild, "TOPLEFT", 0, -y)
                row.text:SetText("  " .. RoleIcon(slot, 12) .. " " .. ColoredMemberName(fullName))
                row.level:SetText(tostring(GuildControlDB.members[fullName].level or ""))
                row:Show()
                y = y + ROSTER_ROW_HEIGHT
            end
            y = y + 4
        end
        candChild:SetHeight(math.max(1, y))
    end

    -- ---------------------------------------------------------------------
    -- Composición (centro): columnas por rol y banca
    -- ---------------------------------------------------------------------
    local compPanel = CreateBackdropBox(view, 644, 374, "TOPLEFT", candPanel, "TOPRIGHT", 6, 0)

    -- Selector de jefe: "Base" o una variante con sus propios cambios
    local dropVariant = CreateFrame("DropdownButton", "GC_RosterVariant", compPanel, "WowStyle1DropdownTemplate")
    dropVariant:SetPoint("TOPLEFT", compPanel, "TOPLEFT", 10, -6)
    dropVariant:SetWidth(160)
    dropVariant:SetupMenu(function(_, root)
        local roster = R.GetSelected()
        root:CreateRadio("Base (todos los jefes)",
            function() return R.GetSelectedVariant(roster) == nil end,
            function() R.SelectVariant(roster, nil); Refresh() end)
        for _, variant in ipairs(R.GetVariants(roster)) do
            local id = variant.id
            root:CreateRadio(variant.name,
                function() return roster.selectedVariant == id end,
                function() R.SelectVariant(roster, id); Refresh() end)
        end
    end)

    local variantInput = CreateFrame("EditBox", nil, compPanel, "InputBoxTemplate")
    variantInput:SetSize(140, 20)
    variantInput:SetPoint("LEFT", dropVariant, "RIGHT", 14, 0)
    variantInput:SetAutoFocus(false)
    variantInput:SetMaxLetters(30)
    variantInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local variantPlaceholder = variantInput:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    variantPlaceholder:SetPoint("LEFT", variantInput, "LEFT", 2, 0)
    variantPlaceholder:SetText("Jefe (vacío: lista de la banda)")
    variantInput:SetScript("OnTextChanged", function(self) variantPlaceholder:SetShown((self:GetText() or "") == "") end)

    local function AddVariant(name)
        R.AddVariant(R.GetSelected(), name or variantInput:GetText())
        variantInput:SetText("")
        variantInput:ClearFocus()
        Refresh()
    end
    variantInput:SetScript("OnEnterPressed", function() AddVariant() end)

    local btnAddVariant = CreateFrame("Button", nil, compPanel, "UIPanelButtonTemplate")
    btnAddVariant:SetSize(100, 22)
    btnAddVariant:SetPoint("LEFT", variantInput, "RIGHT", 8, 0)
    btnAddVariant:SetText("Añadir jefe")
    -- Con nombre escrito se añade ese; si no, y el roster tiene banda, se elige entre sus jefes
    btnAddVariant:SetScript("OnClick", function(self)
        local typed = strtrim(variantInput:GetText() or "")
        local roster = R.GetSelected()
        if typed ~= "" or not roster.raidId then
            AddVariant()
            return
        end
        local bosses = R.GetRaidBosses(roster.raidId)
        if #bosses == 0 then
            AddVariant()
            return
        end
        local existing = {}
        for _, variant in ipairs(R.GetVariants(roster)) do existing[variant.name] = true end
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle(roster.raidName or "Jefes")
            for _, boss in ipairs(bosses) do
                if existing[boss] then
                    root:CreateButton("|cFF808080" .. boss .. " (ya añadido)|r", function() end)
                else
                    root:CreateButton(boss, function() AddVariant(boss) end)
                end
            end
            root:CreateButton("Todos los que faltan", function()
                for _, boss in ipairs(bosses) do
                    if not existing[boss] then R.AddVariant(roster, boss) end
                end
                R.SelectVariant(roster, nil)
                Refresh()
            end)
        end)
    end)

    local deleteVariantArmedUntil = 0
    local btnDeleteVariant = CreateFrame("Button", nil, compPanel, "UIPanelButtonTemplate")
    btnDeleteVariant:SetSize(110, 22)
    btnDeleteVariant:SetPoint("LEFT", btnAddVariant, "RIGHT", 6, 0)
    btnDeleteVariant:SetText("Eliminar jefe")
    btnDeleteVariant:SetScript("OnClick", function(self)
        local roster = R.GetSelected()
        local variant = R.GetSelectedVariant(roster)
        if not variant then return end
        if GetTime() < deleteVariantArmedUntil then
            deleteVariantArmedUntil = 0
            self:SetText("Eliminar jefe")
            R.DeleteVariant(roster, variant)
            Refresh()
        else
            deleteVariantArmedUntil = GetTime() + 4
            self:SetText("|cFFFF3333¿Seguro?|r")
            C_Timer.After(4, function()
                if GetTime() >= deleteVariantArmedUntil then self:SetText("Eliminar jefe") end
            end)
        end
    end)

    local variantDiffText = compPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    variantDiffText:SetPoint("LEFT", btnDeleteVariant, "RIGHT", 10, 0)
    variantDiffText:SetPoint("RIGHT", compPanel, "RIGHT", -10, 0)
    variantDiffText:SetJustifyH("LEFT")
    variantDiffText:SetWordWrap(false)

    -- Cada bloque muestra sus integrantes en una cuadrícula de "cols" columnas
    local blocks = {}
    local function CreateBlock(slot, x, y, width, height, cols)
        local block = CreateFrame("Frame", nil, compPanel)
        block:SetPoint("TOPLEFT", compPanel, "TOPLEFT", x, y)
        block:SetSize(width, height)
        block.slot, block.cols, block.rows = slot, cols, {}
        block.title = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        block.title:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
        block.more = block:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        block.more:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", 0, 0)
        blocks[slot] = block
        return block
    end

    CreateBlock("tank", 12, -38, 140, 210, 1)
    CreateBlock("healer", 160, -38, 150, 210, 1)
    CreateBlock("dps", 318, -38, 316, 210, 2)
    CreateBlock("bench", 12, -262, 622, 104, 4)

    local divider = compPanel:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.12)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", compPanel, "TOPLEFT", 10, -255)
    divider:SetPoint("TOPRIGHT", compPanel, "TOPRIGHT", -10, -255)

    local function AcquireSlotRow(block, index)
        local row = block.rows[index]
        if row then return row end
        row = CreateFrame("Button", nil, block)
        row:SetHeight(ROSTER_ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)

        row:SetScript("OnClick", function(self)
            local name = self.fullName
            if not name then return end
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(name)
                for _, slot in ipairs(R.SLOTS) do
                    if slot ~= block.slot then
                        root:CreateButton("Mover a " .. R.SLOT_LABELS[slot], function()
                            R.AddMember(R.GetSelected(), name, slot)
                            -- El rol general solo cambia al editar la base, no un jefe concreto
                            if slot ~= "bench" and not R.GetSelectedVariant(R.GetSelected()) then R.SetMemberRole(name, slot) end
                            Refresh()
                        end)
                    end
                end
                local removeLabel = R.GetSelectedVariant(R.GetSelected()) and "No juega este jefe" or "Quitar del roster"
                root:CreateButton(removeLabel, function()
                    R.RemoveMember(R.GetSelected(), name)
                    Refresh()
                end)
                root:CreateButton("Susurrar", function() WhisperTo(name) end)
            end)
        end)
        row:SetScript("OnEnter", function(self) if self.fullName then ShowMemberTooltip(self, self.fullName) end end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        block.rows[index] = row
        return row
    end

    local function RefreshBlock(block, names, target)
        local count = #names
        if block.slot == "bench" then
            block.title:SetText("Suplentes (" .. count .. ")")
        else
            local color = (count == target) and "|cFF00FF00" or (count > target and "|cFFFF7F00" or "|cFFFFD100")
            block.title:SetText(RoleIcon(block.slot, 16) .. " " .. R.SLOT_LABELS[block.slot] .. " " .. color .. count .. "/" .. target .. "|r")
        end

        for _, row in ipairs(block.rows) do row:Hide() end
        local colWidth = math.floor(block:GetWidth() / block.cols)
        local maxRows = math.floor((block:GetHeight() - 34) / ROSTER_ROW_HEIGHT)
        local capacity = maxRows * block.cols
        for i, name in ipairs(names) do
            if i > capacity then break end
            local row = AcquireSlotRow(block, i)
            local col, line = (i - 1) % block.cols, math.floor((i - 1) / block.cols)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", block, "TOPLEFT", col * colWidth, -18 - line * ROSTER_ROW_HEIGHT)
            row:SetWidth(colWidth - 4)
            row.fullName = name
            local m = GuildControlDB.members[name] or {}
            row.text:SetText(ColoredMemberName(name) .. " |cFF808080" .. R.GetClassName(m.class) .. "|r")
            row:Show()
        end
        block.more:SetText(count > capacity and ("y " .. (count - capacity) .. " más") or "")
    end

    -- ---------------------------------------------------------------------
    -- Acciones (abajo)
    -- ---------------------------------------------------------------------
    local actionsBar = CreateFrame("Frame", nil, view)
    actionsBar:SetPoint("TOPLEFT", compPanel, "BOTTOMLEFT", 0, -6)
    actionsBar:SetSize(644, 24)

    local function CreateAction(text, width, anchor, onClick)
        local btn = CreateFrame("Button", nil, actionsBar, "UIPanelButtonTemplate")
        btn:SetSize(width, 22)
        if anchor then btn:SetPoint("LEFT", anchor, "RIGHT", 6, 0) else btn:SetPoint("LEFT", actionsBar, "LEFT", 0, 0) end
        btn:SetText(text)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    local btnInvite = CreateAction("Invitar al grupo", 120, nil, function()
        local count = R.InviteRoster(R.GetSelected())
        if count == 0 then
            PrintGC("No hay titulares conectados a los que invitar.")
        else
            PrintGC("Invitando a |cFFFFD100" .. count .. "|r titulares. Con más de 4 el grupo se convierte en banda cuando acepte el primero.")
        end
    end)
    -- Abre el anuncio de la composición para revisarlo y editarlo antes de enviarlo
    local btnAnnounce = CreateAction("Anunciar", 80, btnInvite, function()
        if uiModule.ShowRosterAnnounce then uiModule.ShowRosterAnnounce() end
    end)
    local btnExport = CreateAction("Exportar CSV", 100, btnAnnounce, function()
        if addonTable.CSV and addonTable.CSV.ShowText then
            addonTable.CSV.ShowText(R.BuildCSV(R.GetSelected()))
        end
    end)
    -- Envía el roster completo (base, jefes, fechas y asistencia) a los demás usuarios de GuildControl
    local btnShare = CreateAction("Compartir", 90, btnExport, function()
        local roster = R.GetSelected()
        local parts = R.ShareRoster(roster)
        if parts == 0 then
            PrintGC("|cFFFF3333No se pudo compartir el roster.|r")
        else
            PrintGC("Compartiendo |cFFFFD100" .. roster.name .. "|r con la hermandad (" .. parts .. " mensajes). Los demás usuarios de GuildControl lo verán en Recibidos.")
        end
    end)
    btnShare:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Compartir roster", 1, 1, 1)
        GameTooltip:AddLine("Lo envía a quien use GuildControl en la hermandad. Cada uno decide si lo importa.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnShare:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Mensaje editable para los integrantes (hermandad o susurro a cada uno)
    local btnMessage = CreateAction("Mensaje", 90, btnShare, function()
        if uiModule.ShowRosterMessage then uiModule.ShowRosterMessage() end
    end)

    -- En la base vacía el roster; en un jefe lo restablece a la base. Pide un segundo clic.
    local clearArmedUntil = 0
    local btnClear
    local function ClearLabel()
        return R.GetSelectedVariant(R.GetSelected()) and "Restablecer jefe" or "Vaciar roster"
    end
    btnClear = CreateAction("Vaciar roster", 120, btnMessage, function(self)
        if GetTime() < clearArmedUntil then
            clearArmedUntil = 0
            R.Clear(R.GetSelected())
            Refresh()
        else
            clearArmedUntil = GetTime() + 4
            self:SetText("|cFFFF3333¿Seguro?|r")
            C_Timer.After(4, function()
                if GetTime() >= clearArmedUntil then self:SetText(ClearLabel()) end
            end)
        end
    end)

    -- ---------------------------------------------------------------------
    -- Resumen en el panel de vista previa: jefe, cobertura, armaduras y asistencia
    -- ---------------------------------------------------------------------
    local function ShortList(names)
        local shorts = {}
        for _, name in ipairs(names) do table.insert(shorts, string.match(name, "^([^-]+)") or name) end
        return table.concat(shorts, ", ")
    end

    local function BuildSummaryText(roster)
        local lines = { "|cFFFFD100" .. R.GetDisplayName(roster) .. "|r", R.DifficultyLabel(roster) .. " · " .. roster.size .. " jugadores", "" }
        local diff = R.GetVariantDiff(roster)
        if diff then
            table.insert(lines, "|cFFFFD100Cambios respecto a la base|r")
            if #diff.entering + #diff.leaving + #diff.roleChanges == 0 then
                table.insert(lines, "|cFF808080Igual que la base|r")
            end
            if #diff.entering > 0 then table.insert(lines, "|cFF00FF00Entran:|r " .. ShortList(diff.entering)) end
            if #diff.leaving > 0 then table.insert(lines, "|cFFFF3333Salen:|r " .. ShortList(diff.leaving)) end
            if #diff.roleChanges > 0 then table.insert(lines, "|cFFFFD100Cambian de rol:|r " .. ShortList(diff.roleChanges)) end
            table.insert(lines, "")
        end
        table.insert(lines, "|cFFFFD100Cobertura|r")
        for _, item in ipairs(R.GetCoverage(roster)) do
            if item.count > 0 then
                table.insert(lines, "|cFF00FF00+|r " .. item.label .. " |cFF808080(" .. item.count .. ")|r")
            else
                table.insert(lines, "|cFFFF3333-|r |cFFBFBFBF" .. item.label .. "|r")
            end
        end
        table.insert(lines, "")
        table.insert(lines, "|cFFFFD100Armaduras (titulares)|r")
        local armor = R.GetArmorCounts(roster)
        local armorParts = {}
        for _, a in ipairs(R.ARMOR_TYPES) do table.insert(armorParts, a.label .. " " .. armor[a.key]) end
        table.insert(lines, table.concat(armorParts, " · "))
        table.insert(lines, "")
        table.insert(lines, "|cFFFFD100Asistencia|r")
        local eventCount = #R.GetEventsSorted(roster)
        local average = R.GetRosterAttendanceAverage(roster)
        table.insert(lines, "Fechas registradas: " .. eventCount)
        table.insert(lines, "Media del roster: " .. (average and (average .. "%") or "|cFF808080sin datos|r"))
        return table.concat(lines, "\n")
    end

    local datesPanel = BuildRosterDatesPanel(view, function()
        if activeTab == "Roster" then SetPreviewText(BuildSummaryText(R.GetSelected())) end
    end)

    -- ---------------------------------------------------------------------
    -- Refresco general
    -- ---------------------------------------------------------------------
    Refresh = function()
        if not view:IsShown() then return end
        local roster = R.GetSelected()
        R.Prune(roster)

        dropRoster:SetText(roster.name)
        if not nameInput:HasFocus() then nameInput:SetText(roster.name) end
        dropDifficulty:SetText(R.DifficultyLabel(roster))

        -- Jefe seleccionado, diferencias con la base y rosters recibidos
        local variant = R.GetSelectedVariant(roster)
        dropVariant:SetText(variant and variant.name or "Base")
        btnDeleteVariant:SetShown(variant ~= nil)
        if GetTime() >= clearArmedUntil then btnClear:SetText(ClearLabel()) end
        local diff = R.GetVariantDiff(roster)
        if diff then
            variantDiffText:SetText("|cFF00FF00" .. #diff.entering .. " entran|r · |cFFFF3333" .. #diff.leaving
                .. " salen|r · |cFFFFD100" .. #diff.roleChanges .. " cambian de rol|r")
        else
            variantDiffText:SetText("|cFF808080Base: se aplica a todos los jefes.|r")
        end
        local receivedCount = #R.GetReceived()
        btnReceived:SetShown(receivedCount > 0)
        btnReceived:SetText("|cFF00FF00Recibidos (" .. receivedCount .. ")|r")

        local targets = R.GetTargets(roster)
        sizeText:SetText(roster.size)
        local isMythic = roster.difficulty == "mythic"
        btnSizeDown:SetEnabled(not isMythic and roster.size > R.MIN_SIZE)
        btnSizeUp:SetEnabled(not isMythic and roster.size < R.MAX_SIZE)
        if not tankTarget:HasFocus() then tankTarget:SetText(targets.tank) end
        if not healerTarget:HasFocus() then healerTarget:SetText(targets.healer) end
        dpsTargetText:SetText("DPS: " .. targets.dps)

        local bySlot = R.GetMembersBySlot(roster)
        local starters = #bySlot.tank + #bySlot.healer + #bySlot.dps
        local color = starters == roster.size and "|cFF00FF00" or (starters > roster.size and "|cFFFF7F00" or "|cFFFFD100")
        criteriaStatus:SetText("Titulares: " .. color .. starters .. "/" .. roster.size .. "|r")

        -- Modo: composición o fechas (ocupan la misma zona)
        local mode = GuildControlDB.rosterData.viewMode == "dates" and "dates" or "comp"
        local isComp = mode == "comp"
        criteria:SetShown(isComp)
        candPanel:SetShown(isComp)
        compPanel:SetShown(isComp)
        actionsBar:SetShown(isComp)
        datesPanel:SetShown(not isComp)
        btnModeComp:SetEnabled(not isComp)
        btnModeDates:SetEnabled(isComp)

        if isComp then
            RefreshBlock(blocks.tank, bySlot.tank, targets.tank)
            RefreshBlock(blocks.healer, bySlot.healer, targets.healer)
            RefreshBlock(blocks.dps, bySlot.dps, targets.dps)
            RefreshBlock(blocks.bench, bySlot.bench, 0)
            RefreshCandidates(roster)
        else
            datesPanel.SetRoster(roster)
        end

        if activeTab == "Roster" then SetPreviewText(BuildSummaryText(roster)) end
    end

    uiModule.RefreshRoster = Refresh
    view:SetScript("OnShow", Refresh)
    containers.views["Roster"] = view
end

-- =========================================================================
-- 8b. VISTA INVITAR: MODO INDIVIDUAL Y MODO MASIVO
-- =========================================================================
local MAX_CHAT_BYTES = 255
local MASS_BATCH_SIZE = 10          -- jugadores por lote
local MASS_BATCH_INTERVAL = 3       -- segundos entre invitaciones de un lote
local REINVITE_DAYS = 7             -- no volver a invitar a la misma persona en 7 días

local RECRUIT_ROLES = {
    { key = "tank",   label = "Tanques" },
    { key = "healer", label = "Sanadores" },
    { key = "dps",    label = "DPS" },
}

local RECRUIT_ACTIVITIES = {
    { key = "raid",     label = "Banda" },
    { key = "mplus",    label = "Mítica+" },
    { key = "pvp",      label = "JcJ" },
    { key = "social",   label = "Social" },
    { key = "leveling", label = "Subir de nivel" },
}

-- Iconos de banda que el chat convierte en imagen: {rt1} ... {rt8}
local RAID_ICONS = { "Estrella", "Círculo", "Diamante", "Triángulo", "Luna", "Cuadrado", "Cruz", "Calavera" }

-- { "a", "b", "c" } -> "a, b y c"
local function JoinWithY(list)
    if #list == 0 then return "" end
    if #list == 1 then return list[1] end
    return table.concat(list, ", ", 1, #list - 1) .. " y " .. list[#list]
end

local function EndSentence(text)
    text = strtrim(text or "")
    if text == "" then return "" end
    if not string.find(text, "[%.!%?]$") then text = text .. "." end
    return text
end

-- Construye el mensaje de reclutamiento a partir de settings.recruit
local function ComposeRecruitMessage(recruit)
    local guild = addonTable.GetDisplayGuildName()
    local _, faction = UnitFactionGroup("player")

    local roles = {}
    for _, r in ipairs(RECRUIT_ROLES) do
        if recruit.roles[r.key] then table.insert(roles, r.label) end
    end
    local activities = {}
    for _, a in ipairs(RECRUIT_ACTIVITIES) do
        if recruit.activities[a.key] then table.insert(activities, a.label) end
    end

    local sentence = "<" .. guild .. ">" .. (faction and (" (" .. faction .. ")") or "") .. " busca "
    sentence = sentence .. (#roles > 0 and JoinWithY(roles) or "jugadores")
    if #activities > 0 then sentence = sentence .. " para " .. JoinWithY(activities) end

    local parts = { EndSentence(sentence) }
    if strtrim(recruit.schedule) ~= "" then table.insert(parts, EndSentence("Horario: " .. recruit.schedule)) end
    if strtrim(recruit.extra) ~= "" then table.insert(parts, EndSentence(recruit.extra)) end
    return table.concat(parts, " ")
end

-- Sustituye {nombre} (sin reino) y {hermandad}; nil si el resultado no cabe en el chat
local function ExpandMessage(template, name)
    local short = string.match(name or "", "^([^-]+)") or name or ""
    local msg = string.gsub(template, "{nombre}", function() return short end)
    msg = string.gsub(msg, "{hermandad}", function() return addonTable.GetDisplayGuildName() end)
    if #msg > MAX_CHAT_BYTES then return nil end
    return msg
end

-- Muestra los {rtN} como iconos para la vista previa
local function RenderRaidIcons(text)
    return (string.gsub(text, "{rt(%d)}", "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%1:0|t"))
end

-- Caja de mensaje editable (multilínea visual, una línea al enviar) con paleta de iconos,
-- vista previa y contador. onChange(text) se llama con el texto limpio.
local function CreateMessageEditor(parent, anchor, labelText, height, onChange, width)
    width = width or 850
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
    label:SetText(labelText)

    local box = CreateBackdropBox(parent, width, height, "TOPLEFT", label, "BOTTOMLEFT", 0, -6)
    local edit = CreateFrame("EditBox", nil, box)
    edit:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
    edit:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 8)
    edit:SetMultiLine(true)
    edit:SetFontObject(ChatFontNormal)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)

    -- Paleta de iconos a la derecha de la etiqueta
    local iconsLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    iconsLabel:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", -8 - #RAID_ICONS * 22, 4)
    iconsLabel:SetText("Iconos:")
    for i, iconName in ipairs(RAID_ICONS) do
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(18, 18)
        btn:SetPoint("BOTTOMLEFT", iconsLabel, "BOTTOMRIGHT", 6 + (i - 1) * 22, -3)
        btn:SetNormalTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i)
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        btn:SetScript("OnClick", function()
            edit:SetFocus()
            edit:Insert("{rt" .. i .. "}")
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(iconName .. "  {rt" .. i .. "}", 1, 1, 1)
            GameTooltip:AddLine("Clic para insertarlo en el mensaje", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local preview = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    preview:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -5)
    preview:SetWidth(width - 90)
    preview:SetJustifyH("LEFT")
    preview:SetWordWrap(false)

    local counter = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    counter:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -5)

    local editor = { label = label, box = box, edit = edit }

    -- El chat no admite saltos de línea
    function editor.GetText()
        return strtrim((string.gsub(edit:GetText() or "", "[\r\n]+", " ")))
    end

    function editor.SetText(text)
        edit:SetText(text or "")
    end

    edit:SetScript("OnTextChanged", function()
        local text = editor.GetText()
        local bytes = #text
        local color = bytes > MAX_CHAT_BYTES and "|cFFFF3333" or "|cFFBFBFBF"
        counter:SetText(color .. bytes .. "/" .. MAX_CHAT_BYTES .. "|r")
        preview:SetText("|cFF808080Vista previa:|r " .. RenderRaidIcons(text))
        if onChange then onChange(text) end
    end)

    return editor
end

-- Etiqueta pequeña + caja de texto con texto de ayuda dentro mientras está vacía
local function CreateLabeledInput(parent, labelText, width, placeholderText)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetText(labelText)

    local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    input:SetSize(width, 20)
    input:SetPoint("LEFT", label, "LEFT", 86, 0)
    input:SetAutoFocus(false)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    if placeholderText then
        local placeholder = input:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        placeholder:SetPoint("LEFT", input, "LEFT", 2, 0)
        placeholder:SetText(placeholderText)
        input.placeholder = placeholder
    end
    return label, input
end

local function SetPlaceholderVisibility(input)
    if input.placeholder then input.placeholder:SetShown((input:GetText() or "") == "") end
end

-- -------------------------------------------------------------------------
-- Modo individual: generador del mensaje y envío a un jugador
-- -------------------------------------------------------------------------
local function BuildSingleInvitePanel(panel)
    local recruit = function() return GuildControlDB.settings.recruit end

    local step1 = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    step1:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -54)
    step1:SetText("1. ¿Qué buscáis?")

    local function CreateCheckRow(labelText, yOffset, items, tableKey)
        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", step1, "BOTTOMLEFT", 0, yOffset)
        label:SetText(labelText)

        local checks = {}
        for i, item in ipairs(items) do
            local chk = CreateFrame("CheckButton", "GC_Recruit_" .. tableKey .. "_" .. item.key, panel, "UICheckButtonTemplate")
            chk:SetSize(24, 24)
            chk:SetPoint("LEFT", label, "LEFT", 80 + (i - 1) * 135, 0)
            _G[chk:GetName() .. "Text"]:SetText(item.label)
            chk:SetScript("OnClick", function(self)
                recruit()[tableKey][item.key] = self:GetChecked() and true or false
            end)
            checks[item.key] = chk
        end
        return checks
    end

    local roleChecks = CreateCheckRow("Roles:", -14, RECRUIT_ROLES, "roles")
    local activityChecks = CreateCheckRow("Actividades:", -44, RECRUIT_ACTIVITIES, "activities")

    local scheduleLabel, scheduleInput = CreateLabeledInput(panel, "Horario:", 320, "Ej.: miércoles y jueves de 21:00 a 00:00")
    scheduleLabel:SetPoint("TOPLEFT", step1, "BOTTOMLEFT", 0, -78)
    scheduleInput:SetMaxLetters(80)

    local extraLabel, extraInput = CreateLabeledInput(panel, "Texto final:", 520)
    extraLabel:SetPoint("TOPLEFT", step1, "BOTTOMLEFT", 0, -108)
    extraInput:SetMaxLetters(120)

    scheduleInput:SetScript("OnTextChanged", function(self)
        recruit().schedule = self:GetText() or ""
        SetPlaceholderVisibility(self)
    end)
    extraInput:SetScript("OnTextChanged", function(self) recruit().extra = self:GetText() or "" end)

    local btnGenerate = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnGenerate:SetSize(150, 22)
    btnGenerate:SetPoint("TOPLEFT", step1, "BOTTOMLEFT", 0, -136)
    btnGenerate:SetText("Generar mensaje")

    local editor = CreateMessageEditor(panel, btnGenerate, "2. Mensaje (puedes retocarlo a mano)", 62,
        function(text) recruit().message = text end)

    btnGenerate:SetScript("OnClick", function()
        editor.SetText(ComposeRecruitMessage(recruit()))
        editor.edit:ClearFocus()
    end)

    local step3 = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    step3:SetPoint("TOPLEFT", editor.box, "BOTTOMLEFT", 0, -26)
    step3:SetText("3. Enviar a un jugador")

    local nameInput = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    nameInput:SetSize(200, 20)
    nameInput:SetPoint("TOPLEFT", step3, "BOTTOMLEFT", 6, -8)
    nameInput:SetAutoFocus(false)
    nameInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local namePlaceholder = nameInput:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    namePlaceholder:SetPoint("LEFT", nameInput, "LEFT", 2, 0)
    namePlaceholder:SetText("Nombre o Nombre-Reino")
    nameInput:SetScript("OnTextChanged", function(self) namePlaceholder:SetShown((self:GetText() or "") == "") end)

    local btnTarget = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnTarget:SetSize(120, 22)
    btnTarget:SetPoint("LEFT", nameInput, "RIGHT", 10, 0)
    btnTarget:SetText("Usar objetivo")
    btnTarget:SetScript("OnClick", function()
        if UnitIsPlayer("target") then
            local name, realm = UnitName("target")
            nameInput:SetText(realm and realm ~= "" and (name .. "-" .. realm) or name)
        else
            PrintGC("No tienes a ningún jugador como objetivo.")
        end
    end)

    local function TargetName()
        local name = strtrim(nameInput:GetText() or "")
        if name == "" then
            PrintGC("|cFFFF3333Escribe el nombre del jugador.|r")
            return nil
        end
        return name
    end

    local function MessageFor(name)
        local template = editor.GetText()
        if template == "" then
            PrintGC("|cFFFF3333El mensaje está vacío: pulsa \"Generar mensaje\" o escríbelo.|r")
            return nil
        end
        local msg = ExpandMessage(template, name)
        if not msg then
            PrintGC("|cFFFF3333El mensaje supera los " .. MAX_CHAT_BYTES .. " caracteres del chat.|r")
        end
        return msg
    end

    local actions = {
        { "Susurrar mensaje", function(name)
            local msg = MessageFor(name)
            if msg then SendWhisper(name, msg) end
        end },
        { "Invitar a la hermandad", function(name) InviteToGuild(name) end },
        { "Susurrar e invitar", function(name)
            local msg = MessageFor(name)
            if msg then
                SendWhisper(name, msg)
                InviteToGuild(name)
            end
        end },
    }

    local previous = nil
    for _, action in ipairs(actions) do
        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetSize(170, 22)
        if previous then
            btn:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        else
            btn:SetPoint("TOPLEFT", nameInput, "BOTTOMLEFT", -6, -12)
        end
        btn:SetText(action[1])
        btn:SetScript("OnClick", function()
            local name = TargetName()
            if name then action[2](name) end
        end)
        previous = btn
    end

    -- Para canales (Comercio, Reclutamiento...): se abre en el chat y el jugador elige dónde enviarlo
    local btnOpenChat = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnOpenChat:SetSize(170, 22)
    btnOpenChat:SetPoint("LEFT", previous, "RIGHT", 8, 0)
    btnOpenChat:SetText("Abrir en el chat")
    btnOpenChat:SetScript("OnClick", function()
        local msg = ExpandMessage(editor.GetText(), "")
        if msg and msg ~= "" then OpenChatWith(msg) end
    end)

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", nameInput, "BOTTOMLEFT", -6, -44)
    hint:SetWidth(850)
    hint:SetJustifyH("LEFT")
    hint:SetText("{nombre} = nombre del jugador, {hermandad} = nombre de la hermandad. \"Abrir en el chat\" coloca el mensaje en tu caja de chat para publicarlo en el canal que elijas (por ejemplo /2 para Comercio).")

    panel:SetScript("OnShow", function()
        local r = recruit()
        for key, chk in pairs(roleChecks) do chk:SetChecked(r.roles[key]) end
        for key, chk in pairs(activityChecks) do chk:SetChecked(r.activities[key]) end
        scheduleInput:SetText(r.schedule or "")
        extraInput:SetText(r.extra or "")
        if (r.message or "") == "" then r.message = ComposeRecruitMessage(r) end
        editor.SetText(r.message)
    end)
end

-- -------------------------------------------------------------------------
-- Modo masivo: cola de jugadores, búsqueda /who y envío por lotes
-- -------------------------------------------------------------------------
local function NormalizePlayerName(name)
    name = strtrim(name or "")
    if name == "" then return nil end
    if not string.find(name, "-", 1, true) then
        local realm = GetNormalizedRealmName and GetNormalizedRealmName() or string.gsub(GetRealmName() or "", "%s+", "")
        name = name .. "-" .. realm
    end
    return (string.gsub(name, "%s+", ""))
end

local MASS_STATUS_TEXT = {
    pending = "|cFFBFBFBFPendiente|r",
    invited = "|cFF00FF00Invitado|r",
    member  = "|cFF808080Ya es miembro|r",
    recent  = "|cFF808080Invitado hace poco|r",
    failed  = "|cFFFF3333Mensaje demasiado largo|r",
    blacklist = "|cFFFF3333Lista negra|r",
}

local function BuildMassInvitePanel(panel)
    local recruit = function() return GuildControlDB.settings.recruit end
    local queue = {}            -- { {name, status}, ... }
    local batchTicker = nil

    -- 1. Lista de jugadores --------------------------------------------------
    local step1 = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    step1:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -54)
    step1:SetText("1. Jugadores a invitar")

    -- 1a. Pegar nombres
    local pasteLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pasteLabel:SetPoint("TOPLEFT", step1, "BOTTOMLEFT", 0, -10)
    pasteLabel:SetText("Pega nombres (uno por línea o separados por comas):")

    local pasteBox = CreateBackdropBox(panel, 270, 112, "TOPLEFT", pasteLabel, "BOTTOMLEFT", 0, -4)
    local pasteScroll = CreateFrame("ScrollFrame", nil, pasteBox, "UIPanelScrollFrameTemplate")
    pasteScroll:SetPoint("TOPLEFT", pasteBox, "TOPLEFT", 6, -6)
    pasteScroll:SetPoint("BOTTOMRIGHT", pasteBox, "BOTTOMRIGHT", -26, 6)
    local pasteEdit = CreateFrame("EditBox", nil, pasteScroll)
    pasteEdit:SetMultiLine(true)
    pasteEdit:SetFontObject(ChatFontNormal)
    pasteEdit:SetWidth(232)
    pasteEdit:SetHeight(100)
    pasteEdit:SetAutoFocus(false)
    pasteEdit:SetMaxLetters(0)
    pasteEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    pasteScroll:SetScrollChild(pasteEdit)
    pasteBox:EnableMouse(true)
    pasteBox:SetScript("OnMouseDown", function() pasteEdit:SetFocus() end)

    local btnAddPasted = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnAddPasted:SetSize(130, 22)
    btnAddPasted:SetPoint("TOPLEFT", pasteBox, "BOTTOMLEFT", 0, -4)
    btnAddPasted:SetText("Añadir a la cola")

    -- 1b. Búsqueda /who de jugadores sin hermandad
    local whoTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    whoTitle:SetPoint("TOPLEFT", step1, "BOTTOMLEFT", 300, -10)
    whoTitle:SetText("O busca jugadores sin hermandad (/who):")

    local minLabel, minInput = CreateLabeledInput(panel, "Nivel mínimo:", 40)
    minLabel:SetPoint("TOPLEFT", whoTitle, "BOTTOMLEFT", 0, -14)
    minInput:SetNumeric(true)
    minInput:SetMaxLetters(3)

    local maxLabel, maxInput = CreateLabeledInput(panel, "Nivel máximo:", 40)
    maxLabel:SetPoint("TOPLEFT", minLabel, "BOTTOMLEFT", 0, -16)
    maxInput:SetNumeric(true)
    maxInput:SetMaxLetters(3)

    local extraWhoLabel, extraWhoInput = CreateLabeledInput(panel, "Filtro extra:", 120, "Clase, zona...")
    extraWhoLabel:SetPoint("TOPLEFT", maxLabel, "BOTTOMLEFT", 0, -16)
    extraWhoInput:SetScript("OnTextChanged", SetPlaceholderVisibility)

    local btnWho = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnWho:SetSize(130, 22)
    btnWho:SetPoint("TOPLEFT", extraWhoLabel, "BOTTOMLEFT", 0, -12)
    btnWho:SetText("Buscar y añadir")

    -- 1c. Cola
    local queueTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    queueTitle:SetPoint("TOPLEFT", step1, "BOTTOMLEFT", 540, -10)

    local queueBox = CreateBackdropBox(panel, 320, 112, "TOPLEFT", queueTitle, "BOTTOMLEFT", 0, -4)
    local queueScroll = CreateFrame("ScrollFrame", nil, queueBox, "UIPanelScrollFrameTemplate")
    queueScroll:SetPoint("TOPLEFT", queueBox, "TOPLEFT", 6, -6)
    queueScroll:SetPoint("BOTTOMRIGHT", queueBox, "BOTTOMRIGHT", -26, 6)
    local queueChild = CreateFrame("Frame")
    queueChild:SetSize(286, 1)
    queueScroll:SetScrollChild(queueChild)

    local btnClear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnClear:SetSize(100, 22)
    btnClear:SetPoint("TOPLEFT", queueBox, "BOTTOMLEFT", 0, -4)
    btnClear:SetText("Vaciar cola")

    local btnClearDone = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnClearDone:SetSize(130, 22)
    btnClearDone:SetPoint("LEFT", btnClear, "RIGHT", 6, 0)
    btnClearDone:SetText("Quitar procesados")

    local queueRows = {}

    local function CountByStatus()
        local pending, invited = 0, 0
        for _, item in ipairs(queue) do
            if item.status == "pending" then pending = pending + 1 end
            if item.status == "invited" then invited = invited + 1 end
        end
        return pending, invited
    end

    local statusText   -- se crea más abajo

    local function RefreshQueue()
        for _, row in ipairs(queueRows) do row:Hide() end
        for i, item in ipairs(queue) do
            local row = queueRows[i]
            if not row then
                row = CreateFrame("Frame", nil, queueChild)
                row:SetSize(286, 16)
                row.nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.nameFs:SetPoint("LEFT", row, "LEFT", 2, 0)
                row.nameFs:SetWidth(160)
                row.nameFs:SetJustifyH("LEFT")
                row.nameFs:SetWordWrap(false)
                row.statusFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.statusFs:SetPoint("LEFT", row, "LEFT", 166, 0)
                row.statusFs:SetWidth(118)
                row.statusFs:SetJustifyH("LEFT")
                queueRows[i] = row
            end
            row:SetPoint("TOPLEFT", queueChild, "TOPLEFT", 0, -(i - 1) * 16)
            row.nameFs:SetText(item.name)
            row.statusFs:SetText(MASS_STATUS_TEXT[item.status] or item.status)
            row:Show()
        end
        queueChild:SetHeight(math.max(1, #queue * 16))

        local pending, invited = CountByStatus()
        queueTitle:SetText("Cola: " .. #queue .. " jugadores")
        if statusText then
            statusText:SetText("Pendientes: |cFFFFD100" .. pending .. "|r   Invitados: |cFF00FF00" .. invited .. "|r")
        end
    end

    local function AddToQueue(rawName)
        local name = NormalizePlayerName(rawName)
        if not name then return false end
        for _, item in ipairs(queue) do
            if item.name == name then return false end
        end
        table.insert(queue, { name = name, status = "pending" })
        return true
    end

    btnAddPasted:SetScript("OnClick", function()
        local added = 0
        for token in string.gmatch(pasteEdit:GetText() or "", "[^,;\r\n]+") do
            token = strtrim(token)
            if token ~= "" and not string.find(token, "%s") and AddToQueue(token) then added = added + 1 end
        end
        pasteEdit:SetText("")
        pasteEdit:ClearFocus()
        PrintGC("Añadidos a la cola: |cFFFFD100" .. added .. "|r.")
        RefreshQueue()
    end)

    btnClear:SetScript("OnClick", function()
        wipe(queue)
        RefreshQueue()
    end)

    btnClearDone:SetScript("OnClick", function()
        for i = #queue, 1, -1 do
            if queue[i].status ~= "pending" then table.remove(queue, i) end
        end
        RefreshQueue()
    end)

    -- /who: SendWho exige un clic del jugador; el resultado llega con WHO_LIST_UPDATE
    local whoFrame = CreateFrame("Frame")
    local awaitingWho = false
    whoFrame:SetScript("OnEvent", function()
        if not awaitingWho then return end
        awaitingWho = false
        whoFrame:UnregisterEvent("WHO_LIST_UPDATE")

        local added, total = 0, 0
        local num = C_FriendList.GetNumWhoResults and C_FriendList.GetNumWhoResults() or 0
        for i = 1, num do
            local info = C_FriendList.GetWhoInfo(i)
            if info and info.fullName then
                total = total + 1
                if (info.fullGuildName or "") == "" and AddToQueue(info.fullName) then added = added + 1 end
            end
        end
        PrintGC("/who: " .. total .. " resultados, |cFFFFD100" .. added .. "|r sin hermandad añadidos a la cola.")
        RefreshQueue()
    end)

    btnWho:SetScript("OnClick", function()
        if not (C_FriendList and C_FriendList.SendWho) then return end
        local minLevel, maxLevel = tonumber(minInput:GetText()), tonumber(maxInput:GetText())
        local parts = {}
        if minLevel or maxLevel then
            table.insert(parts, (minLevel or 1) .. "-" .. (maxLevel or minLevel or 90))
        end
        local extra = strtrim(extraWhoInput:GetText() or "")
        if extra ~= "" then table.insert(parts, extra) end

        awaitingWho = true
        whoFrame:RegisterEvent("WHO_LIST_UPDATE")
        if C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, true) end
        local ok = pcall(C_FriendList.SendWho, table.concat(parts, " "))
        if not ok then
            awaitingWho = false
            whoFrame:UnregisterEvent("WHO_LIST_UPDATE")
            PrintGC("|cFFFF3333No se pudo lanzar la búsqueda /who.|r")
        end
    end)

    -- 2. Susurro editable ----------------------------------------------------
    local editor = CreateMessageEditor(panel, btnAddPasted, "2. Susurro que recibe cada jugador al invitarlo", 50,
        function(text) recruit().massMessage = text end)
    editor.label:ClearAllPoints()
    editor.label:SetPoint("TOPLEFT", step1, "BOTTOMLEFT", 0, -186)

    -- 3. Envío ---------------------------------------------------------------
    local step3 = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    step3:SetPoint("TOPLEFT", editor.box, "BOTTOMLEFT", 0, -26)
    step3:SetText("3. Invitar")

    local chkWhisper = CreateFrame("CheckButton", "GC_MassInviteWhisper", panel, "UICheckButtonTemplate")
    chkWhisper:SetSize(24, 24)
    chkWhisper:SetPoint("LEFT", step3, "RIGHT", 20, 0)
    _G[chkWhisper:GetName() .. "Text"]:SetText("Enviar el susurro con cada invitación")
    chkWhisper:SetScript("OnClick", function(self) recruit().massWhisper = self:GetChecked() and true or false end)

    local btnNext = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnNext:SetSize(150, 22)
    btnNext:SetPoint("TOPLEFT", step3, "BOTTOMLEFT", 0, -10)
    btnNext:SetText("Invitar siguiente")

    local btnBatch = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnBatch:SetSize(190, 22)
    btnBatch:SetPoint("LEFT", btnNext, "RIGHT", 8, 0)
    btnBatch:SetText("Invitar lote (" .. MASS_BATCH_SIZE .. ")")

    local btnStop = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnStop:SetSize(100, 22)
    btnStop:SetPoint("LEFT", btnBatch, "RIGHT", 8, 0)
    btnStop:SetText("Detener")
    btnStop:Disable()

    statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusText:SetPoint("LEFT", btnStop, "RIGHT", 20, 0)

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", btnNext, "BOTTOMLEFT", 0, -10)
    hint:SetWidth(850)
    hint:SetJustifyH("LEFT")
    hint:SetText("Se omiten los miembros de la hermandad y a quien ya se invitó en los últimos " .. REINVITE_DAYS .. " días. El lote envía una invitación cada " .. MASS_BATCH_INTERVAL .. " s. Muchos susurros a desconocidos pueden acabar en denuncias por spam: úsalo con moderación.")

    -- Procesa el siguiente pendiente. Devuelve false si ya no quedan.
    local function ProcessNext()
        local history = GuildControlDB.inviteHistory
        local now = time()
        for _, item in ipairs(queue) do
            if item.status == "pending" then
                if addonTable.Blacklist and addonTable.Blacklist.IsBlacklisted(item.name) then
                    item.status = "blacklist"
                elseif GuildControlDB.members[item.name] then
                    item.status = "member"
                elseif history[item.name] and now - history[item.name] < REINVITE_DAYS * 86400 then
                    item.status = "recent"
                else
                    local msg = nil
                    if recruit().massWhisper then
                        msg = ExpandMessage(editor.GetText(), item.name)
                        if not msg then
                            item.status = "failed"
                            RefreshQueue()
                            return true
                        end
                    end
                    -- Primero la invitación (falla si el rango no tiene permiso) y luego el susurro
                    if not InviteToGuild(item.name, true) then
                        RefreshQueue()
                        return false
                    end
                    if msg and msg ~= "" then SendWhisper(item.name, msg) end
                    history[item.name] = now
                    item.status = "invited"
                    RefreshQueue()
                    return true
                end
            end
        end
        RefreshQueue()
        return false
    end

    local function StopBatch()
        if batchTicker then
            batchTicker:Cancel()
            batchTicker = nil
        end
        btnStop:Disable()
        btnBatch:Enable()
    end

    btnNext:SetScript("OnClick", function()
        if not ProcessNext() then PrintGC("No quedan jugadores pendientes en la cola.") end
    end)

    btnBatch:SetScript("OnClick", function()
        if batchTicker then return end
        local remaining = MASS_BATCH_SIZE
        if not ProcessNext() then
            PrintGC("No quedan jugadores pendientes en la cola.")
            return
        end
        remaining = remaining - 1
        btnBatch:Disable()
        btnStop:Enable()
        batchTicker = C_Timer.NewTicker(MASS_BATCH_INTERVAL, function()
            if remaining <= 0 or not ProcessNext() then
                StopBatch()
                return
            end
            remaining = remaining - 1
            if remaining <= 0 then StopBatch() end
        end)
    end)

    btnStop:SetScript("OnClick", StopBatch)
    panel:SetScript("OnHide", StopBatch)

    panel:SetScript("OnShow", function()
        local r = recruit()
        editor.SetText(r.massMessage or "")
        chkWhisper:SetChecked(r.massWhisper)
        RefreshQueue()
    end)
end

local function BuildInviteView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", view, "TOPLEFT", 20, -20)
    title:SetText("Invitar nuevos miembros")

    -- Dos modos en el mismo marco: se cambia con los botones de arriba a la derecha
    local singlePanel = CreateFrame("Frame", nil, view)
    singlePanel:SetAllPoints()
    BuildSingleInvitePanel(singlePanel)

    local massPanel = CreateFrame("Frame", nil, view)
    massPanel:SetAllPoints()
    massPanel:Hide()
    BuildMassInvitePanel(massPanel)

    local btnMass = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnMass:SetSize(160, 22)
    btnMass:SetPoint("TOPRIGHT", view, "TOPRIGHT", -15, -16)
    btnMass:SetText("Invitación masiva")

    local btnSingle = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnSingle:SetSize(160, 22)
    btnSingle:SetPoint("RIGHT", btnMass, "LEFT", -6, 0)
    btnSingle:SetText("Invitación individual")

    local function ShowMode(mode)
        GuildControlDB.settings.recruit.mode = mode
        singlePanel:SetShown(mode == "single")
        massPanel:SetShown(mode == "mass")
        -- El botón del modo activo queda deshabilitado, como las categorías de Logros
        btnSingle:SetEnabled(mode ~= "single")
        btnMass:SetEnabled(mode ~= "mass")
    end

    btnSingle:SetScript("OnClick", function() ShowMode("single") end)
    btnMass:SetScript("OnClick", function() ShowMode("mass") end)
    view:SetScript("OnShow", function() ShowMode(GuildControlDB.settings.recruit.mode or "single") end)

    containers.views["Invitar"] = view
end

-- =========================================================================
-- 8b2. MENSAJE PARA LOS INTEGRANTES DEL ROSTER (HERMANDAD O SUSURRO)
-- =========================================================================
local ROSTER_ROLE_WORDS = { tank = "tanque", healer = "sanador", dps = "DPS", bench = "suplente" }
local ROSTER_WHISPER_INTERVAL = 0.5

-- {roster} {jefe} {dificultad} {fecha} {hora} {nota} {hermandad} y, al susurrar, {nombre} y {rol}
local function ExpandRosterMessage(template, roster, event, fullName)
    local R = addonTable.Roster
    local variant = R.GetSelectedVariant(roster)
    local slot = fullName and R.GetEffectiveMembers(roster)[fullName]
    local fecha = ""
    if event then
        local y, mo, d = string.match(event.date or "", "^(%d+)-(%d+)-(%d+)$")
        fecha = y and (d .. "/" .. mo .. "/" .. y) or (event.date or "")
    end
    local values = {
        roster = roster.name,
        jefe = variant and variant.name or "",
        dificultad = R.DifficultyLabel(roster) .. " " .. roster.size,
        fecha = fecha,
        hora = event and event.time or "",
        nota = event and event.note or "",
        hermandad = addonTable.GetDisplayGuildName(),
        nombre = fullName and (string.match(fullName, "^([^-]+)") or fullName) or "",
        rol = slot and ROSTER_ROLE_WORDS[slot] or "",
    }
    local msg = string.gsub(template, "{(%a+)}", function(key) return values[key] end)
    -- Variables vacías no deben dejar huecos raros ("Hola , ...")
    msg = string.gsub(msg, "%s+", " ")
    msg = string.gsub(msg, " ([,%.!%?:;])", "%1")
    return strtrim(msg)
end

local GC_RosterMsgFrame = nil

local function CreateRosterMessageFrame()
    local R = addonTable.Roster
    local frame = CreateFrame("Frame", "GuildControlRosterMessageFrame", GC_UI, "BasicFrameTemplateWithInset")
    frame:SetSize(600, 340)
    frame:SetPoint("CENTER", GC_UI, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)

    local selectedEventId = nil
    local whisperTicker = nil

    local dateLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dateLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -36)
    dateLabel:SetText("Fecha de banda:")

    local dropEvent = CreateFrame("DropdownButton", "GC_RosterMsgEvent", frame, "WowStyle1DropdownTemplate")
    dropEvent:SetPoint("LEFT", dateLabel, "RIGHT", 10, 0)
    dropEvent:SetWidth(230)

    local chkBench = CreateFrame("CheckButton", "GC_RosterMsgBench", frame, "UICheckButtonTemplate")
    chkBench:SetSize(24, 24)
    chkBench:SetPoint("LEFT", dropEvent, "RIGHT", 14, 0)
    _G[chkBench:GetName() .. "Text"]:SetText("Incluir suplentes")

    local anchor = CreateFrame("Frame", nil, frame)
    anchor:SetSize(1, 1)
    anchor:SetPoint("TOPLEFT", dateLabel, "BOTTOMLEFT", 0, -8)

    local editor = CreateMessageEditor(frame, anchor, "Mensaje (editable)", 64,
        function(text) GuildControlDB.settings.rosterMessage = text end, 564)

    local varsHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    varsHint:SetPoint("TOPLEFT", editor.box, "BOTTOMLEFT", 0, -26)
    varsHint:SetWidth(564)
    varsHint:SetJustifyH("LEFT")
    varsHint:SetText("Variables: {roster} {jefe} {dificultad} {fecha} {hora} {nota} {hermandad}. Solo al susurrar: {nombre} y {rol} (tanque, sanador, DPS o suplente).")

    local recipientsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    recipientsText:SetPoint("TOPLEFT", varsHint, "BOTTOMLEFT", 0, -12)

    local function SelectedEvent(roster)
        return roster and R.GetEvent(roster, selectedEventId)
    end

    -- Integrantes conectados a los que se susurraría (sin mí)
    local function Recipients(roster)
        local list, total = {}, 0
        local me = UnitName("player")
        for name, slot in pairs(R.GetEffectiveMembers(roster)) do
            if slot ~= "bench" or chkBench:GetChecked() then
                total = total + 1
                local m = GuildControlDB.members[name]
                local short = string.match(name, "^([^-]+)") or name
                if m and m.isOnline and short ~= me then table.insert(list, name) end
            end
        end
        table.sort(list)
        return list, total
    end

    local btnGuild, btnWhisper

    local function UpdateRecipients()
        local roster = R.GetSelected()
        local list, total = Recipients(roster)
        recipientsText:SetText("Destinatarios del susurro: |cFFFFD100" .. #list .. "|r conectados de " .. total .. " en el roster."
            .. (whisperTicker and "  |cFF00FF00Enviando...|r" or ""))
    end

    local function Refresh()
        local roster = R.GetSelected()
        frame.title:SetText("Mensaje para " .. R.GetDisplayName(roster))
        local events = R.GetEventsSorted(roster)
        if selectedEventId ~= false and (not selectedEventId or not R.GetEvent(roster, selectedEventId)) then
            -- Por defecto, la próxima fecha (o la más reciente si ya pasaron todas)
            selectedEventId = nil
            local today = date("%Y-%m-%d")
            for i = #events, 1, -1 do
                if events[i].date >= today then selectedEventId = events[i].id break end
            end
            if not selectedEventId and events[1] then selectedEventId = events[1].id end
        end
        local event = SelectedEvent(roster)
        dropEvent:SetText(event and R.FormatEventDate(event) or "Sin fecha")
        UpdateRecipients()
    end

    dropEvent:SetupMenu(function(_, root)
        local roster = R.GetSelected()
        root:CreateRadio("Sin fecha", function() return not selectedEventId end,
            function() selectedEventId = false; Refresh() end)
        for _, event in ipairs(R.GetEventsSorted(roster)) do
            local id = event.id
            local label = R.FormatEventDate(event) .. ((event.note and event.note ~= "") and (" · " .. event.note) or "")
            root:CreateRadio(label, function() return selectedEventId == id end,
                function() selectedEventId = id; Refresh() end)
        end
    end)
    chkBench:SetScript("OnClick", UpdateRecipients)

    btnGuild = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnGuild:SetSize(180, 24)
    btnGuild:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
    btnGuild:SetText("Enviar a la hermandad")
    btnGuild:SetScript("OnClick", function()
        local roster = R.GetSelected()
        local msg = ExpandRosterMessage(editor.GetText(), roster, SelectedEvent(roster), nil)
        if msg == "" then return end
        if #msg > MAX_CHAT_BYTES then
            PrintGC("|cFFFF3333El mensaje supera los " .. MAX_CHAT_BYTES .. " caracteres del chat.|r")
            return
        end
        if C_ChatInfo and C_ChatInfo.SendChatMessage then
            C_ChatInfo.SendChatMessage(msg, "GUILD")
        else
            SendChatMessage(msg, "GUILD")
        end
    end)

    -- Un susurro personalizado a cada integrante conectado, uno cada medio segundo
    btnWhisper = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnWhisper:SetSize(180, 24)
    btnWhisper:SetPoint("LEFT", btnGuild, "RIGHT", 8, 0)
    btnWhisper:SetText("Susurrar a cada uno")
    btnWhisper:SetScript("OnClick", function(self)
        if whisperTicker then return end
        local roster = R.GetSelected()
        local event = SelectedEvent(roster)
        local template = editor.GetText()
        local queue = {}
        for _, name in ipairs(Recipients(roster)) do
            local msg = ExpandRosterMessage(template, roster, event, name)
            if msg ~= "" and #msg <= MAX_CHAT_BYTES then table.insert(queue, { name = name, msg = msg }) end
        end
        if #queue == 0 then
            PrintGC("No hay integrantes conectados a los que susurrar (o el mensaje es demasiado largo).")
            return
        end
        self:Disable()
        local sent = 0
        whisperTicker = C_Timer.NewTicker(ROSTER_WHISPER_INTERVAL, function()
            local item = table.remove(queue, 1)
            if item then
                SendWhisper(item.name, item.msg)
                sent = sent + 1
            end
            if #queue == 0 then
                whisperTicker:Cancel()
                whisperTicker = nil
                self:Enable()
                PrintGC("Susurros enviados: |cFFFFD100" .. sent .. "|r.")
                UpdateRecipients()
            end
        end)
        UpdateRecipients()
    end)

    local btnClose = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnClose:SetSize(100, 24)
    btnClose:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
    btnClose:SetText("Cerrar")
    btnClose:SetScript("OnClick", function() frame:Hide() end)

    frame:SetScript("OnShow", function()
        selectedEventId = nil   -- los ids de fecha son por roster
        editor.SetText(GuildControlDB.settings.rosterMessage or "")
        Refresh()
    end)
    return frame
end

function uiModule.ShowRosterMessage()
    if not GC_UI or not addonTable.Roster then return end
    if not GC_RosterMsgFrame then GC_RosterMsgFrame = CreateRosterMessageFrame() end
    if GC_RosterMsgFrame:IsShown() then GC_RosterMsgFrame:Hide() end
    GC_RosterMsgFrame:Show()
end

-- =========================================================================
-- 8b3. ANUNCIO EDITABLE DE LA COMPOSICIÓN DEL ROSTER
-- =========================================================================
-- Se rellena con la composición (una línea por rol) y se puede editar a mano.
-- Cada línea se envía como un mensaje al chat de hermandad.
local GC_RosterAnnounceFrame = nil

local function CreateRosterAnnounceFrame()
    local R = addonTable.Roster
    local frame = CreateFrame("Frame", "GuildControlRosterAnnounceFrame", GC_UI, "BasicFrameTemplateWithInset")
    frame:SetSize(620, 330)
    frame:SetPoint("CENTER", GC_UI, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -34)
    hint:SetWidth(584)
    hint:SetJustifyH("LEFT")
    hint:SetText("Cada línea se envía como un mensaje al chat de hermandad (máximo 255 caracteres por línea). Puedes añadir, quitar o cambiar líneas.")

    local box = CreateBackdropBox(frame, 584, 196, "TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    local scroll = CreateFrame("ScrollFrame", "GC_RosterAnnounceScroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -28, 8)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(540)
    edit:SetHeight(180)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(edit)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -6)

    local function Lines()
        local lines = {}
        for line in string.gmatch((edit:GetText() or "") .. "\n", "([^\n]*)\n") do
            line = strtrim(line)
            if line ~= "" then table.insert(lines, line) end
        end
        return lines
    end

    local function UpdateStatus()
        local lines = Lines()
        local tooLong = 0
        for _, line in ipairs(lines) do if #line > MAX_CHAT_BYTES then tooLong = tooLong + 1 end end
        status:SetText(#lines .. " mensajes" .. (tooLong > 0 and ("  |cFFFF3333" .. tooLong .. " línea(s) pasan de 255 caracteres|r") or ""))
    end
    edit:SetScript("OnTextChanged", UpdateStatus)

    local function Regenerate()
        local roster = R.GetSelected()
        frame.title:SetText("Anunciar " .. R.GetDisplayName(roster))
        edit:SetText(table.concat(R.BuildAnnounceLines(roster), "\n"))
        UpdateStatus()
    end

    local btnSend = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnSend:SetSize(180, 24)
    btnSend:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
    btnSend:SetText("Enviar a la hermandad")
    btnSend:SetScript("OnClick", function()
        if not IsInGuild() then return end
        local lines = Lines()
        for _, line in ipairs(lines) do
            if #line > MAX_CHAT_BYTES then
                PrintGC("|cFFFF3333Hay líneas de más de " .. MAX_CHAT_BYTES .. " caracteres: pártelas antes de enviar.|r")
                return
            end
        end
        for _, line in ipairs(lines) do
            if C_ChatInfo and C_ChatInfo.SendChatMessage then
                C_ChatInfo.SendChatMessage(line, "GUILD")
            else
                SendChatMessage(line, "GUILD")
            end
        end
        frame:Hide()
    end)

    local btnRegenerate = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnRegenerate:SetSize(150, 24)
    btnRegenerate:SetPoint("LEFT", btnSend, "RIGHT", 8, 0)
    btnRegenerate:SetText("Volver a generar")
    btnRegenerate:SetScript("OnClick", Regenerate)

    local btnClose = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnClose:SetSize(100, 24)
    btnClose:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
    btnClose:SetText("Cerrar")
    btnClose:SetScript("OnClick", function() frame:Hide() end)

    frame:SetScript("OnShow", Regenerate)
    return frame
end

function uiModule.ShowRosterAnnounce()
    if not GC_UI or not addonTable.Roster then return end
    if not GC_RosterAnnounceFrame then GC_RosterAnnounceFrame = CreateRosterAnnounceFrame() end
    if GC_RosterAnnounceFrame:IsShown() then GC_RosterAnnounceFrame:Hide() end
    GC_RosterAnnounceFrame:Show()
end

-- =========================================================================
-- 8c. VISTA MI PERFIL (ROL DECLARADO Y PERFIL DE OFICIAL/JUGADOR)
-- =========================================================================
local function BuildMyProfileView(parent)
    local P = addonTable.Profiles
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", view, "TOPLEFT", 20, -20)
    title:SetText("Mi perfil")

    local subtitle = view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)

    -- Grupo de casillas que se comportan como botones de opción
    local function CreateRoleChoice(labelText, anchor, yOffset, options, onChange)
        local label = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset)
        label:SetText(labelText)
        local checks, selected = {}, nil
        local group = {}
        function group.Set(value)
            selected = value
            for key, chk in pairs(checks) do chk:SetChecked(key == (value or "Ninguno")) end
        end
        function group.Get() return selected end
        for i, option in ipairs(options) do
            local chk = CreateFrame("CheckButton", nil, view, "UICheckButtonTemplate")
            chk:SetSize(24, 24)
            chk:SetPoint("TOPLEFT", label, "BOTTOMLEFT", (i - 1) * 130, -4)
            chk.text = chk:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            chk.text:SetPoint("LEFT", chk, "RIGHT", 2, 0)
            chk.text:SetText(option)
            chk:SetScript("OnClick", function()
                group.Set(option ~= "Ninguno" and option or nil)
                if onChange then onChange() end
            end)
            checks[option] = chk
        end
        group.label = label
        return group
    end

    local mainChoice = CreateRoleChoice("Rol principal", subtitle, -22, P.ROLES)
    local secondaryChoice = CreateRoleChoice("Rol secundario (opcional)", mainChoice.label, -50,
        { "Ninguno", "Tanque", "Sanador", "DPS" })

    -- ¿Personaje principal o alter? Si es alter, de quién
    local mainNameInput, charChoice   -- declarados antes para que el callback los vea
    charChoice = CreateRoleChoice("Este personaje es", secondaryChoice.label, -50, { "Principal", "Alter" },
        function() mainNameInput:SetShown(charChoice.Get() == "Alter") end)

    mainNameInput = CreateFrame("EditBox", nil, view, "InputBoxTemplate")
    mainNameInput:SetSize(170, 20)
    mainNameInput:SetPoint("TOPLEFT", charChoice.label, "BOTTOMLEFT", 240, -6)
    mainNameInput:SetAutoFocus(false)
    mainNameInput:SetMaxLetters(40)
    mainNameInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    mainNameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local mainNamePlaceholder = mainNameInput:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mainNamePlaceholder:SetPoint("LEFT", mainNameInput, "LEFT", 2, 0)
    mainNamePlaceholder:SetText("Nombre de tu principal")
    mainNameInput:SetScript("OnTextChanged", function(self) mainNamePlaceholder:SetShown((self:GetText() or "") == "") end)
    mainNameInput:Hide()

    -- Enfoque principal del jugador (columna Enfoque de Miembros)
    local focusChoice = CreateRoleChoice("Enfoque", charChoice.label, -50, P.FOCUS)

    local specLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    specLabel:SetPoint("TOPLEFT", focusChoice.label, "BOTTOMLEFT", 0, -50)
    specLabel:SetText("Especialización")

    -- Especialización: se elige entre las de la clase del personaje (con su icono y rol)
    local SPEC_ROLE_TO_ROLE = { TANK = "Tanque", HEALER = "Sanador", DAMAGER = "DPS" }
    local specValue = ""
    local specDropdown = CreateFrame("DropdownButton", "GC_ProfileSpec", view, "WowStyle1DropdownTemplate")
    specDropdown:SetPoint("TOPLEFT", specLabel, "BOTTOMLEFT", 0, -6)
    specDropdown:SetWidth(240)

    local function GetMySpecs()
        local specs = {}
        local num = GetNumSpecializations and GetNumSpecializations() or 0
        for i = 1, num do
            local _, name, _, icon, role = GetSpecializationInfo(i)
            if name then table.insert(specs, { name = name, icon = icon, role = SPEC_ROLE_TO_ROLE[role] }) end
        end
        return specs
    end

    local function SetSpec(name)
        specValue = name or ""
        specDropdown:SetText(specValue ~= "" and specValue or "Elige tu especialización")
    end

    specDropdown:SetupMenu(function(_, root)
        for _, spec in ipairs(GetMySpecs()) do
            local label = (spec.icon and ("|T" .. spec.icon .. ":16:16|t ") or "") .. spec.name
                .. (spec.role and ("  " .. RoleIcon(spec.role) .. " |cFF808080" .. spec.role .. "|r") or "")
            root:CreateRadio(label, function() return specValue == spec.name end, function()
                SetSpec(spec.name)
                -- El rol principal sigue al de la especialización elegida (se puede cambiar después)
                if spec.role then mainChoice.Set(spec.role) end
            end)
        end
        root:CreateRadio("Sin especificar", function() return specValue == "" end, function() SetSpec("") end)
    end)

    -- Especialización off: otra de la clase que también puede jugar (solo con equipo para ella)
    local offSpecValue = ""
    local offSpecLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    offSpecLabel:SetPoint("LEFT", specLabel, "LEFT", 260, 0)
    offSpecLabel:SetText("Especialización off |cFFFF7F00(solo si tienes equipo)|r")

    local offSpecDropdown = CreateFrame("DropdownButton", "GC_ProfileOffSpec", view, "WowStyle1DropdownTemplate")
    offSpecDropdown:SetPoint("TOPLEFT", offSpecLabel, "BOTTOMLEFT", 0, -6)
    offSpecDropdown:SetWidth(240)

    local function SetOffSpec(name)
        offSpecValue = name or ""
        offSpecDropdown:SetText(offSpecValue ~= "" and offSpecValue or "Ninguna")
    end

    offSpecDropdown:SetupMenu(function(_, root)
        root:CreateTitle("Elígela solo si tienes equipo para jugarla")
        root:CreateRadio("Ninguna", function() return offSpecValue == "" end, function() SetOffSpec("") end)
        for _, spec in ipairs(GetMySpecs()) do
            if spec.name ~= specValue then
                local label = (spec.icon and ("|T" .. spec.icon .. ":16:16|t ") or "") .. spec.name
                    .. (spec.role and ("  " .. RoleIcon(spec.role) .. " |cFF808080" .. spec.role .. "|r") or "")
                root:CreateRadio(label, function() return offSpecValue == spec.name end, function() SetOffSpec(spec.name) end)
            end
        end
    end)

    local noteLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noteLabel:SetPoint("TOPLEFT", specDropdown, "BOTTOMLEFT", 0, -16)
    noteLabel:SetText("Nota para los oficiales")

    local noteInput = CreateFrame("EditBox", nil, view, "InputBoxTemplate")
    noteInput:SetSize(460, 20)
    noteInput:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 6, -6)
    noteInput:SetAutoFocus(false)
    noteInput:SetMaxLetters(80)
    local notePlaceholder = noteInput:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    notePlaceholder:SetPoint("LEFT", noteInput, "LEFT", 2, 0)
    notePlaceholder:SetText("Disponibilidad, otras especializaciones, alters...")
    noteInput:SetScript("OnTextChanged", function(self) notePlaceholder:SetShown((self:GetText() or "") == "") end)

    for _, box in ipairs({ noteInput }) do
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end

    local btnSave = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnSave:SetSize(160, 24)
    btnSave:SetPoint("TOPLEFT", noteInput, "BOTTOMLEFT", -6, -16)
    btnSave:SetText("Guardar y enviar")

    local saveStatus = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    saveStatus:SetPoint("LEFT", btnSave, "RIGHT", 12, 0)

    local explanation = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    explanation:SetPoint("TOPLEFT", btnSave, "BOTTOMLEFT", 0, -12)
    explanation:SetWidth(520)
    explanation:SetJustifyH("LEFT")
    explanation:SetText("Tu rol se envía a los miembros de la hermandad que usan GuildControl. Los oficiales lo ven en Miembros y al montar el roster. Si un oficial te asigna otro rol a mano, prevalece el suyo.")

    btnSave:SetScript("OnClick", function()
        local main = mainChoice.Get()
        if not main then
            saveStatus:SetText("|cFFFF3333Elige tu rol principal.|r")
            return
        end
        local charType = charChoice.Get() == "Alter" and "alt" or "main"
        P.SaveMyProfile(main, secondaryChoice.Get(), specValue, noteInput:GetText(), charType, mainNameInput:GetText(), focusChoice.Get(), offSpecValue)
        noteInput:ClearFocus()
        saveStatus:SetText("|cFF00FF00Guardado y enviado a las " .. date("%H:%M") .. ".|r")
    end)

    -- Columna derecha: lo que tiene la ficha y, para oficiales, la gestión de perfiles
    local side = CreateBackdropBox(view, 300, 400, "TOPRIGHT", view, "TOPRIGHT", -12, -60)

    local sideTitle = side:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sideTitle:SetPoint("TOPLEFT", side, "TOPLEFT", 12, -12)
    sideTitle:SetText("Tu ficha en la hermandad")

    local sideText = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sideText:SetPoint("TOPLEFT", sideTitle, "BOTTOMLEFT", 0, -8)
    sideText:SetWidth(276)
    sideText:SetJustifyH("LEFT")

    local officerTitle = side:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    officerTitle:SetPoint("TOPLEFT", side, "TOPLEFT", 12, -150)
    officerTitle:SetText("Oficiales")

    local officerText = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    officerText:SetPoint("TOPLEFT", officerTitle, "BOTTOMLEFT", 0, -8)
    officerText:SetWidth(276)
    officerText:SetJustifyH("LEFT")

    local btnRequest = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
    btnRequest:SetSize(200, 22)
    btnRequest:SetPoint("TOPLEFT", officerText, "BOTTOMLEFT", 0, -10)
    btnRequest:SetText("Pedir roles a la hermandad")
    btnRequest:SetScript("OnClick", function()
        P.RequestRoles()
        PrintGC("Petición de roles enviada. Responden los miembros conectados que usan GuildControl.")
    end)

    local rankLabel = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rankLabel:SetPoint("TOPLEFT", btnRequest, "BOTTOMLEFT", 0, -16)
    rankLabel:SetText("Perfil de oficial hasta el rango:")

    local dropRank = CreateFrame("DropdownButton", "GC_OfficerRankSelect", side, "WowStyle1DropdownTemplate")
    dropRank:SetPoint("TOPLEFT", rankLabel, "BOTTOMLEFT", 0, -6)
    dropRank:SetWidth(200)
    dropRank:SetupMenu(function(_, root)
        for _, rank in ipairs(P.GetGuildRanks()) do
            local index = rank.index
            root:CreateRadio(rank.name,
                function() return P.GetOfficerRankIndex() == index end,
                function()
                    GuildControlDB.settings.officerRankIndex = index
                    uiModule.ApplyProfile()
                    view:GetScript("OnShow")(view)
                end)
        end
    end)

    local rankHint = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rankHint:SetPoint("TOPLEFT", dropRank, "BOTTOMLEFT", 0, -6)
    rankHint:SetWidth(276)
    rankHint:SetJustifyH("LEFT")
    rankHint:SetText("Ese rango y los superiores ven todas las pestañas. Quien tenga el permiso de chat de oficiales del juego también es oficial. Es un ajuste de tu cliente: cada oficial lo configura en el suyo.")

    local officerWidgets = { officerTitle, officerText, btnRequest, rankLabel, dropRank, rankHint }

    view:SetScript("OnShow", function()
        local profile = P.GetMyProfile()
        mainChoice.Set(profile.main)
        secondaryChoice.Set(profile.secondary)
        charChoice.Set(profile.charType == "alt" and "Alter" or "Principal")
        focusChoice.Set(profile.focus)
        mainNameInput:SetText(profile.mainName or "")
        mainNameInput:SetShown(profile.charType == "alt")
        SetSpec(profile.spec)
        SetOffSpec(profile.offSpec)
        specLabel:SetText("Especialización (" .. (UnitClass("player") or "") .. ")")
        noteInput:SetText(profile.note or "")
        saveStatus:SetText("")

        local isOfficer = P.IsOfficer()
        local m = GuildControlDB.members[P.GetMyFullName()] or {}
        subtitle:SetText((UnitName("player") or "") .. "   ·   Rango: |cFFFFD100" .. (m.rank or "-") .. "|r   ·   Perfil: "
            .. (isOfficer and "|cFFFFD100Oficial|r" or "|cFF00FFFFJugador|r"))

        local source = m.roleSource == "officer" and "asignado por un oficial"
            or (m.roleSource == "declared" and "declarado por ti" or "por defecto")
        -- Oficial: sus propios rosters. Jugador: los que han publicado los oficiales.
        local rostersText = m.roster or "Sin Roster"
        if not isOfficer and uiModule.GetMySharedRosterNames then
            local names = uiModule.GetMySharedRosterNames()
            rostersText = #names > 0 and table.concat(names, ", ") or "ninguno publicado"
        end
        sideText:SetText("Rol en tu ficha: |cFFFFD100" .. (m.role or "DPS") .. "|r |cFF808080(" .. source .. ")|r\n"
            .. "Rosters: |cFFFFD100" .. rostersText .. "|r\n"
            .. "Profesiones: " .. (m.prof1 or "Ninguna") .. ", " .. (m.prof2 or "Ninguna") .. "\n\n"
            .. "|cFF808080Esto es lo que guarda tu cliente. Cada oficial tiene su propia copia.|r")

        for _, widget in ipairs(officerWidgets) do widget:SetShown(isOfficer) end
        if isOfficer then
            local declared, total = P.CountDeclared()
            officerText:SetText("Roles declarados: |cFFFFD100" .. declared .. "|r de " .. total .. " miembros.\n"
                .. "Los ves en Miembros (vista previa) y en los candidatos del roster.")
            local currentRank = P.GetOfficerRankIndex()
            dropRank:SetText("Rango " .. currentRank)
            for _, rank in ipairs(P.GetGuildRanks()) do
                if rank.index == currentRank then dropRank:SetText(rank.name) end
            end
        end
    end)

    uiModule.RefreshMyProfile = function()
        if view:IsShown() then view:GetScript("OnShow")(view) end
    end
    containers.views["Mi perfil"] = view
end

-- =========================================================================
-- 8d. VISTA MIS ROSTERS (JUGADORES: ROSTERS PUBLICADOS, SOLO LECTURA)
-- =========================================================================
-- Rosters publicados en los que estoy (titular o suplente en la base o en algún jefe)
local function SharedRostersWithMe()
    local R = addonTable.Roster
    local me = addonTable.Profiles and addonTable.Profiles.GetMyFullName()
    local result = {}
    if not R or not me then return result end
    for _, item in ipairs(R.GetSharedRosters()) do
        local inIt = item.roster.members[me] ~= nil
        for _, variant in pairs(item.roster.variants or {}) do
            if variant.overrides[me] then inIt = true end
        end
        if inIt then table.insert(result, item) end
    end
    return result
end

local function BuildMyRostersView(parent)
    local R = addonTable.Roster
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local selectedSyncId, selectedVariantId = nil, nil

    local title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", view, "TOPLEFT", 20, -20)
    title:SetText("Mis rosters")

    local subtitle = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetText("Rosters que publican los oficiales con el botón Compartir. Solo lectura.")

    local dropRoster = CreateFrame("DropdownButton", "GC_MyRostersSelect", view, "WowStyle1DropdownTemplate")
    dropRoster:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)
    dropRoster:SetWidth(220)

    local dropVariant = CreateFrame("DropdownButton", "GC_MyRostersVariant", view, "WowStyle1DropdownTemplate")
    dropVariant:SetPoint("LEFT", dropRoster, "RIGHT", 12, 0)
    dropVariant:SetWidth(170)

    local btnUpdate = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnUpdate:SetSize(110, 22)
    btnUpdate:SetPoint("LEFT", dropVariant, "RIGHT", 12, 0)
    btnUpdate:SetText("Actualizar")
    btnUpdate:SetScript("OnClick", function()
        R.RequestPublishedRosters()
        PrintGC("Pidiendo los rosters publicados a los oficiales conectados...")
    end)

    local infoText = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoText:SetPoint("LEFT", btnUpdate, "RIGHT", 12, 0)
    infoText:SetPoint("RIGHT", view, "RIGHT", -16, 0)
    infoText:SetJustifyH("LEFT")
    infoText:SetWordWrap(false)

    -- Composición (izquierda) y mis datos (derecha)
    local comp = CreateBackdropBox(view, 600, 380, "TOPLEFT", view, "TOPLEFT", 12, -116)
    local function Column(x, y, width)
        local fs = comp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", comp, "TOPLEFT", x, y)
        fs:SetWidth(width)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetSpacing(3)
        return fs
    end
    local tankCol = Column(12, -12, 130)
    local healerCol = Column(150, -12, 140)
    local dpsCol1 = Column(300, -12, 145)
    local dpsCol2 = Column(450, -30, 145)
    local benchCol = Column(12, -260, 576)

    local side = CreateBackdropBox(view, 266, 380, "TOPLEFT", comp, "TOPRIGHT", 8, 0)
    local sideText = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sideText:SetPoint("TOPLEFT", side, "TOPLEFT", 12, -12)
    sideText:SetWidth(242)
    sideText:SetJustifyH("LEFT")
    sideText:SetJustifyV("TOP")
    sideText:SetSpacing(3)

    local emptyText = view:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", comp, "CENTER", 0, 0)
    emptyText:SetWidth(520)

    local function SelectedItem()
        local list = R.GetSharedRosters()
        for _, item in ipairs(list) do
            if item.roster.syncId == selectedSyncId then return item end
        end
        -- Por defecto, el primero en el que estoy (o el primero publicado)
        local mine = SharedRostersWithMe()
        local item = mine[1] or list[1]
        selectedSyncId = item and item.roster.syncId or nil
        selectedVariantId = nil
        return item
    end

    local function NameLine(fullName, me)
        local m = GuildControlDB.members[fullName] or {}
        local short = string.match(fullName, "^([^-]+)") or fullName
        local hex = addonTable.GetClassColorHex(m.class)
        if fullName == me then return "|cFF00FF00>|r |cFF" .. hex .. short .. "|r |cFF00FF00(tú)|r" end
        return "|cFF" .. hex .. short .. "|r"
    end

    local Refresh

    dropRoster:SetupMenu(function(_, root)
        for _, item in ipairs(R.GetSharedRosters()) do
            local syncId = item.roster.syncId
            root:CreateRadio(item.roster.name .. " |cFF808080(" .. item.from .. ")|r",
                function() return selectedSyncId == syncId end,
                function() selectedSyncId = syncId; selectedVariantId = nil; Refresh() end)
        end
    end)
    dropVariant:SetupMenu(function(_, root)
        local item = SelectedItem()
        if not item then return end
        root:CreateRadio("Base (todos los jefes)", function() return selectedVariantId == nil end,
            function() selectedVariantId = nil; Refresh() end)
        for _, variant in ipairs(R.GetVariants(item.roster)) do
            local id = variant.id
            root:CreateRadio(variant.name, function() return selectedVariantId == id end,
                function() selectedVariantId = id; Refresh() end)
        end
    end)

    Refresh = function()
        if not view:IsShown() then return end
        local item = SelectedItem()
        local hasItem = item ~= nil
        for _, widget in ipairs({ comp, side, dropVariant }) do widget:SetShown(hasItem) end
        if not hasItem then
            dropRoster:SetText("Sin rosters")
            infoText:SetText("")
            emptyText:SetText("Todavía no has recibido ningún roster. Los oficiales deben publicarlo con Compartir; pulsa Actualizar para pedirlo a los que estén conectados.")
            emptyText:Show()
            return
        end
        emptyText:Hide()

        local roster = item.roster
        local me = addonTable.Profiles.GetMyFullName()
        local variant = selectedVariantId and (roster.variants or {})[selectedVariantId] or nil
        dropRoster:SetText(roster.name)
        dropVariant:SetText(variant and variant.name or "Base")
        infoText:SetText("Publicado por |cFFFFD100" .. item.from .. "|r" .. (item.fromRank and (" (" .. item.fromRank .. ")") or "")
            .. " · " .. R.DifficultyLabel(roster) .. " " .. roster.size
            .. " · recibido " .. date("%d/%m %H:%M", item.receivedAt or time()))

        -- Composición efectiva de la base o del jefe elegido
        local bySlot = { tank = {}, healer = {}, dps = {}, bench = {} }
        for name, slot in pairs(R.GetEffectiveMembers(roster, variant)) do
            if bySlot[slot] then table.insert(bySlot[slot], name) end
        end
        for _, list in pairs(bySlot) do table.sort(list) end

        local function Block(label, list)
            local lines = { "|cFFFFD100" .. label .. " (" .. #list .. ")|r" }
            for _, name in ipairs(list) do table.insert(lines, NameLine(name, me)) end
            return table.concat(lines, "\n")
        end
        tankCol:SetText(Block("Tanques", bySlot.tank))
        healerCol:SetText(Block("Sanadores", bySlot.healer))
        local half = math.ceil(#bySlot.dps / 2)
        local dps1, dps2 = {}, {}
        for i, name in ipairs(bySlot.dps) do table.insert(i <= half and dps1 or dps2, name) end
        dpsCol1:SetText(Block("DPS", dps1))
        local lines2 = {}
        for _, name in ipairs(dps2) do table.insert(lines2, NameLine(name, me)) end
        dpsCol2:SetText(table.concat(lines2, "\n"))
        local benchNames = {}
        for _, name in ipairs(bySlot.bench) do table.insert(benchNames, NameLine(name, me)) end
        benchCol:SetText("|cFFFFD100Suplentes (" .. #bySlot.bench .. ")|r\n" .. table.concat(benchNames, "   "))

        -- Mis datos: puesto, próximas fechas con mi marca y asistencia
        local SLOT_TEXT = { tank = "Tanque (titular)", healer = "Sanador (titular)", dps = "DPS (titular)", bench = "Suplente" }
        local mySlot = R.GetEffectiveMembers(roster, variant)[me]
        local lines = { "|cFFFFD100Tu puesto|r", mySlot and SLOT_TEXT[mySlot] or "|cFF808080No estás en esta composición|r", "" }

        table.insert(lines, "|cFFFFD100Próximas fechas|r")
        local today = date("%Y-%m-%d")
        local upcoming = {}
        for _, event in ipairs(R.GetEventsSorted(roster)) do
            if event.date >= today then table.insert(upcoming, 1, event) end
        end
        if #upcoming == 0 then table.insert(lines, "|cFF808080Sin fechas próximas|r") end
        for i = 1, math.min(#upcoming, 6) do
            local event = upcoming[i]
            local status = event.attendance[me]
            local mark = status and ("|cFF" .. R.ATTENDANCE_COLORS[status] .. R.ATTENDANCE_LABELS[status] .. "|r") or "|cFF808080sin marcar|r"
            local note = (event.note and event.note ~= "") and (" · " .. event.note) or ""
            table.insert(lines, R.FormatEventDate(event) .. note .. "  " .. mark)
        end

        table.insert(lines, "")
        table.insert(lines, "|cFFFFD100Tu asistencia|r")
        local stats = R.GetAttendanceStats(roster, me)
        if stats.percent then
            table.insert(lines, stats.percent .. "% (" .. (stats.present + stats.late) .. " de " .. stats.counted .. " fechas)")
        else
            table.insert(lines, "|cFF808080Sin datos todavía|r")
        end
        sideText:SetText(table.concat(lines, "\n"))
    end

    R.SetReceivedListener(function()
        Refresh()
        if uiModule.UpdatePlayerInfoBar then uiModule.UpdatePlayerInfoBar() end
    end)
    view:SetScript("OnShow", Refresh)
    containers.views["Mis rosters"] = view
end

-- Nombres de los rosters publicados en los que estoy (para la barra del perfil de jugador)
function uiModule.GetMySharedRosterNames()
    local names = {}
    for _, item in ipairs(SharedRostersWithMe()) do table.insert(names, item.roster.name) end
    return names
end

-- =========================================================================
-- 8e. VISTA RESUMEN (NOTICIAS DE LA HERMANDAD, CONSUME MODULES/NEWS.LUA)
-- =========================================================================
-- Color de la franja izquierda de cada noticia según su tipo
local NEWS_KIND_COLORS = {
    achievement = { 1, 0.82, 0 }, guildAchievement = { 1, 0.6, 0 },
    boss = { 0.9, 0.2, 0.2 }, loot = { 0.64, 0.21, 0.93 },
    join = { 0.2, 0.9, 0.2 }, leave = { 0.5, 0.5, 0.5 }, other = { 0.4, 0.7, 1 },
}
local NEWS_CARD_HEIGHT = 46

local function BuildSummaryView(parent)
    local N = addonTable.News
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local currentFilter = "achievement"
    local Refresh

    -- ---------------------------------------------------------------------
    -- Columna izquierda: noticias
    -- ---------------------------------------------------------------------
    local feedBox = CreateBackdropBox(view, 566, 500, "TOPLEFT", view, "TOPLEFT", 10, -10)

    local feedTitle = feedBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    feedTitle:SetPoint("TOPLEFT", feedBox, "TOPLEFT", 14, -12)
    feedTitle:SetText("Noticias de la hermandad")

    local btnRefresh = CreateFrame("Button", nil, feedBox, "UIPanelButtonTemplate")
    btnRefresh:SetSize(90, 22)
    btnRefresh:SetPoint("TOPRIGHT", feedBox, "TOPRIGHT", -12, -10)
    btnRefresh:SetText("Actualizar")
    btnRefresh:SetScript("OnClick", function()
        N.Request()
        Refresh()
    end)

    local filterButtons = {}
    local previous = nil
    for _, filter in ipairs(N.FILTERS) do
        local btn = CreateFrame("Button", nil, feedBox, "UIPanelButtonTemplate")
        btn:SetSize(80, 20)
        if previous then
            btn:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", feedTitle, "BOTTOMLEFT", 0, -10)
        end
        btn:SetText(filter.label)
        btn:SetScript("OnClick", function()
            currentFilter = filter.key
            Refresh()
        end)
        filterButtons[filter.key] = btn
        previous = btn
    end

    local feedScroll = CreateFrame("ScrollFrame", "GC_SummaryFeedScroll", feedBox, "UIPanelScrollFrameTemplate")
    feedScroll:SetPoint("TOPLEFT", feedBox, "TOPLEFT", 10, -72)
    feedScroll:SetPoint("BOTTOMRIGHT", feedBox, "BOTTOMRIGHT", -30, 10)
    local feedChild = CreateFrame("Frame")
    feedChild:SetSize(524, 1)
    feedScroll:SetScrollChild(feedChild)

    local emptyText = feedBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", feedBox, "CENTER", 0, -20)
    emptyText:SetWidth(460)

    -- Vista previa de una noticia en el panel derecho (logro u objeto)
    -- Vista previa de botín: datos del objeto y su origen (banda o mazmorra y jefe, si figura
    -- en el diario de encuentros). El origen llega de forma asíncrona.
    local previewedLootItem = nil
    local function LootPreviewText(item, sourceText)
        local d = N.GetItemDetails(item.link)
        local lines = { "|cFFFFD100Botín|r", "", item.link, "" }
        if d.itemLevel then table.insert(lines, "Nivel de objeto: |cFFFFFFFF" .. d.itemLevel .. "|r") end
        if d.type or d.slot then
            table.insert(lines, "Tipo: |cFFFFFFFF" .. table.concat({ d.slot or "", d.type or "" }, d.slot and d.type and " · " or "") .. "|r")
        end
        local verb = item.lootType == "crafted" and "Fabricado por" or (item.lootType == "purchased" and "Comprado por" or "Obtenido por")
        table.insert(lines, verb .. ": |cFFFFFFFF" .. (item.who or "-") .. "|r")
        table.insert(lines, "Fecha: " .. (item.dateText or "-"))
        table.insert(lines, "")
        table.insert(lines, "|cFFFFD100Origen|r")
        table.insert(lines, sourceText)
        table.insert(lines, "")
        table.insert(lines, "|cFF808080Pasa el ratón por la noticia para ver el objeto. Shift+clic para compartirlo en la hermandad.|r")
        return table.concat(lines, "\n")
    end

    local function ShowLootPreview(item)
        previewedLootItem = item
        if item.lootType == "crafted" then
            SetPreviewText(LootPreviewText(item, "Fabricado con una profesión."))
            return
        elseif item.lootType == "purchased" then
            SetPreviewText(LootPreviewText(item, "Comprado a un vendedor. El juego no indica a qué PNJ."))
            return
        end
        SetPreviewText(LootPreviewText(item, "|cFF808080Buscando en el diario de encuentros...|r"))
        N.LookupItemSource(item.link, function(source)
            if previewedLootItem ~= item or activeTab ~= "Resumen" then return end
            local text
            if source then
                text = "|cFFFFFFFF" .. (source.instance or "Instancia desconocida") .. "|r"
                    .. (source.encounter and ("\nJefe: |cFFFFFFFF" .. source.encounter .. "|r") or "")
            elseif source == false then
                text = "No figura en el diario de encuentros: puede ser botín de mundo, de una misión, de un evento o de un vendedor."
            else
                text = "|cFF808080No se pudo consultar el diario de encuentros ahora mismo.|r"
            end
            SetPreviewText(LootPreviewText(item, text))
        end)
    end

    local function ShowNewsPreview(item)
        if item.achievementId then
            -- Detalle del logro y botón que lleva a ese logro dentro de la sección Logros
            SetPreviewText(BuildAchievementPreviewText(item.achievementId)
                .. "\n\n|cFF808080Pulsa el botón para ir al detalle del logro en la sección Logros.|r")
            local id, mode = item.achievementId, (item.kind == "guildAchievement") and "guild" or "player"
            SetPreviewAction("Ir al logro en Logros", function()
                SwitchTab("Logros")
                if uiModule.FocusAchievement then uiModule.FocusAchievement(id, mode) end
            end)
        elseif item.link then
            ShowLootPreview(item)
        else
            SetPreviewText("|cFFFFD100" .. (item.title or "") .. "|r\n\n" .. (item.detail or "") .. "\n\nFecha: " .. (item.dateText or "-"))
        end
    end

    -- Shift+clic: comparte el objeto o el logro en el chat de hermandad
    local function ShareNewsItem(item)
        if not IsInGuild() then return end
        local msg
        if item.link then
            msg = "Botín de " .. (item.who or "?") .. ": " .. item.link
        elseif item.achievementId and GetAchievementLink then
            local link = GetAchievementLink(item.achievementId)
            if link then
                msg = (item.kind == "guildAchievement" and "La hermandad ha conseguido " or ((item.who or "?") .. " ha conseguido ")) .. link
            end
        end
        if not msg then return end
        if C_ChatInfo and C_ChatInfo.SendChatMessage then
            C_ChatInfo.SendChatMessage(msg, "GUILD")
        else
            SendChatMessage(msg, "GUILD")
        end
    end

    local cards = {}
    local function AcquireCard(index)
        local card = cards[index]
        if card then return card end
        card = CreateFrame("Button", nil, feedChild)
        card:SetWidth(524)
        card.bg = card:CreateTexture(nil, "BACKGROUND")
        card.bg:SetAllPoints()
        card.highlight = card:CreateTexture(nil, "HIGHLIGHT")
        card.highlight:SetAllPoints()
        card.highlight:SetColorTexture(1, 1, 1, 0.06)
        card.bar = card:CreateTexture(nil, "ARTWORK")
        card.bar:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
        card.bar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
        card.bar:SetWidth(3)
        card.icon = card:CreateTexture(nil, "ARTWORK")
        card.icon:SetSize(32, 32)
        card.icon:SetPoint("LEFT", card, "LEFT", 10, 0)
        card.title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        card.title:SetJustifyH("LEFT")
        card.title:SetWordWrap(false)
        card.detail = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.detail:SetPoint("BOTTOMLEFT", card.icon, "BOTTOMRIGHT", 10, 1)
        card.detail:SetPoint("RIGHT", card, "RIGHT", -10, 0)
        card.detail:SetJustifyH("LEFT")
        card.detail:SetWordWrap(false)
        card.date = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        card.date:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -6)

        -- Tooltip del logro o del objeto, y vista previa al hacer clic
        card:SetScript("OnEnter", function(self)
            local item = self.item
            if not item then return end
            local link = item.link
            if not link and item.achievementId and GetAchievementLink then link = GetAchievementLink(item.achievementId) end
            if link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, link)
                GameTooltip:Show()
            end
        end)
        card:SetScript("OnLeave", function() GameTooltip:Hide() end)
        card:SetScript("OnClick", function(self)
            if not self.item then return end
            if IsShiftKeyDown() then ShareNewsItem(self.item) else ShowNewsPreview(self.item) end
        end)
        cards[index] = card
        return card
    end

    -- Una tarjeta puede ser noticia o cabecera de semana
    local function SetupCard(card, item, headerText)
        local isHeader = headerText ~= nil
        card.item = item
        card:SetHeight(isHeader and 24 or (NEWS_CARD_HEIGHT - 4))
        card:EnableMouse(not isHeader)
        card.icon:SetShown(not isHeader)
        card.bar:SetShown(not isHeader)
        card.detail:SetShown(not isHeader)
        card.date:SetShown(not isHeader)
        card.title:ClearAllPoints()
        if isHeader then
            card.bg:SetColorTexture(1, 0.82, 0, 0.08)
            card.title:SetPoint("LEFT", card, "LEFT", 10, 0)
            card.title:SetPoint("RIGHT", card, "RIGHT", -10, 0)
            card.title:SetText("|cFFFFD100" .. headerText .. "|r")
        else
            card.bg:SetColorTexture(1, 1, 1, 0.04)
            card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -1)
            card.title:SetPoint("RIGHT", card, "RIGHT", -60, 0)
            local color = NEWS_KIND_COLORS[item.kind] or NEWS_KIND_COLORS.other
            card.bar:SetColorTexture(color[1], color[2], color[3], 0.9)
            card.icon:SetTexture(item.icon)
            card.title:SetText(item.title or "")
            card.detail:SetText(item.detail or "")
            card.date:SetText(item.dateText or "")
        end
        card:Show()
    end


    -- ---------------------------------------------------------------------
    -- Columna derecha: mensaje del día, próximas bandas, rosters y oficiales
    -- ---------------------------------------------------------------------
    local function SideBox(titleText, height, anchor)
        local box = CreateBackdropBox(view, 304, height)
        if anchor then
            box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
        else
            box:SetPoint("TOPLEFT", feedBox, "TOPRIGHT", 8, 0)
        end
        box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
        box.title:SetText(titleText)
        box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        box.text:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -6)
        box.text:SetPoint("RIGHT", box, "RIGHT", -12, 0)
        box.text:SetJustifyH("LEFT")
        box.text:SetJustifyV("TOP")
        box.text:SetSpacing(3)
        return box
    end

    local motdBox = SideBox("Mensaje del día", 84)
    local raidsBox = SideBox("Próximas bandas", 118, motdBox)
    local rostersBox = SideBox("Rosters", 118, raidsBox)
    local officersBox = SideBox("Oficiales", 162, rostersBox)

    -- La lista de oficiales puede ser larga: va dentro de un scroll
    officersBox.text:Hide()
    local officersScroll = CreateFrame("ScrollFrame", "GC_SummaryOfficersScroll", officersBox, "UIPanelScrollFrameTemplate")
    officersScroll:SetPoint("TOPLEFT", officersBox.title, "BOTTOMLEFT", 0, -6)
    officersScroll:SetPoint("BOTTOMRIGHT", officersBox, "BOTTOMRIGHT", -28, 8)
    local officersChild = CreateFrame("Frame")
    officersChild:SetSize(262, 1)
    officersScroll:SetScrollChild(officersChild)
    local officersText = officersChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    officersText:SetPoint("TOPLEFT", officersChild, "TOPLEFT", 0, 0)
    officersText:SetWidth(262)
    officersText:SetJustifyH("LEFT")
    officersText:SetSpacing(3)

    local WEEKDAYS = { "Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb" }
    local function ShortEventDate(event)
        local y, mo, d = string.match(event.date or "", "^(%d+)-(%d+)-(%d+)$")
        if not y then return event.date or "" end
        local t = time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 })
        return WEEKDAYS[tonumber(date("%w", t)) + 1] .. " " .. d .. "/" .. mo .. " " .. (event.time or "")
    end

    local function RefreshSide()
        local motd = N.GetMOTD()
        motdBox.text:SetText(motd ~= "" and motd or "|cFF808080La hermandad no tiene mensaje del día.|r")

        local raidLines = {}
        for _, entry in ipairs(N.GetUpcomingRaids(4)) do
            local note = (entry.event.note and entry.event.note ~= "") and (" |cFF808080· " .. entry.event.note .. "|r") or ""
            table.insert(raidLines, "|cFFFFD100" .. ShortEventDate(entry.event) .. "|r  " .. entry.roster.name .. note)
        end
        raidsBox.text:SetText(#raidLines > 0 and table.concat(raidLines, "\n")
            or "|cFF808080No hay bandas programadas. Añádelas en Roster > Fechas.|r")

        local rosterLines = {}
        for i, r in ipairs(N.GetRosterSummaries()) do
            if i > 5 then
                table.insert(rosterLines, "|cFF808080y más...|r")
                break
            end
            local color = r.starters >= r.size and "00FF00" or "FFD100"
            table.insert(rosterLines, r.name .. " |cFF808080(" .. r.difficulty .. " " .. r.size .. ")|r  |cFF" .. color
                .. r.starters .. "/" .. r.size .. "|r" .. (r.bench > 0 and (" |cFF808080+" .. r.bench .. "|r") or ""))
        end
        rostersBox.text:SetText(#rosterLines > 0 and table.concat(rosterLines, "\n") or "|cFF808080Todavía no hay rosters.|r")

        -- Todos los oficiales de la hermandad con su rango (conectados con punto verde)
        local officerLines = {}
        local officers = N.GetOfficers()
        for _, o in ipairs(officers) do
            local short = string.match(o.name, "^([^-]+)") or o.name
            local dot = o.online and "|TInterface\COMMON\Indicator-Green:12:12|t " or "|TInterface\COMMON\Indicator-Gray:12:12|t "
            table.insert(officerLines, dot .. "|cFF" .. addonTable.GetClassColorHex(o.class) .. short .. "|r  |cFFBFBFBF" .. o.rank .. "|r")
        end
        officersBox.title:SetText("Oficiales (" .. #officers .. ")")
        officersText:SetText(#officerLines > 0 and table.concat(officerLines, "\n")
            or "|cFF808080No se han encontrado oficiales. El rango de oficial se ajusta en Mi perfil.|r")
        officersChild:SetHeight(math.max(1, officersText:GetStringHeight() + 4))
    end

    -- Noticias agrupadas por semana (cabecera "Esta semana", "Semana pasada", "Semana del...")
    local function RefreshFeed()
        for key, btn in pairs(filterButtons) do btn:SetEnabled(key ~= currentFilter) end
        for _, card in ipairs(cards) do card:Hide() end

        local feed = N.GetFeed(currentFilter)
        local index, y, lastWeek = 0, 0, nil
        for _, item in ipairs(feed) do
            local weekKey, weekLabel = N.GetWeek(item.sortKey)
            if weekKey ~= lastWeek then
                lastWeek = weekKey
                index = index + 1
                local header = AcquireCard(index)
                header:SetPoint("TOPLEFT", feedChild, "TOPLEFT", 0, -y)
                SetupCard(header, nil, weekLabel)
                y = y + 28
            end
            index = index + 1
            local card = AcquireCard(index)
            card:SetPoint("TOPLEFT", feedChild, "TOPLEFT", 0, -y)
            SetupCard(card, item)
            y = y + NEWS_CARD_HEIGHT
        end
        feedChild:SetHeight(math.max(1, y))
        emptyText:SetShown(#feed == 0)
        emptyText:SetText(IsInGuild() and "No hay noticias para este filtro todavía. Pulsa Actualizar para pedirlas al servidor."
            or "No estás en una hermandad.")
    end

    Refresh = function()
        if not view:IsShown() then return end
        RefreshFeed()
        RefreshSide()
    end

    N.AddListener(function() Refresh() end)
    view:SetScript("OnShow", function()
        N.Request()
        Refresh()
    end)
    uiModule.RefreshSummary = Refresh
    containers.views["Resumen"] = view
end

-- =========================================================================
-- 8f. VISTA BLACK LIST (CONSUME MODULES/BLACKLIST.LUA)
-- =========================================================================
local BLACKLIST_ROW_HEIGHT = 22

local function BuildBlacklistView(parent)
    local B = addonTable.Blacklist
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local Refresh
    local searchQuery = ""
    local selectedReason = "ninja"

    local title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", view, "TOPLEFT", 16, -12)
    title:SetText("Lista negra")

    local subtitle = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("LEFT", title, "RIGHT", 14, 0)
    subtitle:SetText("Personajes no deseados: avisa si entran en la hermandad o en tu grupo, los marca en su tooltip y bloquea invitarlos.")

    -- ---------------------------------------------------------------------
    -- Formulario para añadir
    -- ---------------------------------------------------------------------
    local form = CreateBackdropBox(view, 880, 64, "TOPLEFT", view, "TOPLEFT", 10, -36)

    local nameLabel = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameLabel:SetPoint("TOPLEFT", form, "TOPLEFT", 14, -10)
    nameLabel:SetText("Personaje (Nombre o Nombre-Reino)")
    local nameInput = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    nameInput:SetSize(180, 20)
    nameInput:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -4)
    nameInput:SetAutoFocus(false)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local btnTarget = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    btnTarget:SetSize(90, 22)
    btnTarget:SetPoint("LEFT", nameInput, "RIGHT", 8, 0)
    btnTarget:SetText("Objetivo")
    btnTarget:SetScript("OnClick", function()
        if UnitIsPlayer("target") then
            local name, realm = UnitName("target")
            nameInput:SetText((realm and realm ~= "") and (name .. "-" .. realm) or name)
        else
            PrintGC("No tienes a ningún jugador como objetivo.")
        end
    end)

    local reasonLabel = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reasonLabel:SetPoint("TOPLEFT", form, "TOPLEFT", 312, -10)
    reasonLabel:SetText("Motivo")
    local dropReason = CreateFrame("DropdownButton", "GC_BlacklistReason", form, "WowStyle1DropdownTemplate")
    dropReason:SetPoint("TOPLEFT", reasonLabel, "BOTTOMLEFT", 0, -2)
    dropReason:SetWidth(140)
    dropReason:SetupMenu(function(_, root)
        for _, reason in ipairs(B.REASONS) do
            local key = reason.key
            root:CreateRadio(reason.label, function() return selectedReason == key end,
                function() selectedReason = key; dropReason:SetText(reason.label) end)
        end
    end)
    dropReason:SetText(B.GetReasonLabel(selectedReason))

    local noteLabel = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    noteLabel:SetPoint("TOPLEFT", form, "TOPLEFT", 470, -10)
    noteLabel:SetText("Nota (qué pasó, cuándo...)")
    local noteInput = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    noteInput:SetSize(280, 20)
    noteInput:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 6, -4)
    noteInput:SetAutoFocus(false)
    noteInput:SetMaxLetters(120)
    noteInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local btnAdd = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    btnAdd:SetSize(90, 22)
    btnAdd:SetPoint("LEFT", noteInput, "RIGHT", 10, 0)
    btnAdd:SetText("Añadir")

    local function AddEntry()
        local entry, err = B.Add(nameInput:GetText(), selectedReason, noteInput:GetText())
        if not entry then
            PrintGC("|cFFFF3333" .. err .. "|r")
            return
        end
        PrintGC("|cFFFFD100" .. entry.name .. "|r añadido a la lista negra (" .. B.GetReasonLabel(entry.reason) .. ").")
        nameInput:SetText("")
        noteInput:SetText("")
        nameInput:ClearFocus()
        noteInput:ClearFocus()
    end
    btnAdd:SetScript("OnClick", AddEntry)
    nameInput:SetScript("OnEnterPressed", function() noteInput:SetFocus() end)
    noteInput:SetScript("OnEnterPressed", AddEntry)

    -- ---------------------------------------------------------------------
    -- Tabla
    -- ---------------------------------------------------------------------
    local COLS = {
        { title = "Personaje",   x = 8,   w = 180 },
        { title = "Motivo",      x = 192, w = 110 },
        { title = "Nota",        x = 306, w = 340 },
        { title = "Añadido por", x = 650, w = 110 },
        { title = "Fecha",       x = 764, w = 80 },
    }

    local listBox = CreateBackdropBox(view, 880, 370, "TOPLEFT", form, "BOTTOMLEFT", 0, -6)
    local headerRow = CreateFrame("Frame", nil, listBox)
    headerRow:SetSize(850, 18)
    headerRow:SetPoint("TOPLEFT", listBox, "TOPLEFT", 6, -8)
    for _, col in ipairs(COLS) do
        local fs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", headerRow, "LEFT", col.x, 0)
        fs:SetText(col.title)
    end

    local scroll = CreateFrame("ScrollFrame", "GC_BlacklistScroll", listBox, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -28, 8)
    local child = CreateFrame("Frame")
    child:SetSize(846, 1)
    scroll:SetScrollChild(child)

    local emptyText = listBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", listBox, "CENTER", 0, 0)
    emptyText:SetText("La lista negra está vacía.")

    local rows = {}
    local function AcquireRow(index)
        local row = rows[index]
        if row then return row end
        row = CreateFrame("Button", nil, child)
        row:SetSize(846, BLACKLIST_ROW_HEIGHT - 2)
        row:RegisterForClicks("RightButtonUp")
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.05)
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 0.2, 0.2, 0.12)
        row.cells = {}
        for i, col in ipairs(COLS) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
            fs:SetWidth(col.w - 4)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            row.cells[i] = fs
        end
        row:SetScript("OnEnter", function(self)
            local entry = self.entry
            if not entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetText(entry.name, 1, 0.2, 0.2)
            GameTooltip:AddDoubleLine("Motivo", B.GetReasonLabel(entry.reason), 0.7, 0.7, 0.7, 1, 1, 1)
            if entry.note and entry.note ~= "" then GameTooltip:AddLine(entry.note, 1, 1, 1, true) end
            GameTooltip:AddDoubleLine("Añadido por", entry.addedBy or "-", 0.7, 0.7, 0.7, 1, 1, 1)
            if entry.sharedBy then GameTooltip:AddDoubleLine("Compartido por", entry.sharedBy, 0.7, 0.7, 0.7, 1, 1, 1) end
            if GuildControlDB.members[entry.name] then GameTooltip:AddLine("¡Está en la hermandad!", 1, 0.2, 0.2) end
            GameTooltip:AddLine("Clic derecho: opciones", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            local entry = self.entry
            if not entry then return end
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(entry.name)
                root:CreateButton("Editar (cargar en el formulario)", function()
                    nameInput:SetText(entry.name)
                    noteInput:SetText(entry.note or "")
                    selectedReason = entry.reason
                    dropReason:SetText(B.GetReasonLabel(entry.reason))
                end)
                root:CreateButton("|cFFFF3333Quitar de la lista negra|r", function() B.Remove(entry.name) end)
            end)
        end)
        rows[index] = row
        return row
    end

    -- ---------------------------------------------------------------------
    -- Barra inferior: buscador, compartir y recuento
    -- ---------------------------------------------------------------------
    local bottom = CreateFrame("Frame", nil, view)
    bottom:SetSize(880, 24)
    bottom:SetPoint("TOPLEFT", listBox, "BOTTOMLEFT", 0, -6)

    local searchBox = CreateFrame("EditBox", nil, bottom, "InputBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("LEFT", bottom, "LEFT", 8, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
    searchPlaceholder:SetText("Buscar en la lista...")
    searchBox:SetScript("OnTextChanged", function(self)
        searchQuery = self:GetText() or ""
        searchPlaceholder:SetShown(searchQuery == "")
        Refresh()
    end)

    local btnShare = CreateFrame("Button", nil, bottom, "UIPanelButtonTemplate")
    btnShare:SetSize(170, 22)
    btnShare:SetPoint("LEFT", searchBox, "RIGHT", 12, 0)
    btnShare:SetText("Compartir con oficiales")
    btnShare:SetScript("OnClick", function()
        local count = B.Share()
        PrintGC(count > 0 and ("Enviando |cFFFFD100" .. count .. "|r entradas a los oficiales conectados con GuildControl.")
            or "No hay nada que compartir (o ya se está enviando).")
    end)
    btnShare:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Compartir con oficiales", 1, 1, 1)
        GameTooltip:AddLine("Los oficiales que la reciben añaden las entradas que no tenían. Nunca se borra nada de otro cliente.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnShare:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local countText = bottom:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("RIGHT", bottom, "RIGHT", -8, 0)

    Refresh = function()
        if not view:IsShown() then return end
        for _, row in ipairs(rows) do row:Hide() end
        local list = B.GetAll(searchQuery)
        for i, entry in ipairs(list) do
            local row = AcquireRow(i)
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * BLACKLIST_ROW_HEIGHT)
            row.bg:SetShown(i % 2 == 0)
            row.entry = entry
            local inGuild = GuildControlDB.members[entry.name] ~= nil
            local y, mo, d = string.match(entry.date or "", "^(%d+)-(%d+)-(%d+)$")
            row.cells[1]:SetText((inGuild and "|cFFFF3333" or "|cFFFFFFFF") .. entry.name .. "|r" .. (inGuild and " |cFFFF3333(en la hermandad)|r" or ""))
            row.cells[2]:SetText("|cFFFF7F7F" .. B.GetReasonLabel(entry.reason) .. "|r")
            row.cells[3]:SetText(entry.note or "")
            row.cells[4]:SetText(entry.addedBy or "-")
            row.cells[5]:SetText(y and (d .. "/" .. mo .. "/" .. y) or (entry.date or ""))
            row:Show()
        end
        child:SetHeight(math.max(1, #list * BLACKLIST_ROW_HEIGHT))
        emptyText:SetShown(#list == 0)
        local inGuild = B.CountInGuild()
        countText:SetText(#B.GetAll() .. " personajes en la lista"
            .. (inGuild > 0 and ("   ·   |cFFFF3333" .. inGuild .. " en la hermandad|r") or ""))
    end

    B.AddListener(function()
        Refresh()
        if uiModule.UpdateMemberCounter then uiModule.UpdateMemberCounter() end
    end)
    view:SetScript("OnShow", Refresh)
    containers.views["Black list"] = view
end

-- =========================================================================
-- 8g. VISTA WARNING (AVISOS POR CATEGORÍAS)
-- =========================================================================
-- Cada categoría devuelve { {name, data, detail, sort}, ... } (sort mayor = más grave).
local INACTIVE_OPTIONS = { 14, 30, 60, 90, 180, 365 }
local WARNING_ROW_HEIGHT = 22
local ACTIVE_DAYS = 14   -- "activo" = se ha conectado en las últimas 2 semanas

local function FormatOfflineDays(days)
    days = days or 0
    if days >= 365 then
        local years = math.floor(days / 365)
        return years .. (years == 1 and " año" or " años")
    elseif days >= 60 then
        return math.floor(days / 30) .. " meses"
    end
    return days .. " días"
end

local function WarningSettings()
    local s = GuildControlDB.settings
    s.inactiveDays = s.inactiveDays or 30
    s.lowAttendance = s.lowAttendance or 70
    s.starterInactiveDays = s.starterInactiveDays or 7
    s.reviewRaiderRank = s.reviewRaiderRank or 2
    s.reviewRecruitDays = s.reviewRecruitDays or 30
    s.noteRequired = s.noteRequired or ""
    return s
end

local function IsAlt(m) return m.declared and m.declared.charType == "alt" end
local function ShortOf(name) return string.match(name or "", "^([^-]+)") or name end

-- Fecha (time) del alta más reciente de cada miembro según el historial del addon
local function JoinTimes()
    local result = {}
    for _, log in ipairs(GuildControlDB.history or {}) do
        if log.action == "ALTA" and log.name and not result[log.name] then
            local y, mo, d = string.match(log.date or "", "^(%d+)-(%d+)-(%d+)")
            if y then result[log.name] = time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 }) end
        end
    end
    return result
end

-- Titulares de los rosters (base): { [nombre] = { "Roster 1", ... } }
local function RosterStarters()
    local result = {}
    local R = addonTable.Roster
    if not R then return result end
    for _, roster in ipairs(R.GetAll()) do
        for name, slot in pairs(roster.members) do
            if slot ~= "bench" then
                result[name] = result[name] or {}
                table.insert(result[name], roster)
            end
        end
    end
    return result
end

local WARNING_CATEGORIES = {
    {
        key = "inactive", label = "Inactivos",
        help = "Miembros que llevan mucho tiempo sin conectarse. Clic derecho: expulsar.",
        collect = function(s)
            local list = {}
            for name, m in pairs(GuildControlDB.members or {}) do
                if not m.isOnline and (m.offlineDays or 0) >= s.inactiveDays and (s.inactiveIncludeAlts ~= false or not IsAlt(m)) then
                    table.insert(list, { name = name, data = m, detail = "Sin conectarse: " .. FormatOfflineDays(m.offlineDays), sort = m.offlineDays or 0 })
                end
            end
            return list
        end,
    },
    {
        key = "norole", label = "Sin rol declarado",
        help = "Miembros activos (últimos " .. ACTIVE_DAYS .. " días) que no han declarado su rol en Mi perfil. Puedes enviarles un recordatorio.",
        collect = function()
            local list = {}
            for name, m in pairs(GuildControlDB.members or {}) do
                if not (m.declared and m.declared.main) and (m.isOnline or (m.offlineDays or 0) <= ACTIVE_DAYS) then
                    local detail = HasDefinedRole(m) and ("Rol puesto por un oficial: " .. m.role) or "Sin rol"
                    table.insert(list, { name = name, data = m, detail = detail, sort = m.isOnline and 1 or 0 })
                end
            end
            return list
        end,
    },
    {
        key = "orphanalts", label = "Alters sin principal",
        help = "Personajes que se declaran alter de alguien que no está en la hermandad.",
        collect = function()
            local shortNames = {}
            for name in pairs(GuildControlDB.members or {}) do shortNames[string.lower(ShortOf(name))] = true end
            local list = {}
            for name, m in pairs(GuildControlDB.members or {}) do
                if IsAlt(m) then
                    local mainName = m.declared.mainName
                    local found = mainName and (GuildControlDB.members[mainName] or shortNames[string.lower(ShortOf(mainName))])
                    if not found then
                        table.insert(list, { name = name, data = m, detail = "Dice ser alter de " .. (mainName or "(sin indicar)") .. ", que no está en la hermandad", sort = 0 })
                    end
                end
            end
            return list
        end,
    },
    {
        key = "lowattendance", label = "Baja asistencia",
        help = "Titulares de un roster con asistencia por debajo del umbral (con al menos 3 fechas registradas).",
        collect = function(s)
            local list = {}
            local R = addonTable.Roster
            for name, rosters in pairs(RosterStarters()) do
                local m = GuildControlDB.members[name]
                for _, roster in ipairs(rosters) do
                    local stats = R.GetAttendanceStats(roster, name)
                    if m and stats.percent and stats.counted >= 3 and stats.percent < s.lowAttendance then
                        table.insert(list, { name = name, data = m, sort = 100 - stats.percent,
                            detail = roster.name .. ": " .. stats.percent .. "% (" .. (stats.present + stats.late) .. " de " .. stats.counted .. " fechas)" })
                    end
                end
            end
            return list
        end,
    },
    {
        key = "inactivestarters", label = "Titulares inactivos",
        help = "Titulares de un roster que llevan días sin conectarse.",
        collect = function(s)
            local list = {}
            for name, rosters in pairs(RosterStarters()) do
                local m = GuildControlDB.members[name]
                if m and not m.isOnline and (m.offlineDays or 0) >= s.starterInactiveDays then
                    local names = {}
                    for _, roster in ipairs(rosters) do table.insert(names, roster.name) end
                    table.insert(list, { name = name, data = m, sort = m.offlineDays or 0,
                        detail = table.concat(names, ", ") .. " · sin conectarse: " .. FormatOfflineDays(m.offlineDays) })
                end
            end
            return list
        end,
    },
    {
        key = "ranks", label = "Rangos a revisar",
        help = "Nivel bajo en un rango de raider o superior, y reclutas que llevan tiempo en la hermandad (posible ascenso).",
        collect = function(s)
            local list = {}
            local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or nil
            local numRanks = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
            local lowestRank = numRanks > 0 and (numRanks - 1) or nil
            local joins = JoinTimes()
            for name, m in pairs(GuildControlDB.members or {}) do
                if maxLevel and m.rankIndex and m.rankIndex <= s.reviewRaiderRank and (tonumber(m.level) or 0) < maxLevel then
                    table.insert(list, { name = name, data = m, sort = maxLevel - (tonumber(m.level) or 0),
                        detail = "Nivel " .. (m.level or "?") .. " con rango " .. (m.rank or "?") .. " (por encima del rango de raider)" })
                elseif lowestRank and m.rankIndex == lowestRank and joins[name] then
                    local days = math.floor((time() - joins[name]) / 86400)
                    if days >= s.reviewRecruitDays and (m.isOnline or (m.offlineDays or 0) <= ACTIVE_DAYS) then
                        table.insert(list, { name = name, data = m, sort = days,
                            detail = days .. " días en la hermandad con rango " .. (m.rank or "?") .. ": revisar ascenso" })
                    end
                end
            end
            return list
        end,
    },
    {
        key = "notes", label = "Nota pública",
        help = "Notas públicas vacías o que no contienen el texto obligatorio configurado.",
        collect = function(s)
            local list = {}
            local required = string.lower(strtrim(s.noteRequired or ""))
            for name, m in pairs(GuildControlDB.members or {}) do
                local note = strtrim(m.publicNote or "")
                if note == "" then
                    table.insert(list, { name = name, data = m, detail = "Nota pública vacía", sort = 1 })
                elseif required ~= "" and not string.find(string.lower(note), required, 1, true) then
                    table.insert(list, { name = name, data = m, detail = "Nota sin \"" .. s.noteRequired .. "\": " .. note, sort = 0 })
                end
            end
            return list
        end,
    },
    {
        key = "blacklist", label = "Lista negra",
        help = "Miembros de la hermandad que están en la lista negra.",
        collect = function()
            local list = {}
            local B = addonTable.Blacklist
            for name, m in pairs(GuildControlDB.members or {}) do
                local entry = B and B.Get(name)
                if entry then
                    table.insert(list, { name = name, data = m, sort = 0,
                        detail = B.GetReasonLabel(entry.reason) .. ((entry.note and entry.note ~= "") and (": " .. entry.note) or "") })
                end
            end
            return list
        end,
    },
}

local function CollectCategory(category)
    local list = category.collect(WarningSettings())
    table.sort(list, function(a, b)
        if a.sort ~= b.sort then return a.sort > b.sort end
        return a.name < b.name
    end)
    return list
end

-- Total de avisos para la caja "Warnings" del encabezado: inactivos + lista negra
function uiModule.CountWarnings()
    local total = 0
    for _, category in ipairs(WARNING_CATEGORIES) do
        if category.key == "inactive" or category.key == "blacklist" then total = total + #category.collect(WarningSettings()) end
    end
    return total
end

local function BuildWarningView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()
    local selectedKey = "inactive"
    local Refresh
    local currentList = {}

    -- Izquierda: categorías con su recuento
    local catBox = CreateBackdropBox(view, 200, 500, "TOPLEFT", view, "TOPLEFT", 10, -10)
    local catTitle = catBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    catTitle:SetPoint("TOPLEFT", catBox, "TOPLEFT", 12, -12)
    catTitle:SetText("Warnings")

    local catButtons = {}
    for i, category in ipairs(WARNING_CATEGORIES) do
        local btn = CreateFrame("Button", nil, catBox)
        btn:SetSize(184, 26)
        btn:SetPoint("TOPLEFT", catBox, "TOPLEFT", 8, -40 - (i - 1) * 30)
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(0.8, 0.2, 0.2, 0.35)
        btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.highlight:SetAllPoints()
        btn.highlight:SetColorTexture(1, 1, 1, 0.08)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        btn.text:SetPoint("LEFT", btn, "LEFT", 8, 0)
        btn.text:SetText(category.label)
        btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.count:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        btn:SetScript("OnClick", function()
            selectedKey = category.key
            Refresh()
        end)
        catButtons[category.key] = btn
    end

    -- Derecha: ayuda, ajustes de la categoría, tabla y acciones
    local right = CreateBackdropBox(view, 674, 500, "TOPLEFT", catBox, "TOPRIGHT", 6, 0)
    local helpText = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    helpText:SetPoint("TOPLEFT", right, "TOPLEFT", 14, -12)
    helpText:SetPoint("RIGHT", right, "RIGHT", -14, 0)
    helpText:SetJustifyH("LEFT")

    -- Fila de ajustes: cada categoría muestra los suyos
    local settingsRow = CreateFrame("Frame", nil, right)
    settingsRow:SetSize(646, 26)
    settingsRow:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -32)
    local controlsByKey = {}

    local function NumberControl(key, labelText, settingKey, minValue, maxValue, suffix)
        local holder = CreateFrame("Frame", nil, settingsRow)
        holder:SetAllPoints()
        local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", holder, "LEFT", 0, 0)
        label:SetText(labelText)
        local input = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
        input:SetSize(44, 20)
        input:SetPoint("LEFT", label, "RIGHT", 10, 0)
        input:SetAutoFocus(false)
        input:SetNumeric(true)
        input:SetMaxLetters(4)
        input:SetJustifyH("CENTER")
        local suffixText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        suffixText:SetPoint("LEFT", input, "RIGHT", 6, 0)
        suffixText:SetText(suffix or "")
        local function Save(self)
            local value = tonumber(self:GetText())
            if value then WarningSettings()[settingKey] = math.min(maxValue, math.max(minValue, value)) end
            self:SetText(tostring(WarningSettings()[settingKey]))
            self:ClearFocus()
            Refresh()
            if uiModule.UpdateMemberCounter then uiModule.UpdateMemberCounter() end
        end
        input:SetScript("OnEnterPressed", Save)
        input:SetScript("OnEditFocusLost", function(self) self:SetText(tostring(WarningSettings()[settingKey])) end)
        input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        holder.Load = function() input:SetText(tostring(WarningSettings()[settingKey])) end
        holder.input = input
        controlsByKey[key] = controlsByKey[key] or {}
        table.insert(controlsByKey[key], holder)
        return holder, input
    end

    -- Inactivos: antigüedad e inclusión de alters
    do
        local holder = CreateFrame("Frame", nil, settingsRow)
        holder:SetAllPoints()
        local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", holder, "LEFT", 0, 0)
        label:SetText("Sin conectarse desde hace al menos:")
        local drop = CreateFrame("DropdownButton", "GC_WarningDays", holder, "WowStyle1DropdownTemplate")
        drop:SetPoint("LEFT", label, "RIGHT", 10, 0)
        drop:SetWidth(110)
        drop:SetupMenu(function(_, root)
            for _, days in ipairs(INACTIVE_OPTIONS) do
                root:CreateRadio(FormatOfflineDays(days), function() return WarningSettings().inactiveDays == days end,
                    function()
                        WarningSettings().inactiveDays = days
                        Refresh()
                        if uiModule.UpdateMemberCounter then uiModule.UpdateMemberCounter() end
                    end)
            end
        end)
        local chkAlts = CreateFrame("CheckButton", "GC_WarningIncludeAlts", holder, "UICheckButtonTemplate")
        chkAlts:SetSize(24, 24)
        chkAlts:SetPoint("LEFT", drop, "RIGHT", 16, 0)
        _G[chkAlts:GetName() .. "Text"]:SetText("Incluir alters")
        chkAlts:SetScript("OnClick", function(self)
            WarningSettings().inactiveIncludeAlts = self:GetChecked() and true or false
            Refresh()
            if uiModule.UpdateMemberCounter then uiModule.UpdateMemberCounter() end
        end)
        holder.Load = function()
            drop:SetText(FormatOfflineDays(WarningSettings().inactiveDays))
            chkAlts:SetChecked(WarningSettings().inactiveIncludeAlts ~= false)
        end
        controlsByKey.inactive = { holder }
    end

    NumberControl("lowattendance", "Avisar por debajo de:", "lowAttendance", 1, 100, "% de asistencia")
    NumberControl("inactivestarters", "Titulares sin conectarse desde hace al menos:", "starterInactiveDays", 1, 365, "días")

    -- Rangos: rango de raider (dropdown) y días como recluta
    do
        local holder = CreateFrame("Frame", nil, settingsRow)
        holder:SetAllPoints()
        local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", holder, "LEFT", 0, 0)
        label:SetText("Rango de raider o superior:")
        local drop = CreateFrame("DropdownButton", "GC_WarningRaiderRank", holder, "WowStyle1DropdownTemplate")
        drop:SetPoint("LEFT", label, "RIGHT", 8, 0)
        drop:SetWidth(130)
        drop:SetupMenu(function(_, root)
            for _, rank in ipairs(addonTable.Profiles and addonTable.Profiles.GetGuildRanks() or {}) do
                local index = rank.index
                root:CreateRadio(rank.name, function() return WarningSettings().reviewRaiderRank == index end,
                    function() WarningSettings().reviewRaiderRank = index; Refresh() end)
            end
        end)
        local daysLabel = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        daysLabel:SetPoint("LEFT", drop, "RIGHT", 14, 0)
        daysLabel:SetText("Recluta desde hace:")
        local input = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
        input:SetSize(40, 20)
        input:SetPoint("LEFT", daysLabel, "RIGHT", 8, 0)
        input:SetAutoFocus(false)
        input:SetNumeric(true)
        input:SetMaxLetters(3)
        input:SetJustifyH("CENTER")
        input:SetScript("OnEnterPressed", function(self)
            local value = tonumber(self:GetText())
            if value then WarningSettings().reviewRecruitDays = math.max(1, value) end
            self:ClearFocus()
            Refresh()
        end)
        input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        local suffix = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        suffix:SetPoint("LEFT", input, "RIGHT", 6, 0)
        suffix:SetText("días")
        holder.Load = function()
            local s = WarningSettings()
            drop:SetText("Rango " .. s.reviewRaiderRank)
            for _, rank in ipairs(addonTable.Profiles and addonTable.Profiles.GetGuildRanks() or {}) do
                if rank.index == s.reviewRaiderRank then drop:SetText(rank.name) end
            end
            input:SetText(tostring(s.reviewRecruitDays))
        end
        controlsByKey.ranks = { holder }
    end

    -- Nota pública: texto obligatorio (opcional)
    do
        local holder = CreateFrame("Frame", nil, settingsRow)
        holder:SetAllPoints()
        local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", holder, "LEFT", 0, 0)
        label:SetText("La nota debe contener (opcional):")
        local input = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
        input:SetSize(160, 20)
        input:SetPoint("LEFT", label, "RIGHT", 10, 0)
        input:SetAutoFocus(false)
        input:SetMaxLetters(30)
        input:SetScript("OnEnterPressed", function(self)
            WarningSettings().noteRequired = strtrim(self:GetText() or "")
            self:ClearFocus()
            Refresh()
        end)
        input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        local hint = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("LEFT", input, "RIGHT", 10, 0)
        hint:SetText("Ej.: \"Main\" o \"ilvl\". Enter para aplicar.")
        holder.Load = function() input:SetText(WarningSettings().noteRequired or "") end
        controlsByKey.notes = { holder }
    end

    -- Tabla
    local COLS = {
        { title = "Personaje", x = 8,   w = 170 },
        { title = "Nivel",     x = 182, w = 40 },
        { title = "Rango",     x = 226, w = 90 },
        { title = "Detalle",   x = 320, w = 320 },
    }
    local headerRow = CreateFrame("Frame", nil, right)
    headerRow:SetSize(640, 18)
    headerRow:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -66)
    for _, col in ipairs(COLS) do
        local fs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", headerRow, "LEFT", col.x, 0)
        fs:SetText(col.title)
    end

    local scroll = CreateFrame("ScrollFrame", "GC_WarningScroll", right, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -28, 40)
    local child = CreateFrame("Frame")
    child:SetSize(636, 1)
    scroll:SetScrollChild(child)

    local emptyText = right:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", right, "CENTER", 0, 0)
    emptyText:SetText("Nada que revisar en esta categoría.")

    local rows = {}
    local function AcquireRow(index)
        local row = rows[index]
        if row then return row end
        row = CreateFrame("Button", nil, child)
        row:SetSize(636, WARNING_ROW_HEIGHT - 2)
        row:RegisterForClicks("RightButtonUp")
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.05)
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)
        row.cells = {}
        for i, col in ipairs(COLS) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
            fs:SetWidth(col.w - 4)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            row.cells[i] = fs
        end
        row:SetScript("OnEnter", function(self)
            if not self.detail then return end
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetText(self.fullName or "", 1, 0.82, 0)
            GameTooltip:AddLine(self.detail, 1, 1, 1, true)
            GameTooltip:AddLine("Clic derecho: opciones", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Clic derecho: susurrar, invitar al grupo y, en inactivos, expulsar (con confirmación)
        row:SetScript("OnClick", function(self)
            local name = self.fullName
            if not name then return end
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(name)
                root:CreateButton("Susurrar", function() WhisperTo(name) end)
                root:CreateButton("Invitar al grupo", function() InviteToGroup(name) end)
                if selectedKey == "inactive" and not (CanGuildRemove and not CanGuildRemove()) then
                    local kick = root:CreateButton("|cFFFF3333Expulsar de la hermandad...|r")
                    kick:CreateButton("Sí, expulsar a " .. name, function()
                        if C_GuildInfo and C_GuildInfo.RemoveFromGuild then
                            C_GuildInfo.RemoveFromGuild(name)
                        elseif GuildUninvite then
                            GuildUninvite(name)
                        end
                        PrintGC("Expulsando a |cFFFFD100" .. name .. "|r de la hermandad.")
                    end)
                end
            end)
        end)
        rows[index] = row
        return row
    end

    -- Acciones
    local btnExport = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
    btnExport:SetSize(120, 22)
    btnExport:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 12, 10)
    btnExport:SetText("Exportar CSV")
    btnExport:SetScript("OnClick", function()
        local lines = { "Personaje,Nivel,Rango,Detalle" }
        for _, entry in ipairs(currentList) do
            table.insert(lines, string.format("%s,%s,%s,%s", entry.name, tostring(entry.data.level or ""),
                entry.data.rank or "", (string.gsub(entry.detail or "", ",", " "))))
        end
        if addonTable.CSV and addonTable.CSV.ShowText then addonTable.CSV.ShowText(table.concat(lines, "\n")) end
    end)

    -- Recordatorio por susurro (solo en "Sin rol declarado", a los conectados)
    local reminderTicker = nil
    local btnRemind = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
    btnRemind:SetSize(230, 22)
    btnRemind:SetPoint("LEFT", btnExport, "RIGHT", 8, 0)
    btnRemind:SetText("Recordar a los conectados")
    btnRemind:SetScript("OnClick", function(self)
        if reminderTicker then return end
        local queue = {}
        local me = UnitName("player")
        for _, entry in ipairs(currentList) do
            if entry.data.isOnline and ShortOf(entry.name) ~= me then table.insert(queue, entry.name) end
        end
        if #queue == 0 then
            PrintGC("No hay nadie conectado sin rol declarado.")
            return
        end
        self:Disable()
        local total = #queue
        reminderTicker = C_Timer.NewTicker(0.5, function()
            local name = table.remove(queue, 1)
            if name then
                SendWhisper(name, "¡Hola " .. ShortOf(name) .. "! Cuando puedas, indica tu rol y especialización en GuildControl > Mi perfil. ¡Gracias!")
            end
            if #queue == 0 then
                reminderTicker:Cancel()
                reminderTicker = nil
                self:Enable()
                PrintGC("Recordatorios enviados: |cFFFFD100" .. total .. "|r.")
            end
        end)
    end)

    local countText = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -14, 15)

    Refresh = function()
        if not view:IsShown() then return end
        local selected
        for _, category in ipairs(WARNING_CATEGORIES) do
            local count = #category.collect(WarningSettings())
            local btn = catButtons[category.key]
            btn.count:SetText(count > 0 and ("|cFFFF7F7F" .. count .. "|r") or "|cFF808080 0|r")
            btn.bg:SetShown(category.key == selectedKey)
            if category.key == selectedKey then selected = category end
        end

        helpText:SetText(selected.help)
        for key, holders in pairs(controlsByKey) do
            for _, holder in ipairs(holders) do
                holder:SetShown(key == selectedKey)
                if key == selectedKey and holder.Load then holder.Load() end
            end
        end
        btnRemind:SetShown(selectedKey == "norole")

        for _, row in ipairs(rows) do row:Hide() end
        currentList = CollectCategory(selected)
        for i, entry in ipairs(currentList) do
            local m = entry.data
            local row = AcquireRow(i)
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * WARNING_ROW_HEIGHT)
            row.bg:SetShown(i % 2 == 0)
            row.fullName, row.detail = entry.name, entry.detail
            local dot = m.isOnline and " |TInterface\\COMMON\\Indicator-Green:10:10|t" or ""
            row.cells[1]:SetText("|cFF" .. addonTable.GetClassColorHex(m.class) .. entry.name .. "|r" .. dot)
            row.cells[2]:SetText(tostring(m.level or ""))
            row.cells[3]:SetText(m.rank or "")
            row.cells[4]:SetText(entry.detail or "")
            row:Show()
        end
        child:SetHeight(math.max(1, #currentList * WARNING_ROW_HEIGHT))
        emptyText:SetShown(#currentList == 0)
        countText:SetText("|cFFFFD100" .. #currentList .. "|r personajes")
    end

    view:SetScript("OnShow", Refresh)
    uiModule.RefreshWarnings = Refresh
    containers.views["Warning"] = view
end

-- =========================================================================
-- 8h. VISTA PROFESIONES (QUIÉN TIENE CADA PROFESIÓN Y CON QUÉ HABILIDAD)
-- =========================================================================
local PROF_ROW_HEIGHT = 22

-- "Alquimia 800" -> "Alquimia", 800 ; "Alquimia" -> "Alquimia", nil ; "Ninguna" -> nil
local function ParseProfession(text)
    if not text or text == "" or text == "Ninguna" then return nil end
    local name, skill = string.match(text, "^(.-)%s+(%d+)$")
    if name then return name, tonumber(skill) end
    return text, nil
end

-- { [profesión] = { {name, data, skill, other}, ... } } a partir de prof1/prof2 de cada miembro
local function CollectProfessions()
    local byProf = {}
    for fullName, m in pairs(GuildControlDB.members or {}) do
        local p1, s1 = ParseProfession(m.prof1)
        local p2, s2 = ParseProfession(m.prof2)
        if p1 then
            byProf[p1] = byProf[p1] or {}
            table.insert(byProf[p1], { name = fullName, data = m, skill = s1, other = m.prof2 })
        end
        if p2 and p2 ~= p1 then
            byProf[p2] = byProf[p2] or {}
            table.insert(byProf[p2], { name = fullName, data = m, skill = s2, other = m.prof1 })
        end
    end
    return byProf
end

local function BuildProfessionsView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local selectedProf = nil
    local searchQuery = ""
    local sortKey, sortAsc = "skill", false
    local Refresh

    -- Izquierda: profesiones con su recuento
    local listBox = CreateBackdropBox(view, 200, 500, "TOPLEFT", view, "TOPLEFT", 10, -10)
    local listTitle = listBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listTitle:SetPoint("TOPLEFT", listBox, "TOPLEFT", 12, -10)
    listTitle:SetText("Profesiones")

    local profButtons = {}
    local function AcquireProfButton(index)
        local btn = profButtons[index]
        if btn then return btn end
        btn = CreateFrame("Button", nil, listBox)
        btn:SetSize(184, 22)
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(0.2, 0.4, 0.8, 0.35)
        btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.highlight:SetAllPoints()
        btn.highlight:SetColorTexture(1, 1, 1, 0.08)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        btn.text:SetPoint("LEFT", btn, "LEFT", 8, 0)
        btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        btn.count:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        btn:SetScript("OnClick", function(self)
            selectedProf = self.prof
            Refresh()
        end)
        profButtons[index] = btn
        return btn
    end

    -- Derecha: buscador, filtros y tabla
    local right = CreateBackdropBox(view, 674, 500, "TOPLEFT", listBox, "TOPRIGHT", 6, 0)

    local searchBox = CreateFrame("EditBox", nil, right, "InputBoxTemplate")
    searchBox:SetSize(220, 20)
    searchBox:SetPoint("TOPLEFT", right, "TOPLEFT", 16, -12)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
    searchPlaceholder:SetText("Buscar miembro...")
    searchBox:SetScript("OnTextChanged", function(self)
        searchQuery = string.lower(strtrim(self:GetText() or ""))
        searchPlaceholder:SetShown((self:GetText() or "") == "")
        Refresh()
    end)

    local chkOnline = CreateFrame("CheckButton", "GC_ProfsOnlyOnline", right, "UICheckButtonTemplate")
    chkOnline:SetSize(24, 24)
    chkOnline:SetPoint("LEFT", searchBox, "RIGHT", 14, 0)
    _G[chkOnline:GetName() .. "Text"]:SetText("Solo conectados")
    chkOnline:SetScript("OnClick", function() Refresh() end)

    local countText = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("TOPRIGHT", right, "TOPRIGHT", -16, -16)

    local COLS = {
        { title = "Nombre",          x = 8,   w = 220, key = "name" },
        { title = "Habilidad",       x = 232, w = 80,  key = "skill" },
        { title = "Otra profesión",  x = 316, w = 170, key = "other" },
        { title = "Conexión",        x = 490, w = 140, key = "online" },
    }

    local headerRow = CreateFrame("Frame", nil, right)
    headerRow:SetSize(640, 20)
    headerRow:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -44)
    local headerButtons = {}
    for _, col in ipairs(COLS) do
        local hb = CreateFrame("Button", nil, headerRow)
        hb:SetPoint("LEFT", headerRow, "LEFT", col.x, 0)
        hb:SetSize(col.w, 20)
        hb.text = hb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hb.text:SetPoint("LEFT", hb, "LEFT", 0, 0)
        hb.key, hb.title = col.key, col.title
        hb:SetScript("OnClick", function(self)
            if sortKey == self.key then sortAsc = not sortAsc else sortKey, sortAsc = self.key, self.key ~= "skill" end
            Refresh()
        end)
        table.insert(headerButtons, hb)
    end

    local scroll = CreateFrame("ScrollFrame", "GC_ProfsScroll", right, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -28, 22)
    local child = CreateFrame("Frame")
    child:SetSize(636, 1)
    scroll:SetScrollChild(child)

    local emptyText = right:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", right, "CENTER", 0, 0)
    emptyText:SetWidth(560)
    emptyText:SetText("Todavía no hay profesiones registradas. Se rellenan al escanear la hermandad.")

    local rowHint = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rowHint:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 14, 2)
    rowHint:SetText("Clic en un miembro: susurrar o invitar al grupo")

    local rows = {}
    local function AcquireRow(index)
        local row = rows[index]
        if row then return row end
        row = CreateFrame("Button", nil, child)
        row:SetSize(636, PROF_ROW_HEIGHT - 2)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)
        -- Clic: susurrar o invitar al grupo (mismo menú que en Miembros)
        row:SetScript("OnClick", function(self)
            if self.fullName then ShowPlayerMenu(self, self.fullName) end
        end)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.05)
        row.cells = {}
        for i, col in ipairs(COLS) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
            fs:SetWidth(col.w - 4)
            fs:SetJustifyH(col.key == "skill" and "RIGHT" or "LEFT")
            fs:SetWordWrap(false)
            row.cells[i] = fs
        end
        rows[index] = row
        return row
    end

    local function SortValue(entry, key)
        if key == "skill" then return entry.skill or -1 end
        if key == "online" then return entry.data.isOnline and -1 or (entry.data.offlineDays or 0) end
        if key == "other" then return string.lower(entry.other or "~") end
        return string.lower(entry.name)
    end

    Refresh = function()
        if not view:IsShown() then return end
        local byProf = CollectProfessions()
        local profNames = {}
        for prof in pairs(byProf) do table.insert(profNames, prof) end
        table.sort(profNames)
        if not selectedProf or not byProf[selectedProf] then selectedProf = profNames[1] end

        for _, btn in ipairs(profButtons) do btn:Hide() end
        for i, prof in ipairs(profNames) do
            local btn = AcquireProfButton(i)
            btn:SetPoint("TOPLEFT", listBox, "TOPLEFT", 8, -32 - (i - 1) * 24)
            btn.prof = prof
            btn.text:SetText(prof)
            btn.count:SetText(#byProf[prof])
            btn.bg:SetShown(prof == selectedProf)
            btn:Show()
        end

        for _, hb in ipairs(headerButtons) do
            local arrow = (hb.key == sortKey) and (sortAsc and " ^" or " v") or ""
            hb.text:SetText((hb.key == sortKey and "|cFFFFFFFF" or "") .. hb.title .. arrow .. (hb.key == sortKey and "|r" or ""))
        end

        for _, row in ipairs(rows) do row:Hide() end
        local list = {}
        for _, entry in ipairs(selectedProf and byProf[selectedProf] or {}) do
            local pass = (not chkOnline:GetChecked() or entry.data.isOnline)
                and (searchQuery == "" or string.find(string.lower(entry.name), searchQuery, 1, true))
            if pass then table.insert(list, entry) end
        end
        table.sort(list, function(a, b)
            local va, vb = SortValue(a, sortKey), SortValue(b, sortKey)
            if va ~= vb then
                if sortAsc then return va < vb end
                return va > vb
            end
            return a.name < b.name
        end)

        for i, entry in ipairs(list) do
            local m = entry.data
            local row = AcquireRow(i)
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * PROF_ROW_HEIGHT)
            row.bg:SetShown(i % 2 == 0)
            local dot = m.isOnline and " |TInterface\\COMMON\\Indicator-Green:10:10|t" or ""
            row.fullName = entry.name
            row.cells[1]:SetText("|cFF" .. addonTable.GetClassColorHex(m.class) .. entry.name .. "|r" .. dot)
            row.cells[2]:SetText(entry.skill and tostring(entry.skill) or "|cFF808080-|r")
            local other = entry.other
            row.cells[3]:SetText((other and other ~= "Ninguna") and other or "")
            row.cells[4]:SetText(m.isOnline and "|cFF00FF00En línea|r" or ("|cFF808080" .. (m.lastOnline or "") .. "|r"))
            row:Show()
        end
        child:SetHeight(math.max(1, #list * PROF_ROW_HEIGHT))
        emptyText:SetShown(#profNames == 0)
        countText:SetText(selectedProf and ("|cFFFFD100" .. #list .. "|r miembros con " .. selectedProf) or "")
    end

    view:SetScript("OnShow", Refresh)
    containers.views["Profesiones"] = view
end

-- =========================================================================
-- 8i. VISTA MÍTICAS+ (CONSUME MODULES/MYTHICPLUS.LUA)
-- =========================================================================
local MPLUS_ROW_HEIGHT = 22

local function BuildMythicPlusView(parent)
    local M = addonTable.MythicPlus
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local searchQuery = ""
    local Refresh

    -- Izquierda: clasificación de la hermandad por puntuación M+
    local listBox = CreateBackdropBox(view, 566, 500, "TOPLEFT", view, "TOPLEFT", 10, -10)
    local listTitle = listBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    listTitle:SetPoint("TOPLEFT", listBox, "TOPLEFT", 14, -12)
    listTitle:SetText("Puntuación Mítica+ de la hermandad")

    local searchBox = CreateFrame("EditBox", nil, listBox, "InputBoxTemplate")
    searchBox:SetSize(170, 20)
    searchBox:SetPoint("TOPLEFT", listTitle, "BOTTOMLEFT", 6, -10)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
    searchPlaceholder:SetText("Buscar miembro...")
    searchBox:SetScript("OnTextChanged", function(self)
        searchQuery = string.lower(strtrim(self:GetText() or ""))
        searchPlaceholder:SetShown((self:GetText() or "") == "")
        Refresh()
    end)

    local chkOnline = CreateFrame("CheckButton", "GC_MPlusOnlyOnline", listBox, "UICheckButtonTemplate")
    chkOnline:SetSize(24, 24)
    chkOnline:SetPoint("LEFT", searchBox, "RIGHT", 12, 0)
    _G[chkOnline:GetName() .. "Text"]:SetText("Conectados")
    chkOnline:SetScript("OnClick", function() Refresh() end)

    local chkKeys = CreateFrame("CheckButton", "GC_MPlusOnlyKeys", listBox, "UICheckButtonTemplate")
    chkKeys:SetSize(24, 24)
    chkKeys:SetPoint("LEFT", chkOnline, "RIGHT", 90, 0)
    _G[chkKeys:GetName() .. "Text"]:SetText("Con llave")
    chkKeys:SetScript("OnClick", function() Refresh() end)

    local COLS = {
        { title = "#",          x = 6,   w = 26 },
        { title = "Nombre",     x = 34,  w = 170 },
        { title = "Rol",        x = 206, w = 70 },
        { title = "Puntuación", x = 278, w = 80 },
        { title = "Llave",      x = 362, w = 160 },
    }
    local headerRow = CreateFrame("Frame", nil, listBox)
    headerRow:SetSize(530, 18)
    headerRow:SetPoint("TOPLEFT", listBox, "TOPLEFT", 8, -70)
    for _, col in ipairs(COLS) do
        local fs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", headerRow, "LEFT", col.x, 0)
        fs:SetText(col.title)
    end

    local scroll = CreateFrame("ScrollFrame", "GC_MPlusScroll", listBox, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -28, 26)
    local child = CreateFrame("Frame")
    child:SetSize(526, 1)
    scroll:SetScrollChild(child)

    local listHint = listBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listHint:SetPoint("BOTTOMLEFT", listBox, "BOTTOMLEFT", 12, 8)
    listHint:SetText("La puntuación sale de la lista de la hermandad del juego; las llaves, de quien usa GuildControl.")

    local rows = {}
    local function AcquireRow(index)
        local row = rows[index]
        if row then return row end
        row = CreateFrame("Frame", nil, child)
        row:SetSize(526, MPLUS_ROW_HEIGHT - 2)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.05)
        row.cells = {}
        for i, col in ipairs(COLS) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
            fs:SetWidth(col.w - 4)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            row.cells[i] = fs
        end
        rows[index] = row
        return row
    end

    -- Derecha: afijos, mi llave y mis mejores mazmorras
    local function SideBox(titleText, height, anchor)
        local box = CreateBackdropBox(view, 304, height)
        if anchor then box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6) else box:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 8, 0) end
        box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
        box.title:SetText(titleText)
        box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        box.text:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -6)
        box.text:SetPoint("RIGHT", box, "RIGHT", -12, 0)
        box.text:SetJustifyH("LEFT")
        box.text:SetJustifyV("TOP")
        box.text:SetSpacing(4)
        return box
    end
    local affixBox = SideBox("Afijos de la semana", 116)
    local keyBox = SideBox("Tu llave y tu puntuación", 76, affixBox)
    local bestBox = SideBox("Tus mejores mazmorras de la temporada", 296, keyBox)

    local btnRequest = CreateFrame("Button", nil, keyBox, "UIPanelButtonTemplate")
    btnRequest:SetSize(110, 20)
    btnRequest:SetPoint("TOPRIGHT", keyBox, "TOPRIGHT", -8, -6)
    btnRequest:SetText("Pedir llaves")
    btnRequest:SetScript("OnClick", function()
        M.BroadcastKeystone(true)
        M.RequestKeystones()
        PrintGC("Pidiendo las llaves a los miembros conectados con GuildControl...")
    end)

    local function KeystoneText(keystone)
        if not keystone then return "" end
        local name = M.GetMapName(keystone.mapID) or ("Mazmorra " .. keystone.mapID)
        return "|cFFA335EE+" .. keystone.level .. "|r " .. name
    end

    local function RefreshSide()
        local affixLines = {}
        for _, affix in ipairs(M.GetAffixes()) do
            table.insert(affixLines, (affix.icon and ("|T" .. affix.icon .. ":16:16|t ") or "") .. "|cFFFFD100" .. affix.name .. "|r")
        end
        affixBox.text:SetText(#affixLines > 0 and table.concat(affixLines, "\n") or "|cFF808080Sin datos de afijos todavía.|r")

        local mapID, level = M.GetMyKeystone()
        local myScore = M.GetMyScore()
        keyBox.text:SetText((mapID and ("Llave: " .. KeystoneText({ mapID = mapID, level = level })) or "|cFF808080No tienes llave.|r")
            .. "\nPuntuación: |cFF" .. M.ScoreColorHex(myScore) .. myScore .. "|r")

        local bestLines = {}
        for _, run in ipairs(M.GetMyBestRuns()) do
            if run.level > 0 then
                local timeColor = run.inTime and "00FF00" or "FF7F00"
                table.insert(bestLines, "|cFF" .. timeColor .. "+" .. run.level .. "|r  " .. run.name
                    .. "  |cFF" .. M.ScoreColorHex(run.score * 8) .. math.floor(run.score) .. "|r")
            else
                table.insert(bestLines, "|cFF808080-  " .. run.name .. "|r")
            end
        end
        bestBox.text:SetText(#bestLines > 0 and table.concat(bestLines, "\n") or "|cFF808080Sin datos de la temporada todavía.|r")
    end

    Refresh = function()
        if not view:IsShown() then return end
        for _, row in ipairs(rows) do row:Hide() end
        local list = {}
        for fullName, m in pairs(GuildControlDB.members or {}) do
            local pass = (not chkOnline:GetChecked() or m.isOnline)
                and (not chkKeys:GetChecked() or m.keystone ~= nil)
                and (searchQuery == "" or string.find(string.lower(fullName), searchQuery, 1, true))
                and ((m.mplusScore or 0) > 0 or m.keystone ~= nil)
            if pass then table.insert(list, { name = fullName, data = m }) end
        end
        table.sort(list, function(a, b)
            local sa, sb = a.data.mplusScore or 0, b.data.mplusScore or 0
            if sa ~= sb then return sa > sb end
            return a.name < b.name
        end)

        for i, entry in ipairs(list) do
            local m = entry.data
            local row = AcquireRow(i)
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * MPLUS_ROW_HEIGHT)
            row.bg:SetShown(i % 2 == 0)
            local dot = m.isOnline and " |TInterface\\COMMON\\Indicator-Green:10:10|t" or ""
            local score = m.mplusScore or 0
            row.cells[1]:SetText("|cFF808080" .. i .. "|r")
            row.cells[2]:SetText("|cFF" .. addonTable.GetClassColorHex(m.class) .. (string.match(entry.name, "^([^-]+)") or entry.name) .. "|r" .. dot)
            row.cells[3]:SetText(HasDefinedRole(m) and (RoleIcon(m.role, 12) .. " " .. m.role) or "")
            row.cells[4]:SetText("|cFF" .. M.ScoreColorHex(score) .. score .. "|r")
            row.cells[5]:SetText(KeystoneText(m.keystone))
            row:Show()
        end
        child:SetHeight(math.max(1, #list * MPLUS_ROW_HEIGHT))
        RefreshSide()
    end

    M.AddListener(function() Refresh() end)
    view:SetScript("OnShow", function()
        M.RequestData()
        M.UpdateScores()
        Refresh()
    end)
    containers.views["Míticas+"] = view
end

-- =========================================================================
-- 9. VISTA DE CONFIGURACIÓN (NOMBRE E ICONO DE LA HERMANDAD)
-- =========================================================================
local DEFAULT_GUILD_ICON = "Interface\\Icons\\Achievement_GuildPerk_MobileBanking"

local PRESET_ICONS = {
    "Achievement_GuildPerk_MobileBanking", "Achievement_GuildPerk_EverybodysFriend", "Ability_Hunter_Pet_Wolf",
    "INV_BannerPVP_01", "INV_BannerPVP_02", "Ability_Warrior_BattleShout", "INV_Sword_04", "INV_Shield_06",
    "Spell_Holy_PowerWordShield", "Spell_Nature_HealingTouch", "Spell_Fire_Fire", "Spell_Frost_FrostBolt02",
    "Spell_Shadow_ShadowBolt", "INV_Misc_Head_Dragon_01", "INV_Misc_Coin_01", "INV_Misc_QuestionMark",
}

local function BuildConfigView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()
    local settings = function() return GuildControlDB.settings end

    local title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", view, "TOPLEFT", 16, -12)
    title:SetText("Configuración")

    -- Cada sección es una caja con su título
    local function Section(titleText, x, y, width, height)
        local box = CreateBackdropBox(view, width, height, "TOPLEFT", view, "TOPLEFT", x, y)
        box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
        box.title:SetText(titleText)
        return box
    end

    local function Label(parentBox, text, x, y)
        local fs = parentBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", parentBox, "TOPLEFT", x, y)
        fs:SetText(text)
        return fs
    end

    local function Input(parentBox, width, anchor, placeholderText, maxLetters)
        local input = CreateFrame("EditBox", nil, parentBox, "InputBoxTemplate")
        input:SetSize(width, 20)
        input:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 6, -4)
        input:SetAutoFocus(false)
        if maxLetters then input:SetMaxLetters(maxLetters) end
        if placeholderText then
            local placeholder = input:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            placeholder:SetPoint("LEFT", input, "LEFT", 2, 0)
            placeholder:SetText(placeholderText)
            input:HookScript("OnTextChanged", function(self) placeholder:SetShown((self:GetText() or "") == "") end)
        end
        return input
    end

    local function Button(parentBox, text, width, anchor, onClick)
        local btn = CreateFrame("Button", nil, parentBox, "UIPanelButtonTemplate")
        btn:SetSize(width, 22)
        btn:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
        btn:SetText(text)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    -- ---------------------------------------------------------------------
    -- 9.1 Hermandad: nombre, Discord e icono
    -- ---------------------------------------------------------------------
    local guildBox = Section("Hermandad", 10, -36, 560, 236)

    local nameLabel = Label(guildBox, "Nombre (vacío = el nombre real de la hermandad)", 14, -32)
    local nameInput = Input(guildBox, 230, nameLabel, nil, 48)

    local function SaveName()
        settings().guildName = strtrim(nameInput:GetText() or "")
        nameInput:ClearFocus()
        uiModule.UpdateHeader()
    end
    local btnSaveName = Button(guildBox, "Guardar", 80, nameInput, SaveName)
    Button(guildBox, "Usar nombre del juego", 150, btnSaveName, function()
        nameInput:SetText("")
        SaveName()
    end)
    nameInput:SetScript("OnEnterPressed", SaveName)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:SetText(settings().guildName or "") end)

    local discordLabel = Label(guildBox, "Enlace de Discord (se muestra un botón junto al nombre)", 14, -84)
    local discordInput = Input(guildBox, 300, discordLabel, "https://discord.gg/...", 120)

    local function SaveDiscord()
        settings().discordLink = strtrim(discordInput:GetText() or "")
        discordInput:ClearFocus()
        uiModule.UpdateHeader()
    end
    local btnSaveDiscord = Button(guildBox, "Guardar", 80, discordInput, SaveDiscord)
    Button(guildBox, "Quitar", 70, btnSaveDiscord, function()
        discordInput:SetText("")
        SaveDiscord()
    end)
    discordInput:SetScript("OnEnterPressed", SaveDiscord)
    discordInput:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:SetText(settings().discordLink or "") end)

    local iconLabel = Label(guildBox, "Icono: nombre (INV_Misc_QuestionMark), ID numérico o ruta, o elige uno", 14, -136)
    local iconPreview = guildBox:CreateTexture(nil, "ARTWORK")
    iconPreview:SetSize(32, 32)
    iconPreview:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 0, -4)

    local iconInput = CreateFrame("EditBox", nil, guildBox, "InputBoxTemplate")
    iconInput:SetSize(230, 20)
    iconInput:SetPoint("LEFT", iconPreview, "RIGHT", 12, 0)
    iconInput:SetAutoFocus(false)

    local function RefreshIconFields()
        iconInput:SetText(tostring(settings().guildIcon or ""))
        iconPreview:SetTexture(addonTable.ResolveIconTexture(settings().guildIcon))
    end

    local function SaveIcon(value)
        value = strtrim(value or "")
        if value == "" then value = DEFAULT_GUILD_ICON end
        settings().guildIcon = tonumber(value) or value
        iconInput:ClearFocus()
        uiModule.UpdateHeader()
        RefreshIconFields()
    end

    local btnApplyIcon = Button(guildBox, "Aplicar", 80, iconInput, function() SaveIcon(iconInput:GetText()) end)
    Button(guildBox, "Restablecer", 100, btnApplyIcon, function() SaveIcon(DEFAULT_GUILD_ICON) end)
    iconInput:SetScript("OnEnterPressed", function(self) SaveIcon(self:GetText()) end)
    iconInput:SetScript("OnEscapePressed", function(self) self:ClearFocus(); RefreshIconFields() end)
    iconInput:SetScript("OnTextChanged", function(self, userInput)
        if userInput then iconPreview:SetTexture(addonTable.ResolveIconTexture(strtrim(self:GetText() or ""))) end
    end)

    -- Iconos predefinidos en una fila
    for i, iconName in ipairs(PRESET_ICONS) do
        local btn = CreateFrame("Button", nil, guildBox)
        btn:SetSize(28, 28)
        btn:SetPoint("TOPLEFT", iconPreview, "BOTTOMLEFT", (i - 1) * 33, -8)
        btn:SetNormalTexture("Interface\\Icons\\" .. iconName)
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        btn:SetScript("OnClick", function() SaveIcon("Interface\\Icons\\" .. iconName) end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(iconName, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- ---------------------------------------------------------------------
    -- 9.2 Ventana
    -- ---------------------------------------------------------------------
    local windowBox = Section("Ventana", 578, -36, 312, 236)

    local chkOnTop = CreateFrame("CheckButton", "GC_CfgWindowOnTop", windowBox, "UICheckButtonTemplate")
    chkOnTop:SetPoint("TOPLEFT", windowBox, "TOPLEFT", 10, -30)
    _G[chkOnTop:GetName() .. "Text"]:SetText("Siempre por encima")
    chkOnTop:SetScript("OnClick", function(self)
        settings().windowOnTop = self:GetChecked() and true or false
        uiModule.ApplyWindowStrata()
    end)

    local onTopHint = windowBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    onTopHint:SetPoint("TOPLEFT", chkOnTop, "BOTTOMLEFT", 4, -2)
    onTopHint:SetWidth(284)
    onTopHint:SetJustifyH("LEFT")
    onTopHint:SetText("Muestra la ventana del addon por encima de las barras de acción y otros botones del juego.")

    local aboutText = windowBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    aboutText:SetPoint("BOTTOMLEFT", windowBox, "BOTTOMLEFT", 14, 12)
    aboutText:SetWidth(284)
    aboutText:SetJustifyH("LEFT")
    aboutText:SetText("GuildControl v4.5.0 · Autor: Forxaken · Guild: Lobo Gélido\nEl perfil de oficial y el rango mínimo se configuran en Mi perfil.")

    -- ---------------------------------------------------------------------
    -- 9.3 Saludo automático: mensaje, tiempos y palabras
    -- ---------------------------------------------------------------------
    local greetBox = Section("Saludo automático", 10, -278, 880, 228)

    local chkGreet = CreateFrame("CheckButton", "GC_CfgAutoGreet", greetBox, "UICheckButtonTemplate")
    chkGreet:SetPoint("TOPLEFT", greetBox, "TOPLEFT", 10, -28)
    _G[chkGreet:GetName() .. "Text"]:SetText("Responder a quien salude al conectarse")
    chkGreet:SetScript("OnClick", function(self) settings().autoGreet = self:GetChecked() and true or false end)

    local greetLabel = Label(greetBox, "Mensaje de respuesta", 14, -66)
    local greetInput = Input(greetBox, 220, greetLabel, nil, 120)

    local function SaveGreet()
        local text = strtrim(greetInput:GetText() or "")
        if text == "" then text = "¡Hola, {nombre}!" end
        settings().greetMessage = text
        greetInput:SetText(text)
        greetInput:ClearFocus()
    end
    Button(greetBox, "Guardar", 70, greetInput, SaveGreet)
    greetInput:SetScript("OnEnterPressed", SaveGreet)
    greetInput:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:SetText(settings().greetMessage or "") end)

    local greetHint = greetBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    greetHint:SetPoint("TOPLEFT", greetInput, "BOTTOMLEFT", -6, -8)
    greetHint:SetWidth(300)
    greetHint:SetJustifyH("LEFT")
    greetHint:SetText("{nombre} se sustituye por quien saluda. Solo se responde a quien acaba de conectarse y aún no ha sido saludado.")

    -- Columna central: tiempos
    local timesTitle = Label(greetBox, "|cFFFFD100Tiempos|r", 350, -32)

    local function NumberSetting(anchor, xOffset, yOffset, labelText, key, minValue, maxValue)
        local input = CreateFrame("EditBox", nil, greetBox, "InputBoxTemplate")
        input:SetSize(40, 20)
        input:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", xOffset, yOffset)
        input:SetAutoFocus(false)
        input:SetNumeric(true)
        input:SetMaxLetters(4)
        input:SetJustifyH("CENTER")
        local text = greetBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", input, "RIGHT", 8, 0)
        text:SetWidth(200)
        text:SetJustifyH("LEFT")
        text:SetText(labelText)
        input:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            local value = tonumber(self:GetText())
            if value then settings()[key] = math.min(maxValue, math.max(minValue, value)) end
        end)
        input:SetScript("OnEditFocusLost", function(self) self:SetText(tostring(settings()[key])) end)
        input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return input
    end

    local delayInput = NumberSetting(timesTitle, 6, -10, "Segundos de espera antes de responder (1-60)", "greetDelay", 1, 60)
    local cooldownInput = NumberSetting(delayInput, 0, -16, "Minutos sin volver a saludar a la misma persona (1-1440)", "greetCooldown", 1, 1440)
    local loginInput = NumberSetting(cooldownInput, 0, -16, "Minutos tras conectarse en los que se le saluda (1-30)", "greetLoginWindow", 1, 30)

    local timesHint = greetBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    timesHint:SetPoint("TOPLEFT", loginInput, "BOTTOMLEFT", -6, -12)
    timesHint:SetWidth(250)
    timesHint:SetJustifyH("LEFT")
    timesHint:SetText("A la espera se suman hasta 4 s aleatorios para que, si varios usan GuildControl, solo responda uno.")

    -- Columna derecha: palabras de saludo
    local wordsTitle = Label(greetBox, "|cFFFFD100Palabras de saludo|r", 630, -32)
    local wordsBox = CreateBackdropBox(greetBox, 236, 110, "TOPLEFT", wordsTitle, "BOTTOMLEFT", 0, -6)
    local wordsInput = CreateFrame("EditBox", nil, wordsBox)
    wordsInput:SetPoint("TOPLEFT", wordsBox, "TOPLEFT", 6, -6)
    wordsInput:SetPoint("BOTTOMRIGHT", wordsBox, "BOTTOMRIGHT", -6, 6)
    wordsInput:SetMultiLine(true)
    wordsInput:SetFontObject(GameFontHighlightSmall)
    wordsInput:SetAutoFocus(false)
    wordsInput:SetMaxLetters(0)
    wordsInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    wordsInput:SetScript("OnTextChanged", function(self, userInput)
        if userInput then settings().greetWords = self:GetText() or "" end
    end)
    wordsBox:EnableMouse(true)
    wordsBox:SetScript("OnMouseDown", function() wordsInput:SetFocus() end)

    local wordsHint = greetBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    wordsHint:SetPoint("TOPLEFT", wordsBox, "BOTTOMLEFT", 0, -4)
    wordsHint:SetWidth(236)
    wordsHint:SetJustifyH("LEFT")
    wordsHint:SetText("Separadas por comas; el mensaje debe empezar por una. Vacío = lista por defecto.")

    view:SetScript("OnShow", function()
        local s = settings()
        nameInput:SetText(s.guildName or "")
        discordInput:SetText(s.discordLink or "")
        RefreshIconFields()
        chkOnTop:SetChecked(s.windowOnTop)
        chkGreet:SetChecked(s.autoGreet)
        greetInput:SetText(s.greetMessage or "")
        delayInput:SetText(tostring(s.greetDelay))
        cooldownInput:SetText(tostring(s.greetCooldown))
        loginInput:SetText(tostring(s.greetLoginWindow))
        local words = s.greetWords
        if not words or strtrim(words) == "" then
            words = addonTable.GuildChat and addonTable.GuildChat.DEFAULT_GREET_WORDS or ""
        end
        wordsInput:SetText(words)
    end)
    containers.views["Configuracion"] = view
end

-- =========================================================================
-- 10. PANEL DE CHAT DE HERMANDAD (CONTRAÍBLE, DEBAJO DE LA VENTANA)
-- =========================================================================
local CHAT_EXPANDED_HEIGHT, CHAT_COLLAPSED_HEIGHT = 190, 30
local CHAT_MAX_PERSON_TABS = 6
local CHAT_GENERAL_TAB = "General"

-- El nombre es un enlace de jugador: clic izquierdo abre su pestaña, clic derecho el menú del juego
local function FormatChatLine(entry)
    local hex = entry.class and addonTable.GetClassColorHex(entry.class) or "40FF40"
    local linkName = entry.fullName or entry.sender
    return "|cFF808080[" .. entry.time .. "]|r |Hplayer:" .. linkName .. "|h|cFF" .. hex .. "[" .. entry.sender .. "]|r|h: " .. entry.text
end

-- Un mensaje pertenece a la conversación con "person" si lo escribe esa persona
-- o si lo escribo yo y la menciona
local function EntryMatchesPerson(entry, person)
    if entry.sender == person then return true end
    if entry.sender == UnitName("player") then
        return string.find(string.lower(entry.text), string.lower(person), 1, true) ~= nil
    end
    return false
end

local function BuildChatPanel(parent)
    local panel = CreateBackdropBox(parent, 1300, CHAT_EXPANDED_HEIGHT)
    panel:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, 2)
    panel:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, 2)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -9)
    title:SetText("Chat de hermandad")

    local unreadText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    unreadText:SetPoint("LEFT", title, "RIGHT", 10, 0)

    local btnToggle = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnToggle:SetSize(90, 20)
    btnToggle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -5)

    local tabHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tabHint:SetPoint("RIGHT", btnToggle, "LEFT", -12, 0)
    tabHint:SetText("Clic en un nombre: conversación con esa persona")

    local messagesFrame = CreateFrame("ScrollingMessageFrame", nil, panel)
    messagesFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -32)
    messagesFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 38)
    messagesFrame:SetFontObject(ChatFontNormal)
    messagesFrame:SetJustifyH("LEFT")
    messagesFrame:SetFading(false)
    messagesFrame:SetMaxLines(200)
    messagesFrame:SetHyperlinksEnabled(true)
    messagesFrame:EnableMouseWheel(true)
    messagesFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)

    local input = CreateFrame("EditBox", "GC_GuildChatInput", panel, "InputBoxTemplate")
    input:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 20, 10)
    input:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -110, 10)
    input:SetHeight(20)
    input:SetAutoFocus(false)
    input:SetMaxLetters(255)

    local btnSend = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnSend:SetSize(90, 22)
    btnSend:SetPoint("LEFT", input, "RIGHT", 8, 0)
    btnSend:SetText("Enviar")

    local function SendInput()
        if addonTable.GuildChat then addonTable.GuildChat.Send(input:GetText()) end
        input:SetText("")
        input:ClearFocus()
    end
    input:SetScript("OnEnterPressed", SendInput)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    btnSend:SetScript("OnClick", SendInput)

    -- ---------------------------------------------------------------------
    -- Pestañas: "General" + una por persona (nombre corto)
    -- ---------------------------------------------------------------------
    local tabs = {}            -- lista ordenada de { name, button, unread }
    local activeTabName = CHAT_GENERAL_TAB
    local unread = 0           -- mensajes nuevos con el panel contraído
    local SelectTab            -- declaración adelantada

    local function FindTab(name)
        for i, tab in ipairs(tabs) do
            if tab.name == name then return tab, i end
        end
    end

    local function EntryMatchesTab(entry, tabName)
        return tabName == CHAT_GENERAL_TAB or EntryMatchesPerson(entry, tabName)
    end

    local function LayoutTabs()
        local previous = nil
        for _, tab in ipairs(tabs) do
            tab.button:ClearAllPoints()
            if previous then
                tab.button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
            else
                tab.button:SetPoint("TOPLEFT", panel, "TOPLEFT", 170, -5)
            end
            local label = tab.name
            if tab.unread > 0 then label = label .. " |cFF00FF00(" .. tab.unread .. ")|r" end
            tab.button:SetText(label)
            tab.button:SetEnabled(tab.name ~= activeTabName)
            tab.button:SetShown(not GuildControlDB.settings.chatCollapsed)
            previous = tab.button
        end
        -- Con muchas pestañas la ayuda no cabe
        tabHint:SetShown(not GuildControlDB.settings.chatCollapsed and #tabs <= 3)
    end

    local function RenderMessages()
        messagesFrame:Clear()
        if not addonTable.GuildChat then return end
        for _, entry in ipairs(addonTable.GuildChat.GetMessages()) do
            if EntryMatchesTab(entry, activeTabName) then
                messagesFrame:AddMessage(FormatChatLine(entry), 0.25, 1, 0.25)
            end
        end
    end

    local function CloseTab(name)
        local tab, index = FindTab(name)
        if not tab or name == CHAT_GENERAL_TAB then return end
        tab.button:Hide()
        table.remove(tabs, index)
        if activeTabName == name then
            SelectTab(CHAT_GENERAL_TAB)
        else
            LayoutTabs()
        end
    end

    local function CreateTab(name)
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(name == CHAT_GENERAL_TAB and 80 or 120, 20)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" then CloseTab(name) else SelectTab(name) end
        end)

        if name ~= CHAT_GENERAL_TAB then
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Conversación con " .. name, 1, 1, 1)
                GameTooltip:AddLine("Clic derecho: cerrar pestaña", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        local tab = { name = name, button = button, unread = 0 }
        table.insert(tabs, tab)
        return tab
    end

    SelectTab = function(name)
        local tab = FindTab(name)
        if not tab then
            -- Si ya hay demasiadas pestañas de personas, se cierra la más antigua
            if #tabs - 1 >= CHAT_MAX_PERSON_TABS then
                local oldest = tabs[2]
                oldest.button:Hide()
                table.remove(tabs, 2)
            end
            tab = CreateTab(name)
        end
        tab.unread = 0
        activeTabName = name
        LayoutTabs()
        RenderMessages()
    end

    messagesFrame:SetScript("OnHyperlinkClick", function(self, link, text, button)
        local linkType, target = string.match(link, "^(%a+):([^:]+)")
        if linkType == "player" and button == "LeftButton" and target then
            local short = Ambiguate and Ambiguate(target, "guild") or target
            if short ~= UnitName("player") then
                SelectTab(short)
                return
            end
        end
        SetItemRef(link, text, button)
    end)

    local function ApplyCollapsed()
        local collapsed = GuildControlDB.settings.chatCollapsed
        panel:SetHeight(collapsed and CHAT_COLLAPSED_HEIGHT or CHAT_EXPANDED_HEIGHT)
        messagesFrame:SetShown(not collapsed)
        input:SetShown(not collapsed)
        btnSend:SetShown(not collapsed)
        tabHint:SetShown(not collapsed)
        btnToggle:SetText(collapsed and "Expandir" or "Contraer")
        if not collapsed then unread = 0 end
        unreadText:SetText(unread > 0 and ("|cFF00FF00(" .. unread .. " nuevos)|r") or "")
        LayoutTabs()
        -- Mantener el panel dentro de la pantalla al arrastrar la ventana
        parent:SetClampRectInsets(0, 0, 0, -(panel:GetHeight() - 2))
    end

    btnToggle:SetScript("OnClick", function()
        GuildControlDB.settings.chatCollapsed = not GuildControlDB.settings.chatCollapsed
        ApplyCollapsed()
    end)

    CreateTab(CHAT_GENERAL_TAB)

    -- Mensajes nuevos: a la pestaña activa si le corresponden; en las demás suman como no leídos
    if addonTable.GuildChat then
        addonTable.GuildChat.SetListener(function(entry)
            if EntryMatchesTab(entry, activeTabName) then
                messagesFrame:AddMessage(FormatChatLine(entry), 0.25, 1, 0.25)
            end
            local changed = false
            for _, tab in ipairs(tabs) do
                if tab.name ~= activeTabName and tab.name ~= CHAT_GENERAL_TAB and EntryMatchesPerson(entry, tab.name) then
                    tab.unread = tab.unread + 1
                    changed = true
                end
            end
            if changed then LayoutTabs() end
            if GuildControlDB.settings.chatCollapsed then
                unread = unread + 1
                unreadText:SetText("|cFF00FF00(" .. unread .. " nuevos)|r")
            end
        end)
    end

    parent:SetClampedToScreen(true)
    RenderMessages()
    ApplyCollapsed()
    containers.chat = panel
end

-- =========================================================================
-- CONSTRUCCIÓN TOTAL DE LA UI
-- =========================================================================
function uiModule.CreateUI()
    if GC_UI then return end

    GC_UI = CreateFrame("Frame", "GuildControlMainFrame", UIParent, "BasicFrameTemplateWithInset")
    GC_UI:SetSize(1300, 650 + (HEADER_HEIGHT - 50) + (ANN_BAR_HEIGHT - 45))
    GC_UI:SetPoint("CENTER")
    GC_UI:SetMovable(true)
    GC_UI:EnableMouse(true)
    GC_UI:RegisterForDrag("LeftButton")
    GC_UI:SetScript("OnDragStart", GC_UI.StartMoving)
    GC_UI:SetScript("OnDragStop", GC_UI.StopMovingOrSizing)

    GC_UI.title = GC_UI:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    GC_UI.title:SetPoint("CENTER", GC_UI.TitleBg, "CENTER", 0, 0)
    GC_UI.title:SetText("GuildControl")

    BuildHeader(GC_UI)
    BuildAnnouncementsBar(GC_UI)
    BuildSidebar(GC_UI)
    BuildPreviewPanel(GC_UI)

    local mainContent = CreateBackdropBox(GC_UI, 900, 520, "TOPLEFT", containers.sidebar, "TOPRIGHT", 5, 0)
    containers.mainContent = mainContent

    BuildMembersView(mainContent)
    BuildAchievementsView(mainContent)
    BuildMyProfileView(mainContent)
    BuildMyRostersView(mainContent)
    BuildProfessionsView(mainContent)
    BuildMythicPlusView(mainContent)
    BuildSummaryView(mainContent)
    BuildRosterView(mainContent)
    BuildWarningView(mainContent)
    BuildInviteView(mainContent)
    BuildBlacklistView(mainContent)
    BuildConfigView(mainContent)

    BuildChatPanel(GC_UI)

    -- Perfil (oficial o jugador) y avisos de roles declarados por otros miembros
    uiModule.ApplyProfile()
    if addonTable.Profiles then
        addonTable.Profiles.SetChangeListener(function()
            if not uiModule.IsShown() then return end
            if activeTab == "Miembros" and uiModule.RefreshList then uiModule.RefreshList() end
            if activeTab == "Roster" and uiModule.RefreshRoster then uiModule.RefreshRoster() end
            if uiModule.RefreshMyProfile then uiModule.RefreshMyProfile() end
            if uiModule.UpdatePlayerInfoBar then uiModule.UpdatePlayerInfoBar() end
        end)
    end
    uiModule.ApplyWindowStrata()

    SwitchTab("Miembros")
    GC_UI:Hide()
end

-- =========================================================================
-- HISTORIAL DE BAJAS (/gct bajas)
-- =========================================================================
local GC_BajasFrame = nil

local function CreateBajasFrame(parentUI)
    if GC_BajasFrame then return end
    GC_BajasFrame = CreateFrame("Frame", "GuildControlBajasFrame", parentUI, "BasicFrameTemplateWithInset")
    GC_BajasFrame:SetSize(640, 440)
    GC_BajasFrame:SetPoint("CENTER", parentUI, "CENTER", 0, 0)
    GC_BajasFrame:SetFrameStrata("DIALOG")
    GC_BajasFrame:Hide()

    GC_BajasFrame.title = GC_BajasFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    GC_BajasFrame.title:SetPoint("CENTER", GC_BajasFrame.TitleBg, "CENTER", 0, 0)
    GC_BajasFrame.title:SetText("Historial de bajas")

    local headerBg = CreateFrame("Frame", nil, GC_BajasFrame)
    headerBg:SetSize(590, 20)
    headerBg:SetPoint("TOPLEFT", GC_BajasFrame, "TOPLEFT", 15, -32)

    local function AddHeader(t, x, w)
        local fs = headerBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", headerBg, "LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetJustifyH("LEFT")
        fs:SetText(t)
    end
    AddHeader("Fecha", 5, 130)
    AddHeader("Personaje", 140, 160)
    AddHeader("Detalle", 305, 280)

    local scroll = CreateFrame("ScrollFrame", "GC_BajasScroll", GC_BajasFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", headerBg, "BOTTOMLEFT", 0, -5)
    scroll:SetPoint("BOTTOMRIGHT", GC_BajasFrame, "BOTTOMRIGHT", -35, 40)

    local child = CreateFrame("Frame")
    child:SetSize(590, 1)
    scroll:SetScrollChild(child)

    local emptyText = child:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", child, "TOPLEFT", 5, -10)
    emptyText:SetText("No hay bajas registradas.")

    local totalText = GC_BajasFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalText:SetPoint("BOTTOMLEFT", GC_BajasFrame, "BOTTOMLEFT", 18, 16)

    local rows = {}

    local function AcquireRow(index)
        local row = rows[index]
        if row then return row end

        row = CreateFrame("Frame", nil, child)
        row:SetSize(590, 22)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.05)

        local function Cell(x, w)
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", row, "LEFT", x, 0)
            fs:SetWidth(w)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            return fs
        end
        row.dateFs = Cell(5, 130)
        row.nameFs = Cell(140, 160)
        row.infoFs = Cell(305, 280)

        rows[index] = row
        return row
    end

    GC_BajasFrame.Refresh = function()
        for _, r in ipairs(rows) do r:Hide() end

        local count = 0
        for _, log in ipairs(GuildControlDB.history or {}) do
            if log.action == "BAJA" then
                count = count + 1
                local row = AcquireRow(count)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -5 - (count - 1) * 24)
                row.bg:SetShown(count % 2 == 0)
                row.dateFs:SetText("|cFF808080" .. (log.date or "-") .. "|r")
                row.nameFs:SetText("|cFFFF3333" .. (log.name or "-") .. "|r")
                row.infoFs:SetText(log.info or "")
                row:Show()
            end
        end

        emptyText:SetShown(count == 0)
        totalText:SetText("Total de bajas: |cFFFFD100" .. count .. "|r")
        child:SetHeight(math.max(1, count * 24 + 10))
        scroll:SetVerticalScroll(0)
    end
end

function uiModule.ShowBajas()
    addonTable.InitDB()
    if not GC_UI or not GC_UI:IsShown() then uiModule.ToggleUI() end
    if not GC_UI then return end

    CreateBajasFrame(GC_UI)
    GC_BajasFrame.Refresh()
    GC_BajasFrame:Show()
end

-- HIGH queda por encima de las barras de acción y botones del juego (MEDIUM/LOW);
-- los paneles CSV y Bajas usan DIALOG y siguen por encima de la ventana
function uiModule.ApplyWindowStrata()
    if not GC_UI then return end
    local onTop = GuildControlDB.settings and GuildControlDB.settings.windowOnTop
    GC_UI:SetFrameStrata(onTop and "HIGH" or "MEDIUM")
    GC_UI:SetToplevel(true)
end

function uiModule.UpdateMemberCounter()
    if not containers.header then return end
    local total = IsInGuild() and GetNumGuildMembers() or 0
    local online = 0
    if IsInGuild() then
        for i = 1, total do
            local _, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
            if isOnline then online = online + 1 end
        end
    end
    containers.header.membersBox.value:SetText(total)
    -- Warnings: inactivos (según la antigüedad elegida en Warning) y miembros en la lista negra
    containers.header.warningsBox.value:SetText(uiModule.CountWarnings and uiModule.CountWarnings() or 0)
    containers.header.onlineBox.value:SetText(online)
end

function uiModule.ToggleUI()
    addonTable.InitDB()
    if not GC_UI then uiModule.CreateUI() end
    if GC_UI:IsShown() then
        GC_UI:Hide()
    else
        if IsInGuild() then C_GuildInfo.GuildRoster() end
        uiModule.ApplyProfile()
        if activeTab == "Miembros" and uiModule.ResetMembersSort then uiModule.ResetMembersSort() end
        if uiModule.RefreshList then uiModule.RefreshList() end
        if uiModule.UpdateMemberCounter then uiModule.UpdateMemberCounter() end
        uiModule.UpdateHeader()
        GC_UI:Show()
    end
end