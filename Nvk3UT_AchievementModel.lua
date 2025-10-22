Nvk3UT = Nvk3UT or {}
local M = Nvk3UT

M.AchievementModel = M.AchievementModel or {}
local Module = M.AchievementModel

local EM = EVENT_MANAGER

local REFRESH_HANDLE = "Nvk3UT_AchievementModelRefresh"
local DEFAULT_REFRESH_DELAY_MS = 150

Module.Ach = Module.Ach or { list = {}, meta = { total = 0, completed = 0 } }

local function debugLog(message)
    local utils = M and M.Utils
    if utils and utils.d and M and M.sv and M.sv.debug then
        utils.d("[AchievementModel]", message)
    elseif d then
        d(string.format("[Nvk3UT] AchievementModel: %s", tostring(message)))
    end
end

local function sanitizeText(text)
    if text == nil or text == "" then
        return ""
    end
    local utils = M and M.Utils
    if utils and utils.StripLeadingIconTag then
        text = utils.StripLeadingIconTag(text)
    end
    if zo_strformat then
        local ok, formatted = pcall(zo_strformat, "<<1>>", text)
        if ok and formatted and formatted ~= "" then
            return formatted
        end
    end
    return text
end

local function resolveTexture(path)
    if path == nil or path == "" then
        return ""
    end
    local utils = M and M.Utils
    if utils and utils.ResolveTexturePath then
        local resolved = utils.ResolveTexturePath(path)
        if resolved and resolved ~= "" then
            return resolved
        end
    end
    return path
end

local function getFavoriteScope()
    local sv = M and M.sv
    if not sv then
        return "account"
    end
    local ui = sv.ui
    if not ui then
        return "account"
    end
    return ui.favScope or "account"
end

local function getAchievementLineStart(achievementId)
    if type(GetPreviousAchievementInLine) ~= "function" then
        return achievementId
    end
    local visited = {}
    local current = achievementId
    while type(current) == "number" and current ~= 0 and not visited[current] do
        visited[current] = true
        local okPrev, prevId = pcall(GetPreviousAchievementInLine, current)
        if not okPrev or not prevId or prevId == 0 or visited[prevId] then
            break
        end
        current = prevId
    end
    return current
end

