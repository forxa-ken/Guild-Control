local addonName, addonTable = ...

addonTable.Achievements = {}
local achModule = addonTable.Achievements

local MAX_MEMBERS_SHOWN = 30

-- Carga la UI de logros de Blizzard si aún no está cargada
function achModule.EnsureLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn then
        if not C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI") then
            C_AddOns.LoadAddOn("Blizzard_AchievementUI")
        end
    end
end

-- Devuelve la lista de categorías de hermandad: { {id, title, parent, isChild}, ... }
function achModule.GetCategories()
    local result = {}
    local list = GetGuildCategoryList and GetGuildCategoryList() or nil

    if list then
        for _, catId in ipairs(list) do
            local title, parentID = GetCategoryInfo(catId)
            table.insert(result, {
                id = catId,
                title = title or ("Cat " .. catId),
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

-- Estadísticas de logros de hermandad
function achModule.GetStats()
    local stats = {
        totalPoints = 0,
        completedCount = 0,
        totalCount = 0,
        latestName = "Ninguno",
        latestDate = "",
    }

    if GetTotalAchievementPoints then
        stats.totalPoints = GetTotalAchievementPoints(true) or 0
    end

    if GetNumCompletedAchievements then
        local total, completed = GetNumCompletedAchievements(true)
        stats.totalCount = total or 0
        stats.completedCount = completed or 0
    end

    if GetLatestCompletedAchievements then
        local latest = { GetLatestCompletedAchievements(true) }
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
        name = name or "Desconocido",
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

-- Abre el logro en la ventana de Blizzard
function achModule.OpenAchievement(id)
    if not id then return end
    achModule.EnsureLoaded()
    if not AchievementFrame then return end

    ShowUIPanel(AchievementFrame)
    if AchievementFrame_SelectAchievement then
        pcall(AchievementFrame_SelectAchievement, id)
    end
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