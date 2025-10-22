Nvk3UT = Nvk3UT or {}

-- Nvk3UT.Favorites
-- High-level helpers around the favorites saved variables.
local M = {}
Nvk3UT.Favorites = M

local Utils = Nvk3UT and Nvk3UT.Utils
local Data = Nvk3UT and Nvk3UT.FavoritesData

local function ensureData()
    if Data and Data.InitSavedVars then
        Data.InitSavedVars()
    end
end

local function isDebugEnabled()
    return Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug and Utils and Utils.d
end

local function gatherChainIds(achievementId)
    local ids = {}
    if type(achievementId) ~= "number" then
        return ids
    end

    local normalize = Utils and Utils.NormalizeAchievementId
    local baseId = normalize and normalize(achievementId) or achievementId
    local seen = {}

    local function push(id)
        if type(id) == "number" and id ~= 0 and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end

    push(baseId)

    local current = baseId
    while type(GetNextAchievementInLine) == "function" do
        local okNext, nextId = pcall(GetNextAchievementInLine, current)
        if not okNext or type(nextId) ~= "number" or nextId == 0 or seen[nextId] then
            break
        end
        push(nextId)
        current = nextId
    end

    if baseId ~= achievementId then
        push(achievementId)
    end

    return ids
end

---Remove an achievement (and its chain siblings) from the favorites lists.
---@param achievementId number
---@return boolean removed
function M.Remove(achievementId)
    ensureData()
    if type(achievementId) ~= "number" or not Data then
        return false
    end

    if not (Data.Remove and Data.IsFavorite) then
        return false
    end

    local scopes = { "account", "character" }
    local removedAny = false
    local chainIds = gatherChainIds(achievementId)

    for _, candidateId in ipairs(chainIds) do
        for _, scope in ipairs(scopes) do
            if Data.IsFavorite(candidateId, scope) then
                Data.Remove(candidateId, scope)
                removedAny = true
            end
        end
    end

    if removedAny then
        if isDebugEnabled() then
            Utils.d(string.format("[Favorites] Removed completed achievement %d", achievementId))
        end
        if Nvk3UT.UI and Nvk3UT.UI.RefreshAchievements then
            Nvk3UT.UI.RefreshAchievements()
        end
        if Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then
            Nvk3UT.UI.UpdateStatus()
        end
    end

    return removedAny
end

return M
