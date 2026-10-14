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
    titleText:SetPoint("LEFT", logo, "RIGHT", 12, 0)
    header.titleText = titleText

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

    local factionTag = ""
    local _, localizedFaction = UnitFactionGroup("player")
    if localizedFaction then
        factionTag = "  |cFF808080[" .. localizedFaction .. "]|r"
    end
    header.titleText:SetText("|cFFFFD100" .. addonTable.GetDisplayGuildName() .. "|r" .. factionTag)
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
    containers.announcements = annBar
end

-- =========================================================================
-- 3. CAMBIO DE PESTAÑAS Y NAVEGACIÓN
-- =========================================================================
local function SetPreviewText(text)
    if containers.preview and containers.preview.infoText then
        containers.preview.infoText:SetText(text or PREVIEW_DEFAULT_TEXT)
    end
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
    end
end

-- =========================================================================
-- 4. MENÚ LATERAL IZQUIERDO (SIDEBAR)
-- =========================================================================
local function BuildSidebar(parent)
    local sidebar = CreateBackdropBox(parent, 150, 520, "TOPLEFT", containers.announcements, "BOTTOMLEFT", 0, -5)

    local tabs = { "Resumen", "Miembros", "Logros", "Roster", "Warning", "Invitar", "Black list" }
    local yOffset = -15

    for _, tabName in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
        btn:SetSize(130, 25)
        btn:SetPoint("TOP", sidebar, "TOP", 0, yOffset)
        btn:SetText(tabName)
        btn:SetScript("OnClick", function() SwitchTab(tabName) end)
        yOffset = yOffset - 32
    end

    local btnConfig = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    btnConfig:SetSize(130, 25)
    btnConfig:SetPoint("BOTTOM", sidebar, "BOTTOM", 0, 15)
    btnConfig:SetText("Configuración")
    btnConfig:SetScript("OnClick", function() SwitchTab("Configuracion") end)

    containers.sidebar = sidebar
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
    infoText:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -15, 15)
    infoText:SetJustifyH("LEFT")
    infoText:SetJustifyV("TOP")
    infoText:SetText(PREVIEW_DEFAULT_TEXT)

    preview.infoText = infoText
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
    if d.completed then
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

function uiModule.ShowAchievementPreview(id)
    if not id then return end
    selectedAchievementId = id

    if addonTable.Achievements then
        addonTable.Achievements.RequestMembers(id)
    end
    SetPreviewText(BuildAchievementPreviewText(id))

    -- La lista de participantes puede tardar en llegar del servidor: reintento único
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function()
            if selectedAchievementId == id and activeTab == "Logros" then
                SetPreviewText(BuildAchievementPreviewText(id))
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
    { title = "Nivel",    x = 30,  w = 50,  key = "level" },
    { title = "Clase",    x = 80,  w = 65,  key = "class" },
    { title = "Nombre",   x = 145, w = 140, key = "name" },
    { title = "Rango",    x = 285, w = 80,  key = "rank" },
    { title = "Rol",      x = 365, w = 40,  key = "role" },
    { title = "Enfoque",  x = 405, w = 70,  key = "focus" },
    { title = "Prof. 1",  x = 475, w = 100, key = "prof1" },
    { title = "Prof. 2",  x = 575, w = 100, key = "prof2" },
    { title = "Roster",   x = 675, w = 75,  key = "roster" },
    { title = "Conexión", x = 750, w = 95,  key = "lastOnline" },
}

-- Orden por defecto: conectados primero y después por días desde la última conexión
local DEFAULT_SORT_KEY = "lastOnline"

-- Conectado = -1, desconectado hoy = 0, "N días" = N
local function OnlineSortValue(data)
    if data.isOnline then return -1 end
    return tonumber(string.match(data.lastOnline or "", "(%d+)")) or 0
end

