local addonName, addonTable = ...

addonTable.Announcements = {}
local annModule = addonTable.Announcements

local currentSelectedAnnIndex = 1

function annModule.GetSelectedIndex()
    return currentSelectedAnnIndex
end

function annModule.SetSelectedIndex(idx)
    currentSelectedAnnIndex = idx
end

function annModule.GetAnnouncementData(idx)
    local targetIdx = idx or currentSelectedAnnIndex
    return GuildControlDB.announcements and GuildControlDB.announcements[targetIdx]
end

function annModule.UpdateAnnouncementData(idx, enabled, message, interval)
    if not GuildControlDB.announcements then return end
    local data = GuildControlDB.announcements[idx]
    if data then
        if enabled ~= nil then data.enabled = enabled end
        if message ~= nil then data.message = message end
        if interval ~= nil then data.interval = math.max(1, tonumber(interval) or 15) end
    end
end