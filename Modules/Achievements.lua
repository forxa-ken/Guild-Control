local addonName, addonTable = ...
local L = addonTable.L

addonTable.Achievements = {}
local achModule = addonTable.Achievements

local MAX_MEMBERS_SHOWN = 30

-- Modo de la vista: logros de la hermandad ("guild") o del personaje ("player")
local mode = "guild"

function achModule.GetMode() return mode end
function achModule.IsGuildMode() return mode == "guild" end
function achModule.SetMode(newMode)
    mode = (newMode == "player") and "player" or "guild"
end

-- Carga la UI de logros de Blizzard si aún no está cargada
function achModule.EnsureLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn then
        if not C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI") then
            C_AddOns.LoadAddOn("Blizzard_AchievementUI")
        end
    end
end

-- Categorías del modo actual (hermandad o personaje): { {id, title, parent, isChild}, ... }
function achModule.GetCategories()
    local result = {}
    local list
    if mode == "guild" then
        list = GetGuildCategoryList and GetGuildCategoryList() or nil
    else
        list = GetCategoryList and GetCategoryList() or nil
    end

    if list then
        for _, catId in ipairs(list) do
            local title, parentID = GetCategoryInfo(catId)
            table.insert(result, {
                id = catId,
                title = title or (L["Cat "] .. catId),
                parent = parentID,
                isChild = (parentID ~= nil and parentID > 0),
            })
        end
    end
    return result
end

-- Logro de temporada: su nombre o descripción habla de una temporada (Mítica+, bandas, JcJ)
-- o pertenece a la categoría de eventos del mundo. El juego no tiene un indicador propio.
local SEASON_WORDS = { "temporada", "season" }
local EVENT_CATEGORY_WORDS = { "evento", "event" }

local function ContainsAny(text, words)
    if not text or text == "" then return false end
    text = string.lower(text)
    for _, word in ipairs(words) do
        if string.find(text, word, 1, true) then return true end
    end
    return false
end

function achModule.IsSeasonal(name, description, categoryTitle)
    return ContainsAny(name, SEASON_WORDS)
        or ContainsAny(description, SEASON_WORDS)
        or ContainsAny(categoryTitle, EVENT_CATEGORY_WORDS)
end

-- Formatea fecha de logro (el año viene en 2 dígitos)
function achModule.FormatDate(day, month, year)
    return string.format("%02d/%02d/20%02d", day or 0, month or 0, year or 0)
end

-- Estadísticas de logros del modo actual
function achModule.GetStats()
    local stats = {
        totalPoints = 0,
        completedCount = 0,
        totalCount = 0,
        latestName = L["Ninguno"],
        latestDate = "",
    }

    if GetTotalAchievementPoints then
        stats.totalPoints = GetTotalAchievementPoints(mode == "guild") or 0
    end

    -- El juego solo tiene todos los datos de logros con su interfaz de logros cargada; sin
    -- ella GetNumCompletedAchievements puede quedarse corto (p. ej. 51 en vez de 63)
    achModule.EnsureLoaded()
    if GetNumCompletedAchievements then
        local total, completed = GetNumCompletedAchievements(mode == "guild")
        stats.totalCount = total or 0
        stats.completedCount = completed or 0
    end

    -- Hermandad: recuento por categorías, como lo muestra la ventana de logros; se usa el mayor
    local list = (mode == "guild") and GetGuildCategoryList and GetGuildCategoryList()
    if list and GetCategoryNumAchievements then
        local total, completed = 0, 0
        for _, catId in ipairs(list) do
            local ok, numItems, numCompleted = pcall(GetCategoryNumAchievements, catId, true)
            if ok then
                total = total + (numItems or 0)
                completed = completed + (numCompleted or 0)
            end
        end
        if completed > stats.completedCount then stats.completedCount = completed end
        if total > stats.totalCount then stats.totalCount = total end
    end

    if GetLatestCompletedAchievements then
        local latest = { GetLatestCompletedAchievements(mode == "guild") }
        local latestId = latest[1]
        if latestId then
            local _, name, _, completed, month, day, year = GetAchievementInfo(latestId)
            if name then
                stats.latestName = name
                if completed then
                    stats.latestDate = achModule.FormatDate(day, month, year)
                end
            end
        end
    end

    return stats
end

