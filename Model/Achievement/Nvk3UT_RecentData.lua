Nvk3UT = Nvk3UT or {}

local Utils = Nvk3UT and Nvk3UT.Utils

local RecentData = {}
Nvk3UT.RecentData = RecentData

local DEFAULT_RECENT_LIMIT = 100

local function ensureSavedVars()
    local root = Nvk3UT
    local saved = root and (root.SV or root.sv)
    local ac = saved and saved.ac
    local recent = ac and ac.recent
    if not recent then
        return nil
    end

    if type(recent.list) ~= "table" then
        recent.list = {}
    end
    if type(recent.progress) ~= "table" then
        recent.progress = {}
    end

    if tonumber(recent.limit) ~= 50 and tonumber(recent.limit) ~= 100 and tonumber(recent.limit) ~= 250 then
        recent.limit = DEFAULT_RECENT_LIMIT
    end

    return recent
end

local function now()
    if Utils and Utils.now then
        local ok, value = pcall(Utils.now)
        if ok and value ~= nil then
            return value
        end
    end

    if GetTimeStamp then
        return GetTimeStamp()
    end

    return nil
end

local function isDebugEnabled()
    return Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug and Utils and Utils.d
end

local function emitDebugMessage(...)
    if not isDebugEnabled() then
        return
    end

    if Utils and Utils.d then
        Utils.d("[Nvk3UT][Recent]", ...)
    elseif d then
        d("[Nvk3UT][Recent]", ...)
    end
end

