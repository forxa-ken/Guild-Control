local addonName, addonTable = ...
local L = addonTable.L

addonTable.CSV = {}
local csvModule = addonTable.CSV
local GC_CSVFrame = nil

function csvModule.GenerateCSVTotal()
    local csvLines = { L["Nivel,Clase,Nombre,Rango,NotaPublica,Rol,Enfoque,Profesion1,Profesion2,Roster,Zona,UltimaConexion"] }
    if IsInGuild() then
        local numMembers = GetNumGuildMembers()
        for i = 1, numMembers do
            local fullNameOfficial, rankName, _, level, _, zoneName, publicNote, _, _, _, classFileName = GetGuildRosterInfo(i)
            if fullNameOfficial then
                local data = GuildControlDB.members[fullNameOfficial] or {
                    role = "DPS", focus = "PvE", prof1 = "Ninguna", prof2 = "Ninguna", roster = "Sin Roster", zone = zoneName or "Desconocida", lastOnline = "Online"
                }
                local line = string.format("%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s",
                    level or data.level or 0, classFileName or data.class or "Desconocida",
                    fullNameOfficial, rankName or data.rank or "Recluta",
                    publicNote or data.publicNote or "",
                    data.role or "DPS", data.focus or "PvE", data.prof1 or "Ninguna",
                    data.prof2 or "Ninguna", data.roster or "Sin Roster", zoneName or data.zone or "Desconocida", data.lastOnline or "Online"
                )
                table.insert(csvLines, line)
            end
        end
    else
        for fullName, data in pairs(GuildControlDB.members) do
            local line = string.format("%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s",
                data.level or 0, data.class or "Desconocida",
                data.name or fullName, data.rank or "Recluta",
                data.publicNote or "",
                data.role or "DPS", data.focus or "PvE", data.prof1 or "Ninguna",
                data.prof2 or "Ninguna", data.roster or "Sin Roster", data.zone or "Desconocida", data.lastOnline or "Online"
            )
            table.insert(csvLines, line)
        end
    end
    return table.concat(csvLines, "\n")
end

function csvModule.GenerateCSVSalidas()
    local csvLines = { L["FechaHora,Personaje,Detalle"] }
    for _, log in ipairs(GuildControlDB.history or {}) do
        if log.action == "BAJA" then
            table.insert(csvLines, string.format("%s,%s,%s", log.date or "-", log.name or "-", log.info or ""))
        end
    end
    return table.concat(csvLines, "\n")
end

function csvModule.GenerateCSVAltasHoy()
    local csvLines = { L["FechaHora,Personaje,Detalle"] }
    local todayStr = date("%Y-%m-%d")
    for _, log in ipairs(GuildControlDB.history or {}) do
        if log.action == "ALTA" and log.date and string.sub(log.date, 1, 10) == todayStr then
            table.insert(csvLines, string.format("%s,%s,%s", log.date, log.name or "-", log.info or ""))
        end
    end
    return table.concat(csvLines, "\n")
end

