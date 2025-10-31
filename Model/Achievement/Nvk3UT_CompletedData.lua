Nvk3UT = Nvk3UT or {}

local CompletedData = {}
Nvk3UT.CompletedData = CompletedData

local MONTH_NAMES = {
    [1] = "Januar", [2] = "Februar", [3] = "März", [4] = "April",
    [5] = "Mai", [6] = "Juni", [7] = "Juli", [8] = "August",
    [9] = "September", [10] = "Oktober", [11] = "November", [12] = "Dezember",
}

local LAST50_KEY = 90000

local built = false
local last50 = {}
local monthKeys = {}
local keyToName = {}
local keyToList = {}

local tableUnpack = table.unpack or unpack

local function push(list, value)
    list[#list + 1] = value
end

local function asUnix(ts)
    local n = tonumber(ts)
    if n and n > 0 then
        return math.floor(n)
    end
    return nil
end

local function isDebugEnabled()
    local root = Nvk3UT and Nvk3UT.sv
    return root and root.debug == true
end

local function emitDebugMessage(fmt, ...)
    if not isDebugEnabled() then
        return
    end

    local message
    local ok, formatted = pcall(string.format, fmt, ...)
    if ok then
        message = formatted
    else
        message = tostring(fmt)
    end

    local Utils = Nvk3UT and Nvk3UT.Utils
    if Utils and Utils.d then
        Utils.d("[Nvk3UT][CompletedData] %s", message)
    elseif d then
        d(string.format("[Nvk3UT][CompletedData] %s", message))
    end
end

local function normalizeId(value)
    if type(value) == "number" then
        return value
    end

    if type(value) == "string" then
        local numeric = tonumber(value)
        if numeric then
            return numeric
        end
    end

    return nil
end

local function safeCall(func, ...)
    if type(func) ~= "function" then
        return nil
    end

    local ok, result = pcall(func, ...)
    if ok then
        return result
    end

    return nil
end

local function safeCallMulti(func, ...)
    if type(func) ~= "function" then
        return nil
    end

    local results = { pcall(func, ...) }
    if not results[1] then
        return nil
    end

    table.remove(results, 1)
    return tableUnpack(results)
end

local function collectCompletionMeta(achievementId)
    if not achievementId then
        return false, nil, nil
    end

    local infoPoints
    local infoComplete
    local infoTimestamp

    if type(GetAchievementInfo) == "function" then
        local ok, _, _, points, _, completed, _, timestamp = pcall(GetAchievementInfo, achievementId)
        if ok then
            infoPoints = points
            infoComplete = completed
            infoTimestamp = timestamp
        end
    end

    local isComplete
    if infoComplete ~= nil then
        isComplete = infoComplete == true
    elseif type(IsAchievementComplete) == "function" then
        local ok, completed = pcall(IsAchievementComplete, achievementId)
        if ok then
            isComplete = completed == true
        end
    end

    local timestamp = infoTimestamp
    if (timestamp == nil or timestamp == 0) and type(GetAchievementTimestamp) == "function" then
        local ok, value = pcall(GetAchievementTimestamp, achievementId)
        if ok and value ~= nil then
            timestamp = value
        end
    end

    timestamp = asUnix(timestamp) or 0

    local points
    if type(infoPoints) == "number" then
        points = infoPoints
    else
        points = tonumber(infoPoints)
    end

    return isComplete == true, timestamp, points
end

local function addIdToMonth(achievementId, timestamp)
    local t = asUnix(timestamp)
    if not (achievementId and t) then
        return
    end

    local dateTable = os.date("*t", t)
    if not dateTable then
        return
    end

    local key = dateTable.year * 100 + dateTable.month
    keyToList[key] = keyToList[key] or {}
    push(keyToList[key], achievementId)

    if not keyToName[key] then
        local monthName = MONTH_NAMES[dateTable.month] or tostring(dateTable.month)
        keyToName[key] = string.format("%s %d", monthName, dateTable.year)
        push(monthKeys, key)
    end
end

local function fetchCompletionForScan(achievementId)
    if not achievementId then
        return false, nil
    end

    local infoCompleted
    local infoTimestamp
    if type(GetAchievementInfo) == "function" then
        local ok, _, _, _, _, completed, _, timeStamp = pcall(GetAchievementInfo, achievementId)
        if ok then
            infoCompleted = completed
            infoTimestamp = timeStamp
        end
    end

    local isComplete
    if type(IsAchievementComplete) == "function" then
        local ok, result = pcall(IsAchievementComplete, achievementId)
        if ok and result ~= nil then
            isComplete = result == true
        end
    end

    if isComplete == nil and infoCompleted ~= nil then
        isComplete = infoCompleted == true
    end

    local timestamp = infoTimestamp
    if (timestamp == nil or timestamp == 0) and type(GetAchievementTimestamp) == "function" then
        local ok, value = pcall(GetAchievementTimestamp, achievementId)
        if ok and value ~= nil then
            timestamp = value
        end
    end

    timestamp = asUnix(timestamp) or 0

    return isComplete == true, timestamp
end

local function processAchievements(ids)
    if type(ids) ~= "table" then
        return
    end

    for index = 1, #ids do
        local normalized = normalizeId(ids[index])
        if normalized then
            local completed, timestamp = fetchCompletionForScan(normalized)
            if completed and timestamp and timestamp ~= 0 then
                push(last50, normalized)
                addIdToMonth(normalized, timestamp)
            end
        end
    end
end

local function collectAchievementIds(categoryIndex, subCategoryIndex, total)
    if type(ZO_GetAchievementIds) ~= "function" then
        return
    end

    local ok, ids = pcall(ZO_GetAchievementIds, categoryIndex, subCategoryIndex, total, false)
    if ok then
        processAchievements(ids)
    end
end

local function scanAllAchievements()
    emitDebugMessage("Scanning achievements for completion data")

    last50 = {}
    monthKeys = {}
    keyToName = {}
    keyToList = {}

    local numTop = safeCall(GetNumAchievementCategories) or 0
    for categoryIndex = 1, numTop do
        local _, numSubCategories, numAchievements = safeCallMulti(GetAchievementCategoryInfo, categoryIndex)
        if numAchievements and numAchievements > 0 then
            collectAchievementIds(categoryIndex, nil, numAchievements)
        end

        numSubCategories = numSubCategories or 0
        for subCategoryIndex = 1, numSubCategories do
            local _, subNumAchievements = safeCallMulti(GetAchievementSubCategoryInfo, categoryIndex, subCategoryIndex)
            if subNumAchievements and subNumAchievements > 0 then
                collectAchievementIds(categoryIndex, subCategoryIndex, subNumAchievements)
            end
        end
    end

    table.sort(last50, function(a, b)
        local ta = safeCall(GetAchievementTimestamp, a) or 0
        local tb = safeCall(GetAchievementTimestamp, b) or 0
        return ta > tb
    end)

    if #last50 > 50 then
        local trimmed = {}
        for index = 1, 50 do
            trimmed[index] = last50[index]
        end
        last50 = trimmed
    end

    table.sort(monthKeys, function(left, right)
        return left > right
    end)

    emitDebugMessage("Completed scan (months=%d, last50=%d)", #monthKeys, #last50)
end

local function ensureBuilt()
    if built then
        return
    end

    scanAllAchievements()
    built = true
end

function CompletedData.Rebuild()
    emitDebugMessage("Rebuild requested")
    built = false
end

function CompletedData.GetSubcategoryList()
    ensureBuilt()

    local names = {}
    local ids = {}

    push(names, "Letzte 50")
    push(ids, LAST50_KEY)

    for index = 1, #monthKeys do
        local key = monthKeys[index]
        push(names, keyToName[key])
        push(ids, key)
    end

    return names, ids
end

function CompletedData.ListForKey(key)
    ensureBuilt()
    if key == LAST50_KEY then
        return last50
    end

    return keyToList[key] or {}
end

local function normalizePoints(value)
    if type(value) == "number" then
        return value
    end

    return tonumber(value) or 0
end

function CompletedData.SummaryCountAndPointsForKey(key)
    local ids = CompletedData.ListForKey(key)
    local count = #ids
    local points = 0

    for index = 1, count do
        local _, _, achievementPoints = safeCallMulti(GetAchievementInfo, ids[index])
        points = points + normalizePoints(achievementPoints)
    end

    return count, points
end

function CompletedData.Constants()
    return { LAST50_KEY = LAST50_KEY }
end

local function buildMeta(achievementId)
    local normalized = normalizeId(achievementId)
    if not normalized then
        return nil
    end

    local isComplete, timestamp, points = collectCompletionMeta(normalized)

    if timestamp == 0 then
        timestamp = nil
    end

    return {
        id = normalized,
        isComplete = isComplete,
        timestamp = timestamp,
        points = points,
    }
end

function CompletedData.IsCompleted(achievementId)
    local meta = buildMeta(achievementId)
    return meta and meta.isComplete == true or false
end

function CompletedData.GetCompletedTimestamp(achievementId)
    local meta = buildMeta(achievementId)
    return meta and meta.timestamp or nil
end

function CompletedData.GetCompletedMeta(achievementId)
    return buildMeta(achievementId)
end

return CompletedData
