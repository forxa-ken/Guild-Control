local addonTable = select(2, ...)
local L = addonTable.L

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
-- Ayuda que se muestra en la vista previa al entrar en algunas pestañas (texto en español,
-- se traduce al dibujar)
local TAB_HELP = {
    ["Botín"] = "|cFFFFD100Cómo funciona Botín (+1)|r\n"
        .. "\n|cFFB380FFObjetos de la banda|r\n"
        .. "|cFFFFD100•|r Salen solos al morir un jefe en grupo.\n"
        .. "|cFFFFD100•|r Shift+clic en un objeto para añadirlo.\n"
        .. "|cFFFFD100•|r Clic en uno para llevarlo a Tirada.\n"
        .. "\n|cFF40D959Tirada|r\n"
        .. "|cFFFFD100•|r El líder, un ayudante o un oficial pulsa Tirar.\n"
        .. "|cFFFFD100•|r Cada uno elige Necesidad (+1), Off-spec o Pasar y el addon tira el /roll.\n"
        .. "|cFFFFD100•|r Gana Necesidad con menos +1; si empatan, la tirada más alta.\n"
        .. "|cFFFFD100•|r Clic derecho en un jugador para asignárselo a mano.\n"
        .. "\n|cFF4080FF+1 de la hermandad|r\n"
        .. "|cFFFFD100•|r Ganar por Necesidad suma un +1 y se comparte con la hermandad.\n"
        .. "|cFFFFD100•|r Reiniciar +1 (dos clics) los pone a cero.\n"
        .. "\n|cFFFFBF33Historial de botín|r\n"
        .. "|cFFFFD100•|r Quién se llevó cada objeto.\n"
        .. "|cFFFFD100•|r \"Ya ganó\" avisa de quien ya se llevó algo en esta banda.\n"
        .. "\n|cFFFFD100•|r Nueva sesión empieza una banda nueva.",
}
-- En Botín con el sistema DKP se muestra esta otra ayuda
local TAB_HELP_DKP = {
    ["Botín"] = "|cFFFFD100Botín con DKP|r\n"
        .. "Los DKP son puntos: los ganas jugando con la hermandad y los gastas en objetos.\n"
        .. "\n|cFF40D959Cómo ganas DKP|r\n"
        .. "|cFFFFD100•|r Cada jefe que matáis en una banda programada en Raid.\n"
        .. "|cFFFFD100•|r Al acabar la banda (lo da un oficial).\n"
        .. "|cFFFFD100•|r Cada semana, por antigüedad (desde que rellenas Mi perfil).\n"
        .. "\n|cFFB380FFCómo consigues un objeto|r\n"
        .. "|cFFFFD1001.|r Sale un objeto y un oficial pulsa Tirar.\n"
        .. "|cFFFFD1002.|r Te sale una ventana: Main-spec si es para tu especialización principal u Off-spec si es para la otra (cuesta la mitad).\n"
        .. "|cFFFFD1003.|r Se lo lleva quien tenga más DKP. Main-spec va siempre antes que Off-spec.\n"
        .. "|cFFFFD1004.|r Al ganador se le restan los DKP del precio.\n"
        .. "\n|cFF4080FFPrecios|r\n"
        .. "|cFFFFD100•|r Dependen del tipo de pieza y de la dificultad: Normal, Heroica o Mítica.\n"
        .. "|cFFFFD100•|r Para pedir una pieza de dificultad Mítica tienes que tener ahorrado un mínimo de DKP (20 por defecto). Así nadie se queda en negativo con su primera pieza.\n"
        .. "|cFFFFD100•|r Solo puedes pedir un objeto si tienes los DKP de su precio (o de lo que cuesta como Off-spec).\n"
        .. "\n|cFFFF7F00Ten en cuenta|r\n"
        .. "|cFFFFD100•|r Cada semana los DKP bajan un poco (decay) para que nadie acumule demasiados.\n"
        .. "|cFFFFD100•|r Si hay empate de DKP, gana quien lleve más tiempo.\n"
        .. "\n|cFFFFBF33Solo oficiales: qué botones usan|r\n"
        .. "|cFFFFD100•|r Precios: editar la tabla de precios.\n"
        .. "|cFFFFD100•|r Precio: cambiar el precio de un objeto concreto.\n"
        .. "|cFFFFD100•|r Clic derecho en un jugador de la lista: sumarle o restarle DKP.\n"
        .. "|cFFFFD100•|r Ajustes: puntos por jefe y por banda, decay, mínimos y cambiar a subasta.",
}

local function TabHelp(tabName)
    if TAB_HELP_DKP[tabName] and addonTable.Loot and addonTable.Loot.IsDkp and addonTable.Loot.IsDkp() then
        return TAB_HELP_DKP[tabName]
    end
    return TAB_HELP[tabName]
end

-- Pestañas del menú lateral en grupos plegables (el primero, sin nombre, va siempre abierto).
-- Se pueden abrir varios a la vez (settings.sidebarOpen[grupo]); el de la pestaña activa se abre solo.
local SIDEBAR_TABS = {
    { tabs = { "Resumen" } },
    { name = "General", tabs = { "Miembros", "Favoritos", "Logros" } },
    { name = "Banda", tabs = { "Raid", "Roster", "Botín" } },
    { name = "Comunidad", tabs = { "Profesiones", "Míticas+" } },
    { name = "Personal", tabs = { "Mi perfil", "Para mí" } },
    { name = "Gestión", tabs = { "Warning", "Invitar", "Black list" } },
}
-- Nombre que se ve en el menú cuando no coincide con la clave de la pestaña
local TAB_LABELS = { ["Para mí"] = "Mi diario" }

-- Shift+clic en un objeto (bolsas, chat, enlaces): el juego llama a la función de insertar
-- enlaces en el chat. Forever usa la moderna (ChatFrameUtil.InsertLink) y quizá también la
-- antigua (ChatEdit_InsertLink), así que se escuchan las dos y se avisa una sola vez. Las cajas
-- de texto del addon (buscadores, chat, lista de deseos) se apuntan con OnInsertLink.
local insertLinkListeners = {}
local lastInsertedLink, lastInsertedAt = nil, -1
local function DispatchInsertLink(link)
    if type(link) ~= "string" then return end
    if link == lastInsertedLink and GetTime() == lastInsertedAt then return end
    lastInsertedLink, lastInsertedAt = link, GetTime()
    for _, fn in ipairs(insertLinkListeners) do pcall(fn, link) end
end
if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", DispatchInsertLink) end
if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", DispatchInsertLink) end
local function OnInsertLink(fn)
    table.insert(insertLinkListeners, fn)
end

-- Tooltip con título y explicación (también con el botón desactivado). Si el control ya tiene
-- un OnEnter (las plantillas de Blizzard traen uno, como UIPanelButtonTemplate en Forever) se
-- añade con HookScript para no quitarle el resaltado. tips = { {control, "Título", "Texto"}, ... }
-- (textos sin traducir)
function uiModule.AddTips(tips)
    for _, tip in ipairs(tips) do
        local widget, titleText, text = tip[1], tip[2], tip[3]
        if widget and not widget.gcTip then
            widget.gcTip = true
            if widget.SetMotionScriptsWhileDisabled then widget:SetMotionScriptsWhileDisabled(true) end
            local function OnEnter(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(L[titleText], 1, 1, 1)
                GameTooltip:AddLine(L[text], 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end
            local function OnLeave() GameTooltip:Hide() end
            if widget:GetScript("OnEnter") then
                widget:HookScript("OnEnter", OnEnter)
                widget:HookScript("OnLeave", OnLeave)
            else
                widget:SetScript("OnEnter", OnEnter)
                widget:SetScript("OnLeave", OnLeave)
            end
        end
    end
end
local OFFICER_ONLY_TABS = { ["Roster"] = true, ["Warning"] = true, ["Invitar"] = true, ["Black list"] = true }
local PLAYER_ONLY_TABS = { ["Mis rosters"] = true }   -- los oficiales ya tienen la pestaña Roster completa

-- ¿Ve este perfil la pestaña? Invitar también la ven los jugadores si un oficial lo permite
local function IsTabAllowed(tabName, isOfficer)
    if isOfficer then return not PLAYER_ONLY_TABS[tabName] end
    if tabName == "Invitar" and GuildControlDB.settings and GuildControlDB.settings.playerInvite then return true end
    return not OFFICER_ONLY_TABS[tabName]
end

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

-- Panel con borde, fondo suave y franja de cabecera de un color (Mi perfil y otras vistas)
local PANEL_COLORS = {
    blue = { 0.25, 0.5, 1 }, green = { 0.25, 0.85, 0.35 }, red = { 0.95, 0.3, 0.3 }, gold = { 1, 0.75, 0.2 },
    purple = { 0.7, 0.4, 1 }, cyan = { 0.2, 0.85, 0.9 }, grey = { 0.6, 0.6, 0.6 },
}
local function CreateColoredPanel(parent, titleText, color, width, height)
    local panel = CreateBackdropBox(parent, width, height)
    panel:SetBackdropBorderColor(color[1], color[2], color[3], 0.9)
    panel.tint = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    panel.tint:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -3)
    panel.tint:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, 3)
    panel.tint:SetColorTexture(color[1], color[2], color[3], 0.06)
    panel.header = panel:CreateTexture(nil, "ARTWORK")
    panel.header:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -3)
    panel.header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -3)
    panel.header:SetHeight(21)
    panel.header:SetColorTexture(color[1], color[2], color[3], 0.25)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("LEFT", panel.header, "LEFT", 8, 0)
    panel.title:SetText(titleText)
    return panel
end

-- Icono de la hermandad: una textura o el emblema (tabardo) que la hermandad tiene en el
-- juego, que son tres capas. holder:SetGuildIcon(value) con value = "tabard", fileID o ruta.
local function CreateGuildIconHolder(parent, size)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    holder.icon = holder:CreateTexture(nil, "ARTWORK")
    holder.icon:SetAllPoints()
    holder.tabardBg = holder:CreateTexture(nil, "ARTWORK", nil, 1)
    holder.tabardBg:SetAllPoints()
    holder.tabardEmblem = holder:CreateTexture(nil, "ARTWORK", nil, 2)
    holder.tabardEmblem:SetPoint("CENTER")
    holder.tabardEmblem:SetSize(size * 0.75, size * 0.75)
    holder.tabardBorder = holder:CreateTexture(nil, "ARTWORK", nil, 3)
    holder.tabardBorder:SetAllPoints()
    function holder:SetGuildIcon(value)
        local useTabard = false
        if value == "tabard" and IsInGuild() and SetLargeGuildTabardTextures then
            useTabard = pcall(SetLargeGuildTabardTextures, "player", self.tabardEmblem, self.tabardBg, self.tabardBorder)
        end
        for _, tex in ipairs({ self.tabardBg, self.tabardEmblem, self.tabardBorder }) do tex:SetShown(useTabard) end
        self.icon:SetShown(not useTabard)
        if not useTabard then
            self.icon:SetTexture(addonTable.ResolveIconTexture(value == "tabard" and "Achievement_GuildPerk_MobileBanking" or value))
        end
    end
    return holder
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

    local logo = CreateGuildIconHolder(header, 44)
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
    btnDiscord:SetText(L["Discord"])
    btnDiscord:SetMotionScriptsWhileDisabled(true)
    -- Siempre visible: con enlace lo muestra para copiar; sin él, un oficial va a Configuración
    -- a ponerlo y un jugador ve que aún no hay
    btnDiscord:SetScript("OnClick", function()
        if (GuildControlDB.settings.discordLink or "") ~= "" then
            uiModule.ShowDiscordCopy()
        elseif not addonTable.Profiles or addonTable.Profiles.IsOfficer() then
            uiModule.SwitchTab("Configuracion")
        end
    end)
    btnDiscord:SetScript("OnEnter", function(self)
        local link = GuildControlDB.settings.discordLink or ""
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Discord de la hermandad"], 1, 1, 1)
        if link ~= "" then
            GameTooltip:AddLine(link, 0.6, 0.8, 1)
            GameTooltip:AddLine(L["Clic para copiar el enlace"], 0.7, 0.7, 0.7)
        elseif not addonTable.Profiles or addonTable.Profiles.IsOfficer() then
            GameTooltip:AddLine(L["Todavía no hay enlace. Clic para ponerlo en Configuración > Hermandad."], 0.7, 0.7, 0.7, true)
        else
            GameTooltip:AddLine(L["Los oficiales todavía no han puesto el enlace de Discord."], 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    btnDiscord:SetScript("OnLeave", function() GameTooltip:Hide() end)
    header.btnDiscord = btnDiscord

    -- Cajas de estadísticas alineadas a la derecha
    local statWidth, statGap = 170, 6
    local onlineBox = CreateStatBox(header, L["En línea"], statWidth)
    onlineBox:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    header.onlineBox = onlineBox

    local membersBox = CreateStatBox(header, L["Miembros"], statWidth)
    membersBox:SetPoint("RIGHT", onlineBox, "LEFT", -statGap, 0)
    header.membersBox = membersBox

    local warningsBox = CreateStatBox(header, L["Warnings"], statWidth)
    warningsBox:SetPoint("RIGHT", membersBox, "LEFT", -statGap, 0)
    warningsBox.value:SetTextColor(1, 0.25, 0.25)
    -- Clic: abre la pestaña Warning (solo la ven los oficiales; ApplyProfile la oculta a los jugadores)
    warningsBox:EnableMouse(true)
    warningsBox.highlight = warningsBox:CreateTexture(nil, "HIGHLIGHT")
    warningsBox.highlight:SetAllPoints()
    warningsBox.highlight:SetColorTexture(1, 1, 1, 0.06)
    warningsBox:SetScript("OnMouseUp", function()
        if uiModule.SwitchTab then uiModule.SwitchTab("Warning") end
    end)
    warningsBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Warnings"], 1, 1, 1)
        GameTooltip:AddLine(L["Inactivos y miembros en la lista negra. Clic para abrir Warning."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    warningsBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    header.warningsBox = warningsBox

    local verText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    verText:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -30, -6)
    verText:SetText("v" .. addonTable.VERSION)

    local authorText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    authorText:SetPoint("RIGHT", verText, "LEFT", -12, 0)
    authorText:SetText(L["|cFF808080Autor:|r Forxaken"])

    -- Donación al autor del addon
    local btnDonate = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    btnDonate:SetSize(78, 18)
    btnDonate:SetPoint("RIGHT", authorText, "LEFT", -10, 0)
    btnDonate:SetText("|TInterface\\Icons\\INV_Misc_Coin_01:12:12|t " .. L["Donar"])
    btnDonate:GetFontString():SetFontObject("GameFontHighlightSmall")
    btnDonate:SetScript("OnClick", function() uiModule.ShowDonate() end)
    btnDonate:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Apoya GuildControl"], 1, 1, 1)
        GameTooltip:AddLine(L["Si el addon te ayuda con tu hermandad, puedes invitar al autor a un café."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnDonate:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Más addons del autor: su perfil de CurseForge
    local btnMore = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    btnMore:SetSize(100, 18)
    btnMore:SetPoint("RIGHT", btnDonate, "LEFT", -6, 0)
    btnMore:SetText("|TInterface\\Icons\\INV_Misc_Book_09:12:12|t " .. L["Más addons"])
    btnMore:GetFontString():SetFontObject("GameFontHighlightSmall")
    btnMore:SetScript("OnClick", function() uiModule.ShowCopyLink(L["Más addons del autor"], addonTable.MORE_ADDONS_URL) end)
    btnMore:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Más addons del autor"], 1, 1, 1)
        GameTooltip:AddLine(L["Muestra el perfil de CurseForge del autor para descargar sus otros addons."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnMore:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Tamaño de la ventana: se ajusta a la pantalla y cada uno lo agranda o achica (settings.windowScale)
    local btnSize = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    btnSize:SetSize(78, 18)
    btnSize:SetPoint("RIGHT", btnMore, "LEFT", -6, 0)
    btnSize:SetText(L["Tamaño"])
    btnSize:GetFontString():SetFontObject("GameFontHighlightSmall")
    btnSize:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle(L["Tamaño de la ventana"])
            for _, pct in ipairs({ 60, 70, 80, 90, 100, 110, 120 }) do
                root:CreateRadio(pct == 100 and L["100% (ajustado a la pantalla)"] or (pct .. "%"),
                    function() return (GuildControlDB.settings.windowScale or 100) == pct end,
                    function()
                        GuildControlDB.settings.windowScale = pct
                        uiModule.ApplyWindowScale()
                    end)
            end
        end)
    end)
    btnSize:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Tamaño de la ventana"], 1, 1, 1)
        GameTooltip:AddLine(L["La ventana se ajusta sola a la pantalla en la que juegas. Aquí la puedes hacer más pequeña o más grande."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnSize:SetScript("OnLeave", function() GameTooltip:Hide() end)

    containers.header = header
    uiModule.UpdateHeader()
end

-- Aplica el icono que definieron los oficiales y el nombre de la hermandad del juego
function uiModule.UpdateHeader()
    local header = containers.header
    if not header then return end
    local settings = GuildControlDB.settings or {}

    header.logo:SetGuildIcon(settings.guildIcon)
    header.titleText:SetText("|cFFFFD100" .. addonTable.GetDisplayGuildName() .. "|r")

    -- Reino de la hermandad (GetGuildInfo lo da si es distinto del del personaje) y facción
    local parts = {}
    local guildRealm = IsInGuild() and select(4, GetGuildInfo("player")) or nil
    table.insert(parts, L["Reino: |cFFFFFFFF"] .. (guildRealm or GetRealmName() or "-") .. "|r")
    local _, localizedFaction = UnitFactionGroup("player")
    if localizedFaction then table.insert(parts, L["Facción: |cFFFFFFFF"] .. localizedFaction .. "|r") end
    header.subText:SetText(table.concat(parts, L["   ·   "]))

    -- El botón de Discord siempre está; sin enlace, en gris para los jugadores
    local hasDiscord = (settings.discordLink or "") ~= ""
    header.btnDiscord:Show()
    header.btnDiscord:SetEnabled(hasDiscord or not addonTable.Profiles or addonTable.Profiles.IsOfficer())
end

-- Ventanita con un enlace seleccionado para copiarlo con Ctrl+C (Discord, donación...)
local GC_DiscordFrame = nil
function uiModule.ShowCopyLink(titleText, link)
    if not link or link == "" or not GC_UI then return end
    if not GC_DiscordFrame then
        local frame = CreateFrame("Frame", "GuildControlDiscordFrame", GC_UI, "BasicFrameTemplateWithInset")
        frame:SetSize(420, 110)
        frame:SetPoint("TOP", GC_UI, "TOP", 0, -100)
        frame:SetFrameStrata("DIALOG")
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)

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
        hint:SetText(L["|cFF00FF00Enlace seleccionado.|r Pulsa |cFFFFD100Ctrl+C|r para copiarlo."])
        GC_DiscordFrame = frame
    end
    GC_DiscordFrame.link = link
    GC_DiscordFrame.title:SetText(titleText)
    GC_DiscordFrame:Show()
    GC_DiscordFrame.edit:SetText(link)
    GC_DiscordFrame.edit:SetFocus()
    GC_DiscordFrame.edit:HighlightText()
end

function uiModule.ShowDiscordCopy()
    uiModule.ShowCopyLink(L["Discord de la hermandad"], GuildControlDB.settings.discordLink)
end

function uiModule.ShowDonate()
    if (addonTable.DONATE_URL or "") == "" then
        print("|cFF00FFFF[GuildControl]|r " .. L["Gracias por querer apoyar GuildControl. El enlace de donación aún no está disponible."])
        return
    end
    uiModule.ShowCopyLink(L["Apoya GuildControl"], addonTable.DONATE_URL)
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

    local slotBox = CreateCellBox(annBar, L["Anuncio"], slotWidth)
    slotBox:SetPoint("LEFT", annBar, "LEFT", gap, 0)

    local msgBox = CreateCellBox(annBar, L["Texto que se publica en el chat de hermandad"], msgWidth)
    msgBox:SetPoint("LEFT", slotBox, "RIGHT", gap, 0)

    local timeBox = CreateCellBox(annBar, L["Intervalo (min)"], timeWidth)
    timeBox:SetPoint("LEFT", msgBox, "RIGHT", gap, 0)

    local stateBox = CreateCellBox(annBar, L["Estado"], stateWidth)
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
    _G[chkEnable:GetName() .. "Text"]:SetText(L["Activar"])

    -- La etiqueta de la caja Estado indica si el anuncio seleccionado se está publicando
    local function UpdateStateLabel(enabled)
        if enabled then
            stateBox.label:SetText(L["|cFF00FF00Publicando|r"])
        else
            stateBox.label:SetText(L["Desactivado"])
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
            rootDescription:CreateRadio(L["Mensaje "] .. i,
                function() return addonTable.Announcements and addonTable.Announcements.GetSelectedIndex() == i end,
                function()
                    if addonTable.Announcements then addonTable.Announcements.SetSelectedIndex(i) end
                    RefreshFields()
                end
            )
        end
    end)
    dropAnn:SetText(L["Mensaje 1"])

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
    -- Llega un cambio de otro oficial (Announcements.lua): sin pisar lo que se está escribiendo
    function uiModule.RefreshAnnouncementFields()
        if msgInput:HasFocus() or timeInput:HasFocus() then return end
        RefreshFields()
    end

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
        or L["|cFFFF7F00sin declarar (ve a Mi perfil)|r"]
    -- Los rosters del jugador vienen de los que publican los oficiales
    local rosterNames = uiModule.GetMySharedRosterNames and uiModule.GetMySharedRosterNames() or {}
    local rosterText = #rosterNames > 0 and table.concat(rosterNames, ", ") or L["ninguno publicado"]
    annBar.playerInfo.text:SetText(L["|cFF00FFFFPerfil de jugador|r   ·   Rango: |cFFFFD100"] .. (m.rank or "-")
        .. L["|r   ·   Tu rol: "] .. roleText .. L["   ·   Rosters: |cFFFFD100"] .. rosterText .. "|r")
end

-- =========================================================================
-- 3. CAMBIO DE PESTAÑAS Y NAVEGACIÓN
-- =========================================================================
local function SetPreviewText(text)
    if containers.preview and containers.preview.infoText then
        -- Cada vista previa nueva empieza sin la cabecera de personaje
        if containers.preview.SetCharacter then containers.preview.SetCharacter(nil) end
        containers.preview.infoText:SetText(text or L[PREVIEW_DEFAULT_TEXT])
        if containers.preview.UpdateScroll then containers.preview.UpdateScroll() end
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
    -- Botín abierto en su ventana flotante: vuelve a la ventana principal
    if tabName == "Botín" and uiModule.HideLootFloat then uiModule.HideLootFloat() end
    -- El botón de la pestaña activa se ve gris (desactivado)
    local sidebar = containers.sidebar
    if sidebar and sidebar.tabButtons then
        for name, btn in pairs(sidebar.tabButtons) do btn:SetEnabled(name ~= tabName) end
        if sidebar.btnConfig then sidebar.btnConfig:SetEnabled(tabName ~= "Configuracion") end
        if sidebar.OpenGroupOf then sidebar.OpenGroupOf(tabName) end
    end
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
    SetPreviewText(L[TabHelp(tabName) or PREVIEW_DEFAULT_TEXT])

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
uiModule.SwitchTab = SwitchTab

-- =========================================================================
-- 4. MENÚ LATERAL IZQUIERDO (SIDEBAR)
-- =========================================================================
local function BuildSidebar(parent)
    local sidebar = CreateBackdropBox(parent, 150, 520, "TOPLEFT", containers.announcements, "BOTTOMLEFT", 0, -5)

    -- Los botones se crean todos y Layout decide cuáles se ven y en qué posición. Medidas
    -- compactas para que quepan todos los grupos abiertos.
    local HEADER_H, HEADER_STEP, TAB_H, TAB_STEP = 16, 18, 19, 20   -- Retail: 14 pestañas en grupos (con Logros y Míticas+)
    local function OpenGroups()
        local st = GuildControlDB.settings
        if type(st.sidebarOpen) ~= "table" then st.sidebarOpen = {} end
        return st.sidebarOpen
    end
    sidebar.tabButtons = {}
    sidebar.groupHeaders = {}
    for _, group in ipairs(SIDEBAR_TABS) do
        if group.name then
            -- Cabecera del grupo: clic para abrirlo o cerrarlo (los demás no cambian)
            local header = CreateFrame("Button", nil, sidebar)
            header:SetSize(134, HEADER_H)
            header.bg = header:CreateTexture(nil, "BACKGROUND")
            header.bg:SetAllPoints()
            header.bg:SetColorTexture(0, 0, 0, 0.75)
            header:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
            header.icon = header:CreateTexture(nil, "ARTWORK")
            header.icon:SetSize(12, 12)
            header.icon:SetPoint("LEFT", header, "LEFT", 4, 0)
            header.label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            header.label:SetPoint("LEFT", header.icon, "RIGHT", 4, 0)
            header.label:SetText(L[group.name])
            header:SetScript("OnClick", function()
                local open = OpenGroups()
                open[group.name] = not open[group.name] or nil
                sidebar.Layout()
            end)
            sidebar.groupHeaders[group.name] = header
        end
        for _, tabName in ipairs(group.tabs) do
            local btn = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
            btn:SetSize(group.name and 122 or 130, group.name and TAB_H or 20)
            btn:SetText(L[TAB_LABELS[tabName] or tabName])
            btn:SetScript("OnClick", function() SwitchTab(tabName) end)
            sidebar.tabButtons[tabName] = btn
        end
    end

    -- Expandir todo / Contraer todo
    local btnExpand = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    btnExpand:SetSize(130, 18)
    btnExpand:SetNormalFontObject(GameFontHighlightSmall)
    btnExpand:SetHighlightFontObject(GameFontHighlightSmall)
    local function AllOpen()
        local open = OpenGroups()
        for _, group in ipairs(SIDEBAR_TABS) do
            if group.name and not open[group.name] then return false end
        end
        return true
    end
    btnExpand:SetScript("OnClick", function()
        local open, expand = OpenGroups(), not AllOpen()
        for _, group in ipairs(SIDEBAR_TABS) do
            if group.name then open[group.name] = expand or nil end
        end
        sidebar.Layout()
    end)
    uiModule.AddTips({ { btnExpand, "Expandir todo", "Abre o cierra todos los grupos del menú. Cada grupo también se abre o se cierra con un clic en su nombre." } })

    -- Abre el grupo de una pestaña (al cambiar de pestaña)
    function sidebar.OpenGroupOf(tabName)
        for _, group in ipairs(SIDEBAR_TABS) do
            for _, name in ipairs(group.tabs) do
                if name == tabName then
                    if group.name and not OpenGroups()[group.name] then
                        OpenGroups()[group.name] = true
                        sidebar.Layout()
                    end
                    return
                end
            end
        end
    end

    -- Coloca cabeceras y botones según el perfil (oficial o jugador) y los grupos abiertos
    function sidebar.Layout()
        local isOfficer = not addonTable.Profiles or addonTable.Profiles.IsOfficer()
        local openGroups = OpenGroups()
        local y = -8
        for _, group in ipairs(SIDEBAR_TABS) do
            local allowed = {}
            for _, tabName in ipairs(group.tabs) do
                if IsTabAllowed(tabName, isOfficer) then table.insert(allowed, tabName) end
                sidebar.tabButtons[tabName]:Hide()
            end
            local header = group.name and sidebar.groupHeaders[group.name]
            local open = not group.name or openGroups[group.name]
            if header then
                header:SetShown(#allowed > 0)
                if #allowed > 0 then
                    header:ClearAllPoints()
                    header:SetPoint("TOP", sidebar, "TOP", 0, y)
                    header.icon:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
                    y = y - HEADER_STEP
                end
            end
            if open then
                for _, tabName in ipairs(allowed) do
                    local btn = sidebar.tabButtons[tabName]
                    btn:ClearAllPoints()
                    btn:SetPoint("TOP", sidebar, "TOP", group.name and 6 or 0, y)
                    btn:Show()
                    y = y - (group.name and TAB_STEP or 22)
                end
                if group.name and #allowed > 0 then y = y - 2 end
            end
            if not group.name then
                -- Debajo de Resumen: Expandir todo
                btnExpand:ClearAllPoints()
                btnExpand:SetPoint("TOP", sidebar, "TOP", 0, y)
                y = y - 22
            end
        end
        btnExpand:SetText(AllOpen() and L["Contraer todo"] or L["Expandir todo"])
    end

    sidebar.profileText = sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sidebar.profileText:SetPoint("BOTTOM", sidebar, "BOTTOM", 0, 46)

    local btnConfig = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
    btnConfig:SetSize(130, 25)
    btnConfig:SetPoint("BOTTOM", sidebar, "BOTTOM", 0, 15)
    btnConfig:SetText(L["Configuración"])
    btnConfig:SetScript("OnClick", function() SwitchTab("Configuracion") end)
    sidebar.btnConfig = btnConfig

    -- Botón Desarrollador: solo existe en la copia del autor (la carpeta Dev/ no se empaqueta)
    if addonTable.Dev and addonTable.Dev.CreateButton then addonTable.Dev.CreateButton(sidebar) end

    containers.sidebar = sidebar
end

-- Muestra solo las pestañas del perfil actual (oficial o jugador)
function uiModule.ApplyProfile()
    local sidebar = containers.sidebar
    if not sidebar then return end
    if uiModule.RefreshChatTabs then uiModule.RefreshChatTabs() end   -- pestaña Oficiales
    local isOfficer = not addonTable.Profiles or addonTable.Profiles.IsOfficer()
    if containers.header and containers.header.warningsBox then
        containers.header.warningsBox:SetShown(isOfficer)
    end

    sidebar.Layout()
    sidebar.profileText:SetText(isOfficer and L["Perfil: |cFFFFD100Oficial|r"] or L["Perfil: |cFF00FFFFJugador|r"])

    -- La barra de anuncios es de oficiales; los jugadores ven un resumen de su ficha
    if containers.announcements then
        for _, child in ipairs({ containers.announcements:GetChildren() }) do child:SetShown(isOfficer) end
        if containers.announcements.playerInfo then
            containers.announcements.playerInfo:SetShown(not isOfficer)
            if not isOfficer and uiModule.UpdatePlayerInfoBar then uiModule.UpdatePlayerInfoBar() end
        end
    end

    if containers.views[activeTab] and not IsTabAllowed(activeTab, isOfficer) then SwitchTab("Miembros") end
end

-- =========================================================================
-- 5. PANEL LATERAL DERECHO (PREVIEW)
-- =========================================================================
local function BuildPreviewPanel(parent)
    local preview = CreateBackdropBox(parent, 220, 520, "TOPRIGHT", containers.announcements, "BOTTOMRIGHT", 0, -5)

    local title = preview:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", preview, "TOP", 0, -15)
    title:SetText(L["Vista Previa"])

    -- El texto va dentro de un área con desplazamiento: si no cabe sale la barra (rueda del ratón)
    local scroll = CreateFrame("ScrollFrame", nil, preview, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", preview, "TOPLEFT", 12, -45)
    scroll:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -28, 44)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(178, 1)
    scroll:SetScrollChild(child)

    local infoText = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", child, "TOPLEFT", 2, 0)
    infoText:SetWidth(174)
    infoText:SetJustifyH("LEFT")
    infoText:SetJustifyV("TOP")

    -- Bloque opcional sobre el texto (vista previa de un miembro): cabecera del personaje,
    -- fila de insignias y etiquetas (rosters). preview.SetCharacter(nil) lo oculta.
    local head = CreateFrame("Frame", nil, child)
    head:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    head:SetSize(176, 64)
    head:Hide()
    head.bg = head:CreateTexture(nil, "BACKGROUND")
    head.bg:SetAllPoints()
    head.bar = head:CreateTexture(nil, "ARTWORK")
    head.bar:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
    head.bar:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
    head.bar:SetWidth(3)
    head.icon = head:CreateTexture(nil, "ARTWORK")
    head.icon:SetSize(34, 34)
    head.icon:SetPoint("TOPLEFT", head, "TOPLEFT", 8, -7)
    head.name = head:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    head.name:SetPoint("TOPLEFT", head.icon, "TOPRIGHT", 7, 0)
    head.name:SetPoint("RIGHT", head, "RIGHT", -4, 0)
    head.name:SetJustifyH("LEFT")
    head.name:SetWordWrap(false)
    head.info = head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    head.info:SetPoint("TOPLEFT", head.name, "BOTTOMLEFT", 0, -2)
    head.info:SetPoint("RIGHT", head, "RIGHT", -4, 0)
    head.info:SetJustifyH("LEFT")
    head.info:SetWordWrap(false)
    head.rank = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    head.rank:SetPoint("TOPLEFT", head.info, "BOTTOMLEFT", 0, -2)
    head.rank:SetPoint("RIGHT", head, "RIGHT", -4, 0)
    head.rank:SetJustifyH("LEFT")
    head.rank:SetWordWrap(false)
    head.status = head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    head.status:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 8, 5)
    head.status:SetPoint("RIGHT", head, "RIGHT", -4, 0)
    head.status:SetJustifyH("LEFT")
    head.status:SetWordWrap(false)
    head.badgeButtons, head.tagButtons = {}, {}
    head.tagsTitle = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    head.tagsTitle:Hide()

    local function PooledButton(pool, i, withBg)
        local btn = pool[i]
        if btn then return btn end
        btn = CreateFrame("Button", nil, child)
        if withBg then
            btn.bg = btn:CreateTexture(nil, "BACKGROUND")
            btn.bg:SetAllPoints()
            btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.text:SetPoint("CENTER")
            btn:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight", "ADD")
        else
            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetAllPoints()
        end
        btn:SetScript("OnEnter", function(self)
            if not self.tipTitle then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(self.tipTitle, 1, 0.82, 0)
            if self.tipText and self.tipText ~= "" then GameTooltip:AddLine(self.tipText, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
        pool[i] = btn
        return btn
    end

    -- info = { name, classFile, className, level, rank, statusText, badges = { {icon, label, desc} },
    --          tagsTitle, tags = { {text, color = {r, g, b}, tip, onClick} } }
    function preview.SetCharacter(info)
        for _, btn in ipairs(head.badgeButtons) do btn:Hide() end
        for _, btn in ipairs(head.tagButtons) do btn:Hide() end
        head.tagsTitle:Hide()
        head:SetShown(info ~= nil)
        infoText:ClearAllPoints()
        if not info then
            infoText:SetPoint("TOPLEFT", child, "TOPLEFT", 2, 0)
            return
        end
        local c = info.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.classFile]
        local r, g, b = c and c.r or 0.6, c and c.g or 0.6, c and c.b or 0.6
        head.bg:SetColorTexture(1, 1, 1, 1)
        local ok = CreateColor and pcall(head.bg.SetGradient, head.bg, "HORIZONTAL", CreateColor(r, g, b, 0.3), CreateColor(r, g, b, 0.05))
        if not ok then head.bg:SetColorTexture(r, g, b, 0.18) end
        head.bar:SetColorTexture(r, g, b, 0.9)
        local coords = info.classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[info.classFile]
        if coords then
            head.icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
            head.icon:SetTexCoord(unpack(coords))
        else
            head.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            head.icon:SetTexCoord(0, 1, 0, 1)
        end
        head.name:SetText("|cFF" .. addonTable.GetClassColorHex(info.classFile) .. (info.name or "") .. "|r")
        head.info:SetText(L["Nivel "] .. (info.level or "?") .. " · " .. (info.className or L["Desconocida"]))
        head.rank:SetText(info.rank or "")
        head.status:SetText(info.statusText or "")

        local y = -(head:GetHeight() + 6)
        -- Insignias: iconos pequeños con tooltip
        for i, badge in ipairs(info.badges or {}) do
            local btn = PooledButton(head.badgeButtons, i, false)
            btn:SetSize(18, 18)
            btn.icon:SetTexture(badge.icon)
            btn.tipTitle, btn.tipText, btn.onClick = badge.label, badge.desc, nil
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", 2 + ((i - 1) % 8) * 21, y - math.floor((i - 1) / 8) * 21)
            btn:Show()
        end
        if info.badges and #info.badges > 0 then y = y - math.ceil(#info.badges / 8) * 21 - 4 end

        -- Etiquetas (rosters): se colocan seguidas y bajan de línea si no caben
        if info.tagsTitle then
            head.tagsTitle:ClearAllPoints()
            head.tagsTitle:SetPoint("TOPLEFT", child, "TOPLEFT", 2, y)
            head.tagsTitle:SetText(info.tagsTitle)
            head.tagsTitle:Show()
            y = y - 16
            local x = 2
            for i, tag in ipairs(info.tags or {}) do
                local btn = PooledButton(head.tagButtons, i, true)
                btn.text:SetText(tag.text)
                local tc = tag.color or { 0.6, 0.6, 0.6 }
                btn.bg:SetColorTexture(tc[1], tc[2], tc[3], 0.25)
                btn.text:SetTextColor(math.min(1, tc[1] + 0.3), math.min(1, tc[2] + 0.3), math.min(1, tc[3] + 0.3))
                local w = math.min(172, btn.text:GetStringWidth() + 12)
                btn:SetSize(w, 16)
                if x > 2 and x + w > 174 then x, y = 2, y - 19 end
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", child, "TOPLEFT", x, y)
                btn.tipTitle, btn.tipText, btn.onClick = tag.tipTitle, tag.tip, tag.onClick
                btn:EnableMouse(tag.onClick ~= nil or tag.tipTitle ~= nil)
                btn:Show()
                x = x + w + 4
            end
            y = y - 19 - 6
        end
        infoText:SetPoint("TOPLEFT", child, "TOPLEFT", 2, y)
    end

    -- Ajusta el alto del contenido y muestra la barra solo si hace falta
    function preview.UpdateScroll()
        local top = select(5, infoText:GetPoint(1)) or 0
        local height = -top + infoText:GetStringHeight() + 6
        child:SetHeight(math.max(1, height))
        scroll:SetVerticalScroll(0)
        if scroll.ScrollBar then scroll.ScrollBar:SetShown(height > scroll:GetHeight()) end
    end
    infoText:SetText(L[PREVIEW_DEFAULT_TEXT])

    preview.infoText = infoText
    preview.infoScroll = scroll
    C_Timer.After(0, preview.UpdateScroll)

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
    if not ach then return L[PREVIEW_DEFAULT_TEXT] end

    local d = ach.GetDetails(id)
    if not d then return L[PREVIEW_DEFAULT_TEXT] end

    local lines = {}
    table.insert(lines, "|cFFFFD100" .. d.name .. "|r")
    table.insert(lines, "")

    if d.description ~= "" then
        table.insert(lines, d.description)
        table.insert(lines, "")
    end

    table.insert(lines, L["Puntos: |cFFFFD100"] .. d.points .. "|r")

    if d.completed then
        table.insert(lines, L["Estado: |cFF00FF00Completado|r"])
        table.insert(lines, L["Fecha: "] .. (d.date or "-"))
        table.insert(lines, L["Completado por: |cFF00FFFF"] .. (d.earnedBy or L["No disponible"]) .. "|r")
    else
        table.insert(lines, L["Estado: |cFFFF3333Pendiente|r"])
    end
    -- Logros de personaje: si quien mira ya lo tiene
    if not d.isGuild then
        table.insert(lines, d.completed and L["|cFF00FF00Ya completaste este logro.|r"]
            or L["|cFFFF7F00Aún no has completado este logro.|r"])
    end

    if d.rewardText ~= "" then
        table.insert(lines, "")
        table.insert(lines, L["|cFF66FF66Recompensa:|r "] .. d.rewardText)
    end

    -- Participantes (si la API del cliente lo permite)
    -- (solo en logros de hermandad: los del personaje no tienen participantes)
    if d.completed and ach.IsGuildMode() then
        local names, total, available = ach.GetMembers(id)
        table.insert(lines, "")
        if not available then
            table.insert(lines, L["|cFF808080Participantes: no disponible|r"])
        elseif #names == 0 then
            table.insert(lines, L["|cFF808080Participantes: sin datos aún|r"])
        else
            local maxShown = ach.GetMaxMembersShown()
            local shown = {}
            for i = 1, math.min(#names, maxShown) do
                table.insert(shown, names[i])
            end
            table.insert(lines, L["Participantes ("] .. #names .. "):")
            local extra = #names > maxShown and (L[" |cFF808080y "] .. (#names - maxShown) .. L[" más|r"]) or ""
            table.insert(lines, "|cFF00FFFF" .. table.concat(shown, ", ") .. "|r" .. extra)
        end
    end

    -- Criterios
    if #d.criteria > 0 then
        table.insert(lines, "")
        table.insert(lines, L["Criterios: "] .. d.criteriaDone .. "/" .. #d.criteria)
        for i = 1, math.min(#d.criteria, 8) do
            local c = d.criteria[i]
            local mark = c.done and "|cFF00FF00+|r " or "|cFFFF3333-|r "
            local progress = (c.req > 1) and (" (" .. c.qty .. "/" .. c.req .. ")") or ""
            table.insert(lines, mark .. c.name .. progress)
        end
        if #d.criteria > 8 then
            table.insert(lines, L["|cFF808080... y "] .. (#d.criteria - 8) .. L[" más|r"])
        end
    end

    table.insert(lines, "")
    table.insert(lines, L["|cFF808080Clic derecho: abrir en Blizzard|r"])

    return table.concat(lines, "\n")
end

-- Vista previa de un logro con el botón para abrirlo en la ventana de logros del juego
local function ShowAchievementPreviewWithButton(id)
    SetPreviewText(BuildAchievementPreviewText(id))
    SetPreviewAction(L["Ver en la interfaz del juego"], function()
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
    print(L["|cFF00FFFF[GuildControl]|r "] .. msg)
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
    if not name or name == "" then return end
    if addonTable.WarnIfBusy then addonTable.WarnIfBusy(name) end
    OpenChatWith("/w " .. addonTable.GetGameName(name) .. " ")
end

local function SendWhisper(name, msg)
    if not name or name == "" or not msg or msg == "" then return end
    name = addonTable.GetGameName(name)   -- Forever: nombre con apellido
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(msg, "WHISPER", nil, name)
    else
        SendChatMessage(msg, "WHISPER", nil, name)
    end
end

local function InviteToGroup(name)
    if not name or name == "" then return end
    name = addonTable.GetGameName(name)   -- Forever: nombre con apellido
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
        PrintGC(L["|cFFFF3333No se invita a "] .. name .. L[": está en la lista negra ("] .. addonTable.Blacklist.GetReasonLabel(blacklisted.reason) .. ").|r")
        return false
    end
    if not IsInGuild() or (CanGuildInvite and not CanGuildInvite()) then
        PrintGC(L["|cFFFF3333Tu rango no tiene permiso para invitar a la hermandad.|r"])
        return false
    end
    local gameName = addonTable.GetGameName(name)   -- Forever: nombre con apellido
    if C_GuildInfo and C_GuildInfo.Invite then
        C_GuildInfo.Invite(gameName)
    elseif GuildInvite then
        GuildInvite(gameName)
    end
    if not quiet then PrintGC(L["Invitación a la hermandad enviada a |cFFFFD100"] .. name .. "|r.") end
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
        rootDescription:CreateButton(L["Susurrar"], function() WhisperTo(name) end)
        rootDescription:CreateButton(L["Invitar al grupo"], function() InviteToGroup(name) end)
        local F = addonTable.Favorites
        if F then
            rootDescription:CreateButton(F.IsFavorite(name) and L["Quitar de favoritos"] or L["Añadir a favoritos"], function()
                F.Toggle(name)
                if uiModule.RefreshList then uiModule.RefreshList() end
                if uiModule.RefreshFavorites then uiModule.RefreshFavorites() end
            end)
        end
        -- Oficiales: dar o quitar las insignias nuevas (las de serie se ganan solas)
        local D = addonTable.Dkp
        local isOfficer = addonTable.Profiles and addonTable.Profiles.IsOfficer()
        local custom = D and D.GetCustomBadges and D.GetCustomBadges() or {}
        if isOfficer and #custom > 0 and GuildControlDB.members[name] then
            local submenu = rootDescription:CreateButton(L["Insignias"])
            for _, badge in ipairs(custom) do
                submenu:CreateCheckbox("|T" .. tostring(badge.icon) .. ":14:14|t " .. badge.label,
                    function() return D.HasCustomBadge(name, badge.key) end,
                    function() D.SetBadgeHolder(badge.key, name, not D.HasCustomBadge(name, badge.key)) end)
            end
        end
    end)
end

-- =========================================================================
-- 6. VISTA DE MIEMBROS
-- =========================================================================
local MEMBER_ROW_HEIGHT = 24

-- Columnas de la tabla de miembros. "key" es el criterio de orden (nil = no ordenable)
local MEMBER_COLUMNS = {
    { title = "Nº",       x = 5,   w = 25 },
    { title = "Nivel",    x = 30,  w = 40,  key = "level" },
    { title = "Clase",    x = 70,  w = 62,  key = "class" },
    { title = "Nombre",   x = 132, w = 120, key = "name" },
    { title = "Rango",    x = 252, w = 72,  key = "rank" },
    { title = "Tipo",     x = 324, w = 44,  key = "charType" },
    { title = "Rol",      x = 368, w = 66,  key = "role" },
    { title = "Enfoque",  x = 434, w = 56,  key = "focus" },
    { title = "Prof. 1",  x = 490, w = 76,  key = "prof1" },
    { title = "Prof. 2",  x = 566, w = 76,  key = "prof2" },
    { title = "Zona",     x = 642, w = 148, key = "zone" },
    { title = "Conexión", x = 790, w = 60,  key = "lastOnline" },
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
    return RoleIcon(role, 12) .. " " .. L[role] .. ((declared and declared ~= role) and "*" or "")
end

local function RoleCellColor(data, isOnline)
    local declared = data.declared and data.declared.main
    if data.roleSource == "declared" then return isOnline and "00FFFF" or "4D9999" end
    if declared and declared ~= data.role then return isOnline and "FF7F00" or "996633" end
    return isOnline and "FFFFFF" or "888888"
end

-- Valores que se muestran vacíos cuando no hay dato (profesiones, enfoque y tipo)
local function ProfessionCell(value)
    if not value or value == "Ninguna" then return "" end
    return string.match(value, "^(.-)%s+%d+$") or value
end

-- Zona conocida del miembro (la última si está desconectado)
local function ZoneCell(value)
    return (value and value ~= "Desconocida") and value or ""
end

-- El enfoque solo se muestra si el jugador lo declaró en Mi perfil
local function FocusCell(data)
    return data.declared and data.declared.focus or ""
end

local function CharTypeCell(data)
    local charType = data.declared and data.declared.charType
    if charType == "alt" then return L["Alter"] elseif charType == "main" then return L["Main"] end
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
    elseif key == "focus" then value = FocusCell(data)
    elseif key == "charType" then value = CharTypeCell(data)
    elseif key == "zone" then value = ZoneCell(data.zone)
    else value = tostring(data[key] or "") end
    if value == "" then return "\255" end
    return string.lower(value)
end

local function BuildMembersView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()

    local memberFilter = "all"     -- "all", "online" o "favorites"
    local searchQuery = ""
    local sortKey, sortAsc = DEFAULT_SORT_KEY, true

    -- Barra de filtros (todo dentro del contenedor)
    local searchLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", view, "TOPLEFT", 12, -10)
    searchLabel:SetText(L["Buscar miembros"])

    local searchBox = CreateFrame("EditBox", "GC_NewSearchBox", view, "InputBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 5, -4)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- Texto de ayuda dentro de la caja mientras está vacía
    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
    searchPlaceholder:SetText(L["Nombre, clase, zona, profesión..."])

    local btnShowAll = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnShowAll:SetSize(80, 22)
    btnShowAll:SetPoint("LEFT", searchBox, "RIGHT", 15, 0)
    btnShowAll:SetText(L["Todos"])

    local btnShowOnline = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnShowOnline:SetSize(80, 22)
    btnShowOnline:SetPoint("LEFT", btnShowAll, "RIGHT", 8, 0)
    btnShowOnline:SetText(L["En línea"])

    local btnShowFav = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnShowFav:SetSize(80, 22)
    btnShowFav:SetPoint("LEFT", btnShowOnline, "RIGHT", 8, 0)
    btnShowFav:SetText(L["Favoritos"])

    local countText = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("LEFT", btnShowFav, "RIGHT", 15, 0)
    countText:SetTextColor(0.75, 0.75, 0.75)

    local btnCSV = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnCSV:SetSize(110, 22)
    btnCSV:SetPoint("RIGHT", view, "RIGHT", -12, 0)
    btnCSV:SetPoint("TOP", searchBox, "TOP", 0, 1)
    btnCSV:SetText(L["Sheets / CSV"])

    -- Misma tipografía y separación que la etiqueta "Buscar miembros"
    local exportLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    exportLabel:SetPoint("BOTTOMLEFT", btnCSV, "TOPLEFT", 2, 3)
    exportLabel:SetText(L["Exportar"])
    btnCSV:SetScript("OnClick", function()
        if addonTable.CSV and addonTable.CSV.ShowFrame then addonTable.CSV.ShowFrame() end
    end)

    -- Vuelve a pedir la lista de la hermandad al servidor (a veces llega tarde al conectar)
    local btnReload = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnReload:SetSize(90, 22)
    btnReload:SetPoint("RIGHT", btnCSV, "LEFT", -8, 0)
    btnReload:SetText(L["Actualizar"])
    btnReload:SetScript("OnClick", function()
        if addonTable.ForceRosterScan then addonTable.ForceRosterScan() end
        if uiModule.RefreshList then uiModule.RefreshList() end
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
        hb.text:SetText(L[col.title])

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
        memberFilter = "all"
        uiModule.RefreshList()
    end)

    btnShowOnline:SetScript("OnClick", function()
        memberFilter = "online"
        uiModule.RefreshList()
    end)

    -- Favoritos: clic derecho en un miembro > Añadir a favoritos (avisa al conectarse)
    btnShowFav:SetScript("OnClick", function()
        memberFilter = "favorites"
        uiModule.RefreshList()
    end)
    btnShowFav:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Favoritos"], 1, 1, 1)
        GameTooltip:AddLine(L["Clic derecho en un miembro para añadirlo o quitarlo. Te avisa cuando se conecta."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnShowFav:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function MatchesSearch(fullName, data)
        if searchQuery == "" then return true end
        local fields = { fullName, data.class, data.rank, data.role, L[data.role or ""], data.focus, data.prof1, data.prof2, data.roster, data.zone }
        for _, value in ipairs(fields) do
            if value and string.find(string.lower(tostring(value)), searchQuery, 1, true) then
                return true
            end
        end
        return false
    end

    -- Desglose de profesiones por expansión (solo propio o de miembros con GuildControl)
    local function BuildExpansionText(fullName)
        local lines = { "", L["|cFFFFD100Profesiones por expansión|r"] }
        local breakdown = addonTable.Professions and addonTable.Professions.GetExpansionBreakdown
            and addonTable.Professions.GetExpansionBreakdown(fullName)
        if not breakdown then
            table.insert(lines, L["|cFF808080Sin datos. Solo está disponible para miembros que usan GuildControl.|r"])
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
        if not declaredText then return L["|cFF808080Rol declarado: no lo ha indicado|r\n"] end
        local text = L["Rol declarado: |cFF00FFFF"] .. declaredText .. "|r\n"
        if data.declared.note and data.declared.note ~= "" then
            text = text .. L["Nota: |cFFBFBFBF"] .. data.declared.note .. "|r\n"
        end
        if data.roleSource == "officer" then text = text .. L["|cFF808080(un oficial fijó el rol a mano)|r\n"] end
        local availText = addonTable.Profiles.GetAvailabilityText and addonTable.Profiles.GetAvailabilityText(data)
        if availText then text = text .. availText .. "\n" end
        return text
    end

    -- Aviso en la vista previa si el miembro está en la lista negra
    local function BlacklistPreviewLine(fullName)
        local entry = addonTable.Blacklist and addonTable.Blacklist.Get(fullName)
        if not entry then return "" end
        return L["|cFFFF3333¡En la lista negra! "] .. addonTable.Blacklist.GetReasonLabel(entry.reason)
            .. ((entry.note and entry.note ~= "") and (": " .. entry.note) or "") .. "|r\n\n"
    end

    -- Insignias del miembro (Personal.lua), como iconos con tooltip
    local function MemberBadges(fullName)
        local PM = addonTable.Personal
        local list = {}
        for _, badge in ipairs(PM and PM.GetBadges(fullName) or {}) do
            table.insert(list, { icon = badge.icon, label = L[badge.label], desc = L[badge.desc or ""] })
        end
        return list
    end

    -- Rosters en los que está (los del oficial y los publicados): una etiqueta por banda con
    -- el color y el icono de su puesto. Clic: el roster en Roster (oficiales) o la banda en Raid.
    local SLOT_TAG_COLORS = { tank = { 0.25, 0.5, 1 }, healer = { 0.25, 0.85, 0.35 }, dps = { 0.95, 0.3, 0.3 }, bench = { 0.6, 0.6, 0.6 } }
    local function RosterTags(fullName)
        local R = addonTable.Roster
        local isOfficer = not addonTable.Profiles or addonTable.Profiles.IsOfficer()
        local tags, seen = {}, {}
        local function Add(roster)
            local slot = roster and roster.members and roster.members[fullName]
            local key = roster and (roster.syncId or roster.name)
            if not slot or seen[key] then return end
            seen[key] = true
            local eventId, rosterId = roster.eventId, roster.id
            table.insert(tags, {
                text = (RoleIcon(slot, 12) ~= "" and (RoleIcon(slot, 12) .. " ") or "") .. roster.name,
                color = SLOT_TAG_COLORS[slot] or SLOT_TAG_COLORS.bench,
                tipTitle = roster.name,
                tip = L[R.SLOT_LABELS[slot] or ""] .. "\n|cFF808080" .. (isOfficer and L["Clic: abrir en Roster"] or L["Clic: ver la banda en Raid"]) .. "|r",
                onClick = function()
                    if isOfficer then
                        if eventId then R.SelectEvent(eventId) elseif rosterId then R.Select(rosterId) end
                        SwitchTab("Roster")
                    elseif uiModule.OpenRaidEvent then
                        uiModule.OpenRaidEvent(eventId)
                    end
                end,
            })
        end
        -- Solo los activos: rosters de bandas de Raid que no han pasado, por orden de fecha
        local E = addonTable.RaidEvents
        if R and E then
            local shared = R.GetSharedRosters()
            for _, event in ipairs(E.GetUpcoming()) do
                Add(R.FindByEvent(event.id))
                for _, item in ipairs(shared) do
                    if item.roster.eventId == event.id then Add(item.roster) end
                end
            end
        end
        if #tags == 0 then table.insert(tags, { text = L["Sin roster activo"], color = { 0.4, 0.4, 0.4 } }) end
        return tags
    end

    local function ShowMemberPreview(fullName, data)
        selectedMember = data
        selectedFullName = fullName
        SetPreviewText(
            BlacklistPreviewLine(fullName) ..
            L["Rol: "] .. (HasDefinedRole(data) and (RoleIcon(data.role) .. " " .. L[data.role]) or L["|cFF808080sin definir|r"]) .. "\n" ..
            ((addonTable.Profiles and addonTable.Profiles.GetCharTypeText(data)) and
                (L["Personaje: |cFFFFD100"] .. addonTable.Profiles.GetCharTypeText(data) .. "|r\n") or "") ..
            BuildDeclaredText(data) ..
            L["Enfoque: "] .. (FocusCell(data) ~= "" and FocusCell(data) or L["|cFF808080sin definir|r"]) .. "\n\n" ..
            L["Prof. 1: "] .. (data.prof1 or L["Ninguna"]) .. "\n" ..
            L["Prof. 2: "] .. (data.prof2 or L["Ninguna"]) .. "\n" ..
            -- El estado va en la cabecera; aquí, el desglose de profesiones por expansión
            BuildExpansionText(fullName)
        )
        -- Cabecera: nombre con el color de la clase, nivel, icono, rango y estado
        local className = data.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[data.class] or data.class
        local zone = ZoneCell(data.zone)
        local status = data.isOnline
            and ("|TInterface\\COMMON\\Indicator-Green:12:12|t |cFF00FF00" .. L["En línea"] .. "|r" .. (zone ~= "" and (" |cFFBFBFBF· " .. zone .. "|r") or ""))
            or ("|TInterface\\COMMON\\Indicator-Gray:12:12|t |cFF888888" .. addonTable.FormatLastOnline(data.lastOnline or "Desconectado") .. "|r")
        if containers.preview and containers.preview.SetCharacter then
            containers.preview.SetCharacter({
                name = data.displayName or string.match(fullName, "^([^-]+)") or fullName,
                classFile = data.class, className = className, level = data.level or 0,
                rank = data.rank or L["Recluta"], statusText = status,
                badges = MemberBadges(fullName),
                tagsTitle = L["Rosters"], tags = RosterTags(fullName),
            })
            containers.preview.UpdateScroll()
        end
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

    -- Rendimiento: con la pestaña oculta no se redibuja (cada escaneo del roster la pediría);
    -- se marca pendiente y se hace al volver a verse
    local listDirty = false
    view:HookScript("OnShow", function()
        if listDirty then uiModule.RefreshList() end
    end)

    uiModule.RefreshList = function()
        if not view:IsVisible() then
            listDirty = true
            return
        end
        listDirty = false
        local list, total = {}, 0
        for fullName, data in pairs(GuildControlDB.members or {}) do
            total = total + 1
            local passFilter = (memberFilter == "all") or (memberFilter == "online" and data.isOnline)
                or (memberFilter == "favorites" and addonTable.Favorites and addonTable.Favorites.IsFavorite(fullName))
            if passFilter and MatchesSearch(fullName, data) then
                local entry = { name = fullName, data = data }
                -- El valor de orden se calcula una vez por miembro, no en cada comparación
                entry.sortValue = MemberSortValue(entry, sortKey)
                table.insert(list, entry)
            end
        end

        table.sort(list, function(a, b)
            local va, vb = a.sortValue, b.sortValue
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
                { data.class or L["Desconocida"], hex },
                { ((addonTable.Favorites and addonTable.Favorites.IsFavorite(entry.name)) and "|A:PetJournal-FavoritesIcon:12:12|a" or "") .. entry.name, hex },
                { data.rank or L["Recluta"], isOnline and "FFFFFF" or dim },
                { CharTypeCell(data), isOnline and "FFD100" or dim },
                { RoleCellText(data), RoleCellColor(data, isOnline) },
                { FocusCell(data), isOnline and "FFFFFF" or dim },
                { ProfessionCell(data.prof1), isOnline and "FFFFFF" or dim },
                { ProfessionCell(data.prof2), isOnline and "FFFFFF" or dim },
                { ZoneCell(data.zone), isOnline and "FFFFFF" or dim },
                { addonTable.FormatLastOnline(data.lastOnline or "Online"), isOnline and "00FF00" or dim },
            }
            for c, v in ipairs(values) do
                row.cells[c]:SetText("|cFF" .. v[2] .. tostring(v[1]) .. "|r")
            end
            row:Show()
        end

        scrollChild:SetHeight(math.max(1, #list * MEMBER_ROW_HEIGHT + 10))
        countText:SetText(L["Mostrando "] .. #list .. L[" de "] .. total)

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
    GameTooltip:AddDoubleLine(L["Puntos"], tostring(d.points), 0.7, 0.7, 0.7, 1, 0.82, 0)

    if d.rewardText ~= "" then
        GameTooltip:AddLine(L["Recompensa: "] .. d.rewardText, 0.4, 1, 0.4, true)
    end

    if d.completed then
        GameTooltip:AddDoubleLine(L["Completado"], d.date or "-", 0.7, 0.7, 0.7, 0, 1, 0)
        if d.earnedBy then
            GameTooltip:AddDoubleLine(L["Por"], d.earnedBy, 0.7, 0.7, 0.7, 0, 1, 1)
        end
    else
        if #d.criteria > 0 then
            GameTooltip:AddDoubleLine(L["Criterios"], d.criteriaDone .. "/" .. #d.criteria, 0.7, 0.7, 0.7, 1, 1, 1)
        end
        GameTooltip:AddLine(L["Pendiente"], 1, 0.2, 0.2)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Clic: vista previa  |  Clic derecho: abrir en Blizzard"], 0.5, 0.5, 0.5)
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
    pointsText:SetText(L["Puntos: |cFFFFD1000|r"])

    local completedText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    completedText:SetPoint("LEFT", pointsText, "RIGHT", 30, 0)
    completedText:SetText(L["Completados: |cFF00FF000/0|r"])

    local lastAchText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lastAchText:SetPoint("RIGHT", headerFrame, "RIGHT", -15, 0)
    lastAchText:SetWidth(290)
    lastAchText:SetJustifyH("RIGHT")
    lastAchText:SetWordWrap(false)
    lastAchText:SetText(L["Último logro: |cFF808080Ninguno|r"])

    -- Ver los logros de la hermandad o los del personaje (los scripts se asignan más abajo)
    local btnModeGuild = CreateFrame("Button", nil, headerFrame, "UIPanelButtonTemplate")
    btnModeGuild:SetSize(100, 22)
    btnModeGuild:SetPoint("LEFT", headerFrame, "LEFT", 380, 0)
    btnModeGuild:SetText(L["Hermandad"])

    local btnModePlayer = CreateFrame("Button", nil, headerFrame, "UIPanelButtonTemplate")
    btnModePlayer:SetSize(100, 22)
    btnModePlayer:SetPoint("LEFT", btnModeGuild, "RIGHT", 6, 0)
    btnModePlayer:SetText(L["Personaje"])

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
    searchLabel:SetText(L["Buscar logros"])

    local searchBox = CreateFrame("EditBox", "GC_AchSearchBox", rightPanel, "InputBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 5, -4)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
    searchPlaceholder:SetText(L["Nombre del logro..."])

    local btnFilterAll = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    btnFilterAll:SetSize(65, 22)
    btnFilterAll:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    btnFilterAll:SetText(L["Todos"])

    local btnFilterDone = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    btnFilterDone:SetSize(85, 22)
    btnFilterDone:SetPoint("LEFT", btnFilterAll, "RIGHT", 4, 0)
    btnFilterDone:SetText(L["Completados"])

    local btnFilterPending = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    btnFilterPending:SetSize(75, 22)
    btnFilterPending:SetPoint("LEFT", btnFilterDone, "RIGHT", 4, 0)
    btnFilterPending:SetText(L["Pendientes"])

    -- Logros de temporada: busca en todas las categorías de hermandad
    local chkSeason = CreateFrame("CheckButton", "GC_ChkSeasonAch", rightPanel, "UICheckButtonTemplate")
    chkSeason:SetPoint("LEFT", btnFilterPending, "RIGHT", 8, 0)
    _G[chkSeason:GetName() .. "Text"]:SetText(L["Logros de temporada"])
    chkSeason:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Logros de temporada"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Muestra, de todas las categorías, los logros de temporada (Mítica+, bandas, JcJ) y los de eventos del mundo."], 1, 1, 1, true)
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
    AddAchHeader(L["Estado"], 5, 80)
    AddAchHeader(L["Título del Logro"], 90, 360)
    AddAchHeader(L["Fecha / Progreso"], 460, 180)

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
                    SetPreviewText(L[PREVIEW_DEFAULT_TEXT])
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

        pointsText:SetText(L["Puntos: |cFFFFD100"] .. (stats.totalPoints or 0) .. "|r")
        completedText:SetText(L["Completados: |cFF00FF00"] .. (stats.completedCount or 0) .. "/" .. (stats.totalCount or 0) .. "|r")

        if stats.latestName and stats.latestName ~= L["Ninguno"] then
            local dateStr = (stats.latestDate and stats.latestDate ~= "") and (" (" .. stats.latestDate .. ")") or ""
            lastAchText:SetText(L["Último logro: |cFFFFD100"] .. stats.latestName .. "|r" .. dateStr)
        else
            lastAchText:SetText(L["Último logro: |cFF808080Ninguno|r"])
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
        local scanAll = filterSeason or searchQuery ~= ""
        if not currentCategoryId and not scanAll then
            achChild:SetHeight(1)
            return
        end

        -- Con el filtro de temporada o con texto en el buscador se recorren todas las categorías
        local categoriesToScan = {}
        if scanAll then
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
                        row.titleFs:SetText(name or L["Desconocido"])
                        row.statusFs:SetText(completed and L["|cFF00FF00Completado|r"] or L["|cFFFF3333Pendiente|r"])
                        row.dateFs:SetText(completed and addonTable.Achievements.FormatDate(day, month, year) or L["|cFF808080En progreso|r"])
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
        SetPreviewText(L[PREVIEW_DEFAULT_TEXT])
        BuildGuildCategories()
        btnModeGuild:SetEnabled(newMode ~= "guild")
        btnModePlayer:SetEnabled(newMode ~= "player")
        uiModule.RefreshAchievements()
    end
    btnModeGuild:SetScript("OnClick", function() SetAchievementMode("guild") end)
    btnModePlayer:SetScript("OnClick", function() SetAchievementMode("player") end)
    btnModeGuild:SetEnabled(false)

    containers.views["Logros"] = view
end

-- =========================================================================
-- 8a. VISTA ROSTER (CONSUME MODULES/ROSTER.LUA)
-- =========================================================================
local ROSTER_ROW_HEIGHT = 18

-- Nombre corto con el color de su clase (gris si está desconectado)
local function ColoredMemberName(fullName)
    local m = GuildControlDB.members[fullName] or {}
    -- Forever: con apellido si el juego lo da (displayName), si no el nombre corto
    local short = m.displayName or string.match(fullName, "^([^-]+)") or fullName
    local hex = addonTable.GetClassColorHex(m.class)
    if not m.isOnline then return "|cFF" .. hex .. short .. "|r|cFF808080 ·|r" end
    return "|cFF" .. hex .. short .. "|r"
end

local function ShowMemberTooltip(owner, fullName)
    local R = addonTable.Roster
    local m = GuildControlDB.members[fullName] or {}
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(fullName, 1, 0.82, 0)
    GameTooltip:AddDoubleLine(L["Clase"], R.GetClassName(m.class), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Nivel"], tostring(m.level or "?"), 0.7, 0.7, 0.7, 1, 1, 1)
    local hasRole = R.HasDefinedRole(m)
    GameTooltip:AddDoubleLine(L["Rol"], hasRole and (RoleIcon(m.role) .. " " .. L[m.role]) or L["sin definir"], 0.7, 0.7, 0.7, 1, 1, 1)
    local charType = addonTable.Profiles and addonTable.Profiles.GetCharTypeText(m)
    if charType then GameTooltip:AddDoubleLine(L["Personaje"], charType, 0.7, 0.7, 0.7, 1, 0.82, 0) end
    local declaredText = addonTable.Profiles and addonTable.Profiles.GetDeclaredText(m)
    if declaredText then
        GameTooltip:AddDoubleLine(L["Declarado"], declaredText, 0.7, 0.7, 0.7, 0, 1, 1)
        if m.declared.note and m.declared.note ~= "" then
            GameTooltip:AddLine(m.declared.note, 0.75, 0.75, 0.75, true)
        end
    end
    -- Disponibilidad y ausencia larga (Mi perfil > Disponibilidad)
    local availText = addonTable.Profiles and addonTable.Profiles.GetAvailabilityText and addonTable.Profiles.GetAvailabilityText(m)
    if availText then GameTooltip:AddLine(availText, 0.85, 0.85, 0.85, true) end
    GameTooltip:AddDoubleLine(L["Rango"], m.rank or "-", 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Estado"], m.isOnline and L["En línea"] or addonTable.FormatLastOnline(m.lastOnline or "Desconectado"),
        0.7, 0.7, 0.7, m.isOnline and 0 or 0.6, m.isOnline and 1 or 0.6, m.isOnline and 0 or 0.6)
    -- Asistencia en las bandas (pestaña Raid) asociadas al roster seleccionado
    local stats = addonTable.RaidEvents.GetAttendanceStats(R.GetSelected().name, fullName)
    if stats.percent then
        GameTooltip:AddDoubleLine(L["Asistencia"], stats.percent .. "% (" .. (stats.present + stats.late) .. "/" .. stats.counted .. ")",
            0.7, 0.7, 0.7, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function BuildRosterView(parent)
    local R = addonTable.Roster
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local Refresh   -- declaración adelantada

    -- ---------------------------------------------------------------------
    -- Barra superior: banda de Raid (cada banda tiene su roster), publicar y eliminar
    -- ---------------------------------------------------------------------
    local dropRoster = CreateFrame("DropdownButton", "GC_RosterSelect", view, "WowStyle1DropdownTemplate")
    dropRoster:SetPoint("TOPLEFT", view, "TOPLEFT", 10, -10)
    dropRoster:SetWidth(300)

    local function EventLabel(event)
        local day = string.gsub(event.date or "", "^%d+-(%d+)-(%d+)$", "%2/%1")
        return day .. " " .. (event.time or "") .. "  " .. (event.title or "?")
    end

    dropRoster:SetupMenu(function(_, root)
        local E = addonTable.RaidEvents
        local events = E and E.GetUpcoming() or {}
        if #events == 0 then root:CreateTitle(L["No hay bandas: créala en la pestaña Raid"]) end
        for _, event in ipairs(events) do
            local id = event.id
            root:CreateRadio(EventLabel(event),
                function() local selected = R.GetSelectedEvent(); return selected ~= nil and selected.id == id end,
                function()
                    R.SelectEvent(id)
                    Refresh()
                end)
        end
    end)

    -- Los oficiales ven los cambios en vivo; los jugadores solo lo que se publica aquí
    local btnPublish = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnPublish:SetSize(170, 22)
    btnPublish:SetPoint("LEFT", dropRoster, "RIGHT", 12, 0)
    btnPublish:SetText(L["Publicar a la hermandad"])
    btnPublish:SetScript("OnClick", function()
        if not R.GetSelectedEvent() then return end
        local roster = R.GetSelected()
        local parts = R.Publish(roster)
        if parts == 0 then
            PrintGC(L["|cFFFF3333No se pudo publicar el roster.|r"])
        else
            PrintGC(L["Roster publicado a la hermandad: |cFFFFD100"] .. roster.name .. "|r")
        end
        Refresh()
    end)
    btnPublish:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Publicar a la hermandad"], 1, 1, 1)
        GameTooltip:AddLine(L["Los oficiales ven los cambios del roster en vivo. Los jugadores solo lo ven (en la vista previa de Raid, al elegir la banda) cuando lo publicas, tal como está en ese momento; si lo cambias después, vuelve a publicarlo."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnPublish:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local publishStatus = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    publishStatus:SetPoint("LEFT", btnPublish, "RIGHT", 10, 0)

    -- Eliminar (dos clics): borra el roster de esta banda y lo retira de Mis rosters
    local btnDelete = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnDelete:SetSize(120, 22)
    btnDelete:SetPoint("TOPRIGHT", view, "TOPRIGHT", -10, -10)
    btnDelete:SetText(L["Eliminar roster"])
    local deleteArmedUntil = 0
    btnDelete:SetScript("OnClick", function(self)
        if not R.GetSelectedEvent() then return end
        if GetTime() < deleteArmedUntil then
            deleteArmedUntil = 0
            self:SetText(L["Eliminar roster"])
            R.Delete(R.GetSelected())
            Refresh()
        else
            deleteArmedUntil = GetTime() + 4
            self:SetText(L["|cFFFF3333¿Seguro?|r"])
            C_Timer.After(4, function()
                if GetTime() >= deleteArmedUntil then self:SetText(L["Eliminar roster"]) end
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
            rootDescription:CreateRadio(L[diff.label],
                function() return R.GetSelected().difficulty == key end,
                function()
                    R.SetDifficulty(R.GetSelected(), key)
                    Refresh()
                end)
        end
    end)

    dropDifficulty:Hide()   -- la dificultad la da la banda de Raid

    local sizeLabel = criteria:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sizeLabel:SetPoint("LEFT", criteria, "LEFT", 12, 0)
    sizeLabel:SetText(L["Tamaño:"])

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

    -- El tamaño viene de la banda creada en Raid: no se edita aquí
    btnSizeDown:Hide()
    btnSizeUp:Hide()
    sizeText:ClearAllPoints()
    sizeText:SetPoint("LEFT", sizeLabel, "RIGHT", 6, 0)

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

    local tankTarget = CreateTargetInput(btnSizeUp, L["Tanques:"], "tank")
    local healerTarget = CreateTargetInput(tankTarget, L["Sanadores:"], "healer")

    local dpsTargetText = criteria:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dpsTargetText:SetPoint("LEFT", healerTarget, "RIGHT", 18, 0)

    local criteriaStatus = criteria:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    criteriaStatus:SetPoint("RIGHT", criteria, "RIGHT", -10, 0)

    -- Los cambios de otros oficiales llegan solos: se refresca la vista
    R.SetReceivedListener(function() Refresh() end)

    -- ---------------------------------------------------------------------
    -- Candidatos (izquierda)
    -- ---------------------------------------------------------------------
    local candPanel = CreateBackdropBox(view, 230, 404, "TOPLEFT", criteria, "BOTTOMLEFT", 0, -6)

    local candTitle = candPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    candTitle:SetPoint("TOPLEFT", candPanel, "TOPLEFT", 10, -8)
    candTitle:SetText(L["Candidatos"])

    -- Todos los apuntados, estén conectados o no (sin buscador ni filtros)
    local candScroll = CreateFrame("ScrollFrame", "GC_RosterCandScroll", candPanel, "UIPanelScrollFrameTemplate")
    candScroll:SetPoint("TOPLEFT", candTitle, "BOTTOMLEFT", 0, -8)
    candScroll:SetPoint("BOTTOMRIGHT", candPanel, "BOTTOMRIGHT", -26, 24)
    local candChild = CreateFrame("Frame")
    candChild:SetSize(190, 1)
    candScroll:SetScrollChild(candChild)

    local candHint = candPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    candHint:SetPoint("BOTTOMLEFT", candPanel, "BOTTOMLEFT", 10, 8)
    candHint:SetText(L["Clic: añadir · Clic derecho: rol"])

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
                    for _, slot in ipairs(R.AllowedSlots(name, { "tank", "healer", "dps" })) do
                        root:CreateButton(L["Rol: "] .. L[R.SLOT_LABELS[slot]], function()
                            R.SetMemberRole(name, slot)
                            Refresh()
                        end)
                    end
                    local m = GuildControlDB.members[name]
                    if m and m.declared and m.declared.main and addonTable.Profiles then
                        root:CreateButton(L["Usar rol declarado ("] .. L[m.declared.main] .. ")", function()
                            addonTable.Profiles.UseDeclaredRole(name)
                            Refresh()
                        end)
                    end
                    root:CreateButton(L["Añadir como suplente"], function()
                        R.AddMember(R.GetSelected(), name, "bench")
                        Refresh()
                    end)
                    root:CreateButton(L["Susurrar"], function() WhisperTo(name) end)
                end)
            else
                R.AddMember(R.GetSelected(), self.fullName, self.slot)
                Refresh()
            end
        end)
        row:SetScript("OnEnter", function(self) if self.fullName then ShowMemberTooltip(self, self.fullName) end end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        candRows[index] = row
        return row
    end

    -- Candidatos = quienes se apuntaron a la banda (no Tarde ni Ausente, que van abajo) y aún
    -- no están en el roster, agrupados por el rol con el que se apuntaron
    local VALID_SIGNUP_SLOT = { tank = true, healer = true, dps = true }
    local function RefreshCandidates(roster, event)
        for _, row in ipairs(candRows) do row:Hide() end
        local groups = { tank = {}, healer = {}, dps = {}, none = {} }
        local effective = roster and R.GetEffectiveMembers(roster) or {}
        for fullName, signup in pairs(event and event.signups or {}) do
            if signup.status ~= "absent" and signup.status ~= "late" and not effective[fullName] then
                local slot = VALID_SIGNUP_SLOT[signup.role] and signup.role or R.GetDefinedSlot(fullName) or "none"
                table.insert(groups[slot], fullName)
            end
        end

        local index, y = 0, 0
        local GROUP_LABELS = { tank = L["Tanques"], healer = L["Sanadores"], dps = "DPS", none = L["Sin rol definido"] }
        for _, slot in ipairs({ "tank", "healer", "dps", "none" }) do
            local list = groups[slot]
            table.sort(list, function(a, b)
                local ma, mb = GuildControlDB.members[a] or {}, GuildControlDB.members[b] or {}
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
                row.slot = slot ~= "none" and slot or nil
                row:SetPoint("TOPLEFT", candChild, "TOPLEFT", 0, -y)
                row.text:SetText("  " .. RoleIcon(slot, 12) .. " " .. ColoredMemberName(fullName))
                row.level:SetText(tostring((GuildControlDB.members[fullName] or {}).level or ""))
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
        root:CreateRadio(L["Base (todos los jefes)"],
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
    variantPlaceholder:SetText(L["Jefe (vacío: lista de la banda)"])
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
    btnAddVariant:SetText(L["Añadir jefe"])
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
            root:CreateTitle(roster.raidName or L["Jefes"])
            for _, boss in ipairs(bosses) do
                if existing[boss] then
                    root:CreateButton("|cFF808080" .. boss .. L[" (ya añadido)|r"], function() end)
                else
                    root:CreateButton(boss, function() AddVariant(boss) end)
                end
            end
            root:CreateButton(L["Todos los que faltan"], function()
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
    btnDeleteVariant:SetText(L["Eliminar jefe"])
    btnDeleteVariant:SetScript("OnClick", function(self)
        local roster = R.GetSelected()
        local variant = R.GetSelectedVariant(roster)
        if not variant then return end
        if GetTime() < deleteVariantArmedUntil then
            deleteVariantArmedUntil = 0
            self:SetText(L["Eliminar jefe"])
            R.DeleteVariant(roster, variant)
            Refresh()
        else
            deleteVariantArmedUntil = GetTime() + 4
            self:SetText(L["|cFFFF3333¿Seguro?|r"])
            C_Timer.After(4, function()
                if GetTime() >= deleteVariantArmedUntil then self:SetText(L["Eliminar jefe"]) end
            end)
        end
    end)

    local variantDiffText = compPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    variantDiffText:SetPoint("LEFT", btnDeleteVariant, "RIGHT", 10, 0)
    variantDiffText:SetPoint("RIGHT", compPanel, "RIGHT", -10, 0)
    variantDiffText:SetJustifyH("LEFT")
    variantDiffText:SetWordWrap(false)

    -- El roster es solo la lista de personas con las que se cuenta: la composición por jefe
    -- se gestiona en Raid. Los controles de jefes quedan ocultos.
    for _, widget in ipairs({ dropVariant, variantInput, btnAddVariant, btnDeleteVariant, variantDiffText }) do widget:Hide() end

    -- Cada rol es un contenedor con borde, fondo y franja de cabecera de su color; sus
    -- integrantes se colocan dentro en una cuadrícula de "cols" columnas
    local BLOCK_COLORS = {
        tank = { 0.25, 0.5, 1 }, healer = { 0.25, 0.85, 0.35 }, dps = { 0.95, 0.3, 0.3 }, bench = { 0.6, 0.6, 0.6 },
        late = { 1, 0.82, 0 }, absent = { 1, 0.2, 0.2 },
    }
    local BLOCK_HEADER = 24
    local blocks = {}
    local function CreateBlock(slot, x, y, width, height, cols)
        local color = BLOCK_COLORS[slot]
        local block = CreateBackdropBox(compPanel, width, height, "TOPLEFT", compPanel, "TOPLEFT", x, y)
        block:SetBackdropBorderColor(color[1], color[2], color[3], 0.9)
        block.tint = block:CreateTexture(nil, "BACKGROUND", nil, 1)
        block.tint:SetPoint("TOPLEFT", block, "TOPLEFT", 3, -3)
        block.tint:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", -3, 3)
        block.tint:SetColorTexture(color[1], color[2], color[3], 0.07)
        block.header = block:CreateTexture(nil, "ARTWORK")
        block.header:SetPoint("TOPLEFT", block, "TOPLEFT", 3, -3)
        block.header:SetPoint("TOPRIGHT", block, "TOPRIGHT", -3, -3)
        block.header:SetHeight(BLOCK_HEADER - 3)
        block.header:SetColorTexture(color[1], color[2], color[3], 0.25)
        block.slot, block.cols, block.rows = slot, cols, {}
        block.title = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        block.title:SetPoint("LEFT", block.header, "LEFT", 6, 0)
        block.more = block:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        block.more:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", -8, 6)
        blocks[slot] = block
        return block
    end

    CreateBlock("tank", 8, -8, 150, 238, 1)
    CreateBlock("healer", 164, -8, 150, 238, 1)
    CreateBlock("dps", 320, -8, 316, 238, 2)
    -- Abajo: banca (elegida por el oficial), Tarde (se pueden meter con un clic) y Ausentes
    CreateBlock("bench", 8, -252, 206, 114, 2)
    CreateBlock("late", 219, -252, 206, 114, 2)
    CreateBlock("absent", 430, -252, 206, 114, 2)

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
            -- Tarde: entra al roster con su rol; Ausente: solo susurrar
            if block.slot == "late" or block.slot == "absent" then
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(name)
                    if block.slot == "late" then
                        for _, slot in ipairs(R.AllowedSlots(name, R.SLOTS)) do
                            root:CreateButton(L["Añadir a "] .. L[R.SLOT_LABELS[slot]], function()
                                R.AddMember(R.GetSelected(), name, slot)
                                Refresh()
                            end)
                        end
                    end
                    root:CreateButton(L["Susurrar"], function() WhisperTo(name) end)
                end)
                return
            end
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(name)
                for _, slot in ipairs(R.AllowedSlots(name, R.SLOTS)) do
                    if slot ~= block.slot then
                        root:CreateButton(L["Mover a "] .. L[R.SLOT_LABELS[slot]], function()
                            R.AddMember(R.GetSelected(), name, slot)
                            -- El rol general solo cambia al editar la base, no un jefe concreto
                            if slot ~= "bench" and not R.GetSelectedVariant(R.GetSelected()) then R.SetMemberRole(name, slot) end
                            Refresh()
                        end)
                    end
                end
                local removeLabel = R.GetSelectedVariant(R.GetSelected()) and L["No juega este jefe"] or L["Quitar del roster"]
                root:CreateButton(removeLabel, function()
                    R.RemoveMember(R.GetSelected(), name)
                    Refresh()
                end)
                root:CreateButton(L["Susurrar"], function() WhisperTo(name) end)
            end)
        end)
        row:SetScript("OnEnter", function(self) if self.fullName then ShowMemberTooltip(self, self.fullName) end end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        block.rows[index] = row
        return row
    end

    local function RefreshBlock(block, names, target)
        local count = #names
        local SIMPLE_TITLES = { bench = L["Banca"], late = L["Tarde"], absent = L["Ausentes"] }
        if SIMPLE_TITLES[block.slot] then
            block.title:SetText(SIMPLE_TITLES[block.slot] .. " (" .. count .. ")")
        else
            local color = (count == target) and "|cFF00FF00" or (count > target and "|cFFFF7F00" or "|cFFFFD100")
            block.title:SetText(RoleIcon(block.slot, 16) .. " " .. L[R.SLOT_LABELS[block.slot]] .. " " .. color .. count .. "/" .. target .. "|r")
        end

        for _, row in ipairs(block.rows) do row:Hide() end
        local colWidth = math.floor((block:GetWidth() - 12) / block.cols)
        local maxRows = math.floor((block:GetHeight() - BLOCK_HEADER - 22) / ROSTER_ROW_HEIGHT)
        local capacity = maxRows * block.cols
        for i, name in ipairs(names) do
            if i > capacity then break end
            local row = AcquireSlotRow(block, i)
            local col, line = (i - 1) % block.cols, math.floor((i - 1) / block.cols)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", block, "TOPLEFT", 6 + col * colWidth, -BLOCK_HEADER - 4 - line * ROSTER_ROW_HEIGHT)
            row:SetWidth(colWidth - 4)
            row.fullName = name
            local m = GuildControlDB.members[name] or {}
            row.text:SetText(ColoredMemberName(name) .. " |cFF808080" .. R.GetClassName(m.class) .. "|r")
            row:Show()
        end
        block.more:SetText(count > capacity and (L["y "] .. (count - capacity) .. L[" más"]) or "")
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

    local btnInvite = CreateAction(L["Invitar al grupo"], 120, nil, function()
        local count = R.InviteRoster(R.GetSelected())
        if count == 0 then
            PrintGC(L["No hay titulares conectados a los que invitar."])
        else
            PrintGC(L["Invitando a |cFFFFD100"] .. count .. L["|r titulares. Con más de 4 el grupo se convierte en banda cuando acepte el primero."])
        end
    end)
    -- Anuncio editable para los integrantes (hermandad o susurro a cada uno)
    local btnMessage = CreateAction(L["Anuncio"], 90, btnInvite, function()
        if uiModule.ShowRosterMessage then uiModule.ShowRosterMessage() end
    end)
    local btnExport = CreateAction(L["Exportar CSV"], 100, btnMessage, function()
        if addonTable.CSV and addonTable.CSV.ShowText then
            addonTable.CSV.ShowText(R.BuildCSV(R.GetSelected()))
        end
    end)

    -- En la base vacía el roster; en un jefe lo restablece a la base. Pide un segundo clic.
    local clearArmedUntil = 0
    local btnClear
    local function ClearLabel()
        return R.GetSelectedVariant(R.GetSelected()) and L["Restablecer jefe"] or L["Vaciar roster"]
    end
    btnClear = CreateAction(L["Vaciar roster"], 120, btnExport, function(self)
        if GetTime() < clearArmedUntil then
            clearArmedUntil = 0
            R.Clear(R.GetSelected())
            Refresh()
        else
            clearArmedUntil = GetTime() + 4
            self:SetText(L["|cFFFF3333¿Seguro?|r"])
            C_Timer.After(4, function()
                if GetTime() >= clearArmedUntil then self:SetText(ClearLabel()) end
            end)
        end
    end)
    -- Susurra a los del roster conectados que no se han apuntado a la banda
    local btnRemindRoster = CreateAction(L["Recordar al roster"], 150, btnClear, function()
        if uiModule.RemindRoster then uiModule.RemindRoster(R.GetSelectedEvent()) end
    end)
    btnRemindRoster:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Recordar al roster"], 1, 1, 1)
        GameTooltip:AddLine(L["Susurra a los integrantes del roster que están conectados y aún no se han apuntado a la banda en Raid. Los desconectados lo verán en una ventana al entrar."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnRemindRoster:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ---------------------------------------------------------------------
    -- Resumen en el panel de vista previa: jefe, cobertura, armaduras y asistencia
    -- ---------------------------------------------------------------------
    local function ShortList(names)
        local shorts = {}
        for _, name in ipairs(names) do table.insert(shorts, string.match(name, "^([^-]+)") or name) end
        return table.concat(shorts, ", ")
    end

    local function BuildSummaryText(roster)
        local lines = { "|cFFFFD100" .. R.GetDisplayName(roster) .. "|r", R.DifficultyLabel(roster) .. L[" · "] .. roster.size .. L[" jugadores"], "" }
        local diff = R.GetVariantDiff(roster)
        if diff then
            table.insert(lines, L["|cFFFFD100Cambios respecto a la base|r"])
            if #diff.entering + #diff.leaving + #diff.roleChanges == 0 then
                table.insert(lines, L["|cFF808080Igual que la base|r"])
            end
            if #diff.entering > 0 then table.insert(lines, L["|cFF00FF00Entran:|r "] .. ShortList(diff.entering)) end
            if #diff.leaving > 0 then table.insert(lines, L["|cFFFF3333Salen:|r "] .. ShortList(diff.leaving)) end
            if #diff.roleChanges > 0 then table.insert(lines, L["|cFFFFD100Cambian de rol:|r "] .. ShortList(diff.roleChanges)) end
            table.insert(lines, "")
        end
        table.insert(lines, L["|cFFFFD100Cobertura|r"])
        for _, item in ipairs(R.GetCoverage(roster)) do
            if item.count > 0 then
                table.insert(lines, "|cFF00FF00+|r " .. item.label .. " |cFF808080(" .. item.count .. ")|r")
            else
                table.insert(lines, "|cFFFF3333-|r |cFFBFBFBF" .. item.label .. "|r")
            end
        end
        table.insert(lines, "")
        table.insert(lines, L["|cFFFFD100Armaduras (titulares)|r"])
        local armor = R.GetArmorCounts(roster)
        local armorParts = {}
        for _, a in ipairs(R.ARMOR_TYPES) do table.insert(armorParts, L[a.label] .. " " .. armor[a.key]) end
        table.insert(lines, table.concat(armorParts, L[" · "]))
        table.insert(lines, "")
        table.insert(lines, L["|cFFFFD100Asistencia|r"])
        local average, eventCount = addonTable.RaidEvents.GetRosterAttendance(roster)
        table.insert(lines, L["Bandas con lista pasada: "] .. eventCount)
        table.insert(lines, L["Media del roster: "] .. (average and (average .. "%") or L["|cFF808080sin datos|r"]))
        return table.concat(lines, "\n")
    end

    -- ---------------------------------------------------------------------
    -- Refresco general
    -- ---------------------------------------------------------------------
    -- Sin bandas en Raid no hay roster que montar
    local noEventText = compPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    noEventText:SetPoint("CENTER", compPanel, "CENTER", 0, 0)
    noEventText:SetWidth(560)
    noEventText:SetText(L["No hay bandas programadas. Crea una en la pestaña Raid y aparecerá en el desplegable."])

    -- Lo que cambia en Raid (inscripciones nuevas, bandas creadas) se ve al momento
    if addonTable.RaidEvents and addonTable.RaidEvents.AddListener then
        addonTable.RaidEvents.AddListener(function() if view:IsShown() then Refresh() end end)
    end

    -- Tarde y Ausentes de la banda (los que ya están en el roster no salen en Tarde)
    local function SignupsWithStatus(event, status, effective)
        local list = {}
        for name, signup in pairs(event.signups or {}) do
            if signup.status == status and not effective[name] then table.insert(list, name) end
        end
        table.sort(list)
        return list
    end

    Refresh = function()
        if not view:IsShown() then return end
        local event = R.GetSelectedEvent()
        noEventText:SetShown(event == nil)
        btnPublish:SetEnabled(event ~= nil)
        btnDelete:SetEnabled(event ~= nil)
        if not event then
            dropRoster:SetText(L["Elige una banda"])
            publishStatus:SetText("")
            criteriaStatus:SetText("")
            for _, block in pairs(blocks) do RefreshBlock(block, {}, 0) end
            RefreshCandidates(nil, nil)
            if activeTab == "Roster" then SetPreviewText(L[PREVIEW_DEFAULT_TEXT]) end
            return
        end
        local roster = R.GetSelected()
        -- Sin variantes por jefe en el roster
        if roster.selectedVariant then R.SelectVariant(roster, nil) end

        dropRoster:SetText(EventLabel(event))
        if roster.published and roster.publishedAt then
            publishStatus:SetText(L["|cFF00FF00Publicado|r el "] .. date("%d/%m %H:%M", roster.publishedAt))
        else
            publishStatus:SetText(L["|cFFFF7F00Sin publicar|r (solo lo ven los oficiales)"])
        end
        if GetTime() >= clearArmedUntil then btnClear:SetText(ClearLabel()) end

        -- Tamaño de la banda (si se edita la banda en Raid, el roster lo sigue)
        local eventSize = tonumber(event.size)
        if eventSize and roster.size ~= eventSize then
            roster.size = math.max(R.MIN_SIZE, math.min(R.MAX_SIZE, eventSize))
        end
        local targets = R.GetTargets(roster)
        sizeText:SetText(roster.size)
        if not tankTarget:HasFocus() then tankTarget:SetText(targets.tank) end
        if not healerTarget:HasFocus() then healerTarget:SetText(targets.healer) end
        dpsTargetText:SetText(L["DPS: "] .. targets.dps)

        local bySlot = R.GetMembersBySlot(roster)
        local starters = #bySlot.tank + #bySlot.healer + #bySlot.dps
        local color = starters == roster.size and "|cFF00FF00" or (starters > roster.size and "|cFFFF7F00" or "|cFFFFD100")
        criteriaStatus:SetText(L["Titulares: "] .. color .. starters .. "/" .. roster.size .. "|r")

        RefreshBlock(blocks.tank, bySlot.tank, targets.tank)
        RefreshBlock(blocks.healer, bySlot.healer, targets.healer)
        RefreshBlock(blocks.dps, bySlot.dps, targets.dps)
        RefreshBlock(blocks.bench, bySlot.bench, 0)
        local effective = R.GetEffectiveMembers(roster)
        RefreshBlock(blocks.late, SignupsWithStatus(event, "late", effective), 0)
        RefreshBlock(blocks.absent, SignupsWithStatus(event, "absent", effective), 0)
        RefreshCandidates(roster, event)

        if activeTab == "Roster" then SetPreviewText(BuildSummaryText(roster)) end
    end

    uiModule.RefreshRoster = Refresh
    view:SetScript("OnShow", Refresh)
    uiModule.AddTips({
        { btnDelete, "Eliminar roster", "Borra el roster de esta banda (pide confirmación). Se retira también de los demás oficiales." },
        { btnAddVariant, "Añadir jefe", "Crea una variante del roster para un jefe concreto." },
        { btnDeleteVariant, "Eliminar jefe", "Borra la variante del jefe elegido (pide confirmación)." },
        { btnInvite, "Invitar al grupo", "Invita al grupo a los titulares conectados; con más de 4 se convierte en banda." },
        { btnMessage, "Anuncio", "Abre el mensaje para los integrantes: enviarlo a la hermandad o susurrarlo a cada uno." },
        { btnExport, "Exportar CSV", "Abre el roster en formato CSV para copiarlo a una hoja de cálculo." },
        { btnClear, "Vaciar roster", "Quita a todos los integrantes del roster (pide confirmación)." },
    })
    containers.views["Roster"] = view
end

-- =========================================================================
-- 8b. VISTA INVITAR: MODO INDIVIDUAL Y MODO MASIVO
-- =========================================================================
local MAX_CHAT_BYTES = 255
-- Invitación masiva: jugadores por lote, segundos entre invitaciones de un lote y días sin
-- volver a invitar a la misma persona
local MASS = { batchSize = 10, batchInterval = 3, reinviteDays = 7 }
-- Invitar individual: días del mensaje (clave, letra de la casilla, nombre en el mensaje),
-- mensajes guardados y aviso periódico para publicar (minutos)
MASS.days = {
    { key = "mon", short = "Lu", label = "lunes" },
    { key = "tue", short = "Ma", label = "martes" },
    { key = "wed", short = "Mi", label = "miércoles" },
    { key = "thu", short = "Ju", label = "jueves" },
    { key = "fri", short = "Vi", label = "viernes" },
    { key = "sat", short = "Sá", label = "sábado" },
    { key = "sun", short = "Do", label = "domingo" },
}
MASS.savedSlots = 5
MASS.publishMinInterval = 5

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
    return table.concat(list, ", ", 1, #list - 1) .. L[" y "] .. list[#list]
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
        if recruit.roles[r.key] then table.insert(roles, L[r.label]) end
    end
    local activities = {}
    for _, a in ipairs(RECRUIT_ACTIVITIES) do
        if recruit.activities[a.key] then table.insert(activities, L[a.label]) end
    end

    local sentence = "<" .. guild .. ">" .. (faction and (" (" .. faction .. ")") or "") .. L[" busca "]
    sentence = sentence .. (#roles > 0 and JoinWithY(roles) or "jugadores")
    if #activities > 0 then sentence = sentence .. L[" para "] .. JoinWithY(activities) end

    local parts = { EndSentence(sentence) }
    local days = {}
    for _, d in ipairs(MASS.days) do
        if recruit.days and recruit.days[d.key] then table.insert(days, L[d.label]) end
    end
    if #days > 0 then table.insert(parts, EndSentence(L["Días: "] .. JoinWithY(days))) end
    if strtrim(recruit.schedule) ~= "" then table.insert(parts, EndSentence(L["Horario: "] .. recruit.schedule)) end
    if strtrim(recruit.extra) ~= "" then table.insert(parts, EndSentence(recruit.extra)) end
    return table.concat(parts, " ")
end

-- Número del canal de chat cuyo nombre empieza por "name" (p. ej. "Comercio" encuentra
-- "Comercio - Ciudad"), o nil si el jugador no está en él
local function FindChatChannel(name)
    if not name or strtrim(name) == "" then return nil end
    local wanted = string.lower(strtrim(name))
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        local id, channelName = list[i], list[i + 1]
        if type(channelName) == "string" and string.find(string.lower(channelName), wanted, 1, true) == 1 then return id end
    end
    local id = GetChannelName(name)
    if id and id > 0 then return id end
    return nil
end

-- Sustituye {nombre} (sin reino) y {hermandad}; nil si el resultado no cabe en el chat
local function ExpandMessage(template, name)
    local short = string.match(name or "", "^([^-]+)") or name or ""
    local msg = string.gsub(addonTable.NormalizeVars(template), "{nombre}", function() return short end)
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
    iconsLabel:SetText(L["Iconos:"])
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
            GameTooltip:SetText(L[iconName] .. L["  {rt"] .. i .. "}", 1, 1, 1)
            GameTooltip:AddLine(L["Clic para insertarlo en el mensaje"], 0.7, 0.7, 0.7)
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
        preview:SetText(L["|cFF808080Vista previa:|r "] .. RenderRaidIcons(text))
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

    -- Cuatro contenedores: qué buscáis, mensaje, enviar a un jugador y publicar en un canal
    local searchBox = CreateColoredPanel(panel, L["1. ¿Qué buscáis?"], PANEL_COLORS.blue, 872, 134)
    searchBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -50)
    local messageBox = CreateColoredPanel(panel, "", PANEL_COLORS.blue, 872, 132)
    messageBox:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -8)
    local sendBox = CreateColoredPanel(panel, L["3. Enviar a un jugador"], PANEL_COLORS.blue, 872, 88)
    sendBox:SetPoint("TOPLEFT", messageBox, "BOTTOMLEFT", 0, -8)
    local publishBox = CreateColoredPanel(panel, L["4. Publicar en:"], PANEL_COLORS.blue, 872, 84)
    publishBox:SetPoint("TOPLEFT", sendBox, "BOTTOMLEFT", 0, -8)

    local function CreateCheckRow(labelText, yOffset, items, tableKey)
        local label = searchBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", searchBox, "TOPLEFT", 14, yOffset)
        label:SetText(labelText)

        local checks = {}
        for i, item in ipairs(items) do
            local chk = CreateFrame("CheckButton", "GC_Recruit_" .. tableKey .. "_" .. item.key, searchBox, "UICheckButtonTemplate")
            chk:SetSize(24, 24)
            chk:SetPoint("LEFT", label, "LEFT", 80 + (i - 1) * 135, 0)
            _G[chk:GetName() .. "Text"]:SetText(L[item.label])
            chk:SetScript("OnClick", function(self)
                recruit()[tableKey][item.key] = self:GetChecked() and true or false
            end)
            checks[item.key] = chk
        end
        return checks
    end

    local roleChecks = CreateCheckRow(L["Roles:"], -38, RECRUIT_ROLES, "roles")
    local activityChecks = CreateCheckRow(L["Actividades:"], -62, RECRUIT_ACTIVITIES, "activities")

    local scheduleLabel, scheduleInput = CreateLabeledInput(searchBox, L["Horario:"], 220, L["Ej.: de 21:00 a 00:00"])
    scheduleLabel:SetPoint("TOPLEFT", searchBox, "TOPLEFT", 14, -88)
    scheduleInput:SetMaxLetters(80)

    -- Días de juego: se añaden al mensaje («Días: lunes, miércoles y jueves.»)
    local daysLabel = searchBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    daysLabel:SetPoint("LEFT", scheduleInput, "RIGHT", 16, 0)
    daysLabel:SetText(L["Días:"])
    local dayChecks = {}
    for i, d in ipairs(MASS.days) do
        local chk = CreateFrame("CheckButton", "GC_Recruit_day_" .. d.key, searchBox, "UICheckButtonTemplate")
        chk:SetSize(24, 24)
        chk:SetPoint("LEFT", daysLabel, "RIGHT", 4 + (i - 1) * 44, 0)
        _G[chk:GetName() .. "Text"]:SetText(L[d.short])
        chk:SetScript("OnClick", function(self)
            local r = recruit()
            if type(r.days) ~= "table" then r.days = {} end
            r.days[d.key] = self:GetChecked() and true or nil
        end)
        chk:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L[d.label], 1, 1, 1)
            GameTooltip:Show()
        end)
        chk:SetScript("OnLeave", function() GameTooltip:Hide() end)
        dayChecks[d.key] = chk
    end

    local extraLabel, extraInput = CreateLabeledInput(searchBox, L["Texto final:"], 520)
    extraLabel:SetPoint("TOPLEFT", searchBox, "TOPLEFT", 14, -114)
    extraInput:SetMaxLetters(120)

    scheduleInput:SetScript("OnTextChanged", function(self)
        recruit().schedule = self:GetText() or ""
        SetPlaceholderVisibility(self)
    end)
    extraInput:SetScript("OnTextChanged", function(self) recruit().extra = self:GetText() or "" end)

    local btnGenerate = CreateFrame("Button", nil, searchBox, "UIPanelButtonTemplate")
    btnGenerate:SetSize(150, 22)
    btnGenerate:SetPoint("BOTTOMRIGHT", searchBox, "BOTTOMRIGHT", -14, 12)
    btnGenerate:SetText(L["Generar mensaje"])

    local editor = CreateMessageEditor(messageBox, btnGenerate, L["2. Mensaje (puedes retocarlo a mano)"], 62,
        function(text) recruit().message = text end, 848)
    editor.label:ClearAllPoints()
    editor.label:SetPoint("LEFT", messageBox.header, "LEFT", 8, 0)
    editor.box:ClearAllPoints()
    editor.box:SetPoint("TOPLEFT", messageBox, "TOPLEFT", 12, -48)

    -- El mensaje completo en la vista previa de la derecha (la línea de abajo se corta)
    local function ShowMessagePreview()
        local text = editor.GetText()
        SetPreviewText(L["|cFFFFD100Mensaje de reclutamiento|r"] .. "\n\n"
            .. (text ~= "" and RenderRaidIcons(ExpandMessage(text, "") or text) or L["|cFF808080(vacío)|r"])
            .. "\n\n|cFF808080" .. #text .. "/" .. MAX_CHAT_BYTES .. "|r")
    end
    editor.edit:HookScript("OnTextChanged", function() if panel:IsVisible() then ShowMessagePreview() end end)

    -- Hasta MASS.savedSlots mensajes guardados: elegir uno lo carga en el editor
    local selectedSlot = nil
    local function Saved()
        local r = recruit()
        if type(r.saved) ~= "table" then r.saved = {} end
        return r.saved
    end
    local function SlotLabel(i)
        local text = Saved()[i]
        if not text or text == "" then return i .. ". " .. L["|cFF808080(vacío)|r"] end
        local short = string.gsub(text, "{rt%d}", "")
        if #short > 40 then short = string.sub(short, 1, 38) .. "…" end
        return i .. ". " .. short
    end
    local dropSaved = CreateFrame("DropdownButton", "GC_RecruitSaved", messageBox, "WowStyle1DropdownTemplate")
    dropSaved:SetPoint("TOPLEFT", messageBox, "TOPLEFT", 12, -24)
    dropSaved:SetWidth(260)
    dropSaved:SetHeight(22)
    local function UpdateSavedText()
        dropSaved:SetText(selectedSlot and SlotLabel(selectedSlot) or L["Mensajes guardados"])
    end
    dropSaved:SetupMenu(function(_, root)
        for i = 1, MASS.savedSlots do
            root:CreateRadio(SlotLabel(i), function() return selectedSlot == i end, function()
                selectedSlot = i
                local text = Saved()[i]
                if text and text ~= "" then
                    editor.SetText(text)
                    editor.edit:ClearFocus()
                end
                UpdateSavedText()
                ShowMessagePreview()
            end)
        end
    end)
    local btnSaveSlot = CreateFrame("Button", nil, messageBox, "UIPanelButtonTemplate")
    btnSaveSlot:SetSize(80, 22)
    btnSaveSlot:SetPoint("LEFT", dropSaved, "RIGHT", 6, 0)
    btnSaveSlot:SetText(L["Guardar"])
    btnSaveSlot:SetScript("OnClick", function()
        local text = editor.GetText()
        if text == "" then return end
        local saved = Saved()
        if not selectedSlot then
            -- Sin ranura elegida: la primera libre (o la 1 si están todas ocupadas)
            selectedSlot = 1
            for i = 1, MASS.savedSlots do
                if not saved[i] or saved[i] == "" then selectedSlot = i; break end
            end
        end
        saved[selectedSlot] = text
        UpdateSavedText()
        PrintGC(string.format(L["Mensaje guardado en la ranura %d."], selectedSlot))
    end)
    local btnDeleteSlot = CreateFrame("Button", nil, messageBox, "UIPanelButtonTemplate")
    btnDeleteSlot:SetSize(70, 22)
    btnDeleteSlot:SetPoint("LEFT", btnSaveSlot, "RIGHT", 4, 0)
    btnDeleteSlot:SetText(L["Borrar"])
    btnDeleteSlot:SetScript("OnClick", function()
        if not selectedSlot then return end
        Saved()[selectedSlot] = nil
        UpdateSavedText()
    end)
    for _, info in ipairs({
        { dropSaved, L["Mensajes guardados"], L["Elige un mensaje para cargarlo en el editor y verlo completo en la vista previa."] },
        { btnSaveSlot, L["Guardar"], L["Guarda el mensaje del editor en la ranura elegida (o en la primera libre)."] },
        { btnDeleteSlot, L["Borrar"], L["Vacía la ranura elegida."] },
    }) do
        info[1]:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(info[2], 1, 1, 1)
            GameTooltip:AddLine(info[3], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        info[1]:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    btnGenerate:SetScript("OnClick", function()
        editor.SetText(ComposeRecruitMessage(recruit()))
        editor.edit:ClearFocus()
    end)

    local nameInput = CreateFrame("EditBox", nil, sendBox, "InputBoxTemplate")
    nameInput:SetSize(200, 20)
    nameInput:SetPoint("TOPLEFT", sendBox, "TOPLEFT", 20, -30)
    nameInput:SetAutoFocus(false)
    nameInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local namePlaceholder = nameInput:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    namePlaceholder:SetPoint("LEFT", nameInput, "LEFT", 2, 0)
    namePlaceholder:SetText(L["Nombre o Nombre-Reino"])
    nameInput:SetScript("OnTextChanged", function(self) namePlaceholder:SetShown((self:GetText() or "") == "") end)

    local btnTarget = CreateFrame("Button", nil, sendBox, "UIPanelButtonTemplate")
    btnTarget:SetSize(120, 22)
    btnTarget:SetPoint("LEFT", nameInput, "RIGHT", 10, 0)
    btnTarget:SetText(L["Usar objetivo"])
    btnTarget:SetScript("OnClick", function()
        if UnitIsPlayer("target") then
            local name, realm = UnitName("target")
            nameInput:SetText(realm and realm ~= "" and (name .. "-" .. realm) or name)
        else
            PrintGC(L["No tienes a ningún jugador como objetivo."])
        end
    end)

    local chkAutoWhisper = CreateFrame("CheckButton", "GC_RecruitAutoWhisper", sendBox, "UICheckButtonTemplate")
    chkAutoWhisper:SetSize(24, 24)
    chkAutoWhisper:SetPoint("LEFT", btnTarget, "RIGHT", 24, 0)
    _G[chkAutoWhisper:GetName() .. "Text"]:SetText(L["Invitar a la hermandad a quien me susurre"])
    chkAutoWhisper:SetScript("OnClick", function(self) recruit().autoInviteWhisper = self:GetChecked() and true or false end)
    chkAutoWhisper:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Invitar a la hermandad a quien me susurre"], 1, 1, 1)
        GameTooltip:AddLine(L["Quien te susurre y no sea de la hermandad recibe una invitación al momento. Se salta la lista negra y a quien ya invitaste en los últimos 7 días. Si ya tiene hermandad, el juego la rechaza."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    chkAutoWhisper:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function TargetName()
        local name = strtrim(nameInput:GetText() or "")
        if name == "" then
            PrintGC(L["|cFFFF3333Escribe el nombre del jugador.|r"])
            return nil
        end
        return name
    end

    local function MessageFor(name)
        local template = editor.GetText()
        if template == "" then
            PrintGC(L["|cFFFF3333El mensaje está vacío: pulsa \"Generar mensaje\" o escríbelo.|r"])
            return nil
        end
        local msg = ExpandMessage(template, name)
        if not msg then
            PrintGC(L["|cFFFF3333El mensaje supera los "] .. MAX_CHAT_BYTES .. L[" caracteres del chat.|r"])
        end
        return msg
    end

    local actions = {
        { L["Susurrar mensaje"], function(name)
            local msg = MessageFor(name)
            if msg then SendWhisper(name, msg) end
        end },
        { L["Invitar a la hermandad"], function(name) InviteToGuild(name) end },
        { L["Susurrar e invitar"], function(name)
            local msg = MessageFor(name)
            if msg then
                SendWhisper(name, msg)
                InviteToGuild(name)
            end
        end },
    }

    local previous = nil
    for _, action in ipairs(actions) do
        local btn = CreateFrame("Button", nil, sendBox, "UIPanelButtonTemplate")
        btn:SetSize(170, 22)
        if previous then
            btn:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        else
            btn:SetPoint("TOPLEFT", nameInput, "BOTTOMLEFT", -6, -8)
        end
        btn:SetText(action[1])
        btn:SetScript("OnClick", function()
            local name = TargetName()
            if name then action[2](name) end
        end)
        previous = btn
    end

    -- Para canales (Comercio, Reclutamiento...): se abre en el chat y el jugador elige dónde enviarlo
    local btnOpenChat = CreateFrame("Button", nil, sendBox, "UIPanelButtonTemplate")
    btnOpenChat:SetSize(170, 22)
    btnOpenChat:SetPoint("LEFT", previous, "RIGHT", 8, 0)
    btnOpenChat:SetText(L["Abrir en el chat"])
    btnOpenChat:SetScript("OnClick", function()
        local msg = ExpandMessage(editor.GetText(), "")
        if msg and msg ~= "" then OpenChatWith(msg) end
    end)

    -- 4. Publicar en un canal: grito o canal General, Comercio o Mundo (los nombres de los
    -- canales se cambian en Configuración). Se envía con el clic, como si lo escribiera el jugador.
    local PUBLISH_OPTIONS = {
        { key = "yell", label = "Gritar" },
        { key = "general", label = "Canal General" },
        { key = "trade", label = "Canal de Comercio" },
        { key = "world", label = "Canal Mundo" },
    }
    local function PublishLabel(key)
        for _, option in ipairs(PUBLISH_OPTIONS) do
            if option.key == key then
                if key == "yell" then return L[option.label] end
                local channelName = GuildControlDB.settings.recruitChannels and GuildControlDB.settings.recruitChannels[key] or ""
                return L[option.label] .. " |cFF808080(" .. channelName .. ")|r"
            end
        end
        return ""
    end

    local dropPublish = CreateFrame("DropdownButton", "GC_RecruitPublish", publishBox, "WowStyle1DropdownTemplate")
    dropPublish:SetPoint("TOPLEFT", publishBox, "TOPLEFT", 14, -30)
    dropPublish:SetWidth(250)
    dropPublish:SetupMenu(function(_, root)
        for _, option in ipairs(PUBLISH_OPTIONS) do
            local key = option.key
            root:CreateRadio(PublishLabel(key), function() return recruit().publishChannel == key end, function()
                recruit().publishChannel = key
                dropPublish:SetText(PublishLabel(key))
            end)
        end
    end)

    local btnPublish = CreateFrame("Button", nil, publishBox, "UIPanelButtonTemplate")
    btnPublish:SetSize(110, 22)
    btnPublish:SetPoint("LEFT", dropPublish, "RIGHT", 8, 0)
    btnPublish:SetText(L["Publicar"])
    btnPublish:SetScript("OnClick", function() uiModule.PublishRecruit() end)
    uiModule.RecruitChannelLabel = function() return PublishLabel(recruit().publishChannel or "trade") end

    -- Aviso periódico: el juego no deja que un addon escriba solo en canales públicos ni grite,
    -- así que cada N minutos sale una ventanita y el mensaje se publica con un clic
    local chkAuto = CreateFrame("CheckButton", "GC_RecruitAutoPublish", publishBox, "UICheckButtonTemplate")
    chkAuto:SetSize(24, 24)
    chkAuto:SetPoint("LEFT", btnPublish, "RIGHT", 20, 0)
    _G[chkAuto:GetName() .. "Text"]:SetText(L["Avisarme para publicar cada"])
    local intervalInput = CreateFrame("EditBox", nil, publishBox, "InputBoxTemplate")
    intervalInput:SetSize(34, 20)
    intervalInput:SetPoint("LEFT", _G[chkAuto:GetName() .. "Text"], "RIGHT", 10, 0)
    intervalInput:SetAutoFocus(false)
    intervalInput:SetNumeric(true)
    intervalInput:SetMaxLetters(3)
    local minLabel = publishBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    minLabel:SetPoint("LEFT", intervalInput, "RIGHT", 4, 0)
    minLabel:SetText(L["min"])
    local function SaveInterval()
        local minutes = math.max(MASS.publishMinInterval, tonumber(intervalInput:GetText()) or 15)
        recruit().autoInterval = minutes
        intervalInput:SetText(tostring(minutes))
        intervalInput:ClearFocus()
    end
    intervalInput:SetScript("OnEnterPressed", SaveInterval)
    intervalInput:SetScript("OnEditFocusLost", SaveInterval)
    intervalInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    chkAuto:SetScript("OnClick", function(self)
        local r = recruit()
        r.autoPublish = self:GetChecked() and true or false
        r.lastPublishAt = time()   -- la cuenta empieza ahora
    end)
    chkAuto:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Avisarme para publicar cada"], 1, 1, 1)
        GameTooltip:AddLine(L["Cada vez que pase ese tiempo (mínimo 5 min) aparece una ventana para publicar el mensaje en el canal elegido con un clic. El juego no deja que un addon escriba solo en canales públicos."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    chkAuto:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local hint = publishBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", publishBox, "TOPLEFT", 16, -60)
    hint:SetWidth(840)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["{nombre} = nombre del jugador, {hermandad} = nombre de la hermandad. \"Abrir en el chat\" coloca el mensaje en tu caja de chat para publicarlo en el canal que elijas (por ejemplo /2 para Comercio)."])

    panel:SetScript("OnShow", function()
        local r = recruit()
        for key, chk in pairs(roleChecks) do chk:SetChecked(r.roles[key]) end
        for key, chk in pairs(activityChecks) do chk:SetChecked(r.activities[key]) end
        scheduleInput:SetText(r.schedule or "")
        extraInput:SetText(r.extra or "")
        for key, chk in pairs(dayChecks) do chk:SetChecked(type(r.days) == "table" and r.days[key] or false) end
        if (r.message or "") == "" then r.message = ComposeRecruitMessage(r) end
        editor.SetText(r.message)
        dropPublish:SetText(PublishLabel(r.publishChannel or "trade"))
        chkAutoWhisper:SetChecked(r.autoInviteWhisper == true)
        chkAuto:SetChecked(r.autoPublish == true)
        intervalInput:SetText(tostring(r.autoInterval or 15))
        UpdateSavedText()
        -- SwitchTab pone después el texto de la pestaña: la vista previa del mensaje, al fotograma siguiente
        C_Timer.After(0, function() if panel:IsVisible() then ShowMessagePreview() end end)
    end)
end

-- Publica el mensaje de reclutamiento en el canal elegido (botón Publicar y aviso periódico).
-- Tiene que venir de un clic: el juego no deja escribir en canales públicos ni gritar sin él.
function uiModule.PublishRecruit()
    local recruit = GuildControlDB.settings.recruit
    local msg = ExpandMessage(recruit.message or "", "")
    if not msg or msg == "" then
        PrintGC(L["|cFFFF3333El mensaje está vacío: pulsa \"Generar mensaje\" o escríbelo.|r"])
        return false
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local key = recruit.publishChannel or "trade"
    if key == "yell" then
        send(msg, "YELL")
        recruit.lastPublishAt = time()
        return true
    end
    local channelName = GuildControlDB.settings.recruitChannels[key]
    local channelId = FindChatChannel(channelName)
    if not channelId then
        PrintGC(L["|cFFFF3333No estás en el canal "] .. (channelName or "?") .. L[". Únete a él o cambia su nombre en Configuración.|r"])
        return false
    end
    send(msg, "CHANNEL", nil, channelId)
    recruit.lastPublishAt = time()
    return true
end

StaticPopupDialogs["GUILDCONTROL_RECRUIT_PUBLISH"] = {
    text = "%s",
    button1 = L["Publicar"],
    button2 = L["Ahora no"],
    button3 = L["Desactivar"],
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function() uiModule.PublishRecruit() end,
    OnCancel = function() GuildControlDB.settings.recruit.lastPublishAt = time() end,
    OnAlt = function()
        GuildControlDB.settings.recruit.autoPublish = false
        PrintGC(L["Aviso para publicar el reclutamiento desactivado (Invitar > Publicar en)."])
    end,
}

-- Aviso periódico para publicar e invitación a quien susurra (settings.recruit)
do
    local sessionStart = time()
    C_Timer.NewTicker(30, function()
        local r = GuildControlDB and GuildControlDB.settings and GuildControlDB.settings.recruit
        if not r or not r.autoPublish or not IsInGuild() or InCombatLockdown() then return end
        local now = time()
        if now - sessionStart < 60 then return end
        local interval = math.max(MASS.publishMinInterval, tonumber(r.autoInterval) or 15) * 60
        if not r.lastPublishAt or r.lastPublishAt > now then r.lastPublishAt = now; return end
        if now - r.lastPublishAt < interval then return end
        if StaticPopup_Visible("GUILDCONTROL_RECRUIT_PUBLISH") then return end
        local where = uiModule.RecruitChannelLabel and uiModule.RecruitChannelLabel() or (r.publishChannel or "")
        StaticPopup_Show("GUILDCONTROL_RECRUIT_PUBLISH",
            L["|cFF00FFFF[GuildControl]|r ¿Publicar el mensaje de reclutamiento?"] .. "\n" .. where)
    end)

    local whisperWatcher = CreateFrame("Frame")
    whisperWatcher:RegisterEvent("CHAT_MSG_WHISPER")
    whisperWatcher:SetScript("OnEvent", function(_, _, _, sender, _, _, _, flags)
        local r = GuildControlDB and GuildControlDB.settings and GuildControlDB.settings.recruit
        if not r or not r.autoInviteWhisper then return end
        if issecretvalue and (issecretvalue(sender) or issecretvalue(flags)) then return end
        if type(sender) ~= "string" or sender == "" or flags == "GM" or flags == "DEV" then return end
        if not IsInGuild() or (CanGuildInvite and not CanGuildInvite()) then return end
        if addonTable.IsMe and addonTable.IsMe(sender) then return end
        local key = addonTable.NormalizeName(sender)
        if not key or GuildControlDB.members[key] then return end
        if addonTable.Blacklist and addonTable.Blacklist.IsBlacklisted(sender) then return end
        local history = GuildControlDB.inviteHistory
        local now = time()
        if history[key] and now - history[key] < MASS.reinviteDays * 86400 then return end
        history[key] = now
        C_Timer.After(1, function() InviteToGuild(sender) end)
    end)
end

-- -------------------------------------------------------------------------
-- Modo masivo: cola de jugadores, búsqueda /who y envío por lotes
-- -------------------------------------------------------------------------
-- Nombres de la invitación masiva: tal como se escribieron o como los da /who (con apellido
-- en Forever), porque se usan para invitar y susurrar
local function NormalizePlayerName(name)
    name = strtrim(name or "")
    return name ~= "" and name or nil
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

    -- Cuatro contenedores: búsqueda /who, cola, susurro e invitar
    local whoBox = CreateColoredPanel(panel, L["1. Buscar jugadores sin hermandad (/who)"], PANEL_COLORS.blue, 300, 190)
    whoBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -50)
    local queuePanel = CreateColoredPanel(panel, "", PANEL_COLORS.blue, 564, 190)
    queuePanel:SetPoint("TOPLEFT", whoBox, "TOPRIGHT", 8, 0)
    local messageBox = CreateColoredPanel(panel, "", PANEL_COLORS.blue, 872, 126)
    messageBox:SetPoint("TOPLEFT", whoBox, "BOTTOMLEFT", 0, -8)
    local sendBox = CreateColoredPanel(panel, L["3. Invitar"], PANEL_COLORS.blue, 872, 128)
    sendBox:SetPoint("TOPLEFT", messageBox, "BOTTOMLEFT", 0, -8)

    -- 1a. Búsqueda /who de jugadores sin hermandad
    local minLabel, minInput = CreateLabeledInput(whoBox, L["Nivel mínimo:"], 40)
    minLabel:SetPoint("TOPLEFT", whoBox, "TOPLEFT", 14, -40)
    minInput:SetNumeric(true)
    minInput:SetMaxLetters(3)

    local maxLabel, maxInput = CreateLabeledInput(whoBox, L["Nivel máximo:"], 40)
    maxLabel:SetPoint("TOPLEFT", minLabel, "BOTTOMLEFT", 0, -16)
    maxInput:SetNumeric(true)
    maxInput:SetMaxLetters(3)

    local extraWhoLabel, extraWhoInput = CreateLabeledInput(whoBox, L["Filtro extra:"], 120, L["Clase, zona..."])
    extraWhoLabel:SetPoint("TOPLEFT", maxLabel, "BOTTOMLEFT", 0, -16)
    extraWhoInput:SetScript("OnTextChanged", SetPlaceholderVisibility)

    local btnWho = CreateFrame("Button", nil, whoBox, "UIPanelButtonTemplate")
    btnWho:SetSize(130, 22)
    btnWho:SetPoint("TOPLEFT", extraWhoLabel, "BOTTOMLEFT", 0, -16)
    btnWho:SetText(L["Buscar y añadir"])

    -- 1b. Cola (el título del contenedor dice cuántos hay)
    local queueTitle = queuePanel.title

    local queueBox = CreateBackdropBox(queuePanel, 540, 124, "TOPLEFT", queuePanel, "TOPLEFT", 12, -30)
    local queueScroll = CreateFrame("ScrollFrame", nil, queueBox, "UIPanelScrollFrameTemplate")
    queueScroll:SetPoint("TOPLEFT", queueBox, "TOPLEFT", 6, -6)
    queueScroll:SetPoint("BOTTOMRIGHT", queueBox, "BOTTOMRIGHT", -26, 6)
    local queueChild = CreateFrame("Frame")
    queueChild:SetSize(286, 1)
    queueScroll:SetScrollChild(queueChild)

    local btnClear = CreateFrame("Button", nil, queuePanel, "UIPanelButtonTemplate")
    btnClear:SetSize(100, 22)
    btnClear:SetPoint("TOPLEFT", queueBox, "BOTTOMLEFT", 0, -4)
    btnClear:SetText(L["Vaciar cola"])

    local btnClearDone = CreateFrame("Button", nil, queuePanel, "UIPanelButtonTemplate")
    btnClearDone:SetSize(130, 22)
    btnClearDone:SetPoint("LEFT", btnClear, "RIGHT", 6, 0)
    btnClearDone:SetText(L["Quitar procesados"])

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
            row.statusFs:SetText(MASS_STATUS_TEXT[item.status] and L[MASS_STATUS_TEXT[item.status]] or item.status)
            row:Show()
        end
        queueChild:SetHeight(math.max(1, #queue * 16))

        local pending, invited = CountByStatus()
        queueTitle:SetText(L["Cola: "] .. #queue .. L[" jugadores"])
        if statusText then
            statusText:SetText(L["Pendientes: |cFFFFD100"] .. pending .. L["|r   Invitados: |cFF00FF00"] .. invited .. "|r")
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
        PrintGC(L["/who: "] .. total .. L[" resultados, |cFFFFD100"] .. added .. L["|r sin hermandad añadidos a la cola."])
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
            PrintGC(L["|cFFFF3333No se pudo lanzar la búsqueda /who.|r"])
        end
    end)

    -- 2. Susurro editable ----------------------------------------------------
    local editor = CreateMessageEditor(messageBox, btnWho, L["2. Susurro que recibe cada jugador al invitarlo"], 50,
        function(text) recruit().massMessage = text end, 848)
    editor.label:ClearAllPoints()
    editor.label:SetPoint("LEFT", messageBox.header, "LEFT", 8, 0)
    editor.box:ClearAllPoints()
    editor.box:SetPoint("TOPLEFT", messageBox, "TOPLEFT", 12, -48)

    -- 3. Envío ---------------------------------------------------------------
    local chkWhisper = CreateFrame("CheckButton", "GC_MassInviteWhisper", sendBox, "UICheckButtonTemplate")
    chkWhisper:SetSize(24, 24)
    chkWhisper:SetPoint("TOPLEFT", sendBox, "TOPLEFT", 10, -28)
    _G[chkWhisper:GetName() .. "Text"]:SetText(L["Enviar el susurro con cada invitación"])
    chkWhisper:SetScript("OnClick", function(self) recruit().massWhisper = self:GetChecked() and true or false end)

    local btnNext = CreateFrame("Button", nil, sendBox, "UIPanelButtonTemplate")
    btnNext:SetSize(150, 22)
    btnNext:SetPoint("TOPLEFT", sendBox, "TOPLEFT", 14, -58)
    btnNext:SetText(L["Invitar siguiente"])

    local btnBatch = CreateFrame("Button", nil, sendBox, "UIPanelButtonTemplate")
    btnBatch:SetSize(190, 22)
    btnBatch:SetPoint("LEFT", btnNext, "RIGHT", 8, 0)
    btnBatch:SetText(L["Invitar lote ("] .. MASS.batchSize .. ")")

    local btnStop = CreateFrame("Button", nil, sendBox, "UIPanelButtonTemplate")
    btnStop:SetSize(100, 22)
    btnStop:SetPoint("LEFT", btnBatch, "RIGHT", 8, 0)
    btnStop:SetText(L["Detener"])
    btnStop:Disable()

    statusText = sendBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusText:SetPoint("LEFT", btnStop, "RIGHT", 20, 0)

    local hint = sendBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", btnNext, "BOTTOMLEFT", 0, -10)
    hint:SetWidth(840)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["Se omiten los miembros de la hermandad y a quien ya se invitó en los últimos "] .. MASS.reinviteDays .. L[" días. El lote envía una invitación cada "] .. MASS.batchInterval .. L[" s. Muchos susurros a desconocidos pueden acabar en denuncias por spam: úsalo con moderación."])

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
                elseif history[item.name] and now - history[item.name] < MASS.reinviteDays * 86400 then
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
        if not ProcessNext() then PrintGC(L["No quedan jugadores pendientes en la cola."]) end
    end)

    btnBatch:SetScript("OnClick", function()
        if batchTicker then return end
        local remaining = MASS.batchSize
        if not ProcessNext() then
            PrintGC(L["No quedan jugadores pendientes en la cola."])
            return
        end
        remaining = remaining - 1
        btnBatch:Disable()
        btnStop:Enable()
        batchTicker = C_Timer.NewTicker(MASS.batchInterval, function()
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
    title:SetText(L["Invitar nuevos miembros"])

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
    btnMass:SetText(L["Invitación masiva"])

    local btnSingle = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnSingle:SetSize(160, 22)
    btnSingle:SetPoint("RIGHT", btnMass, "LEFT", -6, 0)
    btnSingle:SetText(L["Invitación individual"])

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
        nota = event and (event.note or event.description) or "",
        hermandad = addonTable.GetDisplayGuildName(),
        nombre = fullName and (string.match(fullName, "^([^-]+)") or fullName) or "",
        rol = slot and L[ROSTER_ROLE_WORDS[slot]] or "",
    }
    local msg = string.gsub(addonTable.NormalizeVars(template), "{(%a+)}", function(key) return values[key] end)
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
    dateLabel:SetText(L["Fecha de banda:"])

    local dropEvent = CreateFrame("DropdownButton", "GC_RosterMsgEvent", frame, "WowStyle1DropdownTemplate")
    dropEvent:SetPoint("LEFT", dateLabel, "RIGHT", 10, 0)
    dropEvent:SetWidth(230)

    local chkBench = CreateFrame("CheckButton", "GC_RosterMsgBench", frame, "UICheckButtonTemplate")
    chkBench:SetSize(24, 24)
    chkBench:SetPoint("LEFT", dropEvent, "RIGHT", 14, 0)
    _G[chkBench:GetName() .. "Text"]:SetText(L["Incluir suplentes"])

    local anchor = CreateFrame("Frame", nil, frame)
    anchor:SetSize(1, 1)
    anchor:SetPoint("TOPLEFT", dateLabel, "BOTTOMLEFT", 0, -8)

    local editor = CreateMessageEditor(frame, anchor, L["Mensaje (editable)"], 64,
        function(text) GuildControlDB.settings.rosterMessage = text end, 564)

    local varsHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    varsHint:SetPoint("TOPLEFT", editor.box, "BOTTOMLEFT", 0, -26)
    varsHint:SetWidth(564)
    varsHint:SetJustifyH("LEFT")
    varsHint:SetText(L["Variables: {roster} {jefe} {dificultad} {fecha} {hora} {nota} {hermandad}. Solo al susurrar: {nombre} y {rol} (tanque, sanador, DPS o suplente)."])

    local recipientsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    recipientsText:SetPoint("TOPLEFT", varsHint, "BOTTOMLEFT", 0, -12)

    -- Bandas de la pestaña Raid: las asociadas a este roster o, si no hay, todas las próximas
    local function RosterEvents(roster)
        local E = addonTable.RaidEvents
        local events = E.GetUpcomingForRoster(roster.name)
        if #events == 0 then events = E.GetUpcomingForRoster(nil) end
        return events
    end

    local function SelectedEvent()
        return selectedEventId and addonTable.RaidEvents.Get(selectedEventId) or nil
    end

    -- Integrantes conectados a los que se susurraría (sin mí)
    local function Recipients(roster)
        local list, total = {}, 0
        local me = string.match(UnitName("player") or "", "^(%S+)")   -- sin apellido (Forever)
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
        recipientsText:SetText(L["Destinatarios del susurro: |cFFFFD100"] .. #list .. L["|r conectados de "] .. total .. L[" en el roster."]
            .. (whisperTicker and L["  |cFF00FF00Enviando...|r"] or ""))
    end

    local function Refresh()
        local roster = R.GetSelected()
        frame.title:SetText(L["Anuncio para "] .. R.GetDisplayName(roster))
        if selectedEventId ~= false and not SelectedEvent() then
            -- Por defecto, la próxima banda
            local events = RosterEvents(roster)
            selectedEventId = events[1] and events[1].id or nil
        end
        local event = SelectedEvent()
        dropEvent:SetText(event and (R.FormatEventDate(event) .. L[" · "] .. event.title) or L["Sin fecha"])
        UpdateRecipients()
    end

    dropEvent:SetupMenu(function(_, root)
        local roster = R.GetSelected()
        root:CreateRadio(L["Sin fecha"], function() return not selectedEventId end,
            function() selectedEventId = false; Refresh() end)
        for _, event in ipairs(RosterEvents(roster)) do
            local id = event.id
            local label = R.FormatEventDate(event) .. L[" · "] .. event.title
            root:CreateRadio(label, function() return selectedEventId == id end,
                function() selectedEventId = id; Refresh() end)
        end
    end)
    chkBench:SetScript("OnClick", UpdateRecipients)

    btnGuild = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnGuild:SetSize(180, 24)
    btnGuild:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
    btnGuild:SetText(L["Enviar a la hermandad"])
    btnGuild:SetScript("OnClick", function()
        local roster = R.GetSelected()
        local msg = ExpandRosterMessage(editor.GetText(), roster, SelectedEvent(), nil)
        if msg == "" then return end
        if #msg > MAX_CHAT_BYTES then
            PrintGC(L["|cFFFF3333El mensaje supera los "] .. MAX_CHAT_BYTES .. L[" caracteres del chat.|r"])
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
    btnWhisper:SetText(L["Susurrar a cada uno"])
    btnWhisper:SetScript("OnClick", function(self)
        if whisperTicker then return end
        local roster = R.GetSelected()
        local event = SelectedEvent()
        local template = editor.GetText()
        local queue = {}
        for _, name in ipairs(Recipients(roster)) do
            local msg = ExpandRosterMessage(template, roster, event, name)
            if msg ~= "" and #msg <= MAX_CHAT_BYTES then table.insert(queue, { name = name, msg = msg }) end
        end
        if #queue == 0 then
            PrintGC(L["No hay integrantes conectados a los que susurrar (o el mensaje es demasiado largo)."])
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
                PrintGC(L["Susurros enviados: |cFFFFD100"] .. sent .. "|r.")
                UpdateRecipients()
            end
        end)
        UpdateRecipients()
    end)

    local btnClose = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnClose:SetSize(100, 24)
    btnClose:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
    btnClose:SetText(L["Cerrar"])
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
    hint:SetText(L["Cada línea se envía como un mensaje al chat de hermandad (máximo 255 caracteres por línea). Puedes añadir, quitar o cambiar líneas."])

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
        status:SetText(#lines .. L[" mensajes"] .. (tooLong > 0 and ("  |cFFFF3333" .. tooLong .. L[" línea(s) pasan de 255 caracteres|r"]) or ""))
    end
    edit:SetScript("OnTextChanged", UpdateStatus)

    local function Regenerate()
        local roster = R.GetSelected()
        frame.title:SetText(L["Anunciar "] .. R.GetDisplayName(roster))
        edit:SetText(table.concat(R.BuildAnnounceLines(roster), "\n"))
        UpdateStatus()
    end

    local btnSend = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnSend:SetSize(180, 24)
    btnSend:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
    btnSend:SetText(L["Enviar a la hermandad"])
    btnSend:SetScript("OnClick", function()
        if not IsInGuild() then return end
        local lines = Lines()
        for _, line in ipairs(lines) do
            if #line > MAX_CHAT_BYTES then
                PrintGC(L["|cFFFF3333Hay líneas de más de "] .. MAX_CHAT_BYTES .. L[" caracteres: pártelas antes de enviar.|r"])
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
    btnRegenerate:SetText(L["Volver a generar"])
    btnRegenerate:SetScript("OnClick", Regenerate)

    local btnClose = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnClose:SetSize(100, 24)
    btnClose:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
    btnClose:SetText(L["Cerrar"])
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
    title:SetPoint("TOPLEFT", view, "TOPLEFT", 16, -12)
    title:SetText(L["Mi perfil"])

    local subtitle = view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("LEFT", title, "RIGHT", 16, 0)

    -- Paneles de colores: a la izquierda lo que declaras, a la derecha tu ficha y lo de oficiales
    local LEFT_X, RIGHT_X, TOP_Y, GAP = 8, 580, -40, 6
    local roleBox = CreateColoredPanel(view, L["Roles"], PANEL_COLORS.blue, 564, 112)
    roleBox:SetPoint("TOPLEFT", view, "TOPLEFT", LEFT_X, TOP_Y)
    local charBox = CreateColoredPanel(view, L["Personaje"], PANEL_COLORS.blue, 564, 112)
    charBox:SetPoint("TOPLEFT", roleBox, "BOTTOMLEFT", 0, -GAP)
    local specBox = CreateColoredPanel(view, L["Especialización"], PANEL_COLORS.blue, 564, 76)
    specBox:SetPoint("TOPLEFT", charBox, "BOTTOMLEFT", 0, -GAP)
    local noteBox = CreateColoredPanel(view, L["Nota y envío"], PANEL_COLORS.blue, 564, 470 - 112 - 112 - 76 - GAP * 3)
    noteBox:SetPoint("TOPLEFT", specBox, "BOTTOMLEFT", 0, -GAP)

    -- Grupo de casillas que se comportan como botones de opción, dentro de un panel
    local function CreateRoleChoice(box, labelText, y, options, onChange)
        local label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", box, "TOPLEFT", 12, y)
        label:SetWidth(120)
        label:SetJustifyH("LEFT")
        label:SetText(labelText)
        local checks, selected = {}, nil
        local group = {}
        function group.Set(value)
            selected = value
            for key, chk in pairs(checks) do chk:SetChecked(key == (value or "Ninguno")) end
        end
        function group.Get() return selected end
        for i, option in ipairs(options) do
            local chk = CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate")
            chk:SetSize(24, 24)
            chk:SetPoint("LEFT", label, "RIGHT", 6 + (i - 1) * 104, 0)
            chk.text = chk:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            chk.text:SetPoint("LEFT", chk, "RIGHT", 2, 0)
            local icon = (option == "Tanque" or option == "Sanador" or option == "DPS") and (RoleIcon(option, 14) .. " ") or ""
            chk.text:SetText(icon .. L[option])
            chk:SetScript("OnClick", function()
                group.Set(option ~= "Ninguno" and option or nil)
                if onChange then onChange() end
            end)
            checks[option] = chk
        end
        -- Deja solo las opciones permitidas, colocadas seguidas
        function group.Filter(isAllowed)
            local shown = 0
            for _, option in ipairs(options) do
                local chk = checks[option]
                local ok = isAllowed(option)
                chk:SetShown(ok)
                if ok then
                    chk:ClearAllPoints()
                    chk:SetPoint("LEFT", label, "RIGHT", 6 + shown * 104, 0)
                    shown = shown + 1
                end
            end
        end
        group.label = label
        return group
    end

    -- Roles (solo los que puede llevar la clase del personaje)
    local mainChoice = CreateRoleChoice(roleBox, L["Rol principal"], -38, P.ROLES)
    local secondaryChoice = CreateRoleChoice(roleBox, L["Rol secundario (opcional)"], -74,
        { "Ninguno", "Tanque", "Sanador", "DPS" })
    -- Cazador, brujo, pícaro y mago: rol DPS fijo, sin opciones
    local fixedRoleText = roleBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fixedRoleText:SetPoint("LEFT", mainChoice.label, "RIGHT", 12, 0)
    fixedRoleText:Hide()
    local function ApplyClassRoles()
        local me = P.GetMyFullName()
        local function Allowed(option)
            return option == "Ninguno" or not addonTable.CanRole or addonTable.CanRole(me, option)
        end
        local ignore = addonTable.Dev and addonTable.Dev.IgnoreClassRoles and addonTable.Dev.IgnoreClassRoles()
        local dpsOnly = addonTable.IsDpsOnlyClass and addonTable.IsDpsOnlyClass(select(2, UnitClass("player"))) and not ignore
        if dpsOnly then
            mainChoice.Filter(function() return false end)
            fixedRoleText:SetText(RoleIcon("DPS", 14) .. " " .. L["Rol DPS"] .. "  |cFF808080" .. L["(tu clase solo puede ser DPS)"] .. "|r")
            mainChoice.Set("DPS")
            secondaryChoice.Set(nil)
        else
            mainChoice.Filter(Allowed)
        end
        fixedRoleText:SetShown(dpsOnly)
        secondaryChoice.label:SetShown(not dpsOnly)
        secondaryChoice.Filter(function(option) return not dpsOnly and Allowed(option) end)
    end
    uiModule.RefreshProfileRoles = ApplyClassRoles

    -- Personaje: principal o alter (y de quién) y enfoque
    local mainNameInput, charChoice   -- declarados antes para que el callback los vea
    charChoice = CreateRoleChoice(charBox, L["Este personaje es"], -38, { "Principal", "Alter" },
        function() mainNameInput:SetShown(charChoice.Get() == "Alter") end)

    mainNameInput = CreateFrame("EditBox", nil, charBox, "InputBoxTemplate")
    mainNameInput:SetSize(170, 20)
    mainNameInput:SetPoint("LEFT", charChoice.label, "RIGHT", 236, 0)
    mainNameInput:SetAutoFocus(false)
    mainNameInput:SetMaxLetters(40)
    mainNameInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    mainNameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local mainNamePlaceholder = mainNameInput:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mainNamePlaceholder:SetPoint("LEFT", mainNameInput, "LEFT", 2, 0)
    mainNamePlaceholder:SetText(L["Nombre de tu principal"])
    mainNameInput:SetScript("OnTextChanged", function(self) mainNamePlaceholder:SetShown((self:GetText() or "") == "") end)
    mainNameInput:Hide()

    -- Enfoque principal del jugador (columna Enfoque de Miembros)
    -- Se aplica al pulsarlo (P.SetMyFocus), sin esperar a Guardar y enviar
    local focusChoice
    focusChoice = CreateRoleChoice(charBox, L["Enfoque"], -74, P.FOCUS, function()
        if P.SetMyFocus then P.SetMyFocus(focusChoice.Get()) end
    end)

    -- Especialización y especialización off, de la clase del personaje
    local SPEC_ROLE_TO_ROLE = { TANK = "Tanque", HEALER = "Sanador", DAMAGER = "DPS" }
    local specLabel = specBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    specLabel:SetPoint("TOPLEFT", specBox, "TOPLEFT", 12, -32)
    specLabel:SetText(L["Especialización"])

    local specValue = ""
    local specDropdown = CreateFrame("DropdownButton", "GC_ProfileSpec", specBox, "WowStyle1DropdownTemplate")
    specDropdown:SetPoint("TOPLEFT", specLabel, "BOTTOMLEFT", 0, -4)
    specDropdown:SetWidth(250)

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
        specDropdown:SetText(specValue ~= "" and specValue or L["Elige tu especialización"])
    end

    specDropdown:SetupMenu(function(_, root)
        for _, spec in ipairs(GetMySpecs()) do
            local label = (spec.icon and ("|T" .. spec.icon .. ":16:16|t ") or "") .. spec.name
                .. (spec.role and ("  " .. RoleIcon(spec.role) .. " |cFF808080" .. L[spec.role] .. "|r") or "")
            root:CreateRadio(label, function() return specValue == spec.name end, function()
                SetSpec(spec.name)
                -- El rol principal sigue al de la especialización elegida (se puede cambiar después)
                if spec.role then mainChoice.Set(spec.role) end
            end)
        end
        root:CreateRadio(L["Sin especificar"], function() return specValue == "" end, function() SetSpec("") end)
    end)

    -- Especialización off: otra de la clase que también puede jugar (solo con equipo para ella)
    local offSpecValue = ""
    local offSpecLabel = specBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    offSpecLabel:SetPoint("TOPLEFT", specBox, "TOPLEFT", 290, -32)
    offSpecLabel:SetText(L["Especialización off |cFFFF7F00(solo si tienes equipo)|r"])

    local offSpecDropdown = CreateFrame("DropdownButton", "GC_ProfileOffSpec", specBox, "WowStyle1DropdownTemplate")
    offSpecDropdown:SetPoint("TOPLEFT", offSpecLabel, "BOTTOMLEFT", 0, -4)
    offSpecDropdown:SetWidth(250)

    local function SetOffSpec(name)
        offSpecValue = name or ""
        offSpecDropdown:SetText(offSpecValue ~= "" and offSpecValue or L["Ninguna"])
    end

    offSpecDropdown:SetupMenu(function(_, root)
        root:CreateTitle(L["Elígela solo si tienes equipo para jugarla"])
        root:CreateRadio(L["Ninguna"], function() return offSpecValue == "" end, function() SetOffSpec("") end)
        for _, spec in ipairs(GetMySpecs()) do
            if spec.name ~= specValue then
                local label = (spec.icon and ("|T" .. spec.icon .. ":16:16|t ") or "") .. spec.name
                    .. (spec.role and ("  " .. RoleIcon(spec.role) .. " |cFF808080" .. L[spec.role] .. "|r") or "")
                root:CreateRadio(label, function() return offSpecValue == spec.name end, function() SetOffSpec(spec.name) end)
            end
        end
    end)

    -- Nota para los oficiales y envío
    local noteLabel = noteBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteLabel:SetPoint("TOPLEFT", noteBox, "TOPLEFT", 12, -32)
    noteLabel:SetText(L["Nota para los oficiales"])

    local noteInput = CreateFrame("EditBox", nil, noteBox, "InputBoxTemplate")
    noteInput:SetSize(530, 20)
    noteInput:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 6, -4)
    noteInput:SetAutoFocus(false)
    noteInput:SetMaxLetters(80)
    local notePlaceholder = noteInput:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    notePlaceholder:SetPoint("LEFT", noteInput, "LEFT", 2, 0)
    notePlaceholder:SetText(L["Disponibilidad, otras especializaciones, alters..."])
    noteInput:SetScript("OnTextChanged", function(self) notePlaceholder:SetShown((self:GetText() or "") == "") end)
    noteInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    noteInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local btnSave = CreateFrame("Button", nil, noteBox, "UIPanelButtonTemplate")
    btnSave:SetSize(160, 24)
    btnSave:SetPoint("TOPLEFT", noteInput, "BOTTOMLEFT", -6, -10)
    btnSave:SetText(L["Guardar y enviar"])

    btnSave:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Guardar y enviar"], 1, 1, 1)
        GameTooltip:AddLine(L["Guarda tu perfil y lo envía a los miembros de la hermandad que usan GuildControl."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnSave:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local saveStatus = noteBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    saveStatus:SetPoint("LEFT", btnSave, "RIGHT", 12, 0)

    local explanation = noteBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    explanation:SetPoint("TOPLEFT", btnSave, "BOTTOMLEFT", 0, -8)
    explanation:SetWidth(536)
    explanation:SetJustifyH("LEFT")
    explanation:SetText(L["Tu rol se envía a los miembros de la hermandad que usan GuildControl. Los oficiales lo ven en Miembros y al montar el roster. Si un oficial te asigna otro rol a mano, prevalece el suyo."])

    btnSave:SetScript("OnClick", function()
        local main = mainChoice.Get()
        if not main then
            saveStatus:SetText(L["|cFFFF3333Elige tu rol principal.|r"])
            return
        end
        local charType = charChoice.Get() == "Alter" and "alt" or "main"
        P.SaveMyProfile(main, secondaryChoice.Get(), specValue, noteInput:GetText(), charType, mainNameInput:GetText(), focusChoice.Get(), offSpecValue)
        noteInput:ClearFocus()
        saveStatus:SetText(L["|cFF00FF00Guardado y enviado a las "] .. date("%H:%M") .. ".|r")
    end)

    -- Derecha: tu ficha y, para oficiales, la gestión de perfiles
    local side = CreateColoredPanel(view, L["Tu ficha en la hermandad"], PANEL_COLORS.blue, 310, 150)
    side:SetPoint("TOPLEFT", view, "TOPLEFT", RIGHT_X, TOP_Y)

    local sideText = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sideText:SetPoint("TOPLEFT", side, "TOPLEFT", 12, -32)
    sideText:SetWidth(286)
    sideText:SetJustifyH("LEFT")
    sideText:SetSpacing(2)

    -- Mis profesiones: un botón; el detalle va en el tooltip y el clic abre la primera profesión
    -- (C_TradeSkillUI) o, si no hay, el libro de profesiones
    local btnMyProfs = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
    btnMyProfs:SetSize(150, 22)
    btnMyProfs:SetPoint("TOPLEFT", sideText, "TOPLEFT", -2, -34)
    btnMyProfs:SetText(L["Mis profesiones"])
    btnMyProfs:SetScript("OnClick", function()
        local prof1, prof2 = GetProfessions()
        local index = prof1 or prof2
        local skillLine = index and select(7, GetProfessionInfo(index))
        if skillLine and C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill and pcall(C_TradeSkillUI.OpenTradeSkill, skillLine) then return end
        if ToggleProfessionsBook then ToggleProfessionsBook() end
    end)
    btnMyProfs:SetScript("OnEnter", function(self)
        local m = GuildControlDB.members[P.GetMyFullName()] or {}
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Mis profesiones"], 1, 1, 1)
        local any = false
        for _, prof in ipairs({ m.prof1, m.prof2 }) do
            if prof and prof ~= "Ninguna" then
                GameTooltip:AddLine(prof, 1, 0.82, 0)
                any = true
            end
        end
        if not any then GameTooltip:AddLine(L["Ninguna"], 0.6, 0.6, 0.6) end
        local recipes = GuildControlDB.recipes and GuildControlDB.recipes[P.GetMyFullName()]
        if type(recipes) == "table" then
            for prof, data in pairs(recipes) do
                GameTooltip:AddDoubleLine(prof, string.format(L["%d recetas compartidas"], #(data.ids or {})), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Clic: abre tu primera profesión (o el libro de profesiones si no tienes). Al cerrar la ventana de una profesión, tus recetas se envían a la hermandad."], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    btnMyProfs:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Tu progreso: DKP o +1, antigüedad, objetos ganados y asistencia
    local progressBox = CreateColoredPanel(view, L["Tu progreso"], PANEL_COLORS.blue, 310, 140)
    progressBox:SetPoint("TOPLEFT", side, "BOTTOMLEFT", 0, -GAP)
    local progressText = progressBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    progressText:SetPoint("TOPLEFT", progressBox, "TOPLEFT", 12, -32)
    progressText:SetWidth(286)
    progressText:SetJustifyH("LEFT")
    progressText:SetSpacing(3)

    local function ProgressLines(me)
        local lines = {}
        local D, LT = addonTable.Dkp, addonTable.Loot
        if D and D.IsActive() then
            local balance = D.GetBalance(me)
            local list, position = D.GetList(), nil
            for i, entry in ipairs(list) do if entry.name == me then position = i end end
            table.insert(lines, L["DKP: |cFFFFD100"] .. balance .. "|r"
                .. (position and (L["   |cFF808080(puesto "] .. position .. L[" de "] .. #list .. ")|r") or ""))
        elseif LT then
            table.insert(lines, L["Tus +1: |cFFFFD100"] .. LT.GetPoints(me) .. "|r")
        end
        local since = D and D.GetSince(me)
        if since then
            table.insert(lines, L["Antigüedad: |cFFFFD100"] .. D.GetSeniorityDays(me) .. L[" días|r |cFF808080(desde el "] .. date("%d/%m/%Y", since) .. ")|r")
        else
            table.insert(lines, L["Antigüedad: |cFF808080empieza al guardar tu perfil|r"])
        end
        if LT then
            local won, last = 0, nil
            for _, entry in ipairs(LT.GetHistory()) do
                if entry.winner == me then
                    won = won + 1
                    last = last or entry
                end
            end
            table.insert(lines, L["Objetos ganados: |cFFFFD100"] .. won .. "|r"
                .. (last and ("  " .. LT.DisplayLink(last.link)) or ""))
        end
        local E = addonTable.RaidEvents
        local stats = E and E.GetAttendanceStats and E.GetAttendanceStats(nil, me)
        if stats and stats.percent then
            table.insert(lines, L["Asistencia: |cFFFFD100"] .. stats.percent .. "%|r |cFF808080(" .. stats.counted .. L[" bandas)|r"])
        else
            table.insert(lines, L["Asistencia: |cFF808080sin bandas con lista todavía|r"])
        end
        -- Mi asistencia en cada roster en el que estoy (hasta 3)
        local R, shownRosters = addonTable.Roster, 0
        local seen = {}
        local rosters = {}
        for _, roster in ipairs(R and R.GetAll() or {}) do table.insert(rosters, roster) end
        for _, item in ipairs(R and R.GetSharedRosters and R.GetSharedRosters() or {}) do table.insert(rosters, item.roster) end
        for _, roster in ipairs(rosters) do
            if shownRosters < 3 and roster.members and roster.members[me] and not seen[roster.name] then
                seen[roster.name] = true
                local rs = E and E.GetAttendanceStats and E.GetAttendanceStats(roster.name, me)
                if rs and rs.percent then
                    shownRosters = shownRosters + 1
                    table.insert(lines, "   |cFF808080" .. roster.name .. ":|r |cFFFFD100" .. rs.percent .. "%|r |cFF808080(" .. rs.counted .. ")|r")
                end
            end
        end
        return table.concat(lines, "\n")
    end

    local officerBox = CreateColoredPanel(view, L["Oficiales"], PANEL_COLORS.blue, 310, 470 - 150 - 140 - GAP * 2)
    officerBox:SetPoint("TOPLEFT", progressBox, "BOTTOMLEFT", 0, -GAP)

    local officerText = officerBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    officerText:SetPoint("TOPLEFT", officerBox, "TOPLEFT", 12, -32)
    officerText:SetWidth(286)
    officerText:SetJustifyH("LEFT")

    local btnRequest = CreateFrame("Button", nil, officerBox, "UIPanelButtonTemplate")
    btnRequest:SetSize(220, 22)
    btnRequest:SetPoint("TOPLEFT", officerText, "BOTTOMLEFT", 0, -10)
    btnRequest:SetText(L["Pedir roles a la hermandad"])
    btnRequest:SetScript("OnClick", function()
        P.RequestRoles()
        PrintGC(L["Petición de roles enviada. Responden los miembros conectados que usan GuildControl."])
    end)

    local rankLabel = officerBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rankLabel:SetPoint("TOPLEFT", btnRequest, "BOTTOMLEFT", 0, -16)
    rankLabel:SetText(L["Perfil de oficial hasta el rango:"])

    local dropRank = CreateFrame("DropdownButton", "GC_OfficerRankSelect", officerBox, "WowStyle1DropdownTemplate")
    dropRank:SetPoint("TOPLEFT", rankLabel, "BOTTOMLEFT", 0, -6)
    dropRank:SetWidth(220)
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

    dropRank:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Perfil de oficial hasta el rango:"], 1, 1, 1)
        GameTooltip:AddLine(L["Ese rango y los superiores ven todas las pestañas. Quien tenga el permiso de chat de oficiales del juego también es oficial. Es un ajuste de tu cliente: cada oficial lo configura en el suyo."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    dropRank:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- ---------------------------------------------------------------------
    -- Subpestañas: Perfil, Lista de deseos y Disponibilidad
    -- ---------------------------------------------------------------------
    local profilePanels = { roleBox, charBox, specBox, noteBox, side, progressBox }
    local profileMode = "profile"
    local wishPage = CreateFrame("Frame", nil, view)
    wishPage:SetPoint("TOPLEFT", view, "TOPLEFT", LEFT_X, TOP_Y)
    wishPage:SetSize(882, 470)
    wishPage:Hide()
    if uiModule.AttachWishlist then uiModule.AttachWishlist(wishPage, 882, 470) end

    local availPage = CreateFrame("Frame", nil, view)
    availPage:SetPoint("TOPLEFT", view, "TOPLEFT", LEFT_X, TOP_Y)
    availPage:SetSize(882, 470)
    availPage:Hide()

    local profileTabs = {}
    local function ShowProfileMode(mode)
        profileMode = mode
        for _, panel in ipairs(profilePanels) do panel:SetShown(mode == "profile") end
        officerBox:SetShown(mode == "profile" and P.IsOfficer())
        wishPage:SetShown(mode == "wish")
        availPage:SetShown(mode == "avail")
        for _, btn in ipairs(profileTabs) do btn:SetEnabled(btn.mode ~= mode) end
    end
    for i, info in ipairs({ { "avail", "Disponibilidad" }, { "wish", "Lista de deseos" }, { "profile", "Perfil" } }) do
        local btn = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
        btn:SetText(L[info[2]])
        local textWidth = btn:GetFontString() and btn:GetFontString():GetStringWidth() or 0
        btn:SetSize(math.max(80, math.ceil(textWidth + 24)), 22)
        if i == 1 then
            btn:SetPoint("TOPRIGHT", view, "TOPRIGHT", -12, -8)
        else
            btn:SetPoint("RIGHT", profileTabs[i - 1], "LEFT", -4, 0)
        end
        btn.mode = info[1]
        btn:SetScript("OnClick", function() ShowProfileMode(info[1]) end)
        profileTabs[i] = btn
    end

    -- Disponibilidad semanal ------------------------------------------------
    local weekAvailBox = CreateColoredPanel(availPage, L["Disponibilidad semanal"], PANEL_COLORS.blue, 882, 150)
    weekAvailBox:SetPoint("TOPLEFT", availPage, "TOPLEFT", 0, 0)
    local daysLabel = weekAvailBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    daysLabel:SetPoint("TOPLEFT", weekAvailBox, "TOPLEFT", 14, -40)
    daysLabel:SetText(L["Días que puedes jugar:"])
    local availDayChecks = {}
    for i, short in ipairs(P.AVAIL_DAYS or {}) do
        local chk = CreateFrame("CheckButton", "GC_AvailDay" .. i, weekAvailBox, "UICheckButtonTemplate")
        chk:SetSize(24, 24)
        chk:SetPoint("LEFT", daysLabel, "RIGHT", 10 + (i - 1) * 50, 0)
        _G[chk:GetName() .. "Text"]:SetText(L[short])
        availDayChecks[i] = chk
    end
    local function TimeInput(parentBox, labelText, anchor, x)
        local label = parentBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, -22)
        label:SetText(labelText)
        local input = CreateFrame("EditBox", nil, parentBox, "InputBoxTemplate")
        input:SetSize(60, 20)
        input:SetPoint("LEFT", label, "RIGHT", 10, 0)
        input:SetAutoFocus(false)
        input:SetMaxLetters(5)
        input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return input, label
    end
    local fromInput, fromLabel = TimeInput(weekAvailBox, L["Desde (HH:MM):"], daysLabel, 0)
    local toInput = TimeInput(weekAvailBox, L["Hasta (HH:MM):"], daysLabel, 200)
    local weekHint = weekAvailBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    weekHint:SetPoint("TOPLEFT", fromLabel, "BOTTOMLEFT", 0, -16)
    weekHint:SetWidth(850)
    weekHint:SetJustifyH("LEFT")
    weekHint:SetText(L["Los oficiales lo ven en Miembros (vista previa) y les ayuda a montar los rosters y las bandas."])

    local btnSaveAvail = CreateFrame("Button", nil, availPage, "UIPanelButtonTemplate")
    btnSaveAvail:SetSize(160, 24)
    btnSaveAvail:SetPoint("TOPLEFT", weekAvailBox, "BOTTOMLEFT", 4, -12)
    btnSaveAvail:SetText(L["Guardar y enviar"])
    local availStatus = availPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    availStatus:SetPoint("LEFT", btnSaveAvail, "RIGHT", 12, 0)

    btnSaveAvail:SetScript("OnClick", function()
        local days = ""
        for i = 1, 7 do days = days .. (availDayChecks[i] and availDayChecks[i]:GetChecked() and "1" or "0") end
        P.SaveMyAvailability({ days = days, from = strtrim(fromInput:GetText() or ""), to = strtrim(toInput:GetText() or "") })
        availStatus:SetText(L["|cFF00FF00Guardado y enviado a las "] .. date("%H:%M") .. ".|r")
    end)

    local function LoadAvailability()
        local a = P.GetMyAvailability and P.GetMyAvailability() or {}
        for i = 1, 7 do
            if availDayChecks[i] then availDayChecks[i]:SetChecked(string.sub(a.days or "", i, i) == "1") end
        end
        fromInput:SetText(a.from or "")
        toInput:SetText(a.to or "")
        availStatus:SetText("")
    end

    view:SetScript("OnShow", function()
        local profile = P.GetMyProfile()
        mainChoice.Set(profile.main)
        secondaryChoice.Set(profile.secondary)
        ApplyClassRoles()
        charChoice.Set(profile.charType == "alt" and "Alter" or "Principal")
        focusChoice.Set(profile.focus)
        mainNameInput:SetText(profile.mainName or "")
        mainNameInput:SetShown(profile.charType == "alt")
        SetSpec(profile.spec)
        SetOffSpec(profile.offSpec)
        specLabel:SetText(L["Especialización ("] .. (UnitClass("player") or "") .. ")")
        noteInput:SetText(profile.note or "")
        saveStatus:SetText("")

        local isOfficer = P.IsOfficer()
        local m = GuildControlDB.members[P.GetMyFullName()] or {}
        subtitle:SetText((UnitName("player") or "") .. L["   ·   Rango: |cFFFFD100"] .. (m.rank or "-") .. L["|r   ·   Perfil: "]
            .. (isOfficer and L["|cFFFFD100Oficial|r"] or L["|cFF00FFFFJugador|r"]))

        local source = m.roleSource == "officer" and L["asignado por un oficial"]
            or (m.roleSource == "declared" and L["declarado por ti"] or L["por defecto"])
        -- Oficial: sus propios rosters. Jugador: los que han publicado los oficiales.
        local rostersText = m.roster or L["Sin Roster"]
        if not isOfficer and uiModule.GetMySharedRosterNames then
            local names = uiModule.GetMySharedRosterNames()
            rostersText = #names > 0 and table.concat(names, ", ") or L["ninguno publicado"]
        end
        sideText:SetText(L["Rol en tu ficha: |cFFFFD100"] .. L[m.role or "DPS"] .. "|r |cFF808080(" .. source .. ")|r\n"
            .. L["Rosters: |cFFFFD100"] .. rostersText .. "|r\n"
            .. "\n\n\n"
            .. L["|cFF808080Esto es lo que guarda tu cliente. Cada oficial tiene su propia copia.|r"])

        progressText:SetText(ProgressLines(P.GetMyFullName()))
        LoadAvailability()
        ShowProfileMode(profileMode)
        if isOfficer then
            local declared, total = P.CountDeclared()
            officerText:SetText(L["Roles declarados: |cFFFFD100"] .. declared .. L["|r de "] .. total .. L[" miembros.\n"]
                .. L["Los ves en Miembros (vista previa) y en los candidatos del roster."])
            local currentRank = P.GetOfficerRankIndex()
            dropRank:SetText(L["Rango "] .. currentRank)
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
    title:SetText(L["Mis rosters"])

    local subtitle = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetText(L["Rosters que publican los oficiales con el botón Compartir. Solo lectura."])

    local dropRoster = CreateFrame("DropdownButton", "GC_MyRostersSelect", view, "WowStyle1DropdownTemplate")
    dropRoster:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)
    dropRoster:SetWidth(220)

    local dropVariant = CreateFrame("DropdownButton", "GC_MyRostersVariant", view, "WowStyle1DropdownTemplate")
    dropVariant:SetPoint("LEFT", dropRoster, "RIGHT", 12, 0)
    dropVariant:SetWidth(170)

    local btnUpdate = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnUpdate:SetSize(110, 22)
    btnUpdate:SetPoint("LEFT", dropVariant, "RIGHT", 12, 0)
    btnUpdate:SetText(L["Actualizar"])
    btnUpdate:SetScript("OnClick", function()
        R.RequestPublishedRosters()
        PrintGC(L["Pidiendo los rosters publicados a los oficiales conectados..."])
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
        if fullName == me then return L["|cFF00FF00>|r |cFF"] .. hex .. short .. L["|r |cFF00FF00(tú)|r"] end
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
        root:CreateRadio(L["Base (todos los jefes)"], function() return selectedVariantId == nil end,
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
        for _, widget in ipairs({ comp, side }) do widget:SetShown(hasItem) end
        dropVariant:Hide()   -- sin jefes: el roster es la lista de personas
        if not hasItem then
            dropRoster:SetText(L["Sin rosters"])
            infoText:SetText("")
            emptyText:SetText(L["Todavía no has recibido ningún roster. Los oficiales deben publicarlo con Compartir; pulsa Actualizar para pedirlo a los que estén conectados."])
            emptyText:Show()
            return
        end
        emptyText:Hide()

        local roster = item.roster
        local me = addonTable.Profiles.GetMyFullName()
        local variant = selectedVariantId and (roster.variants or {})[selectedVariantId] or nil
        dropRoster:SetText(roster.name)
        dropVariant:SetText(variant and variant.name or L["Base"])
        infoText:SetText(L["Publicado por |cFFFFD100"] .. item.from .. "|r" .. (item.fromRank and (" (" .. item.fromRank .. ")") or "")
            .. L[" · "] .. R.DifficultyLabel(roster) .. " " .. roster.size
            .. L[" · recibido "] .. date("%d/%m %H:%M", item.receivedAt or time()))

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
        tankCol:SetText(Block(L["Tanques"], bySlot.tank))
        healerCol:SetText(Block(L["Sanadores"], bySlot.healer))
        local half = math.ceil(#bySlot.dps / 2)
        local dps1, dps2 = {}, {}
        for i, name in ipairs(bySlot.dps) do table.insert(i <= half and dps1 or dps2, name) end
        dpsCol1:SetText(Block("DPS", dps1))
        local lines2 = {}
        for _, name in ipairs(dps2) do table.insert(lines2, NameLine(name, me)) end
        dpsCol2:SetText(table.concat(lines2, "\n"))
        local benchNames = {}
        for _, name in ipairs(bySlot.bench) do table.insert(benchNames, NameLine(name, me)) end
        benchCol:SetText(L["|cFFFFD100Suplentes ("] .. #bySlot.bench .. ")|r\n" .. table.concat(benchNames, "   "))

        -- Mis datos: puesto, próximas bandas (pestaña Raid) con mi respuesta y asistencia
        local SLOT_TEXT = { tank = L["Tanque (titular)"], healer = L["Sanador (titular)"], dps = L["DPS (titular)"], bench = L["Suplente"] }
        local mySlot = R.GetEffectiveMembers(roster, variant)[me]
        local lines = { L["|cFFFFD100Tu puesto|r"], mySlot and SLOT_TEXT[mySlot] or L["|cFF808080No estás en esta composición|r"], "" }

        local E = addonTable.RaidEvents
        table.insert(lines, L["|cFFFFD100Próximas bandas|r"])
        local upcoming = E.GetUpcomingForRoster(roster.name)
        if #upcoming == 0 then table.insert(lines, L["|cFF808080Sin bandas próximas|r"]) end
        for i = 1, math.min(#upcoming, 6) do
            local event = upcoming[i]
            local signup = E.GetMySignup(event)
            local mark = signup and ("|cFF" .. E.STATUS_COLORS[signup.status] .. L[E.STATUS_LABELS[signup.status]] .. "|r")
                or L["|cFFFF7F00sin responder|r"]
            table.insert(lines, R.FormatEventDate(event) .. L[" · "] .. event.title .. "  " .. mark)
        end

        table.insert(lines, "")
        table.insert(lines, L["|cFFFFD100Tu asistencia|r"])
        local stats = E.GetAttendanceStats(roster.name, me)
        if stats.percent then
            table.insert(lines, stats.percent .. "% (" .. (stats.present + stats.late) .. L[" de "] .. stats.counted .. L[" bandas)"])
        else
            table.insert(lines, L["|cFF808080Sin datos todavía|r"])
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

    local currentFilter = "guildAchievement"
    local Refresh

    -- ---------------------------------------------------------------------
    -- Columna izquierda: noticias
    -- ---------------------------------------------------------------------
    local SUMMARY_TOP_HEIGHT = 150   -- fila de cajas de arriba (Para ti, Ahora, Esta semana, Pendiente)
    local feedBox = CreateBackdropBox(view, 566, 500 - SUMMARY_TOP_HEIGHT - 6, "TOPLEFT", view, "TOPLEFT", 10, -10 - SUMMARY_TOP_HEIGHT - 6)

    -- Barra propia con las subpestañas del tablón y Actualizar, todos del mismo ancho y
    -- repartidos a la misma distancia
    local summaryMode = "news"
    local tabBar = CreateBackdropBox(feedBox, 546, 32, "TOPLEFT", feedBox, "TOPLEFT", 10, -8)
    local subTabs = {}
    local BAR_ITEMS = {
        { "news", "Noticias", "Logros, jefes derrotados, botín, altas y bajas de la hermandad, agrupados por semana." },
        -- Retail no tiene el Diario de la hermandad (Journal.lua de Forever): el botón muestra solo los récords
        addonTable.Journal and { "journal", "Diario de la hermandad", "Los recuerdos de la hermandad que no se borran y, en otra columna, los récords." }
            or { "journal", "Récords", "Récords de la hermandad: puntos de logro, puntuación de Míticas+, bandas, objetos, DKP y la mejor llave de la semana." },
        { "rules", "Normas", "Las normas de la hermandad. Las escriben los oficiales en Configuración > Normas de la hermandad." },
        { "refresh", "Actualizar", "Vuelve a pedir las noticias y redibuja el Resumen." },
    }
    local BAR_GAP = 6
    local barButtonWidth = math.floor((546 - BAR_GAP * (#BAR_ITEMS + 1)) / #BAR_ITEMS)
    for i, info in ipairs(BAR_ITEMS) do
        local btn = CreateFrame("Button", nil, tabBar, "UIPanelButtonTemplate")
        btn:SetSize(barButtonWidth, 22)
        btn:SetPoint("LEFT", tabBar, "LEFT", BAR_GAP + (i - 1) * (barButtonWidth + BAR_GAP), 0)
        btn:SetText(L[info[2]])
        btn.mode = info[1]
        btn:SetScript("OnClick", function()
            if info[1] == "refresh" then
                N.Request()
            else
                summaryMode = info[1]
            end
            if Refresh then Refresh() end
        end)
        if info[1] ~= "refresh" then table.insert(subTabs, btn) end
        uiModule.AddTips({ { btn, info[2], info[3] } })
    end

    -- Normas de la hermandad: texto con los iconos de banda ya dibujados
    local function RulesText()
        local rules = addonTable.GuildConfig and addonTable.GuildConfig.GetRules() or ""
        if rules == "" then
            return L["|cFF808080La hermandad todavía no tiene normas escritas. Los oficiales las escriben en Configuración.|r"]
        end
        return RenderRaidIcons(rules)
    end
    if addonTable.GuildConfig then
        addonTable.GuildConfig.AddListener(function()
            if summaryMode == "rules" and view:IsShown() and Refresh then Refresh() end
        end)
    end

    local filterButtons = {}
    for _, filter in ipairs(N.FILTERS) do
        local btn = CreateFrame("Button", nil, feedBox, "UIPanelButtonTemplate")
        btn:SetText(L[filter.label])
        -- El ancho sale del texto (en otros idiomas es más largo), con un mínimo
        local textWidth = btn:GetFontString() and btn:GetFontString():GetStringWidth() or 0
        btn:SetSize(math.max(56, math.ceil(textWidth + 22)), 20)
        btn:SetScript("OnClick", function()
            currentFilter = filter.key
            Refresh()
        end)
        filterButtons[filter.key] = btn
        uiModule.AddTips({ { btn, filter.label, "Muestra solo estas noticias." } })
    end

    -- Solo se ven los filtros que tienen noticias (Altas y Bajas siempre); si el elegido
    -- se queda vacío se pasa al primero que tenga
    local function LayoutFilters()
        local active = N.GetActiveFilters()
        if not active[currentFilter] then
            for _, filter in ipairs(N.FILTERS) do
                if active[filter.key] then currentFilter = filter.key break end
            end
        end
        local previousBtn = nil
        for _, filter in ipairs(N.FILTERS) do
            local btn = filterButtons[filter.key]
            btn:ClearAllPoints()
            btn:SetShown(active[filter.key] == true)
            if active[filter.key] then
                if previousBtn then
                    btn:SetPoint("LEFT", previousBtn, "RIGHT", 4, 0)
                else
                    btn:SetPoint("TOPLEFT", feedBox, "TOPLEFT", 14, -46)
                end
                previousBtn = btn
            end
        end
    end

    local feedScroll = CreateFrame("ScrollFrame", "GC_SummaryFeedScroll", feedBox, "UIPanelScrollFrameTemplate")
    feedScroll:SetPoint("TOPLEFT", feedBox, "TOPLEFT", 10, -74)
    feedScroll:SetPoint("BOTTOMRIGHT", feedBox, "BOTTOMRIGHT", -30, 10)
    local feedChild = CreateFrame("Frame")
    feedChild:SetSize(524, 1)
    feedScroll:SetScrollChild(feedChild)

    local emptyText = feedBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", feedBox, "CENTER", 0, -20)
    emptyText:SetWidth(460)

    -- Diario de la hermandad (columna ancha) y récords (columna estrecha), y normas: textos con
    -- desplazamiento en el sitio de las noticias
    local function TextColumn(x, y, width, height, titleText)
        local box = CreateBackdropBox(feedBox, width, height, "TOPLEFT", feedBox, "TOPLEFT", x, y)
        box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -8)
        box.title:SetText(titleText or "")
        box.scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
        box.scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 8, titleText and -26 or -8)
        box.scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 6)
        box.child = CreateFrame("Frame", nil, box.scroll)
        box.child:SetSize(width - 40, 1)
        box.scroll:SetScrollChild(box.child)
        box.text = box.child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        box.text:SetPoint("TOPLEFT", box.child, "TOPLEFT", 2, -2)
        box.text:SetWidth(width - 44)
        box.text:SetJustifyH("LEFT")
        box.text:SetSpacing(3)
        function box.SetBody(text)
            box.text:SetText(text)
            box.child:SetHeight(math.max(1, box.text:GetStringHeight() + 6))
        end
        box:Hide()
        return box
    end
    local feedHeight = 500 - SUMMARY_TOP_HEIGHT - 6
    local journalCol = TextColumn(10, -46, 320, feedHeight - 56, L["Diario de la hermandad"])
    local recordsCol = addonTable.Journal and TextColumn(336, -46, 220, feedHeight - 56, L["Récords"])
        or TextColumn(10, -46, 546, feedHeight - 56, L["Récords de la hermandad"])
    local rulesCol = TextColumn(10, -46, 546, feedHeight - 56, L["Normas de la hermandad"])
    if addonTable.Journal then
        addonTable.Journal.AddListener(function() if summaryMode == "journal" and Refresh then Refresh() end end)
    end

    -- Vista previa de una noticia en el panel derecho (logro u objeto)
    -- Vista previa de botín: datos del objeto y su origen (banda o mazmorra y jefe, si figura
    -- en el diario de encuentros). El origen llega de forma asíncrona.
    local previewedLootItem = nil
    local function LootPreviewText(item, sourceText)
        local d = N.GetItemDetails(item.link)
        local lines = { L["|cFFFFD100Botín|r"], "", item.link, "" }
        if d.itemLevel then table.insert(lines, L["Nivel de objeto: |cFFFFFFFF"] .. d.itemLevel .. "|r") end
        if d.type or d.slot then
            table.insert(lines, L["Tipo: |cFFFFFFFF"] .. table.concat({ d.slot or "", d.type or "" }, d.slot and d.type and L[" · "] or "") .. "|r")
        end
        local verb = item.lootType == "crafted" and L["Fabricado por"] or (item.lootType == "purchased" and L["Comprado por"] or L["Obtenido por"])
        table.insert(lines, verb .. ": |cFFFFFFFF" .. (item.who or "-") .. "|r")
        table.insert(lines, L["Fecha: "] .. (item.dateText or "-"))
        table.insert(lines, "")
        table.insert(lines, L["|cFFFFD100Origen|r"])
        table.insert(lines, sourceText)
        table.insert(lines, "")
        table.insert(lines, L["|cFF808080Pasa el ratón por la noticia para ver el objeto. Shift+clic para compartirlo en la hermandad.|r"])
        return table.concat(lines, "\n")
    end

    local function ShowLootPreview(item)
        previewedLootItem = item
        if item.lootType == "crafted" then
            SetPreviewText(LootPreviewText(item, L["Fabricado con una profesión."]))
            return
        elseif item.lootType == "purchased" then
            SetPreviewText(LootPreviewText(item, L["Comprado a un vendedor. El juego no indica a qué PNJ."]))
            return
        end
        SetPreviewText(LootPreviewText(item, L["|cFF808080Buscando en el diario de encuentros...|r"]))
        N.LookupItemSource(item.link, function(source)
            if previewedLootItem ~= item or activeTab ~= "Resumen" then return end
            local text
            if source then
                text = "|cFFFFFFFF" .. (source.instance or L["Instancia desconocida"]) .. "|r"
                    .. (source.encounter and (L["\nJefe: |cFFFFFFFF"] .. source.encounter .. "|r") or "")
            elseif source == false then
                text = L["No figura en el diario de encuentros: puede ser botín de mundo, de una misión, de un evento o de un vendedor."]
            else
                text = L["|cFF808080No se pudo consultar el diario de encuentros ahora mismo.|r"]
            end
            SetPreviewText(LootPreviewText(item, text))
        end)
    end

    local function ShowNewsPreview(item)
        if item.kind == "achievement" or item.kind == "guildAchievement" then
            -- Quién y cuándo, y debajo el detalle completo del logro (descripción, puntos,
            -- recompensa y criterios)
            local header = "|cFF00FFFF" .. (item.kind == "guildAchievement" and L["Logro de la hermandad"]
                or (L["Logro de "] .. (item.who or "?"))) .. "|r  |cFF808080" .. (item.dateText or "") .. "|r\n\n"
            local details = item.achievementId and addonTable.Achievements and addonTable.Achievements.GetDetails(item.achievementId)
            if details then
                SetPreviewText(header .. BuildAchievementPreviewText(item.achievementId))
            else
                SetPreviewText(header .. "|cFFFFD100" .. (item.name or "") .. L["|r\n\n|cFF808080El juego no da el detalle de este logro.|r"])
            end
        elseif item.link then
            ShowLootPreview(item)
        else
            SetPreviewText("|cFFFFD100" .. (item.title or "") .. "|r\n\n" .. (item.detail or "") .. L["\n\nFecha: "] .. (item.dateText or "-"))
        end
    end

    -- Shift+clic: comparte el objeto o el logro en el chat de hermandad
    local function ShareNewsItem(item)
        if not IsInGuild() then return end
        local msg
        if item.link then
            msg = L["Botín de "] .. (item.who or "?") .. ": " .. item.link
        elseif item.achievementId and GetAchievementLink then
            local link = GetAchievementLink(item.achievementId)
            if link then
                msg = (item.kind == "guildAchievement" and L["La hermandad ha conseguido "] or ((item.who or "?") .. L[" ha conseguido "])) .. link
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
        card.subtitle = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        -- Banner de bienvenida: icono de la hermandad, recuento a la derecha y línea inferior
        card.logo = CreateGuildIconHolder(card, 42)
        card.logo:SetPoint("LEFT", card, "LEFT", 10, 0)
        card.count = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        card.count:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -9)
        card.countLabel = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        card.countLabel:SetPoint("TOPRIGHT", card.count, "BOTTOMRIGHT", 0, -3)
        card.underline = card:CreateTexture(nil, "ARTWORK")
        card.underline:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
        card.underline:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
        card.underline:SetHeight(2)

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
        -- Clic: vista previa · Shift+clic: compartir · Clic derecho: abrir el logro en Blizzard
        card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        card:SetScript("OnClick", function(self, button)
            local item = self.item
            if not item then return end
            if button == "RightButton" then
                if item.achievementId and addonTable.Achievements then
                    ShowNewsPreview(item)
                    addonTable.Achievements.OpenAchievement(item.achievementId)
                end
            elseif IsShiftKeyDown() then
                ShareNewsItem(item)
            else
                ShowNewsPreview(item)
            end
        end)
        cards[index] = card
        return card
    end

    -- Una tarjeta puede ser noticia o cabecera de semana
    -- subtitleText: cabecera grande (la de las últimas altas) con un subtítulo debajo
    local BIG_HEADER_HEIGHT = 58
    -- Fondo en degradado de izquierda a derecha (si el cliente no lo admite, color liso)
    local function SetGradientBg(tex, r, g, b, alphaLeft, alphaRight)
        tex:SetColorTexture(1, 1, 1, 1)
        local ok = CreateColor and pcall(tex.SetGradient, tex, "HORIZONTAL", CreateColor(r, g, b, alphaLeft), CreateColor(r, g, b, alphaRight))
        if not ok and tex.SetGradientAlpha then
            ok = pcall(tex.SetGradientAlpha, tex, "HORIZONTAL", r, g, b, alphaLeft, r, g, b, alphaRight)
        end
        if not ok then tex:SetColorTexture(r, g, b, alphaLeft) end
    end

    -- banner (cabecera grande): { logo = true, count = "+3", countLabel = "...", color = {r, g, b} }
    local function SetupCard(card, item, headerText, subtitleText, banner)
        local isHeader = headerText ~= nil
        local isBig = isHeader and subtitleText ~= nil
        card.item = item
        card:SetHeight(isBig and BIG_HEADER_HEIGHT or (isHeader and 24 or (NEWS_CARD_HEIGHT - 4)))
        card:EnableMouse(not isHeader)
        card.icon:SetShown(not isHeader)
        card.bar:SetShown(not isHeader)
        card.detail:SetShown(not isHeader)
        card.date:SetShown(not isHeader)
        card.subtitle:SetShown(isBig)
        card.logo:SetShown(banner ~= nil and banner.logo == true)
        card.count:SetShown(banner ~= nil and banner.count ~= nil)
        card.countLabel:SetShown(banner ~= nil and banner.count ~= nil)
        card.underline:SetShown(banner ~= nil)
        card.icon:SetTexCoord(0, 1, 0, 1)
        card.title:ClearAllPoints()
        card.subtitle:ClearAllPoints()
        card.title:SetFontObject(isBig and "GameFontNormalHuge" or "GameFontHighlight")
        if isHeader then
            local left = 12
            if banner then
                local c = banner.color or { 1, 0.82, 0 }
                SetGradientBg(card.bg, c[1], c[2], c[3], 0.32, 0.04)
                card.underline:SetColorTexture(c[1], c[2], c[3], 0.8)
                if banner.logo then
                    card.logo:SetGuildIcon(GuildControlDB.settings.guildIcon or addonTable.DEFAULT_LOGO)
                    left = 62
                end
                if banner.count then
                    card.count:SetText(banner.count)
                    card.countLabel:SetText(banner.countLabel or "")
                end
            else
                card.bg:SetColorTexture(1, 0.82, 0, isBig and 0.14 or 0.08)
            end
            if isBig then
                card.title:SetPoint("TOPLEFT", card, "TOPLEFT", left, -9)
                card.subtitle:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", left, 9)
                card.subtitle:SetText(subtitleText)
            else
                card.title:SetPoint("LEFT", card, "LEFT", 10, 0)
            end
            card.title:SetPoint("RIGHT", card, "RIGHT", banner and banner.count and -110 or -10, 0)
            card.title:SetText("|cFFFFD100" .. headerText .. "|r")
        else
            card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -1)
            card.title:SetPoint("RIGHT", card, "RIGHT", -60, 0)
            local color = NEWS_KIND_COLORS[item.kind] or NEWS_KIND_COLORS.other
            card.icon:SetTexture(item.icon)
            card.title:SetText(item.title or "")
            -- Altas: icono de clase, nombre y fila con el color de su clase
            local classColor = item.kind == "join" and item.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[item.class]
            if classColor then
                color = { classColor.r, classColor.g, classColor.b }
                SetGradientBg(card.bg, color[1], color[2], color[3], 0.22, 0.03)
                local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[item.class]
                if coords then
                    card.icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
                    card.icon:SetTexCoord(unpack(coords))
                end
                card.title:SetText("|cFF" .. addonTable.GetClassColorHex(item.class) .. (item.shortName or "") .. "|r"
                    .. L[" se ha unido a la hermandad"])
            else
                card.bg:SetColorTexture(1, 1, 1, 0.04)
            end
            card.bar:SetColorTexture(color[1], color[2], color[3], 0.9)
            card.detail:SetText(item.detail or "")
            card.date:SetText(item.dateText or "")
        end
        card:Show()
    end


    -- ---------------------------------------------------------------------
    -- Columna derecha: mensaje del día, próximas bandas y oficiales
    -- ---------------------------------------------------------------------
    -- Área con desplazamiento bajo el título de una caja; la barra solo sale si el contenido no cabe
    local function AddBoxScroll(box)
        box.scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
        box.child = CreateFrame("Frame", nil, box.scroll)
        box.child:SetSize(1, 1)
        box.scroll:SetScrollChild(box.child)
        -- contentHeight: alto de lo que hay dentro; devuelve el ancho útil para el contenido
        function box.FitScroll(contentHeight)
            local top = box.title:GetStringHeight() + 16
            local visible = box:GetHeight() - top - 8
            local needBar = contentHeight > visible + 1
            box.scroll:ClearAllPoints()
            box.scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -top)
            box.scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", needBar and -28 or -10, 8)
            if box.scroll.ScrollBar then box.scroll.ScrollBar:SetShown(needBar) end
            if not needBar then box.scroll:SetVerticalScroll(0) end
            local width = box:GetWidth() - 12 - (needBar and 28 or 10)
            box.child:SetSize(width, math.max(1, contentHeight))
            return width
        end
        return box
    end

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
        AddBoxScroll(box)
        box.text = box.child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        box.text:SetPoint("TOPLEFT", box.child, "TOPLEFT", 0, 0)
        box.text:SetJustifyH("LEFT")
        box.text:SetJustifyV("TOP")
        box.text:SetSpacing(3)
        -- Pone el texto y ajusta el desplazamiento (primero mide con el ancho sin barra)
        function box.SetBoxText(text)
            box.text:SetWidth(box.FitScroll(0))
            box.text:SetText(text)
            box.text:SetWidth(box.FitScroll(box.text:GetStringHeight() + 4))
            box.child:SetHeight(math.max(1, box.text:GetStringHeight() + 4))
        end
        return box
    end

    local motdBox = SideBox(L["Mensaje del día"], 70)
    local raidsBox = SideBox(L["Próximas bandas"], 120, motdBox)
    local officersBox = SideBox(L["Oficiales"], 500 - SUMMARY_TOP_HEIGHT - 6 - 70 - 120 - 12, raidsBox)


    local WEEKDAYS = { L["Dom"], L["Lun"], L["Mar"], L["Mié"], L["Jue"], L["Vie"], L["Sáb"] }
    local function ShortEventDate(event)
        local y, mo, d = string.match(event.date or "", "^(%d+)-(%d+)-(%d+)$")
        if not y then return event.date or "" end
        local t = time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 })
        return WEEKDAYS[tonumber(date("%w", t)) + 1] .. " " .. d .. "/" .. mo .. " " .. (event.time or "")
    end

    -- ---------------------------------------------------------------------
    -- Arriba: lo que te toca hacer, lo que pasa ahora y la semana (y lo pendiente, oficiales)
    -- Cada línea puede llevar a la pestaña o al filtro correspondiente con un clic.
    -- ---------------------------------------------------------------------
    local INFO_LINE_HEIGHT = 16
    local function InfoBox(titleText)
        local box = CreateBackdropBox(view, 214, SUMMARY_TOP_HEIGHT)
        box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
        box.title:SetText(titleText)
        box.lines = {}
        return AddBoxScroll(box)
    end

    -- lines = { {text, onClick}, ... }; las que tienen onClick se resaltan al pasar el ratón
    local function SetBoxLines(box, lines)
        for _, row in ipairs(box.lines) do row:Hide() end
        -- Todas las líneas; si no caben, la caja se desplaza con la rueda o la barra
        local rowWidth = box.FitScroll(#lines * INFO_LINE_HEIGHT)
        for i, line in ipairs(lines) do
            local row = box.lines[i]
            if not row then
                row = CreateFrame("Button", nil, box.child)
                row:SetHeight(INFO_LINE_HEIGHT)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetAllPoints()
                row.text:SetJustifyH("LEFT")
                row.text:SetWordWrap(false)
                row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
                row.highlight:SetAllPoints()
                row.highlight:SetColorTexture(1, 1, 1, 0.08)
                row:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
                box.lines[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", box.child, "TOPLEFT", 0, -(i - 1) * INFO_LINE_HEIGHT)
            row:SetWidth(rowWidth)
            row.text:SetText(line.text)
            row.onClick = line.onClick
            row:EnableMouse(line.onClick ~= nil)
            -- Insignias de color detrás del texto: { {text = "+3", color = {r, g, b}}, ... }
            row.badges = row.badges or {}
            for _, badge in ipairs(row.badges) do badge:Hide() end
            local x = row.text:GetStringWidth() + 6
            for b, info in ipairs(line.badges or {}) do
                local badge = row.badges[b]
                if not badge then
                    badge = CreateFrame("Frame", nil, row)
                    badge:SetHeight(INFO_LINE_HEIGHT - 2)
                    badge.bg = badge:CreateTexture(nil, "BACKGROUND")
                    badge.bg:SetAllPoints()
                    badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    badge.text:SetPoint("CENTER")
                    row.badges[b] = badge
                end
                local c = info.color
                badge.bg:SetColorTexture(c[1], c[2], c[3], 0.22)
                badge.text:SetText(info.text)
                badge.text:SetTextColor(c[1], c[2], c[3])
                badge:SetWidth(math.max(26, badge.text:GetStringWidth() + 12))
                badge:ClearAllPoints()
                badge:SetPoint("LEFT", row, "LEFT", x, 0)
                x = x + badge:GetWidth() + 4
                badge:Show()
            end
            row:Show()
        end
    end

    local forYouBox = InfoBox(L["Para ti"])
    local nowBox = InfoBox(L["Ahora en la hermandad"])
    local weekBox = InfoBox(L["Esta semana"])
    local pendingBox = InfoBox(L["Pendiente (oficiales)"])

    local function LayoutTopBoxes(isOfficer)
        local boxes = isOfficer and { forYouBox, nowBox, weekBox, pendingBox } or { forYouBox, nowBox, weekBox }
        local gap = 6
        local width = math.floor((878 - gap * (#boxes - 1)) / #boxes)
        pendingBox:SetShown(isOfficer)
        for i, box in ipairs(boxes) do
            box:ClearAllPoints()
            box:SetWidth(width)
            box:SetPoint("TOPLEFT", view, "TOPLEFT", 10 + (i - 1) * (width + gap), -10)
        end
    end

    local function GoTo(tabName) return function() SwitchTab(tabName) end end
    local function ShowFilter(key) return function() currentFilter = key; Refresh() end end

    -- Rosters en los que estoy (los míos de oficial y los publicados), sin repetir nombre
    local function MyRosters(me)
        local R = addonTable.Roster
        local list, seen = {}, {}
        local function Add(roster)
            if roster and roster.members and roster.members[me] and not seen[roster.name] then
                seen[roster.name] = true
                table.insert(list, roster)
            end
        end
        for _, roster in ipairs(R.GetAll()) do Add(roster) end
        for _, item in ipairs(R.GetSharedRosters()) do Add(item.roster) end
        return list
    end

    local function ForYouLines(isOfficer)
        local E, M, P = addonTable.RaidEvents, addonTable.MythicPlus, addonTable.Profiles
        local me = P.GetMyFullName()
        local lines = {}
        local function Add(text, onClick) table.insert(lines, { text = text, onClick = onClick }) end

        local nextEvent = E.GetUpcomingForRoster(nil)[1]
        if nextEvent then
            local signup = E.GetMySignup(nextEvent)
            local answer = signup and ("|cFF" .. E.STATUS_COLORS[signup.status] .. L[E.STATUS_LABELS[signup.status]] .. "|r"
                .. (signup.role and (" " .. RoleIcon(signup.role, 12)) or "")) or L["|cFFFF7F00sin responder|r"]
            Add("|cFFFFD100" .. ShortEventDate(nextEvent) .. "|r  " .. nextEvent.title, GoTo("Raid"))
            Add(L["Tu respuesta: "] .. answer, GoTo("Raid"))
        end

        local profile = P.GetMyProfile()
        if not nextEvent then
            -- Sin bandas próximas: resumen del personaje (clase, nivel, rama, rol, rango y saldo)
            local className, classFile = UnitClass("player")
            -- Especialización del juego (ya viene en el idioma del cliente)
            local specIndex = GetSpecialization and GetSpecialization()
            local spec = specIndex and select(2, GetSpecializationInfo(specIndex)) or nil
            Add("|cFF" .. addonTable.GetClassColorHex(classFile) .. (className or "") .. "|r  |cFF808080" .. L["Nivel "] .. (UnitLevel("player") or "?")
                .. (spec and (" · " .. spec) or "") .. "|r", GoTo("Mi perfil"))
            if profile and profile.main then
                Add(L["Tu rol: "] .. RoleIcon(profile.main, 12) .. " |cFF00FF00" .. L[profile.main] .. "|r"
                    .. (profile.secondary and (" / " .. RoleIcon(profile.secondary, 12) .. " " .. L[profile.secondary]) or ""), GoTo("Mi perfil"))
            end
            local m = GuildControlDB.members[me]
            if m and m.rank then Add(L["Rango: "] .. "|cFFFFD100" .. m.rank .. "|r", GoTo("Miembros")) end
            local D, Lo = addonTable.Dkp, addonTable.Loot
            if D and D.IsActive and D.IsActive() then
                Add(L["Tus DKP: "] .. "|cFFFFD100" .. (D.GetBalance(me) or 0) .. "|r", GoTo("Botín"))
            elseif Lo and Lo.GetPoints then
                Add(L["Tus +1: "] .. "|cFFFFD100" .. (Lo.GetPoints(me) or 0) .. "|r", GoTo("Botín"))
            end
        end
        if not (profile and profile.main) then Add(L["|cFFFF7F00No has declarado tu rol|r"], GoTo("Mi perfil")) end
        if not nextEvent then Add(L["|cFF808080Sin bandas próximas|r"], GoTo("Raid")) end

        local key = M.GetKeystone(me)
        if key then
            Add(L["Tu llave: "] .. "|cFFA335EE+" .. key.level .. "|r " .. (M.GetMapName(key.mapID) or ""), GoTo("Míticas+"))
        end
        local runs, best = M.GetMyWeeklyRuns()
        if runs > 0 then
            Add(L["Míticas+ esta semana: "] .. runs .. (best and (" |cFF808080(+" .. best .. ")|r") or ""), GoTo("Míticas+"))
        else
            Add(L["|cFFFF7F00Aún no has hecho Míticas+ esta semana|r"], GoTo("Míticas+"))
        end

        -- Asistencia al final: lo primero que se ve es lo de esta semana (la caja se desplaza si no cabe)
        local threshold = GuildControlDB.settings.lowAttendance or 70
        local shown = 0
        for _, roster in ipairs(MyRosters(me)) do
            local stats = E.GetAttendanceStats(roster.name, me)
            if stats.percent and shown < 2 then
                shown = shown + 1
                local color = stats.percent < threshold and "FF3333" or "00FF00"
                Add(L["Asistencia en "] .. roster.name .. ": |cFF" .. color .. stats.percent .. "%|r", GoTo(isOfficer and "Roster" or "Raid"))
            end
        end
        return lines
    end

    local function NowLines()
        local F, R = addonTable.Favorites, addonTable.Roster
        local lines = {}
        local function Add(text, onClick) table.insert(lines, { text = text, onClick = onClick }) end
        local online, total = 0, 0
        local instances = R.GetInstanceNames()
        local inInstance = {}
        local roles = { tank = 0, healer = 0, dps = 0, none = 0 }
        for name, m in pairs(GuildControlDB.members) do
            total = total + 1
            if m.isOnline then
                online = online + 1
                if m.zone and instances[m.zone] then table.insert(inInstance, { name = name, m = m }) end
                local slot = R.GetDefinedSlot and R.GetDefinedSlot(name)
                local key = (slot and roles[slot]) and slot or "none"
                roles[key] = roles[key] + 1
            end
        end
        Add(L["Conectados: "] .. "|cFF00FF00" .. online .. "|r / " .. total
            .. (roles.none > 0 and ("  |cFF808080" .. string.format(L["(%d sin rol)"], roles.none) .. "|r") or ""), GoTo("Miembros"))
        -- Roles de los conectados: "1 Tanque | 0 Sanadores | 3 DPS"
        local function RolePart(n, one, many) return "|cFFFFFFFF" .. n .. "|r " .. (n == 1 and one or many) end
        Add("|cFFBFBFBF" .. RolePart(roles.tank, L["Tanque"], L["Tanques"]) .. "  |  " .. RolePart(roles.healer, L["Sanador"], L["Sanadores"])
            .. "  |  " .. RolePart(roles.dps, L["DPS"], L["DPS"]) .. "|r", GoTo("Miembros"))

        local favOnline = {}
        for _, name in ipairs(F.GetAll()) do
            local m = GuildControlDB.members[name]
            if m and m.isOnline then
                table.insert(favOnline, "|cFF" .. addonTable.GetClassColorHex(m.class) .. (string.match(name, "^([^-]+)") or name) .. "|r")
            end
        end
        Add(L["Favoritos conectados: "] .. #favOnline, GoTo("Favoritos"))
        if #favOnline > 0 then Add("  " .. table.concat(favOnline, ", "), GoTo("Favoritos")) end

        table.sort(inInstance, function(a, b) return a.name < b.name end)
        Add(L["En mazmorra o banda: "] .. #inInstance, GoTo("Miembros"))
        for i, entry in ipairs(inInstance) do
            if i > 2 then break end
            Add("  |cFF" .. addonTable.GetClassColorHex(entry.m.class) .. (string.match(entry.name, "^([^-]+)") or entry.name)
                .. "|r |cFF808080· " .. entry.m.zone .. "|r")
        end
        return lines
    end

    local function WeekLines()
        local M = addonTable.MythicPlus
        local lines = {}
        local function Add(text, onClick) table.insert(lines, { text = text, onClick = onClick }) end
        local reset = M.GetLastWeeklyReset()
        local resetKey = date("%Y%m%d", reset)
        local function CountSince(filter)
            local n = 0
            for _, item in ipairs(N.GetFeed(filter)) do
                if string.sub(item.sortKey or "", 1, 8) >= resetKey then n = n + 1 end
            end
            return n
        end
        local resetText = date("%Y-%m-%d %H:%M:%S", reset)
        local joins, leaves = 0, 0
        for _, log in ipairs(GuildControlDB.history or {}) do
            if (log.date or "") >= resetText then
                if log.action == "ALTA" then joins = joins + 1 elseif log.action == "BAJA" then leaves = leaves + 1 end
            end
        end
        Add("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:14:14|t " .. L["Jefes derrotados: "] .. "|cFFFFD100" .. CountSince("boss") .. "|r", ShowFilter("boss"))
        Add(L["Logros de la hermandad: "] .. "|cFFFFD100" .. CountSince("guildAchievement") .. "|r", ShowFilter("guildAchievement"))
        Add(L["Logros de personajes: "] .. "|cFFFFD100" .. CountSince("achievement") .. "|r", ShowFilter("achievement"))
        table.insert(lines, { text = L["Altas / Bajas"], onClick = ShowFilter("join"), badges = {
            { text = "+" .. joins, color = { 0.3, 0.9, 0.35 } },
            { text = "-" .. leaves, color = { 1, 0.5, 0.5 } },
        } })
        local bestName, bestLevel, bestMap = M.GetGuildWeeklyBest()
        if bestName then
            Add(L["Mejor llave: "] .. "|cFFA335EE+" .. bestLevel .. "|r " .. (M.GetMapName(bestMap) or ""), GoTo("Míticas+"))
            Add("  |cFF808080" .. (string.match(bestName, "^([^-]+)") or bestName) .. "|r", GoTo("Míticas+"))
        else
            Add(L["|cFF808080Mejor llave: sin datos todavía|r"], GoTo("Míticas+"))
        end
        return lines
    end

    local function PendingLines()
        local E, R = addonTable.RaidEvents, addonTable.Roster
        local lines = {}
        local function Add(text, onClick) table.insert(lines, { text = text, onClick = onClick }) end
        local summary = uiModule.GetWarningSummary and uiModule.GetWarningSummary() or {}
        for i, item in ipairs(summary) do
            if i > 4 then break end
            local key = item.key
            Add(L[item.label] .. ": |cFFFF7F7F" .. item.count .. "|r", function()
                if uiModule.OpenWarningCategory then uiModule.OpenWarningCategory(key) end
            end)
        end
        if #summary == 0 then Add(L["|cFF00FF00Nada pendiente en Warning|r"], GoTo("Warning")) end

        -- Bandas de los próximos 7 días a las que les faltan roles
        local limit = date("%Y-%m-%d", time() + 7 * 86400)
        for _, event in ipairs(E.GetUpcomingForRoster(nil)) do
            if event.date <= limit then
                local roster
                for _, r in ipairs(R.GetAll()) do if r.name == event.rosterName then roster = r end end
                local need = R.GetTargets(roster or { size = event.size })
                local counts = E.CountSignups(event)
                local parts = {}
                for _, role in ipairs({ "tank", "healer", "dps" }) do
                    local missing = (need[role] or 0) - (counts[role] or 0)
                    if missing > 0 then table.insert(parts, missing .. " " .. RoleIcon(role, 12)) end
                end
                local status = #parts > 0 and (L["faltan "] .. table.concat(parts, "  ")) or L["|cFF00FF00completa|r"]
                Add("|cFFFFD100" .. ShortEventDate(event) .. "|r  " .. status, GoTo("Raid"))
            end
        end
        return lines
    end

    local function RefreshTop()
        local isOfficer = not addonTable.Profiles or addonTable.Profiles.IsOfficer()
        LayoutTopBoxes(isOfficer)
        SetBoxLines(forYouBox, ForYouLines(isOfficer))
        SetBoxLines(nowBox, NowLines())
        SetBoxLines(weekBox, WeekLines())
        if isOfficer then SetBoxLines(pendingBox, PendingLines()) end
    end

    local function RefreshSide()
        local motd = N.GetMOTD()
        motdBox.SetBoxText(motd ~= "" and motd or L["|cFF808080La hermandad no tiene mensaje del día.|r"])

        local raidLines = {}
        for _, entry in ipairs(N.GetUpcomingRaids(4)) do
            local roster = entry.event.rosterName and (L[" |cFF808080· "] .. entry.event.rosterName .. "|r") or ""
            table.insert(raidLines, "|cFFFFD100" .. ShortEventDate(entry.event) .. "|r  " .. entry.event.title .. roster)
        end
        raidsBox.SetBoxText(#raidLines > 0 and table.concat(raidLines, "\n")
            or L["|cFF808080No hay bandas programadas. Los oficiales las crean en Raid.|r"])

        -- Todos los oficiales de la hermandad con su rango (conectados con punto verde)
        local officerLines = {}
        local officers = N.GetOfficers()
        for _, o in ipairs(officers) do
            local short = string.match(o.name, "^([^-]+)") or o.name
            local dot = o.online and "|TInterface\\COMMON\\Indicator-Green:12:12|t " or "|TInterface\\COMMON\\Indicator-Gray:12:12|t "
            table.insert(officerLines, dot .. "|cFF" .. addonTable.GetClassColorHex(o.class) .. short .. "|r  |cFFBFBFBF" .. o.rank .. "|r")
        end
        officersBox.title:SetText(L["Oficiales ("] .. #officers .. ")")
        officersBox.SetBoxText(#officerLines > 0 and table.concat(officerLines, "\n")
            or L["|cFF808080No se han encontrado oficiales. El rango de oficial se ajusta en Mi perfil.|r"])
    end

    -- Noticias agrupadas por semana (cabecera "Esta semana", "Semana pasada", "Semana del...")
    local function RefreshFeed()
        LayoutFilters()
        for key, btn in pairs(filterButtons) do btn:SetEnabled(key ~= currentFilter) end
        for _, card in ipairs(cards) do card:Hide() end

        local index, y, lastWeek = 0, 0, nil
        local feed
        if currentFilter == "join" then
            -- Altas: las 5 últimas, bajo una cabecera grande en vez de agrupar por semanas
            feed = N.GetLatestJoins(5)
            if #feed > 0 then
                index = 1
                local header = AcquireCard(index)
                header:SetPoint("TOPLEFT", feedChild, "TOPLEFT", 0, 0)
                SetupCard(header, nil, L["¡Bienvenidos a la hermandad!"], L["Las 5 últimas incorporaciones"], {
                    logo = true, count = "+" .. N.CountJoinsSince(30), countLabel = L["en 30 días"], color = { 0.25, 0.85, 0.35 },
                })
                y = BIG_HEADER_HEIGHT + 6
                lastWeek = false
            end
        elseif currentFilter == "leave" then
            -- Bajas: cabecera grande y la lista sin agrupar por semanas
            feed = N.GetFeed("leave")
            if #feed > 0 then
                index = 1
                local header = AcquireCard(index)
                header:SetPoint("TOPLEFT", feedChild, "TOPLEFT", 0, 0)
                SetupCard(header, nil, L["¡Abandonan el barco!"], L["Bajas de los últimos 30 días"], { color = { 0.6, 0.6, 0.6 } })
                y = BIG_HEADER_HEIGHT + 6
                lastWeek = false
            end
        else
            feed = N.GetFeed(currentFilter)
        end
        for _, item in ipairs(feed) do
            local weekKey, weekLabel = N.GetWeek(item.sortKey)
            if lastWeek ~= false and weekKey ~= lastWeek then
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
        emptyText:SetText(IsInGuild() and L["No hay noticias para este filtro todavía. Pulsa Actualizar para pedirlas al servidor."]
            or L["No estás en una hermandad."])
    end

    Refresh = function()
        if not view:IsShown() then return end
        for _, btn in ipairs(subTabs) do btn:SetEnabled(btn.mode ~= summaryMode) end
        local isNews = summaryMode == "news"
        feedScroll:SetShown(isNews)
        journalCol:SetShown(summaryMode == "journal" and addonTable.Journal ~= nil)
        recordsCol:SetShown(summaryMode == "journal")
        rulesCol:SetShown(summaryMode == "rules")
        if isNews then
            RefreshFeed()
        else
            for _, btn in pairs(filterButtons) do btn:Hide() end
            emptyText:Hide()
            if summaryMode == "journal" and uiModule.RecordsJournalText then
                if addonTable.Journal then journalCol.SetBody(uiModule.RecordsJournalText("journal")) end
                recordsCol.SetBody(uiModule.RecordsJournalText("records"))
            elseif summaryMode == "rules" then
                rulesCol.SetBody(RulesText())
            end
        end
        RefreshSide()
        RefreshTop()
    end

    N.AddListener(function() Refresh() end)
    if addonTable.RaidEvents then addonTable.RaidEvents.AddListener(function() Refresh() end) end
    if addonTable.MythicPlus then addonTable.MythicPlus.AddListener(function() Refresh() end) end
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
    title:SetText(L["Lista negra"])

    local subtitle = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("LEFT", title, "RIGHT", 14, 0)
    subtitle:SetText(L["Personajes no deseados: avisa si entran en la hermandad o en tu grupo, los marca en su tooltip y bloquea invitarlos."])

    -- ---------------------------------------------------------------------
    -- Formulario para añadir
    -- ---------------------------------------------------------------------
    local form = CreateBackdropBox(view, 880, 64, "TOPLEFT", view, "TOPLEFT", 10, -36)

    local nameLabel = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameLabel:SetPoint("TOPLEFT", form, "TOPLEFT", 14, -10)
    nameLabel:SetText(L["Personaje (Nombre o Nombre-Reino)"])
    local nameInput = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    nameInput:SetSize(180, 20)
    nameInput:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -4)
    nameInput:SetAutoFocus(false)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local btnTarget = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    btnTarget:SetSize(90, 22)
    btnTarget:SetPoint("LEFT", nameInput, "RIGHT", 8, 0)
    btnTarget:SetText(L["Objetivo"])
    btnTarget:SetScript("OnClick", function()
        if UnitIsPlayer("target") then
            local name, realm = UnitName("target")
            nameInput:SetText((realm and realm ~= "") and (name .. "-" .. realm) or name)
        else
            PrintGC(L["No tienes a ningún jugador como objetivo."])
        end
    end)

    local reasonLabel = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reasonLabel:SetPoint("TOPLEFT", form, "TOPLEFT", 312, -10)
    reasonLabel:SetText(L["Motivo"])
    local dropReason = CreateFrame("DropdownButton", "GC_BlacklistReason", form, "WowStyle1DropdownTemplate")
    dropReason:SetPoint("TOPLEFT", reasonLabel, "BOTTOMLEFT", 0, -2)
    dropReason:SetWidth(140)
    dropReason:SetupMenu(function(_, root)
        for _, reason in ipairs(B.REASONS) do
            local key = reason.key
            root:CreateRadio(L[reason.label], function() return selectedReason == key end,
                function() selectedReason = key; dropReason:SetText(L[reason.label]) end)
        end
    end)
    dropReason:SetText(B.GetReasonLabel(selectedReason))

    local noteLabel = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    noteLabel:SetPoint("TOPLEFT", form, "TOPLEFT", 470, -10)
    noteLabel:SetText(L["Nota (qué pasó, cuándo...)"])
    local noteInput = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    noteInput:SetSize(280, 20)
    noteInput:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 6, -4)
    noteInput:SetAutoFocus(false)
    noteInput:SetMaxLetters(120)
    noteInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local btnAdd = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    btnAdd:SetSize(90, 22)
    btnAdd:SetPoint("LEFT", noteInput, "RIGHT", 10, 0)
    btnAdd:SetText(L["Añadir"])

    local function AddEntry()
        local entry, err = B.Add(nameInput:GetText(), selectedReason, noteInput:GetText())
        if not entry then
            PrintGC("|cFFFF3333" .. err .. "|r")
            return
        end
        PrintGC("|cFFFFD100" .. entry.name .. L["|r añadido a la lista negra ("] .. B.GetReasonLabel(entry.reason) .. ").")
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
        { title = L["Personaje"],   x = 8,   w = 180 },
        { title = L["Motivo"],      x = 192, w = 110 },
        { title = L["Nota"],        x = 306, w = 340 },
        { title = L["Añadido por"], x = 650, w = 110 },
        { title = L["Fecha"],       x = 764, w = 80 },
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
    emptyText:SetText(L["La lista negra está vacía."])

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
            GameTooltip:AddDoubleLine(L["Motivo"], B.GetReasonLabel(entry.reason), 0.7, 0.7, 0.7, 1, 1, 1)
            if entry.note and entry.note ~= "" then GameTooltip:AddLine(entry.note, 1, 1, 1, true) end
            GameTooltip:AddDoubleLine(L["Añadido por"], entry.addedBy or "-", 0.7, 0.7, 0.7, 1, 1, 1)
            if entry.sharedBy then GameTooltip:AddDoubleLine(L["Compartido por"], entry.sharedBy, 0.7, 0.7, 0.7, 1, 1, 1) end
            if GuildControlDB.members[entry.name] then GameTooltip:AddLine(L["¡Está en la hermandad!"], 1, 0.2, 0.2) end
            GameTooltip:AddLine(L["Clic derecho: opciones"], 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            local entry = self.entry
            if not entry then return end
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(entry.name)
                root:CreateButton(L["Editar (cargar en el formulario)"], function()
                    nameInput:SetText(entry.name)
                    noteInput:SetText(entry.note or "")
                    selectedReason = entry.reason
                    dropReason:SetText(B.GetReasonLabel(entry.reason))
                end)
                root:CreateButton(L["|cFFFF3333Quitar de la lista negra|r"], function() B.Remove(entry.name) end)
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
    searchPlaceholder:SetText(L["Buscar en la lista..."])
    searchBox:SetScript("OnTextChanged", function(self)
        searchQuery = self:GetText() or ""
        searchPlaceholder:SetShown(searchQuery == "")
        Refresh()
    end)

    local btnShare = CreateFrame("Button", nil, bottom, "UIPanelButtonTemplate")
    btnShare:SetSize(170, 22)
    btnShare:SetPoint("LEFT", searchBox, "RIGHT", 12, 0)
    btnShare:SetText(L["Compartir con oficiales"])
    btnShare:SetScript("OnClick", function()
        local count = B.Share()
        PrintGC(count > 0 and (L["Enviando |cFFFFD100"] .. count .. L["|r entradas a los oficiales conectados con GuildControl."])
            or L["No hay nada que compartir (o ya se está enviando)."])
    end)
    btnShare:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Compartir con oficiales"], 1, 1, 1)
        GameTooltip:AddLine(L["Los oficiales que la reciben añaden las entradas que no tenían. Nunca se borra nada de otro cliente."], 0.8, 0.8, 0.8, true)
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
            row.cells[1]:SetText((inGuild and "|cFFFF3333" or "|cFFFFFFFF") .. entry.name .. "|r" .. (inGuild and L[" |cFFFF3333(en la hermandad)|r"] or ""))
            row.cells[2]:SetText("|cFFFF7F7F" .. B.GetReasonLabel(entry.reason) .. "|r")
            row.cells[3]:SetText(entry.note or "")
            row.cells[4]:SetText(entry.addedBy or "-")
            row.cells[5]:SetText(y and (d .. "/" .. mo .. "/" .. y) or (entry.date or ""))
            row:Show()
        end
        child:SetHeight(math.max(1, #list * BLACKLIST_ROW_HEIGHT))
        emptyText:SetShown(#list == 0)
        local inGuild = B.CountInGuild()
        countText:SetText(#B.GetAll() .. L[" personajes en la lista"]
            .. (inGuild > 0 and (L["   ·   |cFFFF3333"] .. inGuild .. L[" en la hermandad|r"]) or ""))
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
        return years .. (years == 1 and L[" año"] or L[" años"])
    elseif days >= 60 then
        return math.floor(days / 30) .. L[" meses"]
    end
    return days .. L[" días"]
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
                    table.insert(list, { name = name, data = m, detail = L["Sin conectarse: "] .. FormatOfflineDays(m.offlineDays), sort = m.offlineDays or 0 })
                end
            end
            return list
        end,
    },
    {
        key = "norole", label = "Sin rol declarado",
        help = "Miembros activos (últimos %d días) que no han declarado su rol en Mi perfil. Puedes enviarles un recordatorio.", helpArg = ACTIVE_DAYS,
        collect = function()
            local list = {}
            for name, m in pairs(GuildControlDB.members or {}) do
                if not (m.declared and m.declared.main) and (m.isOnline or (m.offlineDays or 0) <= ACTIVE_DAYS) then
                    local detail = HasDefinedRole(m) and (L["Rol puesto por un oficial: "] .. L[m.role]) or L["Sin rol"]
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
                        table.insert(list, { name = name, data = m, detail = L["Dice ser alter de "] .. (mainName or L["(sin indicar)"]) .. L[", que no está en la hermandad"], sort = 0 })
                    end
                end
            end
            return list
        end,
    },
    {
        key = "lowattendance", label = "Baja asistencia",
        help = "Titulares de un roster con asistencia por debajo del umbral (con al menos 2 bandas con lista pasada en Raid).",
        collect = function(s)
            local list = {}
            local E = addonTable.RaidEvents
            for name, rosters in pairs(RosterStarters()) do
                local m = GuildControlDB.members[name]
                for _, roster in ipairs(rosters) do
                    local stats = E.GetAttendanceStats(roster.name, name)
                    if m and stats.percent and stats.counted >= 2 and stats.percent < s.lowAttendance then
                        table.insert(list, { name = name, data = m, sort = 100 - stats.percent,
                            detail = roster.name .. ": " .. stats.percent .. "% (" .. (stats.present + stats.late) .. L[" de "] .. stats.counted .. L[" bandas)"] })
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
                        detail = table.concat(names, ", ") .. L[" · sin conectarse: "] .. FormatOfflineDays(m.offlineDays) })
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
                        detail = L["Nivel "] .. (m.level or "?") .. L[" con rango "] .. (m.rank or "?") .. L[" (por encima del rango de raider)"] })
                elseif lowestRank and m.rankIndex == lowestRank and joins[name] then
                    local days = math.floor((time() - joins[name]) / 86400)
                    if days >= s.reviewRecruitDays and (m.isOnline or (m.offlineDays or 0) <= ACTIVE_DAYS) then
                        table.insert(list, { name = name, data = m, sort = days,
                            detail = days .. L[" días en la hermandad con rango "] .. (m.rank or "?") .. L[": revisar ascenso"] })
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
                    table.insert(list, { name = name, data = m, detail = L["Nota pública vacía"], sort = 1 })
                elseif required ~= "" and not string.find(string.lower(note), required, 1, true) then
                    table.insert(list, { name = name, data = m, detail = L["Nota sin \""] .. s.noteRequired .. "\": " .. note, sort = 0 })
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
    {
        key = "noaddon", label = "Sin GuildControl",
        help = "Miembros de los que no consta que usen GuildControl. Se detecta con cualquier mensaje del addon (roles, llaves, bandas...) y con Comprobar ahora, que pregunta a los conectados.",
        collect = function(s)
            local list = {}
            for name, m in pairs(GuildControlDB.members or {}) do
                if not addonTable.GetAddonUser(name) and (not s.addonOnlineOnly or m.isOnline) then
                    table.insert(list, { name = name, data = m, sort = m.isOnline and 1 or 0,
                        detail = m.isOnline and L["|cFF00FF00Conectado|r"] or (addonTable.FormatLastOnline(m.lastOnline) or "") })
                end
            end
            return list
        end,
    },
    {
        key = "withaddon", label = "Con GuildControl", info = true,
        help = "Miembros que usan GuildControl, con su versión y la última vez que se detectó.",
        collect = function(s)
            local list = {}
            for name, m in pairs(GuildControlDB.members or {}) do
                local user = addonTable.GetAddonUser(name)
                if user and (not s.addonOnlineOnly or m.isOnline) then
                    local version = user.version or "?"
                    local mine = addonTable.VERSION
                    local other = user.version and mine ~= "dev" and version ~= "dev" and version ~= mine
                    table.insert(list, { name = name, data = m, sort = m.isOnline and 1 or 0,
                        detail = (other and "|cFFFF7F00" or "|cFFFFFFFF") .. L["Versión "] .. version .. "|r  |cFF808080"
                            .. L["visto el "] .. date("%d/%m %H:%M", user.at or 0) .. "|r" })
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
-- Recuento de cada categoría con avisos (para el bloque de oficiales del Resumen):
-- { {key, label, count}, ... } en el orden de WARNING_CATEGORIES
function uiModule.GetWarningSummary()
    local result = {}
    local settings = WarningSettings()
    for _, category in ipairs(WARNING_CATEGORIES) do
        local count = #category.collect(settings)
        if count > 0 and not category.info then table.insert(result, { key = category.key, label = category.label, count = count }) end
    end
    return result
end

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
    catTitle:SetText(L["Warnings"])

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
        btn.text:SetText(L[category.label])
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
        label:SetText(L["Sin conectarse desde hace al menos:"])
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
        _G[chkAlts:GetName() .. "Text"]:SetText(L["Incluir alters"])
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

    NumberControl("lowattendance", L["Avisar por debajo de:"], "lowAttendance", 1, 100, L["% de asistencia"])
    NumberControl("inactivestarters", L["Titulares sin conectarse desde hace al menos:"], "starterInactiveDays", 1, 365, L["días"])

    -- Rangos: rango de raider (dropdown) y días como recluta
    do
        local holder = CreateFrame("Frame", nil, settingsRow)
        holder:SetAllPoints()
        local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", holder, "LEFT", 0, 0)
        label:SetText(L["Rango de raider o superior:"])
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
        daysLabel:SetText(L["Recluta desde hace:"])
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
        suffix:SetText(L["días"])
        holder.Load = function()
            local s = WarningSettings()
            drop:SetText(L["Rango "] .. s.reviewRaiderRank)
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
        label:SetText(L["La nota debe contener (opcional):"])
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
        hint:SetText(L["Ej.: \"Main\" o \"ilvl\". Enter para aplicar."])
        holder.Load = function() input:SetText(WarningSettings().noteRequired or "") end
        controlsByKey.notes = { holder }
    end

    -- Uso de GuildControl: solo conectados y comprobar ahora
    for _, key in ipairs({ "noaddon", "withaddon" }) do
        local holder = CreateFrame("Frame", nil, settingsRow)
        holder:SetAllPoints()
        local chk = CreateFrame("CheckButton", nil, holder, "UICheckButtonTemplate")
        chk:SetSize(24, 24)
        chk:SetPoint("LEFT", holder, "LEFT", -4, 0)
        local chkText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        chkText:SetPoint("LEFT", chk, "RIGHT", 2, 0)
        chkText:SetText(L["Solo conectados"])
        chk:SetScript("OnClick", function(self)
            WarningSettings().addonOnlineOnly = self:GetChecked() and true or false
            Refresh()
        end)
        local btnCheck = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
        btnCheck:SetSize(140, 22)
        btnCheck:SetPoint("LEFT", chkText, "RIGHT", 16, 0)
        btnCheck:SetText(L["Comprobar ahora"])
        btnCheck:SetScript("OnClick", function()
            if addonTable.PingAddonUsers then addonTable.PingAddonUsers() end
            PrintGC(L["Preguntando a los conectados que usan GuildControl..."])
            C_Timer.After(8, function() Refresh() end)
        end)
        local hint = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("LEFT", btnCheck, "RIGHT", 10, 0)
        hint:SetText(L["Las respuestas llegan en unos segundos."])
        holder.Load = function() chk:SetChecked(WarningSettings().addonOnlineOnly == true) end
        controlsByKey[key] = { holder }
    end

    -- Tabla
    local COLS = {
        { title = L["Personaje"], x = 8,   w = 170 },
        { title = L["Nivel"],     x = 182, w = 40 },
        { title = L["Rango"],     x = 226, w = 90 },
        { title = L["Detalle"],   x = 320, w = 320 },
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
    emptyText:SetText(L["Nada que revisar en esta categoría."])

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
            GameTooltip:AddLine(L["Clic derecho: opciones"], 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Clic derecho: susurrar, invitar al grupo y, en inactivos, expulsar (con confirmación)
        row:SetScript("OnClick", function(self)
            local name = self.fullName
            if not name then return end
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(name)
                root:CreateButton(L["Susurrar"], function() WhisperTo(name) end)
                root:CreateButton(L["Invitar al grupo"], function() InviteToGroup(name) end)
                if selectedKey == "inactive" and not (CanGuildRemove and not CanGuildRemove()) then
                    local kick = root:CreateButton(L["|cFFFF3333Expulsar de la hermandad...|r"])
                    kick:CreateButton(L["Sí, expulsar a "] .. name, function()
                        if C_GuildInfo and C_GuildInfo.RemoveFromGuild then
                            C_GuildInfo.RemoveFromGuild(name)
                        elseif GuildUninvite then
                            GuildUninvite(name)
                        end
                        PrintGC(L["Expulsando a |cFFFFD100"] .. name .. L["|r de la hermandad."])
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
    btnExport:SetText(L["Exportar CSV"])
    btnExport:SetScript("OnClick", function()
        local lines = { L["Personaje,Nivel,Rango,Detalle"] }
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
    btnRemind:SetText(L["Recordar a los conectados"])
    btnRemind:SetScript("OnClick", function(self)
        if reminderTicker then return end
        local queue = {}
        local me = string.match(UnitName("player") or "", "^(%S+)")   -- sin apellido (Forever)
        for _, entry in ipairs(currentList) do
            if entry.data.isOnline and ShortOf(entry.name) ~= me then table.insert(queue, entry.name) end
        end
        if #queue == 0 then
            PrintGC(L["No hay nadie conectado sin rol declarado."])
            return
        end
        self:Disable()
        local total = #queue
        reminderTicker = C_Timer.NewTicker(0.5, function()
            local name = table.remove(queue, 1)
            if name then
                SendWhisper(name, L["¡Hola "] .. ShortOf(name) .. L["! Cuando puedas, indica tu rol y especialización en GuildControl > Mi perfil. ¡Gracias!"])
            end
            if #queue == 0 then
                reminderTicker:Cancel()
                reminderTicker = nil
                self:Enable()
                PrintGC(L["Recordatorios enviados: |cFFFFD100"] .. total .. "|r.")
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
            btn.count:SetText(count > 0 and ((category.info and "|cFF7FFF7F" or "|cFFFF7F7F") .. count .. "|r") or "|cFF808080 0|r")
            btn.bg:SetShown(category.key == selectedKey)
            if category.key == selectedKey then selected = category end
        end

        helpText:SetText(selected.helpArg and string.format(L[selected.help], selected.helpArg) or L[selected.help])
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
            -- Nombre con apellido (Forever); la clave interna solo sirve para identificar
            local shown = m.displayName or string.match(entry.name, "^([^-]+)") or entry.name
            row.cells[1]:SetText("|cFF" .. addonTable.GetClassColorHex(m.class) .. shown .. "|r" .. dot)
            row.cells[2]:SetText(tostring(m.level or ""))
            row.cells[3]:SetText(m.rank or "")
            row.cells[4]:SetText(entry.detail or "")
            row:Show()
        end
        child:SetHeight(math.max(1, #currentList * WARNING_ROW_HEIGHT))
        emptyText:SetShown(#currentList == 0)
        countText:SetText("|cFFFFD100" .. #currentList .. L["|r personajes"])
    end

    view:SetScript("OnShow", Refresh)
    uiModule.RefreshWarnings = Refresh
    -- Abre Warning en una categoría concreta (desde el Resumen)
    uiModule.OpenWarningCategory = function(key)
        selectedKey = key
        if uiModule.SwitchTab then uiModule.SwitchTab("Warning") end
        Refresh()
    end
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
-- Miembros por profesión: { [nombre de la profesión] = { {name, data, skill, other}, ... } }.
-- Se agrupan por ID de profesión (así "Herbalism" y "Botánica" son la misma) y salen todas las
-- principales, también las que nadie tiene todavía (lista vacía).
local function CollectProfessions()
    local P = addonTable.Professions
    local function Key(base) return (P and P.ProfessionIdByName and P.ProfessionIdByName(base)) or base end
    local byKey, names = {}, {}
    local function Add(base, entry)
        local key = Key(base)
        names[key] = names[key] or base
        byKey[key] = byKey[key] or {}
        table.insert(byKey[key], entry)
    end
    for fullName, m in pairs(GuildControlDB.members or {}) do
        local p1, s1 = ParseProfession(m.prof1)
        local p2, s2 = ParseProfession(m.prof2)
        if p1 then Add(p1, { name = fullName, data = m, skill = s1, other = m.prof2 }) end
        if p2 and (not p1 or Key(p2) ~= Key(p1)) then Add(p2, { name = fullName, data = m, skill = s2, other = m.prof1 }) end
    end
    for _, prof in ipairs(P and P.PRIMARY or {}) do
        if not names[prof.id] then
            names[prof.id] = (P.DisplayName and P.DisplayName(prof.id)) or prof.en
            byKey[prof.id] = {}
        end
    end
    local byProf = {}
    for key, list in pairs(byKey) do byProf[names[key]] = list end
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
    local SetMode   -- miembros por profesión o artesanos y pedidos (se define al final)

    -- Izquierda: profesiones con su recuento
    local listBox = CreateBackdropBox(view, 200, 500, "TOPLEFT", view, "TOPLEFT", 10, -10)
    local listTitle = listBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listTitle:SetPoint("TOPLEFT", listBox, "TOPLEFT", 12, -10)
    listTitle:SetText(L["Profesiones"])

    -- Mi profesión: abre la ventana de profesiones del juego (elige cuál si tienes varias)
    local function OpenMyProfession(skillLine)
        if skillLine and C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
            local ok, opened = pcall(C_TradeSkillUI.OpenTradeSkill, skillLine)
            if ok and opened ~= false then return end
        end
        if ToggleProfessionsBook then ToggleProfessionsBook() end
    end
    local btnMyProf = CreateFrame("Button", nil, listBox, "UIPanelButtonTemplate")
    btnMyProf:SetSize(180, 24)
    btnMyProf:SetPoint("BOTTOM", listBox, "BOTTOM", 0, 10)
    btnMyProf:SetText(L["Mi profesión"])
    btnMyProf:SetScript("OnClick", function(self)
        local mine = {}
        for _, index in ipairs({ GetProfessions() }) do
            if index then
                local name, icon, _, _, _, _, skillLine = GetProfessionInfo(index)
                if name then table.insert(mine, { name = name, icon = icon, skillLine = skillLine }) end
            end
        end
        if #mine == 0 then
            OpenMyProfession(nil)
            return
        end
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle(L["Abrir profesión"])
            for _, prof in ipairs(mine) do
                root:CreateButton("|T" .. tostring(prof.icon) .. ":14:14|t " .. prof.name, function() OpenMyProfession(prof.skillLine) end)
            end
            root:CreateButton(L["Libro de profesiones"], function() if ToggleProfessionsBook then ToggleProfessionsBook() end end)
        end)
    end)

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
            if SetMode then SetMode("members") else Refresh() end
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
    searchPlaceholder:SetText(L["Buscar miembro..."])
    searchBox:SetScript("OnTextChanged", function(self)
        searchQuery = string.lower(strtrim(self:GetText() or ""))
        searchPlaceholder:SetShown((self:GetText() or "") == "")
        Refresh()
    end)

    local chkOnline = CreateFrame("CheckButton", "GC_ProfsOnlyOnline", right, "UICheckButtonTemplate")
    chkOnline:SetSize(24, 24)
    chkOnline:SetPoint("LEFT", searchBox, "RIGHT", 14, 0)
    _G[chkOnline:GetName() .. "Text"]:SetText(L["Solo conectados"])
    chkOnline:SetScript("OnClick", function() Refresh() end)

    local countText = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("TOPRIGHT", right, "TOPRIGHT", -16, -16)

    -- Dos contenedores: la profesión que se mira (nombre y habilidad) y la segunda profesión
    -- de cada miembro. Las columnas van dentro de cada uno; la fila de cada miembro cruza los dos.
    local profPanel = CreateColoredPanel(right, "", PANEL_COLORS.blue, 392, 434)
    profPanel:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -40)
    local otherPanel = CreateColoredPanel(right, L["Segunda profesión"], PANEL_COLORS.purple, 236, 434)
    otherPanel:SetPoint("TOPLEFT", profPanel, "TOPRIGHT", 4, 0)

    local COLS = {
        { title = L["Nombre"],     x = 8,   w = 230, key = "name" },
        { title = L["Nivel"],      x = 300, w = 76,  key = "skill",      right = true },
        { title = L["Profesión"],  x = 404, w = 150, key = "other" },
        { title = L["Nivel"],      x = 556, w = 64,  key = "otherSkill", right = true },
    }

    local headerRow = CreateFrame("Frame", nil, right)
    headerRow:SetSize(640, 20)
    headerRow:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -66)
    headerRow:SetFrameLevel(profPanel:GetFrameLevel() + 2)
    local headerButtons = {}
    for _, col in ipairs(COLS) do
        local hb = CreateFrame("Button", nil, headerRow)
        hb:SetPoint("LEFT", headerRow, "LEFT", col.x, 0)
        hb:SetSize(col.w, 20)
        hb.text = hb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if col.right then hb.text:SetPoint("RIGHT", hb, "RIGHT", 0, 0) else hb.text:SetPoint("LEFT", hb, "LEFT", 0, 0) end
        hb.key, hb.title = col.key, col.title
        hb:SetScript("OnClick", function(self)
            if sortKey == self.key then sortAsc = not sortAsc
            else sortKey, sortAsc = self.key, self.key ~= "skill" and self.key ~= "otherSkill" end
            Refresh()
        end)
        uiModule.AddTips({ { hb, col.title, "Clic para ordenar por esta columna. Otro clic invierte el orden." } })
        table.insert(headerButtons, hb)
    end

    local scroll = CreateFrame("ScrollFrame", "GC_ProfsScroll", right, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -28, 30)
    scroll:SetFrameLevel(profPanel:GetFrameLevel() + 2)
    local child = CreateFrame("Frame")
    child:SetSize(636, 1)
    scroll:SetScrollChild(child)

    local emptyText = right:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", right, "CENTER", 0, 0)
    emptyText:SetWidth(560)
    emptyText:SetText(L["Todavía no hay profesiones registradas. Se rellenan al escanear la hermandad."])

    local rowHint = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rowHint:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 14, 2)
    rowHint:SetText(L["Clic en un miembro: susurrar o invitar al grupo"])

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
            fs:SetJustifyH(col.right and "RIGHT" or "LEFT")
            fs:SetWordWrap(false)
            row.cells[i] = fs
        end
        rows[index] = row
        return row
    end

    -- Segunda profesión de un miembro: "Desollar 203" -> "Desollar", 203
    local function SplitOther(other)
        if not other or other == "Ninguna" then return nil, nil end
        local name, level = string.match(other, "^(.-)%s+(%d+)$")
        if name then return name, tonumber(level) end
        return other, nil
    end

    local function SortValue(entry, key)
        if key == "skill" then return entry.skill or -1 end
        if key == "other" then return string.lower(SplitOther(entry.other) or "~") end
        if key == "otherSkill" then return select(2, SplitOther(entry.other)) or -1 end
        return string.lower(entry.name)
    end

    Refresh = function()
        if not view:IsShown() then return end
        local byProf = CollectProfessions()
        local profNames = {}
        for prof in pairs(byProf) do table.insert(profNames, prof) end
        table.sort(profNames)
        -- Al entrar se elige la primera que alguien tenga
        if not selectedProf or not byProf[selectedProf] then
            selectedProf = profNames[1]
            for _, prof in ipairs(profNames) do
                if #byProf[prof] > 0 then selectedProf = prof; break end
            end
        end

        for _, btn in ipairs(profButtons) do btn:Hide() end
        for i, prof in ipairs(profNames) do
            local btn = AcquireProfButton(i)
            btn:SetPoint("TOPLEFT", listBox, "TOPLEFT", 8, -32 - (i - 1) * 24)
            btn.prof = prof
            -- Las que nadie tiene todavía, en gris
            btn.text:SetText(#byProf[prof] > 0 and prof or ("|cFF808080" .. prof .. "|r"))
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
            -- Nombre con apellido (Forever); la clave interna solo sirve para identificar
            local shown = m.displayName or string.match(entry.name, "^([^-]+)") or entry.name
            row.cells[1]:SetText("|cFF" .. addonTable.GetClassColorHex(m.class) .. shown .. "|r" .. dot)
            row.cells[2]:SetText(entry.skill and tostring(entry.skill) or "|cFF808080-|r")
            local otherName, otherLevel = SplitOther(entry.other)
            row.cells[3]:SetText(otherName or "|cFF808080-|r")
            row.cells[4]:SetText(otherLevel and tostring(otherLevel) or "")
            row:Show()
        end
        child:SetHeight(math.max(1, #list * PROF_ROW_HEIGHT))
        -- Profesión que nadie tiene: mensaje en lugar de los contenedores vacíos
        local noOne = selectedProf and #(byProf[selectedProf] or {}) == 0
        emptyText:SetText(noOne and string.format(L["Nadie de la hermandad tiene %s todavía."], selectedProf)
            or L["Todavía no hay profesiones registradas. Se rellenan al escanear la hermandad."])
        emptyText:SetShown(#profNames == 0 or noOne)
        countText:SetText(selectedProf and ("|cFFFFD100" .. #list .. L["|r miembros con "] .. selectedProf) or "")
        profPanel.title:SetText(selectedProf or L["Profesión"])
        profPanel:SetShown(#profNames > 0 and not noOne)
        otherPanel:SetShown(#profNames > 0 and not noOne)
        headerRow:SetShown(#profNames > 0 and not noOne)
    end

    -- ---------------------------------------------------------------------
    -- Artesanos: ¿quién me lo hace? y pedidos (Community.lua)
    -- ---------------------------------------------------------------------
    local C = addonTable.Community
    local mode = "members"
    local craftPanel = CreateBackdropBox(view, 674, 500, "TOPLEFT", listBox, "TOPRIGHT", 6, 0)
    craftPanel:Hide()

    local craftTitle = craftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    craftTitle:SetPoint("TOPLEFT", craftPanel, "TOPLEFT", 14, -10)
    craftTitle:SetText(L["Artesanos: ¿quién me lo hace?"])

    local craftSearch = CreateFrame("EditBox", nil, craftPanel, "InputBoxTemplate")
    craftSearch:SetSize(330, 20)
    craftSearch:SetPoint("TOPLEFT", craftTitle, "BOTTOMLEFT", 4, -8)
    craftSearch:SetAutoFocus(false)
    craftSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    craftSearch:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local craftPlaceholder = craftSearch:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    craftPlaceholder:SetPoint("LEFT", craftSearch, "LEFT", 2, 0)
    craftPlaceholder:SetText(L["Receta, Shift+clic en un objeto o enlace de Wowhead"])
    local craftInfo = craftPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    craftInfo:SetPoint("LEFT", craftSearch, "RIGHT", 12, 0)
    craftInfo:SetWidth(280)
    craftInfo:SetJustifyH("LEFT")

    -- Shift+clic en un objeto (bolsas, chat, enlaces) con el buscador activo: se busca por su nombre
    OnInsertLink(function(link)
            if link and craftSearch:IsVisible() and craftSearch:HasFocus() then
                local name = string.match(link, "%[(.-)%]")
                if name then craftSearch:SetText(name) end
            end
    end)

    local resultsBox = CreateBackdropBox(craftPanel, 650, 206, "TOPLEFT", craftPanel, "TOPLEFT", 12, -60)
    local resultsScroll = CreateFrame("ScrollFrame", nil, resultsBox, "UIPanelScrollFrameTemplate")
    resultsScroll:SetPoint("TOPLEFT", resultsBox, "TOPLEFT", 6, -6)
    resultsScroll:SetPoint("BOTTOMRIGHT", resultsBox, "BOTTOMRIGHT", -26, 6)
    local resultsChild = CreateFrame("Frame")
    resultsChild:SetSize(610, 1)
    resultsScroll:SetScrollChild(resultsChild)
    local resultsEmpty = resultsBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    resultsEmpty:SetPoint("TOPLEFT", resultsBox, "TOPLEFT", 12, -12)
    resultsEmpty:SetWidth(620)
    resultsEmpty:SetJustifyH("LEFT")

    -- Pedir: se elige el artesano (conectados primero) y se escribe una nota
    local function AskOrder(owner, entry)
        local function Ask(crafter)
            uiModule.ShowOrderDialog(crafter, entry.recipeID, entry.name)
        end
        local others = {}
        for _, crafter in ipairs(entry.crafters) do
            if not addonTable.IsMe(crafter) then table.insert(others, crafter) end
        end
        if #others == 0 then
            PrintGC(L["Solo tú conoces esa receta."])
        elseif #others == 1 then
            Ask(others[1])
        else
            MenuUtil.CreateContextMenu(owner, function(_, root)
                root:CreateTitle(L["¿A quién se lo pides?"])
                for _, crafter in ipairs(others) do
                    root:CreateButton(ColoredMemberName(crafter), function() Ask(crafter) end)
                end
            end)
        end
    end

    local resultRows = {}
    local function AcquireResultRow(index)
        local row = resultRows[index]
        if row then return row end
        row = CreateFrame("Frame", nil, resultsChild)
        row:SetSize(610, 36)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.04)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -3)
        row.name:SetPoint("RIGHT", row, "RIGHT", -170, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.who = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.who:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
        row.who:SetPoint("RIGHT", row, "RIGHT", -170, 0)
        row.who:SetJustifyH("LEFT")
        row.who:SetWordWrap(false)
        row.order = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.order:SetSize(78, 22)
        row.order:SetPoint("RIGHT", row, "RIGHT", -86, 0)
        row.order:SetText(L["Pedir"])
        row.whisper = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.whisper:SetSize(78, 22)
        row.whisper:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.whisper:SetText(L["Susurrar"])
        uiModule.AddTips({
            { row.order, "Pedir", "Encarga esta receta a un artesano que la conoce. Si la conocen varios, eliges a quién." },
            { row.whisper, "Susurrar", "Abre un susurro al primer artesano conectado que conoce la receta." },
        })
        resultRows[index] = row
        return row
    end

    local function RefreshResults()
        for _, row in ipairs(resultRows) do row:Hide() end
        local results = C and C.SearchRecipes(craftSearch:GetText(), 40) or {}
        for i, entry in ipairs(results) do
            local row = AcquireResultRow(i)
            row:SetPoint("TOPLEFT", resultsChild, "TOPLEFT", 0, -(i - 1) * 38)
            row.name:SetText("|cFFFFD100" .. entry.name .. "|r |cFF808080(" .. entry.profession .. ")|r")
            local names, firstOnline = {}, nil
            for _, crafter in ipairs(entry.crafters) do
                local m = GuildControlDB.members[crafter]
                if m and m.isOnline and not firstOnline and not addonTable.IsMe(crafter) then firstOnline = crafter end
                table.insert(names, ColoredMemberName(crafter))
            end
            row.who:SetText(table.concat(names, ", "))
            row.whisper:SetEnabled(firstOnline ~= nil)
            row.whisper:SetScript("OnClick", function() WhisperTo(firstOnline) end)
            row.order:SetScript("OnClick", function(self) AskOrder(self, entry) end)
            row:Show()
        end
        resultsChild:SetHeight(math.max(1, #results * 38))
        local query = strtrim(craftSearch:GetText() or "")
        resultsEmpty:SetShown(#results == 0)
        resultsEmpty:SetText(#query < 3
            and L["Escribe el nombre de una receta o haz Shift+clic en un objeto con el buscador activo. Las recetas las comparte cada jugador con GuildControl al abrir y cerrar su ventana de profesión."]
            or L["Nadie de la hermandad ha compartido esa receta todavía."])
        craftInfo:SetText(string.format(L["%d artesanos"], C and C.CountCrafters() or 0))
    end

    local craftSearchTimer = nil
    -- Enlace de Wowhead pegado (".../item=ID/..." o ".../spell=ID/...", también el de Classic):
    -- se busca por el nombre del objeto o de la receta en el idioma del juego. Si el juego aún
    -- no tiene los datos del objeto, se piden y se reintenta unas veces.
    local function ResolveWowhead(text, tries)
        local itemID = tonumber(string.match(text, "[Ii][Tt][Ee][Mm]=(%d+)"))
        local spellID = tonumber(string.match(text, "[Ss][Pp][Ee][Ll][Ll]=(%d+)"))
        local name
        if itemID then
            name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or (GetItemInfo and (GetItemInfo(itemID)))
            if not name then
                if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
                if (tries or 0) < 6 then
                    C_Timer.After(0.5, function()
                        if craftSearch:GetText() == text then ResolveWowhead(text, (tries or 0) + 1) end
                    end)
                end
                return true
            end
        elseif spellID then
            name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or (GetSpellInfo and (GetSpellInfo(spellID)))
        else
            return false
        end
        if name then craftSearch:SetText(name) end
        return true
    end

    craftSearch:SetScript("OnTextChanged", function(self)
        craftPlaceholder:SetShown((self:GetText() or "") == "")
        local text = self:GetText() or ""
        if string.find(string.lower(text), "wowhead", 1, true) or string.match(text, "[Ii][Tt][Ee][Mm]=%d+") then
            if ResolveWowhead(text, 0) then return end
        end
        -- Se busca 0,3 s después de la última tecla (puede haber miles de recetas)
        if craftSearchTimer then craftSearchTimer:Cancel() end
        craftSearchTimer = C_Timer.NewTimer(0.3, function()
            craftSearchTimer = nil
            RefreshResults()
        end)
    end)

    -- Pedidos: los que me hacen (izquierda) y los míos (derecha)
    local function OrderColumn(titleText, x)
        local box = CreateBackdropBox(craftPanel, 322, 216, "TOPLEFT", craftPanel, "TOPLEFT", x, -274)
        box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -8)
        box.title:SetText(titleText)
        box.scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
        box.scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -28)
        box.scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 6)
        box.child = CreateFrame("Frame")
        box.child:SetSize(290, 1)
        box.scroll:SetScrollChild(box.child)
        box.empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        box.empty:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -32)
        box.empty:SetWidth(296)
        box.empty:SetJustifyH("LEFT")
        box.rows = {}
        -- Quita de la lista los pedidos cerrados (hechos, rechazados o cancelados)
        box.clear = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
        box.clear:SetSize(110, 20)
        box.clear:SetPoint("TOPRIGHT", box, "TOPRIGHT", -8, -5)
        box.clear:SetText(L["Limpiar cerrados"])
        return box
    end
    local forMeBox = OrderColumn(L["Me piden"], 12)
    local mineBox = OrderColumn(L["Mis pedidos"], 340)
    forMeBox.clear:SetScript("OnClick", function() if C and C.ClearClosedOrders then C.ClearClosedOrders("forMe") end end)
    mineBox.clear:SetScript("OnClick", function() if C and C.ClearClosedOrders then C.ClearClosedOrders("mine") end end)

    local ORDER_TIPS = {
        [L["Aceptar"]]  = L["Aceptas hacer este pedido. Quien lo pidió recibe el aviso."],
        [L["Rechazar"]] = L["Rechazas el pedido. Quien lo pidió recibe el aviso."],
        [L["Hecho"]]    = L["Marca el pedido como terminado. Quien lo pidió recibe el aviso."],
        [L["Susurrar"]] = L["Abre un susurro con la otra persona del pedido."],
        [L["Cancelar"]] = L["Cancelas tu pedido. El artesano recibe el aviso."],
    }

    local function AcquireOrderRow(box, index)
        local row = box.rows[index]
        if row then return row end
        row = CreateFrame("Frame", nil, box.child)
        row:SetSize(290, 40)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.04)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -3)
        row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.info:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
        row.info:SetPoint("RIGHT", row, "RIGHT", -132, 0)
        row.info:SetJustifyH("LEFT")
        row.info:SetWordWrap(false)
        row.b1 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.b1:SetSize(62, 18)
        row.b1:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -66, 2)
        row.b2 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.b2:SetSize(62, 18)
        row.b2:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 2)
        for _, btn in ipairs({ row.b1, row.b2 }) do
            if btn.SetMotionScriptsWhileDisabled then btn:SetMotionScriptsWhileDisabled(true) end
            btn:SetScript("OnEnter", function(self)
                local tipText = self.tipKey and ORDER_TIPS[self.tipKey]
                if not tipText then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self.tipKey, 1, 1, 1)
                GameTooltip:AddLine(tipText, 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not self.order or not self.order.note or self.order.note == "" then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["Nota del pedido"], 1, 1, 1)
            GameTooltip:AddLine(self.order.note, 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        box.rows[index] = row
        return row
    end

    local function SetButton(btn, text, onClick)
        btn.tipKey = text
        if not text then btn:Hide() return end
        btn:SetText(text)
        btn:SetScript("OnClick", onClick)
        btn:Show()
    end

    local function FillOrders(box, orders, isForMe)
        for _, row in ipairs(box.rows) do row:Hide() end
        for i, order in ipairs(orders) do
            local row = AcquireOrderRow(box, i)
            row.order = order
            row:SetPoint("TOPLEFT", box.child, "TOPLEFT", 0, -(i - 1) * 42)
            local status = "|cFF" .. C.ORDER_COLORS[order.status] .. L[C.ORDER_LABELS[order.status]] .. "|r"
            row.name:SetText("|cFFFFD100" .. (C.RecipeName(order.recipeID) or ("#" .. order.recipeID)) .. "|r  " .. status)
            local other = isForMe and order.requester or order.crafter
            -- Si quien pide aporta los materiales (icono de bolsa) o no
            local mats = order.materials and ("|cFF00FF00" .. L["con materiales"] .. "|r") or ("|cFFFF7F00" .. L["sin materiales"] .. "|r")
            row.info:SetText(ColoredMemberName(other) .. "  " .. mats .. "  |cFF808080" .. date("%d/%m %H:%M", order.at)
                .. ((order.note and order.note ~= "") and " ·" or "") .. "|r")
            local id = order.id
            if isForMe and order.status == "pending" then
                SetButton(row.b1, L["Aceptar"], function() C.SetOrderStatus(id, "accepted") end)
                SetButton(row.b2, L["Rechazar"], function() C.SetOrderStatus(id, "rejected") end)
            elseif isForMe and order.status == "accepted" then
                SetButton(row.b1, L["Hecho"], function() C.SetOrderStatus(id, "done") end)
                SetButton(row.b2, L["Susurrar"], function() WhisperTo(order.requester) end)
            elseif not isForMe and (order.status == "pending" or order.status == "accepted") then
                SetButton(row.b1, L["Susurrar"], function() WhisperTo(order.crafter) end)
                SetButton(row.b2, L["Cancelar"], function() C.SetOrderStatus(id, "cancelled") end)
            else
                SetButton(row.b1, nil)
                SetButton(row.b2, L["Susurrar"], function() WhisperTo(other) end)
            end
            row:Show()
        end
        box.child:SetHeight(math.max(1, #orders * 42))
        box.empty:SetShown(#orders == 0)
    end

    local function RefreshOrders()
        if not C or not C.GetOrders then return end
        local orders = C.GetOrders()
        forMeBox.title:SetText(L["Me piden"] .. " (" .. #orders.forMe .. ")")
        mineBox.title:SetText(L["Mis pedidos"] .. " (" .. #orders.mine .. ")")
        forMeBox.empty:SetText(L["Nadie te ha pedido nada. Cuando alguien te pida una receta, te avisará y aparecerá aquí."])
        mineBox.empty:SetText(L["Busca una receta arriba y pulsa Pedir para encargársela a un artesano."])
        FillOrders(forMeBox, orders.forMe, true)
        FillOrders(mineBox, orders.mine, false)
    end

    local function RefreshCraftPanel()
        if not craftPanel:IsShown() then return end
        RefreshResults()
        RefreshOrders()
    end
    if C and C.AddListener then C.AddListener(RefreshCraftPanel) end

    -- Dos botones separados encima de Mi profesión: el de la vista actual queda desactivado
    local btnCrafts = CreateFrame("Button", nil, listBox, "UIPanelButtonTemplate")
    btnCrafts:SetSize(180, 24)
    btnCrafts:SetPoint("BOTTOM", btnMyProf, "TOP", 0, 4)
    btnCrafts:SetText(L["Artesanos y pedidos"])
    local btnMembers = CreateFrame("Button", nil, listBox, "UIPanelButtonTemplate")
    btnMembers:SetSize(180, 24)
    btnMembers:SetPoint("BOTTOM", btnCrafts, "TOP", 0, 4)
    btnMembers:SetText(L["Ver miembros"])

    SetMode = function(newMode)
        mode = newMode
        right:SetShown(mode == "members")
        craftPanel:SetShown(mode == "crafts")
        btnMembers:SetEnabled(mode ~= "members")
        btnCrafts:SetEnabled(mode ~= "crafts")
        -- Al abrir los artesanos se piden las recetas a la hermandad (como mucho una vez por minuto)
        if mode == "crafts" and C and C.RequestRecipes then C.RequestRecipes() end
        if mode == "crafts" then RefreshCraftPanel() else Refresh() end
    end
    btnCrafts:SetScript("OnClick", function() SetMode("crafts") end)
    btnMembers:SetScript("OnClick", function() SetMode("members") end)
    btnMembers:SetEnabled(false)
    uiModule.OpenCraftOrders = function()
        SwitchTab("Profesiones")
        SetMode("crafts")
    end

    view:SetScript("OnShow", function() if mode == "crafts" then RefreshCraftPanel() else Refresh() end end)
    uiModule.AddTips({
        { btnMyProf, "Mi profesión", "Abre la ventana de tu profesión (si tienes varias, eliges cuál). Al cerrarla, tus recetas se envían a la hermandad." },
        { searchBox, "Buscar miembro", "Filtra la lista por el nombre del miembro." },
        { chkOnline, "Solo conectados", "Muestra solo a los miembros conectados ahora." },
        { craftSearch, "Buscar receta", "Escribe el nombre de una receta, haz Shift+clic en un objeto o pega un enlace de Wowhead para ver quién de la hermandad sabe hacerlo." },
        { forMeBox.clear, "Limpiar cerrados", "Quita de la lista los pedidos que te hicieron y ya están hechos, rechazados o cancelados." },
        { mineBox.clear, "Limpiar cerrados", "Quita de la lista tus pedidos que ya están hechos, rechazados o cancelados." },
        { btnCrafts, "Artesanos y pedidos", "Busca quién de la hermandad sabe hacer una receta, pídesela y sigue tus pedidos." },
        { btnMembers, "Ver miembros", "Vuelve a la lista de profesiones de los miembros." },
    })
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
    listTitle:SetText(L["Puntuación Mítica+ de la hermandad"])

    local searchBox = CreateFrame("EditBox", nil, listBox, "InputBoxTemplate")
    searchBox:SetSize(170, 20)
    searchBox:SetPoint("TOPLEFT", listTitle, "BOTTOMLEFT", 6, -10)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
    searchPlaceholder:SetText(L["Buscar miembro..."])
    searchBox:SetScript("OnTextChanged", function(self)
        searchQuery = string.lower(strtrim(self:GetText() or ""))
        searchPlaceholder:SetShown((self:GetText() or "") == "")
        Refresh()
    end)

    local chkOnline = CreateFrame("CheckButton", "GC_MPlusOnlyOnline", listBox, "UICheckButtonTemplate")
    chkOnline:SetSize(24, 24)
    chkOnline:SetPoint("LEFT", searchBox, "RIGHT", 12, 0)
    _G[chkOnline:GetName() .. "Text"]:SetText(L["Conectados"])
    chkOnline:SetScript("OnClick", function() Refresh() end)

    local chkKeys = CreateFrame("CheckButton", "GC_MPlusOnlyKeys", listBox, "UICheckButtonTemplate")
    chkKeys:SetSize(24, 24)
    chkKeys:SetPoint("LEFT", chkOnline, "RIGHT", 90, 0)
    _G[chkKeys:GetName() .. "Text"]:SetText(L["Con llave"])
    chkKeys:SetScript("OnClick", function() Refresh() end)

    local COLS = {
        { title = "#",          x = 6,   w = 26 },
        { title = L["Nombre"],     x = 34,  w = 170 },
        { title = L["Rol"],        x = 206, w = 70 },
        { title = L["Puntuación"], x = 278, w = 80 },
        { title = L["Llave"],      x = 362, w = 160 },
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
    listHint:SetText(L["La puntuación sale de la lista de la hermandad del juego; las llaves, de quien usa GuildControl."])

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
    local affixBox = SideBox(L["Afijos de la semana"], 116)
    local keyBox = SideBox(L["Tu llave y tu puntuación"], 76, affixBox)
    local bestBox = SideBox(L["Tus mejores mazmorras de la temporada"], 296, keyBox)

    local btnRequest = CreateFrame("Button", nil, keyBox, "UIPanelButtonTemplate")
    btnRequest:SetSize(110, 20)
    btnRequest:SetPoint("TOPRIGHT", keyBox, "TOPRIGHT", -8, -6)
    btnRequest:SetText(L["Pedir llaves"])
    btnRequest:SetScript("OnClick", function()
        M.BroadcastKeystone(true)
        M.RequestKeystones()
        PrintGC(L["Pidiendo las llaves a los miembros conectados con GuildControl..."])
    end)

    local function KeystoneText(keystone)
        if not keystone then return "" end
        local name = M.GetMapName(keystone.mapID) or (L["Mazmorra "] .. keystone.mapID)
        return "|cFFA335EE+" .. keystone.level .. "|r " .. name
    end

    local function RefreshSide()
        local affixLines = {}
        for _, affix in ipairs(M.GetAffixes()) do
            table.insert(affixLines, (affix.icon and ("|T" .. affix.icon .. ":16:16|t ") or "") .. "|cFFFFD100" .. affix.name .. "|r")
        end
        affixBox.text:SetText(#affixLines > 0 and table.concat(affixLines, "\n") or L["|cFF808080Sin datos de afijos todavía.|r"])

        local mapID, level = M.GetMyKeystone()
        local myScore = M.GetMyScore()
        keyBox.text:SetText((mapID and (L["Llave: "] .. KeystoneText({ mapID = mapID, level = level })) or L["|cFF808080No tienes llave.|r"])
            .. L["\nPuntuación: |cFF"] .. M.ScoreColorHex(myScore) .. myScore .. "|r")

        local bestLines = {}
        for _, run in ipairs(M.GetMyBestRuns()) do
            if run.level > 0 then
                local timeColor = run.inTime and "00FF00" or "FF7F00"
                table.insert(bestLines, "|cFF" .. timeColor .. "+" .. run.level .. "|r  " .. run.name
                    .. L["  |cFF"] .. M.ScoreColorHex(run.score * 8) .. math.floor(run.score) .. "|r")
            else
                table.insert(bestLines, "|cFF808080-  " .. run.name .. "|r")
            end
        end
        bestBox.text:SetText(#bestLines > 0 and table.concat(bestLines, "\n") or L["|cFF808080Sin datos de la temporada todavía.|r"])
    end

    Refresh = function()
        if not view:IsShown() then return end
        for _, row in ipairs(rows) do row:Hide() end
        local list = {}
        for fullName, m in pairs(GuildControlDB.members or {}) do
            local keystone = M.GetKeystone(fullName)
            local pass = (not chkOnline:GetChecked() or m.isOnline)
                and (not chkKeys:GetChecked() or keystone ~= nil)
                and (searchQuery == "" or string.find(string.lower(fullName), searchQuery, 1, true))
                and ((m.mplusScore or 0) > 0 or keystone ~= nil)
            if pass then table.insert(list, { name = fullName, data = m, keystone = keystone }) end
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
            row.cells[3]:SetText(HasDefinedRole(m) and (RoleIcon(m.role, 12) .. " " .. L[m.role]) or "")
            row.cells[4]:SetText("|cFF" .. M.ScoreColorHex(score) .. score .. "|r")
            row.cells[5]:SetText(KeystoneText(entry.keystone))
            row:Show()
        end
        child:SetHeight(math.max(1, #list * MPLUS_ROW_HEIGHT))
        RefreshSide()
    end

    M.AddListener(function() Refresh() end)
    view:SetScript("OnShow", function()
        M.RequestData()
        M.UpdateScores(true)
        M.RequestKeystones(true)   -- con límite de tiempo: no repite la petición cada vez
        Refresh()
    end)
    containers.views["Míticas+"] = view
end

-- =========================================================================
-- 8j. VISTA RAID: PLANNING (INSCRIPCIONES) Y VISTA DE GRUPOS (CONSUME RAIDEVENTS.LUA)
-- =========================================================================
local RAID_WEEKDAYS = { "Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado" }
local RAID_DIFFICULTY_LABELS = { normal = "Normal", heroic = "Heroica", mythic = "Mítica" }

local function RaidEventDateText(event, long)
    local y, mo, d = string.match(event.date or "", "^(%d+)-(%d+)-(%d+)$")
    if not y then return event.date or "" end
    local t = time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 })
    local weekday = L[RAID_WEEKDAYS[tonumber(date("%w", t)) + 1]]
    if long then return weekday .. " " .. d .. "/" .. mo .. "/" .. y .. L[" a las "] .. event.time end
    return string.sub(weekday, 1, 3) .. " " .. d .. "/" .. mo .. " " .. event.time
end

-- Recordar al roster (botón de la pestaña Roster): susurra a los integrantes conectados del
-- roster de la banda que todavía no se han apuntado; a los desconectados se les avisa en la
-- ventana de tareas cuando entren (RaidEvents.SetReminder)
function uiModule.RemindRoster(event)
    if not event then
        PrintGC(L["Elige una banda de Raid para recordar a su roster."])
        return
    end
    local roster = addonTable.Roster and addonTable.Roster.FindByEvent(event.id)
    if not roster or not next(roster.members) then
        PrintGC(L["Esta banda aún no tiene roster (se monta en la pestaña Roster)."])
        return
    end
    local me, sent = string.match(UnitName("player") or "", "^(%S+)"), 0   -- sin apellido (Forever)
    local offline = {}
    for name in pairs(roster.members) do
        local m = GuildControlDB.members[name]
        if not event.signups[name] and string.match(name, "^([^-]+)") ~= me then
            if m and m.isOnline then
                SendWhisper(name, L["¡Hola! Hay banda ("] .. event.title .. L[") el "] .. RaidEventDateText(event, true)
                    .. L[". Apúntate en GuildControl > Raid, por favor."])
                sent = sent + 1
            else
                table.insert(offline, name)
            end
        end
    end
    PrintGC(L["Recordatorios enviados a |cFFFFD100"] .. sent .. L["|r miembros del roster sin responder."])
    if #offline > 0 and addonTable.RaidEvents.SetReminder then
        addonTable.RaidEvents.SetReminder(event, offline)
        PrintGC(string.format(L["Los |cFFFFD100%d|r desconectados lo verán al entrar (si usan GuildControl)."], #offline))
    end
end

local function SignupName(name, signup)
    local m = GuildControlDB.members[name] or {}
    local short = string.match(name, "^([^-]+)") or name
    local text = "|cFF" .. addonTable.GetClassColorHex(m.class) .. short .. "|r"
    if signup and signup.spec and signup.spec ~= "" then text = text .. " |cFF808080" .. signup.spec .. "|r" end
    if signup and signup.status == "late" then text = text .. L[" |cFFFFD100(tarde)|r"] end
    return text
end

-- Mi especialización actual (para inscribirme)
local function CurrentSpecName()
    if GetSpecialization and GetSpecializationInfo then
        local index = GetSpecialization()
        if index then
            local _, name = GetSpecializationInfo(index)
            if name then return name end
        end
    end
    return addonTable.Profiles and addonTable.Profiles.GetMyProfile().spec or ""
end

local function BuildRaidView(parent)
    local E = addonTable.RaidEvents
    local R = addonTable.Roster
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local selectedEventId = nil
    local mode = "planning"           -- "planning", "groups", "attendance" (solo oficiales) o "history"
    local editing = nil               -- nil, "new" o el evento que se edita
    local Refresh

    local function SelectedEvent() return E.Get(selectedEventId) end
    local function IsOfficerProfile() return not addonTable.Profiles or addonTable.Profiles.IsOfficer() end

    -- Tooltip con la explicación de cada botón (también si está desactivado)
    local function Tip(btn, titleText, text)
        btn:SetMotionScriptsWhileDisabled(true)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(titleText, 1, 1, 1)
            GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", view, "TOPLEFT", 16, -12)
    title:SetText(L["Raid"])

    -- Ayudante: panel pequeño para la banda (listos, pull, marcas, buffos, pizarra...)
    local btnMini = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnMini:SetSize(110, 22)
    btnMini:SetPoint("LEFT", title, "RIGHT", 20, 0)
    btnMini:SetText(L["Ayudante"])
    btnMini:SetScript("OnClick", function() if uiModule.EnterMiniMode then uiModule.EnterMiniMode() end end)
    btnMini:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Ayudante"], 1, 1, 1)
        GameTooltip:AddLine(L["Cambia la ventana por un panel pequeño para la banda: listos, pull, marcas, descanso, buff check, botín y pizarra."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnMini:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local btnAttendance = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnAttendance:SetSize(110, 22)
    btnAttendance:SetPoint("TOPRIGHT", view, "TOPRIGHT", -10, -10)
    btnAttendance:SetText(L["Asistencia"])
    btnAttendance:SetScript("OnClick", function() mode = "attendance"; editing = nil; Refresh() end)
    local btnGroups = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnGroups:SetSize(130, 22)
    btnGroups:SetPoint("RIGHT", btnAttendance, "LEFT", -6, 0)
    btnGroups:SetText(L["Vista de grupos"])
    local btnPlanning = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnPlanning:SetSize(130, 22)
    btnPlanning:SetPoint("RIGHT", btnGroups, "LEFT", -6, 0)
    btnPlanning:SetText(L["Planning raid"])
    btnPlanning:SetScript("OnClick", function() mode = "planning"; Refresh() end)
    btnGroups:SetScript("OnClick", function() mode = "groups"; editing = nil; Refresh() end)
    local btnHistory = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnHistory:SetSize(100, 22)
    btnHistory:SetPoint("RIGHT", btnPlanning, "LEFT", -6, 0)
    btnHistory:SetText(L["Historial"])
    btnHistory:SetScript("OnClick", function() mode = "history"; editing = nil; selectedEventId = nil; Refresh() end)
    Tip(btnAttendance, L["Asistencia"], L["Solo oficiales: pasa lista en la banda elegida (presente, tarde, ausente o justificado). Se envía a la hermandad y cuenta en Roster y Warning."])
    Tip(btnGroups, L["Vista de grupos"], L["Reparte a los apuntados en los 8 grupos de la banda; los oficiales pueden publicarlos y aplicarlos en la banda."])
    Tip(btnPlanning, L["Planning raid"], L["Las próximas bandas: detalles, quién se ha apuntado y tu respuesta."])
    Tip(btnHistory, L["Historial"], L["Bandas ya jugadas, con los jefes que murieron y la asistencia."])

    -- ---------------------------------------------------------------------
    -- Lista de bandas (izquierda, común a los dos modos)
    -- ---------------------------------------------------------------------
    local listBox = CreateBackdropBox(view, 230, 470, "TOPLEFT", view, "TOPLEFT", 10, -40)
    local listTitle = listBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listTitle:SetPoint("TOPLEFT", listBox, "TOPLEFT", 12, -10)
    listTitle:SetText(L["Próximas bandas"])

    local btnNew = CreateFrame("Button", nil, listBox, "UIPanelButtonTemplate")
    btnNew:SetSize(70, 20)
    btnNew:SetPoint("TOPRIGHT", listBox, "TOPRIGHT", -8, -6)
    btnNew:SetText(L["Nueva"])
    btnNew:SetScript("OnClick", function() editing = "new"; mode = "planning"; Refresh() end)
    Tip(btnNew, L["Nueva banda"], L["Solo oficiales: crea una banda con fecha y hora y la publica en la hermandad para que se apunten."])

    local eventButtons = {}
    local function AcquireEventButton(index)
        local btn = eventButtons[index]
        if btn then return btn end
        btn = CreateFrame("Button", nil, listBox)
        btn:SetSize(214, 44)
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.highlight:SetAllPoints()
        btn.highlight:SetColorTexture(1, 1, 1, 0.08)
        btn.titleFs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        btn.titleFs:SetPoint("TOPLEFT", btn, "TOPLEFT", 8, -6)
        btn.titleFs:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        btn.titleFs:SetJustifyH("LEFT")
        btn.titleFs:SetWordWrap(false)
        btn.infoFs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.infoFs:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 8, 6)
        btn.infoFs:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        btn.infoFs:SetJustifyH("LEFT")
        btn:SetScript("OnClick", function(self)
            selectedEventId = self.eventId
            editing = nil
            Refresh()
        end)
        eventButtons[index] = btn
        return btn
    end

    local listEmpty = listBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listEmpty:SetPoint("TOPLEFT", listBox, "TOPLEFT", 12, -40)
    listEmpty:SetWidth(206)
    listEmpty:SetJustifyH("LEFT")

    -- ---------------------------------------------------------------------
    -- Planning: detalle de la banda e inscripciones
    -- ---------------------------------------------------------------------
    local detail = CreateBackdropBox(view, 644, 470, "TOPLEFT", listBox, "TOPRIGHT", 6, 0)

    local evTitle = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    evTitle:SetPoint("TOPLEFT", detail, "TOPLEFT", 14, -12)
    evTitle:SetPoint("RIGHT", detail, "RIGHT", -200, 0)
    evTitle:SetJustifyH("LEFT")
    evTitle:SetWordWrap(false)
    local evInfo = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    evInfo:SetPoint("TOPLEFT", evTitle, "BOTTOMLEFT", 0, -6)
    evInfo:SetPoint("RIGHT", detail, "RIGHT", -206, 0)
    evInfo:SetJustifyH("LEFT")
    local evDesc = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    evDesc:SetPoint("TOPLEFT", evInfo, "BOTTOMLEFT", 0, -4)
    evDesc:SetPoint("RIGHT", detail, "RIGHT", -14, 0)
    evDesc:SetJustifyH("LEFT")
    evDesc:SetMaxLines(2)

    -- Roster asociado: lo propio (oficiales) o el publicado (jugadores)
    local function FindRosterByName(name)
        if not name then return nil end
        for _, roster in ipairs(R.GetAll()) do
            if roster.name == name then return roster end
        end
        for _, item in ipairs(R.GetSharedRosters()) do
            if item.roster.name == name then return item.roster end
        end
        return nil
    end

    -- Roster publicado de la banda (el que ven todos; el que se edita en vivo no se muestra aquí)
    local function FindEventRoster(event)
        if not event then return nil end
        for _, item in ipairs(R.GetSharedRosters()) do
            if item.roster.eventId == event.id then return item.roster end
        end
        return nil
    end

    -- Vista previa del roster publicado: sus integrantes por rol y qué ha respondido cada uno
    local function ShowRosterPreview(event)
        local roster = FindEventRoster(event)
        if not roster then
            SetPreviewText(L["|cFF808080El roster de esta banda aún no se ha publicado.|r"])
            return
        end
        local lines = { "|cFFFFD100" .. roster.name .. "|r", R.DifficultyLabel(roster) .. L[" · "] .. roster.size .. L[" jugadores"], "" }
        local bySlot = R.GetMembersBySlot(roster)
        local answered, total = 0, 0
        for _, slot in ipairs(R.SLOTS) do
            local names = bySlot[slot] or {}
            table.insert(lines, (slot ~= "bench" and (RoleIcon(slot, 14) .. " ") or "") .. "|cFFFFD100" .. L[R.SLOT_LABELS[slot]] .. " (" .. #names .. ")|r")
            for _, name in ipairs(names) do
                total = total + 1
                local signup = event.signups[name]
                local mark
                if signup then
                    answered = answered + 1
                    mark = "|cFF" .. E.STATUS_COLORS[signup.status] .. L[E.STATUS_LABELS[signup.status]] .. "|r"
                else
                    mark = L["|cFFFF7F00sin responder|r"]
                end
                table.insert(lines, "  " .. SignupName(name) .. "  " .. mark)
            end
            table.insert(lines, "")
        end
        table.insert(lines, L["Han respondido: |cFFFFD100"] .. answered .. "/" .. total .. "|r")
        SetPreviewText(table.concat(lines, "\n"))
    end

    local btnRosterPreview = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    btnRosterPreview:SetSize(186, 22)
    btnRosterPreview:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -14, -36)
    btnRosterPreview:SetText(L["Ver roster"])
    btnRosterPreview:SetScript("OnClick", function() ShowRosterPreview(SelectedEvent()) end)
    Tip(btnRosterPreview, L["Ver roster"], L["Muestra en la vista previa el roster de esta banda (el tuyo o el que publicaron los oficiales)."])

    -- Acciones de oficial: editar, eliminar, invitar y recordar
    local officerBar = CreateFrame("Frame", nil, detail)
    officerBar:SetSize(190, 22)
    officerBar:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -10, -10)
    local btnEdit = CreateFrame("Button", nil, officerBar, "UIPanelButtonTemplate")
    btnEdit:SetSize(80, 22)
    btnEdit:SetPoint("LEFT", officerBar, "LEFT", 0, 0)
    btnEdit:SetText(L["Editar"])
    btnEdit:SetScript("OnClick", function() editing = SelectedEvent(); Refresh() end)
    Tip(btnEdit, L["Editar"], L["Cambia el título, la banda, la fecha, la hora o la descripción y la vuelve a publicar."])
    local deleteArmedUntil = 0
    local btnDelete = CreateFrame("Button", nil, officerBar, "UIPanelButtonTemplate")
    btnDelete:SetSize(100, 22)
    btnDelete:SetPoint("LEFT", btnEdit, "RIGHT", 6, 0)
    btnDelete:SetText(L["Eliminar"])
    btnDelete:SetScript("OnClick", function(self)
        if GetTime() < deleteArmedUntil then
            deleteArmedUntil = 0
            self:SetText(L["Eliminar"])
            E.Delete(SelectedEvent())
            selectedEventId = nil
            Refresh()
        else
            deleteArmedUntil = GetTime() + 4
            self:SetText(L["|cFFFF3333¿Seguro?|r"])
            C_Timer.After(4, function() if GetTime() >= deleteArmedUntil then self:SetText(L["Eliminar"]) end end)
        end
    end)

    Tip(btnDelete, L["Eliminar"], L["Borra la banda para toda la hermandad. Pide un segundo clic para confirmar."])

    -- Barra de inscripción (todos)
    local signBar = CreateFrame("Frame", nil, detail)
    signBar:SetSize(620, 52)
    signBar:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -84)
    local signLabel = signBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    signLabel:SetPoint("TOPLEFT", signBar, "TOPLEFT", 2, 0)
    signLabel:SetText(L["Tu respuesta:"])
    local mySignupText = signBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mySignupText:SetPoint("LEFT", signLabel, "RIGHT", 10, 0)

    local noteInput = CreateFrame("EditBox", nil, signBar, "InputBoxTemplate")
    noteInput:SetSize(150, 20)
    noteInput:SetPoint("TOPRIGHT", signBar, "TOPRIGHT", -4, 2)
    noteInput:SetAutoFocus(false)
    noteInput:SetMaxLetters(60)
    noteInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    noteInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local notePlaceholder = noteInput:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    notePlaceholder:SetPoint("LEFT", noteInput, "LEFT", 2, 0)
    notePlaceholder:SetText(L["Nota (opcional)"])
    noteInput:SetScript("OnTextChanged", function(self) notePlaceholder:SetShown((self:GetText() or "") == "") end)

    local signButtons = {}
    local SIGN_OPTIONS = {
        { label = RoleIcon("tank", 14) .. L[" Tanque"], status = "signed", role = "tank", width = 92, title = L["Tanque"],
            tip = L["Te apuntas como tanque (solo si tu clase puede serlo)."] },
        { label = RoleIcon("healer", 14) .. L[" Sanador"], status = "signed", role = "healer", width = 96, title = L["Sanador"],
            tip = L["Te apuntas como sanador (solo si tu clase puede serlo)."] },
        { label = RoleIcon("dps", 14) .. L[" DPS"], status = "signed", role = "dps", width = 74, title = L["DPS"],
            tip = L["Te apuntas como DPS."] },
        { label = L["Tarde"], status = "late", width = 64, title = L["Tarde"],
            tip = L["Vienes, pero llegarás tarde. Conserva el rol que elegiste (o el de Mi perfil)."] },
        { label = L["Ausente"], status = "absent", width = 70, title = L["Ausente"],
            tip = L["No puedes venir. La nota de al lado sirve para explicar el motivo."] },
    }
    local previousSign = nil
    for _, option in ipairs(SIGN_OPTIONS) do
        local btn = CreateFrame("Button", nil, signBar, "UIPanelButtonTemplate")
        btn:SetSize(option.width, 22)
        if previousSign then btn:SetPoint("LEFT", previousSign, "RIGHT", 4, 0) else btn:SetPoint("BOTTOMLEFT", signBar, "BOTTOMLEFT", 0, 2) end
        btn:SetText(L[option.label])
        btn:SetScript("OnClick", function()
            local event = SelectedEvent()
            if not event then return end
            -- "Tarde" conserva el rol elegido antes; si no hay, el de Mi perfil
            local current = E.GetMySignup(event)
            local role = option.role or (current and current.role)
            if not role and addonTable.Roster then role = addonTable.Roster.GetDefinedSlot(addonTable.Profiles.GetMyFullName()) end
            E.SignUp(event, option.status, role, CurrentSpecName(), noteInput:GetText())
        end)
        btn.role = option.role
        Tip(btn, option.title, option.tip)
        table.insert(signButtons, btn)
        previousSign = btn
    end

    local countsText = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    countsText:SetPoint("TOPLEFT", signBar, "BOTTOMLEFT", 2, -10)

    -- Apuntados por rol, cada rol en un contenedor de su color (como en Roster); debajo, la
    -- fila de otros estados. col:SetHeader(texto) pone la cabecera y col:SetText(texto, texto2)
    -- la lista (texto2 = segunda columna de nombres, solo en el de DPS, que es más ancho).
    local function Column(x, width, color, columns)
        local panel = CreateColoredPanel(detail, "", color, width, 232)
        panel:SetPoint("TOPLEFT", detail, "TOPLEFT", x, -164)
        local colWidth = (width - 16) / (columns or 1)
        local function NamesText(offset)
            local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", panel, "TOPLEFT", 8 + offset, -30)
            fs:SetWidth(colWidth - 4)
            fs:SetJustifyH("LEFT")
            fs:SetJustifyV("TOP")
            fs:SetSpacing(3)
            return fs
        end
        local fs = NamesText(0)
        local fs2 = (columns or 1) > 1 and NamesText(colWidth) or nil
        panel.columns = columns or 1
        panel.SetHeader = function(self, text) self.title:SetText(text) end
        panel.SetText = function(_, text, text2)
            fs:SetText(text)
            if fs2 then fs2:SetText(text2 or "") end
        end
        return panel
    end
    -- Tanques y sanadores suelen ser pocos: sus contenedores son más estrechos que el de DPS
    local tankCol = Column(12, 150, PANEL_COLORS.blue)
    local healerCol = Column(166, 160, PANEL_COLORS.green)
    local dpsCol = Column(330, 302, PANEL_COLORS.red, 2)
    local otherText = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    otherText:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 16, 44)
    otherText:SetPoint("RIGHT", detail, "RIGHT", -14, 0)
    otherText:SetJustifyH("LEFT")
    otherText:SetSpacing(3)

    -- Acciones de oficial al pie: invitar a los apuntados y recordar al roster
    local footer = CreateFrame("Frame", nil, detail)
    footer:SetSize(620, 24)
    footer:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 12, 10)

    local function InviteSigned(event)
        local me = string.match(UnitName("player") or "", "^(%S+)")   -- sin apellido (Forever)
        local names = {}
        for name, s in pairs(event.signups) do
            local m = GuildControlDB.members[name]
            if (s.status == "signed" or s.status == "late") and m and m.isOnline and (string.match(name, "^([^-]+)") ~= me) then
                table.insert(names, name)
            end
        end
        if #names == 0 then
            PrintGC(L["No hay apuntados conectados a los que invitar."])
            return
        end
        -- Se reutiliza la invitación del roster (convierte en banda al pasar de 5)
        local temp = { members = {} }
        for _, name in ipairs(names) do temp.members[name] = "dps" end
        R.InviteRoster(temp)
        PrintGC(L["Invitando a |cFFFFD100"] .. #names .. L["|r apuntados."])
    end

    local btnInvite = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    btnInvite:SetSize(170, 22)
    btnInvite:SetPoint("LEFT", footer, "LEFT", 0, 0)
    btnInvite:SetText(L["Invitar a los apuntados"])
    btnInvite:SetScript("OnClick", function() local ev = SelectedEvent(); if ev then InviteSigned(ev) end end)
    Tip(btnInvite, L["Invitar a los apuntados"], L["Invita al grupo a los apuntados que están conectados (no a los ausentes)."])

    local btnRepublish = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    btnRepublish:SetSize(120, 22)
    btnRepublish:SetPoint("LEFT", btnInvite, "RIGHT", 6, 0)
    btnRepublish:SetText(L["Publicar de nuevo"])
    btnRepublish:SetScript("OnClick", function()
        local ev = SelectedEvent()
        if ev then E.Publish(ev); PrintGC(L["Banda enviada de nuevo a la hermandad."]) end
    end)
    Tip(btnRepublish, L["Publicar de nuevo"], L["Vuelve a enviar la banda a la hermandad, por si a alguien no le ha llegado."])

    local btnRefreshEvents = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    btnRefreshEvents:SetSize(100, 22)
    btnRefreshEvents:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
    btnRefreshEvents:SetText(L["Actualizar"])
    btnRefreshEvents:SetScript("OnClick", function() E.RequestEvents() end)
    Tip(btnRefreshEvents, L["Actualizar"], L["Pide a la hermandad las bandas y las inscripciones que te falten."])

    local emptyDetail = detail:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyDetail:SetPoint("CENTER", detail, "CENTER", 0, 0)
    emptyDetail:SetWidth(560)

    -- ---------------------------------------------------------------------
    -- Formulario de crear o editar banda (oficiales)
    -- ---------------------------------------------------------------------
    local form = CreateFrame("Frame", nil, detail)
    form:SetAllPoints()
    form:Hide()
    local formTitle = form:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    formTitle:SetPoint("TOPLEFT", form, "TOPLEFT", 14, -14)

    local formFields = { raidId = nil, raidName = nil, difficulty = "heroic", rosterName = nil }
    local function FormLabel(text, x, y)
        local fs = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", form, "TOPLEFT", x, y)
        fs:SetText(text)
        return fs
    end
    local function FormInput(anchor, width, maxLetters)
        local input = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
        input:SetSize(width, 20)
        input:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 6, -4)
        input:SetAutoFocus(false)
        input:SetMaxLetters(maxLetters or 40)
        input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return input
    end

    local titleInput = FormInput(FormLabel(L["Título"], 16, -50), 260, 40)
    -- El título sale de la banda elegida: no se escribe a mano
    titleInput:Disable()
    titleInput:SetTextColor(0.8, 0.8, 0.8)
    local raidLabel = FormLabel(L["Banda (diario de encuentros)"], 316, -50)
    local btnRaid = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    btnRaid:SetSize(260, 22)
    btnRaid:SetPoint("TOPLEFT", raidLabel, "BOTTOMLEFT", 0, -2)
    btnRaid:SetScript("OnClick", function(self)
        local tiers = R.GetRaidTiers(3)
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateButton(L["Sin banda concreta"], function()
                formFields.raidId, formFields.raidName = nil, nil
                self:SetText(L["Sin banda concreta"])
                titleInput:SetText(L["Banda"])
            end)
            for i, tier in ipairs(tiers) do
                local menu = (i == 1) and root or root:CreateButton(tier.name)
                if i == 1 then root:CreateTitle(tier.name) end
                for _, raid in ipairs(tier.raids) do
                    menu:CreateButton(raid.name, function()
                        formFields.raidId, formFields.raidName = raid.id, raid.name
                        self:SetText(raid.name)
                        titleInput:SetText(raid.name)
                    end)
                end
            end
        end)
    end)

    local diffLabel = FormLabel(L["Dificultad"], 16, -100)
    local dropDiff = CreateFrame("DropdownButton", "GC_RaidFormDifficulty", form, "WowStyle1DropdownTemplate")
    dropDiff:SetPoint("TOPLEFT", diffLabel, "BOTTOMLEFT", 0, -2)
    dropDiff:SetWidth(130)
    dropDiff:SetupMenu(function(_, root)
        for _, key in ipairs({ "normal", "heroic", "mythic" }) do
            root:CreateRadio(L[RAID_DIFFICULTY_LABELS[key]], function() return formFields.difficulty == key end,
                function() formFields.difficulty = key; dropDiff:SetText(L[RAID_DIFFICULTY_LABELS[key]]) end)
        end
    end)
    local sizeInput = FormInput(FormLabel(L["Tamaño"], 170, -100), 40, 2)
    sizeInput:SetNumeric(true)
    local dateInput = FormInput(FormLabel(L["Fecha (DD/MM/AAAA)"], 240, -100), 100, 10)
    local timeInput = FormInput(FormLabel(L["Hora"], 370, -100), 50, 5)

    local rosterLabel = FormLabel(L["Roster asociado (para recordatorios)"], 440, -100)
    local dropRosterLink = CreateFrame("DropdownButton", "GC_RaidFormRoster", form, "WowStyle1DropdownTemplate")
    dropRosterLink:SetPoint("TOPLEFT", rosterLabel, "BOTTOMLEFT", 0, -2)
    dropRosterLink:SetWidth(170)
    dropRosterLink:SetupMenu(function(_, root)
        root:CreateRadio(L["Ninguno"], function() return formFields.rosterName == nil end,
            function() formFields.rosterName = nil; dropRosterLink:SetText(L["Ninguno"]) end)
        for _, roster in ipairs(R.GetAll()) do
            local name = roster.name
            root:CreateRadio(name, function() return formFields.rosterName == name end,
                function() formFields.rosterName = name; dropRosterLink:SetText(name) end)
        end
    end)
    -- El roster se monta después, en la pestaña Roster: aquí ya no se elige
    rosterLabel:Hide()
    dropRosterLink:Hide()

    local descInput = FormInput(FormLabel(L["Descripción (estrategia, requisitos, consumibles...)"], 16, -150), 600, 160)

    local formError = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    formError:SetPoint("TOPLEFT", descInput, "BOTTOMLEFT", -6, -14)
    formError:SetTextColor(1, 0.3, 0.3)

    local formHint = form:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    formHint:SetPoint("TOPLEFT", formError, "BOTTOMLEFT", 0, -8)
    formHint:SetWidth(600)
    formHint:SetJustifyH("LEFT")
    formHint:SetText(L["Al guardar, la banda se publica en la hermandad y los miembros con GuildControl pueden apuntarse desde Raid > Planning raid."])

    local btnSave = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    btnSave:SetSize(170, 24)
    btnSave:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 14, 12)
    btnSave:SetText(L["Guardar y publicar"])
    btnSave:SetScript("OnClick", function()
        local fields = {
            title = titleInput:GetText(), raidId = formFields.raidId, raidName = formFields.raidName,
            difficulty = formFields.difficulty, size = sizeInput:GetText(),
            dateText = dateInput:GetText(), timeText = timeInput:GetText(),
            description = descInput:GetText(), rosterName = formFields.rosterName,
        }
        local event, err
        if editing == "new" then event, err = E.Create(fields) else event, err = E.Update(editing, fields) end
        if not event then
            formError:SetText(err or L["No se pudo guardar."])
            return
        end
        selectedEventId = event.id
        editing = nil
        Refresh()
    end)
    local btnCancel = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    btnCancel:SetSize(100, 24)
    btnCancel:SetPoint("LEFT", btnSave, "RIGHT", 8, 0)
    btnCancel:SetText(L["Cancelar"])
    btnCancel:SetScript("OnClick", function() editing = nil; Refresh() end)
    Tip(btnRaid, L["Banda"], L["Elige la banda del diario de encuentros; cuenta para los jefes y el DKP cuando estáis dentro."])
    -- Los desplegables usan OnEnter para su resaltado: el tooltip se engancha sin sustituirlo
    for _, info in ipairs({
        { dropDiff, L["Dificultad"], L["Normal, Heroica o Mítica: los jefes y el DKP solo cuentan si coincide con la de la banda en el juego."] },
        { dropRosterLink, L["Roster asociado"], L["El roster en el que cuenta la asistencia de esta banda."] },
    }) do
        info[1]:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(info[2], 1, 1, 1)
            GameTooltip:AddLine(info[3], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        info[1]:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    Tip(btnSave, L["Guardar y publicar"], L["Guarda la banda y la envía a la hermandad para que se apunten."])
    Tip(btnCancel, L["Cancelar"], L["Cierra el formulario sin guardar."])

    local function LoadForm()
        formError:SetText("")
        if editing == "new" then
            formTitle:SetText(L["Nueva banda"])
            titleInput:SetText(L["Banda"])
            formFields.raidId, formFields.raidName, formFields.difficulty, formFields.rosterName = nil, nil, "heroic", nil
            sizeInput:SetText("20")
            dateInput:SetText(date("%d/%m/%Y"))
            timeInput:SetText("21:00")
            descInput:SetText("")
        else
            local ev = editing
            formTitle:SetText(L["Editar banda"])
            titleInput:SetText(ev.title or "")
            formFields.raidId, formFields.raidName, formFields.difficulty, formFields.rosterName = ev.raidId, ev.raidName, ev.difficulty, ev.rosterName
            sizeInput:SetText(tostring(ev.size or 20))
            local y, mo, d = string.match(ev.date or "", "^(%d+)-(%d+)-(%d+)$")
            dateInput:SetText(y and (d .. "/" .. mo .. "/" .. y) or "")
            timeInput:SetText(ev.time or "")
            descInput:SetText(ev.description or "")
        end
        btnRaid:SetText(formFields.raidName or L["Sin banda concreta"])
        dropDiff:SetText(L[RAID_DIFFICULTY_LABELS[formFields.difficulty]])
        dropRosterLink:SetText(formFields.rosterName or L["Ninguno"])
    end

    -- ---------------------------------------------------------------------
    -- Vista de grupos
    -- ---------------------------------------------------------------------
    local groupsPanel = CreateFrame("Frame", nil, view)
    groupsPanel:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 6, 0)
    groupsPanel:SetSize(644, 470)
    groupsPanel:Hide()

    local selectedPlayer = nil   -- jugador elegido para colocarlo en un grupo

    local unassignedBox = CreateBackdropBox(groupsPanel, 170, 430, "TOPLEFT", groupsPanel, "TOPLEFT", 0, 0)
    local unassignedTitle = unassignedBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    unassignedTitle:SetPoint("TOPLEFT", unassignedBox, "TOPLEFT", 10, -10)

    local unassignedButtons = {}
    local function AcquireUnassigned(index)
        local btn = unassignedButtons[index]
        if btn then return btn end
        btn = CreateFrame("Button", nil, unassignedBox)
        btn:SetSize(154, 20)
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(1, 0.82, 0, 0.3)
        btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.highlight:SetAllPoints()
        btn.highlight:SetColorTexture(1, 1, 1, 0.08)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.text:SetPoint("LEFT", btn, "LEFT", 4, 0)
        btn.text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
        btn.text:SetJustifyH("LEFT")
        btn.text:SetWordWrap(false)
        btn:SetScript("OnClick", function(self)
            if not IsOfficerProfile() then return end
            selectedPlayer = (selectedPlayer == self.playerName) and nil or self.playerName
            Refresh()
        end)
        unassignedButtons[index] = btn
        return btn
    end

    -- 8 grupos en 4 columnas y 2 filas, 5 huecos cada uno
    local groupBoxes = {}
    for g = 1, 8 do
        local col, row = (g - 1) % 4, math.floor((g - 1) / 4)
        local box = CreateBackdropBox(groupsPanel, 114, 150, "TOPLEFT", unassignedBox, "TOPRIGHT", 6 + col * 116, -row * 156)
        box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
        box.slots = {}
        for s = 1, 5 do
            local slot = CreateFrame("Button", nil, box)
            slot:SetSize(100, 20)
            slot:SetPoint("TOPLEFT", box, "TOPLEFT", 7, -28 - (s - 1) * 23)
            slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            slot.bg = slot:CreateTexture(nil, "BACKGROUND")
            slot.bg:SetAllPoints()
            slot.bg:SetColorTexture(1, 1, 1, 0.06)
            slot.highlight = slot:CreateTexture(nil, "HIGHLIGHT")
            slot.highlight:SetAllPoints()
            slot.highlight:SetColorTexture(1, 1, 1, 0.1)
            slot.text = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            slot.text:SetPoint("LEFT", slot, "LEFT", 3, 0)
            slot.text:SetPoint("RIGHT", slot, "RIGHT", -3, 0)
            slot.text:SetJustifyH("LEFT")
            slot.text:SetWordWrap(false)
            slot.group = g
            -- Clic: coloca aquí al jugador elegido (o elige al que ocupa el hueco).
            -- Clic derecho: lo saca del grupo.
            slot:SetScript("OnClick", function(self, button)
                local event = SelectedEvent()
                if not event or not IsOfficerProfile() then return end
                if button == "RightButton" then
                    if self.playerName then E.SetGroup(event, self.playerName, nil) end
                elseif selectedPlayer then
                    if self.playerName then E.SetGroup(event, self.playerName, nil) end
                    E.SetGroup(event, selectedPlayer, self.group)
                    selectedPlayer = nil
                elseif self.playerName then
                    selectedPlayer = self.playerName
                end
                Refresh()
            end)
            box.slots[s] = slot
        end
        groupBoxes[g] = box
    end

    local groupsHint = groupsPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    groupsHint:SetPoint("TOPLEFT", groupBoxes[5], "BOTTOMLEFT", 0, -8)
    groupsHint:SetWidth(466)
    groupsHint:SetJustifyH("LEFT")

    local groupsFooter = CreateFrame("Frame", nil, groupsPanel)
    groupsFooter:SetSize(644, 24)
    groupsFooter:SetPoint("BOTTOMLEFT", groupsPanel, "BOTTOMLEFT", 0, 4)
    local function FooterButton(text, width, anchor, onClick)
        local btn = CreateFrame("Button", nil, groupsFooter, "UIPanelButtonTemplate")
        btn:SetSize(width, 22)
        if anchor then btn:SetPoint("LEFT", anchor, "RIGHT", 6, 0) else btn:SetPoint("LEFT", groupsFooter, "LEFT", 0, 0) end
        btn:SetText(text)
        btn:SetScript("OnClick", onClick)
        return btn
    end
    local btnAuto = FooterButton(L["Repartir automáticamente"], 180, nil, function() E.AutoGroups(SelectedEvent()); Refresh() end)
    local btnClearGroups = FooterButton(L["Vaciar grupos"], 110, btnAuto, function() E.ClearGroups(SelectedEvent()); Refresh() end)
    local btnPublishGroups = FooterButton(L["Publicar grupos"], 120, btnClearGroups, function()
        local ev = SelectedEvent()
        if ev then E.Publish(ev); PrintGC(L["Grupos publicados en la hermandad."]) end
    end)
    -- Aplica los grupos en la banda actual (hay que ser líder o ayudante)
    local btnApply = FooterButton(L["Aplicar en la banda"], 140, btnPublishGroups, function()
        local event = SelectedEvent()
        if not event or not IsInRaid() then
            PrintGC(L["Tienes que estar en una banda para aplicar los grupos."])
            return
        end
        if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
            PrintGC(L["Necesitas ser líder o ayudante de la banda."])
            return
        end
        local moved = 0
        for i = 1, GetNumGroupMembers() do
            local name, _, subgroup = GetRaidRosterInfo(i)
            local full = name and addonTable.Profiles.NormalizeName(name)
            local target = full and event.groups[full]
            if target and target ~= subgroup then
                SetRaidSubgroup(i, target)
                moved = moved + 1
            end
        end
        PrintGC(L["Moviendo a |cFFFFD100"] .. moved .. L["|r jugadores. Si algún grupo estaba lleno, pulsa de nuevo cuando se libere."])
    end)
    local officerGroupButtons = { btnAuto, btnClearGroups, btnPublishGroups, btnApply }
    Tip(btnAuto, L["Repartir automáticamente"], L["Coloca a los apuntados en los grupos, con tanques y sanadores repartidos."])
    Tip(btnClearGroups, L["Vaciar grupos"], L["Deja a todos sin grupo."])
    Tip(btnPublishGroups, L["Publicar grupos"], L["Envía los grupos a la hermandad para que todos los vean."])
    Tip(btnApply, L["Aplicar en la banda"], L["Mueve a los jugadores de tu banda a su grupo (tienes que ser líder o ayudante)."])

    local function RefreshGroups(event)
        selectedPlayer = (event and selectedPlayer and event.signups[selectedPlayer]) and selectedPlayer or nil
        local isOfficer = IsOfficerProfile()
        for _, btn in ipairs(officerGroupButtons) do btn:SetShown(isOfficer) end
        groupsHint:SetText(isOfficer and L["Clic en un jugador de la izquierda y luego en un hueco para colocarlo. Clic en un hueco ocupado para moverlo; clic derecho para sacarlo."]
            or L["Grupos publicados por los oficiales para esta banda."])

        local members = {}
        for g = 1, 8 do members[g] = {} end
        local unassigned = {}
        if event then
            for name, s in pairs(event.signups) do
                if s.status == "signed" or s.status == "late" then
                    local g = event.groups and event.groups[name]
                    if g and #members[g] < 5 then table.insert(members[g], name) else table.insert(unassigned, name) end
                end
            end
        end
        table.sort(unassigned)

        for _, btn in ipairs(unassignedButtons) do btn:Hide() end
        unassignedTitle:SetText(L["Sin grupo ("] .. #unassigned .. ")")
        for i, name in ipairs(unassigned) do
            if i > 19 then break end
            local btn = AcquireUnassigned(i)
            btn:SetPoint("TOPLEFT", unassignedBox, "TOPLEFT", 8, -32 - (i - 1) * 21)
            btn.playerName = name
            local s = event.signups[name]
            btn.text:SetText(RoleIcon(s.role, 12) .. " " .. SignupName(name))
            btn.bg:SetShown(selectedPlayer == name)
            btn:Show()
        end

        local numGroups = event and math.max(1, math.ceil((event.size or 20) / 5)) or 4
        for g = 1, 8 do
            local box = groupBoxes[g]
            box:SetAlpha(g <= numGroups and 1 or 0.45)
            box.title:SetText(L["Grupo "] .. g .. " |cFF808080(" .. #members[g] .. "/5)|r")
            table.sort(members[g])
            for s = 1, 5 do
                local slot = box.slots[s]
                local name = members[g][s]
                slot.playerName = name
                if name then
                    local signup = event.signups[name]
                    slot.text:SetText(RoleIcon(signup and signup.role, 12) .. " " .. SignupName(name))
                    if selectedPlayer == name then slot.bg:SetColorTexture(1, 0.82, 0, 0.3) else slot.bg:SetColorTexture(1, 1, 1, 0.06) end
                else
                    slot.text:SetText(L["|cFF555555vacío|r"])
                    slot.bg:SetColorTexture(1, 1, 1, 0.03)
                end
            end
        end
    end

    -- ---------------------------------------------------------------------
    -- Asistencia: hoja para pasar lista de la banda seleccionada (oficiales)
    -- ---------------------------------------------------------------------
    local attPanel = CreateBackdropBox(view, 644, 470, "TOPLEFT", listBox, "TOPRIGHT", 6, 0)
    attPanel:Hide()

    local attTitle = attPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    attTitle:SetPoint("TOPLEFT", attPanel, "TOPLEFT", 10, -10)
    attTitle:SetWidth(620)
    attTitle:SetJustifyH("LEFT")
    attTitle:SetWordWrap(false)

    local function AttButton(text, width, anchor, onClick)
        local btn = CreateFrame("Button", nil, attPanel, "UIPanelButtonTemplate")
        btn:SetSize(width, 22)
        if anchor then btn:SetPoint("LEFT", anchor, "RIGHT", 6, 0) else btn:SetPoint("TOPLEFT", attTitle, "BOTTOMLEFT", 0, -8) end
        btn:SetText(text)
        btn:SetScript("OnClick", onClick)
        return btn
    end
    local btnFromGroup = AttButton(L["Tomar del grupo actual"], 170, nil, function()
        local event = SelectedEvent()
        if not event then return end
        local present = E.TakeAttendanceFromGroup(event)
        PrintGC(L["Asistencia tomada del grupo: |cFFFFD100"] .. present .. L["|r integrantes presentes."])
    end)
    local btnSignedPresent = AttButton(L["Apuntados presentes"], 150, btnFromGroup, function() E.MarkSignedPresent(SelectedEvent()) end)
    Tip(AttButton(L["Limpiar marcas"], 120, btnSignedPresent, function() E.ClearAttendance(SelectedEvent()) end),
        L["Limpiar marcas"], L["Quita todas las marcas de asistencia de esta banda."])
    Tip(btnFromGroup, L["Tomar del grupo actual"], L["Marca como presentes a los que están ahora en tu grupo o banda."])
    Tip(btnSignedPresent, L["Apuntados presentes"], L["Marca como presentes a todos los apuntados."])

    local ATT_COLS = { name = 6, answer = 150, status = 246, statusWidth = 62, history = 500 }
    local attHeader = CreateFrame("Frame", nil, attPanel)
    attHeader:SetSize(610, 16)
    attHeader:SetPoint("TOPLEFT", btnFromGroup, "BOTTOMLEFT", 0, -10)
    for _, h in ipairs({ { L["Jugador"], ATT_COLS.name }, { L["Respuesta"], ATT_COLS.answer },
                         { L["Marca"], ATT_COLS.status }, { L["Historial"], ATT_COLS.history } }) do
        local fs = attHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", attHeader, "LEFT", h[2], 0)
        fs:SetText(h[1])
    end

    local attScroll = CreateFrame("ScrollFrame", "GC_RaidAttendanceScroll", attPanel, "UIPanelScrollFrameTemplate")
    attScroll:SetPoint("TOPLEFT", attHeader, "BOTTOMLEFT", 0, -4)
    attScroll:SetPoint("BOTTOMRIGHT", attPanel, "BOTTOMRIGHT", -26, 46)
    local attChild = CreateFrame("Frame")
    attChild:SetSize(600, 1)
    attScroll:SetScrollChild(attChild)

    local attSummary = attPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    attSummary:SetPoint("BOTTOMLEFT", attPanel, "BOTTOMLEFT", 10, 26)
    local attHint = attPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    attHint:SetPoint("BOTTOMLEFT", attPanel, "BOTTOMLEFT", 10, 9)
    attHint:SetWidth(620)
    attHint:SetJustifyH("LEFT")
    attHint:SetText(L["Aparecen los inscritos y los integrantes del roster asociado. La asistencia se envía sola a la hermandad y cuenta en Roster, Mis rosters y Warning."])

    local attEmpty = attPanel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    attEmpty:SetPoint("CENTER", attPanel, "CENTER", 0, 0)
    attEmpty:SetText(L["Selecciona una banda para pasar lista."])

    local attRows = {}
    local function AcquireAttRow(index)
        local row = attRows[index]
        if row then return row end
        row = CreateFrame("Frame", nil, attChild)
        row:SetSize(600, 20)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.05)
        row.nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.nameFs:SetPoint("LEFT", row, "LEFT", ATT_COLS.name, 0)
        row.nameFs:SetWidth(140)
        row.nameFs:SetJustifyH("LEFT")
        row.nameFs:SetWordWrap(false)
        row.answerFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.answerFs:SetPoint("LEFT", row, "LEFT", ATT_COLS.answer, 0)
        row.answerFs:SetWidth(92)
        row.answerFs:SetJustifyH("LEFT")
        row.answerFs:SetWordWrap(false)
        row.historyFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.historyFs:SetPoint("LEFT", row, "LEFT", ATT_COLS.history, 0)
        row.statusButtons = {}
        for i, status in ipairs(E.ATTENDANCE) do
            local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            btn:SetSize(ATT_COLS.statusWidth - 2, 18)
            btn:SetPoint("LEFT", row, "LEFT", ATT_COLS.status + (i - 1) * ATT_COLS.statusWidth, 0)
            btn.status = status
            Tip(btn, L[E.ATTENDANCE_LABELS[status]], ({ present = L["Estuvo en la banda."], late = L["Llegó tarde."],
                absent = L["No vino y no avisó."], excused = L["No vino, pero avisó (falta justificada)."] })[status] or "")
            btn:SetScript("OnClick", function(self)
                local event = SelectedEvent()
                if event and row.fullName then E.SetAttendance(event, row.fullName, self.status) end
            end)
            row.statusButtons[status] = btn
        end
        attRows[index] = row
        return row
    end

    local SLOT_ANSWER = { tank = L["Titular"], healer = L["Titular"], dps = L["Titular"], bench = L["Suplente"] }
    local function AnswerText(entry)
        local s = entry.signup
        if s then return "|cFF" .. E.STATUS_COLORS[s.status] .. L[E.STATUS_LABELS[s.status]] .. "|r" end
        return "|cFF808080" .. (entry.slot and SLOT_ANSWER[entry.slot] or "-") .. " · " .. L["sin responder"] .. "|r"
    end

    local function RefreshAttendance(event)
        for _, row in ipairs(attRows) do row:Hide() end
        local hasEvent = event ~= nil
        for _, widget in ipairs({ attTitle, attHeader, attScroll, attSummary }) do widget:SetShown(hasEvent) end
        attEmpty:SetShown(not hasEvent)
        if not hasEvent then return end

        attTitle:SetText(L["Asistencia · "] .. RaidEventDateText(event, true) .. L[" · "] .. event.title
            .. (event.rosterName and ("  |cFF808080(" .. event.rosterName .. ")|r") or ""))
        local marks = E.GetMarks(event)
        local list = E.GetAttendanceList(event)
        for i, entry in ipairs(list) do
            local row = AcquireAttRow(i)
            row:SetPoint("TOPLEFT", attChild, "TOPLEFT", 0, -(i - 1) * 21)
            row.bg:SetShown(i % 2 == 0)
            row.fullName = entry.name
            local role = (entry.signup and entry.signup.role) or entry.slot
            row.nameFs:SetText(((role and role ~= "bench") and (RoleIcon(role, 12) .. " ") or "") .. SignupName(entry.name))
            row.answerFs:SetText(AnswerText(entry))
            local stats = E.GetAttendanceStats(event.rosterName, entry.name)
            if stats.percent then
                local color = stats.percent >= 90 and "00FF00" or (stats.percent >= 70 and "FFD100" or "FF3333")
                row.historyFs:SetText("|cFF" .. color .. stats.percent .. "%|r |cFF808080(" .. (stats.present + stats.late) .. "/" .. stats.counted .. ")|r")
            else
                row.historyFs:SetText("|cFF808080-|r")
            end
            local current = marks[entry.name]
            for status, btn in pairs(row.statusButtons) do
                local label = L[E.ATTENDANCE_LABELS[status]]
                btn:SetText(current == status and ("|cFF" .. E.ATTENDANCE_COLORS[status] .. label .. "|r") or ("|cFF808080" .. label .. "|r"))
            end
            row:Show()
        end
        attChild:SetHeight(math.max(1, #list * 21))

        local counts = E.GetAttendanceCounts(event)
        attSummary:SetText(string.format(L["|cFF00FF00Presentes %d|r   |cFFFFD100Tarde %d|r   |cFFFF3333Ausentes %d|r   |cFF66B3FFJustificadas %d|r   |cFF808080Sin marcar %d|r"],
            counts.present, counts.late, counts.absent, counts.excused,
            math.max(0, #list - counts.present - counts.late - counts.absent - counts.excused)))
    end

    -- ---------------------------------------------------------------------
    -- Refresco general
    -- ---------------------------------------------------------------------
    -- Al elegir una banda, la vista previa muestra su roster publicado (o que aún no lo está).
    -- Solo al cambiar de banda o al recibir un roster, para no pisar otras vistas previas.
    local previewEventId = nil
    view:HookScript("OnHide", function() previewEventId = nil end)
    R.SetReceivedListener(function()
        local ev = previewEventId and E.Get(previewEventId)
        if ev and activeTab == "Raid" and view:IsShown() then ShowRosterPreview(ev) end
    end)

    local function RefreshPlanning(event)
        local isOfficer = IsOfficerProfile()
        btnRosterPreview:Hide()   -- el roster publicado se ve solo en la vista previa
        if event and event.id ~= previewEventId and activeTab == "Raid" then
            previewEventId = event.id
            -- Un instante después: al cambiar de pestaña, SwitchTab pone el texto por defecto
            local id = event.id
            C_Timer.After(0, function()
                local ev = E.Get(id)
                if ev and previewEventId == id and activeTab == "Raid" then ShowRosterPreview(ev) end
            end)
        elseif not event then
            previewEventId = nil
        end
        officerBar:SetShown(isOfficer and event ~= nil)
        footer:SetShown(event ~= nil)
        for _, btn in ipairs({ btnInvite, btnRepublish }) do btn:SetShown(isOfficer) end

        local hasEvent = event ~= nil
        for _, widget in ipairs({ evTitle, evInfo, evDesc, signBar, countsText, tankCol, healerCol, dpsCol, otherText }) do widget:SetShown(hasEvent) end
        emptyDetail:SetShown(not hasEvent)
        emptyDetail:SetText(isOfficer and L["No hay bandas programadas. Crea una con el botón Nueva."]
            or L["No hay bandas programadas. Cuando un oficial publique una, aparecerá aquí para que te apuntes."])
        if not hasEvent then return end

        evTitle:SetText(event.title)
        evInfo:SetText("|cFFFFD100" .. RaidEventDateText(event, true) .. L["|r   ·   "]
            .. (event.raidName and (event.raidName .. " ") or "") .. L[RAID_DIFFICULTY_LABELS[event.difficulty] or ""] .. " " .. event.size
            .. L["   ·   |cFF808080por "] .. (event.createdBy or "?") .. "|r")
        evDesc:SetText(event.description ~= "" and event.description or L["|cFF808080Sin descripción.|r"])

        -- Solo los roles que puede llevar mi clase
        local meKey = addonTable.Profiles and addonTable.Profiles.GetMyFullName()
        for _, b in ipairs(signButtons) do
            if b.role then b:SetEnabled(not addonTable.CanRole or addonTable.CanRole(meKey, b.role)) end
        end
        local mine = E.GetMySignup(event)
        if mine then
            mySignupText:SetText("|cFF" .. E.STATUS_COLORS[mine.status] .. L[E.STATUS_LABELS[mine.status]] .. "|r"
                .. (mine.role and (L[" como "] .. RoleIcon(mine.role, 12)) or "") .. ((mine.spec and mine.spec ~= "") and (" " .. mine.spec) or ""))
        else
            mySignupText:SetText(L["|cFFFF7F00Aún no has respondido|r"])
        end

        local counts = E.CountSignups(event)
        countsText:SetText(L["Apuntados: |cFF00FF00"] .. counts.total .. "|r/" .. event.size
            .. "   " .. RoleIcon("tank", 14) .. " " .. counts.tank .. "   " .. RoleIcon("healer", 14) .. " " .. counts.healer
            .. "   " .. RoleIcon("dps", 14) .. " " .. counts.dps
            .. L["   ·   Tarde "] .. counts.late .. L["   ·   Ausentes "] .. counts.absent)

        local byRole = E.GetSignupsByRole(event)
        local function FillColumn(col, label, role, list)
            col:SetHeader(RoleIcon(role, 16) .. " " .. label .. " |cFFFFFFFF(" .. #list .. ")|r")
            -- Caben 12 líneas por columna de nombres (dos en DPS); el resto se resume
            local capacity = 12 * col.columns
            local lines = {}
            local shown = #list > capacity and capacity - 1 or #list
            for i = 1, shown do table.insert(lines, SignupName(list[i].name, list[i].signup)) end
            if #list > shown then
                table.insert(lines, L["|cFF808080y "] .. (#list - shown) .. L[" más (ver Vista de grupos)|r"])
            end
            if #lines == 0 then
                col:SetText(L["|cFF808080Nadie todavía|r"])
            elseif col.columns > 1 then
                col:SetText(table.concat(lines, "\n", 1, math.min(12, #lines)), #lines > 12 and table.concat(lines, "\n", 13) or "")
            else
                col:SetText(table.concat(lines, "\n"))
            end
        end
        FillColumn(tankCol, L["Tanques"], "tank", byRole.tank)
        FillColumn(healerCol, L["Sanadores"], "healer", byRole.healer)
        FillColumn(dpsCol, "DPS", "dps", byRole.dps)

        local otherLines = {}
        for _, status in ipairs({ "tentative", "bench", "absent" }) do
            local list = byRole.other[status] or {}
            if #list > 0 then
                local names = {}
                for _, entry in ipairs(list) do table.insert(names, SignupName(entry.name, entry.signup)) end
                table.insert(otherLines, "|cFF" .. E.STATUS_COLORS[status] .. L[E.STATUS_LABELS[status]] .. " (" .. #list .. "):|r " .. table.concat(names, ", "))
            end
        end
        otherText:SetText(table.concat(otherLines, "\n"))
    end

    -- ---------------------------------------------------------------------
    -- Historial de bandas (todos): jefes que murieron y asistencia de cada banda pasada
    -- ---------------------------------------------------------------------
    local HISTORY_PAGE_SIZE = 8
    local historyPage = 1
    local btnPrevPage = CreateFrame("Button", nil, listBox, "UIPanelButtonTemplate")
    btnPrevPage:SetSize(50, 20)
    btnPrevPage:SetPoint("BOTTOMLEFT", listBox, "BOTTOMLEFT", 8, 8)
    btnPrevPage:SetText("<")
    btnPrevPage:SetScript("OnClick", function() historyPage = math.max(1, historyPage - 1); selectedEventId = nil; Refresh() end)
    local btnNextPage = CreateFrame("Button", nil, listBox, "UIPanelButtonTemplate")
    btnNextPage:SetSize(50, 20)
    btnNextPage:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -8, 8)
    btnNextPage:SetText(">")
    btnNextPage:SetScript("OnClick", function() historyPage = historyPage + 1; selectedEventId = nil; Refresh() end)
    Tip(btnPrevPage, L["Anterior"], L["Página anterior del historial."])
    Tip(btnNextPage, L["Siguiente"], L["Página siguiente del historial."])
    local pageText = listBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pageText:SetPoint("BOTTOM", listBox, "BOTTOM", 0, 13)
    for _, w in ipairs({ btnPrevPage, btnNextPage, pageText }) do w:Hide() end

    local histPanel = CreateBackdropBox(view, 644, 470, "TOPLEFT", listBox, "TOPRIGHT", 6, 0)
    histPanel:Hide()
    local histTitle = histPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    histTitle:SetPoint("TOPLEFT", histPanel, "TOPLEFT", 14, -12)
    histTitle:SetWidth(616)
    histTitle:SetJustifyH("LEFT")
    histTitle:SetWordWrap(false)
    local histInfo = histPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    histInfo:SetPoint("TOPLEFT", histTitle, "BOTTOMLEFT", 0, -6)
    histInfo:SetWidth(616)
    histInfo:SetJustifyH("LEFT")
    histInfo:SetWordWrap(false)
    local histSummary = histPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    histSummary:SetPoint("TOPLEFT", histInfo, "BOTTOMLEFT", 0, -6)
    histSummary:SetWidth(616)
    histSummary:SetJustifyH("LEFT")
    histSummary:SetWordWrap(false)

    local histBossBox = CreateColoredPanel(histPanel, L["Jefes"], PANEL_COLORS.blue, 300, 380)
    histBossBox:SetPoint("TOPLEFT", histPanel, "TOPLEFT", 10, -80)
    local histAttBox = CreateColoredPanel(histPanel, L["Asistencia"], PANEL_COLORS.blue, 318, 380)
    histAttBox:SetPoint("TOPLEFT", histBossBox, "TOPRIGHT", 6, 0)
    local histAttScroll = CreateFrame("ScrollFrame", nil, histAttBox, "UIPanelScrollFrameTemplate")
    histAttScroll:SetPoint("TOPLEFT", histAttBox, "TOPLEFT", 8, -28)
    histAttScroll:SetPoint("BOTTOMRIGHT", histAttBox, "BOTTOMRIGHT", -28, 8)
    local histAttChild = CreateFrame("Frame")
    histAttChild:SetSize(280, 1)
    histAttScroll:SetScrollChild(histAttChild)
    local histEmpty = histPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    histEmpty:SetPoint("CENTER")
    histEmpty:SetWidth(560)
    histEmpty:SetText(L["Aquí aparecen las bandas programadas en Raid que ya se jugaron, con los jefes que murieron y la asistencia."])

    local bossLines, attLines = {}, {}
    local function HistLine(lines, parent, index, x, y, width)
        local fs = lines[index]
        if not fs then
            fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetWidth(width)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            lines[index] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        fs:Show()
        return fs
    end

    local ATT_ORDER = { present = 1, late = 2, excused = 3, absent = 4 }
    local function RefreshHistory()
        local history = E.GetHistory()
        local pages = math.max(1, math.ceil(#history / HISTORY_PAGE_SIZE))
        historyPage = math.min(historyPage, pages)
        local first = (historyPage - 1) * HISTORY_PAGE_SIZE
        listTitle:SetText(L["Bandas anteriores"])
        local selected = nil
        for i = first + 1, math.min(#history, first + HISTORY_PAGE_SIZE) do
            if history[i].id == selectedEventId then selected = history[i] end
        end
        if not selected then
            selected = history[first + 1]
            selectedEventId = selected and selected.id or nil
        end
        for _, btn in ipairs(eventButtons) do btn:Hide() end
        for i = 1, HISTORY_PAGE_SIZE do
            local entry = history[first + i]
            if not entry then break end
            local btn = AcquireEventButton(i)
            btn:SetPoint("TOPLEFT", listBox, "TOPLEFT", 8, -34 - (i - 1) * 48)
            btn.eventId = entry.id
            btn.bg:SetColorTexture(1, 0.82, 0, entry.id == selectedEventId and 0.22 or 0.05)
            btn.titleFs:SetText(entry.title)
            local bosses, killed = E.GetHistoryBosses(entry)
            btn.infoFs:SetText("|cFFBFBFBF" .. RaidEventDateText(entry) .. "|r   " .. L["Jefes: "] .. "|cFFFFD100" .. killed
                .. (#bosses > 0 and ("/" .. #bosses) or "") .. "|r")
            btn:Show()
        end
        listEmpty:SetShown(#history == 0)
        listEmpty:SetText(L["Todavía no hay bandas anteriores."])
        for _, w in ipairs({ btnPrevPage, btnNextPage, pageText }) do w:SetShown(pages > 1) end
        btnPrevPage:SetEnabled(historyPage > 1)
        btnNextPage:SetEnabled(historyPage < pages)
        pageText:SetText(historyPage .. "/" .. pages)

        -- Detalle de la banda elegida
        for _, fs in ipairs(bossLines) do fs:Hide() end
        for _, fs in ipairs(attLines) do fs:Hide() end
        histEmpty:SetShown(selected == nil)
        histBossBox:SetShown(selected ~= nil)
        histAttBox:SetShown(selected ~= nil)
        if not selected then
            histTitle:SetText(L["Historial de bandas"])
            histInfo:SetText("")
            histSummary:SetText("")
            return
        end
        histTitle:SetText(selected.title)
        local info = { RaidEventDateText(selected, true) }
        if selected.raidName then table.insert(info, selected.raidName) end
        if RAID_DIFFICULTY_LABELS[selected.difficulty or ""] then table.insert(info, L[RAID_DIFFICULTY_LABELS[selected.difficulty]]) end
        if selected.rosterName then table.insert(info, L["Roster: "] .. selected.rosterName) end
        histInfo:SetText("|cFFBFBFBF" .. table.concat(info, "  ·  ") .. "|r")

        local bosses, killed = E.GetHistoryBosses(selected)
        for i, boss in ipairs(bosses) do
            local fs = HistLine(bossLines, histBossBox, i, 14, -32 - (i - 1) * 18, 272)
            if boss.at then
                fs:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t |cFFFFFFFF" .. boss.name .. "|r  |cFF808080" .. date("%H:%M", boss.at) .. "|r")
            else
                fs:SetText("|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t |cFF808080" .. boss.name .. "|r")
            end
        end
        if #bosses == 0 then
            HistLine(bossLines, histBossBox, 1, 14, -32, 272):SetText("|cFF808080" .. L["No se registró ningún jefe."] .. "|r")
        end

        local names = {}
        local counts = { present = 0, late = 0, absent = 0, excused = 0 }
        for name, status in pairs(selected.marks) do
            table.insert(names, { name = name, status = status })
            if counts[status] then counts[status] = counts[status] + 1 end
        end
        table.sort(names, function(a, b)
            local oa, ob = ATT_ORDER[a.status] or 9, ATT_ORDER[b.status] or 9
            if oa ~= ob then return oa < ob end
            return a.name < b.name
        end)
        for i, entry in ipairs(names) do
            local fs = HistLine(attLines, histAttChild, i, 4, -(i - 1) * 16, 270)
            local m = GuildControlDB.members[entry.name]
            local short = string.match(entry.name, "^([^-]+)") or entry.name
            fs:SetText("|cFF" .. addonTable.GetClassColorHex(m and m.class) .. short .. "|r  |cFF"
                .. (E.ATTENDANCE_COLORS[entry.status] or "FFFFFF") .. L[E.ATTENDANCE_LABELS[entry.status] or entry.status] .. "|r")
        end
        histAttChild:SetHeight(math.max(1, #names * 16))
        if #names == 0 then
            HistLine(attLines, histAttChild, 1, 4, 0, 270):SetText("|cFF808080" .. L["No se pasó lista en esta banda."] .. "|r")
        end
        local summary = L["Jefes: "] .. "|cFFFFD100" .. killed .. (#bosses > 0 and ("/" .. #bosses) or "") .. "|r"
        if #names > 0 then
            summary = summary .. "     " .. L["Presentes: "] .. "|cFF00FF00" .. counts.present .. "|r   " .. L["Tarde: "] .. "|cFFFFD100" .. counts.late
                .. "|r   " .. L["Ausentes: "] .. "|cFFFF3333" .. counts.absent .. "|r   " .. L["Justificados: "] .. "|cFF66B3FF" .. counts.excused .. "|r"
        end
        histSummary:SetText(summary)
    end

    Refresh = function()
        if not view:IsShown() then return end
        local isOfficer = IsOfficerProfile()
        btnNew:SetShown(isOfficer)
        btnAttendance:SetShown(isOfficer)
        if mode == "attendance" and not isOfficer then mode = "planning" end
        btnPlanning:SetEnabled(mode ~= "planning")
        btnGroups:SetEnabled(mode ~= "groups")
        btnAttendance:SetEnabled(mode ~= "attendance")
        btnHistory:SetEnabled(mode ~= "history")
        local isHistory = mode == "history"
        histPanel:SetShown(isHistory)
        if not isHistory then for _, w in ipairs({ btnPrevPage, btnNextPage, pageText }) do w:Hide() end end
        if isHistory then
            btnNew:Hide()
            detail:Hide(); groupsPanel:Hide(); attPanel:Hide(); form:Hide()
            form.loadedFor = nil
            RefreshHistory()
            return
        end

        -- Lista de bandas: las próximas o, al pasar lista, también las de los últimos 14 días
        local isAttendance = mode == "attendance"
        local events = isAttendance and E.GetRecent() or E.GetUpcoming()
        listTitle:SetText(isAttendance and L["Bandas recientes"] or L["Próximas bandas"])
        local inList = false
        for _, ev in ipairs(events) do if ev.id == selectedEventId then inList = true end end
        if not inList then
            selectedEventId = events[1] and events[1].id or nil
            if isAttendance then
                -- Por defecto, la última banda que ya empezó
                local today = date("%Y-%m-%d")
                for _, ev in ipairs(events) do
                    if ev.date <= today then selectedEventId = ev.id break end
                end
            end
        end
        for _, btn in ipairs(eventButtons) do btn:Hide() end
        for i, ev in ipairs(events) do
            if i > 9 then break end
            local btn = AcquireEventButton(i)
            btn:SetPoint("TOPLEFT", listBox, "TOPLEFT", 8, -34 - (i - 1) * 48)
            btn.eventId = ev.id
            btn.bg:SetColorTexture(1, 0.82, 0, ev.id == selectedEventId and 0.22 or 0.05)
            btn.titleFs:SetText(ev.title)
            local counts = E.CountSignups(ev)
            local mine = E.GetMySignup(ev)
            local mark = mine and (L[" |cFF"] .. E.STATUS_COLORS[mine.status] .. L["•|r"]) or ""
            btn.infoFs:SetText("|cFFBFBFBF" .. RaidEventDateText(ev) .. "|r   |cFF00FF00" .. counts.total .. "|r/" .. ev.size .. mark)
            btn:Show()
        end
        listEmpty:SetShown(#events == 0)
        listEmpty:SetText(isOfficer and L["Sin bandas. Pulsa Nueva para crear una."] or L["Sin bandas publicadas todavía."])

        local event = SelectedEvent()
        local showForm = mode == "planning" and editing ~= nil and isOfficer
        detail:SetShown(mode == "planning")
        groupsPanel:SetShown(mode == "groups")
        attPanel:SetShown(isAttendance)
        form:SetShown(showForm)
        if showForm then
            for _, widget in ipairs({ evTitle, evInfo, evDesc, signBar, countsText, tankCol, healerCol, dpsCol, otherText, officerBar, footer, emptyDetail, btnRosterPreview }) do widget:Hide() end
            if not form.loadedFor or form.loadedFor ~= editing then
                form.loadedFor = editing
                LoadForm()
            end
            return
        end
        form.loadedFor = nil
        if mode == "planning" then RefreshPlanning(event)
        elseif mode == "groups" then RefreshGroups(event)
        else RefreshAttendance(event) end
    end

    E.AddListener(function() Refresh() end)
    view:SetScript("OnShow", Refresh)
    -- Abre Raid con una banda elegida (p. ej. desde las etiquetas de rosters de Miembros)
    uiModule.OpenRaidEvent = function(eventId)
        if eventId and E.Get(eventId) then
            selectedEventId, mode, editing = eventId, "planning", nil
        end
        SwitchTab("Raid")
        Refresh()
    end
    containers.views["Raid"] = view
end

-- =========================================================================
-- 8k. VISTA FAVORITOS (CONSUME MODULES/FAVORITES.LUA Y LA LISTA DE AMIGOS DE BATTLE.NET)
-- =========================================================================
local FAV_ROW_HEIGHT = 24

-- Amigos de Battle.net: { {accountName, battleTag, isBattleTagFriend, online, character, realm, inWoW, gameAccountID, info}, ... }
local function GetBattleNetFriends()
    local list = {}
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return list end
    local total = BNGetNumFriends() or 0
    for i = 1, total do
        local ok, account = pcall(C_BattleNet.GetFriendAccountInfo, i)
        if ok and account then
            local game = account.gameAccountInfo or {}
            local inWoW = game.isOnline and game.clientProgram == BNET_CLIENT_WOW
                and (not game.wowProjectID or game.wowProjectID == WOW_PROJECT_ID)
            table.insert(list, {
                accountName = account.accountName,
                battleTag = account.battleTag,
                isBattleTagFriend = account.isBattleTagFriend,
                online = game.isOnline and true or false,
                character = inWoW and game.characterName or nil,
                realm = inWoW and game.realmName or nil,
                realmID = inWoW and game.realmID or nil,
                area = game.areaName,
                className = game.className,
                level = game.characterLevel,
                inWoW = inWoW,
                gameAccountID = game.gameAccountID,
                program = game.clientProgram,
                isAFK = account.isAFK or game.isGameAFK,
                isDND = account.isDND or game.isGameBusy,
            })
        end
    end
    return list
end

local function BuildFavoritesView(parent)
    local F = addonTable.Favorites
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()
    local Refresh

    -- Botoncito de acción de una fila
    local function RowButton(row, text, width, anchor)
        local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btn:SetSize(width, 20)
        if anchor then btn:SetPoint("RIGHT", anchor, "LEFT", -3, 0) else btn:SetPoint("RIGHT", row, "RIGHT", -2, 0) end
        btn:SetText(text)
        btn:GetFontString():SetFontObject("GameFontHighlightSmall")
        return btn
    end

    -- Caja con título, scroll y filas reutilizables
    local function ListBox(width, height, point, relativeTo, relativePoint, x, y, titleText)
        local box = CreateBackdropBox(view, width, height, point, relativeTo, relativePoint, x, y)
        box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
        box.title:SetText(titleText)
        box.scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
        box.scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -32)
        box.scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -28, 8)
        box.child = CreateFrame("Frame")
        box.child:SetSize(width - 40, 1)
        box.scroll:SetScrollChild(box.child)
        box.empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        box.empty:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -40)
        box.empty:SetWidth(width - 30)
        box.empty:SetJustifyH("LEFT")
        box.rows = {}
        return box
    end

    local function AcquireRow(box, index, buttons)
        local row = box.rows[index]
        if row then return row end
        row = CreateFrame("Frame", nil, box.child)
        row:SetSize(box.child:GetWidth(), FAV_ROW_HEIGHT)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.05)
        row.buttons = {}
        local anchor = nil
        for i = #buttons, 1, -1 do
            local b = buttons[i]
            local btn = RowButton(row, b.text, b.width, anchor)
            btn.key = b.key
            row.buttons[b.key] = btn
            anchor = btn
        end
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.text:SetPoint("RIGHT", anchor or row, anchor and "LEFT" or "RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        box.rows[index] = row
        return row
    end

    -- ---------------------------------------------------------------------
    -- Izquierda: favoritos de la hermandad
    -- ---------------------------------------------------------------------
    local favBox = ListBox(440, 500, "TOPLEFT", view, "TOPLEFT", 10, -10, L["Favoritos de la hermandad"])
    favBox.scroll:SetPoint("BOTTOMRIGHT", favBox, "BOTTOMRIGHT", -28, 64)

    local addLabel = favBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addLabel:SetPoint("BOTTOMLEFT", favBox, "BOTTOMLEFT", 14, 40)
    addLabel:SetText(L["Añadir jugador (de la hermandad o de fuera):"])
    local addInput = CreateFrame("EditBox", nil, favBox, "InputBoxTemplate")
    addInput:SetSize(220, 20)
    addInput:SetPoint("BOTTOMLEFT", favBox, "BOTTOMLEFT", 18, 14)
    addInput:SetAutoFocus(false)
    addInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local btnAdd = CreateFrame("Button", nil, favBox, "UIPanelButtonTemplate")
    btnAdd:SetSize(90, 22)
    btnAdd:SetPoint("LEFT", addInput, "RIGHT", 8, 0)
    btnAdd:SetText(L["Añadir"])
    local function AddTyped()
        local text = strtrim(addInput:GetText() or "")
        if text == "" then return end
        local wanted = string.lower(text)
        local found = nil
        for fullName in pairs(GuildControlDB.members) do
            local lower = string.lower(fullName)
            if lower == wanted or string.lower(string.match(fullName, "^([^-]+)") or "") == wanted then found = fullName break end
        end
        if not found then
            -- Fuera de la hermandad también vale: se guarda como Nombre-Reino (tu reino si no lo pones)
            local name, realm = string.match(text, "^([^%-%s]+)%-?(.*)$")
            if not name then return end
            name = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
            if realm == "" then
                realm = GetNormalizedRealmName and GetNormalizedRealmName() or string.gsub(GetRealmName() or "", "%s+", "")
            end
            found = name .. "-" .. string.gsub(realm, "%s+", "")
            PrintGC(L["Añadido a favoritos (fuera de la hermandad): "] .. found)
        end
        if not F.IsFavorite(found) then F.Toggle(found) end
        addInput:SetText("")
        addInput:ClearFocus()
        Refresh()
    end
    btnAdd:SetScript("OnClick", AddTyped)
    addInput:SetScript("OnEnterPressed", AddTyped)

    local FAV_BUTTONS = {
        { key = "whisper", text = L["Susurrar"], width = 66 },
        { key = "invite", text = L["Invitar"], width = 58 },
        { key = "remove", text = L["Quitar"], width = 54 },
    }

    -- ---------------------------------------------------------------------
    -- Derecha: amigos BattleTag (los de Real ID no se muestran)
    -- ---------------------------------------------------------------------
    local tagBox = ListBox(434, 500, "TOPLEFT", favBox, "TOPRIGHT", 6, 0, L["Amigos BattleTag"])
    local BNET_BUTTONS = {
        { key = "whisper", text = L["Susurrar"], width = 66 },
        { key = "invite", text = L["Invitar"], width = 58 },
    }

    local function BNetWhisper(friend)
        local target = friend.accountName or friend.battleTag
        if not target then return end
        if ChatFrameUtil and ChatFrameUtil.SendBNetTell then
            ChatFrameUtil.SendBNetTell(target)
        elseif ChatFrame_SendBNetTell then
            ChatFrame_SendBNetTell(target)
        end
    end

    -- Primero la invitación de Battle.net (no depende del nombre ni del reino: en Forever
    -- "Nombre Apellido-Reino" con el reino de Battle.net no lo encuentra el juego). Si no
    -- está disponible, por nombre: sin reino si es el mismo que el mío.
    local function BNetInvite(friend)
        if not friend.inWoW then return end
        if friend.gameAccountID and BNInviteFriend then
            BNInviteFriend(friend.gameAccountID)
            return
        end
        if not friend.character then return end
        local sameRealm = (friend.realmID and GetRealmID and friend.realmID == GetRealmID())
            or not friend.realm or friend.realm == ""
            or string.lower(string.gsub(friend.realm, "%s+", "")) == string.lower(string.gsub(GetRealmName() or "", "%s+", ""))
        local target = sameRealm and friend.character or (friend.character .. "-" .. string.gsub(friend.realm, "%s+", ""))
        if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(target) elseif InviteUnit then InviteUnit(target) end
    end

    local function FriendText(friend)
        local name = friend.accountName or friend.battleTag or "?"
        if not friend.online then return "|cFF808080" .. name .. "|r" end
        local status = ""
        if friend.isAFK then status = L[" |cFFFFD100(ausente)|r"] elseif friend.isDND then status = L[" |cFFFF3333(ocupado)|r"] end
        local where
        if friend.inWoW then
            where = "|cFFFFFFFF" .. (friend.character or "") .. "|r" .. (friend.level and (" |cFF808080" .. friend.level .. "|r") or "")
                .. ((friend.area and friend.area ~= "") and (" |cFF808080· " .. friend.area .. "|r") or "")
        else
            where = "|cFF808080" .. (friend.program or L["En línea"]) .. "|r"
        end
        return "|cFF82C5FF" .. name .. "|r" .. status .. "  " .. where
    end

    local function FillFriends(box, friends)
        for _, row in ipairs(box.rows) do row:Hide() end
        local online = 0
        for i, friend in ipairs(friends) do
            local row = AcquireRow(box, i, BNET_BUTTONS)
            row:SetPoint("TOPLEFT", box.child, "TOPLEFT", 0, -(i - 1) * (FAV_ROW_HEIGHT + 2))
            row.bg:SetShown(i % 2 == 0)
            row.text:SetText(FriendText(friend))
            row.buttons.whisper:SetEnabled(friend.online)
            row.buttons.whisper:SetScript("OnClick", function() BNetWhisper(friend) end)
            row.buttons.invite:SetEnabled(friend.inWoW == true)
            row.buttons.invite:SetScript("OnClick", function() BNetInvite(friend) end)
            row:Show()
            if friend.online then online = online + 1 end
        end
        box.child:SetHeight(math.max(1, #friends * (FAV_ROW_HEIGHT + 2)))
        box.empty:SetShown(#friends == 0)
        return online
    end

    Refresh = function()
        if not view:IsShown() then return end

        -- Favoritos: conectados primero
        -- Los de fuera de la hermandad: si están en tu lista de amigos se sabe si están conectados
        local function FriendInfo(fullName)
            if not (C_FriendList and C_FriendList.GetFriendInfo) then return nil end
            local short = string.match(fullName, "^([^-]+)") or fullName
            return C_FriendList.GetFriendInfo(fullName) or C_FriendList.GetFriendInfo(short)
        end
        local favorites = {}
        for _, fullName in ipairs(F.GetAll()) do
            local m = GuildControlDB.members[fullName]
            local friend = not m and FriendInfo(fullName) or nil
            table.insert(favorites, { name = fullName, data = m, friend = friend,
                                      online = (m and m.isOnline) or (friend and friend.connected) or false })
        end
        -- Conectados primero, luego los de la hermandad y al final los de fuera
        table.sort(favorites, function(a, b)
            if a.online ~= b.online then return a.online end
            local ga, gb = a.data ~= nil, b.data ~= nil
            if ga ~= gb then return ga end
            return a.name < b.name
        end)
        for _, row in ipairs(favBox.rows) do row:Hide() end
        for i, entry in ipairs(favorites) do
            local row = AcquireRow(favBox, i, FAV_BUTTONS)
            row:SetPoint("TOPLEFT", favBox.child, "TOPLEFT", 0, -(i - 1) * (FAV_ROW_HEIGHT + 2))
            row.bg:SetShown(i % 2 == 0)
            local m = entry.data
            local short = string.match(entry.name, "^([^-]+)") or entry.name
            local text
            local outside = L[" |cFF66B3FF[fuera de la hermandad]|r"]
            if not m then
                local friend = entry.friend
                if friend and friend.connected then
                    text = "|TInterface\\COMMON\\Indicator-Green:12:12|t |cFFFFFFFF"
                        .. short .. "|r" .. outside .. ((friend.area and friend.area ~= "") and (" |cFF808080· " .. friend.area .. "|r") or "")
                elseif friend then
                    text = "|TInterface\\COMMON\\Indicator-Gray:12:12|t |cFF808080" .. short .. "|r" .. outside
                else
                    text = "|cFFBFBFBF" .. short .. "|r" .. outside
                end
            elseif m.isOnline then
                text = "|TInterface\\COMMON\\Indicator-Green:12:12|t |cFF" .. addonTable.GetClassColorHex(m.class) .. short .. "|r"
                    .. ((m.zone and m.zone ~= "") and (" |cFF808080· " .. m.zone .. "|r") or "")
            else
                text = "|TInterface\\COMMON\\Indicator-Gray:12:12|t |cFF808080" .. short .. " · "
                    .. (addonTable.FormatLastOnline(m.lastOnline) or "") .. "|r"
            end
            row.text:SetText(text)
            -- Sin datos de conexión (fuera de la hermandad y no es tu amigo) se deja probar
            local online = entry.online or (not m and not entry.friend)
            row.buttons.whisper:SetEnabled(online == true)
            row.buttons.whisper:SetScript("OnClick", function() WhisperTo(entry.name) end)
            row.buttons.invite:SetEnabled(online == true)
            row.buttons.invite:SetScript("OnClick", function() InviteToGroup(entry.name) end)
            row.buttons.remove:SetScript("OnClick", function()
                F.Toggle(entry.name)
                Refresh()
                if uiModule.RefreshList then uiModule.RefreshList() end
            end)
            row:Show()
        end
        favBox.child:SetHeight(math.max(1, #favorites * (FAV_ROW_HEIGHT + 2)))
        favBox.empty:SetShown(#favorites == 0)
        favBox.empty:SetText(L["Todavía no tienes favoritos. Añádelos aquí abajo (de la hermandad o de fuera) o con clic derecho en Miembros; te avisa cuando se conectan."])

        -- Amigos BattleTag, conectados primero
        local tags = {}
        for _, friend in ipairs(GetBattleNetFriends()) do
            if friend.isBattleTagFriend then table.insert(tags, friend) end
        end
        local function ByOnline(a, b)
            if a.online ~= b.online then return a.online end
            if (a.inWoW or false) ~= (b.inWoW or false) then return a.inWoW or false end
            return tostring(a.battleTag or "") < tostring(b.battleTag or "")
        end
        table.sort(tags, ByOnline)
        local onlineTags = FillFriends(tagBox, tags)
        tagBox.title:SetText(L["Amigos BattleTag"] .. " |cFF808080(" .. onlineTags .. "/" .. #tags .. ")|r")
        tagBox.empty:SetText(L["No tienes amigos por BattleTag."])
    end

    -- La lista de amigos cambia a menudo: se refresca como mucho una vez por segundo
    local refreshPending = false
    local bnetFrame = CreateFrame("Frame")
    for _, event in ipairs({ "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "FRIENDLIST_UPDATE" }) do
        pcall(bnetFrame.RegisterEvent, bnetFrame, event)
    end
    bnetFrame:SetScript("OnEvent", function()
        if refreshPending or not view:IsShown() then return end
        refreshPending = true
        C_Timer.After(1, function()
            refreshPending = false
            Refresh()
        end)
    end)

    view:SetScript("OnShow", Refresh)
    uiModule.RefreshFavorites = Refresh
    containers.views["Favoritos"] = view
end

-- =========================================================================
-- 8l. VISTA BOTÍN (SISTEMA +1, CONSUME MODULES/LOOT.LUA)
-- =========================================================================
local function ItemIconFromLink(link)
    local itemID = tonumber(string.match(link or "", "item:(%d+)"))
    if itemID and C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok and icon then return icon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function ShowLinkTooltip(owner, link)
    if not link then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetHyperlink, GameTooltip, string.match(link, "|H(item:[^|]+)|h") or link)
    GameTooltip:Show()
end

local function ShortName(fullName)
    return fullName and (string.match(fullName, "^([^-]+)") or fullName) or "?"
end

-- Ventanita de tirada: aparece a todos los del grupo cuando se abre una tirada
local GC_LootRollFrame = nil
function uiModule.ShowLootRollPopup(key)
    local LT = addonTable.Loot
    local item = LT.GetItem(key)
    if not item then return end
    if not GC_LootRollFrame then
        local frame = CreateFrame("Frame", "GuildControlLootRollFrame", UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(340, 150)
        frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
        frame.title:SetText(L["Tirada de botín"])

        frame.itemButton = CreateFrame("Button", nil, frame)
        frame.itemButton:SetSize(300, 32)
        frame.itemButton:SetPoint("TOP", frame, "TOP", 0, -30)
        frame.itemButton.icon = frame.itemButton:CreateTexture(nil, "ARTWORK")
        frame.itemButton.icon:SetSize(30, 30)
        frame.itemButton.icon:SetPoint("LEFT", frame.itemButton, "LEFT", 0, 0)
        frame.itemButton.text = frame.itemButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.itemButton.text:SetPoint("LEFT", frame.itemButton.icon, "RIGHT", 8, 0)
        frame.itemButton.text:SetPoint("RIGHT", frame.itemButton, "RIGHT", 0, 0)
        frame.itemButton.text:SetJustifyH("LEFT")
        frame.itemButton:SetScript("OnEnter", function(self) ShowLinkTooltip(self, self.link) end)
        frame.itemButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

        frame.info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.info:SetPoint("TOP", frame.itemButton, "BOTTOM", 0, -6)
        frame.info:SetWidth(310)

        frame.buttons = {}
        local previous
        for _, kind in ipairs({ "need", "offspec", "pass" }) do
            local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            btn:SetSize(104, 24)
            if previous then btn:SetPoint("LEFT", previous, "RIGHT", 4, 0) else btn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10) end
            btn:SetText(L[LT.KINDS[kind]])
            btn:SetScript("OnClick", function()
                LT.Choose(frame.key, kind)
                frame:Hide()
            end)
            frame.buttons[kind] = btn
            previous = btn
        end
        -- Subasta DKP: cantidad, Pujar y Pasar
        frame.bidInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        frame.bidInput:SetSize(90, 20)
        frame.bidInput:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 13)
        frame.bidInput:SetAutoFocus(false)
        frame.bidInput:SetNumeric(true)
        frame.bidInput:SetMaxLetters(6)
        frame.bidButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.bidButton:SetSize(100, 24)
        frame.bidButton:SetPoint("LEFT", frame.bidInput, "RIGHT", 8, 0)
        frame.bidButton:SetText(L["Pujar"])
        local function DoBid()
            if LT.Bid(frame.key, frame.bidInput:GetText()) then frame:Hide() end
        end
        frame.bidButton:SetScript("OnClick", DoBid)
        frame.bidInput:SetScript("OnEnterPressed", DoBid)
        frame.bidInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        frame.bidPass = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.bidPass:SetSize(100, 24)
        frame.bidPass:SetPoint("LEFT", frame.bidButton, "RIGHT", 4, 0)
        frame.bidPass:SetText(L["Pasar"])
        frame.bidPass:SetScript("OnClick", function()
            LT.Choose(frame.key, "pass")
            frame:Hide()
        end)
        -- Barra para elegir la puja (de la puja mínima a tus DKP); va unida a la casilla
        local slider = CreateFrame("Slider", nil, frame, "BackdropTemplate")
        slider:SetOrientation("HORIZONTAL")
        slider:SetSize(250, 16)
        slider:SetPoint("BOTTOM", frame, "BOTTOM", 0, 46)
        slider:SetHitRectInsets(0, 0, -6, -6)
        slider:SetBackdrop({
            bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
            tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 },
        })
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        slider:SetValueStep(1)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        slider.low = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        slider.low:SetPoint("RIGHT", slider, "LEFT", -6, 0)
        slider.high = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        slider.high:SetPoint("LEFT", slider, "RIGHT", 6, 0)
        slider:SetScript("OnValueChanged", function(self, value)
            if self.updating then return end
            frame.bidInput:SetText(tostring(math.floor(value + 0.5)))
        end)
        frame.bidInput:SetScript("OnTextChanged", function(self, userInput)
            local value = tonumber(self:GetText())
            if not userInput or not value then return end
            slider.updating = true
            slider:SetValue(value)
            slider.updating = false
        end)
        frame.bidSlider = slider
        GC_LootRollFrame = frame
        -- Se cierra sola cuando la tirada termina
        LT.AddListener(function()
            local current = frame.key and LT.GetItem(frame.key)
            if frame:IsShown() and (not current or current.state ~= "rolling" or LT.GetMyChoice(frame.key)) then frame:Hide() end
        end)
    end
    local frame = GC_LootRollFrame
    local me = addonTable.Profiles.GetMyFullName()
    local link = LT.DisplayLink(item.link)
    frame.key = key
    frame.itemButton.link = link
    frame.itemButton.icon:SetTexture(ItemIconFromLink(link))
    frame.itemButton.text:SetText(link)
    local wins = LT.GetSessionWins(me)
    local dkp = LT.IsDkp()
    local fixed = dkp and LT.IsFixed()
    local auction = dkp and not fixed
    for _, btn in pairs(frame.buttons) do btn:SetShown(not auction); btn:SetEnabled(true) end
    frame.bidInput:SetShown(auction)
    frame.bidButton:SetShown(auction)
    frame.bidPass:SetShown(auction)
    frame.bidSlider:SetShown(auction)
    frame:SetHeight(auction and 180 or 150)
    frame.title:SetText(fixed and L["Botín DKP"] or (auction and L["Subasta DKP"] or L["Tirada de botín"]))
    local winsText = wins > 0 and (L["   |cFFFF7F00Ya ganaste "] .. wins .. L[" objeto(s) en esta banda|r"]) or ""
    if fixed then
        -- Precio fijo: Main-spec paga el precio y Off-spec un %
        local D = addonTable.Dkp
        local price = LT.GetItemPrice(item)
        frame.buttons.need:SetText(L["Main-spec"] .. " (" .. price .. ")")
        frame.buttons.offspec:SetText(L["Off-spec"] .. " (" .. D.GetOffspecPrice(price) .. ")")
        local ok, reason = D.CheckEligible(me, LT.GetItemTier(item))
        local warning = ok and "" or (reason == "gate" and L["\n|cFFFF3333Necesitas al menos "] .. D.GetSettings().gate .. L[" DKP para piezas de Mítica.|r"]
            or L["\n|cFFFF3333No llegas a la asistencia mínima.|r"])
        -- Sin DKP para pagar, ese botón no se puede pulsar
        local canNeed, canOff = LT.CanAfford(me, item, "need"), LT.CanAfford(me, item, "offspec")
        frame.buttons.need:SetEnabled(canNeed)
        frame.buttons.offspec:SetEnabled(canOff)
        if ok and not canOff then
            warning = L["\n|cFFFF3333No tienes DKP suficientes para pedirlo.|r"]
        elseif ok and not canNeed then
            warning = L["\n|cFFFF3333Solo te llega para Off-spec.|r"]
        end
        frame.info:SetText(L["Tus DKP: |cFFFFD100"] .. D.GetBalance(me) .. L["|r   Precio: |cFFFFD100"] .. price .. "|r" .. winsText .. warning)
    elseif auction then
        local D = addonTable.Dkp
        local minBid = LT.GetMinBid(item)
        local maxBid = math.max(minBid, D.GetBalance(me))
        local slider = frame.bidSlider
        slider.updating = true
        slider:SetMinMaxValues(minBid, maxBid)
        slider:SetValue(minBid)
        slider.updating = false
        slider:SetEnabled(maxBid > minBid)
        slider.low:SetText(minBid)
        slider.high:SetText(maxBid)
        frame.bidInput:SetText(tostring(minBid))
        frame.info:SetText(L["Tus DKP: |cFFFFD100"] .. D.GetBalance(me) .. L["|r   Puja mínima: |cFFFFD100"] .. minBid .. "|r" .. winsText)
    else
        for kind, btn in pairs(frame.buttons) do btn:SetText(L[LT.KINDS[kind]]) end
        frame.info:SetText(L["Tus +1: |cFFFFD100"] .. LT.GetPoints(me) .. "|r" .. winsText)
    end
    frame:Show()
end

local function BuildLootView(parent)
    local LT = addonTable.Loot
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()
    local selectedKey = nil
    local Refresh

    local title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", view, "TOPLEFT", 16, -12)
    title:SetText(L["Botín"])

    local systemLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    systemLabel:SetPoint("LEFT", title, "RIGHT", 24, 0)
    systemLabel:SetText(L["Sistema:"])
    local dropSystem = CreateFrame("DropdownButton", "GC_LootSystem", view, "WowStyle1DropdownTemplate")
    dropSystem:SetPoint("LEFT", systemLabel, "RIGHT", 8, 0)
    dropSystem:SetWidth(170)
    -- El sistema lo eligen los oficiales y llega a toda la hermandad
    dropSystem:SetupMenu(function(_, root)
        local isOfficer = addonTable.Profiles and addonTable.Profiles.IsOfficer()
        for _, system in ipairs(LT.SYSTEMS) do
            local key = system.key
            local button = root:CreateRadio(L[system.label], function() return LT.GetSystem() == key end, function()
                if addonTable.Dkp then addonTable.Dkp.SetSystem(key) end
            end)
            if not isOfficer and button and button.SetEnabled then button:SetEnabled(false) end
        end
    end)
    dropSystem:SetText("+1")

    local sessionText = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sessionText:SetPoint("LEFT", dropSystem, "RIGHT", 16, 0)

    local btnNewSession = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    btnNewSession:SetSize(120, 22)
    btnNewSession:SetPoint("TOPRIGHT", view, "TOPRIGHT", -10, -10)
    btnNewSession:SetText(L["Nueva sesión"])
    btnNewSession:SetScript("OnClick", function() selectedKey = nil; LT.NewSession() end)
    view.btnShowLoot = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.btnShowLoot:SetSize(90, 22)
    view.btnShowLoot:SetPoint("RIGHT", btnNewSession, "LEFT", -6, 0)
    view.btnShowLoot:SetText(L["Mostrar"])
    view.btnShowLoot:SetScript("OnClick", function() LT.ShowToGroup() end)

    -- Caja con título y lista con scroll
    local function ListBox(titleText, color, width, height)
        local box = CreateColoredPanel(view, titleText, color, width, height)
        box.scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
        box.scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -28)
        box.scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -28, 8)
        box.child = CreateFrame("Frame")
        box.child:SetSize(width - 40, 1)
        box.scroll:SetScrollChild(box.child)
        box.empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        box.empty:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -34)
        box.empty:SetWidth(width - 30)
        box.empty:SetJustifyH("LEFT")
        box.rows = {}
        return box
    end

    local itemsBox = ListBox(L["Objetos de la banda"], PANEL_COLORS.purple, 437, 234)
    itemsBox:SetPoint("TOPLEFT", view, "TOPLEFT", 10, -40)
    itemsBox.scroll:SetPoint("BOTTOMRIGHT", itemsBox, "BOTTOMRIGHT", -28, 36)
    local historyBox = ListBox(L["Historial de botín"], PANEL_COLORS.gold, 437, 234)
    historyBox:SetPoint("TOPLEFT", itemsBox, "BOTTOMLEFT", 0, -6)
    local rollBox = CreateColoredPanel(view, L["Tirada"], PANEL_COLORS.green, 437, 234)
    rollBox:SetPoint("TOPLEFT", itemsBox, "TOPRIGHT", 6, 0)
    local pointsBox = ListBox(L["+1 de la hermandad"], PANEL_COLORS.blue, 437, 234)
    pointsBox:SetPoint("TOPLEFT", rollBox, "BOTTOMLEFT", 0, -6)

    -- Añadir un objeto a mano: Shift+clic en un objeto con el cursor en la caja
    local addInput = CreateFrame("EditBox", nil, itemsBox, "InputBoxTemplate")
    addInput:SetSize(290, 20)
    addInput:SetPoint("BOTTOMLEFT", itemsBox, "BOTTOMLEFT", 16, 10)
    addInput:SetAutoFocus(false)
    addInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local addPlaceholder = addInput:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    addPlaceholder:SetPoint("LEFT", addInput, "LEFT", 2, 0)
    addPlaceholder:SetText(L["Shift+clic en un objeto para añadirlo"])
    addInput:SetScript("OnTextChanged", function(self) addPlaceholder:SetShown((self:GetText() or "") == "") end)
    local btnAddItem = CreateFrame("Button", nil, itemsBox, "UIPanelButtonTemplate")
    btnAddItem:SetSize(90, 22)
    btnAddItem:SetPoint("LEFT", addInput, "RIGHT", 8, 0)
    btnAddItem:SetText(L["Añadir"])
    local function AddTyped()
        local item = LT.AddManual(addInput:GetText())
        if not item then
            PrintGC(L["|cFFFF3333Pega el enlace del objeto con Shift+clic.|r"])
            return
        end
        selectedKey = item.key
        addInput:SetText("")
        addInput:ClearFocus()
    end
    btnAddItem:SetScript("OnClick", AddTyped)
    addInput:SetScript("OnEnterPressed", AddTyped)
    OnInsertLink(function(link)
            if addInput:IsVisible() and addInput:HasFocus() and link then addInput:Insert(link) end
    end)

    -- Filas de objetos
    local STATE_TEXT = {
        pending = L["|cFFBFBFBFPendiente|r"], rolling = L["|cFF00FF00Tirando...|r"],
    }
    local function AcquireItemRow(index)
        local row = itemsBox.rows[index]
        if row then return row end
        row = CreateFrame("Button", nil, itemsBox.child)
        row:SetSize(390, 34)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.06)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(28, 28)
        row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.action = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.action:SetSize(70, 20)
        row.action:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
        row.name:SetPoint("RIGHT", row.action, "LEFT", -4, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.info:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
        row.info:SetPoint("RIGHT", row.action, "LEFT", -4, 0)
        row.info:SetJustifyH("LEFT")
        row.info:SetWordWrap(false)
        row:SetScript("OnClick", function(self) selectedKey = self.key; Refresh() end)
        row:SetScript("OnEnter", function(self) ShowLinkTooltip(self, self.link) end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        itemsBox.rows[index] = row
        return row
    end

    -- Panel de la tirada seleccionada
    local rollItem = CreateFrame("Button", nil, rollBox)
    rollItem:SetSize(420, 30)
    rollItem:SetPoint("TOPLEFT", rollBox, "TOPLEFT", 10, -28)
    rollItem.icon = rollItem:CreateTexture(nil, "ARTWORK")
    rollItem.icon:SetSize(28, 28)
    rollItem.icon:SetPoint("LEFT", rollItem, "LEFT", 0, 0)
    rollItem.text = rollItem:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rollItem.text:SetPoint("LEFT", rollItem.icon, "RIGHT", 8, 0)
    rollItem.text:SetPoint("RIGHT", rollItem, "RIGHT", 0, 0)
    rollItem.text:SetJustifyH("LEFT")
    rollItem.text:SetWordWrap(false)
    rollItem:SetScript("OnEnter", function(self) ShowLinkTooltip(self, self.link) end)
    rollItem:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local rollState = rollBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rollState:SetPoint("TOPLEFT", rollItem, "BOTTOMLEFT", 0, -4)
    rollState:SetWidth(420)
    rollState:SetJustifyH("LEFT")

    local chooseButtons = {}
    local previousChoose
    for _, kind in ipairs({ "need", "offspec", "pass" }) do
        local btn = CreateFrame("Button", nil, rollBox, "UIPanelButtonTemplate")
        btn:SetSize(110, 22)
        if previousChoose then btn:SetPoint("LEFT", previousChoose, "RIGHT", 4, 0) else btn:SetPoint("TOPLEFT", rollState, "BOTTOMLEFT", 0, -6) end
        btn:SetText(L[LT.KINDS[kind]])
        btn:SetScript("OnClick", function() if selectedKey then LT.Choose(selectedKey, kind) end end)
        chooseButtons[kind] = btn
        previousChoose = btn
    end

    -- Subasta DKP: cantidad, Pujar y Pasar (se puede subir la puja mientras siga abierta)
    local bidInput = CreateFrame("EditBox", nil, rollBox, "InputBoxTemplate")
    bidInput:SetSize(80, 20)
    bidInput:SetPoint("TOPLEFT", rollState, "BOTTOMLEFT", 6, -7)
    bidInput:SetAutoFocus(false)
    bidInput:SetNumeric(true)
    bidInput:SetMaxLetters(6)
    bidInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local btnBid = CreateFrame("Button", nil, rollBox, "UIPanelButtonTemplate")
    btnBid:SetSize(100, 22)
    btnBid:SetPoint("LEFT", bidInput, "RIGHT", 8, 0)
    btnBid:SetText(L["Pujar"])
    local function DoBid()
        if selectedKey and LT.Bid(selectedKey, bidInput:GetText()) then bidInput:ClearFocus() end
    end
    btnBid:SetScript("OnClick", DoBid)
    bidInput:SetScript("OnEnterPressed", DoBid)
    local btnBidPass = CreateFrame("Button", nil, rollBox, "UIPanelButtonTemplate")
    btnBidPass:SetSize(80, 22)
    btnBidPass:SetPoint("LEFT", btnBid, "RIGHT", 4, 0)
    btnBidPass:SetText(L["Pasar"])
    btnBidPass:SetScript("OnClick", function() if selectedKey then LT.Choose(selectedKey, "pass") end end)
    local bidControls = { bidInput, btnBid, btnBidPass }

    -- Precio del objeto elegido (oficiales, DKP)
    local btnPrice = CreateFrame("Button", nil, rollBox, "UIPanelButtonTemplate")
    btnPrice:SetSize(90, 20)
    btnPrice:SetPoint("TOPRIGHT", rollBox, "TOPRIGHT", -8, -3)
    btnPrice:SetText(L["Precio"])
    btnPrice:SetScript("OnClick", function() if selectedKey and uiModule.ShowItemPrice then uiModule.ShowItemPrice(selectedKey) end end)

    local ROLL_COLS = { name = 0, kind = 130, roll = 230, points = 280, wins = 320 }
    local rollHeader = CreateFrame("Frame", nil, rollBox)
    rollHeader:SetSize(420, 14)
    rollHeader:SetPoint("TOPLEFT", rollState, "BOTTOMLEFT", 0, -32)
    rollHeader.labels = {}
    for _, h in ipairs({ { "name", L["Jugador"] }, { "kind", L["Pide"] }, { "roll", L["Tirada"] },
                         { "points", "+1" }, { "wins", L["En esta banda"] } }) do
        local fs = rollHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", rollHeader, "LEFT", ROLL_COLS[h[1]], 0)
        fs:SetText(h[2])
        rollHeader.labels[h[1]] = fs
    end
    -- Quienes piden o pujan y quienes pasan, en una lista con desplazamiento (antes solo se veían 4)
    local rollScroll = CreateFrame("ScrollFrame", nil, rollBox, "UIPanelScrollFrameTemplate")
    rollScroll:SetPoint("TOPLEFT", rollHeader, "BOTTOMLEFT", 0, -2)
    rollScroll:SetPoint("BOTTOMRIGHT", rollBox, "BOTTOMRIGHT", -28, 38)
    local rollChild = CreateFrame("Frame", nil, rollScroll)
    rollChild:SetSize(399, 1)
    rollScroll:SetScrollChild(rollChild)
    local rollRows = {}
    local function AcquireRollRow(index)
        local row = rollRows[index]
        if row then return row end
        row = CreateFrame("Button", nil, rollChild)
        row:SetSize(399, 16)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)
        row.cells = {}
        for key, x in pairs(ROLL_COLS) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", row, "LEFT", x, 0)
            row.cells[key] = fs
        end
        -- Clic derecho (quien gestiona la tirada): asignar a este jugador
        row:SetScript("OnClick", function(self, button)
            if button ~= "RightButton" or not self.playerName or not selectedKey or not LT.CanManage() then return end
            local name = self.playerName
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(ShortName(name))
                root:CreateButton(L["Asignar a este jugador"], function() LT.Award(selectedKey, name) end)
            end)
        end)
        rollRows[index] = row
        return row
    end

    local passText = rollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    passText:SetWidth(390)
    passText:SetJustifyH("LEFT")

    local btnStartRoll = CreateFrame("Button", nil, rollBox, "UIPanelButtonTemplate")
    btnStartRoll:SetSize(130, 22)
    btnStartRoll:SetPoint("BOTTOMLEFT", rollBox, "BOTTOMLEFT", 10, 10)
    btnStartRoll:SetText(L["Abrir tirada"])
    btnStartRoll:SetScript("OnClick", function() if selectedKey then LT.StartRoll(selectedKey) end end)
    local btnAward = CreateFrame("Button", nil, rollBox, "UIPanelButtonTemplate")
    btnAward:SetSize(170, 22)
    btnAward:SetPoint("LEFT", btnStartRoll, "RIGHT", 6, 0)
    btnAward:SetText(L["Asignar al ganador"])
    btnAward:SetScript("OnClick", function()
        if selectedKey and not LT.Award(selectedKey) then PrintGC(L["|cFFFF3333Nadie ha tirado todavía.|r"]) end
    end)
    local btnCancelRoll = CreateFrame("Button", nil, rollBox, "UIPanelButtonTemplate")
    btnCancelRoll:SetSize(100, 22)
    btnCancelRoll:SetPoint("LEFT", btnAward, "RIGHT", 6, 0)
    btnCancelRoll:SetText(L["Cancelar"])
    btnCancelRoll:SetScript("OnClick", function() if selectedKey then LT.CancelRoll(selectedKey) end end)

    local rollEmpty = rollBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rollEmpty:SetPoint("CENTER", rollBox, "CENTER", 0, 0)
    rollEmpty:SetWidth(400)
    rollEmpty:SetText(L["Selecciona un objeto de la banda. Los objetos aparecen solos al derrotar a un jefe en grupo, o añádelos con Shift+clic."])

    -- +1 de la hermandad: reinicio con doble clic de confirmación
    local resetArmedUntil = 0
    local btnReset = CreateFrame("Button", nil, pointsBox, "UIPanelButtonTemplate")
    btnReset:SetSize(110, 20)
    btnReset:SetPoint("TOPRIGHT", pointsBox, "TOPRIGHT", -8, -3)
    btnReset:SetText(L["Reiniciar +1"])
    btnReset:SetScript("OnClick", function(self)
        if GetTime() < resetArmedUntil then
            resetArmedUntil = 0
            self:SetText(L["Reiniciar +1"])
            LT.ResetPoints()
        else
            resetArmedUntil = GetTime() + 4
            self:SetText(L["|cFFFF3333¿Seguro?|r"])
            C_Timer.After(4, function() if GetTime() >= resetArmedUntil then self:SetText(L["Reiniciar +1"]) end end)
        end
    end)

    -- DKP: ajustes y DKP de banda (oficiales)
    local btnDkpSettings = CreateFrame("Button", nil, pointsBox, "UIPanelButtonTemplate")
    btnDkpSettings:SetSize(76, 20)
    btnDkpSettings:SetPoint("TOPRIGHT", pointsBox, "TOPRIGHT", -8, -3)
    btnDkpSettings:SetText(L["Ajustes"])
    btnDkpSettings:SetScript("OnClick", function() if uiModule.ShowDkpSettings then uiModule.ShowDkpSettings() end end)
    local raidArmedUntil = 0
    local btnRaidDkp = CreateFrame("Button", nil, pointsBox, "UIPanelButtonTemplate")
    btnRaidDkp:SetSize(110, 20)
    btnRaidDkp:SetPoint("RIGHT", btnDkpSettings, "LEFT", -4, 0)
    btnRaidDkp:SetText(L["DKP de banda"])
    btnRaidDkp:SetScript("OnClick", function(self)
        if GetTime() < raidArmedUntil then
            raidArmedUntil = 0
            self:SetText(L["DKP de banda"])
            addonTable.Dkp.AwardRaid()
        else
            raidArmedUntil = GetTime() + 4
            self:SetText(L["|cFFFF3333¿Dar "] .. addonTable.Dkp.GetSettings().raid .. "?|r")
            C_Timer.After(4, function() if GetTime() >= raidArmedUntil then self:SetText(L["DKP de banda"]) end end)
        end
    end)
    btnRaidDkp:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["DKP de banda"], 1, 1, 1)
        GameTooltip:AddLine(L["Da los DKP de banda completada a los miembros de la hermandad de tu grupo (dos clics)."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnRaidDkp:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local btnPrices = CreateFrame("Button", nil, pointsBox, "UIPanelButtonTemplate")
    btnPrices:SetSize(70, 20)
    btnPrices:SetPoint("RIGHT", btnRaidDkp, "LEFT", -4, 0)
    btnPrices:SetText(L["Precios"])
    btnPrices:SetScript("OnClick", function() if uiModule.ShowDkpPrices then uiModule.ShowDkpPrices() end end)

    local function SimpleRow(box, index)
        local row = box.rows[index]
        if row then return row end
        row = CreateFrame("Button", nil, box.child)
        row:SetSize(box.child:GetWidth(), 16)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetAllPoints()
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnEnter", function(self) ShowLinkTooltip(self, self.link) end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        box.rows[index] = row
        return row
    end

    local function ClassName(fullName)
        local m = GuildControlDB.members[fullName]
        return "|cFF" .. addonTable.GetClassColorHex(m and m.class) .. ShortName(fullName) .. "|r"
    end

    Refresh = function()
        if not view:IsShown() then return end
        local canManage = LT.CanManage()
        local isOfficer = addonTable.Profiles and addonTable.Profiles.IsOfficer()
        local dkp = LT.IsDkp()
        local D = addonTable.Dkp
        if activeTab == "Botín" and view.helpDkp ~= dkp then
            view.helpDkp = dkp
            SetPreviewText(L[TabHelp("Botín")])
        end
        btnNewSession:SetShown(canManage)
        view.btnShowLoot:SetShown(canManage and IsInGroup())
        btnReset:SetShown(isOfficer and not dkp)
        btnDkpSettings:SetShown(isOfficer and dkp)
        btnRaidDkp:SetShown(isOfficer and dkp)
        btnPrices:SetShown(isOfficer and dkp)
        local fixed = dkp and LT.IsFixed()
        dropSystem:SetText(dkp and "DKP" or "+1")
        pointsBox.title:SetText(dkp and L["DKP de la hermandad"] or L["+1 de la hermandad"])
        rollHeader.labels.kind:SetText(fixed and L["Pide"] or (dkp and L["Puja"] or L["Pide"]))
        rollHeader.labels.roll:SetText(fixed and L["Paga"] or (dkp and "DKP" or L["Tirada"]))
        rollHeader.labels.points:SetText(fixed and "DKP" or (dkp and L["Antig."] or "+1"))
        -- En precio fijo los botones de pedir son Main-spec y Off-spec
        for kind, btn in pairs(chooseButtons) do
            btn:SetText(fixed and (kind == "need" and L["Main-spec"] or (kind == "offspec" and L["Off-spec"] or L["Pasar"])) or L[LT.KINDS[kind]])
        end
        local function WinnerText(it)
            if it.kind == "bid" then return " |cFFFFD100" .. tostring(it.roll or 0) .. " DKP|r" end
            return it.kind == "need" and " |cFFFFD100+1|r" or L[" |cFF66B3FF(off-spec)|r"]
        end
        local session = LT.GetSession()
        sessionText:SetText(session and (L["Sesión: |cFFFFD100"] .. session.title .. "|r |cFF808080" .. date("%d/%m %H:%M", session.startedAt) .. "|r")
            or L["|cFF808080Sin sesión: empieza al salir botín en banda.|r"])

        -- Objetos
        local items = LT.GetItems()
        local activeKey = LT.GetActiveKey()
        -- Al abrirse una tirada nueva (también la del líder) se selecciona sola
        if activeKey and (not selectedKey or activeKey ~= view.lastActiveKey) then selectedKey = activeKey end
        view.lastActiveKey = activeKey
        for _, row in ipairs(itemsBox.rows) do row:Hide() end
        for i, item in ipairs(items) do
            local row = AcquireItemRow(i)
            row:SetPoint("TOPLEFT", itemsBox.child, "TOPLEFT", 0, -(i - 1) * 36)
            local link = LT.DisplayLink(item.link)
            row.key, row.link = item.key, link
            row.bg:SetColorTexture(1, 0.82, 0, item.key == selectedKey and 0.2 or 0.04)
            row.icon:SetTexture(ItemIconFromLink(link))
            row.name:SetText(link)
            local state = item.state == "done"
                and (L["|cFF00FF00Ganador:|r "] .. ClassName(item.winner) .. WinnerText(item))
                or STATE_TEXT[item.state] or ""
            local priceText = (dkp and item.state ~= "done") and ("   |cFFFFD100" .. LT.GetItemPrice(item) .. " DKP|r") or ""
            local wanted = addonTable.Personal and #addonTable.Personal.WhoWants(addonTable.Personal.ItemIdFromLink(item.link)) or 0
            if wanted > 0 and item.state ~= "done" then priceText = priceText .. "   |cFFFFD100*" .. wanted .. "|r" end
            local tradeText = LT.TradeText and LT.TradeText(item) or ""
            row.info:SetText(L["Le tocó a "] .. ShortName(item.owner) .. priceText .. "   " .. state .. (tradeText ~= "" and ("   " .. tradeText) or ""))
            row.action:SetShown(canManage and item.state ~= "done")
            row.action:SetText(item.state == "rolling" and L["Asignar"] or (dkp and L["Subastar"] or L["Tirar"]))
            row.action:SetScript("OnClick", function()
                selectedKey = item.key
                if item.state == "rolling" then LT.Award(item.key) else LT.StartRoll(item.key) end
            end)
            row:Show()
        end
        itemsBox.child:SetHeight(math.max(1, #items * 36))
        itemsBox.empty:SetShown(#items == 0)
        itemsBox.empty:SetText(L["Todavía no ha salido botín en esta sesión."])

        -- Tirada seleccionada
        local item = selectedKey and LT.GetItem(selectedKey)
        for _, row in ipairs(rollRows) do row:Hide() end
        local hasItem = item ~= nil
        for _, w in ipairs({ rollItem, rollState, rollHeader, rollScroll }) do w:SetShown(hasItem) end
        rollEmpty:SetShown(not hasItem)
        for _, btn in pairs(chooseButtons) do btn:SetShown(false) end
        for _, w in ipairs(bidControls) do w:SetShown(false) end
        btnStartRoll:SetShown(false); btnAward:SetShown(false); btnCancelRoll:SetShown(false)
        btnPrice:SetShown(hasItem and dkp and isOfficer and canManage and item.state ~= "done")
        if hasItem then
            local link = LT.DisplayLink(item.link)
            rollItem.link = link
            rollItem.icon:SetTexture(ItemIconFromLink(link))
            rollItem.text:SetText(link)
            local myChoice = LT.GetMyChoice(item.key)
            local me = addonTable.Profiles.GetMyFullName()
            local price = dkp and LT.GetItemPrice(item) or 0
            if item.state == "rolling" and fixed then
                rollState:SetText(L["|cFF00FF00Abierto.|r "] .. L["Precio: |cFFFFD100"] .. price .. L["|r · Off-spec: |cFFFFD100"]
                    .. D.GetOffspecPrice(price) .. "|r" .. (myChoice and (L["   Has pedido: "] .. (myChoice == "need" and L["Main-spec"] or (myChoice == "offspec" and L["Off-spec"] or L["Pasar"]))) or ""))
                for _, btn in pairs(chooseButtons) do btn:SetShown(not myChoice) end
            elseif item.state == "rolling" and dkp then
                local mine = item.rolls[me]
                rollState:SetText(L["|cFF00FF00Subasta abierta.|r "] .. L["Tus DKP: |cFFFFD100"] .. D.GetBalance(me) .. "|r"
                    .. ((mine and mine.kind == "bid") and (L["   Tu puja: |cFFFFD100"] .. mine.bid .. "|r") or ""))
                for _, w in ipairs(bidControls) do w:SetShown(true) end
                if not bidInput:HasFocus() then bidInput:SetText(tostring(LT.GetMinBid(item))) end
            elseif item.state == "rolling" then
                rollState:SetText(L["|cFF00FF00Tirada abierta.|r "] .. (myChoice and (L["Has pedido: "] .. L[LT.KINDS[myChoice]]) or L["Elige qué pides:"]))
                for _, btn in pairs(chooseButtons) do btn:SetShown(not myChoice) end
            elseif item.state == "done" then
                rollState:SetText(L["|cFF00FF00Ganador:|r "] .. ClassName(item.winner) .. WinnerText(item)
                    .. (item.kind == "bid" and "" or (L["  ·  tirada "] .. tostring(item.roll or "-"))))
            else
                rollState:SetText(dkp and (L["|cFFBFBFBFPendiente.|r "] .. L["Precio: |cFFFFD100"] .. price .. " DKP|r") or L["|cFFBFBFBFPendiente de tirar.|r"])
            end
            -- Quién tiene el objeto en su lista de deseos (estrella delante del nombre)
            local wantSet = {}
            if addonTable.Personal then
                for _, name in ipairs(addonTable.Personal.WhoWants(addonTable.Personal.ItemIdFromLink(item.link))) do wantSet[name] = true end
            end
            local list = LT.GetRollList(item)
            for i, entry in ipairs(list) do
                local row = AcquireRollRow(i)
                row:SetPoint("TOPLEFT", rollChild, "TOPLEFT", 0, -(i - 1) * 16)
                row.playerName = entry.name
                local color = LT.KIND_COLORS[entry.kind] or "FFFFFF"
                local wants = wantSet[entry.name] and "|cFFFFD100*|r " or ""
                row.cells.name:SetText((i == 1 and item.state == "rolling" and "|cFFFFD100>|r " or "") .. wants .. ClassName(entry.name))
                if fixed and (entry.kind == "need" or entry.kind == "offspec") then
                    -- Precio fijo: lo que pide, lo que pagaría y sus DKP; si no puede optar, el motivo
                    row.cells.kind:SetText("|cFF" .. color .. (entry.kind == "need" and L["Main-spec"] or L["Off-spec"]) .. "|r")
                    row.cells.roll:SetText((entry.valid and "|cFFFFD100" or "|cFFFF3333") .. entry.price .. "|r")
                    row.cells.points:SetText(tostring(entry.balance))
                elseif entry.kind == "bid" then
                    -- Puja, DKP del jugador (en rojo si la puja los supera) y días de antigüedad
                    row.cells.kind:SetText((entry.valid and "|cFFFFD100" or "|cFFFF3333") .. entry.bid .. "|r")
                    row.cells.roll:SetText(tostring(entry.balance))
                    row.cells.points:SetText(entry.days and (entry.days .. L["d"]) or "|cFF808080-|r")
                else
                    row.cells.kind:SetText("|cFF" .. color .. L[LT.KINDS[entry.kind]] .. "|r")
                    row.cells.roll:SetText(entry.roll and tostring(entry.roll) or "|cFF808080...|r")
                    row.cells.points:SetText(tostring(entry.points))
                end
                if entry.valid == false and entry.reason then
                    row.cells.wins:SetText(entry.reason == "dkp" and L["|cFFFF3333Sin DKP|r"]
                        or entry.reason == "gate" and L["|cFFFF3333Mín. DKP|r"] or L["|cFFFF3333Asistencia|r"])
                else
                    row.cells.wins:SetText(entry.wins > 0 and ("|cFFFF7F00" .. L["Ya ganó "] .. entry.wins .. "|r") or "")
                end
                row:Show()
            end
            local passes = LT.GetPassList(item)
            passText:ClearAllPoints()
            passText:SetPoint("TOPLEFT", rollChild, "TOPLEFT", 0, -2 - #list * 16)
            local passNames = {}
            for _, name in ipairs(passes) do table.insert(passNames, ShortName(name)) end
            passText:SetText(#passNames > 0 and (L["Pasan: "] .. table.concat(passNames, ", ")) or "")
            rollChild:SetHeight(math.max(1, #list * 16 + (#passNames > 0 and (passText:GetStringHeight() + 6) or 0)))
            btnStartRoll:SetShown(canManage and item.state == "pending")
            btnAward:SetShown(canManage and item.state == "rolling")
            btnCancelRoll:SetShown(canManage and item.state == "rolling")
        end

        -- +1 o DKP de la hermandad (con DKP: clic derecho de un oficial para ajustar)
        local points = dkp and D.GetList() or LT.GetPointsList()
        for _, row in ipairs(pointsBox.rows) do row:Hide() end
        for i, entry in ipairs(points) do
            local row = SimpleRow(pointsBox, i)
            row:SetPoint("TOPLEFT", pointsBox.child, "TOPLEFT", 4, -(i - 1) * 16)
            row.link = nil
            if dkp then
                row.text:SetText("|cFFFFD100" .. entry.balance .. " DKP|r  " .. ClassName(entry.name)
                    .. (entry.days and (" |cFF808080(" .. entry.days .. L[" días)"] .. "|r") or L[" |cFF808080(sin Mi perfil)|r"]))
                row:RegisterForClicks("RightButtonUp")
                local name = entry.name
                row:SetScript("OnClick", function()
                    if isOfficer and uiModule.ShowDkpAdjust then uiModule.ShowDkpAdjust(name) end
                end)
            else
                row.text:SetText("|cFFFFD100+" .. entry.points .. "|r  " .. ClassName(entry.name))
                row:SetScript("OnClick", nil)
            end
            row:Show()
        end
        pointsBox.child:SetHeight(math.max(1, #points * 16))
        pointsBox.empty:SetShown(#points == 0)
        pointsBox.empty:SetText(dkp and L["Nadie tiene DKP todavía. Se ganan por jefe, por banda y por antigüedad (desde que se rellena Mi perfil)."] or L["Nadie tiene +1 todavía."])

        -- Historial
        local history = LT.GetHistory()
        for _, row in ipairs(historyBox.rows) do row:Hide() end
        local shown = math.min(#history, 60)
        for i = 1, shown do
            local entry = history[i]
            local row = SimpleRow(historyBox, i)
            row:SetPoint("TOPLEFT", historyBox.child, "TOPLEFT", 4, -(i - 1) * 16)
            local link = LT.DisplayLink(entry.link)
            row.link = link
            local kindText
            if entry.kind == "bid" then kindText = " |cFFFFD100-" .. tostring(entry.roll or 0) .. " DKP|r  "
            elseif entry.kind == "need" then kindText = " |cFFFFD100+1|r  "
            else kindText = L[" |cFF66B3FF(off)|r  "] end
            row.text:SetText("|cFF808080" .. date("%d/%m", entry.at or 0) .. "|r  " .. ClassName(entry.winner) .. kindText .. link
                .. (entry.external and L[" |cFF66B3FF[fuera de la hermandad]|r"] or ""))
            row:Show()
        end
        historyBox.child:SetHeight(math.max(1, shown * 16))
        historyBox.empty:SetShown(#history == 0)
        historyBox.empty:SetText(L["Todavía no se ha repartido nada."])
    end

    LT.AddListener(function() Refresh() end)
    if addonTable.Dkp then addonTable.Dkp.AddListener(function() Refresh() end) end
    view:SetScript("OnShow", Refresh)
    uiModule.AddTips({
        { btnNewSession, "Nueva sesión", "Empieza una sesión de botín nueva: la lista de objetos se vacía (el historial se conserva)." },
        { view.btnShowLoot, "Mostrar", "Abre el botín a todos los del grupo con GuildControl, con la lista de objetos de la sesión." },
        { btnAddItem, "Añadir", "Añade a la sesión el objeto escrito o pegado con Shift+clic." },
        { btnBid, "Pujar", "Envía tu puja por el objeto con los DKP escritos." },
        { btnBidPass, "Pasar", "No pujas por este objeto." },
        { btnPrice, "Precio", "Solo oficiales: cambia el precio de este objeto." },
        { btnStartRoll, "Abrir tirada", "Avisa a la banda para que pidan o pujen por el objeto elegido." },
        { btnAward, "Asignar al ganador", "Da el objeto a quien va primero en la lista y lo apunta en el historial." },
        { btnCancelRoll, "Cancelar", "Cierra la tirada sin asignar el objeto." },
        { btnReset, "Reiniciar +1", "Pone a cero los +1 de todos (pide confirmación)." },
        { btnDkpSettings, "Ajustes", "Puntos por jefe y por banda, decay, mínimos y forma de reparto." },
        { btnPrices, "Precios", "Edita la tabla de precios por tipo de objeto." },
    })
    containers.views["Botín"] = view
end

-- La ventanita de tirada se abre aunque la ventana del addon esté cerrada
if addonTable.Loot then
    addonTable.Loot.OnRollStarted = function(key) uiModule.ShowLootRollPopup(key) end
    -- Mostrar del líder: el botín se abre en su ventana flotante
    addonTable.Loot.OnShowRequested = function() uiModule.ShowLootFloat() end
end

-- =========================================================================
-- 9. VISTA DE CONFIGURACIÓN (HERMANDAD, VENTANA, IDIOMA Y SALUDO)
-- =========================================================================

local PRESET_ICONS = {
    "Achievement_GuildPerk_MobileBanking", "Achievement_GuildPerk_EverybodysFriend", "Ability_Hunter_Pet_Wolf",
    "INV_BannerPVP_01", "INV_BannerPVP_02", "Ability_Warrior_BattleShout", "INV_Sword_04", "INV_Shield_06",
    "Spell_Holy_PowerWordShield", "Spell_Nature_HealingTouch", "Spell_Fire_Fire", "Spell_Frost_FrostBolt02",
    "Spell_Shadow_ShadowBolt", "INV_Misc_Head_Dragon_01", "INV_Misc_Coin_01", "Achievement_Boss_Ragnaros",
    "Ability_Mount_Drake_Proto", "INV_Misc_Book_09", "Spell_Holy_HolyBolt", "Ability_DualWield",
    "INV_Helmet_06", "Achievement_Dungeon_ClassicDungeonMaster", "Ability_Warrior_DefensiveStance", "INV_Misc_QuestionMark",
}

-- Selector con todos los iconos del juego (los de las macros): cuadrícula con desplazamiento.
-- onPick(fileID) se llama al elegir uno.
local GC_IconPicker = nil
local gameIcons = nil
local PICKER = { cols = 10, rows = 9, cell = 40 }

local function LoadGameIcons()
    if gameIcons then return gameIcons end
    gameIcons = {}
    if GetMacroIcons then pcall(GetMacroIcons, gameIcons) end
    if GetMacroItemIcons then pcall(GetMacroItemIcons, gameIcons) end
    if #gameIcons == 0 then
        for _, iconName in ipairs(PRESET_ICONS) do table.insert(gameIcons, "Interface\\Icons\\" .. iconName) end
    end
    return gameIcons
end

function uiModule.ShowIconPicker(onPick)
    if not GC_UI then return end
    if not GC_IconPicker then
        local frame = CreateFrame("Frame", "GuildControlIconPicker", GC_UI, "BasicFrameTemplateWithInset")
        frame:SetSize(PICKER.cols * PICKER.cell + 52, PICKER.rows * PICKER.cell + 70)
        frame:SetPoint("CENTER", GC_UI, "CENTER", 0, 0)
        frame:SetFrameStrata("DIALOG")
        frame:EnableMouse(true)
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
        frame.title:SetText(L["Iconos del juego"])
        frame.offset = 0

        frame.cells = {}
        for row = 1, PICKER.rows do
            for col = 1, PICKER.cols do
                local btn = CreateFrame("Button", nil, frame)
                btn:SetSize(PICKER.cell - 4, PICKER.cell - 4)
                btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12 + (col - 1) * PICKER.cell, -32 - (row - 1) * PICKER.cell)
                btn.icon = btn:CreateTexture(nil, "ARTWORK")
                btn.icon:SetAllPoints()
                btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
                btn:SetScript("OnClick", function(self)
                    if self.value and frame.onPick then frame.onPick(self.value) end
                    frame:Hide()
                end)
                table.insert(frame.cells, btn)
            end
        end

        local slider = CreateFrame("Slider", nil, frame, "BackdropTemplate")
        slider:SetOrientation("VERTICAL")
        slider:SetSize(16, PICKER.rows * PICKER.cell - 4)
        slider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -32)
        slider:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
            tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 } })
        slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
        slider:SetValueStep(1)
        slider:SetObeyStepOnDrag(true)
        frame.slider = slider

        frame.countText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        frame.countText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 12)

        function frame.Render()
            local icons = LoadGameIcons()
            for i, btn in ipairs(frame.cells) do
                local value = icons[frame.offset * PICKER.cols + i]
                btn.value = value
                btn.icon:SetTexture(value)
                btn:SetShown(value ~= nil)
            end
            frame.countText:SetText(#icons .. L[" iconos · rueda del ratón para desplazarte"])
        end
        slider:SetScript("OnValueChanged", function(_, value)
            frame.offset = math.floor(value + 0.5)
            frame.Render()
        end)
        frame:EnableMouseWheel(true)
        frame:SetScript("OnMouseWheel", function(_, delta)
            local minValue, maxValue = slider:GetMinMaxValues()
            slider:SetValue(math.max(minValue, math.min(maxValue, slider:GetValue() - delta * 3)))
        end)
        GC_IconPicker = frame
    end
    local frame = GC_IconPicker
    frame.onPick = onPick
    local totalRows = math.ceil(#LoadGameIcons() / PICKER.cols)
    frame.slider:SetMinMaxValues(0, math.max(0, totalRows - PICKER.rows))
    frame.slider:SetValue(0)
    frame.offset = 0
    frame.Render()
    frame:Show()
end

local function BuildConfigView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()
    local settings = function() return GuildControlDB.settings end

    local title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", view, "TOPLEFT", 16, -12)
    title:SetText(L["Configuración"])

    -- Las secciones no caben en la ventana: van dentro de un área con desplazamiento
    local scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -30)
    scroll:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -26, 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(870, 1282)
    scroll:SetScrollChild(content)

    -- Subpestaña Normas de la hermandad: página aparte (sin desplazamiento), solo oficiales
    local rulesPage = CreateFrame("Frame", nil, view)
    rulesPage:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -30)
    rulesPage:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 6)
    rulesPage:Hide()
    local configMode = "general"
    local configTabs = {}
    local function ShowConfigMode(mode)
        configMode = mode
        scroll:SetShown(mode == "general")
        rulesPage:SetShown(mode == "rules")
        for _, btn in ipairs(configTabs) do btn:SetEnabled(btn.mode ~= mode) end
    end
    for i, info in ipairs({ { "general", "General" }, { "rules", "Normas de la hermandad" } }) do
        local btn = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
        btn:SetText(L[info[2]])
        local textWidth = btn:GetFontString() and btn:GetFontString():GetStringWidth() or 0
        btn:SetSize(math.max(90, math.ceil(textWidth + 24)), 22)
        if i == 1 then
            btn:SetPoint("LEFT", title, "RIGHT", 20, 0)
        else
            btn:SetPoint("LEFT", configTabs[i - 1], "RIGHT", 4, 0)
        end
        btn.mode = info[1]
        btn:SetScript("OnClick", function() ShowConfigMode(info[1]) end)
        configTabs[i] = btn
    end

    -- Cada sección es un panel con franja de título (y como si empezara bajo el título de la vista)
    local function Section(titleText, x, y, width, height)
        local box = CreateColoredPanel(content, titleText, PANEL_COLORS.blue, width, height)
        box:SetPoint("TOPLEFT", content, "TOPLEFT", x, y + 30)
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
    -- 9.1 Hermandad: Discord e icono (los definen los oficiales y se comparten)
    -- ---------------------------------------------------------------------
    local guildBox = Section(L["Hermandad"], 10, -36, 560, 266)
    local G = addonTable.GuildConfig
    local officerOnly = {}   -- controles que solo pueden usar los oficiales

    local readOnlyNote = guildBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    readOnlyNote:SetPoint("TOPRIGHT", guildBox, "TOPRIGHT", -12, -12)
    readOnlyNote:SetText(L["Lo definen los oficiales"])

    local discordLabel = Label(guildBox, L["Enlace de Discord (se muestra un botón junto al nombre)"], 14, -32)
    local discordInput = Input(guildBox, 300, discordLabel, L["https://discord.gg/..."], 120)

    local function SaveDiscord()
        discordInput:ClearFocus()
        if G then G.Set(strtrim(discordInput:GetText() or ""), nil) end
    end
    local btnSaveDiscord = Button(guildBox, L["Guardar"], 80, discordInput, SaveDiscord)
    local btnClearDiscord = Button(guildBox, L["Quitar"], 70, btnSaveDiscord, function()
        discordInput:SetText("")
        SaveDiscord()
    end)
    discordInput:SetScript("OnEnterPressed", SaveDiscord)
    discordInput:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:SetText(settings().discordLink or "") end)
    for _, w in ipairs({ discordInput, btnSaveDiscord, btnClearDiscord }) do table.insert(officerOnly, w) end

    local iconLabel = Label(guildBox, L["Icono de la hermandad"], 14, -84)
    local iconPreview = CreateGuildIconHolder(guildBox, 40)
    iconPreview:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 0, -6)

    local iconInput = CreateFrame("EditBox", nil, guildBox, "InputBoxTemplate")
    iconInput:SetSize(220, 20)
    iconInput:SetAutoFocus(false)

    local function RefreshIconFields()
        local value = settings().guildIcon
        iconInput:SetText(value == "tabard" and "" or tostring(value or ""))
        iconPreview:SetGuildIcon(value)
    end

    local function SaveIcon(value)
        iconInput:ClearFocus()
        if not G then return end
        if not G.CleanIcon(value) then
            PrintGC(L["|cFFFF3333Icono no válido: escribe un ID numérico o una ruta de textura.|r"])
            return
        end
        G.Set(nil, value)
        RefreshIconFields()
    end

    local btnTabard = CreateFrame("Button", nil, guildBox, "UIPanelButtonTemplate")
    btnTabard:SetSize(150, 22)
    btnTabard:SetPoint("TOPLEFT", iconPreview, "TOPRIGHT", 12, 2)
    btnTabard:SetText(L["Emblema del juego"])
    btnTabard:SetScript("OnClick", function() SaveIcon("tabard") end)

    local btnPicker = CreateFrame("Button", nil, guildBox, "UIPanelButtonTemplate")
    btnPicker:SetSize(170, 22)
    btnPicker:SetPoint("LEFT", btnTabard, "RIGHT", 6, 0)
    btnPicker:SetText(L["Iconos del juego..."])
    btnPicker:SetScript("OnClick", function() uiModule.ShowIconPicker(function(value) SaveIcon(value) end) end)

    iconInput:SetPoint("TOPLEFT", btnTabard, "BOTTOMLEFT", 6, -4)
    local iconPlaceholder = iconInput:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    iconPlaceholder:SetPoint("LEFT", iconInput, "LEFT", 2, 0)
    iconPlaceholder:SetText(L["ID o ruta de tu imagen"])
    local btnApplyIcon = Button(guildBox, L["Aplicar"], 80, iconInput, function() SaveIcon(strtrim(iconInput:GetText() or "")) end)
    iconInput:SetScript("OnEnterPressed", function(self) SaveIcon(strtrim(self:GetText() or "")) end)
    iconInput:SetScript("OnEscapePressed", function(self) self:ClearFocus(); RefreshIconFields() end)
    iconInput:SetScript("OnTextChanged", function(self, userInput)
        iconPlaceholder:SetShown((self:GetText() or "") == "")
        if userInput and G and G.CleanIcon(strtrim(self:GetText() or "")) then
            iconPreview:SetGuildIcon(G.CleanIcon(strtrim(self:GetText() or "")))
        end
    end)
    for _, w in ipairs({ btnTabard, btnPicker, iconInput, btnApplyIcon }) do table.insert(officerOnly, w) end

    -- Iconos rápidos (el resto, en "Iconos del juego...")
    for i, iconName in ipairs(PRESET_ICONS) do
        if i > 17 then break end
        local btn = CreateFrame("Button", nil, guildBox)
        btn:SetSize(26, 26)
        btn:SetPoint("TOPLEFT", guildBox, "TOPLEFT", 14 + (i - 1) * 31, -156)
        btn:SetNormalTexture("Interface\\Icons\\" .. iconName)
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        btn:SetScript("OnClick", function() SaveIcon("Interface\\Icons\\" .. iconName) end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(iconName, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(officerOnly, btn)
    end

    local iconHint = guildBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    iconHint:SetPoint("TOPLEFT", guildBox, "TOPLEFT", 14, -190)
    iconHint:SetWidth(532)
    iconHint:SetJustifyH("LEFT")
    iconHint:SetText(L["Imagen propia: copia un archivo TGA o BLP de 64×64 o 128×128 en Interface\\AddOns\\GuildControl\\Media\\ (reinicia el juego) y escribe su ruta, p. ej. Interface\\AddOns\\GuildControl\\Media\\logo. Cada jugador necesita el archivo para verla."])
    table.insert(officerOnly, iconHint)

    -- Permiso compartido: los jugadores pueden usar la pestaña Invitar
    local chkPlayerInvite = CreateFrame("CheckButton", "GC_CfgPlayerInvite", guildBox, "UICheckButtonTemplate")
    chkPlayerInvite:SetPoint("TOPLEFT", guildBox, "TOPLEFT", 10, -226)
    _G[chkPlayerInvite:GetName() .. "Text"]:SetText(L["Los jugadores pueden usar Invitar (reclutar)"])
    chkPlayerInvite:SetScript("OnClick", function(self)
        if G and G.SetPlayerInvite then G.SetPlayerInvite(self:GetChecked()) end
        uiModule.ApplyProfile()
    end)
    chkPlayerInvite:SetScript("OnShow", function(self) self:SetChecked(settings().playerInvite == true) end)

    -- Los jugadores ven lo que definieron los oficiales, sin poder cambiarlo
    local function ApplyGuildEditPermissions()
        local isOfficer = not addonTable.Profiles or addonTable.Profiles.IsOfficer()
        readOnlyNote:SetShown(not isOfficer)
        for _, w in ipairs(officerOnly) do w:SetShown(isOfficer) end
        discordInput:Show()
        discordInput:SetEnabled(isOfficer)
    end
    -- ---------------------------------------------------------------------
    -- 9.1b Normas de la hermandad (las escriben los oficiales y todos las ven en el Resumen)
    -- ---------------------------------------------------------------------
    local rulesBox = CreateColoredPanel(rulesPage, L["Normas de la hermandad"], PANEL_COLORS.blue, 880, 470)
    rulesBox:SetPoint("TOPLEFT", rulesPage, "TOPLEFT", 10, -6)
    local rulesHint = Label(rulesBox, L["Se ven en la vista previa del Resumen y se envían a la hermandad. Sin colores; Intro salta de línea. Los iconos y las viñetas se ven como en el chat."], 14, -32)
    local rulesFrame = CreateBackdropBox(rulesBox, 852, 340, "TOPLEFT", rulesHint, "BOTTOMLEFT", 0, -34)
    local rulesScroll = CreateFrame("ScrollFrame", nil, rulesFrame, "UIPanelScrollFrameTemplate")
    rulesScroll:SetPoint("TOPLEFT", rulesFrame, "TOPLEFT", 8, -8)
    rulesScroll:SetPoint("BOTTOMRIGHT", rulesFrame, "BOTTOMRIGHT", -28, 8)
    local rulesInput = CreateFrame("EditBox", nil, rulesScroll)
    rulesInput:SetWidth(812)
    rulesInput:SetMultiLine(true)
    rulesInput:SetFontObject(GameFontHighlightSmall)
    rulesInput:SetAutoFocus(false)
    rulesInput:SetMaxLetters(0)
    if rulesInput.SetMaxBytes then rulesInput:SetMaxBytes(((G and G.RULES_MAX) or 1500) + 1) end
    rulesScroll:SetScrollChild(rulesInput)
    rulesFrame:EnableMouse(true)
    rulesFrame:SetScript("OnMouseDown", function() rulesInput:SetFocus() end)
    rulesInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if ScrollingEdit_OnCursorChanged then rulesInput:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged) end
    if ScrollingEdit_OnUpdate then
        rulesInput:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, rulesScroll) end)
    end
    -- Barra de iconos de banda ({rt1}...{rt8}) y viñeta (•) encima del texto
    local rulesTools = CreateFrame("Frame", nil, rulesBox)
    rulesTools:SetSize(852, 22)
    rulesTools:SetPoint("BOTTOMLEFT", rulesFrame, "TOPLEFT", 0, 4)
    local btnBullet = CreateFrame("Button", nil, rulesTools, "UIPanelButtonTemplate")
    btnBullet:SetSize(90, 22)
    btnBullet:SetPoint("LEFT", rulesTools, "LEFT", 0, 0)
    btnBullet:SetText("• " .. L["Viñeta"])
    btnBullet:SetScript("OnClick", function()
        rulesInput:SetFocus()
        -- Al principio de una línea va la viñeta; si no, salta de línea antes
        local text, pos = rulesInput:GetText() or "", rulesInput:GetCursorPosition()
        local before = string.sub(text, pos, pos)
        rulesInput:Insert((pos == 0 or before == "\n") and "• " or "\n• ")
    end)
    btnBullet:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Viñeta"], 1, 1, 1)
        GameTooltip:AddLine(L["Empieza una línea con una viñeta (•) donde está el cursor."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnBullet:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local iconsLabel = rulesTools:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    iconsLabel:SetPoint("LEFT", btnBullet, "RIGHT", 16, 0)
    iconsLabel:SetText(L["Iconos:"])
    for i, iconName in ipairs(RAID_ICONS) do
        local btn = CreateFrame("Button", nil, rulesTools)
        btn:SetSize(18, 18)
        btn:SetPoint("LEFT", iconsLabel, "RIGHT", 6 + (i - 1) * 22, 0)
        btn:SetNormalTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i)
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        btn:SetScript("OnClick", function()
            rulesInput:SetFocus()
            rulesInput:Insert("{rt" .. i .. "}")
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L[iconName] .. L["  {rt"] .. i .. "}", 1, 1, 1)
            GameTooltip:AddLine(L["Clic para insertarlo en el mensaje"], 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local btnRulesPreview = CreateFrame("Button", nil, rulesTools, "UIPanelButtonTemplate")
    btnRulesPreview:SetSize(110, 22)
    btnRulesPreview:SetPoint("RIGHT", rulesTools, "RIGHT", 0, 0)
    btnRulesPreview:SetText(L["Vista previa"])
    btnRulesPreview:SetScript("OnClick", function()
        SetPreviewText(L["|cFFFFD100Normas de la hermandad|r"] .. "\n\n" .. RenderRaidIcons(string.gsub(rulesInput:GetText() or "", "|", "")))
    end)
    btnRulesPreview:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Vista previa"], 1, 1, 1)
        GameTooltip:AddLine(L["Muestra a la derecha cómo se verán las normas, con los iconos, sin guardarlas."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnRulesPreview:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local rulesCount = rulesBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rulesCount:SetPoint("TOPLEFT", rulesFrame, "BOTTOMLEFT", 2, -8)
    rulesInput:SetScript("OnTextChanged", function(self)
        rulesCount:SetText(string.format(L["%d / %d bytes"], #(self:GetText() or ""), (G and G.RULES_MAX) or 1500))
        rulesScroll:UpdateScrollChildRect()
    end)
    local btnSaveRules = CreateFrame("Button", nil, rulesBox, "UIPanelButtonTemplate")
    btnSaveRules:SetSize(110, 22)
    btnSaveRules:SetPoint("TOPRIGHT", rulesFrame, "BOTTOMRIGHT", 0, -4)
    btnSaveRules:SetText(L["Guardar"])
    btnSaveRules:SetScript("OnClick", function()
        rulesInput:ClearFocus()
        if G and G.SetRules(rulesInput:GetText() or "") then
            rulesInput:SetText(G.GetRules())
            PrintGC(L["Normas guardadas y enviadas a la hermandad."])
        end
    end)
    local btnUndoRules = CreateFrame("Button", nil, rulesBox, "UIPanelButtonTemplate")
    btnUndoRules:SetSize(110, 22)
    btnUndoRules:SetPoint("RIGHT", btnSaveRules, "LEFT", -6, 0)
    btnUndoRules:SetText(L["Deshacer"])
    btnUndoRules:SetScript("OnClick", function()
        rulesInput:ClearFocus()
        rulesInput:SetText(G and G.GetRules() or "")
    end)

    if G then G.AddListener(function()
        if not view:IsShown() then return end
        discordInput:SetText(settings().discordLink or "")
        RefreshIconFields()
        if not rulesInput:HasFocus() then rulesInput:SetText(G.GetRules()) end
    end) end

    -- ---------------------------------------------------------------------
    -- 9.2 Ventana
    -- ---------------------------------------------------------------------
    local windowBox = Section(L["Ventana"], 578, -36, 312, 266)

    local chkOnTop = CreateFrame("CheckButton", "GC_CfgWindowOnTop", windowBox, "UICheckButtonTemplate")
    chkOnTop:SetPoint("TOPLEFT", windowBox, "TOPLEFT", 10, -30)
    _G[chkOnTop:GetName() .. "Text"]:SetText(L["Siempre por encima"])
    chkOnTop:SetScript("OnClick", function(self)
        settings().windowOnTop = self:GetChecked() and true or false
        uiModule.ApplyWindowStrata()
    end)

    local onTopHint = windowBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    onTopHint:SetPoint("TOPLEFT", chkOnTop, "BOTTOMLEFT", 4, -2)
    onTopHint:SetWidth(284)
    onTopHint:SetJustifyH("LEFT")
    onTopHint:SetText(L["Muestra la ventana del addon por encima de las barras de acción y otros botones del juego."])

    -- Idioma de la interfaz: se aplica al recargar (/reload)
    local langLabel = windowBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    langLabel:SetPoint("TOPLEFT", onTopHint, "BOTTOMLEFT", -4, -14)
    langLabel:SetText(L["Idioma (se aplica al recargar)"])

    local dropLanguage = CreateFrame("DropdownButton", "GC_CfgLanguage", windowBox, "WowStyle1DropdownTemplate")
    dropLanguage:SetPoint("TOPLEFT", langLabel, "BOTTOMLEFT", 0, -4)
    dropLanguage:SetWidth(170)

    local btnReloadLang = CreateFrame("Button", nil, windowBox, "UIPanelButtonTemplate")
    btnReloadLang:SetSize(100, 22)
    btnReloadLang:SetPoint("LEFT", dropLanguage, "RIGHT", 8, 0)
    btnReloadLang:SetText(L["Recargar"])
    btnReloadLang:SetScript("OnClick", function() ReloadUI() end)
    btnReloadLang:Hide()

    local function LanguageName(code)
        if code == "auto" then return L["Automático (el del juego)"] end
        for _, lang in ipairs(addonTable.GetLanguages()) do
            if lang.code == code then return lang.name end
        end
        return code
    end
    dropLanguage:SetupMenu(function(_, root)
        local codes = { "auto" }
        for _, lang in ipairs(addonTable.GetLanguages()) do table.insert(codes, lang.code) end
        for _, code in ipairs(codes) do
            root:CreateRadio(LanguageName(code), function() return (settings().language or "auto") == code end,
                function()
                    settings().language = code
                    dropLanguage:SetText(LanguageName(code))
                    btnReloadLang:Show()
                end)
        end
    end)
    dropLanguage:SetText(LanguageName(settings().language or "auto"))

    local chkNotify = CreateFrame("CheckButton", "GC_CfgPersonalNotify", windowBox, "UICheckButtonTemplate")
    chkNotify:SetPoint("TOPLEFT", dropLanguage, "BOTTOMLEFT", -4, -8)
    _G[chkNotify:GetName() .. "Text"]:SetText(L["Avisos personales en pantalla"])
    chkNotify:SetScript("OnClick", function(self) settings().personalNotify = self:GetChecked() and true or false end)
    chkNotify:SetScript("OnShow", function(self) self:SetChecked(settings().personalNotify ~= false) end)

    local chkCombat = CreateFrame("CheckButton", "GC_CfgCloseInCombat", windowBox, "UICheckButtonTemplate")
    chkCombat:SetPoint("TOPLEFT", chkNotify, "BOTTOMLEFT", 0, 2)
    _G[chkCombat:GetName() .. "Text"]:SetText(L["Cerrar al entrar en combate"])
    chkCombat:SetScript("OnClick", function(self) settings().closeInCombat = self:GetChecked() and true or false end)
    chkCombat:SetScript("OnShow", function(self) self:SetChecked(settings().closeInCombat == true) end)

    local chkMinimap = CreateFrame("CheckButton", "GC_CfgHideMinimap", windowBox, "UICheckButtonTemplate")
    chkMinimap:SetPoint("TOPLEFT", chkCombat, "BOTTOMLEFT", 0, 2)
    _G[chkMinimap:GetName() .. "Text"]:SetText(L["Ocultar el botón del minimapa"])
    chkMinimap:SetScript("OnClick", function(self)
        GuildControlDB.minimap.hide = self:GetChecked() and true or false
        if addonTable.ApplyMinimapButton then addonTable.ApplyMinimapButton() end
        if GuildControlDB.minimap.hide then PrintGC(L["Botón del minimapa oculto. Abre GuildControl con /gct."]) end
    end)
    chkMinimap:SetScript("OnShow", function(self) self:SetChecked(GuildControlDB.minimap.hide == true) end)

    local aboutText = windowBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    aboutText:SetPoint("BOTTOMLEFT", windowBox, "BOTTOMLEFT", 14, 12)
    aboutText:SetWidth(284)
    aboutText:SetJustifyH("LEFT")
    aboutText:SetText(L["GuildControl v"] .. addonTable.VERSION .. L[" · Autor: Forxaken\nEl perfil de oficial y el rango mínimo se configuran en Mi perfil."])

    -- ---------------------------------------------------------------------
    -- 9.3 Saludo automático: mensaje, tiempos y palabras
    -- ---------------------------------------------------------------------
    local greetBox = Section(L["Saludo automático"], 10, -278, 880, 228)

    local chkGreet = CreateFrame("CheckButton", "GC_CfgAutoGreet", greetBox, "UICheckButtonTemplate")
    chkGreet:SetPoint("TOPLEFT", greetBox, "TOPLEFT", 10, -28)
    _G[chkGreet:GetName() .. "Text"]:SetText(L["Responder a quien salude al conectarse"])
    chkGreet:SetScript("OnClick", function(self) settings().autoGreet = self:GetChecked() and true or false end)

    local greetLabel = Label(greetBox, L["Mensaje de respuesta"], 14, -66)
    local greetInput = Input(greetBox, 220, greetLabel, nil, 120)

    local function SaveGreet()
        local text = strtrim(greetInput:GetText() or "")
        if text == "" then text = L["¡Hola, {nombre}!"] end
        settings().greetMessage = text
        greetInput:SetText(text)
        greetInput:ClearFocus()
    end
    Button(greetBox, L["Guardar"], 70, greetInput, SaveGreet)
    greetInput:SetScript("OnEnterPressed", SaveGreet)
    greetInput:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:SetText(settings().greetMessage or "") end)

    local greetHint = greetBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    greetHint:SetPoint("TOPLEFT", greetInput, "BOTTOMLEFT", -6, -8)
    greetHint:SetWidth(300)
    greetHint:SetJustifyH("LEFT")
    greetHint:SetText(L["{nombre} se sustituye por quien saluda. Solo se responde a quien acaba de conectarse y aún no ha sido saludado."])

    -- Columna central: tiempos
    local timesTitle = Label(greetBox, L["|cFFFFD100Tiempos|r"], 350, -32)

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

    local delayInput = NumberSetting(timesTitle, 6, -10, L["Segundos de espera antes de responder (1-60)"], "greetDelay", 1, 60)
    local cooldownInput = NumberSetting(delayInput, 0, -16, L["Minutos sin volver a saludar a la misma persona (1-1440)"], "greetCooldown", 1, 1440)
    local loginInput = NumberSetting(cooldownInput, 0, -16, L["Minutos tras conectarse en los que se le saluda (1-30)"], "greetLoginWindow", 1, 30)

    local timesHint = greetBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    timesHint:SetPoint("TOPLEFT", loginInput, "BOTTOMLEFT", -6, -12)
    timesHint:SetWidth(250)
    timesHint:SetJustifyH("LEFT")
    timesHint:SetText(L["A la espera se suman hasta 4 s aleatorios para que, si varios usan GuildControl, solo responda uno."])

    -- Columna derecha: palabras de saludo
    local wordsTitle = Label(greetBox, L["|cFFFFD100Palabras de saludo|r"], 630, -32)
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
    wordsHint:SetText(L["Separadas por comas; el mensaje debe empezar por una. Vacío = lista por defecto."])

    -- ---------------------------------------------------------------------
    -- 9.4 Bienvenida a quien entra nuevo en la hermandad
    -- ---------------------------------------------------------------------
    local welcomeBox = Section(L["Bienvenida a nuevos miembros"], 10, -512, 880, 112)

    local chkWelcome = CreateFrame("CheckButton", "GC_CfgWelcomeNew", welcomeBox, "UICheckButtonTemplate")
    chkWelcome:SetPoint("TOPLEFT", welcomeBox, "TOPLEFT", 10, -28)
    _G[chkWelcome:GetName() .. "Text"]:SetText(L["Dar la bienvenida en el chat de hermandad a quien se une"])
    chkWelcome:SetScript("OnClick", function(self) settings().welcomeNew = self:GetChecked() and true or false end)

    local welcomeInput = CreateFrame("EditBox", nil, welcomeBox, "InputBoxTemplate")
    welcomeInput:SetSize(560, 20)
    welcomeInput:SetPoint("TOPLEFT", chkWelcome, "BOTTOMLEFT", 8, -4)
    welcomeInput:SetAutoFocus(false)
    welcomeInput:SetMaxLetters(200)
    local function SaveWelcome()
        local text = strtrim(welcomeInput:GetText() or "")
        if text ~= "" then settings().welcomeMessage = text end
        welcomeInput:SetText(settings().welcomeMessage or "")
        welcomeInput:ClearFocus()
    end
    Button(welcomeBox, L["Guardar"], 70, welcomeInput, SaveWelcome)
    welcomeInput:SetScript("OnEnterPressed", SaveWelcome)
    welcomeInput:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:SetText(settings().welcomeMessage or "") end)

    local welcomeHint = welcomeBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    welcomeHint:SetPoint("TOPLEFT", welcomeInput, "BOTTOMLEFT", -6, -6)
    welcomeHint:SetWidth(850)
    welcomeHint:SetJustifyH("LEFT")
    welcomeHint:SetText(L["{nombre} y {hermandad} se sustituyen. A quien entra nuevo no se le aplica el saludo automático. Si varios usan GuildControl, solo responde uno."])

    -- ---------------------------------------------------------------------
    -- 9.5 Canales para publicar el mensaje de reclutamiento (Invitar)
    -- ---------------------------------------------------------------------
    local channelsBox = Section(L["Canales de reclutamiento"], 10, -630, 430, 130)
    local CHANNEL_FIELDS = {
        { key = "general", label = "Canal General:" },
        { key = "trade", label = "Canal de Comercio:" },
        { key = "world", label = "Canal Mundo:" },
    }
    local channelInputs = {}
    for i, field in ipairs(CHANNEL_FIELDS) do
        local label = Label(channelsBox, L[field.label], 14, -32 - (i - 1) * 26)
        local input = CreateFrame("EditBox", nil, channelsBox, "InputBoxTemplate")
        input:SetSize(180, 20)
        input:SetPoint("LEFT", label, "LEFT", 140, 0)
        input:SetAutoFocus(false)
        input:SetMaxLetters(40)
        local key = field.key
        local function SaveChannel(self)
            local text = strtrim(self:GetText() or "")
            if text ~= "" then settings().recruitChannels[key] = text end
            self:SetText(settings().recruitChannels[key] or "")
            self:ClearFocus()
        end
        input:SetScript("OnEnterPressed", SaveChannel)
        input:SetScript("OnEditFocusLost", function(self)
            local text = strtrim(self:GetText() or "")
            if text ~= "" then settings().recruitChannels[key] = text end
        end)
        input:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:SetText(settings().recruitChannels[key] or "") end)
        channelInputs[key] = input
        -- Línea fina entre canales
        if i < #CHANNEL_FIELDS then
            local line = channelsBox:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(1, 1, 1, 0.08)
            line:SetHeight(1)
            line:SetPoint("TOPLEFT", channelsBox, "TOPLEFT", 12, -50 - (i - 1) * 26)
            line:SetPoint("TOPRIGHT", channelsBox, "TOPRIGHT", -12, -50 - (i - 1) * 26)
        end
    end
    local channelsHint = channelsBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    channelsHint:SetPoint("TOPLEFT", channelsBox, "TOPLEFT", 14, -108)
    channelsHint:SetWidth(400)
    channelsHint:SetJustifyH("LEFT")
    channelsHint:SetText(L["El nombre con el que empieza el canal en tu chat (Invitar > Publicar en)."])

    -- ---------------------------------------------------------------------
    -- 9.6 Sonido al conectarse un favorito
    -- ---------------------------------------------------------------------
    local soundBox = Section(L["Aviso de favoritos"], 448, -630, 442, 130)
    local F = addonTable.Favorites

    local chkSound = CreateFrame("CheckButton", "GC_CfgFavoriteSound", soundBox, "UICheckButtonTemplate")
    chkSound:SetPoint("TOPLEFT", soundBox, "TOPLEFT", 10, -28)
    _G[chkSound:GetName() .. "Text"]:SetText(L["Sonido cuando se conecta un favorito"])
    chkSound:SetScript("OnClick", function(self) settings().favoriteSoundEnabled = self:GetChecked() and true or false end)

    local function SoundLabel(key)
        for _, sound in ipairs(F and F.SOUNDS or {}) do
            if sound.key == key then return L[sound.label] end
        end
        return key or ""
    end

    local dropSound = CreateFrame("DropdownButton", "GC_CfgFavoriteSoundSelect", soundBox, "WowStyle1DropdownTemplate")
    dropSound:SetPoint("TOPLEFT", chkSound, "BOTTOMLEFT", 6, -6)
    dropSound:SetWidth(220)
    dropSound:SetupMenu(function(_, root)
        for _, sound in ipairs(F and F.SOUNDS or {}) do
            local key = sound.key
            root:CreateRadio(L[sound.label], function() return settings().favoriteSound == key end, function()
                settings().favoriteSound = key
                dropSound:SetText(SoundLabel(key))
                if F then F.PlaySound(key) end
            end)
        end
    end)

    local btnTestSound = CreateFrame("Button", nil, soundBox, "UIPanelButtonTemplate")
    btnTestSound:SetSize(90, 22)
    btnTestSound:SetPoint("LEFT", dropSound, "RIGHT", 8, 0)
    btnTestSound:SetText(L["Probar"])
    btnTestSound:SetScript("OnClick", function() if F then F.PlaySound(settings().favoriteSound) end end)

    local soundHint = soundBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    soundHint:SetPoint("TOPLEFT", dropSound, "BOTTOMLEFT", 0, -8)
    soundHint:SetWidth(410)
    soundHint:SetJustifyH("LEFT")
    soundHint:SetText(L["Los favoritos se marcan con clic derecho en Miembros o en la pestaña Favoritos."])

    -- ---------------------------------------------------------------------
    -- 9.6 Canales del chat: canales de idioma y chat de oficiales
    -- ---------------------------------------------------------------------
    local chatChannelsBox = Section(L["Canales del chat"], 10, -796, 880, 260)
    local CHANNEL_COLUMNS = { game = 330, tab = 600 }
    local function ColumnHeader(text, column)
        local fs = chatChannelsBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", chatChannelsBox, "TOPLEFT", CHANNEL_COLUMNS[column], -30)
        fs:SetText(text)
    end
    ColumnHeader(L["Ver en el chat del juego"], "game")
    ColumnHeader(L["Pestaña en GuildControl"], "tab")

    local CHANNEL_ROWS = {
        { key = "guild", label = L["Hermandad"], tabOnly = true },
        { key = "whisper", label = L["Susurros"], tabOnly = true },
        { key = "raid", label = L["Banda"], tabOnly = true },
        { key = "party", label = L["Grupo (y mazmorra)"], tabOnly = true },
        { key = "english", label = L["lobosenglish (inglés)"] },
        { key = "spanish", label = L["lobosespañol (español)"], noTab = true },
        { key = "officer", label = L["Oficiales (chat del juego)"], officer = true },
    }
    local channelChecks, officerRow = {}, {}
    local function Chat() return addonTable.GuildChat end
    local function RefreshChannelChecks()
        local isOfficerChat = Chat() and Chat().CanUseOfficerChat and Chat().CanUseOfficerChat() or false
        for _, widget in ipairs(officerRow) do widget:SetShown(isOfficerChat) end
        for _, chk in ipairs(channelChecks) do chk:SetChecked(chk.getter() and true or false) end
    end
    for i, row in ipairs(CHANNEL_ROWS) do
        local y = -46 - (i - 1) * 26
        local nameText = chatChannelsBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameText:SetPoint("TOPLEFT", chatChannelsBox, "TOPLEFT", 16, y - 6)
        nameText:SetText(row.label)
        if row.officer then table.insert(officerRow, nameText) end
        local function Check(column, getter, setter)
            local chk = CreateFrame("CheckButton", nil, chatChannelsBox, "UICheckButtonTemplate")
            chk:SetSize(26, 26)
            chk:SetPoint("TOPLEFT", chatChannelsBox, "TOPLEFT", CHANNEL_COLUMNS[column], y)
            chk.getter = getter
            chk:SetScript("OnClick", function(self)
                if Chat() then setter(self:GetChecked() and true or false) end
                RefreshChannelChecks()
            end)
            table.insert(channelChecks, chk)
            if row.officer then table.insert(officerRow, chk) end
        end
        if row.tabOnly then
            -- Canales del juego: solo se elige si se ve su pestaña
        elseif row.officer then
            Check("game", function() return Chat() and Chat().ShowsInGame("officer") end,
                function(value) Chat().SetOfficerInGame(value) end)
        else
            Check("game", function() return Chat() and Chat().ShowsInGame(row.key) end,
                function(value) Chat().SetChannelInGame(row.key, value) end)
        end
        if not row.noTab then
            Check("tab", function() return Chat() and Chat().ShowsTab(row.key) end,
                function(value) Chat().SetChannelTab(row.key, value) end)
        end
    end

    local channelsHint = chatChannelsBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    channelsHint:SetPoint("TOPLEFT", chatChannelsBox, "TOPLEFT", 16, -230)
    channelsHint:SetWidth(850)
    channelsHint:SetJustifyH("LEFT")
    channelsHint:SetText(L["Entras solo en el canal del idioma de tu juego (lobosenglish o lobosespañol). El número (/5, /6...) lo pone cada cliente y puede ser distinto: compruébalo con /chatlist. Desde el chat de GuildControl se escribe por nombre."])

    -- ---------------------------------------------------------------------
    -- 9.7 Insignias y premios DKP (solo oficiales)
    -- ---------------------------------------------------------------------
    -- Las de serie (se pueden quitar del premio y restablecer) y las nuevas que crean los
    -- oficiales (se dan a mano a cada jugador y se pueden borrar). Las filas se crean según
    -- haga falta y la sección crece con ellas.
    local badgeBox = Section(L["Insignias y premios DKP"], 10, -1062, 880, 214)
    local badgeRewardRows = {}
    local RefreshBadgeRewards

    -- Busca un miembro por nombre (con o sin reino, sin distinguir mayúsculas)
    local function FindMemberName(text)
        text = strtrim(text or "")
        if text == "" then return nil end
        local key = addonTable.NormalizeName and addonTable.NormalizeName(text) or text
        if GuildControlDB.members[key] then return key end
        local wanted = string.lower(string.match(text, "^([^%-%s]+)") or text)
        for name in pairs(GuildControlDB.members) do
            if string.lower(string.match(name, "^([^-]+)") or name) == wanted then return name end
        end
        return nil
    end

    StaticPopupDialogs["GUILDCONTROL_GIVE_BADGE"] = {
        text = "%s",
        button1 = ACCEPT,
        button2 = CANCEL,
        hasEditBox = true,
        maxLetters = 60,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnShow = function(self)
            local box = self.EditBox or self.editBox
            if box then box:SetText(""); box:SetFocus() end
        end,
        OnAccept = function(self, data)
            local box = self.EditBox or self.editBox
            local D = addonTable.Dkp
            local name = FindMemberName(box and box:GetText())
            if not name then
                PrintGC(L["|cFFFF3333No hay ningún miembro con ese nombre.|r"])
            elseif D and data and D.SetBadgeHolder(data, name, true) then
                PrintGC(L["Insignia dada a "] .. name .. ".")
            end
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            StaticPopupDialogs["GUILDCONTROL_GIVE_BADGE"].OnAccept(parent, parent.data)
            parent:Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    }

    -- Ventana para crear una insignia: nombre, descripción, icono y premio
    local newBadgeFrame = nil
    local function ShowNewBadgeDialog()
        if not newBadgeFrame then
            local frame = CreateFrame("Frame", "GuildControlNewBadgeFrame", UIParent, "BasicFrameTemplateWithInset")
            frame:SetSize(420, 230)
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
            frame:SetFrameStrata("HIGH")   -- por debajo del selector de iconos
            frame:SetToplevel(true)
            frame:SetMovable(true)
            frame:EnableMouse(true)
            frame:RegisterForDrag("LeftButton")
            frame:SetScript("OnDragStart", frame.StartMoving)
            frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
            tinsert(UISpecialFrames, "GuildControlNewBadgeFrame")
            local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
            title:SetText(L["Nueva insignia"])

            local function Field(label, y, width, maxLetters)
                local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 84, y)
                fs:SetText(label)
                local input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
                input:SetSize(width, 20)
                input:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 6, -2)
                input:SetAutoFocus(false)
                input:SetMaxLetters(maxLetters)
                input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                return input
            end
            frame.nameInput = Field(L["Nombre"], -34, 300, 30)
            frame.descInput = Field(L["Descripción (por qué se da)"], -78, 300, 100)
            frame.rewardInput = Field(L["Premio (DKP)"], -122, 70, 4)
            frame.rewardInput:SetNumeric(true)

            -- Icono: botón con la textura elegida, abre el selector de iconos
            frame.iconButton = CreateFrame("Button", nil, frame)
            frame.iconButton:SetSize(56, 56)
            frame.iconButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -40)
            frame.iconButton.tex = frame.iconButton:CreateTexture(nil, "ARTWORK")
            frame.iconButton.tex:SetAllPoints()
            frame.iconButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            local iconHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            iconHint:SetPoint("TOP", frame.iconButton, "BOTTOM", 0, -4)
            iconHint:SetText(L["Icono"])
            frame.iconButton:SetScript("OnClick", function()
                if uiModule.ShowIconPicker then
                    uiModule.ShowIconPicker(function(value)
                        frame.icon = value
                        frame.iconButton.tex:SetTexture(value)
                    end)
                end
            end)

            local btnCreate = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            btnCreate:SetSize(120, 24)
            btnCreate:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
            btnCreate:SetText(L["Crear"])
            btnCreate:SetScript("OnClick", function()
                local D = addonTable.Dkp
                local label = strtrim(frame.nameInput:GetText() or "")
                if label == "" then
                    PrintGC(L["|cFFFF3333Escribe el nombre de la insignia.|r"])
                    return
                end
                if D and D.CreateCustomBadge(label, frame.descInput:GetText(), frame.icon, frame.rewardInput:GetText()) then
                    frame:Hide()
                    RefreshBadgeRewards()
                end
            end)
            newBadgeFrame = frame
        end
        local frame = newBadgeFrame
        frame.icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"
        frame.iconButton.tex:SetTexture(frame.icon)
        frame.nameInput:SetText("")
        frame.descInput:SetText("")
        frame.rewardInput:SetText("10")
        frame:Show()
        frame.nameInput:SetFocus()
    end

    local function BadgeRewardRow(i)
        local row = badgeRewardRows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, badgeBox)
        row:SetSize(850, 26)
        row:SetPoint("TOPLEFT", badgeBox, "TOPLEFT", 14, -32 - (i - 1) * 28)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.label:SetWidth(130)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.desc = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.desc:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
        row.desc:SetWidth(320)
        row.desc:SetJustifyH("LEFT")
        row.desc:SetWordWrap(false)
        row.input = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        row.input:SetSize(50, 20)
        row.input:SetPoint("LEFT", row.desc, "RIGHT", 12, 0)
        row.input:SetAutoFocus(false)
        row.input:SetNumeric(true)
        row.input:SetMaxLetters(4)
        row.unit = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.unit:SetPoint("LEFT", row.input, "RIGHT", 6, 0)
        row.unit:SetText("DKP")
        local function SaveAmount(self)
            local D = addonTable.Dkp
            local key = row.badge and row.badge.key
            if D and key and D.GetBadgeRewards()[key] and tonumber(self:GetText()) ~= D.GetBadgeRewards()[key] then
                D.SetBadgeReward(key, self:GetText())
            end
        end
        row.input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        row.input:SetScript("OnEditFocusLost", function(self) SaveAmount(self); RefreshBadgeRewards() end)
        row.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        -- De serie: quitar del premio o volver a añadir. Nueva: borrar (con segundo clic).
        row.toggle = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.toggle:SetSize(80, 22)
        row.toggle:SetPoint("LEFT", row.unit, "RIGHT", 12, 0)
        row.toggle:SetScript("OnClick", function(self)
            local D = addonTable.Dkp
            local badge = row.badge
            if not D or not badge then return end
            if badge.custom then
                if GetTime() < (self.armedUntil or 0) then
                    self.armedUntil = 0
                    D.DeleteCustomBadge(badge.key)
                else
                    self.armedUntil = GetTime() + 4
                    self:SetText(L["|cFFFF3333¿Seguro?|r"])
                    C_Timer.After(4, function() if GetTime() >= (self.armedUntil or 0) then RefreshBadgeRewards() end end)
                    return
                end
            elseif D.GetBadgeRewards()[badge.key] then
                D.RemoveBadgeReward(badge.key)
            else
                D.SetBadgeReward(badge.key, D.DEFAULT_BADGE_REWARDS[badge.key] or 0)
            end
            RefreshBadgeRewards()
        end)
        -- Solo las nuevas: darla a un jugador (también desde el clic derecho en Miembros)
        row.give = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.give:SetSize(80, 22)
        row.give:SetPoint("LEFT", row.toggle, "RIGHT", 6, 0)
        row.give:SetText(L["Dar a…"])
        row.give:SetScript("OnClick", function()
            if not row.badge then return end
            local popup = StaticPopup_Show("GUILDCONTROL_GIVE_BADGE", string.format(L["¿A quién das la insignia %s?"], row.badge.label))
            if popup then popup.data = row.badge.key end
        end)
        badgeRewardRows[i] = row
        return row
    end

    local btnBadgeDefaults = CreateFrame("Button", nil, badgeBox, "UIPanelButtonTemplate")
    btnBadgeDefaults:SetSize(200, 22)
    btnBadgeDefaults:SetPoint("BOTTOMRIGHT", badgeBox, "BOTTOMRIGHT", -14, 12)
    btnBadgeDefaults:SetText(L["Restablecer predeterminadas"])
    btnBadgeDefaults:SetScript("OnClick", function()
        if addonTable.Dkp and addonTable.Dkp.ResetBadgeRewards then addonTable.Dkp.ResetBadgeRewards() end
        RefreshBadgeRewards()
    end)
    local btnNewBadge = CreateFrame("Button", nil, badgeBox, "UIPanelButtonTemplate")
    btnNewBadge:SetSize(140, 22)
    btnNewBadge:SetPoint("RIGHT", btnBadgeDefaults, "LEFT", -6, 0)
    btnNewBadge:SetText(L["Nueva insignia"])
    btnNewBadge:SetScript("OnClick", ShowNewBadgeDialog)

    local badgeHint = badgeBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    badgeHint:SetPoint("BOTTOMLEFT", badgeBox, "BOTTOMLEFT", 16, 12)
    badgeHint:SetPoint("RIGHT", btnNewBadge, "LEFT", -12, 0)
    badgeHint:SetJustifyH("LEFT")

    RefreshBadgeRewards = function()
        local D, PMod = addonTable.Dkp, addonTable.Personal
        if not D or not D.GetBadgeRewards or not PMod or not PMod.GetAllBadges then return end
        local rewards = D.GetBadgeRewards()
        local badges = PMod.GetAllBadges()
        -- Cuántos jugadores tienen cada insignia nueva
        local holders = {}
        for _, badge in ipairs(badges) do
            if badge.custom then
                local count = 0
                for name in pairs(GuildControlDB.members or {}) do
                    if D.HasCustomBadge(name, badge.key) then count = count + 1 end
                end
                holders[badge.key] = count
            end
        end
        for _, row in ipairs(badgeRewardRows) do row:Hide() end
        for i, badge in ipairs(badges) do
            local row = BadgeRewardRow(i)
            row.badge = badge
            local amount = rewards[badge.key]
            row.icon:SetTexture(badge.icon)
            row.icon:SetDesaturated(not amount)
            row.label:SetText((amount and "|cFFFFD100" or "|cFF808080") .. L[badge.label] .. "|r")
            row.desc:SetText((badge.custom and ("|cFF66B3FF" .. string.format(L["Nueva · %d jugador(es)"], holders[badge.key] or 0) .. "|r  ") or "")
                .. L[badge.desc or ""])
            row.input:SetShown(amount ~= nil)
            row.unit:SetShown(amount ~= nil)
            if amount and not row.input:HasFocus() then row.input:SetText(tostring(amount)) end
            row.toggle:SetText(badge.custom and L["Borrar"] or (amount and L["Quitar"] or L["Añadir"]))
            row.give:SetShown(badge.custom == true)
            row:Show()
        end
        badgeBox:SetHeight(28 + #badges * 28 + 50)
        if badgeBox:IsShown() then content:SetHeight(1032 + badgeBox:GetHeight() + 10) end
        badgeHint:SetText((D.IsActive() and "" or L["|cFFFF7F00El sistema de botín no es DKP: no se dan premios.|r "])
            .. L["El premio se da una vez por jugador e insignia; las nuevas se dan con «Dar a…» o con clic derecho en Miembros."])
    end
    if addonTable.Dkp and addonTable.Dkp.AddListener then
        addonTable.Dkp.AddListener(function() if badgeBox:IsVisible() then RefreshBadgeRewards() end end)
    end

    view:SetScript("OnShow", function()
        local s = settings()
        discordInput:SetText(s.discordLink or "")
        RefreshIconFields()
        ApplyGuildEditPermissions()
        -- Distribución según el perfil. Los jugadores no ven la sección Hermandad (Discord, icono
        -- y permisos los ponen los oficiales) y los canales de reclutamiento solo si pueden invitar.
        local officerView = not addonTable.Profiles or addonTable.Profiles.IsOfficer()
        local function Place(box, x, y, width, height)
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", content, "TOPLEFT", x, y + 30)
            if width then box:SetWidth(width) end
            if height then box:SetHeight(height) end
        end
        guildBox:SetShown(officerView)
        badgeBox:SetShown(officerView)
        configTabs[2]:SetShown(officerView)
        configTabs[1]:SetShown(officerView)
        if not officerView or configMode ~= "rules" then ShowConfigMode("general") end
        if officerView and G and not rulesInput:HasFocus() then rulesInput:SetText(G.GetRules()) end
        channelsBox:Show()
        if officerView then
            Place(windowBox, 578, -36, 312, 266)
            Place(greetBox, 10, -308)
            Place(welcomeBox, 10, -542)
            Place(channelsBox, 10, -660, 430)
            Place(soundBox, 448, -660, 442, 130)
            Place(chatChannelsBox, 10, -796)
            Place(badgeBox, 10, -1062)
            content:SetHeight(1282)
        else
            -- Jugador: dos columnas iguales arriba (Ventana | Aviso de favoritos y, si puede
            -- invitar, Canales de reclutamiento debajo, con las dos columnas a la misma altura) y
            -- después, a todo lo ancho, Canales del chat, Saludo automático y Bienvenida
            local canInvite = s.playerInvite == true
            Place(windowBox, 10, -36, 437, 266)
            Place(soundBox, 453, -36, 437, canInvite and 130 or 266)
            channelsBox:SetShown(canInvite)
            if canInvite then Place(channelsBox, 453, -172, 437) end
            Place(chatChannelsBox, 10, -308)
            Place(greetBox, 10, -574)
            Place(welcomeBox, 10, -808)
            content:SetHeight(930)
        end
        chkOnTop:SetChecked(s.windowOnTop)
        RefreshChannelChecks()
        RefreshBadgeRewards()
        chkGreet:SetChecked(s.autoGreet)
        chkWelcome:SetChecked(s.welcomeNew)
        welcomeInput:SetText(s.welcomeMessage or "")
        for key, input in pairs(channelInputs) do input:SetText(s.recruitChannels and s.recruitChannels[key] or "") end
        chkSound:SetChecked(s.favoriteSoundEnabled ~= false)
        dropSound:SetText(SoundLabel(s.favoriteSound))
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
    uiModule.AddTips({
        { btnSaveDiscord, "Guardar", "Guarda el enlace de Discord y lo envía a la hermandad." },
        { btnClearDiscord, "Quitar", "Quita el enlace de Discord para todos." },
        { btnTabard, "Emblema del juego", "Usa el emblema de la hermandad como icono del encabezado." },
        { btnPicker, "Iconos del juego...", "Elige cualquier icono del juego para el encabezado." },
        { btnApplyIcon, "Aplicar", "Usa como icono el ID o la ruta escritos." },
        { chkPlayerInvite, "Los jugadores pueden usar Invitar (reclutar)", "Los jugadores también ven la pestaña Invitar. Se comparte con la hermandad." },
        { btnSaveRules, "Guardar", "Guarda las normas y las envía a la hermandad." },
        { btnUndoRules, "Deshacer", "Vuelve a las normas guardadas." },
        { chkOnTop, "Siempre por encima", "Muestra la ventana del addon por encima de las barras de acción y otros botones del juego." },
        { btnReloadLang, "Recargar", "Recarga la interfaz para aplicar el idioma." },
        { chkNotify, "Avisos personales en pantalla", "Ventanitas y mensajes cuando hay algo para ti: bandas, botín, DKP o tu lista de deseos." },
        { chkCombat, "Cerrar al entrar en combate", "Cierra la ventana de GuildControl en cuanto entras en combate." },
        { chkMinimap, "Ocultar el botón del minimapa", "Quita el botón del minimapa; el addon se abre con /gct." },
        { chkGreet, "Responder a quien salude al conectarse", "Responde con el mensaje de abajo a quien saluda nada más conectarse." },
        { chkWelcome, "Dar la bienvenida en el chat de hermandad a quien se une", "Saluda en el chat de hermandad a cada miembro nuevo con el mensaje de abajo." },
        { chkSound, "Sonido cuando se conecta un favorito", "Suena el sonido elegido cuando se conecta uno de tus favoritos." },
        { btnTestSound, "Probar", "Reproduce el sonido elegido." },
        { btnBadgeDefaults, "Restablecer predeterminadas", "Vuelve a los premios de serie de las insignias." },
        { btnNewBadge, "Nueva insignia", "Crea una insignia propia para darla a mano a quien quieras." },
    })
    containers.views["Configuracion"] = view
end

-- =========================================================================
-- 10. PANEL DE CHAT (HERMANDAD, SUSURROS, BANDA Y GRUPO; CONTRAÍBLE, DEBAJO DE LA VENTANA)
-- =========================================================================
local CHAT_SIZES = { expanded = 190, collapsed = 30, maxPersonTabs = 4 }

-- Pestañas fijas: "all" muestra todo; el resto, un canal. Las de persona usan el nombre corto.
local CHAT_CHANNEL_TABS = {
    { key = "all", label = "Todo" },
    { key = "guild", label = "Hermandad" },
    { key = "whisper", label = "Susurros" },
    { key = "raid", label = "Banda" },
    { key = "party", label = "Grupo" },
    { key = "officer", label = "Oficiales" },  -- chat de oficiales del juego (solo oficiales)
    { key = "english", label = "English" },    -- canal lobosenglish (GuildChat.lua)

}
local CHAT_CHANNEL_KEYS = { all = true, guild = true, whisper = true, raid = true, party = true,
    officer = true, english = true, spanish = true }
-- Color y etiqueta de cada canal (como en el chat del juego)
local CHAT_CHANNEL_STYLE = {
    guild = { color = "40FF40", tag = "H" }, whisper = { color = "FF80FF", tag = "S" },
    raid = { color = "FF7F00", tag = "B" }, party = { color = "AAAAFF", tag = "G" },
    instance = { color = "FF7F00", tag = "M" }, officer = { color = "40C040", tag = "O" },
    english = { color = "40FF40", tag = "EN" }, spanish = { color = "40FF40", tag = "ES" },   -- verde, como hermandad
}

-- Canales que se pueden ocultar (Configuración > Canales del chat): todos menos Todo; los de
-- idioma además si no estoy en ellos y el de oficiales si no tengo permiso. Ocultar un canal
-- quita su pestaña y sus mensajes de Todo.
local function IsChatChannelShown(key)
    local chat = addonTable.GuildChat
    if not chat then return true end
    if key == "officer" then
        return chat.CanUseOfficerChat and chat.CanUseOfficerChat() and chat.ShowsTab("officer") or false
    end
    if chat.GetLangChannel and chat.GetLangChannel(key) then
        -- lobosespañol no tiene pestaña: sus mensajes salen siempre en Todo
        return chat.UsesChannel(key) and (key == "spanish" or chat.ShowsTab(key))
    end
    if key == "all" or not chat.ShowsTab then return true end
    if key == "instance" then key = "party" end   -- mazmorra va con Grupo
    return chat.ShowsTab(key)
end

local function ChatEntryTime(entry)
    if not entry.at then return entry.time or "" end
    if date("%Y%m%d", entry.at) == date("%Y%m%d") then return date("%H:%M", entry.at) end
    return date("%d/%m %H:%M", entry.at)
end

-- El nombre es un enlace de jugador: clic izquierdo abre su pestaña, clic derecho el menú del juego
local function FormatChatLine(entry)
    local style = CHAT_CHANNEL_STYLE[entry.channel or "guild"] or CHAT_CHANNEL_STYLE.guild
    local hex = entry.class and addonTable.GetClassColorHex(entry.class) or style.color
    local linkName = entry.fullName or entry.sender
    local who = "|Hplayer:" .. linkName .. "|h|cFF" .. hex .. "[" .. entry.sender .. "]|r|h"
    if entry.channel == "whisper" then
        if entry.dir == "out" then
            who = L["A "] .. "|Hplayer:" .. (entry.target or "?") .. "|h[" .. (entry.target or "?") .. "]|h"
        else
            who = L["De "] .. who
        end
    end
    return "|cFF808080[" .. ChatEntryTime(entry) .. "]|r |cFF" .. style.color .. "[" .. L[style.tag] .. "]|r " .. who
        .. ": |cFF" .. style.color .. entry.text .. "|r"
end

-- Conversación con "person": lo que escribe, los susurros con ella y lo mío que la menciona
local function EntryMatchesPerson(entry, person)
    if entry.sender == person then return true end
    if entry.channel == "whisper" and entry.dir == "out" and entry.target == person then return true end
    if entry.sender == UnitName("player") and entry.text then
        return string.find(string.lower(entry.text), string.lower(person), 1, true) ~= nil
    end
    return false
end

local function EntryMatchesTab(entry, tabName)
    if entry.channel and not IsChatChannelShown(entry.channel) then return false end
    if tabName == "all" then return true end
    if tabName == "party" then return entry.channel == "party" or entry.channel == "instance" end
    if CHAT_CHANNEL_KEYS[tabName] then return (entry.channel or "guild") == tabName end
    return EntryMatchesPerson(entry, tabName)
end

local function BuildChatPanel(parent)
    local panel = CreateBackdropBox(parent, 1300, CHAT_SIZES.expanded)
    panel:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, 2)
    panel:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, 2)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -9)
    title:SetText(L["Chat"])

    local unreadText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    unreadText:SetPoint("LEFT", title, "RIGHT", 8, 0)

    local btnToggle = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnToggle:SetSize(90, 20)
    btnToggle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -5)

    -- Borrar el historial guardado (con segundo clic de confirmación)
    local clearArmedUntil = 0
    local btnClear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnClear:SetSize(80, 20)
    btnClear:SetPoint("RIGHT", btnToggle, "LEFT", -6, 0)
    btnClear:SetText(L["Limpiar"])

    local messagesFrame = CreateFrame("ScrollingMessageFrame", nil, panel)
    messagesFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -32)
    messagesFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 38)
    messagesFrame:SetFontObject(ChatFontNormal)
    messagesFrame:SetJustifyH("LEFT")
    messagesFrame:SetFading(false)
    messagesFrame:SetMaxLines(500)
    messagesFrame:SetHyperlinksEnabled(true)
    messagesFrame:EnableMouseWheel(true)
    messagesFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)

    -- Destino del mensaje según la pestaña activa
    local targetText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    targetText:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 14)
    targetText:SetWidth(150)
    targetText:SetJustifyH("LEFT")
    targetText:SetWordWrap(false)

    local input = CreateFrame("EditBox", "GC_GuildChatInput", panel, "InputBoxTemplate")
    input:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 172, 10)
    input:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -110, 10)
    input:SetHeight(20)
    input:SetAutoFocus(false)
    input:SetMaxLetters(255)

    local btnSend = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btnSend:SetSize(90, 22)
    btnSend:SetPoint("LEFT", input, "RIGHT", 8, 0)
    btnSend:SetText(L["Enviar"])

    -- ---------------------------------------------------------------------
    -- Pestañas: las de canal y una por persona (nombre corto)
    -- ---------------------------------------------------------------------
    local tabs = {}            -- lista ordenada de { name, button, unread }
    local activeTabName = "all"
    local unread = 0           -- mensajes nuevos con el panel contraído
    local SelectTab            -- declaración adelantada

    local function FindTab(name)
        for i, tab in ipairs(tabs) do
            if tab.name == name then return tab, i end
        end
    end

    -- Último interlocutor de susurros (para responder desde la pestaña Susurros)
    local function LastWhisperPartner()
        local list = addonTable.GuildChat and addonTable.GuildChat.GetMessages() or {}
        for i = #list, 1, -1 do
            local entry = list[i]
            if entry.channel == "whisper" then return entry.dir == "out" and entry.target or entry.sender end
        end
        return nil
    end

    -- Canal y destinatario al escribir: pestaña de persona = susurro a esa persona
    local function SendTarget()
        if activeTabName == "all" or activeTabName == "guild" then return "guild", nil end
        if activeTabName == "raid" then return "raid", nil end
        if activeTabName == "party" then return "party", nil end
        if activeTabName == "officer" or activeTabName == "english" or activeTabName == "spanish" then
            return activeTabName, nil
        end
        if activeTabName == "whisper" then return "whisper", LastWhisperPartner() end
        return "whisper", activeTabName
    end

    local function UpdateTargetText()
        local channel, target = SendTarget()
        local labels = { guild = L["Hermandad"], raid = L["Banda"], party = L["Grupo"], officer = L["Oficiales"],
            english = "lobosenglish", spanish = "lobosespañol" }
        if channel == "whisper" then
            targetText:SetText(target and ("|cFFFF80FF" .. L["Susurro a "] .. target .. ":|r") or L["|cFF808080Sin destinatario|r"])
        else
            local style = CHAT_CHANNEL_STYLE[channel]
            targetText:SetText("|cFF" .. style.color .. labels[channel] .. ":|r")
        end
    end

    local function SendInput()
        local channel, target = SendTarget()
        local text = input:GetText()
        if addonTable.GuildChat and strtrim(text or "") ~= "" then
            if not addonTable.GuildChat.Send(text, channel, target) then
                if channel == "english" or channel == "spanish" then
                    PrintGC(string.format(L["|cFFFF3333No estás en el canal %s. Actívalo en Configuración > Canales del chat.|r"],
                        channel == "english" and "lobosenglish" or "lobosespañol"))
                elseif channel == "officer" then
                    PrintGC(L["|cFFFF3333Tu rango no puede escribir en el chat de oficiales.|r"])
                else
                    PrintGC(L["|cFFFF3333No puedes escribir en ese canal ahora (no estás en banda, grupo o no hay destinatario).|r"])
                end
                return
            end
        end
        input:SetText("")
        input:ClearFocus()
    end
    input:SetScript("OnEnterPressed", SendInput)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    btnSend:SetScript("OnClick", SendInput)

    -- Shift+clic en un objeto (bolsas, chat, mensajes de este panel) con la caja activa:
    -- se inserta su enlace, como en el chat del juego
    OnInsertLink(function(link)
            if link and input:IsVisible() and input:HasFocus() then input:Insert(link) end
    end)

    local function LayoutTabs()
        local previous = nil
        local collapsed = GuildControlDB.settings.chatCollapsed
        for _, tab in ipairs(tabs) do
            tab.button:ClearAllPoints()
            -- Canales ocultos (Configuración > Canales del chat) o sin permiso: sin pestaña
            local hidden = CHAT_CHANNEL_KEYS[tab.name] and not IsChatChannelShown(tab.name)
            if hidden then
                tab.button:Hide()
            else
                if previous then
                    tab.button:SetPoint("LEFT", previous, "RIGHT", 3, 0)
                else
                    tab.button:SetPoint("TOPLEFT", panel, "TOPLEFT", 110, -5)
                end
                local label = tab.label or tab.name
                if tab.unread > 0 then label = label .. " |cFF00FF00(" .. tab.unread .. ")|r" end
                tab.button:SetText(label)
                tab.button:SetEnabled(tab.name ~= activeTabName)
                tab.button:SetShown(not collapsed)
                previous = tab.button
            end
        end
        UpdateTargetText()
    end

    local function RenderMessages()
        messagesFrame:Clear()
        if not addonTable.GuildChat then return end
        for _, entry in ipairs(addonTable.GuildChat.GetMessages()) do
            if EntryMatchesTab(entry, activeTabName) then
                messagesFrame:AddMessage(FormatChatLine(entry))
            end
        end
    end

    local function CloseTab(name)
        local tab, index = FindTab(name)
        if not tab or CHAT_CHANNEL_KEYS[name] then return end
        tab.button:Hide()
        table.remove(tabs, index)
        if activeTabName == name then
            SelectTab("all")
        else
            LayoutTabs()
        end
    end

    local function CreateTab(name, label)
        local isChannel = CHAT_CHANNEL_KEYS[name]
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(isChannel and 72 or 96, 20)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" then CloseTab(name) else SelectTab(name) end
        end)

        if not isChannel then
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(L["Conversación con "] .. name, 1, 1, 1)
                GameTooltip:AddLine(L["Lo que escribas aquí se le envía por susurro."], 0.7, 0.7, 0.7)
                GameTooltip:AddLine(L["Clic derecho: cerrar pestaña"], 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        local tab = { name = name, label = label, button = button, unread = 0 }
        table.insert(tabs, tab)
        return tab
    end

    SelectTab = function(name)
        local tab = FindTab(name)
        if not tab then
            -- Si ya hay demasiadas pestañas de personas, se cierra la más antigua
            if #tabs - #CHAT_CHANNEL_TABS >= CHAT_SIZES.maxPersonTabs then
                local oldest = tabs[#CHAT_CHANNEL_TABS + 1]
                oldest.button:Hide()
                table.remove(tabs, #CHAT_CHANNEL_TABS + 1)
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
            if not addonTable.IsMe(target) then
                SelectTab(short)
                return
            end
        end
        SetItemRef(link, text, button)
    end)

    btnClear:SetScript("OnClick", function(self)
        if GetTime() < clearArmedUntil then
            clearArmedUntil = 0
            self:SetText(L["Limpiar"])
            if addonTable.GuildChat then addonTable.GuildChat.Clear() end
            RenderMessages()
        else
            clearArmedUntil = GetTime() + 4
            self:SetText(L["|cFFFF3333¿Seguro?|r"])
            C_Timer.After(4, function() if GetTime() >= clearArmedUntil then self:SetText(L["Limpiar"]) end end)
        end
    end)

    local function ApplyCollapsed()
        local collapsed = GuildControlDB.settings.chatCollapsed
        panel:SetHeight(collapsed and CHAT_SIZES.collapsed or CHAT_SIZES.expanded)
        messagesFrame:SetShown(not collapsed)
        input:SetShown(not collapsed)
        btnSend:SetShown(not collapsed)
        targetText:SetShown(not collapsed)
        btnClear:SetShown(not collapsed)
        btnToggle:SetText(collapsed and L["Expandir"] or L["Contraer"])
        if not collapsed then unread = 0 end
        unreadText:SetText(unread > 0 and ("|cFF00FF00(" .. unread .. L[" nuevos)|r"]) or "")
        LayoutTabs()
        -- Mantener el panel dentro de la pantalla al arrastrar la ventana
        parent:SetClampRectInsets(0, 0, 0, -(panel:GetHeight() - 2))
    end

    btnToggle:SetScript("OnClick", function()
        GuildControlDB.settings.chatCollapsed = not GuildControlDB.settings.chatCollapsed
        ApplyCollapsed()
    end)

    for _, channelTab in ipairs(CHAT_CHANNEL_TABS) do CreateTab(channelTab.key, L[channelTab.label]) end

    -- Mensajes nuevos: a la pestaña activa si le corresponden; en las demás suman como no leídos
    if addonTable.GuildChat then
        addonTable.GuildChat.SetListener(function(entry)
            if EntryMatchesTab(entry, activeTabName) then
                messagesFrame:AddMessage(FormatChatLine(entry))
            end
            local changed = false
            for _, tab in ipairs(tabs) do
                if tab.name ~= activeTabName and tab.name ~= "all" and EntryMatchesTab(entry, tab.name) then
                    tab.unread = tab.unread + 1
                    changed = true
                end
            end
            if changed then LayoutTabs() end
            if entry.channel == "whisper" and activeTabName == "whisper" then UpdateTargetText() end
            if GuildControlDB.settings.chatCollapsed then
                unread = unread + 1
                unreadText:SetText("|cFF00FF00(" .. unread .. L[" nuevos)|r"])
            end
        end)
    end

    -- Al unirse/salir de un canal, ocultarlo o cambiar el perfil: pestañas y mensajes de nuevo
    -- (ApplyProfile lo llama en cada escaneo del roster: solo se redibuja si algo cambió)
    local shownSignature = nil
    function uiModule.RefreshChatTabs()
        local signature = ""
        for _, channelTab in ipairs(CHAT_CHANNEL_TABS) do
            signature = signature .. (IsChatChannelShown(channelTab.key) and "1" or "0")
        end
        if signature == shownSignature then return end
        shownSignature = signature
        if CHAT_CHANNEL_KEYS[activeTabName] and not IsChatChannelShown(activeTabName) then
            SelectTab("all")
        else
            LayoutTabs()
            RenderMessages()
        end
    end

    parent:SetClampedToScreen(true)
    RenderMessages()
    ApplyCollapsed()
    containers.chat = panel
end

-- =========================================================================
-- 10b. AVISOS PERSONALES EN PANTALLA (TOAST)
-- =========================================================================
local toastFrame = nil
local toastQueue = {}

local function ShowNextToast()
    if not toastFrame or toastFrame:IsShown() then return end
    local nextToast = table.remove(toastQueue, 1)
    if not nextToast then return end
    toastFrame.icon:SetTexture(nextToast.icon or "Interface\\Icons\\Achievement_GuildPerk_MobileBanking")
    toastFrame.text:SetText(nextToast.text)
    toastFrame:SetAlpha(1)
    toastFrame:Show()
    toastFrame.hideAt = GetTime() + 6
end

function uiModule.ShowToast(text, icon)
    if not toastFrame then
        local frame = CreateBackdropBox(UIParent, 380, 58, "TOP", UIParent, "TOP", 0, -110)
        frame:SetFrameStrata("DIALOG")
        frame:EnableMouse(true)
        frame:Hide()
        frame.icon = frame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetSize(36, 36)
        frame.icon:SetPoint("LEFT", frame, "LEFT", 12, 0)
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.title:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, 0)
        frame.title:SetText("GuildControl")
        frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.text:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)
        frame.text:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
        frame.text:SetJustifyH("LEFT")
        frame.text:SetMaxLines(2)
        frame:SetScript("OnMouseUp", function(self) self:Hide() end)
        frame:SetScript("OnUpdate", function(self)
            local left = (self.hideAt or 0) - GetTime()
            if left <= 0 then
                self:Hide()
            elseif left < 1 then
                self:SetAlpha(left)
            end
        end)
        frame:SetScript("OnHide", function() C_Timer.After(0.3, ShowNextToast) end)
        toastFrame = frame
    end
    table.insert(toastQueue, { text = text, icon = icon })
    while #toastQueue > 5 do table.remove(toastQueue, 1) end
    ShowNextToast()
end

local function ColoredName(fullName)
    local m = GuildControlDB.members and GuildControlDB.members[fullName]
    -- Con apellido si el juego lo da (Forever)
    local short = (m and m.displayName) or (fullName and (string.match(fullName, "^([^-]+)") or fullName)) or "?"
    return "|cFF" .. addonTable.GetClassColorHex(m and m.class) .. short .. "|r"
end

local function ItemLinkById(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local link = getInfo and select(2, getInfo(itemID))
    return link or ("item:" .. itemID)
end

-- =========================================================================
-- AVISO A LOS OFICIALES: OBJETO DE UNA LISTA DE DESEOS
-- =========================================================================
-- Ventana flotante cuando sale en la banda un objeto que alguien tiene en su lista de deseos.
-- names = { {name, inGroup}, ... }. Si salen varios seguidos se enseñan uno detrás de otro.
local wishDrop = { frame = nil, queue = {} }

local function ShowNextWishDrop()
    local frame = wishDrop.frame
    if not frame or frame:IsShown() then return end
    local entry = table.remove(wishDrop.queue, 1)
    if not entry then return end
    local LT = addonTable.Loot
    local item = LT and LT.GetItem(entry.key)
    if not item then return ShowNextWishDrop() end
    local link = LT.DisplayLink(item.link)
    frame.key = item.key
    frame.itemButton.link = link
    frame.itemButton.icon:SetTexture(ItemIconFromLink(link))
    frame.itemButton.text:SetText(link)
    local lines = {}
    for _, who in ipairs(entry.names) do
        table.insert(lines, ColoredName(who.name) .. (who.inGroup and "" or L[" |cFF808080(no está en la banda)|r"]))
    end
    frame.names:SetText(L["Lo tienen en su lista de deseos:"] .. "\n" .. table.concat(lines, "\n"))
    frame:SetHeight(118 + math.max(1, #lines) * 14)
    local canRoll = LT.CanManage() and item.state == "pending"
    frame.btnRoll:SetEnabled(canRoll)
    frame.btnRoll:SetText(item.state == "rolling" and L["Tirada abierta"] or L["Abrir tirada"])
    frame:Show()
    PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
end

function uiModule.ShowWishDropAlert(itemKey, names)
    if not itemKey or not names or #names == 0 then return end
    if not wishDrop.frame then
        local frame = CreateFrame("Frame", "GuildControlWishDropFrame", UIParent, "BasicFrameTemplateWithInset")
        frame:Hide()   -- nace visible: si no, ShowNext lo da por ocupado y se queda en blanco
        frame:SetSize(340, 150)
        frame:SetPoint("TOP", UIParent, "TOP", 0, -220)
        frame:SetFrameStrata("DIALOG")
        frame:SetToplevel(true)
        frame:SetClampedToScreen(true)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
        frame.title:SetText(L["Objeto de una lista de deseos"])

        frame.itemButton = CreateFrame("Button", nil, frame)
        frame.itemButton:SetSize(300, 32)
        frame.itemButton:SetPoint("TOP", frame, "TOP", 0, -30)
        frame.itemButton.icon = frame.itemButton:CreateTexture(nil, "ARTWORK")
        frame.itemButton.icon:SetSize(30, 30)
        frame.itemButton.icon:SetPoint("LEFT", frame.itemButton, "LEFT", 0, 0)
        frame.itemButton.text = frame.itemButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.itemButton.text:SetPoint("LEFT", frame.itemButton.icon, "RIGHT", 8, 0)
        frame.itemButton.text:SetPoint("RIGHT", frame.itemButton, "RIGHT", 0, 0)
        frame.itemButton.text:SetJustifyH("LEFT")
        frame.itemButton:SetScript("OnEnter", function(self) ShowLinkTooltip(self, self.link) end)
        frame.itemButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

        frame.names = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.names:SetPoint("TOPLEFT", frame.itemButton, "BOTTOMLEFT", 0, -8)
        frame.names:SetWidth(300)
        frame.names:SetJustifyH("LEFT")
        frame.names:SetSpacing(2)

        frame.btnRoll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.btnRoll:SetSize(100, 22)
        frame.btnRoll:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 10)
        frame.btnRoll:SetScript("OnClick", function()
            if frame.key and addonTable.Loot.StartRoll(frame.key) then frame:Hide() end
        end)
        local btnLoot = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btnLoot:SetSize(100, 22)
        btnLoot:SetPoint("LEFT", frame.btnRoll, "RIGHT", 6, 0)
        btnLoot:SetText(L["Ver en Botín"])
        btnLoot:SetScript("OnClick", function()
            frame:Hide()
            if not (GC_UI and GC_UI:IsShown()) then uiModule.ToggleUI() end
            SwitchTab("Botín")
        end)
        local btnClose = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btnClose:SetSize(100, 22)
        btnClose:SetPoint("LEFT", btnLoot, "RIGHT", 6, 0)
        btnClose:SetText(L["Cerrar"])
        btnClose:SetScript("OnClick", function() frame:Hide() end)
        frame:SetScript("OnHide", function() C_Timer.After(0.3, ShowNextWishDrop) end)
        wishDrop.frame = frame
    end
    for _, entry in ipairs(wishDrop.queue) do
        if entry.key == itemKey then return end
    end
    if wishDrop.frame:IsShown() and wishDrop.frame.key == itemKey then return end
    table.insert(wishDrop.queue, { key = itemKey, names = names })
    ShowNextWishDrop()
end

-- Cuenta atrás corta: "en 2 d 3 h", "en 45 min"
local function CountdownText(seconds)
    if seconds <= 0 then return L["|cFF00FF00ahora|r"] end
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if days > 0 then return string.format(L["en %d d %d h"], days, hours) end
    if hours > 0 then return string.format(L["en %d h %d min"], hours, minutes) end
    return string.format(L["en %d min"], math.max(1, minutes))
end

-- =========================================================================
-- 10c. VISTA PARA MÍ: LISTA DE DESEOS, PRÓXIMAS BANDAS, HISTORIAL E INSIGNIAS
-- =========================================================================
local ROLE_KEYS = { Tanque = "tank", Sanador = "healer", DPS = "dps" }

local function BuildForMeView(parent)
    local PM = addonTable.Personal
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()
    local Refresh

    local function ScrollPanel(titleText, x, y, width, height)
        local box = CreateColoredPanel(view, titleText, PANEL_COLORS.blue, width, height)
        box:SetPoint("TOPLEFT", view, "TOPLEFT", x, y)
        box.scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
        box.scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -28)
        box.scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -28, 8)
        box.child = CreateFrame("Frame")
        box.child:SetSize(width - 40, 1)
        box.scroll:SetScrollChild(box.child)
        box.empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        box.empty:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -34)
        box.empty:SetWidth(width - 30)
        box.empty:SetJustifyH("LEFT")
        box.rows = {}
        return box
    end

    -- 1. Lista de deseos ------------------------------------------------------
    local wishBox = ScrollPanel(L["Mi lista de deseos"], 10, -10, 437, 250)
    wishBox.scroll:SetPoint("BOTTOMRIGHT", wishBox, "BOTTOMRIGHT", -28, 36)
    local wishInput = CreateFrame("EditBox", nil, wishBox, "InputBoxTemplate")
    wishInput:SetSize(300, 20)
    wishInput:SetMaxLetters(0)
    wishInput:SetPoint("BOTTOMLEFT", wishBox, "BOTTOMLEFT", 16, 10)
    wishInput:SetAutoFocus(false)
    wishInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local wishPlaceholder = wishInput:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    wishPlaceholder:SetPoint("LEFT", wishInput, "LEFT", 2, 0)
    wishPlaceholder:SetText(L["Shift+clic en un objeto o pega un enlace de Wowhead"])
    wishInput:SetScript("OnTextChanged", function(self) wishPlaceholder:SetShown((self:GetText() or "") == "") end)
    local btnWishAdd = CreateFrame("Button", nil, wishBox, "UIPanelButtonTemplate")
    btnWishAdd:SetSize(90, 22)
    btnWishAdd:SetPoint("LEFT", wishInput, "RIGHT", 8, 0)
    btnWishAdd:SetText(L["Añadir"])
    local function AddWish()
        local id = PM.ItemIdFromLink(wishInput:GetText())
        if not id then
            PrintGC(L["|cFFFF3333Pega el enlace del objeto con Shift+clic o un enlace de Wowhead (wowhead.com/item=...).|r"])
            return
        end
        if not PM.GetMyWishlist()[id] then PM.ToggleWish(id) end
        wishInput:SetText("")
        wishInput:ClearFocus()
    end
    btnWishAdd:SetScript("OnClick", AddWish)
    wishInput:SetScript("OnEnterPressed", AddWish)
    OnInsertLink(function(link)
            if wishInput:IsVisible() and wishInput:HasFocus() and link then wishInput:Insert(link) end
    end)

    local function AcquireWishRow(index)
        local row = wishBox.rows[index]
        if row then return row end
        row = CreateFrame("Button", nil, wishBox.child)
        row:SetSize(wishBox.child:GetWidth(), 24)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        row.remove:SetSize(20, 20)
        row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnEnter", function(self) ShowLinkTooltip(self, self.link) end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        wishBox.rows[index] = row
        return row
    end

    -- La lista de deseos se ve en Mi perfil (subpestaña Lista de deseos): allí se coloca
    local function RefreshWish()
        if not wishBox:IsVisible() or not PM then return end
        local me = addonTable.Profiles and addonTable.Profiles.GetMyFullName() or UnitName("player")
        for _, row in ipairs(wishBox.rows) do row:Hide() end
        local ids = PM.GetMyWishIds()
        for i, id in ipairs(ids) do
            local row = AcquireWishRow(i)
            row:SetPoint("TOPLEFT", wishBox.child, "TOPLEFT", 0, -(i - 1) * 26)
            local link = ItemLinkById(id)
            row.link = link
            row.icon:SetTexture(ItemIconFromLink(link))
            local others = 0
            for _, name in ipairs(PM.WhoWants(id)) do if name ~= me then others = others + 1 end end
            row.text:SetText(link .. (others > 0 and ("  |cFF808080" .. string.format(L["(+%d lo quieren)"], others) .. "|r") or ""))
            row.remove:SetScript("OnClick", function() PM.ToggleWish(id) end)
            row:Show()
        end
        wishBox.child:SetHeight(math.max(1, #ids * 26))
        wishBox.empty:SetShown(#ids == 0)
        wishBox.empty:SetText(L["Añade los objetos que buscas: cuando caigan en la banda te avisará, y los oficiales verán que los quieres."])
    end
    wishBox:SetScript("OnShow", RefreshWish)
    function uiModule.AttachWishlist(host, width, height)
        wishBox:SetParent(host)
        wishBox:ClearAllPoints()
        wishBox:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        wishBox:SetSize(width, height)
        wishBox.child:SetWidth(width - 40)
        wishBox.empty:SetWidth(width - 30)
        wishInput:SetWidth(width - 140)
    end

    -- 1. Mi semana (desde el reinicio semanal) ----------------------------------
    local weekBox = ScrollPanel(L["Mi semana"], 10, -10, 437, 250)
    local weekText = weekBox.child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    weekText:SetPoint("TOPLEFT", weekBox.child, "TOPLEFT", 4, -2)
    weekText:SetWidth(390)
    weekText:SetJustifyH("LEFT")
    weekText:SetSpacing(3)

    local function WeekLines(me)
        local w = PM.GetWeekSummary and PM.GetWeekSummary(me)
        if not w then return "" end
        local lines = {}
        local function List(items, max)
            if #items <= max then return table.concat(items, ", ") end
            local first = {}
            for i = 1, max do first[i] = items[i] end
            return table.concat(first, ", ") .. string.format(L[" y %d más"], #items - max)
        end
        table.insert(lines, "|cFFFFD100" .. L["Jefes derrotados"] .. "|r  " .. #w.bosses
            .. "  |cFF808080" .. string.format(L["(%d bandas)"], w.raids) .. "|r")
        if #w.bosses > 0 then table.insert(lines, "   |cFFBFBFBF" .. List(w.bosses, 8) .. "|r") end
        if addonTable.Dkp and addonTable.Dkp.IsActive() then
            table.insert(lines, "|cFFFFD100DKP|r  |cFF00FF00+" .. w.gained .. "|r " .. L["ganados"] .. "  ·  |cFFFF3333-" .. w.spent .. "|r " .. L["gastados"])
        end
        if (w.mplusRuns or 0) > 0 then
            local M = addonTable.MythicPlus
            table.insert(lines, "|cFFFFD100" .. L["Míticas+"] .. "|r  " .. w.mplusRuns .. (w.mplusBest and ("  |cFF808080" .. L["mejor llave"] .. "|r |cFFA335EE+"
                .. w.mplusBest .. "|r " .. (M and M.GetMapName and M.GetMapName(w.mplusMap) or "")) or ""))
        end
        table.insert(lines, "|cFFFFD100" .. L["Objetos ganados"] .. "|r  " .. #w.items)
        for _, link in ipairs(w.items) do table.insert(lines, "   " .. link) end
        table.insert(lines, "|cFFFFD100" .. L["Insignias nuevas"] .. "|r  " .. #w.badges)
        for _, badge in ipairs(w.badges) do
            table.insert(lines, "   |T" .. badge.icon .. ":14:14|t " .. L[badge.label])
        end
        if #w.wishDrops > 0 then
            table.insert(lines, "|cFFFFD100" .. L["Han caído de tu lista de deseos"] .. "|r")
            for _, link in ipairs(w.wishDrops) do table.insert(lines, "   " .. link) end
        end
        return table.concat(lines, "\n")
    end

    -- 2. Próximas bandas ------------------------------------------------------
    local raidBox = ScrollPanel(L["Mis próximas bandas"], 453, -10, 437, 250)
    local function AcquireRaidRow(index)
        local row = raidBox.rows[index]
        if row then return row end
        row = CreateFrame("Frame", nil, raidBox.child)
        row:SetSize(397, 42)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.04)
        row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -5)
        row.title:SetPoint("RIGHT", row, "RIGHT", -100, 0)
        row.title:SetJustifyH("LEFT")
        row.title:SetWordWrap(false)
        row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.info:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 5)
        row.info:SetPoint("RIGHT", row, "RIGHT", -100, 0)
        row.info:SetJustifyH("LEFT")
        row.info:SetWordWrap(false)
        row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.button:SetSize(92, 22)
        row.button:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        raidBox.rows[index] = row
        return row
    end

    -- 3. Mi historial -----------------------------------------------------------
    local historyBox = ScrollPanel(L["Mi historial"], 10, -266, 437, 250)
    local historyText = historyBox.child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    historyText:SetPoint("TOPLEFT", historyBox.child, "TOPLEFT", 4, -2)
    historyText:SetWidth(390)
    historyText:SetJustifyH("LEFT")
    historyText:SetSpacing(3)

    -- 4. Insignias ------------------------------------------------------------
    local badgeBox = CreateColoredPanel(view, L["Mis insignias"], PANEL_COLORS.blue, 437, 250)
    badgeBox:SetPoint("TOPLEFT", view, "TOPLEFT", 453, -266)
    -- Las de serie y las nuevas de los oficiales: con muchas, la lista se desplaza
    local badgeScroll = CreateFrame("ScrollFrame", nil, badgeBox, "UIPanelScrollFrameTemplate")
    badgeScroll:SetPoint("TOPLEFT", badgeBox, "TOPLEFT", 8, -26)
    badgeScroll:SetPoint("BOTTOMRIGHT", badgeBox, "BOTTOMRIGHT", -28, 6)
    local badgeChild = CreateFrame("Frame", nil, badgeScroll)
    badgeChild:SetSize(400, 1)
    badgeScroll:SetScrollChild(badgeChild)
    local badgeRows = {}
    local function BadgeRow(i)
        local row = badgeRows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, badgeChild)
        row:SetSize(400, 26)
        row:SetPoint("TOPLEFT", badgeChild, "TOPLEFT", 4, -2 - (i - 1) * 27)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        badgeRows[i] = row
        return row
    end

    Refresh = function()
        if not view:IsShown() or not PM then return end
        local me = addonTable.Profiles and addonTable.Profiles.GetMyFullName() or UnitName("player")

        -- Mi semana
        weekText:SetText(WeekLines(me))
        weekBox.child:SetHeight(math.max(1, weekText:GetStringHeight() + 6))
        weekBox.empty:Hide()

        -- Próximas bandas
        local E = addonTable.RaidEvents
        for _, row in ipairs(raidBox.rows) do row:Hide() end
        local events = E and E.GetUpcoming() or {}
        local profile = addonTable.Profiles and addonTable.Profiles.GetMyProfile() or {}
        local shown = 0
        for _, ev in ipairs(events) do
            local start = E.EventStart and E.EventStart(ev)
            if start and start > time() - 3 * 3600 then
                shown = shown + 1
                local row = AcquireRaidRow(shown)
                row:SetPoint("TOPLEFT", raidBox.child, "TOPLEFT", 0, -(shown - 1) * 46)
                row.title:SetText(ev.title)
                local mine = ev.signups and ev.signups[me]
                local status = mine and ("|cFF" .. (E.STATUS_COLORS[mine.status] or "FFFFFF") .. L[E.STATUS_LABELS[mine.status] or mine.status] .. "|r")
                    or L["|cFF808080sin apuntar|r"]
                row.info:SetText("|cFFBFBFBF" .. RaidEventDateText(ev) .. "|r  ·  " .. CountdownText(start - time()) .. "  ·  " .. status)
                row.button:SetShown(not mine or mine.status == "absent")
                row.button:SetText(L["Apuntarme"])
                row.button:SetScript("OnClick", function()
                    E.SignUp(ev, "signed", ROLE_KEYS[profile.main or ""], profile.spec or "", "")
                end)
                row:Show()
            end
        end
        raidBox.child:SetHeight(math.max(1, shown * 46))
        raidBox.empty:SetShown(shown == 0)
        raidBox.empty:SetText(L["No hay bandas programadas. Cuando un oficial publique una en Raid aparecerá aquí, con un aviso 15 minutos antes si estás apuntado."])

        -- Mi historial: DKP, objetos y bandas, lo más reciente primero
        local entries = {}
        for _, change in ipairs(PM.GetLedger(me)) do
            table.insert(entries, { at = change.at or 0, text = (change.delta > 0 and "|cFF00FF00+" or "|cFFFF3333") .. change.delta .. " DKP|r  "
                .. (change.reason or "") .. "  |cFF808080(" .. (change.balance or 0) .. ")|r" })
        end
        local LT = addonTable.Loot
        for _, award in ipairs(LT and LT.GetHistory() or {}) do
            if award.winner == me then
                table.insert(entries, { at = award.at or 0, text = L["|cFFFFD100Objeto:|r "] .. LT.DisplayLink(award.link)
                    .. (award.kind == "bid" and (" |cFF808080(-" .. tostring(award.roll or 0) .. " DKP)|r") or "") })
            end
        end
        for _, raid in ipairs(E and E.GetHistory and E.GetHistory() or {}) do
            local mark = raid.marks[me]
            if mark == "present" or mark == "late" then
                local _, killed = E.GetHistoryBosses(raid)
                table.insert(entries, { at = (E.EventStart and E.EventStart(raid)) or 0, text = L["|cFF66B3FFBanda:|r "] .. raid.title
                    .. "  |cFF808080" .. string.format(L["(%d jefes)"], killed) .. "|r" })
            end
        end
        table.sort(entries, function(a, b) return a.at > b.at end)
        local lines = {}
        for i = 1, math.min(#entries, 80) do
            table.insert(lines, "|cFF808080" .. date("%d/%m", entries[i].at) .. "|r  " .. entries[i].text)
        end
        historyText:SetText(table.concat(lines, "\n"))
        historyBox.child:SetHeight(math.max(1, historyText:GetStringHeight() + 6))
        historyBox.empty:SetShown(#lines == 0)
        historyBox.empty:SetText(L["Aquí irán tus DKP ganados y gastados, los objetos que ganes y las bandas a las que vayas."])

        -- Insignias: las ganadas en color y las que faltan en gris (como objetivo)
        local earned = {}
        for _, badge in ipairs(PM.GetBadges(me)) do earned[badge.key] = true end
        for _, row in ipairs(badgeRows) do row:Hide() end
        local allBadges = PM.GetAllBadges()
        for i, badge in ipairs(allBadges) do
            local row = BadgeRow(i)
            row.badge = badge
            row.icon:SetTexture(badge.icon)
            row:Show()
            local has = earned[row.badge.key]
            row.icon:SetDesaturated(not has)
            row.icon:SetAlpha(has and 1 or 0.4)
            -- Premio en DKP de la insignia (solo con el sistema DKP)
            local D = addonTable.Dkp
            local reward = D and D.IsActive() and D.GetBadgeReward and D.GetBadgeReward(row.badge.key)
            row.text:SetText((has and "|cFFFFD100" or "|cFF808080") .. L[row.badge.label] .. "|r  "
                .. (reward and ((has and "|cFF00FF00" or "|cFF607060") .. "+" .. reward .. " DKP|r  ") or "")
                .. (has and "|cFFFFFFFF" or "|cFF606060") .. L[row.badge.desc or ""] .. "|r")
        end
        badgeChild:SetHeight(math.max(1, #allBadges * 27 + 4))
    end

    PM.AddListener(function() Refresh(); RefreshWish() end)
    if addonTable.Dkp and addonTable.Dkp.AddListener then addonTable.Dkp.AddListener(function() Refresh() end) end
    if addonTable.RaidEvents then addonTable.RaidEvents.AddListener(function() Refresh() end) end
    local itemFrame = CreateFrame("Frame")
    itemFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    itemFrame:SetScript("OnEvent", function()
        if (view:IsShown() or wishBox:IsVisible()) and not itemFrame.pending then
            itemFrame.pending = true
            C_Timer.After(0.5, function() itemFrame.pending = false; Refresh(); RefreshWish() end)
        end
    end)
    view:SetScript("OnShow", Refresh)
    containers.views["Para mí"] = view
end

-- =========================================================================
-- 10d. RÉCORDS Y DIARIO DEL RESUMEN
-- =========================================================================
-- Texto de las subpestañas Récords y Diario del Resumen (antes en Comunidad).
-- mode = "records" o "journal" (Journal.lua: recuerdos que no se borran)
function uiModule.RecordsJournalText(mode)
    local PM = addonTable.Personal
    local lines = {}
    local J = addonTable.Journal
    if mode == "journal" and J then
        local function When(entry) return "|cFF808080" .. date("%d/%m/%Y", entry.at or 0) .. "|r" end
        for _, section in ipairs(J.GetSections()) do
            table.insert(lines, "|cFFFFD100" .. section.title .. "|r")
            for _, line in ipairs(section.lines) do
                local label = line.class and ("|cFF" .. addonTable.GetClassColorHex(line.class) .. line.label .. "|r") or line.label
                local entry = line.entry
                local text
                if not entry then
                    text = line.milestone and ("|cFF808080" .. L["todavía no"] .. "|r") or ("|cFF66B3FF" .. L["¡Sé el primero!"] .. "|r")
                elseif line.milestone then
                    text = When(entry)
                else
                    -- En los jefes van todos los de la hermandad que estaban: se resumen
                    local who = entry.who or "?"
                    if line.entry and section.bosses then
                        local names = { strsplit(",", who) }
                        if #names > 5 then
                            who = table.concat(names, ",", 1, 5) .. string.format(L[" y %d más"], #names - 5)
                        end
                    end
                    text = "|cFFFFFFFF" .. who .. "|r" .. ((line.loot and entry.detail and entry.detail ~= "") and (" · " .. entry.detail) or "")
                        .. "  " .. When(entry)
                end
                table.insert(lines, "   " .. label .. ": " .. text)
            end
            table.insert(lines, " ")
        end
        return table.concat(lines, "\n")
    end
    for _, record in ipairs(PM and PM.GetRecords() or {}) do
        table.insert(lines, "|cFFFFD100" .. L[record.label] .. "|r" .. (record.suffix and ("  |cFF808080" .. record.suffix .. "|r") or ""))
        if #record.entries == 0 then
            table.insert(lines, "   |cFF808080" .. L["sin datos todavía"] .. "|r")
        else
            for i, entry in ipairs(record.entries) do
                table.insert(lines, "   " .. i .. ". " .. ColoredName(entry.name) .. "  |cFFFFFFFF" .. entry.value .. "|r")
            end
        end
    end
    return table.concat(lines, "\n")
end

-- =========================================================================
-- CONSTRUCCIÓN TOTAL DE LA UI
-- =========================================================================
function uiModule.CreateUI()
    if GC_UI then return end

    GC_UI = CreateFrame("Frame", "GuildControlMainFrame", UIParent, "BasicFrameTemplateWithInset")
    GC_UI:SetSize(1300, 650 + (HEADER_HEIGHT - 50) + (ANN_BAR_HEIGHT - 45))
    GC_UI:SetPoint("CENTER")
    GC_UI:SetClampedToScreen(true)
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
    BuildFavoritesView(mainContent)
    BuildForMeView(mainContent)
    BuildAchievementsView(mainContent)
    BuildMyProfileView(mainContent)
    BuildMyRostersView(mainContent)
    BuildProfessionsView(mainContent)
    BuildMythicPlusView(mainContent)
    BuildRaidView(mainContent)
    BuildLootView(mainContent)
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
    GC_BajasFrame.title:SetText(L["Historial de bajas"])

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
    AddHeader(L["Fecha"], 5, 130)
    AddHeader(L["Personaje"], 140, 160)
    AddHeader(L["Detalle"], 305, 280)

    local scroll = CreateFrame("ScrollFrame", "GC_BajasScroll", GC_BajasFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", headerBg, "BOTTOMLEFT", 0, -5)
    scroll:SetPoint("BOTTOMRIGHT", GC_BajasFrame, "BOTTOMRIGHT", -35, 40)

    local child = CreateFrame("Frame")
    child:SetSize(590, 1)
    scroll:SetScrollChild(child)

    local emptyText = child:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", child, "TOPLEFT", 5, -10)
    emptyText:SetText(L["No hay bajas registradas."])

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
                row.infoFs:SetText(L[log.info or ""])
                row:Show()
            end
        end

        emptyText:SetShown(count == 0)
        totalText:SetText(L["Total de bajas: |cFFFFD100"] .. count .. "|r")
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

-- Escala de la ventana: la que cabe en la pantalla (como mucho el 90% de ancho y alto, nunca
-- más grande que el tamaño de diseño) por el porcentaje elegido (settings.windowScale, 100 = ajustada)
function uiModule.ApplyWindowScale()
    if not GC_UI then return end
    local w, h = GC_UI:GetWidth(), GC_UI:GetHeight()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    if not (w > 0 and h > 0 and sw > 0 and sh > 0) then return end
    local fit = math.min(1, sw * 0.9 / w, sh * 0.9 / h)
    local pct = (GuildControlDB and GuildControlDB.settings and GuildControlDB.settings.windowScale) or 100
    -- Nunca más grande que la pantalla
    local scale = math.min(fit * pct / 100, sw * 0.98 / w, sh * 0.98 / h)
    GC_UI:SetScale(math.max(0.4, scale))
end

-- Configuración > Cerrar al entrar en combate (settings.closeInCombat) y escala al cambiar la
-- resolución o la escala de la interfaz (otra pantalla)
do
    local combatWatcher = CreateFrame("Frame")
    combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatWatcher:RegisterEvent("UI_SCALE_CHANGED")
    combatWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    combatWatcher:SetScript("OnEvent", function(_, event)
        if event ~= "PLAYER_REGEN_DISABLED" then
            uiModule.ApplyWindowScale()
            return
        end
        local s = GuildControlDB and GuildControlDB.settings
        if s and s.closeInCombat and GC_UI and GC_UI:IsShown() then GC_UI:Hide() end
    end)
end

function uiModule.ToggleUI()
    addonTable.InitDB()
    if not GC_UI then uiModule.CreateUI() end
    -- En el Ayudante, /gct vuelve al modo normal
    if uiModule.IsMiniMode and uiModule.IsMiniMode() then
        uiModule.ExitMiniMode()
        return
    end
    if GC_UI:IsShown() then
        GC_UI:Hide()
    else
        -- Si la lista está vacía (llegó tarde al conectar) se fuerza el escaneo
        if IsInGuild() then
            if next(GuildControlDB.members) == nil and addonTable.ForceRosterScan then
                addonTable.ForceRosterScan()
            else
                C_GuildInfo.GuildRoster()
            end
        end
        uiModule.ApplyProfile()
        if activeTab == "Miembros" and uiModule.ResetMembersSort then uiModule.ResetMembersSort() end
        if uiModule.RefreshList then uiModule.RefreshList() end
        if uiModule.UpdateMemberCounter then uiModule.UpdateMemberCounter() end
        uiModule.UpdateHeader()
        uiModule.ApplyWindowScale()
        GC_UI:Show()
    end
end


-- =========================================================================
-- 11. MODO MINIMALISTA DE BANDA Y VENTANA DE BUFFOS (CONSUME MODULES/RAIDTOOLS.LUA)
-- =========================================================================
-- El Ayudante (antes «modo minimalista») sustituye a la ventana principal por un panel pequeño con lo que se usa
-- durante la banda: listos, pull 10/5, cancelar pull, marcas en el objetivo, buff check, la
-- ventana de buffos y volver al modo normal. settings.raidMini recuerda si estaba activo y
-- settings.raidMiniPos dónde estaba.
local raidMiniFrame = nil
local buffFrame = nil

local CHECK_TEXTURES = { ready = "Interface\\RaidFrame\\ReadyCheck-Ready", notReady = "Interface\\RaidFrame\\ReadyCheck-NotReady", unknown = "Interface\\RaidFrame\\ReadyCheck-Waiting" }

-- Botón pequeño con letra pequeña y una ayuda al pasar el ratón
local function MiniButton(parent, text, width, tooltipTitle, tooltipText, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, 22)
    btn:SetNormalFontObject("GameFontNormalSmall")
    btn:SetHighlightFontObject("GameFontHighlightSmall")
    btn:SetDisabledFontObject("GameFontDisableSmall")
    btn:SetText(text)
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tooltipTitle or text, 1, 1, 1)
        if tooltipText then GameTooltip:AddLine(tooltipText, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

-- -------------------------------------------------------------------------
-- Ventana de buffos
-- -------------------------------------------------------------------------
local BUFF_COLS = { name = 10, group = 162, buffs = 194, flask = 342, food = 404, rune = 466, potions = 528 }
local BUFF_ROW_HEIGHT = 20

local function CreateBuffFrame()
    local T = addonTable.RaidTools
    local frame = CreateFrame("Frame", "GuildControlBuffFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(640, 440)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    tinsert(UISpecialFrames, "GuildControlBuffFrame")

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
    frame.title:SetText(L["Buff check de la banda"])

    local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -32)
    summary:SetPoint("RIGHT", frame, "RIGHT", -280, 0)
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(false)

    local btnRefresh = MiniButton(frame, L["Actualizar"], 100, L["Actualizar"],
        L["Vuelve a leer los buffos y pide a quien usa GuildControl lo que lleva en las bolsas."],
        function() T.RequestReports() end)
    btnRefresh:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -28)

    -- Susurra a cada uno lo que le falta (los que salen con la X roja)
    local btnWarn = MiniButton(frame, L["Avisar a los que faltan"], 150, L["Avisar a los que faltan"],
        L["Susurra a cada integrante los buffos de banda, el frasco o la comida que le faltan. Solo a quien se puede leer (no en combate ni fuera de alcance)."],
        function()
            local members, available = T.GetGroupStatus()
            local sent = 0
            for _, m in ipairs(members) do
                local scan = m.scan
                if scan and m.online and not addonTable.IsMe(m.fullName) then
                    local missing = {}
                    for _, key in ipairs(available) do
                        if not scan.buffs[key] then table.insert(missing, (T.GetBuffInfo(key))) end
                    end
                    if not scan.flask then table.insert(missing, L["frasco o elixir"]) end
                    if not scan.food then table.insert(missing, L["comida"]) end
                    if #missing > 0 then
                        SendWhisper(m.fullName, L["[GuildControl] Te falta: "] .. table.concat(missing, ", "))
                        sent = sent + 1
                    end
                end
            end
            PrintGC(string.format(L["Aviso de buffos enviado a %d jugadores."], sent))
        end)
    btnWarn:SetPoint("RIGHT", btnRefresh, "LEFT", -6, 0)

    -- Cabecera de columnas
    local header = CreateFrame("Frame", nil, frame)
    header:SetSize(600, 16)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -56)
    for _, col in ipairs({
        { L["Jugador"], BUFF_COLS.name }, { L["Gr."], BUFF_COLS.group }, { L["Buffos de banda"], BUFF_COLS.buffs },
        { L["Frasco"], BUFF_COLS.flask }, { L["Comida"], BUFF_COLS.food }, { L["Runa"], BUFF_COLS.rune },
        { L["Pociones"], BUFF_COLS.potions },
    }) do
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", header, "LEFT", col[2], 0)
        fs:SetText(col[1])
    end

    local listBox = CreateBackdropBox(frame, 620, 316, "TOPLEFT", frame, "TOPLEFT", 10, -74)
    local scroll = CreateFrame("ScrollFrame", nil, listBox, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", listBox, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -26, 4)
    local child = CreateFrame("Frame")
    child:SetSize(590, 1)
    scroll:SetScrollChild(child)

    local empty = listBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("CENTER")
    empty:SetText(L["No estás en un grupo."])

    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", listBox, "BOTTOMLEFT", 4, -6)
    note:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    note:SetJustifyH("LEFT")
    note:SetText(L["Los buffos se leen de cada jugador (no en combate ni fuera de alcance). Las pociones solo se ven de quien usa GuildControl. Los buffos de banda solo cuentan si alguien del grupo puede darlos."])

    local rows = {}
    local function StatusIcon(row, key)
        local tex = row:CreateTexture(nil, "ARTWORK")
        tex:SetSize(16, 16)
        tex:SetPoint("LEFT", row, "LEFT", BUFF_COLS[key] + 10, 0)
        return tex
    end
    local function AcquireRow(index)
        local row = rows[index]
        if row then return row end
        row = CreateFrame("Frame", nil, child)
        row:SetSize(590, BUFF_ROW_HEIGHT)
        row:EnableMouse(true)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row, "LEFT", BUFF_COLS.name, 0)
        row.name:SetWidth(148)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.group = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.group:SetPoint("LEFT", row, "LEFT", BUFF_COLS.group + 4, 0)
        row.buffIcons = {}
        for i = 1, #T.RAID_BUFFS do
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(18, 18)
            icon:SetPoint("LEFT", row, "LEFT", BUFF_COLS.buffs + (i - 1) * 21, 0)
            row.buffIcons[i] = icon
        end
        row.flask = StatusIcon(row, "flask")
        row.food = StatusIcon(row, "food")
        row.rune = StatusIcon(row, "rune")
        row.potions = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.potions:SetPoint("LEFT", row, "LEFT", BUFF_COLS.potions + 14, 0)
        row:SetScript("OnEnter", function(self)
            local m = self.member
            if not m then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(m.short, 1, 1, 1)
            for _, key in ipairs(self.available or {}) do
                local name = T.GetBuffInfo(key)
                local has = m.scan and m.scan.buffs[key]
                GameTooltip:AddDoubleLine(name, has and L["|cFF00FF00Sí|r"] or L["|cFFFF3333Falta|r"])
            end
            if m.report then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["En las bolsas:"], 1, 0.82, 0)
                GameTooltip:AddDoubleLine(L["Pociones"], m.report.potions, 0.8, 0.8, 0.8, 1, 1, 1)
                GameTooltip:AddDoubleLine(L["Frascos"], m.report.flasks, 0.8, 0.8, 0.8, 1, 1, 1)
                GameTooltip:AddDoubleLine(L["Comida"], m.report.food, 0.8, 0.8, 0.8, 1, 1, 1)
                GameTooltip:AddDoubleLine(L["Runas y pergaminos"], m.report.runes, 0.8, 0.8, 0.8, 1, 1, 1)
            else
                GameTooltip:AddLine(L["Sin GuildControl: no se ven sus bolsas."], 0.6, 0.6, 0.6, true)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[index] = row
        return row
    end

    local function SetStatus(tex, value)
        if value == nil then tex:SetTexture(CHECK_TEXTURES.unknown) else tex:SetTexture(value and CHECK_TEXTURES.ready or CHECK_TEXTURES.notReady) end
    end

    function frame.Refresh()
        if not frame:IsShown() then return end
        local members, available = T.GetGroupStatus()
        for _, row in ipairs(rows) do row:Hide() end
        local missingFlask, missingFood, missingRune, missingBuffs, unreadable = 0, 0, 0, 0, 0
        for i, m in ipairs(members) do
            local row = AcquireRow(i)
            row.member, row.available = m, available
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * BUFF_ROW_HEIGHT)
            local scan = m.scan
            local nameColor = m.online and ("|cFF" .. addonTable.GetClassColorHex(m.class)) or "|cFF808080"
            row.name:SetText(nameColor .. m.short .. "|r" .. (scan and "" or (m.online and L[" |cFF808080(lejos)|r"] or L[" |cFF808080(desc.)|r"])))
            row.group:SetText(m.group)
            local lacksBuff = false
            for b, icon in ipairs(row.buffIcons) do
                local key = available[b]
                if key then
                    local _, texture = T.GetBuffInfo(key)
                    icon:SetTexture(texture or CHECK_TEXTURES.unknown)
                    local has = scan and scan.buffs[key]
                    icon:SetDesaturated(not has)
                    icon:SetAlpha(has and 1 or 0.3)
                    if scan and not has then lacksBuff = true end
                    icon:Show()
                else
                    icon:Hide()
                end
            end
            SetStatus(row.flask, scan and scan.flask)
            SetStatus(row.food, scan and scan.food)
            SetStatus(row.rune, scan and scan.rune)
            if m.report then
                row.potions:SetText((m.report.potions > 0 and "|cFFFFFFFF" or "|cFFFF3333") .. m.report.potions .. "|r")
            else
                row.potions:SetText("|cFF808080-|r")
            end
            if scan then
                if not scan.flask then missingFlask = missingFlask + 1 end
                if not scan.food then missingFood = missingFood + 1 end
                if not scan.rune then missingRune = missingRune + 1 end
                if lacksBuff then missingBuffs = missingBuffs + 1 end
            else
                unreadable = unreadable + 1
            end
            local bad = scan and (not scan.flask or not scan.food or lacksBuff)
            row.bg:SetColorTexture(bad and 0.6 or 1, bad and 0.1 or 1, bad and 0.1 or 1, bad and 0.12 or (i % 2 == 0 and 0.04 or 0))
            row:Show()
        end
        child:SetHeight(math.max(1, #members * BUFF_ROW_HEIGHT))
        empty:SetShown(#members == 0)
        local parts = { L["Integrantes: "] .. "|cFFFFFFFF" .. #members .. "|r" }
        table.insert(parts, L["Sin frasco: "] .. "|cFFFF7F00" .. missingFlask .. "|r")
        table.insert(parts, L["Sin comida: "] .. "|cFFFF7F00" .. missingFood .. "|r")
        table.insert(parts, L["Sin runa: "] .. "|cFFFF7F00" .. missingRune .. "|r")
        table.insert(parts, L["Faltan buffos: "] .. "|cFFFF7F00" .. missingBuffs .. "|r")
        if unreadable > 0 then table.insert(parts, L["Sin leer: "] .. "|cFF808080" .. unreadable .. "|r") end
        if InCombatLockdown() then table.insert(parts, L["|cFFFF3333En combate|r"]) end
        summary:SetText(table.concat(parts, "   "))
    end

    -- Se refresca con los cambios del grupo y de auras, como mucho dos veces por segundo
    local pending = false
    local function QueueRefresh()
        if pending or not frame:IsShown() then return end
        pending = true
        C_Timer.After(0.5, function()
            pending = false
            frame.Refresh()
        end)
    end
    -- Los eventos (UNIT_AURA llega sin parar en banda) solo se escuchan con la ventana abierta
    local BUFF_EVENTS = { "GROUP_ROSTER_UPDATE", "UNIT_AURA", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "BAG_UPDATE_DELAYED" }
    local events = CreateFrame("Frame")
    events:SetScript("OnEvent", QueueRefresh)
    T.AddListener(QueueRefresh)
    frame:SetScript("OnShow", function()
        for _, event in ipairs(BUFF_EVENTS) do events:RegisterEvent(event) end
        frame.Refresh()
    end)
    frame:SetScript("OnHide", function() events:UnregisterAllEvents() end)
    return frame
end

-- Muestra la ventana de buffos (anchor opcional: el marco junto al que se abre)
function uiModule.ShowBuffWindow(anchor)
    if not addonTable.RaidTools then return end
    if not buffFrame then buffFrame = CreateBuffFrame() end
    buffFrame:ClearAllPoints()
    if anchor and anchor:IsShown() then
        buffFrame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    else
        buffFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
    buffFrame:Show()
    buffFrame:Raise()
    buffFrame.Refresh()
end

-- -------------------------------------------------------------------------
-- Ayudante (panel pequeño para la banda; antes «modo minimalista»)
-- -------------------------------------------------------------------------
-- El panel tiene botones seguros (las marcas): en combate no se puede mostrar ni ocultar, así
-- que el cambio de modo se aplaza hasta salir del combate
local pendingAfterCombat = nil
local afterCombatFrame = CreateFrame("Frame")
afterCombatFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local fn = pendingAfterCombat
    pendingAfterCombat = nil
    if fn then fn() end
end)
local function AfterCombat(fn)
    if not InCombatLockdown() then
        fn()
        return
    end
    pendingAfterCombat = fn
    afterCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    PrintGC(L["En combate no se puede cambiar de modo: se hará al salir del combate."])
end

local MINI = { width = 244, height = 138, pad = 8, gap = 4 }

local function SaveMiniPosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    GuildControlDB.settings.raidMiniPos = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function CreateRaidMiniFrame()
    local T = addonTable.RaidTools
    local frame = CreateBackdropBox(UIParent, MINI.width, MINI.height)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveMiniPosition(self)
    end)
    frame:Hide()

    local pos = GuildControlDB.settings.raidMiniPos
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end

    -- Título y cierre
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", MINI.pad + 2, -8)
    title:SetText(L["GuildControl · Ayudante"])
    local btnClose = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    btnClose:SetSize(22, 22)
    btnClose:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 1)
    btnClose:SetScript("OnClick", function()
        AfterCombat(function()
            GuildControlDB.settings.raidMini = false
            frame:Hide()
        end)
    end)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.1)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", MINI.pad, -22)
    line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -MINI.pad, -22)

    local inner = MINI.width - MINI.pad * 2

    -- Fila 1: listos y pull
    local width1 = (inner - MINI.gap * 3) / 4
    local row1 = {
        MiniButton(frame, L["Listos"], width1, L["Comprobación de listos"], L["Lanza la comprobación de listos (líder o ayudante)."], function() T.ReadyCheck() end),
        MiniButton(frame, L["Pull 10"], width1, L["Pull 10"], L["Cuenta atrás de 10 segundos para todo el grupo."], function() T.Pull(10) end),
        MiniButton(frame, L["Pull 5"], width1, L["Pull 5"], L["Cuenta atrás de 5 segundos para todo el grupo."], function() T.Pull(5) end),
        MiniButton(frame, L["Cancelar"], width1, L["Cancelar pull"], L["Cancela la cuenta atrás."], function() T.CancelPull() end),
    }
    for i, btn in ipairs(row1) do
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", MINI.pad + (i - 1) * (width1 + MINI.gap), -28)
    end

    -- Fila 2: marcas en el objetivo (8) y quitar marca
    local MARK_SIZE = 22
    local markGap = (inner - MARK_SIZE * 9) / 8
    for i = 1, 9 do
        -- SetRaidTarget está protegida: las marcas son botones seguros del tipo "raidtarget",
        -- que el juego ejecuta como si el jugador usara /tm
        local btn = CreateFrame("Button", "GC_RaidMiniMark" .. i, frame, "SecureActionButtonTemplate")
        btn:SetSize(MARK_SIZE, MARK_SIZE)
        btn:RegisterForClicks("AnyUp", "AnyDown")
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", MINI.pad + (i - 1) * (MARK_SIZE + markGap), -55)
        local index = i <= 8 and i or 0
        if index > 0 then
            btn:SetNormalTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index)
        else
            btn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        end
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        btn:SetAttribute("type", "raidtarget")
        btn:SetAttribute("unit", "target")
        btn:SetAttribute("action", index > 0 and "toggle" or "clear")
        btn:SetAttribute("marker", index)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(index > 0 and L[RAID_ICONS[index]] or L["Quitar marca"], 1, 1, 1)
            GameTooltip:AddLine(L["Se pone en tu objetivo."], 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Fila 3: descanso, buff check y botín
    local width3 = (inner - MINI.gap * 2) / 3
    -- Al pulsarlo se elige la duración: rápidas, la última usada u "Otro..." para escribirla
    local btnBreak
    btnBreak = MiniButton(frame, L["Descanso"], width3, L["Descanso"],
        L["Elige la duración y se avisa a la banda al empezar, a falta de 1 minuto y al terminar. Con un descanso en marcha puedes cancelarlo."],
        function(self)
            MenuUtil.CreateContextMenu(self, function(_, root)
                if T.IsOnBreak() then
                    root:CreateButton(L["|cFFFF3333Cancelar descanso|r"], function() T.CancelBreak() end)
                    return
                end
                local last = T.GetBreakMinutes()
                root:CreateTitle(L["Duración del descanso"])
                for _, minutes in ipairs({ 3, 5, 10, 15 }) do
                    root:CreateButton(string.format(L["%d minutos"], minutes) .. (minutes == last and L[" |cFF808080(última)|r"] or ""),
                        function() T.Break(minutes) end)
                end
                root:CreateButton(L["Otro…"], function()
                    StaticPopup_Show("GUILDCONTROL_BREAK_MINUTES", string.format(L["Minutos de descanso (%d-%d):"], T.BREAK_MIN, T.BREAK_MAX))
                end)
            end)
        end)
    T.AddListener(function()
        btnBreak:SetText(T.IsOnBreak() and L["|cFFFFD100Descanso…|r"] or L["Descanso"])
    end)
    local row3 = {
        btnBreak,
        MiniButton(frame, L["Buff check"], width3, L["Buff check"], L["Comprueba los buffos de la banda y abre una ventana con los buffos, frascos, comida, runas y pociones de cada uno; desde ella puedes susurrar lo que le falta a cada jugador. Púlsalo otra vez para cerrarla."], function()
            -- Segundo clic con la ventana abierta: la cierra
            if buffFrame and buffFrame:IsShown() then buffFrame:Hide(); return end
            if addonTable.RaidTools then addonTable.RaidTools.RequestReports() end
            uiModule.ShowBuffWindow(nil)
        end),
        MiniButton(frame, L["Botín"], width3, L["Botín"], L["Abre el botín en una ventana flotante sin salir del Ayudante."], function()
            uiModule.ToggleLootFloat()
        end),
    }
    for i, btn in ipairs(row3) do
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", MINI.pad + (i - 1) * (width3 + MINI.gap), -82)
    end
    -- Fila 4: pizarra de jefes (Board.lua; botón normal, no seguro) y volver a la ventana completa
    local width4 = (inner - MINI.gap) / 2
    local btnBoard = MiniButton(frame, L["Pizarra"], width4, L["Pizarra"],
        L["Abre la pizarra para explicar un jefe con marcas, roles, texto y dibujos; el líder, un ayudante o un oficial puede enseñarla al grupo o ponerla en vivo."],
        function() if addonTable.Board then addonTable.Board.Toggle() end end)
    btnBoard:SetPoint("TOPLEFT", frame, "TOPLEFT", MINI.pad, -108)
    local btnNormal = MiniButton(frame, L["Modo normal"], width4, L["Modo normal"], L["Vuelve a la ventana completa de GuildControl."], function() uiModule.ExitMiniMode() end)
    btnNormal:SetPoint("LEFT", btnBoard, "RIGHT", MINI.gap, 0)
    return frame
end

-- -------------------------------------------------------------------------
-- Botín en ventana flotante
-- -------------------------------------------------------------------------
-- La vista Botín se pasa a una ventana aparte (sobre todo para el Ayudante, que oculta
-- la principal). Al cerrarla vuelve a su sitio. settings.lootFloatPos guarda la posición.
local lootFloat = nil

local function ReturnLootView()
    local view = containers.views and containers.views["Botín"]
    if not view or not containers.mainContent then return end
    view:SetParent(containers.mainContent)
    view:ClearAllPoints()
    view:SetAllPoints(containers.mainContent)
    view:SetShown(activeTab == "Botín")
end

local function CreateLootFloat()
    local frame = CreateFrame("Frame", "GuildControlLootFloat", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(912, 560)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        GuildControlDB.settings.lootFloatPos = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)
    local pos = GuildControlDB.settings.lootFloatPos
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -40)
    end
    tinsert(UISpecialFrames, "GuildControlLootFloat")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
    title:SetText(L["GuildControl · Botín"])

    frame.holder = CreateFrame("Frame", nil, frame)
    frame.holder:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -26)
    frame.holder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    frame:SetScript("OnHide", ReturnLootView)
    frame:Hide()
    return frame
end

function uiModule.ShowLootFloat()
    addonTable.InitDB()
    if not GC_UI then uiModule.CreateUI() end
    local view = containers.views["Botín"]
    if not view then return end
    if not lootFloat then lootFloat = CreateLootFloat() end
    view:SetParent(lootFloat.holder)
    view:ClearAllPoints()
    view:SetAllPoints(lootFloat.holder)
    lootFloat:Show()
    lootFloat:Raise()
    view:Show()
end

function uiModule.HideLootFloat()
    if lootFloat and lootFloat:IsShown() then lootFloat:Hide() end
end

function uiModule.IsLootFloatShown()
    return lootFloat ~= nil and lootFloat:IsShown()
end

function uiModule.ToggleLootFloat()
    if uiModule.IsLootFloatShown() then uiModule.HideLootFloat() else uiModule.ShowLootFloat() end
end

function uiModule.EnterMiniMode(silent)
    if not addonTable.RaidTools then return end
    if addonTable.RaidTools.CanUseHelper and not addonTable.RaidTools.CanUseHelper() then
        if not silent then
            PrintGC(L["|cFFFF3333El Ayudante es para el líder del grupo, o para el líder y los ayudantes en banda. La pizarra y las tiradas se te abren cuando ellos las abren.|r"])
        end
        return
    end
    AfterCombat(function()
        addonTable.InitDB()
        if not raidMiniFrame then raidMiniFrame = CreateRaidMiniFrame() end
        GuildControlDB.settings.raidMini = true
        -- Si estabas en Botín, el botín sigue abierto en su ventana flotante
        local keepLoot = GC_UI and GC_UI:IsShown() and activeTab == "Botín"
        if GC_UI then GC_UI:Hide() end
        raidMiniFrame:Show()
        if keepLoot then uiModule.ShowLootFloat() end
    end)
end

function uiModule.ExitMiniMode()
    AfterCombat(function()
        GuildControlDB.settings.raidMini = false
        if raidMiniFrame then raidMiniFrame:Hide() end
        if not (GC_UI and GC_UI:IsShown()) then uiModule.ToggleUI() end
        SwitchTab("Raid")
    end)
end

function uiModule.IsMiniMode()
    return raidMiniFrame ~= nil and raidMiniFrame:IsShown()
end

-- Al entrar en el juego se recupera el Ayudante si estaba activo
local miniLoginFrame = CreateFrame("Frame")
miniLoginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
miniLoginFrame:SetScript("OnEvent", function(self, _, isInitialLogin, isReloadingUi)
    if not (isInitialLogin or isReloadingUi) then return end
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if GuildControlDB and GuildControlDB.settings and GuildControlDB.settings.raidMini then
        C_Timer.After(1, function() uiModule.EnterMiniMode(true) end)
    end
end)


-- =========================================================================
-- 12. DKP: AJUSTES Y AJUSTE MANUAL (OFICIALES)
-- =========================================================================
local dkpSettingsFrame = nil
local DKP_SETTING_FIELDS = {
    { key = "boss", label = "DKP por jefe de banda" },
    { key = "raid", label = "DKP por banda completada" },
    { key = "seniority", label = "DKP semanales por antigüedad" },
    { key = "decay", label = "Decay semanal (%)" },
    { key = "minBid", label = "Puja mínima" },
    { key = "offspec", label = "Off-spec paga (% del precio)" },
    { key = "gate", label = "DKP mínimos para piezas de Mítica" },
    { key = "minAttendance", label = "Asistencia mínima (%; 0 = no)" },
}

function uiModule.ShowDkpSettings()
    local D = addonTable.Dkp
    if not D or not (addonTable.Profiles and addonTable.Profiles.IsOfficer()) then return end
    if not dkpSettingsFrame then
        local frame = CreateFrame("Frame", "GuildControlDkpSettingsFrame", UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(320, 370)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetToplevel(true)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        tinsert(UISpecialFrames, "GuildControlDkpSettingsFrame")
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
        frame.title:SetText(L["Ajustes de DKP"])

        -- Reparto: precio fijo o subasta
        frame.modeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.modeButton:SetSize(284, 22)
        frame.modeButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -34)
        local function ModeText()
            frame.modeButton:SetText(L["Reparto: "] .. (frame.mode == "auction" and L["Subasta abierta"] or L["Precio fijo"]))
        end
        frame.ModeText = ModeText
        frame.modeButton:SetScript("OnClick", function()
            frame.mode = frame.mode == "auction" and "fixed" or "auction"
            ModeText()
        end)

        frame.inputs = {}
        for i, field in ipairs(DKP_SETTING_FIELDS) do
            local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -70 - (i - 1) * 28)
            label:SetText(L[field.label])
            local input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
            input:SetSize(60, 20)
            input:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -22, -66 - (i - 1) * 28)
            input:SetAutoFocus(false)
            input:SetNumeric(true)
            input:SetMaxLetters(4)
            input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            frame.inputs[field.key] = input
        end

        local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -294)
        hint:SetWidth(284)
        hint:SetJustifyH("LEFT")
        hint:SetText(L["La antigüedad cuenta desde que cada jugador rellena Mi perfil. El decay y los DKP de antigüedad se aplican en cada reinicio semanal."])

        local btnSave = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btnSave:SetSize(110, 22)
        btnSave:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
        btnSave:SetText(L["Guardar"])
        btnSave:SetScript("OnClick", function()
            local values = {}
            for key, input in pairs(frame.inputs) do values[key] = input:GetText() end
            if D.SetSettings(values) then
                if frame.mode ~= D.GetMode() then D.SetMode(frame.mode) end
                PrintGC(L["Ajustes de DKP guardados y enviados a la hermandad."])
                frame:Hide()
            end
        end)
        dkpSettingsFrame = frame
    end
    local settings = D.GetSettings()
    for key, input in pairs(dkpSettingsFrame.inputs) do input:SetText(tostring(settings[key] or 0)) end
    dkpSettingsFrame.mode = D.GetMode()
    dkpSettingsFrame.ModeText()
    dkpSettingsFrame:Show()
end

-- Clic derecho en un jugador de la lista de DKP: sumar (o restar con -) una cantidad
-- Ventana de pedido a un artesano (Profesiones > Artesanos y pedidos > Pedir): nota y si
-- quien pide aporta los materiales
local orderDialog = nil
function uiModule.ShowOrderDialog(crafter, recipeID, recipeName)
    if not orderDialog then
        local f = CreateFrame("Frame", "GuildControlOrderFrame", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(380, 190)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        tinsert(UISpecialFrames, "GuildControlOrderFrame")
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("CENTER", f.TitleBg, "CENTER", 0, 0)
        f.title:SetText(L["Pedir a un artesano"])
        f.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.info:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -34)
        f.info:SetPoint("RIGHT", f, "RIGHT", -16, 0)
        f.info:SetJustifyH("LEFT")
        local noteLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noteLabel:SetPoint("TOPLEFT", f.info, "BOTTOMLEFT", 0, -12)
        noteLabel:SetText(L["Nota (cantidad, detalles...)"])
        f.note = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        f.note:SetSize(340, 20)
        f.note:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 6, -4)
        f.note:SetAutoFocus(false)
        f.note:SetMaxLetters(80)
        f.note:SetScript("OnEscapePressed", function() f:Hide() end)
        f.mats = CreateFrame("CheckButton", "GuildControlOrderMats", f, "UICheckButtonTemplate")
        f.mats:SetSize(24, 24)
        f.mats:SetPoint("TOPLEFT", f.note, "BOTTOMLEFT", -8, -8)
        _G[f.mats:GetName() .. "Text"]:SetText(L["Aporto los materiales"])
        f.send = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.send:SetSize(110, 22)
        f.send:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 14)
        f.send:SetText(L["Pedir"])
        f.cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.cancel:SetSize(110, 22)
        f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 14)
        f.cancel:SetText(CANCEL)
        f.cancel:SetScript("OnClick", function() f:Hide() end)
        uiModule.AddTips({
            { f.note, "Nota", "Cantidad, calidad o lo que quieras decirle al artesano. Intro envía el pedido." },
            { f.mats, "Aporto los materiales", "Marca esta casilla si le darás tú los materiales al artesano." },
            { f.send, "Pedir", "Envía el pedido al artesano. Le llega un aviso y lo verá en «Me piden»." },
        })
        local function Send()
            local C = addonTable.Community
            if C and C.CreateOrder and f.crafter then
                local order = C.CreateOrder(f.crafter, f.recipeID, f.note:GetText() or "", f.mats:GetChecked() and true or false)
                if order then PrintGC(L["Pedido enviado. Te avisará cuando lo acepte o lo termine."]) end
            end
            f:Hide()
        end
        f.send:SetScript("OnClick", Send)
        f.note:SetScript("OnEnterPressed", Send)
        orderDialog = f
    end
    local f = orderDialog
    f.crafter, f.recipeID = crafter, recipeID
    f.info:SetText(string.format(L["Pedido a %s:\n|cFFFFD100%s|r"], ColoredMemberName(crafter), recipeName or ("#" .. tostring(recipeID))))
    f.note:SetText("")
    f.mats:SetChecked(false)
    f:Show()
    f:Raise()
    f.note:SetFocus()
end

-- Duración del descanso a mano (botón Descanso > Otro… del Ayudante)
StaticPopupDialogs["GUILDCONTROL_BREAK_MINUTES"] = {
    text = "%s",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 2,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self)
        local box = self.EditBox or self.editBox
        local T = addonTable.RaidTools
        if box then box:SetNumeric(true); box:SetText(tostring(T and T.GetBreakMinutes() or 5)); box:SetFocus(); box:HighlightText() end
    end,
    OnAccept = function(self)
        local box = self.EditBox or self.editBox
        local minutes = box and tonumber(box:GetText())
        local T = addonTable.RaidTools
        if minutes and minutes > 0 and T then T.Break(math.min(T.BREAK_MAX, math.max(T.BREAK_MIN, minutes))) end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["GUILDCONTROL_BREAK_MINUTES"].OnAccept(parent)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["GUILDCONTROL_DKP_ADJUST"] = {
    text = "%s",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 6,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self)
        local box = self.EditBox or self.editBox
        if box then box:SetText(""); box:SetFocus() end
    end,
    OnAccept = function(self, data)
        local box = self.EditBox or self.editBox
        local amount = box and tonumber(box:GetText())
        if data and amount and amount ~= 0 and addonTable.Dkp then
            addonTable.Dkp.Adjust({ data }, amount, L["Ajuste manual"])
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local onAccept = parent and StaticPopupDialogs["GUILDCONTROL_DKP_ADJUST"].OnAccept
        if onAccept then onAccept(parent, parent.data) end
        if parent then parent:Hide() end
    end,
    EditBoxOnEscapePressed = function(self)
        local parent = self:GetParent()
        if parent then parent:Hide() end
    end,
}

function uiModule.ShowDkpAdjust(fullName)
    if not addonTable.Dkp or not (addonTable.Profiles and addonTable.Profiles.IsOfficer()) then return end
    local short = string.match(fullName, "^([^-]+)") or fullName
    StaticPopup_Show("GUILDCONTROL_DKP_ADJUST",
        L["DKP para "] .. short .. L[" (ahora "] .. addonTable.Dkp.GetBalance(fullName) .. L["). Escribe la cantidad (usa - para restar):"],
        nil, fullName)
end

-- Precio de un objeto concreto (botón Precio de Tirada, oficiales). "Predeterminado" vuelve al
-- de la tabla de precios.
StaticPopupDialogs["GUILDCONTROL_ITEM_PRICE"] = {
    text = "%s",
    button1 = ACCEPT,
    button2 = CANCEL,
    button3 = "",
    hasEditBox = true,
    maxLetters = 6,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self, data)
        data = data or self.data
        local box = self.EditBox or self.editBox
        if box then box:SetNumeric(true); box:SetText(tostring(data and data.price or "")); box:SetFocus(); box:HighlightText() end
        local third = self.button3 or (self.GetButton and self:GetButton(3))
        if third then third:SetText(L["Predeterminado"]) end
    end,
    OnAccept = function(self, data)
        local box = self.EditBox or self.editBox
        local price = box and tonumber(box:GetText())
        if data and price and addonTable.Loot then addonTable.Loot.SetItemPrice(data.key, price) end
    end,
    OnAlt = function(self, data)
        if data and addonTable.Loot then addonTable.Loot.SetItemPrice(data.key, nil) end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["GUILDCONTROL_ITEM_PRICE"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

function uiModule.ShowItemPrice(key)
    local LT, D = addonTable.Loot, addonTable.Dkp
    if not LT or not D or not (addonTable.Profiles and addonTable.Profiles.IsOfficer()) then return end
    local item = LT.GetItem(key)
    if not item then return end
    local default = D.GetDefaultPrice(item.link, item.difficultyID)
    StaticPopup_Show("GUILDCONTROL_ITEM_PRICE",
        L["Precio en DKP de "] .. LT.DisplayLink(item.link) .. L[" (predeterminado: "] .. default .. "):",
        nil, { key = key, price = LT.GetItemPrice(item) })
end

-- Tabla de precios por hueco y dificultad (oficiales)
local dkpPricesFrame = nil
local PRICE_TIER_LABELS = { normal = "Normal", heroic = "Heroica", mythic = "Mítica" }

function uiModule.ShowDkpPrices()
    local D = addonTable.Dkp
    if not D or not (addonTable.Profiles and addonTable.Profiles.IsOfficer()) then return end
    if not dkpPricesFrame then
        local frame = CreateFrame("Frame", "GuildControlDkpPricesFrame", UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(520, 340)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetToplevel(true)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        tinsert(UISpecialFrames, "GuildControlDkpPricesFrame")
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
        frame.title:SetText(L["Precios de los objetos (DKP)"])

        local COLS = { normal = 296, heroic = 366, mythic = 436 }
        for tier, x in pairs(COLS) do
            local head = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            head:SetPoint("TOP", frame, "TOPLEFT", x + 30, -36)
            head:SetText(L[PRICE_TIER_LABELS[tier]])
        end
        frame.inputs = {}
        for i, category in ipairs(D.ITEM_CATEGORIES) do
            local y = -58 - (i - 1) * 28
            local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, y - 4)
            label:SetWidth(270)
            label:SetJustifyH("LEFT")
            label:SetText(L[category.label])
            frame.inputs[category.key] = {}
            for tier, x in pairs(COLS) do
                local input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
                input:SetSize(56, 20)
                input:SetPoint("TOPLEFT", frame, "TOPLEFT", x + 6, y)
                input:SetAutoFocus(false)
                input:SetNumeric(true)
                input:SetMaxLetters(6)
                input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                frame.inputs[category.key][tier] = input
            end
        end

        local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -258)
        hint:SetWidth(484)
        hint:SetJustifyH("LEFT")
        hint:SetText(L["El precio de cada objeto sale de esta tabla según su hueco y la dificultad en la que cayó. Con el botón Precio de Tirada se cambia el de un objeto concreto."])

        local function Fill(prices)
            for key, row in pairs(frame.inputs) do
                for tier, input in pairs(row) do input:SetText(tostring(prices[key] and prices[key][tier] or 0)) end
            end
        end
        frame.Fill = Fill

        local btnSave = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btnSave:SetSize(120, 22)
        btnSave:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 12)
        btnSave:SetText(L["Guardar"])
        btnSave:SetScript("OnClick", function()
            local prices = {}
            for key, row in pairs(frame.inputs) do
                prices[key] = {}
                for tier, input in pairs(row) do prices[key][tier] = input:GetText() end
            end
            if D.SetPrices(prices) then
                PrintGC(L["Precios guardados y enviados a la hermandad."])
                frame:Hide()
            end
        end)
        local btnDefaults = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btnDefaults:SetSize(170, 22)
        btnDefaults:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 12)
        btnDefaults:SetText(L["Valores recomendados"])
        btnDefaults:SetScript("OnClick", function() Fill(D.DEFAULT_PRICES) end)
        dkpPricesFrame = frame
    end
    dkpPricesFrame.Fill(D.GetPrices())
    dkpPricesFrame:Show()
end

-- =========================================================================
-- 13. TAREA PENDIENTE: RELLENAR MI PERFIL
-- =========================================================================
-- Al entrar en el juego, quien no ha rellenado Mi perfil ve una ventanita que se lo recuerda
-- (la antigüedad del DKP empieza a contar desde ese momento). "Más tarde" la oculta hasta la
-- próxima vez que entre.
local taskFrame = nil

local function NeedsProfile()
    if not IsInGuild() or not addonTable.Profiles then return false end
    local profile = addonTable.Profiles.GetMyProfile()
    -- Las clases que solo pueden ser DPS ya tienen el rol, pero el resto de Mi perfil (principal o
    -- alter, especialización) también hay que rellenarlo una vez
    return not profile.main or not profile.savedAt
end

-- Tareas de la ventana: rellenar Mi perfil y apuntarse a las bandas que recuerdan los oficiales
-- force: incluir Mi perfil aunque ya esté rellenado (herramientas de desarrollador)
local function PendingTasks(force)
    local tasks = {}
    if force or NeedsProfile() then
        table.insert(tasks, {
            icon = "Interface\\Icons\\INV_Misc_Note_01", heading = L["Rellena Mi perfil"],
            text = L["Indica tu rol, tu especialización y si es tu personaje principal. Los oficiales lo usan para los rosters y las bandas, y tu antigüedad en el DKP empieza a contar cuando lo guardas."],
            goLabel = L["Ir a Mi perfil"], tab = "Mi perfil",
        })
    end
    local E = addonTable.RaidEvents
    for _, event in ipairs(IsInGuild() and E and E.GetMyReminders and E.GetMyReminders() or {}) do
        table.insert(tasks, {
            icon = "Interface\\Icons\\INV_Misc_Bell_01", heading = L["Recordatorio de banda"],
            text = string.format(L["Estás en el roster de |cFFFFD100%s|r (%s) y todavía no te has apuntado. Los oficiales te piden que respondas en Raid."],
                event.title, RaidEventDateText(event, true)),
            goLabel = L["Ir a Raid"], tab = "Raid", eventKey = event.id .. ":" .. event.remind.at,
        })
    end
    return tasks
end

function uiModule.ShowProfileTask(force)
    local tasks = PendingTasks(force)
    if #tasks == 0 then
        if taskFrame then taskFrame:Hide() end
        return
    end
    if not taskFrame then
        local frame = CreateFrame("Frame", "GuildControlTaskFrame", UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(360, 170)
        frame:SetPoint("TOP", UIParent, "TOP", 0, -180)
        frame:SetFrameStrata("DIALOG")
        frame:SetToplevel(true)
        frame:SetClampedToScreen(true)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
        frame.title:SetText(L["GuildControl · Tarea pendiente"])

        frame.icon = frame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetSize(36, 36)
        frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)

        frame.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.heading:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, -2)

        frame.counter = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        frame.counter:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -34)

        frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.text:SetPoint("TOPLEFT", frame.heading, "BOTTOMLEFT", 0, -6)
        frame.text:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
        frame.text:SetJustifyH("LEFT")

        -- Una tarea cada vez: "Más tarde" pasa a la siguiente y cierra con la última
        function frame.ShowTask(index)
            local task = frame.tasks[index]
            if not task then frame:Hide(); return end
            frame.index = index
            frame.icon:SetTexture(task.icon)
            frame.heading:SetText(task.heading)
            frame.text:SetText(task.text)
            frame.btnGo:SetText(task.goLabel)
            frame.counter:SetText(#frame.tasks > 1 and (index .. "/" .. #frame.tasks) or "")
            frame.btnLater:SetText(index < #frame.tasks and L["Siguiente"] or L["Más tarde"])
            if task.eventKey then frame.shown[task.eventKey] = true end
        end

        frame.btnGo = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.btnGo:SetSize(150, 24)
        frame.btnGo:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 14)
        frame.btnGo:SetScript("OnClick", function()
            local task = frame.tasks[frame.index]
            frame:Hide()
            if uiModule.IsMiniMode and uiModule.IsMiniMode() then uiModule.ExitMiniMode() end
            if not (GC_UI and GC_UI:IsShown()) then uiModule.ToggleUI() end
            SwitchTab(task and task.tab or "Mi perfil")
        end)
        frame.btnLater = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.btnLater:SetSize(150, 24)
        frame.btnLater:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 14)
        frame.btnLater:SetScript("OnClick", function() frame.ShowTask(frame.index + 1) end)
        frame.shown = {}   -- recordatorios ya vistos en esta sesión
        taskFrame = frame
    end
    taskFrame.tasks = tasks
    taskFrame.ShowTask(1)
    taskFrame:Show()
end

-- Los recordatorios suelen llegar unos segundos después de entrar (respuesta a Q de las bandas):
-- si aparece uno que no se ha visto en esta sesión, se abre la ventana
if addonTable.RaidEvents and addonTable.RaidEvents.AddListener then
    addonTable.RaidEvents.AddListener(function()
        if not GuildControlDB or InCombatLockdown() or not IsInGuild() then return end
        if taskFrame and taskFrame:IsShown() then return end
        local E = addonTable.RaidEvents
        for _, event in ipairs(E.GetMyReminders and E.GetMyReminders() or {}) do
            if not (taskFrame and taskFrame.shown[event.id .. ":" .. event.remind.at]) then
                uiModule.ShowProfileTask()
                return
            end
        end
    end)
end

local taskLoginFrame = CreateFrame("Frame")
taskLoginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
taskLoginFrame:SetScript("OnEvent", function(self, _, isInitialLogin, isReloadingUi)
    if not (isInitialLogin or isReloadingUi) then return end
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- Nada más conectarse; si la hermandad aún no ha llegado se vuelve a mirar cada segundo
    local tries = 0
    local function Try()
        tries = tries + 1
        if not GuildControlDB or InCombatLockdown() then return end
        if not IsInGuild() and tries < 15 then
            C_Timer.After(1, Try)
            return
        end
        uiModule.ShowProfileTask()
    end
    C_Timer.After(1, Try)
end)
