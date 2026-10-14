local addonName, addonTable = ...

addonTable.UI = {}
local uiModule = addonTable.UI

local GC_UI = nil
local GC_BajasFrame = nil
local memberCountText = nil
local searchBox = nil

local currentSearchQuery = ""
local currentSortField = "name"
local sortAscending = true
local showOnlyOnline = false

local function CreateInput(name, parent, width, xOffset, yOffset, placeholder)
    local editBox = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    editBox:SetSize(width, 20)
    editBox:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    editBox:SetAutoFocus(false)
    local text = editBox:CreateFontString(name .. "Text", "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("BOTTOMLEFT", editBox, "TOPLEFT", 0, 2)
    if placeholder and placeholder ~= "" then text:SetText(placeholder) end
    return editBox
end

local function CreateSectionBackdrop(parent, width, height, xOffset, yOffset)
    local val = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    val:SetSize(width, height)
    val:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    val:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    val:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    return val
end

function uiModule.GetMainFrame()
    return GC_UI
end

function uiModule.IsShown()
    return GC_UI and GC_UI:IsShown()
end

function uiModule.UpdateMemberCounter()
    if not memberCountText then return end
    local gameCount = IsInGuild() and GetNumGuildMembers() or 0
    local onlineCount = 0
    if IsInGuild() then
        for i = 1, gameCount do
            local _, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            if online == true or online == 1 or online == "true" then
                onlineCount = onlineCount + 1
            end
        end
    else
        for _, data in pairs(GuildControlDB.members or {}) do
            if data.isOnline then onlineCount = onlineCount + 1 end
        end
    end
    memberCountText:SetText(string.format("Miembros: |cFF00FF00%d|r | En línea: |cFF00FFFF%d|r", gameCount, onlineCount))
end

function uiModule.CreateBajasFrame()
    if GC_BajasFrame then return end
    GC_BajasFrame = CreateFrame("Frame", "GuildControlBajasFrame", GC_UI, "BasicFrameTemplateWithInset")
    GC_BajasFrame:SetSize(520, 380)
    GC_BajasFrame:SetPoint("CENTER", GC_UI, "CENTER", 0, 0)
    GC_BajasFrame:SetFrameStrata("DIALOG")
    GC_BajasFrame:Hide()

    GC_BajasFrame.title = GC_BajasFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    GC_BajasFrame.title:SetPoint("CENTER", GC_BajasFrame.TitleBg, "CENTER", 0, 0)
    GC_BajasFrame.title:SetText("Historial de Salidas / Bajas")

    local scroll = CreateFrame("ScrollFrame", nil, GC_BajasFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", GC_BajasFrame, "TOPLEFT", 15, -40)
    scroll:SetPoint("BOTTOMRIGHT", GC_BajasFrame, "BOTTOMRIGHT", -35, 15)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(scroll:GetWidth())
    editBox:SetAutoFocus(false)
    scroll:SetScrollChild(editBox)

    GC_BajasFrame.RefreshBajas = function()
        local bajasLogs = { "Fecha/Hora           | Personaje          | Detalle" }
        table.insert(bajasLogs, "------------------------------------------------------------------")
        local count = 0
        for _, log in ipairs(GuildControlDB.history or {}) do
            if log.action == "BAJA" then
                table.insert(bajasLogs, string.format("[%s]  %-18s  %s", log.date or "-", log.name or "-", log.info or ""))
                count = count + 1
            end
        end
        if count == 0 then table.insert(bajasLogs, "No hay registros de bajas aún.") end
        editBox:SetText(table.concat(bajasLogs, "\n"))
    end
end

function uiModule.ShowBajas()
    if GC_UI then
        GC_UI:Show()
        if GC_BajasFrame then
            GC_BajasFrame.RefreshBajas()
            GC_BajasFrame:Show()
        end
    end
end

function uiModule.CreateUI()
    if GC_UI then return end

    GC_UI = CreateFrame("Frame", "GuildControlMainFrame", UIParent, "BasicFrameTemplateWithInset")
    GC_UI:SetSize(1320, 710)
    GC_UI:SetPoint("CENTER")
    GC_UI:SetMovable(true)
    GC_UI:EnableMouse(true)
    GC_UI:RegisterForDrag("LeftButton")
    GC_UI:SetScript("OnDragStart", GC_UI.StartMoving)
    GC_UI:SetScript("OnDragStop", GC_UI.StopMovingOrSizing)
    
    GC_UI.title = GC_UI:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    GC_UI.title:SetPoint("CENTER", GC_UI.TitleBg, "CENTER", 0, 0)
    GC_UI.title:SetText("Control Guild Lobo Gélido")

    if addonTable.CSV and addonTable.CSV.CreateCSVFrame then
        addonTable.CSV.CreateCSVFrame(GC_UI)
    end
    uiModule.CreateBajasFrame()

    local formBg = CreateFrame("Frame", nil, GC_UI, "BackdropTemplate")
    formBg:SetSize(1280, 45)
    formBg:SetPoint("TOP", GC_UI, "TOP", 0, -35)
    formBg:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    formBg:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)

    local savePanel = CreateSectionBackdrop(formBg, 100, 37, 1165, -4)
    local btnCSV = CreateFrame("Button", nil, savePanel, "UIPanelButtonTemplate")
    btnCSV:SetSize(85, 22) btnCSV:SetPoint("CENTER", savePanel, "CENTER", 0, 0) btnCSV:SetText("Sheets/CSV")
    btnCSV:SetScript("OnClick", function()
        if addonTable.CSV and addonTable.CSV.ShowFrame then addonTable.CSV.ShowFrame() end
    end)

    local annBg = CreateFrame("Frame", nil, GC_UI, "BackdropTemplate")
    annBg:SetSize(1280, 65)
    annBg:SetPoint("TOP", formBg, "BOTTOM", 0, -4)
    annBg:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    annBg:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)

    local annTitle = annBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    annTitle:SetPoint("TOPLEFT", annBg, "TOPLEFT", 10, -4) 
    annTitle:SetText("Configuración de Anuncios Múltiples")

    local dropdownLabel = annBg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dropdownLabel:SetPoint("TOPLEFT", annBg, "TOPLEFT", 10, -22)
    dropdownLabel:SetText("Seleccionar:")

    local dropAnn = CreateFrame("DropdownButton", "GC_DropAnnSelect", annBg, "WowStyle1DropdownTemplate")
    dropAnn:SetPoint("TOPLEFT", dropdownLabel, "BOTTOMLEFT", 0, -2)
    dropAnn:SetWidth(130)

    local chkEnable = CreateFrame("CheckButton", "GC_AnnActiveChk", annBg, "UICheckButtonTemplate")
    chkEnable:SetPoint("TOPLEFT", annBg, "TOPLEFT", 160, -20)
    _G[chkEnable:GetName() .. "Text"]:SetText("Activar")

    local msgInput = CreateInput("GC_AnnMsgInput", annBg, 520, 240, -22, "Mensaje del anuncio...")
    local timeInput = CreateInput("GC_AnnTimeInput", annBg, 50, 780, -22, "Tiempo (Min)")
    timeInput:SetNumeric(true)

    local function RefreshAnnFields()
        if addonTable.Announcements then
            local data = addonTable.Announcements.GetAnnouncementData()
            if data then
                chkEnable:SetChecked(data.enabled)
                msgInput:SetText(data.message or "")
                timeInput:SetText(tostring(data.interval or 15))
            end
        end
    end

    dropAnn.RefreshMenu = function()
        dropAnn:SetupMenu(function(owner, rootDescription)
            for i = 1, 5 do
                rootDescription:CreateRadio("Mensaje " .. i, 
                    function() return addonTable.Announcements.GetSelectedIndex() == i end,
                    function() 
                        addonTable.Announcements.SetSelectedIndex(i)
                        RefreshAnnFields()
                    end
                )
            end
        end)
    end
    dropAnn.RefreshMenu()
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
            local val = tonumber(self:GetText()) or 15
            addonTable.Announcements.UpdateAnnouncementData(addonTable.Announcements.GetSelectedIndex(), nil, nil, val)
        end
    end)

    memberCountText = annBg:CreateFontString(nil, "OVERLAY", "GameFontNormalMed3")
    memberCountText:SetPoint("BOTTOMRIGHT", annBg, "BOTTOMRIGHT", -15, 6)
    memberCountText:SetJustifyH("RIGHT")

    local filterBg = CreateFrame("Frame", nil, GC_UI, "BackdropTemplate")
    filterBg:SetSize(1280, 35)
    filterBg:SetPoint("TOP", annBg, "BOTTOM", 0, -4)
    filterBg:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    filterBg:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    searchBox = CreateInput("GC_SearchBox", filterBg, 220, 10, -8, "Buscar por nombre...")
    searchBox:SetScript("OnTextChanged", function(self)
        currentSearchQuery = string.lower(self:GetText() or "")
        uiModule.RefreshList()
    end)

    local btnShowAll = CreateFrame("Button", nil, filterBg, "UIPanelButtonTemplate")
    btnShowAll:SetSize(90, 22)
    btnShowAll:SetPoint("LEFT", searchBox, "RIGHT", 15, 2)
    btnShowAll:SetText("Miembros")

    local btnShowOnline = CreateFrame("Button", nil, filterBg, "UIPanelButtonTemplate")
    btnShowOnline:SetSize(90, 22)
    btnShowOnline:SetPoint("LEFT", btnShowAll, "RIGHT", 8, 0)
    btnShowOnline:SetText("En línea")

    btnShowAll:SetScript("OnClick", function()
        showOnlyOnline = false
        btnShowAll:Disable()
        btnShowOnline:Enable()
        uiModule.RefreshList()
    end)

    btnShowOnline:SetScript("OnClick", function()
        showOnlyOnline = true
        btnShowOnline:Disable()
        btnShowAll:Enable()
        uiModule.RefreshList()
    end)
    btnShowAll:Disable()

    local headerBg = CreateFrame("Frame", nil, GC_UI)
    headerBg:SetSize(1280, 20)
    headerBg:SetPoint("TOP", filterBg, "BOTTOM", 0, -8)

    local function CreateSortableHeader(t, x, w, fieldKey)
        local btn = CreateFrame("Button", nil, headerBg)
        btn:SetSize(w, 20)
        btn:SetPoint("LEFT", headerBg, "LEFT", x, 0)
        
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", btn, "LEFT", 0, 0)
        fs:SetText(t)

        btn:SetScript("OnClick", function()
            if currentSortField == fieldKey then
                sortAscending = not sortAscending
            else
                currentSortField = fieldKey
                sortAscending = true
            end
            uiModule.RefreshList()
        end)
    end

    local numFs = headerBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    numFs:SetPoint("LEFT", headerBg, "LEFT", 5, 0) numFs:SetWidth(25) numFs:SetText("Nº")

    CreateSortableHeader("Nivel", 30, 35, "level")
    CreateSortableHeader("Clase", 65, 70, "class")
    CreateSortableHeader("Nombre", 135, 120, "name")
    CreateSortableHeader("Rango", 255, 90, "rank")
    CreateSortableHeader("Nota Pública", 345, 130, "publicNote")
    CreateSortableHeader("Rol", 475, 50, "role")
    CreateSortableHeader("Enfoque", 525, 55, "focus")
    CreateSortableHeader("Prof. 1", 580, 110, "prof1")
    CreateSortableHeader("Prof. 2", 690, 110, "prof2")
    CreateSortableHeader("Roster", 800, 90, "roster")
    CreateSortableHeader("Zona", 890, 110, "zone")
    CreateSortableHeader("Última Conexión", 1000, 100, "lastOnline")

    local scrollFrame = CreateFrame("ScrollFrame", "GC_ScrollFrame", GC_UI, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", headerBg, "BOTTOMLEFT", 0, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", GC_UI, "BOTTOMRIGHT", -35, 15)
    
    local scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(scrollFrame:GetWidth(), scrollFrame:GetHeight())
    scrollFrame:SetScrollChild(scrollChild)

    uiModule.RefreshList = function()
        if not scrollChild then return end
        if scrollChild.rows then for _, row in pairs(scrollChild.rows) do row:Hide() end end
        scrollChild.rows = {}

        local filteredList = {}
        for fullName, data in pairs(GuildControlDB.members or {}) do
            local passSearch = (currentSearchQuery == "") or string.find(string.lower(fullName), currentSearchQuery, 1, true)
            local passOnline = (not showOnlyOnline) or data.isOnline

            if passSearch and passOnline then
                table.insert(filteredList, { name = fullName, data = data })
            end
        end

        table.sort(filteredList, function(a, b)
            local valA, valB = "", ""
            if currentSortField == "name" then
                valA, valB = a.name, b.name
            elseif currentSortField == "level" then
                valA, valB = a.data.level or 0, b.data.level or 0
            elseif currentSortField == "class" then
                valA, valB = a.data.class or "", b.data.class or ""
            elseif currentSortField == "rank" then
                valA, valB = a.data.rank or "", b.data.rank or ""
            elseif currentSortField == "publicNote" then
                valA, valB = a.data.publicNote or "", b.data.publicNote or ""
            elseif currentSortField == "role" then
                valA, valB = a.data.role or "", b.data.role or ""
            elseif currentSortField == "focus" then
                valA, valB = a.data.focus or "", b.data.focus or ""
            elseif currentSortField == "prof1" then
                valA, valB = a.data.prof1 or "", b.data.prof1 or ""
            elseif currentSortField == "prof2" then
                valA, valB = a.data.prof2 or "", b.data.prof2 or ""
            elseif currentSortField == "roster" then
                valA, valB = a.data.roster or "", b.data.roster or ""
            elseif currentSortField == "zone" then
                valA, valB = a.data.zone or "", b.data.zone or ""
            elseif currentSortField == "lastOnline" then
                valA, valB = a.data.lastOnline or "", b.data.lastOnline or ""
            end

            if sortAscending then
                return valA < valB
            else
                return valA > valB
            end
        end)

        local yOffset, rowIndex = -5, 1
        for _, item in ipairs(filteredList) do
            local fullName, data = item.name, item.data
            local row = CreateFrame("Frame", nil, scrollChild)
            row:SetSize(1280, 22) row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)

            if rowIndex % 2 == 0 then
                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints() bg:SetColorTexture(1, 1, 1, 0.05)
            end

            local isOnline = data.isOnline
            local baseColorHex = isOnline and addonTable.GetClassColorHex(data.class) or "888888"

            local function CreateCell(t, x, w, colorHex)
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("LEFT", row, "LEFT", x, 0) fs:SetWidth(w) fs:SetJustifyH("LEFT")
                if colorHex then
                    fs:SetText("|cFF" .. colorHex .. tostring(t) .. "|r")
                else
                    fs:SetText(tostring(t))
                end
            end

            CreateCell(tostring(rowIndex), 5, 25, "888888")
            CreateCell(tostring(data.level or 0), 30, 35, baseColorHex)
            CreateCell(data.class or "Desconocida", 65, 70, baseColorHex)
            CreateCell(data.name or fullName, 135, 120, baseColorHex)
            
            local rankColor = isOnline and "FFFFFF" or "888888"
            CreateCell(data.rank or "Recluta", 255, 90, rankColor)
            CreateCell(data.publicNote or "", 345, 130, rankColor)
            
            local roleColor = "|cFF888888"
            if isOnline then
                if data.role == "DPS" then roleColor = "|cFFff7f7f"
                elseif data.role == "Healer" then roleColor = "|cFF7fff7f"
                elseif data.role == "Tank" then roleColor = "|cFF7f7fff"
                else roleColor = "|cFFFFFFFF" end
            end
            local roleFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            roleFs:SetPoint("LEFT", row, "LEFT", 475, 0) roleFs:SetWidth(50) roleFs:SetJustifyH("LEFT")
            roleFs:SetText(roleColor .. (data.role or "DPS") .. "|r")

            CreateCell(data.focus or "PvE", 525, 55, rankColor)
            CreateCell(data.prof1 or "Ninguna", 580, 110, rankColor)
            CreateCell(data.prof2 or "Ninguna", 690, 110, rankColor)
            CreateCell(data.roster or "Sin Roster", 800, 90, isOnline and "00ffff" or "888888")
            CreateCell(data.zone or "Desconocida", 890, 110, rankColor)
            
            local onlineTextHex = isOnline and "00FF00" or "888888"
            CreateCell(data.lastOnline or "Online", 1000, 100, onlineTextHex)

            table.insert(scrollChild.rows, row)
            yOffset = yOffset - 24
            rowIndex = rowIndex + 1
        end
        uiModule.UpdateMemberCounter()
    end

    RefreshAnnFields()
    GC_UI:Hide()
end

function uiModule.ToggleUI()
    addonTable.InitDB()
    if not GC_UI then uiModule.CreateUI() end
    if GC_UI:IsShown() then
        GC_UI:Hide()
        if addonTable.CSV and addonTable.CSV.GC_CSVFrame then addonTable.CSV.GC_CSVFrame:Hide() end
        if GC_BajasFrame then GC_BajasFrame:Hide() end
    else
        if IsInGuild() then
            C_GuildInfo.GuildRoster()
        end
        if addonTable.Professions and addonTable.Professions.RequestGuildProfessions then
            addonTable.Professions.RequestGuildProfessions()
        end
        if uiModule.RefreshList then uiModule.RefreshList() end
        if uiModule.UpdateMemberCounter then uiModule.UpdateMemberCounter() end
        GC_UI:Show()
    end
end