local addonName, addonTable = ...
local L = addonTable.L

addonTable.Favorites = {}
local favModule = addonTable.Favorites

-- Personajes favoritos (sin frames): GuildControlDB.favorites[Nombre-Reino] = true.
-- Cuando uno se conecta se avisa en el chat, en el centro de la pantalla y con un sonido.
-- Llega por dos vías (aviso del sistema y escaneo de la lista), así que se evita repetir.

local REPEAT_SECONDS = 300
local lastAlert = {}

local function Store()
    if type(GuildControlDB.favorites) ~= "table" then GuildControlDB.favorites = {} end
    return GuildControlDB.favorites
end

local function ShortName(name)
    return name and (string.match(name, "^([^-]+)") or name) or nil
end

-- Clave guardada de un favorito a partir de un nombre con o sin reino (nil si no lo es)
local function FindFavorite(name)
    if not name or name == "" then return nil end
    local store = Store()
    if store[name] then return name end
    local short = ShortName(name)
    for fullName in pairs(store) do
        if ShortName(fullName) == short then return fullName end
    end
    return nil
end

function favModule.IsFavorite(name)
    return FindFavorite(name) ~= nil
end

function favModule.Toggle(fullName)
    if not fullName then return end
    local store = Store()
    if store[fullName] then store[fullName] = nil else store[fullName] = true end
    return store[fullName] == true
end

function favModule.GetAll()
    local list = {}
    for fullName in pairs(Store()) do table.insert(list, fullName) end
    table.sort(list)
    return list
end

-- Lo llaman el chat (aviso "se ha conectado") y Core (paso a conectado en la lista)
function favModule.OnOnline(name)
    if not GuildControlDB then return end
    local fullName = FindFavorite(name)
    if not fullName then return end
    local short = ShortName(fullName)
    if lastAlert[short] and GetTime() - lastAlert[short] < REPEAT_SECONDS then return end
    lastAlert[short] = GetTime()

    local m = GuildControlDB.members and GuildControlDB.members[fullName]
    local hex = addonTable.GetClassColorHex and addonTable.GetClassColorHex(m and m.class) or "FFFFFF"
    local text = L["Tu favorito "] .. "|cFF" .. hex .. short .. "|r" .. L[" se ha conectado."]
    print("|cFF00FFFF[GuildControl]|r |A:PetJournal-FavoritesIcon:14:14|a " .. text)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, 1, 0.82, 0) end
    if PlaySound and SOUNDKIT then
        pcall(PlaySound, SOUNDKIT.UI_BNET_TOAST or SOUNDKIT.TELL_MESSAGE)
    end
end
