local addonName, addonTable = ...

addonTable.CSV = {}
local csvModule = addonTable.CSV
local GC_CSVFrame = nil

function csvModule.GenerateCSVTotal()
    local csvLines = { "Nivel,Clase,Nombre,Rango,NotaPublica,Rol,Enfoque,Profesion1,Profesion2,Roster,Zona,UltimaConexion" }
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
    local csvLines = { "FechaHora,Personaje,Detalle" }
    for _, log in ipairs(GuildControlDB.history or {}) do
        if log.action == "BAJA" then
            table.insert(csvLines, string.format("%s,%s,%s", log.date or "-", log.name or "-", log.info or ""))
        end
    end
    return table.concat(csvLines, "\n")
end

function csvModule.GenerateCSVAltasHoy()
    local csvLines = { "FechaHora,Personaje,Detalle" }
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
    GC_CSVFrame.title:SetText("Exportar Google Sheets (CSV)")

    local scroll = CreateFrame("ScrollFrame", "GC_CSVScroll", GC_CSVFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", GC_CSVFrame, "TOPLEFT", 15, -40)
    scroll:SetPoint("BOTTOMRIGHT", GC_CSVFrame, "BOTTOMRIGHT", -35, 60)

    local editBox = CreateFrame("EditBox", "GC_CSVEditBox", scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(scroll:GetWidth())
    editBox:SetAutoFocus(false)
    scroll:SetScrollChild(editBox)

    local btnCSVTotal = CreateFrame("Button", nil, GC_CSVFrame, "UIPanelButtonTemplate")
    btnCSVTotal:SetSize(120, 22) btnCSVTotal:SetPoint("BOTTOMLEFT", GC_CSVFrame, "BOTTOMLEFT", 15, 35) btnCSVTotal:SetText("CSV Total")

    local btnCSVSalidas = CreateFrame("Button", nil, GC_CSVFrame, "UIPanelButtonTemplate")
    btnCSVSalidas:SetSize(120, 22) btnCSVSalidas:SetPoint("LEFT", btnCSVTotal, "RIGHT", 8, 0) btnCSVSalidas:SetText("CSV Salidas")

    local btnCSVAltas = CreateFrame("Button", nil, GC_CSVFrame, "UIPanelButtonTemplate")
    btnCSVAltas:SetSize(120, 22) btnCSVAltas:SetPoint("LEFT", btnCSVSalidas, "RIGHT", 8, 0) btnCSVAltas:SetText("CSV Altas Hoy")

    local btnCopy = CreateFrame("Button", nil, GC_CSVFrame, "UIPanelButtonTemplate")
    btnCopy:SetSize(90, 22) btnCopy:SetPoint("LEFT", btnCSVAltas, "RIGHT", 8, 0) btnCopy:SetText("Copiar")

    btnCSVTotal:SetScript("OnClick", function()
        if IsInGuild() then C_GuildInfo.GuildRoster() end
        editBox:SetText(csvModule.GenerateCSVTotal())
        editBox:HighlightText()
        editBox:SetFocus()
    end)

    btnCSVSalidas:SetScript("OnClick", function() editBox:SetText(csvModule.GenerateCSVSalidas()); editBox:HighlightText(); editBox:SetFocus() end)
    btnCSVAltas:SetScript("OnClick", function() editBox:SetText(csvModule.GenerateCSVAltasHoy()); editBox:HighlightText(); editBox:SetFocus() end)
    btnCopy:SetScript("OnClick", function() editBox:HighlightText(); editBox:SetFocus() end)
end

function csvModule.ShowFrame()
    if addonTable.UI.GetMainFrame then
        local mainUI = addonTable.UI.GetMainFrame()
        if mainUI then
            if not mainUI:IsShown() then mainUI:Show() end
            if GC_CSVFrame then GC_CSVFrame:Show() end
        end
    end
end