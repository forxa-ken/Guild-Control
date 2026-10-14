local addonName, addonTable = ...

addonTable.UI = {}
local uiModule = addonTable.UI

local GC_UI = nil
local activeTab = "Miembros"
local selectedMember = nil

-- Referencias a los contenedores principales
local containers = {
    header = nil,
    announcements = nil,
    sidebar = nil,
    mainContent = nil,
    preview = nil,
    views = {} -- Vistas específicas (Resumen, Miembros, Logros, etc.)
}

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
local function BuildHeader(parent)
    local header = CreateBackdropBox(parent, 1280, 50, "TOPLEFT", parent, "TOPLEFT", 10, -25)
    
    local logoBg = header:CreateTexture(nil, "OVERLAY")
    logoBg:SetSize(36, 36)
    logoBg:SetPoint("LEFT", header, "LEFT", 10, 0)
    logoBg:SetTexture("Interface\\Icons\\Achievement_GuildPerk_MobileBanking")

    local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", logoBg, "RIGHT", 10, 0)
    titleText:SetText("|cFFFFD100Lobo Gélido|r  |cFF808080[Horda]|r")

    local onlineText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    onlineText:SetPoint("RIGHT", header, "RIGHT", -220, 0)
    header.onlineText = onlineText

    local membersText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    membersText:SetPoint("RIGHT", onlineText, "LEFT", -30, 0)
    header.membersText = membersText

    local warningsText = header:CreateFontString(nil, "OVERLAY", "GameFontRed")
    warningsText:SetPoint("RIGHT", membersText, "LEFT", -30, 0)
    warningsText:SetText("Warnings: 0")

    local verText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    verText:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -15, -8)
    verText:SetText("v4.5.0")

    containers.header = header
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
local function SwitchTab(tabName)
    activeTab = tabName
    for name, viewFrame in pairs(containers.views) do
        if name == tabName then
            viewFrame:Show()
        else
            viewFrame:Hide()
        end
    end
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
    infoText:SetText("Selecciona un elemento para ver su información detallada.")

    preview.infoText = infoText
    containers.preview = preview
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
                    if containers.preview and containers.preview.infoText then
                        containers.preview.infoText:SetText(
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
                    end
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
-- 7. VISTA DE LOGROS (EXCLUSIVO HERMANDAD - DEDICADO Y OPTIMIZADO)
-- =========================================================================
local function BuildAchievementsView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    -- Categoría base de logros de Hermandad en WoW Retail
    local GUILD_CATEGORY_BASE = 15070
    local currentCategoryId = GUILD_CATEGORY_BASE
    local searchQuery = ""
    local filterState = "TODOS" -- "TODOS", "COMPLETADOS", "PENDIENTES"
    local filterSeasonalOnly = false

    -- 7.1 Encabezado de estadísticas
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
    catChild:SetSize(catScroll:GetWidth(), catScroll:GetHeight())
    catScroll:SetScrollChild(catChild)

    -- 7.3 Panel Derecho: Buscador, Filtros y Lista
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

    local chkSeasonal = CreateFrame("CheckButton", "GC_ChkSeasonalAch", rightPanel, "UICheckButtonTemplate")
    chkSeasonal:SetPoint("LEFT", btnFilterPending, "RIGHT", 8, 0)
    _G[chkSeasonal:GetName() .. "Text"]:SetText("Temporada")

    -- Encabezados
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
    achChild:SetSize(achScroll:GetWidth(), achScroll:GetHeight())
    achScroll:SetScrollChild(achChild)

    -- Cargar Categorías de Hermandad
    local function BuildGuildCategories()
        if catChild.buttons then for _, b in pairs(catChild.buttons) do b:Hide() end end
        catChild.buttons = {}

        local categories = GetCategoryList()
        local yOffset = -5
        local firstSet = false

        for _, catId in ipairs(categories or {}) do
            local title, parentID = GetCategoryInfo(catId)
            if catId == GUILD_CATEGORY_BASE or parentID == GUILD_CATEGORY_BASE then
                if not firstSet then
                    currentCategoryId = catId
                    firstSet = true
                end

                local btn = CreateFrame("Button", nil, catChild, "UIPanelButtonTemplate")
                btn:SetSize(165, 22)
                btn:SetPoint("TOPLEFT", catChild, "TOPLEFT", 5, yOffset)
                btn:SetText(title or ("Cat " .. catId))

                btn:SetScript("OnClick", function()
                    currentCategoryId = catId
                    uiModule.RefreshAchievements()
                end)

                table.insert(catChild.buttons, btn)
                yOffset = yOffset - 25
            end
        end
    end

    -- Escaneo global rápido de resumen de Hermandad (Sin Lag)
    local function CalculateGuildSummary()
        local guildPoints = GetTotalAchievementPoints and GetTotalAchievementPoints(true) or 0
        pointsText:SetText("Puntos: |cFFFFD100" .. guildPoints .. "|r")

        local totalCount, doneCount = 0, 0
        local latestName, latestDate = nil, nil
        local latestTS = 0

        local categories = GetCategoryList()
        for _, catId in ipairs(categories or {}) do
            local _, parentID = GetCategoryInfo(catId)
            if catId == GUILD_CATEGORY_BASE or parentID == GUILD_CATEGORY_BASE then
                local numAch = GetCategoryNumAchievements(catId, true) or 0
                for i = 1, numAch do
                    local _, name, _, completed, month, day, year = GetAchievementInfo(catId, i)
                    if name then
                        totalCount = totalCount + 1
                        if completed then
                            doneCount = doneCount + 1
                            if year and month and day and year > 0 then
                                local ts = (year * 10000) + (month * 100) + day
                                if ts > latestTS then
                                    latestTS = ts
                                    latestName = name
                                    latestDate = string.format("%02d/%02d/20%02d", day, month, year)
                                end
                            end
                        end
                    end
                end
            end
        end

        completedText:SetText("Completados: |cFF00FF00" .. doneCount .. "/" .. totalCount .. "|r")
        if latestName then
            lastAchText:SetText("Último logro: |cFFFFD100" .. latestName .. "|r (" .. (latestDate or "") .. ")")
        else
            lastAchText:SetText("Último logro: |cFF808080Ninguno|r")
        end
    end

    -- Renderizado de la lista
    uiModule.RefreshAchievements = function()
        if not achChild then return end
        if achChild.rows then for _, r in pairs(achChild.rows) do r:Hide() end end
        achChild.rows = {}

        CalculateGuildSummary()

        local numAchievements = GetCategoryNumAchievements(currentCategoryId, true) or 0
        local yOffset = -5
        local rowIndex = 1

        for i = 1, numAchievements do
            local id, name, points, completed, month, day, year, description, flags, icon = GetAchievementInfo(currentCategoryId, i)
            
            if id then
                local passSearch = (searchQuery == "") or string.find(string.lower(name or ""), searchQuery, 1, true)
                local passState = true
                if filterState == "COMPLETADOS" and not completed then passState = false end
                if filterState == "PENDIENTES" and completed then passState = false end

                local isSeasonalOrAvailable = bit.band(flags or 0, ACHIEVEMENT_FLAGS_ACCOUNT or 0) == 0
                local passSeasonal = (not filterSeasonalOnly) or isSeasonalOrAvailable

                if passSearch and passState and passSeasonal then
                    local row = CreateFrame("Button", nil, achChild)
                    row:SetSize(650, 24)
                    row:SetPoint("TOPLEFT", achChild, "TOPLEFT", 0, yOffset)

                    if rowIndex % 2 == 0 then
                        local bg = row:CreateTexture(nil, "BACKGROUND")
                        bg:SetAllPoints()
                        bg:SetColorTexture(1, 1, 1, 0.05)
                    end

                    local iconTex = row:CreateTexture(nil, "ARTWORK")
                    iconTex:SetSize(20, 20)
                    iconTex:SetPoint("LEFT", row, "LEFT", 90, 0)
                    iconTex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

                    local titleFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    titleFs:SetPoint("LEFT", iconTex, "RIGHT", 8, 0)
                    titleFs:SetWidth(330)
                    titleFs:SetJustifyH("LEFT")
                    titleFs:SetText(name or "Desconocido")

                    local statusFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    statusFs:SetPoint("LEFT", row, "LEFT", 5, 0)
                    statusFs:SetWidth(80)
                    statusFs:SetJustifyH("LEFT")
                    statusFs:SetText(completed and "|cFF00FF00Completado|r" or "|cFFFF3333Pendiente|r")

                    local dateFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    dateFs:SetPoint("LEFT", row, "LEFT", 460, 0)
                    dateFs:SetWidth(180)
                    dateFs:SetJustifyH("LEFT")
                    dateFs:SetText(completed and string.format("%02d/%02d/20%02d", day or 0, month or 0, year or 0) or "|cFF808080En progreso|r")

                    -- Clic: Abrir la interfaz oficial de Blizzard y navegar al logro
                    row:SetScript("OnClick", function()
                        if not C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI") then
                            AchievementFrame_LoadUI()
                        end
                        if AchievementFrame then
                            ShowUIPanel(AchievementFrame)
                            if AchievementFrame_ToggleGuildTab then
                                AchievementFrame_ToggleGuildTab(true)
                            end
                            if AchievementFrame_SelectAchievement then
                                AchievementFrame_SelectAchievement(id)
                            end
                        end
                    end)

                    table.insert(achChild.rows, row)
                    yOffset = yOffset - 26
                    rowIndex = rowIndex + 1
                end
            end
        end
    end

    -- Eventos de filtros
    searchBox:SetScript("OnTextChanged", function(self)
        searchQuery = string.lower(self:GetText() or "")
        uiModule.RefreshAchievements()
    end)

    btnFilterAll:SetScript("OnClick", function() filterState = "TODOS"; uiModule.RefreshAchievements() end)
    btnFilterDone:SetScript("OnClick", function() filterState = "COMPLETADOS"; uiModule.RefreshAchievements() end)
    btnFilterPending:SetScript("OnClick", function() filterState = "PENDIENTES"; uiModule.RefreshAchievements() end)
    chkSeasonal:SetScript("OnClick", function(self) filterSeasonalOnly = self:GetChecked(); uiModule.RefreshAchievements() end)

    BuildGuildCategories()
    containers.views["Logros"] = view
end

-- =========================================================================
-- 8. VISTAS PLACEHOLDER (PARA COMPLETAR EN FUTUROS PASOS)
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
-- CONSTRUCCIÓN TOTAL DE LA UI
-- =========================================================================
function uiModule.CreateUI()
    if GC_UI then return end

    GC_UI = CreateFrame("Frame", "GuildControlMainFrame", UIParent, "BasicFrameTemplateWithInset")
    GC_UI:SetSize(1300, 650)
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
    BuildPlaceholderView(mainContent, "Configuracion")

    SwitchTab("Miembros")
    GC_UI:Hide()
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
    containers.header.membersText:SetText("Miembros: |cFF00FF00" .. total .. "|r")
    containers.header.onlineText:SetText("Online: |cFF00FFFF" .. online .. "|r")
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
        GC_UI:Show()
    end
end