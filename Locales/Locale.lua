local addonName, addonTable = ...

-- ============================================================================
-- LOCALIZACIÓN
-- El texto original (español) es la clave: L["Miembros"] devuelve la traducción
-- del idioma activo o, si no existe, la propia clave. Así el español no necesita
-- archivo propio y un texto sin traducir nunca rompe nada.
--
-- Para añadir un idioma: copia Locales/enUS.lua con el código del idioma
-- (frFR.lua, deDE.lua...), cambia la llamada a RegisterLocale, traduce los
-- valores de la derecha y añade el archivo a GuildControl.toc.
-- ============================================================================

local locales = {}          -- [código] = { name = "English", strings = {...} }
local order = {}            -- códigos en orden de registro
local active = nil          -- tabla de traducciones activa (nil = español)
local activeCode = "esES"

local L = setmetatable({}, {
    __index = function(_, key)
        local value = active and active[key]
        if value == nil then return key end
        return value
    end,
    __newindex = function() end,
})
addonTable.L = L

-- El español es el idioma base: no tiene tabla de traducciones
locales.esES = { name = "Español", strings = nil }
table.insert(order, "esES")

function addonTable.RegisterLocale(code, name, strings)
    if not locales[code] then table.insert(order, code) end
    locales[code] = { name = name, strings = strings }
end

-- Idioma que corresponde al cliente: español para esES/esMX, el del cliente si
-- hay traducción y, si no, inglés.
local function ClientLanguage()
    local client = GetLocale and GetLocale() or "enUS"
    if client == "esES" or client == "esMX" then return "esES" end
    if client == "enGB" then client = "enUS" end
    if locales[client] then return client end
    return "enUS"
end

-- code: "auto" o un código registrado. Los textos ya dibujados no cambian hasta /reload.
function addonTable.SetLanguage(code)
    if not code or code == "auto" or not locales[code] then code = ClientLanguage() end
    if not locales[code] then code = "esES" end
    activeCode = code
    active = locales[code].strings
end

function addonTable.GetLanguage() return activeCode end

-- { {code, name}, ... } en orden de registro
function addonTable.GetLanguages()
    local list = {}
    for _, code in ipairs(order) do
        table.insert(list, { code = code, name = locales[code].name })
    end
    return list
end

-- "Online", "Desconectado" o "N días" (como lo guarda Core) en el idioma activo
function addonTable.FormatLastOnline(value)
    if type(value) ~= "string" then return value end
    local days = string.match(value, "^(%d+) días$")
    if days then return string.format(L["%d días"], tonumber(days)) end
    return L[value]
end

-- Variables de los mensajes: los nombres en inglés se aceptan como alias de los españoles
local VAR_ALIASES = {
    name = "nombre", guild = "hermandad", date = "fecha", time = "hora",
    difficulty = "dificultad", boss = "jefe", note = "nota", role = "rol",
}
function addonTable.NormalizeVars(text)
    if type(text) ~= "string" then return text end
    return (string.gsub(text, "{(%a+)}", function(var)
        local alias = VAR_ALIASES[string.lower(var)]
        if alias then return "{" .. alias .. "}" end
    end))
end
