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

-- Caja de estadística: número grande arriba y etiqueta pequeña debajo
local function CreateStatBox(parent, label, width)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(width, HEADER_HEIGHT - 12)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0.08, 0.08, 0.1, 0.95)
    box:SetBackdropBorderColor(0.3, 0.3, 0.32, 1)

    box.value = box:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    box.value:SetPoint("TOP", box, "TOP", 0, -6)
    box.value:SetText("0")

    box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.label:SetPoint("BOTTOM", box, "BOTTOM", 0, 6)
    box.label:SetTextColor(0.75, 0.75, 0.75)
    box.label:SetText(label)

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
    local annBar = CreateBackdropBox(parent, 1280, 45, "TOPLEFT", containers.header, "BOTTOMLEFT", 0, -5)

    local label = annBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", annBar, "TOPLEFT", 10, -4)
    label:SetText("Configuración de mensajes múltiples")

    local dropAnn = CreateFrame("DropdownButton", "GC_DropAnnSelect_New", annBar, "WowStyle1DropdownTemplate")
    dropAnn:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    dropAnn:SetWidth(140)

    local msgInput = CreateFrame("EditBox", "GC_AnnMsgInput_New", annBar, "InputBoxTemplate")
    msgInput:SetSize(620, 20)
    msgInput:SetPoint("LEFT", dropAnn, "RIGHT", 15, 0)
    msgInput:SetAutoFocus(false)

    local timeLabel = annBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeLabel:SetPoint("LEFT", msgInput, "RIGHT", 15, 10)
    timeLabel:SetText("Tiempo")

    local timeInput = CreateFrame("EditBox", "GC_AnnTimeInput_New", annBar, "InputBoxTemplate")
    timeInput:SetSize(50, 20)
    timeInput:SetPoint("TOPLEFT", timeLabel, "BOTTOMLEFT", 0, -2)
    timeInput:SetNumeric(true)
    timeInput:SetAutoFocus(false)

    local chkEnable = CreateFrame("CheckButton", "GC_AnnEnable_New", annBar, "UICheckButtonTemplate")
    chkEnable:SetPoint("LEFT", timeInput, "RIGHT", 15, 0)
    _G[chkEnable:GetName() .. "Text"]:SetText("Activar")

    local function RefreshFields()
        if addonTable.Announcements then
            local data = addonTable.Announcements.GetAnnouncementData()
            if data then
                chkEnable:SetChecked(data.enabled)
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

    local tabs = { "Resumen", "Miembros", "Logros", "Roster", "Warning", "Black list" }
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
-- 6. VISTA DE MIEMBROS
-- =========================================================================
local function BuildMembersView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()

    local searchBox = CreateFrame("EditBox", "GC_NewSearchBox", view, "InputBoxTemplate")
    searchBox:SetSize(220, 20)
    searchBox:SetPoint("TOPLEFT", view, "TOPLEFT", 10, -10)
    searchBox:SetAutoFocus(false)

    local searchLabel = searchBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("BOTTOMLEFT", searchBox, "TOPLEFT", 0, 2)
    searchLabel:SetText("Buscar por nombre...")

    local btnShowAll = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnShowAll:SetSize(90, 22)
    btnShowAll:SetPoint("LEFT", searchBox, "RIGHT", 15, 0)
    btnShowAll:SetText("Todos")

    local btnShowOnline = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnShowOnline:SetSize(90, 22)
    btnShowOnline:SetPoint("LEFT", btnShowAll, "RIGHT", 8, 0)
    btnShowOnline:SetText("En línea")

    local btnCSV = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnCSV:SetSize(100, 22)
    btnCSV:SetPoint("TOPRIGHT", view, "TOPRIGHT", -10, -10)
    btnCSV:SetText("Sheets / CSV")
    btnCSV:SetScript("OnClick", function()
        if addonTable.CSV and addonTable.CSV.ShowFrame then addonTable.CSV.ShowFrame() end
    end)

    local headerBg = CreateFrame("Frame", nil, view)
    headerBg:SetSize(880, 20)
    headerBg:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -5, -15)

    local function CreateHeader(t, x, w)
        local fs = headerBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", headerBg, "LEFT", x, 0)
        fs:SetWidth(w)
        fs:SetText(t)
    end

    CreateHeader("Nº", 5, 25)
    CreateHeader("Nivel", 30, 35)
    CreateHeader("Clase", 65, 70)
    CreateHeader("Nombre", 135, 120)
    CreateHeader("Rango", 255, 90)
    CreateHeader("Rol", 345, 50)
    CreateHeader("Enfoque", 395, 55)
    CreateHeader("Prof. 1", 450, 100)
    CreateHeader("Prof. 2", 550, 100)
    CreateHeader("Roster", 650, 90)
    CreateHeader("Conexión", 740, 90)

    local scrollFrame = CreateFrame("ScrollFrame", "GC_NewMembersScroll", view, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", headerBg, "BOTTOMLEFT", 0, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -25, 10)

    local scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(scrollFrame:GetWidth(), scrollFrame:GetHeight())
    scrollFrame:SetScrollChild(scrollChild)

    local showOnlyOnline = false
    local searchQuery = ""

    searchBox:SetScript("OnTextChanged", function(self)
        searchQuery = string.lower(self:GetText() or "")
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

    uiModule.RefreshList = function()
        if not scrollChild then return end
        if scrollChild.rows then for _, r in pairs(scrollChild.rows) do r:Hide() end end
        scrollChild.rows = {}

        local yOffset, rowIndex = -5, 1
        for fullName, data in pairs(GuildControlDB.members or {}) do
            local passSearch = (searchQuery == "") or string.find(string.lower(fullName), searchQuery, 1, true)
            local passOnline = (not showOnlyOnline) or data.isOnline

            if passSearch and passOnline then
                local row = CreateFrame("Button", nil, scrollChild)
                row:SetSize(870, 22)
                row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)

                if rowIndex % 2 == 0 then
                    local bg = row:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints()
                    bg:SetColorTexture(1, 1, 1, 0.05)
                end

                local isOnline = data.isOnline
                local hex = isOnline and addonTable.GetClassColorHex(data.class) or "888888"

                local function Cell(t, x, w, cHex)
                    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    fs:SetPoint("LEFT", row, "LEFT", x, 0)
                    fs:SetWidth(w)
                    fs:SetJustifyH("LEFT")
                    fs:SetText("|cFF" .. (cHex or "FFFFFF") .. tostring(t) .. "|r")
                end

                Cell(rowIndex, 5, 25, "888888")
                Cell(data.level or 0, 30, 35, hex)
                Cell(data.class or "Desconocida", 65, 70, hex)
                Cell(fullName, 135, 120, hex)
                Cell(data.rank or "Recluta", 255, 90, isOnline and "FFFFFF" or "888888")
                Cell(data.role or "DPS", 345, 50, isOnline and "FF7F7F" or "888888")
                Cell(data.focus or "PvE", 395, 55, isOnline and "FFFFFF" or "888888")
                Cell(data.prof1 or "Ninguna", 450, 100, isOnline and "FFFFFF" or "888888")
                Cell(data.prof2 or "Ninguna", 550, 100, isOnline and "FFFFFF" or "888888")
                Cell(data.roster or "Sin Roster", 650, 90, isOnline and "00FFFF" or "888888")
                Cell(data.lastOnline or "Online", 740, 90, isOnline and "00FF00" or "888888")

                row:SetScript("OnClick", function()
                    selectedMember = data
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
                        "Estado: " .. (data.isOnline and "|cFF00FF00En línea|r" or ("|cFF888888" .. (data.lastOnline or "Desconectado") .. "|r"))
                    )
                end)

                table.insert(scrollChild.rows, row)
                yOffset = yOffset - 24
                rowIndex = rowIndex + 1
            end
        end
    end

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
    local filterWithPoints = false

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

    local searchBox = CreateFrame("EditBox", "GC_AchSearchBox", rightPanel, "InputBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 10, -10)
    searchBox:SetAutoFocus(false)

    local searchLabel = searchBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("BOTTOMLEFT", searchBox, "TOPLEFT", 0, 2)
    searchLabel:SetText("Buscador por nombre...")

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

    local chkPoints = CreateFrame("CheckButton", "GC_ChkPointsAch", rightPanel, "UICheckButtonTemplate")
    chkPoints:SetPoint("LEFT", btnFilterPending, "RIGHT", 8, 0)
    _G[chkPoints:GetName() .. "Text"]:SetText("Solo con puntos")

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
        if not currentCategoryId then
            achChild:SetHeight(1)
            return
        end

        local numAchievements = GetCategoryNumAchievements(currentCategoryId, true) or 0
        local yOffset = -5
        local rowIndex = 0

        for i = 1, numAchievements do
            local id, name, points, completed, month, day, year, _, _, icon = GetAchievementInfo(currentCategoryId, i)

            if id then
                local passSearch = (searchQuery == "") or string.find(string.lower(name or ""), searchQuery, 1, true)

                local passState = true
                if filterState == "COMPLETADOS" and not completed then passState = false end
                if filterState == "PENDIENTES" and completed then passState = false end

                local passPoints = (not filterWithPoints) or ((points or 0) > 0)

                if passSearch and passState and passPoints then
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

        achChild:SetHeight(math.max(1, rowIndex * 26 + 10))

        -- Si hay un logro seleccionado, mantener la vista previa actualizada
        if selectedAchievementId and activeTab == "Logros" then
            SetPreviewText(BuildAchievementPreviewText(selectedAchievementId))
        end
    end

    searchBox:SetScript("OnTextChanged", function(self)
        searchQuery = string.lower(self:GetText() or "")
        uiModule.RefreshAchievements()
    end)

    btnFilterAll:SetScript("OnClick", function() filterState = "TODOS"; uiModule.RefreshAchievements() end)
    btnFilterDone:SetScript("OnClick", function() filterState = "COMPLETADOS"; uiModule.RefreshAchievements() end)
    btnFilterPending:SetScript("OnClick", function() filterState = "PENDIENTES"; uiModule.RefreshAchievements() end)
    chkPoints:SetScript("OnClick", function(self) filterWithPoints = self:GetChecked(); uiModule.RefreshAchievements() end)

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

    view:SetScript("OnShow", RefreshConfigFields)
    containers.views["Configuracion"] = view
end

-- =========================================================================
-- CONSTRUCCIÓN TOTAL DE LA UI
-- =========================================================================
function uiModule.CreateUI()
    if GC_UI then return end

    GC_UI = CreateFrame("Frame", "GuildControlMainFrame", UIParent, "BasicFrameTemplateWithInset")
    GC_UI:SetSize(1300, 650 + (HEADER_HEIGHT - 50))
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
    BuildPlaceholderView(mainContent, "Black list")
    BuildConfigView(mainContent)

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
        if uiModule.RefreshList then uiModule.RefreshList() end
        if uiModule.UpdateMemberCounter then uiModule.UpdateMemberCounter() end
        uiModule.UpdateHeader()
        GC_UI:Show()
    end
end