local function MemberSortValue(entry, key)
    local data = entry.data
    if key == "level" then return tonumber(data.level) or 0 end
    if key == "lastOnline" then return OnlineSortValue(data) end
    if key == "name" then return string.lower(entry.name) end

    local value = data[key]
    if key == "prof1" or key == "prof2" then
        -- "Ninguna" siempre al final en orden ascendente
        if not value or value == "Ninguna" then return "\255" end
    end
    return string.lower(tostring(value or ""))
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

    local function ShowMemberPreview(fullName, data)
        selectedMember = data
        selectedFullName = fullName
        SetPreviewText(
            "|cFFFFD100" .. fullName .. "|r\n\n" ..
            "Nivel: " .. (data.level or 0) .. "\n" ..
            "Clase: " .. (data.class or "Desconocida") .. "\n" ..
            "Rango: " .. (data.rank or "Recluta") .. "\n" ..
            "Rol: " .. (data.role or "DPS") .. "\n" ..
            "Enfoque: " .. (data.focus or "PvE") .. "\n" ..
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
                { data.role or "DPS", isOnline and "FF7F7F" or dim },
                { data.focus or "PvE", isOnline and "FFFFFF" or dim },
                { data.prof1 or "Ninguna", isOnline and "FFFFFF" or dim },
                { data.prof2 or "Ninguna", isOnline and "FFFFFF" or dim },
                { data.roster or "Sin Roster", isOnline and "00FFFF" or dim },
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
    lastAchText:SetText("Último logro: |cFF808080Ninguno|r")

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

        -- Si hay un logro seleccionado, mantener la vista previa actualizada
        if selectedAchievementId and activeTab == "Logros" then
            SetPreviewText(BuildAchievementPreviewText(selectedAchievementId))
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
local function CreateMessageEditor(parent, anchor, labelText, height, onChange)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
    label:SetText(labelText)

    local box = CreateBackdropBox(parent, 850, height, "TOPLEFT", label, "BOTTOMLEFT", 0, -6)
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
    preview:SetWidth(760)
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
                if GuildControlDB.members[item.name] then
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

    local title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", view, "TOPLEFT", 20, -20)
    title:SetText("Configuración")

    -- 9.1 Nombre de la hermandad
    local nameLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -25)
    nameLabel:SetText("Nombre de la hermandad")

    local nameInput = CreateFrame("EditBox", "GC_CfgGuildName", view, "InputBoxTemplate")
    nameInput:SetSize(300, 20)
    nameInput:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -8)
    nameInput:SetAutoFocus(false)
    nameInput:SetMaxLetters(48)

    local btnSaveName = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnSaveName:SetSize(90, 22)
    btnSaveName:SetPoint("LEFT", nameInput, "RIGHT", 10, 0)
    btnSaveName:SetText("Guardar")

    local btnResetName = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnResetName:SetSize(150, 22)
    btnResetName:SetPoint("LEFT", btnSaveName, "RIGHT", 6, 0)
    btnResetName:SetText("Usar nombre del juego")

    local nameHint = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    nameHint:SetPoint("TOPLEFT", nameInput, "BOTTOMLEFT", -6, -6)
    nameHint:SetText("Si lo dejas vacío se muestra el nombre real de la hermandad.")

    -- 9.2 Icono de la hermandad
    local iconLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    iconLabel:SetPoint("TOPLEFT", nameHint, "BOTTOMLEFT", 0, -30)
    iconLabel:SetText("Icono de la hermandad")

    local iconPreview = view:CreateTexture(nil, "ARTWORK")
    iconPreview:SetSize(48, 48)
    iconPreview:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 0, -8)

    local iconInput = CreateFrame("EditBox", "GC_CfgGuildIcon", view, "InputBoxTemplate")
    iconInput:SetSize(300, 20)
    iconInput:SetPoint("LEFT", iconPreview, "RIGHT", 16, 0)
    iconInput:SetAutoFocus(false)

    local btnApplyIcon = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnApplyIcon:SetSize(90, 22)
    btnApplyIcon:SetPoint("LEFT", iconInput, "RIGHT", 10, 0)
    btnApplyIcon:SetText("Aplicar")

    local btnResetIcon = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnResetIcon:SetSize(150, 22)
    btnResetIcon:SetPoint("LEFT", btnApplyIcon, "RIGHT", 6, 0)
    btnResetIcon:SetText("Restablecer icono")

    local iconHint = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    iconHint:SetPoint("TOPLEFT", iconPreview, "BOTTOMLEFT", 0, -6)
    iconHint:SetText("Escribe el nombre del icono (INV_Misc_QuestionMark), su ID numérico o la ruta completa, o elige uno:")

    local function RefreshConfigFields()
        local settings = GuildControlDB.settings or {}
        nameInput:SetText(settings.guildName or "")
        iconInput:SetText(tostring(settings.guildIcon or ""))
        iconPreview:SetTexture(addonTable.ResolveIconTexture(settings.guildIcon))
    end

    local function SaveName()
        GuildControlDB.settings.guildName = strtrim(nameInput:GetText() or "")
        nameInput:ClearFocus()
        uiModule.UpdateHeader()
        RefreshConfigFields()
    end

    local function SaveIcon(value)
        value = strtrim(value or "")
        if value == "" then value = DEFAULT_GUILD_ICON end
        GuildControlDB.settings.guildIcon = tonumber(value) or value
        iconInput:ClearFocus()
        uiModule.UpdateHeader()
        RefreshConfigFields()
    end

    btnSaveName:SetScript("OnClick", SaveName)
    nameInput:SetScript("OnEnterPressed", SaveName)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus(); RefreshConfigFields() end)
    btnResetName:SetScript("OnClick", function()
        nameInput:SetText("")
        SaveName()
    end)

    btnApplyIcon:SetScript("OnClick", function() SaveIcon(iconInput:GetText()) end)
    iconInput:SetScript("OnEnterPressed", function(self) SaveIcon(self:GetText()) end)
    iconInput:SetScript("OnEscapePressed", function(self) self:ClearFocus(); RefreshConfigFields() end)
    iconInput:SetScript("OnTextChanged", function(self, userInput)
        if userInput then iconPreview:SetTexture(addonTable.ResolveIconTexture(strtrim(self:GetText() or ""))) end
    end)
    btnResetIcon:SetScript("OnClick", function() SaveIcon(DEFAULT_GUILD_ICON) end)

    -- Cuadrícula de iconos predefinidos
    local perRow, size, gap = 8, 36, 6
    for i, iconName in ipairs(PRESET_ICONS) do
        local btn = CreateFrame("Button", nil, view)
        btn:SetSize(size, size)
        local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
        btn:SetPoint("TOPLEFT", iconHint, "BOTTOMLEFT", col * (size + gap), -10 - row * (size + gap))
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

    -- 9.3 Saludo automático
    local greetLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    greetLabel:SetPoint("TOPLEFT", iconHint, "BOTTOMLEFT", 0, -110)
    greetLabel:SetText("Saludo automático")

    local chkGreet = CreateFrame("CheckButton", "GC_CfgAutoGreet", view, "UICheckButtonTemplate")
    chkGreet:SetPoint("TOPLEFT", greetLabel, "BOTTOMLEFT", -4, -4)
    _G[chkGreet:GetName() .. "Text"]:SetText("Responder cuando alguien de la hermandad salude")

    local greetInput = CreateFrame("EditBox", "GC_CfgGreetMessage", view, "InputBoxTemplate")
    greetInput:SetSize(300, 20)
    greetInput:SetPoint("TOPLEFT", chkGreet, "BOTTOMLEFT", 10, -6)
    greetInput:SetAutoFocus(false)
    greetInput:SetMaxLetters(120)

    local btnSaveGreet = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnSaveGreet:SetSize(90, 22)
    btnSaveGreet:SetPoint("LEFT", greetInput, "RIGHT", 10, 0)
    btnSaveGreet:SetText("Guardar")

    local greetHint = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    greetHint:SetPoint("TOPLEFT", greetInput, "BOTTOMLEFT", -6, -6)
    greetHint:SetText("{nombre} se sustituye por el nombre de quien saluda. Responde a saludos cortos (hola, buenas...). Los tiempos se ajustan en la columna derecha.")
    greetHint:SetWidth(620)
    greetHint:SetJustifyH("LEFT")

    local function SaveGreet()
        local text = strtrim(greetInput:GetText() or "")
        if text == "" then text = "¡Hola, {nombre}!" end
        GuildControlDB.settings.greetMessage = text
        greetInput:SetText(text)
        greetInput:ClearFocus()
    end

    chkGreet:SetScript("OnClick", function(self) GuildControlDB.settings.autoGreet = self:GetChecked() and true or false end)
    btnSaveGreet:SetScript("OnClick", SaveGreet)
    greetInput:SetScript("OnEnterPressed", SaveGreet)
    greetInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetText(GuildControlDB.settings.greetMessage or "")
    end)

    -- 9.4 Ventana (columna derecha)
    local windowLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    windowLabel:SetPoint("TOPLEFT", view, "TOPLEFT", 660, -70)
    windowLabel:SetText("Ventana")

    local chkOnTop = CreateFrame("CheckButton", "GC_CfgWindowOnTop", view, "UICheckButtonTemplate")
    chkOnTop:SetPoint("TOPLEFT", windowLabel, "BOTTOMLEFT", -4, -4)
    _G[chkOnTop:GetName() .. "Text"]:SetText("Siempre por encima")

    local onTopHint = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    onTopHint:SetPoint("TOPLEFT", chkOnTop, "BOTTOMLEFT", 4, -2)
    onTopHint:SetWidth(210)
    onTopHint:SetJustifyH("LEFT")
    onTopHint:SetText("Muestra la ventana del addon por encima de las barras de acción y otros botones del juego.")

    chkOnTop:SetScript("OnClick", function(self)
        GuildControlDB.settings.windowOnTop = self:GetChecked() and true or false
        uiModule.ApplyWindowStrata()
    end)

    -- 9.5 Tiempos del saludo automático (columna derecha)
    local timesLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timesLabel:SetPoint("TOPLEFT", onTopHint, "BOTTOMLEFT", 0, -30)
    timesLabel:SetText("Tiempos del saludo")

    -- Campo numérico con su texto a la derecha; guarda al escribir dentro de [minValue, maxValue]
    local function CreateNumberSetting(anchor, xOffset, yOffset, labelText, key, minValue, maxValue)
        local input = CreateFrame("EditBox", nil, view, "InputBoxTemplate")
        input:SetSize(40, 20)
        input:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", xOffset, yOffset)
        input:SetAutoFocus(false)
        input:SetNumeric(true)
        input:SetMaxLetters(4)
        input:SetJustifyH("CENTER")

        local text = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", input, "RIGHT", 8, 0)
        text:SetWidth(160)
        text:SetJustifyH("LEFT")
        text:SetText(labelText)

        input:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            local value = tonumber(self:GetText())
            if value then
                GuildControlDB.settings[key] = math.min(maxValue, math.max(minValue, value))
            end
        end)
        input:SetScript("OnEditFocusLost", function(self) self:SetText(tostring(GuildControlDB.settings[key])) end)
        input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return input
    end

    local delayInput = CreateNumberSetting(timesLabel, 6, -8, "Segundos de espera antes de responder (1-60)", "greetDelay", 1, 60)
    local cooldownInput = CreateNumberSetting(delayInput, 0, -18, "Minutos sin volver a saludar a la misma persona (1-1440)", "greetCooldown", 1, 1440)

    local loginInput = CreateNumberSetting(cooldownInput, 0, -18, "Minutos tras conectarse en los que se le saluda (1-30)", "greetLoginWindow", 1, 30)

    local timesHint = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    timesHint:SetPoint("TOPLEFT", loginInput, "BOTTOMLEFT", -6, -10)
    timesHint:SetWidth(210)
    timesHint:SetJustifyH("LEFT")
    timesHint:SetText("Solo se saluda a quien acaba de conectarse y aún no ha sido saludado. A la espera se suman hasta 4 s aleatorios.")

    -- Palabras que cuentan como saludo
    local wordsLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    wordsLabel:SetPoint("TOPLEFT", timesHint, "BOTTOMLEFT", 0, -16)
    wordsLabel:SetText("Palabras de saludo")

    local wordsBox = CreateBackdropBox(view, 220, 64, "TOPLEFT", wordsLabel, "BOTTOMLEFT", 0, -4)
    local wordsInput = CreateFrame("EditBox", nil, wordsBox)
    wordsInput:SetPoint("TOPLEFT", wordsBox, "TOPLEFT", 6, -6)
    wordsInput:SetPoint("BOTTOMRIGHT", wordsBox, "BOTTOMRIGHT", -6, 6)
    wordsInput:SetMultiLine(true)
    wordsInput:SetFontObject(GameFontHighlightSmall)
    wordsInput:SetAutoFocus(false)
    wordsInput:SetMaxLetters(0)
    wordsInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    wordsInput:SetScript("OnTextChanged", function(self, userInput)
        if userInput then GuildControlDB.settings.greetWords = self:GetText() or "" end
    end)
    wordsBox:EnableMouse(true)
    wordsBox:SetScript("OnMouseDown", function() wordsInput:SetFocus() end)

    local wordsHint = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    wordsHint:SetPoint("TOPLEFT", wordsBox, "BOTTOMLEFT", 0, -4)
    wordsHint:SetWidth(220)
    wordsHint:SetJustifyH("LEFT")
    wordsHint:SetText("Separadas por comas. El mensaje debe empezar por una de ellas. Vacío = lista por defecto.")

    view:SetScript("OnShow", function()
        RefreshConfigFields()
        delayInput:SetText(tostring(GuildControlDB.settings.greetDelay))
        cooldownInput:SetText(tostring(GuildControlDB.settings.greetCooldown))
        loginInput:SetText(tostring(GuildControlDB.settings.greetLoginWindow))
        local words = GuildControlDB.settings.greetWords
        if not words or strtrim(words) == "" then
            words = addonTable.GuildChat and addonTable.GuildChat.DEFAULT_GREET_WORDS or ""
        end
        wordsInput:SetText(words)
        chkOnTop:SetChecked(GuildControlDB.settings.windowOnTop)
        chkGreet:SetChecked(GuildControlDB.settings.autoGreet)
        greetInput:SetText(GuildControlDB.settings.greetMessage or "")
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
    BuildPlaceholderView(mainContent, "Resumen")
    BuildPlaceholderView(mainContent, "Roster")
    BuildPlaceholderView(mainContent, "Warning")
    BuildInviteView(mainContent)
    BuildPlaceholderView(mainContent, "Black list")
    BuildConfigView(mainContent)

    BuildChatPanel(GC_UI)
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
    containers.header.onlineBox.value:SetText(online)
end

function uiModule.ToggleUI()
    addonTable.InitDB()
    if not GC_UI then uiModule.CreateUI() end
    if GC_UI:IsShown() then
        GC_UI:Hide()
    else
        if IsInGuild() then C_GuildInfo.GuildRoster() end
        if activeTab == "Miembros" and uiModule.ResetMembersSort then uiModule.ResetMembersSort() end
        if uiModule.RefreshList then uiModule.RefreshList() end
        if uiModule.UpdateMemberCounter then uiModule.UpdateMemberCounter() end
        uiModule.UpdateHeader()
        GC_UI:Show()
    end
end