function csvModule.CreateCSVFrame(parentUI)
    if GC_CSVFrame then return end
    GC_CSVFrame = CreateFrame("Frame", "GuildControlCSVFrame", parentUI, "BasicFrameTemplateWithInset")
    GC_CSVFrame:SetSize(600, 440)
    GC_CSVFrame:SetPoint("CENTER", parentUI, "CENTER", 0, 0)
    GC_CSVFrame:SetFrameStrata("DIALOG")
    GC_CSVFrame:Hide()

    GC_CSVFrame.title = GC_CSVFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    GC_CSVFrame.title:SetPoint("CENTER", GC_CSVFrame.TitleBg, "CENTER", 0, 0)
    GC_CSVFrame.title:SetText(L["Exportar Google Sheets (CSV)"])

    local scroll = CreateFrame("ScrollFrame", "GC_CSVScroll", GC_CSVFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", GC_CSVFrame, "TOPLEFT", 15, -40)
    scroll:SetPoint("BOTTOMRIGHT", GC_CSVFrame, "BOTTOMRIGHT", -35, 60)

    local editBox = CreateFrame("EditBox", "GC_CSVEditBox", scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    -- Ancho fijo (600 - 15 - 35): con el frame oculto scroll:GetWidth() puede devolver 0
    editBox:SetWidth(550)
    -- Sin altura el EditBox no recibe clics ni foco y no se puede seleccionar el texto
    editBox:SetHeight(330)
    editBox:SetMaxLetters(0)
    if editBox.SetMaxBytes then editBox:SetMaxBytes(0) end
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(editBox)

    -- WoW no permite a los addons escribir en el portapapeles: el texto se mantiene siempre
    -- seleccionado y con el foco puesto para que el jugador lo copie con Ctrl+C
    local currentText = ""

    local function SelectAll()
        editBox:SetFocus()
        editBox:HighlightText()
    end

    local function ShowCSV(text)
        currentText = text or ""
        editBox:SetText(currentText)
        editBox:SetCursorPosition(0)
        scroll:SetVerticalScroll(0)
        SelectAll()
    end

    -- Cualquier clic o intento de edición vuelve a dejar todo seleccionado
    editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    editBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(currentText)
            self:HighlightText()
        end
    end)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", SelectAll)

    local hintText = GC_CSVFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hintText:SetPoint("BOTTOMLEFT", GC_CSVFrame, "BOTTOMLEFT", 18, 14)
    hintText:SetTextColor(0.75, 0.75, 0.75)
    hintText:SetText(L["|cFF00FF00Texto seleccionado.|r Pulsa |cFFFFD100Ctrl+C|r para copiarlo y pégalo en Google Sheets."])

    local btnCSVTotal = CreateFrame("Button", nil, GC_CSVFrame, "UIPanelButtonTemplate")
    btnCSVTotal:SetSize(120, 22) btnCSVTotal:SetPoint("BOTTOMLEFT", GC_CSVFrame, "BOTTOMLEFT", 15, 35) btnCSVTotal:SetText(L["CSV Total"])

    local btnCSVSalidas = CreateFrame("Button", nil, GC_CSVFrame, "UIPanelButtonTemplate")
    btnCSVSalidas:SetSize(120, 22) btnCSVSalidas:SetPoint("LEFT", btnCSVTotal, "RIGHT", 8, 0) btnCSVSalidas:SetText(L["CSV Salidas"])

    local btnCSVAltas = CreateFrame("Button", nil, GC_CSVFrame, "UIPanelButtonTemplate")
    btnCSVAltas:SetSize(120, 22) btnCSVAltas:SetPoint("LEFT", btnCSVSalidas, "RIGHT", 8, 0) btnCSVAltas:SetText(L["CSV Altas Hoy"])

    local function ShowTotal()
        if IsInGuild() then C_GuildInfo.GuildRoster() end
        ShowCSV(csvModule.GenerateCSVTotal())
    end

    btnCSVTotal:SetScript("OnClick", ShowTotal)
    btnCSVSalidas:SetScript("OnClick", function() ShowCSV(csvModule.GenerateCSVSalidas()) end)
    btnCSVAltas:SetScript("OnClick", function() ShowCSV(csvModule.GenerateCSVAltasHoy()) end)

    -- Al abrir el panel: CSV Total si aún no hay nada y el texto seleccionado
    -- Para que otros módulos (p. ej. el roster) muestren su propio CSV
    GC_CSVFrame.ShowCSV = ShowCSV

    GC_CSVFrame:SetScript("OnShow", function()
        if currentText == "" then ShowTotal() else SelectAll() end
    end)
end

function csvModule.ShowFrame()
    if not addonTable.UI or not addonTable.UI.GetMainFrame then return end

    -- Abrir la ventana principal (la crea si aún no existe) porque el panel CSV cuelga de ella
    local mainUI = addonTable.UI.GetMainFrame()
    if (not mainUI or not mainUI:IsShown()) and addonTable.UI.ToggleUI then
        addonTable.UI.ToggleUI()
        mainUI = addonTable.UI.GetMainFrame()
    end
    if not mainUI then return end

    -- Creación perezosa: el frame se construye la primera vez que se pide
    csvModule.CreateCSVFrame(mainUI)
    if GC_CSVFrame then GC_CSVFrame:Show() end
end

-- Abre el panel con un texto CSV ya generado
function csvModule.ShowText(text)
    csvModule.ShowFrame()
    if GC_CSVFrame and GC_CSVFrame.ShowCSV then GC_CSVFrame.ShowCSV(text) end
end