local function getAchievementLineIds(achievementId)
    local ids = {}
    if type(achievementId) ~= "number" or achievementId == 0 then
        return ids
    end
    local startId = getAchievementLineStart(achievementId)
    local visited = {}
    local current = startId
    while type(current) == "number" and current ~= 0 and not visited[current] do
        ids[#ids + 1] = current
        visited[current] = true
        if type(GetNextAchievementInLine) ~= "function" then
            break
        end
        local okNext, nextId = pcall(GetNextAchievementInLine, current)
        if not okNext or not nextId or nextId == 0 or visited[nextId] then
            break
        end
        current = nextId
    end
    return ids
end

local function isAchievementLineCompleted(achievementId)
    local ids = getAchievementLineIds(achievementId)
    local finalId = ids[#ids] or achievementId
    if type(IsAchievementComplete) == "function" then
        local ok, complete = pcall(IsAchievementComplete, finalId)
        if ok then
            return complete == true, finalId, ids
        end
    end
    if type(GetAchievementInfo) == "function" then
        local ok, _, _, _, _, completed = pcall(GetAchievementInfo, finalId)
        if ok then
            return completed == true, finalId, ids
        end
    end
    return false, finalId, ids
end

local function removeFavoriteChain(ids, scope)
    if not ids or #ids == 0 then
        return
    end
    local Fav = M and M.FavoritesData
    if not (Fav and Fav.IsFavorite and Fav.Remove) then
        return
    end
    for _, id in ipairs(ids) do
        if Fav.IsFavorite(id, scope) then
            Fav.Remove(id, scope)
        end
    end
end

local function pruneCompletedFavorites()
    local Fav = M and M.FavoritesData
    if not (Fav and Fav.Iterate and Fav.Remove) then
        return
    end
    local scope = getFavoriteScope()
    local removals = {}
    for achievementId, flagged in Fav.Iterate(scope) do
        if flagged then
            local completed, _, chainIds = isAchievementLineCompleted(achievementId)
            if completed then
                chainIds = (chainIds and #chainIds > 0) and chainIds or { achievementId }
                for _, id in ipairs(chainIds) do
                    removals[#removals + 1] = id
                end
            end
        end
    end
    if #removals == 0 then
        return
    end
    removeFavoriteChain(removals, scope)
end

local function gatherFavorites()
    local results = {}
    local Fav = M and M.FavoritesData
    if not (Fav and Fav.Iterate) then
        return results
    end

    local scope = getFavoriteScope()
    local seen = {}
    local removals = {}

    local playerGender
    local okGender, gender = pcall(GetUnitGender, "player")
    if okGender then
        playerGender = gender
    end

    for achievementId, flagged in Fav.Iterate(scope) do
        if flagged and type(achievementId) == "number" and achievementId ~= 0 and not seen[achievementId] then
            local completed, finalId, chainIds = isAchievementLineCompleted(achievementId)
            if completed then
                chainIds = (chainIds and #chainIds > 0) and chainIds or { achievementId }
                for _, id in ipairs(chainIds) do
                    removals[#removals + 1] = id
                    seen[id] = true
                end
                if finalId then
                    removals[#removals + 1] = finalId
                    seen[finalId] = true
                end
            else
                local ids = (chainIds and #chainIds > 0) and chainIds or { achievementId }
                for _, id in ipairs(ids) do
                    seen[id] = true
                end

                local displayName
                local description
                local iconPath
                local totalCurrent = 0
                local totalRequired = 0
                local objectives = {}
                local stageDetails = {}

                for _, id in ipairs(ids) do
                    local okInfo, stageName, stageDescription, _, stageIcon = pcall(GetAchievementInfo, id)
                    if okInfo then
                        local sanitizedName = sanitizeText(stageName)
                        local stageEntryDescription = sanitizeText(stageDescription)
                        if playerGender and sanitizedName ~= "" and zo_strformat then
                            local okFormat, formatted = pcall(zo_strformat, sanitizedName, playerGender)
                            if okFormat and formatted and formatted ~= "" then
                                sanitizedName = formatted
                            end
                        end

                        if (not displayName or displayName == "") and sanitizedName ~= "" then
                            displayName = sanitizedName
                        elseif sanitizedName ~= "" then
                            displayName = sanitizedName
                        end

                        if stageEntryDescription ~= "" then
                            description = stageEntryDescription
                        end

                        if stageIcon and stageIcon ~= "" then
                            iconPath = stageIcon
                        end

                        stageDetails[#stageDetails + 1] = {
                            id = id,
                            name = sanitizedName,
                            description = stageEntryDescription,
                        }
                    end

                    local numCriteria = GetAchievementNumCriteria and GetAchievementNumCriteria(id) or 0
                    for criterionIndex = 1, numCriteria do
                        local okCrit, criterionDescription, numCompleted, numRequired =
                            pcall(GetAchievementCriterion, id, criterionIndex)
                        if okCrit then
                            local sanitized = sanitizeText(criterionDescription)
                            local currentValue = tonumber(numCompleted) or 0
                            local requiredValue = tonumber(numRequired) or 0
                            if requiredValue == 0 then
                                requiredValue = currentValue
                            end
                            totalCurrent = totalCurrent + currentValue
                            totalRequired = totalRequired + requiredValue
                            if sanitized ~= "" and currentValue < requiredValue then
                                local objectiveIndex = #objectives + 1
                                objectives[objectiveIndex] = {
                                    text = sanitized,
                                    current = currentValue,
                                    max = requiredValue,
                                    index = objectiveIndex,
                                }
                            end
                        end
                    end
                end

                local normalizedIcon = resolveTexture(iconPath)
                local cleanedName = sanitizeText(displayName or "")
                if cleanedName == "" then
                    cleanedName = string.format("%d", achievementId)
                end

                local lowerName
                if cleanedName ~= "" then
                    if type(zo_strlower) == "function" then
                        lowerName = zo_strlower(cleanedName)
                    else
                        lowerName = string.lower(cleanedName)
                    end
                else
                    lowerName = string.format("%d", achievementId)
                end

                local pct = 0
                if totalRequired > 0 then
                    pct = (totalCurrent / totalRequired) * 100
                elseif totalCurrent > 0 then
                    pct = 100
                end
                if type(zo_round) == "function" then
                    pct = zo_round(pct)
                else
                    pct = math.floor(pct + 0.5)
                end

                results[#results + 1] = {
                    id = achievementId,
                    favoriteId = achievementId,
                    displayId = finalId or achievementId,
                    name = cleanedName,
                    description = description or "",
                    icon = (normalizedIcon ~= "" and normalizedIcon) or "EsoUI/Art/Journal/journal_tabIcon_achievements_up.dds",
                    objectives = objectives,
                    completed = false,
                    sortKey = lowerName,
                    progressCurrent = totalCurrent,
                    progressMax = totalRequired,
                    chainIds = ids,
                    stages = stageDetails,
                    progress = { cur = totalCurrent, max = totalRequired, pct = pct },
                }
            end
        end
    end

    if #removals > 0 then
        removeFavoriteChain(removals, scope)
    end

    table.sort(results, function(a, b)
        local aKey = (a.sortKey ~= "" and a.sortKey) or a.name or ""
        local bKey = (b.sortKey ~= "" and b.sortKey) or b.name or ""
        return aKey < bKey
    end)

    for _, entry in ipairs(results) do
        entry.sortKey = nil
    end

    return results
end

function Module.Scan()
    pruneCompletedFavorites()

    Module.Ach.list = gatherFavorites()
    Module.Ach.meta = Module.Ach.meta or {}
    Module.Ach.meta.total = #Module.Ach.list
    Module.Ach.meta.completed = 0

    return Module.Ach
end

function Module.GetList()
    if not Module.Ach or not Module.Ach.list then
        Module.Scan()
    end
    return Module.Ach.list or {}, (Module.Ach and Module.Ach.meta) or { total = 0, completed = 0 }
end

function Module.ForceRefresh()
    if EM and EM.UnregisterForUpdate then
        EM:UnregisterForUpdate(REFRESH_HANDLE)
    end
    Module.refreshPending = false
    Module.dirty = false
    Module.Scan()
    if M.Publish then
        M.Publish("ach:changed", Module.Ach)
    elseif M.Core and M.Core.Publish then
        M.Core.Publish("ach:changed", Module.Ach)
    end
end

function Module.ThrottledRefresh()
    if Module.refreshPending then
        return
    end
    Module.refreshPending = true
    local delay = DEFAULT_REFRESH_DELAY_MS
    local trackerSV = M and M.sv and M.sv.tracker
    if trackerSV and trackerSV.throttleMs then
        delay = tonumber(trackerSV.throttleMs) or delay
    end

    local function callback()
        Module.refreshPending = false
        if Module.dirty then
            Module.ForceRefresh()
        end
    end

    if EM and EM.RegisterForUpdate then
        EM:RegisterForUpdate(REFRESH_HANDLE, delay, function()
            if EM.UnregisterForUpdate then
                EM:UnregisterForUpdate(REFRESH_HANDLE)
            end
            callback()
        end)
    else
        zo_callLater(callback, delay)
    end
end

local function handleAchievementUpdate()
    Module.dirty = true
    Module.ThrottledRefresh()
end

function Module.Init()
    debugLog("Init() invoked")
    Module.dirty = true
    if not EM then
        Module.ForceRefresh()
        return
    end

    EM:UnregisterForEvent("Nvk3UT_AchievementModel_Activated", EVENT_PLAYER_ACTIVATED)
    EM:RegisterForEvent("Nvk3UT_AchievementModel_Activated", EVENT_PLAYER_ACTIVATED, function()
        handleAchievementUpdate()
    end)

    EM:UnregisterForEvent("Nvk3UT_AchievementModel_Awarded", EVENT_ACHIEVEMENT_AWARDED)
    EM:RegisterForEvent("Nvk3UT_AchievementModel_Awarded", EVENT_ACHIEVEMENT_AWARDED, function(_, _, _, achievementId)
        handleAchievementUpdate()
        if achievementId then
            local completed, _, chainIds = isAchievementLineCompleted(achievementId)
            if completed then
                local scope = getFavoriteScope()
                chainIds = (chainIds and #chainIds > 0) and chainIds or { achievementId }
                removeFavoriteChain(chainIds, scope)
            end
        end
    end)

    EM:UnregisterForEvent("Nvk3UT_AchievementModel_Updated", EVENT_ACHIEVEMENT_UPDATED)
    EM:RegisterForEvent("Nvk3UT_AchievementModel_Updated", EVENT_ACHIEVEMENT_UPDATED, function(_, achievementId)
        handleAchievementUpdate()
        if achievementId then
            local completed, _, chainIds = isAchievementLineCompleted(achievementId)
            if completed then
                local scope = getFavoriteScope()
                chainIds = (chainIds and #chainIds > 0) and chainIds or { achievementId }
                removeFavoriteChain(chainIds, scope)
            end
        end
    end)

    Module.ForceRefresh()
end

return