-- Solicita al servidor los miembros que completaron el logro (si la API existe)
function achModule.RequestMembers(id)
    if id and SetFocusedAchievement then
        pcall(SetFocusedAchievement, id)
    end
end

-- Devuelve (listaDeNombres, totalMiembros, disponible)
-- disponible = false si la API no existe en esta versión del juego
function achModule.GetMembers(id)
    local names = {}
    if not id or not GetGuildAchievementNumMembers or not GetGuildAchievementMemberInfo then
        return names, 0, false
    end

    local okNum, total = pcall(GetGuildAchievementNumMembers, id)
    if not okNum or type(total) ~= "number" then
        return names, 0, false
    end

    for i = 1, total do
        local ok, name = pcall(GetGuildAchievementMemberInfo, id, i)
        if ok and type(name) == "string" and name ~= "" then
            table.insert(names, Ambiguate(name, "guild"))
        end
    end
    table.sort(names)
    return names, total, true
end

-- Detalle completo de un logro para tooltip y vista previa
function achModule.GetDetails(id)
    if not id then return nil end

    local aId, name, points, completed, month, day, year, description, flags, icon,
          rewardText, isGuild, wasEarnedByMe, earnedBy = GetAchievementInfo(id)
    if not aId then return nil end

    local details = {
        id = aId,
        name = name or L["Desconocido"],
        points = points or 0,
        completed = completed and true or false,
        date = completed and achModule.FormatDate(day, month, year) or nil,
        description = description or "",
        icon = icon,
        rewardText = rewardText or "",
        isGuild = isGuild,
        wasEarnedByMe = wasEarnedByMe,
        earnedBy = (earnedBy and earnedBy ~= "") and Ambiguate(earnedBy, "guild") or nil,
        criteria = {},
        criteriaDone = 0,
    }

    local numCriteria = GetAchievementNumCriteria and GetAchievementNumCriteria(id) or 0
    for i = 1, numCriteria do
        local cName, _, cDone, qty, req = GetAchievementCriteriaInfo(id, i)
        if cName then
            table.insert(details.criteria, {
                name = cName,
                done = cDone and true or false,
                qty = qty or 0,
                req = req or 0,
            })
            if cDone then details.criteriaDone = details.criteriaDone + 1 end
        end
    end

    return details
end

function achModule.GetMaxMembersShown()
    return MAX_MEMBERS_SHOWN
end

-- Abre la ventana de logros de Blizzard en ese logro concreto (pestaña de hermandad o de
-- personaje según el logro)
function achModule.OpenAchievement(id)
    if not id then return end
    achModule.EnsureLoaded()
    if not AchievementFrame then return end

    local isGuild = select(12, GetAchievementInfo(id)) and true or false
    -- Función del propio juego para los enlaces de logro: abre la ventana y lo selecciona
    if OpenAchievementFrameToAchievement and pcall(OpenAchievementFrameToAchievement, id) then
        if AchievementFrame_SelectAchievement then
            C_Timer.After(0.1, function() pcall(AchievementFrame_SelectAchievement, id, true) end)
        end
        return
    end

    if not AchievementFrame:IsShown() then
        if AchievementFrame_ToggleAchievementFrame then
            pcall(AchievementFrame_ToggleAchievementFrame, false, isGuild)
        else
            ShowUIPanel(AchievementFrame)
        end
    end
    if AchievementFrame_SelectAchievement then
        -- forceSelect: lo selecciona aunque el filtro de la ventana lo oculte
        pcall(AchievementFrame_SelectAchievement, id, true)
        -- La ventana termina de montarse en el siguiente fotograma: segundo intento
        C_Timer.After(0.1, function() pcall(AchievementFrame_SelectAchievement, id, true) end)
    end
end

-- true si el personaje (o la cuenta) ya tiene el logro; para los de hermandad, si la hermandad lo tiene
function achModule.IsCompleted(id)
    if not id then return false end
    local _, _, _, completed = GetAchievementInfo(id)
    return completed and true or false
end

function achModule.IsGuildAchievement(id)
    return id and select(12, GetAchievementInfo(id)) and true or false
end

-- Refresco automático al ganar un logro
local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("ACHIEVEMENT_EARNED")
evFrame:SetScript("OnEvent", function()
    local ui = addonTable.UI
    if ui and ui.IsShown and ui.IsShown() and ui.RefreshAchievements then
        ui.RefreshAchievements()
    end
end)