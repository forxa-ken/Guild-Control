local addonName, addonTable = ...

addonTable.Professions = {}
local profModule = addonTable.Professions

local profFrame = CreateFrame("Frame")
profFrame:RegisterEvent("TRADE_SKILL_SHOW")
profFrame:RegisterEvent("CHAT_MSG_ADDON")

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix("GuildControlProf")
    C_ChatInfo.RegisterAddonMessagePrefix("GuildControlReq")
end

function profModule.GetProfessionsFromClub(guid)
    if not guid or not C_Club or not C_Club.GetGuildClubId then return nil, nil end
    local clubId = C_Club.GetGuildClubId()
    if not clubId then return nil, nil end
    
    local memberInfo = C_Club.GetMemberInfoForGUID and C_Club.GetMemberInfoForGUID(clubId, guid)
    if memberInfo then
        local p1, r1 = memberInfo.profession1Name, memberInfo.profession1Rank
        local p2, r2 = memberInfo.profession2Name, memberInfo.profession2Rank
        
        local str1, str2 = nil, nil
        if p1 and p1 ~= "" then str1 = (r1 and r1 > 0) and (p1 .. " " .. r1) or p1 end
        if p2 and p2 ~= "" then str2 = (r2 and r2 > 0) and (p2 .. " " .. r2) or p2 end
        return str1, str2
    end
    return nil, nil
end

function profModule.BroadcastMyProfessions()
    if not IsInGuild() then return end
    local prof1, prof2 = GetProfessions()
    local p1Name, p2Name = "Ninguna", "Ninguna"
    
    if prof1 then
        local name1 = GetProfessionInfo(prof1)
        if name1 and name1 ~= "" then p1Name = name1 end
    end
    if prof2 then
        local name2 = GetProfessionInfo(prof2)
        if name2 and name2 ~= "" then p2Name = name2 end
    end

    local message = p1Name .. "," .. p2Name
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage("GuildControlProf", message, "GUILD")
    end
end

function profModule.RequestGuildProfessions()
    if IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage("GuildControlReq", "REQ", "GUILD")
    end
end

function profModule.ScanMyProfessions()
    if not IsInGuild() then return end
    local playerName = UnitName("player") .. "-" .. GetRealmName()
    playerName = string.gsub(playerName, "%s+", "")

    local prof1, prof2 = GetProfessions()
    local p1Name, p2Name = "Ninguna", "Ninguna"
    
    if prof1 then
        local name1 = GetProfessionInfo(prof1)
        if name1 and name1 ~= "" then p1Name = name1 end
    end
    if prof2 then
        local name2 = GetProfessionInfo(prof2)
        if name2 and name2 ~= "" then p2Name = name2 end
    end

    if GuildControlDB.members[playerName] then
        if p1Name ~= "Ninguna" then GuildControlDB.members[playerName].prof1 = p1Name end
        if p2Name ~= "Ninguna" then GuildControlDB.members[playerName].prof2 = p2Name end
    end

    profModule.BroadcastMyProfessions()
end

function profModule.Scan()
    if not IsInGuild() then return end
    
    if QueryGuildTradeSkill then
        QueryGuildTradeSkill()
    end

    if GetNumGuildTradeSkills and GetGuildTradeSkillInfo then
        local numSkills = GetNumGuildTradeSkills()
        if numSkills > 0 then
            local currentProf = ""
            for i = 1, numSkills do
                local skillName, _, isHeader, _, _, _, name, rank = GetGuildTradeSkillInfo(i)
                if isHeader then
                    currentProf = skillName or ""
                elseif name and name ~= "" and currentProf ~= "" then
                    local playerName = name
                    if not string.find(playerName, "-") then
                        playerName = playerName .. "-" .. GetRealmName()
                    end
                    playerName = string.gsub(playerName, "%s+", "")

                    if GuildControlDB.members[playerName] then
                        local displayProf = currentProf
                        if rank and tonumber(rank) and tonumber(rank) > 0 then
                            displayProf = currentProf .. " " .. rank
                        end
                        local m = GuildControlDB.members[playerName]
                        if m.prof1 == "Ninguna" or not m.prof1 then
                            m.prof1 = displayProf
                        elseif (m.prof2 == "Ninguna" or not m.prof2) and m.prof1 ~= displayProf then
                            m.prof2 = displayProf
                        end
                    end
                end
            end
        end
    end

    for fullName, m in pairs(GuildControlDB.members) do
        if m.guid then
            local clubP1, clubP2 = profModule.GetProfessionsFromClub(m.guid)
            if clubP1 then m.prof1 = clubP1 end
            if clubP2 then m.prof2 = clubP2 end
        end
    end
end

profFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
    if event == "TRADE_SKILL_SHOW" then
        profModule.ScanMyProfessions()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = arg1, arg2, arg3, arg4
        if channel == "GUILD" then
            if prefix == "GuildControlReq" then
                profModule.BroadcastMyProfessions()
            elseif prefix == "GuildControlProf" and sender and msg then
                local fullSender = sender
                if not string.find(fullSender, "-") then
                    fullSender = sender .. "-" .. GetRealmName()
                end
                fullSender = string.gsub(fullSender, "%s+", "")

                local p1, p2 = strsplit(",", msg)
                if GuildControlDB.members[fullSender] then
                    if p1 and p1 ~= "" then GuildControlDB.members[fullSender].prof1 = p1 end
                    if p2 and p2 ~= "" then GuildControlDB.members[fullSender].prof2 = p2 end
                    if addonTable.UI.RefreshList and addonTable.UI.IsShown and addonTable.UI.IsShown() then
                        addonTable.UI.RefreshList()
                    end
                end
            end
        end
    end
end)