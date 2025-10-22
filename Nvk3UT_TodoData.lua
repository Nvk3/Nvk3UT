Nvk3UT = Nvk3UT or {}
local M = {}
Nvk3UT.TodoData = M

local function isFullyComplete(id)
    local utils = Nvk3UT and Nvk3UT.Utils
    if utils and utils.IsAchievementFullyComplete then
        return utils.IsAchievementFullyComplete(id)
    end
    local _, _, _, _, completed = GetAchievementInfo(id)
    return completed == true
end

local function AddRange(result, topIndex, subIndex, numAchievements, searchMap)
    for a=1,(numAchievements or 0) do
        local id = GetAchievementId(topIndex, subIndex, a)
        if not isFullyComplete(id) then
            if searchMap then
                local cIdx, scIdx, aIdx = GetCategoryInfoFromAchievementId(id)
                local r = searchMap[cIdx]
                if r then r = r[scIdx or ZO_ACHIEVEMENTS_ROOT_SUBCATEGORY]; if r and r[aIdx] then result[#result+1] = id end end
            else
                result[#result+1] = id
            end
        end
    end
end

local function BuildSearchMap()
    local results = ACHIEVEMENTS_MANAGER and ACHIEVEMENTS_MANAGER:GetSearchResults()
    if not results or not next(results) then
        return nil
    end
    local U = Nvk3UT and Nvk3UT.Utils
    if U and U.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug then
        U.d("[Nvk3UT][ToDo][Build] done")
    end
    if Nvk3UT and Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then
        Nvk3UT.UI.UpdateStatus()
    end
    return results
end

local function SortByName(ids)
    local idToName = {}
    local gender = GetUnitGender and GetUnitGender("player") or 0
    local function nameOf(id)
        local name = GetAchievementInfo(id)
        name = zo_strformat(name, gender)
        idToName[id] = name
        return name
    end
    table.sort(ids, function(a,b) return (idToName[a] or nameOf(a)) < (idToName[b] or nameOf(b)) end)
end

function M.ListAllOpen(maxCount, respectSearch)
    local U = Nvk3UT and Nvk3UT.Utils; if U and U.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug then U.d("[Nvk3UT][ToDo][Build] start", "data={reason:M.ListAllOpen}") end
    local res = {}
    local searchMap = respectSearch and BuildSearchMap() or nil
    local numCats = GetNumAchievementCategories()
    for top=1,numCats do
        local _, nSub, nAch = GetAchievementCategoryInfo(top)
        if nAch and nAch > 0 then AddRange(res, top, nil, nAch, searchMap) end
        for sub=1,(nSub or 0) do
            local _, nSAch = GetAchievementSubCategoryInfo(top, sub)
            if nSAch and nSAch > 0 then AddRange(res, top, sub, nSAch, searchMap) end
        end
    end
    SortByName(res)
    local limit = tonumber(maxCount)
    if limit and limit > 0 and #res > limit then
        local out={} for i=1,limit do out[i]=res[i] end
        return out
    end
    return res
end

function M.ListOpenForTop(topIndex, respectSearch)
    local U = Nvk3UT and Nvk3UT.Utils; if U and U.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug then U.d("[Nvk3UT][ToDo][Build] start", "data={reason:M.ListOpenForTop}") end
    local res = {}
    if not topIndex then return res end
    local searchMap = respectSearch and BuildSearchMap() or nil
    local _, nSub, nAch = GetAchievementCategoryInfo(topIndex)
    if nAch and nAch > 0 then AddRange(res, topIndex, nil, nAch, searchMap) end
    for sub=1,(nSub or 0) do
        local _, nSAch = GetAchievementSubCategoryInfo(topIndex, sub)
        if nSAch and nSAch > 0 then AddRange(res, topIndex, sub, nSAch, searchMap) end
    end
    SortByName(res)
    return res
end