local function collectCandidateKeys(id)
    local keys = {}
    local seen = {}

    local function push(value)
        if value == nil or seen[value] then
            return
        end
        seen[value] = true
        keys[#keys + 1] = value
    end

    push(id)

    if type(id) == "number" then
        push(tostring(id))
    elseif type(id) == "string" then
        local numeric = tonumber(id)
        if numeric then
            push(numeric)
        end
    end

    if Utils and Utils.NormalizeAchievementId then
        local ok, normalized = pcall(Utils.NormalizeAchievementId, id)
        if ok and normalized ~= nil then
            push(normalized)
            if type(normalized) == "number" then
                push(tostring(normalized))
            elseif type(normalized) == "string" then
                local numeric = tonumber(normalized)
                if numeric then
                    push(numeric)
                end
            end
        end
    end

    return keys
end

local function normalizeIdForStorage(id)
    if id == nil then
        return nil
    end

    if Utils and Utils.NormalizeAchievementId then
        local ok, normalized = pcall(Utils.NormalizeAchievementId, id)
        if ok and normalized ~= nil then
            id = normalized
        end
    end

    if type(id) == "number" then
        return id
    end

    local numeric = tonumber(id)
    if numeric then
        return numeric
    end

    return id
end

function RecentData.InitSavedVars()
    return ensureSavedVars()
end

local function IsOpen(id)
    if not id then
        return false
    end

    if Utils and Utils.IsMultiStageAchievement then
        local okMulti, isMulti = pcall(Utils.IsMultiStageAchievement, id)
        if okMulti and isMulti and Utils.IsAchievementFullyComplete then
            local okComplete, fullyComplete = pcall(Utils.IsAchievementFullyComplete, id)
            if okComplete then
                return fullyComplete == false
            end
        end
    end

    if type(GetAchievementInfo) ~= "function" then
        return false
    end

    local infoOk, _, _, _, completedOrErr = pcall(GetAchievementInfo, id)
    if not infoOk then
        if isDebugEnabled() then
            emitDebugMessage("IsOpen failed", "id:", tostring(id), "error:", tostring(completedOrErr))
        end
        return false
    end

    return completedOrErr == false
end

function RecentData.Touch(id, timestamp)
    if not id then
        return
    end

    local recent = ensureSavedVars()
    if not recent then
        return
    end
    local storeId = normalizeIdForStorage(id)
    if not storeId then
        return
    end

    recent.progress[storeId] = timestamp or now() or GetTimeStamp()
end

function RecentData.Clear(id)
    if not id then
        return
    end

    local recent = ensureSavedVars()
    if not recent then
        return
    end
    local storeId = normalizeIdForStorage(id)
    if not storeId then
        return
    end

    recent.progress[storeId] = nil
end

function RecentData.GetTimestamp(id)
    if not id then
        return nil
    end

    local recent = ensureSavedVars()
    if not recent then
        return nil
    end
    local progress = recent.progress
    local keys = collectCandidateKeys(id)

    for index = 1, #keys do
        local key = keys[index]
        if key ~= nil and progress[key] ~= nil then
            return progress[key]
        end
    end

    return nil
end

function RecentData.Contains(id)
    local ts = RecentData.GetTimestamp(id)
    return ts ~= nil
end

function RecentData.IterateProgress()
    local recent = ensureSavedVars()
    if not recent then
        return function() end, nil, nil
    end
    return next, recent.progress, nil
end

-- Build a sorted list of IDs by timestamp (desc); optional sinceTs and maxCount
function RecentData.List(maxCount, sinceTs)
    local recent = ensureSavedVars()
    if not recent then
        return {}
    end
    local t = {}

    for id, ts in pairs(recent.progress) do
        if (not sinceTs) or (type(ts) == "number" and ts >= sinceTs) then
            t[#t + 1] = { id = id, ts = ts or 0 }
        end
    end

    table.sort(t, function(a, b)
        return a.ts > b.ts
    end)

    local res = {}
    local limit = tonumber(maxCount) or 0
    local removed = 0

    for i = 1, #t do
        local entryId = t[i].id
        local open = IsOpen(entryId)
        if open then
            if limit == 0 or #res < limit then
                local storeValue = entryId
                if type(storeValue) == "string" then
                    local numeric = tonumber(storeValue)
                    if numeric then
                        storeValue = numeric
                    end
                end
                res[#res + 1] = storeValue
            end
        elseif entryId then
            RecentData.Clear(entryId)
            removed = removed + 1
        end
    end

    if removed > 0 then
        emitDebugMessage("List filtered", "removed:", removed)
    end

    local limitCount = tonumber(recent.limit) or DEFAULT_RECENT_LIMIT
    local capped = {}
    local cap = math.min(#res, limitCount)
    for index = 1, cap do
        capped[index] = res[index]
    end
    recent.list = capped

    return res
end

local function getConfigWindow()
    local sv = Nvk3UT and Nvk3UT.sv
    local ui = sv and sv.ui or {}
    local ac = sv and sv.ac or {}
    local recent = ac.recent or {}
    local win = ui.recentWindow or 0
    local maxc = recent.limit or DEFAULT_RECENT_LIMIT
    local sinceTs = nil

    if win == 7 then
        sinceTs = (GetTimeStamp() - 7 * 24 * 60 * 60)
    elseif win == 30 then
        sinceTs = (GetTimeStamp() - 30 * 24 * 60 * 60)
    end

    return maxc, sinceTs
end

function RecentData.ListConfigured()
    RecentData.InitSavedVars()
    local maxc, sinceTs = getConfigWindow()
    return RecentData.List(maxc, sinceTs)
end

function RecentData.CountConfigured()
    RecentData.InitSavedVars()
    local maxc, sinceTs = getConfigWindow()
    local list = RecentData.List(maxc, sinceTs)
    return (list and #list) or 0
end

-- Seed the account-wide recent list with up to 50 entries (only if empty)
function RecentData.BuildInitial()
    local recent = ensureSavedVars()
    if not recent then
        return 0
    end

    if next(recent.progress) ~= nil then
        return 0
    end

    local INIT_CAP = 50
    local stamp = now() or GetTimeStamp()

    local function hasPartialProgress(id)
        if not id or not IsOpen(id) then
            return false
        end

        local inspectIds = { id }
        if Utils and Utils.NormalizeAchievementId then
            local normalized = Utils.NormalizeAchievementId(id)
            if normalized and normalized ~= id then
                inspectIds[#inspectIds + 1] = normalized
            end
        end

        local getState = Utils and Utils.GetAchievementCriteriaState
        if type(getState) == "function" then
            for _, inspectId in ipairs(inspectIds) do
                local state = getState(inspectId)
                if state and type(state.total) == "number" and state.total > 0 then
                    local total = state.total
                    local completed = tonumber(state.completed) or 0
                    if completed > 0 and completed < total then
                        return true
                    end
                end
            end
        end

        if type(GetAchievementProgress) == "function" then
            local ok, completed, total = pcall(GetAchievementProgress, id)
            if ok and type(total) == "number" and total > 0 and type(completed) == "number" then
                if completed > 0 and completed < total then
                    return true
                end
            end
        end

        return false
    end

    local function getRandom(minValue, maxValue)
        if type(zo_random) == "function" then
            return zo_random(minValue, maxValue)
        end
        if type(math.random) == "function" then
            if maxValue then
                return math.random(minValue, maxValue)
            end
            return math.random(minValue)
        end
        return minValue
    end

    local function shuffle(list)
        for i = #list, 2, -1 do
            local swapIndex = getRandom(1, i)
            list[i], list[swapIndex] = list[swapIndex], list[i]
        end
    end

    local candidates = {}
    local seen = {}

    local function collect(id)
        if not id then
            return
        end

        local okPartial, hasProgress = pcall(hasPartialProgress, id)
        if not okPartial then
            if isDebugEnabled() then
                emitDebugMessage("Seed partial check failed", "id:", tostring(id), "error:", tostring(hasProgress))
            end
            return
        end
        if not hasProgress then
            return
        end

        local storeId = id
        if Utils and Utils.NormalizeAchievementId then
            storeId = Utils.NormalizeAchievementId(id) or id
        end

        if not storeId or seen[storeId] then
            return
        end

        seen[storeId] = true
        candidates[#candidates + 1] = storeId
    end

    local numCats = GetNumAchievementCategories and GetNumAchievementCategories() or 0
    for top = 1, numCats do
        local _, numSub, numAch = GetAchievementCategoryInfo(top)
        for a = 1, (numAch or 0) do
            collect(GetAchievementId(top, nil, a))
        end
        for sub = 1, (numSub or 0) do
            local _, numAch2 = GetAchievementSubCategoryInfo(top, sub)
            for a = 1, (numAch2 or 0) do
                collect(GetAchievementId(top, sub, a))
            end
        end
    end

    if #candidates == 0 then
        return 0
    end

    shuffle(candidates)

    local added = 0
    for index = 1, math.min(INIT_CAP, #candidates) do
        local storeId = candidates[index]
        if storeId then
            if recent.progress[storeId] == nil then
                added = added + 1
            end
            recent.progress[storeId] = stamp
        end
    end

    return added
end

-- Event wiring: keep list fresh passively
function RecentData.RegisterEvents()
    local em = EVENT_MANAGER
    if not em then
        return
    end

    em:UnregisterForEvent("Nvk3UT_RecentData", EVENT_ACHIEVEMENT_UPDATED)
    em:UnregisterForEvent("Nvk3UT_RecentData", EVENT_ACHIEVEMENT_AWARDED)

    em:RegisterForEvent("Nvk3UT_RecentData", EVENT_ACHIEVEMENT_UPDATED, function(_, achievementId)
        if IsOpen(achievementId) then
            RecentData.Touch(achievementId)
        else
            RecentData.Clear(achievementId)
        end
    end)

    em:RegisterForEvent("Nvk3UT_RecentData", EVENT_ACHIEVEMENT_AWARDED, function(_, _, _, achievementId)
        if IsOpen(achievementId) then
            RecentData.Touch(achievementId)
        else
            RecentData.Clear(achievementId)
        end
    end)
end

return RecentData
