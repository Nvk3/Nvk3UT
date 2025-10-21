
Nvk3UT = Nvk3UT or {}
local M = {}
Nvk3UT.CompletedData = M

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

local function push(t, v) t[#t+1] = v end

local function addIdToMonth(id, ts)
    local dt = os.date("*t", ts)
    local key = dt.year * 100 + dt.month
    keyToList[key] = keyToList[key] or {}
    push(keyToList[key], id)
    if not keyToName[key] then
        keyToName[key] = string.format("%s %d", MONTH_NAMES[dt.month] or tostring(dt.month), dt.year)
        push(monthKeys, key)
    end
end

local function processAchievements(ids)
    if not ids then return end
    for _, id in ipairs(ids) do
        if IsAchievementComplete(id) then
            local ts = GetAchievementTimestamp and GetAchievementTimestamp(id) or 0
            if ts and ts ~= 0 then
                push(last50, id)
                addIdToMonth(id, ts)
            end
        end
    end
end

local function scanAllAchievements()
    last50 = {}
    keyToList, keyToName, monthKeys = {}, {}, {}
    local numTop = GetNumAchievementCategories and GetNumAchievementCategories() or 0
    for categoryIndex = 1, numTop do
        local _, numSubCategories, numAchievements = GetAchievementCategoryInfo(categoryIndex)
        if numAchievements and numAchievements > 0 then
            processAchievements(ZO_GetAchievementIds(categoryIndex, nil, numAchievements, false))
        end
        for subCategoryIndex = 1, (numSubCategories or 0) do
            local _, subNumAchievements = GetAchievementSubCategoryInfo(categoryIndex, subCategoryIndex)
            if subNumAchievements and subNumAchievements > 0 then
                processAchievements(ZO_GetAchievementIds(categoryIndex, subCategoryIndex, subNumAchievements, false))
            end
        end
    end
    table.sort(last50, function(a, b)
        local ta = GetAchievementTimestamp(a) or 0
        local tb = GetAchievementTimestamp(b) or 0
        return ta > tb
    end)
    if #last50 > 50 then
        local trimmed = {}
        for i=1,50 do trimmed[i] = last50[i] end
        last50 = trimmed
    end
    table.sort(monthKeys, function(a,b) return a>b end)
end

local function ensure()
    if not built then
        scanAllAchievements()
        built = true
    end
end

function M.Rebuild()
    built = false
end

function M.GetSubcategoryList()
    ensure()
    local names, ids = {}, {}
    push(names, "Letzte 50")
    push(ids, LAST50_KEY)
    for _, key in ipairs(monthKeys) do
        push(names, keyToName[key])
        push(ids, key)
    end
    return names, ids
end

function M.ListForKey(key)
    ensure()
    if key == LAST50_KEY then
        return last50
    end
    return keyToList[key] or {}
end

function M.SummaryCountAndPointsForKey(key)
    local ids = M.ListForKey(key)
    local count = #ids
    local points = 0
    for i=1,count do
        local _,_,_,pts = GetAchievementInfo(ids[i])
        points = points + (pts or 0)
    end
    return count, points
end

function M.Constants()
    return { LAST50_KEY = LAST50_KEY }
end
