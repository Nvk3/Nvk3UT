local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Controller = Nvk3UT.AchievementTrackerController or {}
Nvk3UT.AchievementTrackerController = Controller

local state = {
    dirty = true,
    lastReason = nil,
}

local function getRoot()
    local root = rawget(_G, addonName)
    if type(root) == "table" then
        return root
    end

    return Nvk3UT
end

local function getRuntime()
    local root = getRoot()
    return root and rawget(root, "TrackerRuntime")
end

local function getModel()
    local root = getRoot()
    return root and rawget(root, "AchievementModel")
end

local function isDebugEnabled()
    local root = getRoot()
    if root and type(root.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(root.IsDebugEnabled, root)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local utils = root and rawget(root, "Utils")
    if utils and type(utils.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(utils.IsDebugEnabled)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local diagnostics = root and rawget(root, "Diagnostics")
    if diagnostics and type(diagnostics.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return diagnostics:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    return false
end

local function debug(message, ...)
    if not isDebugEnabled() then
        return
    end

    local formatted = message
    if select("#", ...) > 0 then
        local ok, fmt = pcall(string.format, message, ...)
        if ok then
            formatted = fmt
        end
    end

    if d then
        d(string.format("[%s][AchievementCtrl] %s", addonName, formatted))
    elseif print then
        print(string.format("[%s][AchievementCtrl] %s", addonName, formatted))
    end
end

local function isFavorite(achievementId)
    if achievementId == nil then
        return false
    end

    if type(IsFavoriteAchievement) == "function" then
        local ok, flagged = pcall(IsFavoriteAchievement, achievementId)
        if ok and flagged ~= nil then
            return flagged == true
        end
    end

    local root = getRoot()
    local favorites = root and rawget(root, "FavoritesData")
    if favorites and type(favorites.IsFavorited) == "function" then
        local ok, flagged = pcall(favorites.IsFavorited, achievementId)
        if ok and flagged ~= nil then
            return flagged == true
        end
    end

    return false
end

local function resolveSnapshot()
    local Model = getModel()
    if Model and type(Model.GetSnapshot) == "function" then
        local ok, snapshot = pcall(Model.GetSnapshot)
        if ok then
            return snapshot
        end
    end

    return nil
end

function Controller:Init()
    state.dirty = true
    state.lastReason = nil
end

function Controller:MarkDirty(reason)
    state.dirty = true
    state.lastReason = reason
    debug("MarkDirty: %s", tostring(reason))

    local runtime = getRuntime()
    if runtime and type(runtime.QueueDirty) == "function" then
        pcall(runtime.QueueDirty, runtime, "achievement")
    end
end

function Controller:IsDirty()
    return state.dirty == true
end

local function buildFavorites()
    local snapshot = resolveSnapshot()
    local achievements = snapshot and snapshot.achievements
    if type(achievements) ~= "table" then
        debug("BuildViewModel: missing snapshot; favorites=0")
        return {}
    end

    local favorites = {}
    for index = 1, #achievements do
        local achievement = achievements[index]
        local achievementId = achievement and achievement.id
        if achievementId and isFavorite(achievementId) then
            favorites[#favorites + 1] = {
                id = achievementId,
                name = achievement and achievement.name,
                icon = achievement and achievement.icon,
                iconTexture = achievement and achievement.iconTexture,
                progress = achievement and achievement.progress,
                progressText = achievement and achievement.progressText,
            }
        end
    end

    return favorites
end

function Controller:BuildViewModel()
    state.dirty = false

    local favorites = buildFavorites()
    debug("BuildViewModel: favorites=%d", #favorites)

    return { favorites = favorites }
end

return Controller
