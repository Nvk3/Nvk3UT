Nvk3UT = Nvk3UT or {}
local UI = Nvk3UT.UI
local function copyTable(src)
    if type(src) ~= "table" then
        return src
    end
    local out = {}
    for key, value in pairs(src) do
        if type(value) == "table" then
            out[key] = copyTable(value)
        else
            out[key] = value
        end
    end
    return out
end

local function blendDefaults(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end
    if type(defaults) ~= "table" then
        return target
    end
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = blendDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

local function getTrackerDefaults()
    local questYellow = { r = 1, g = 0.82, b = 0.1, a = 1 }
    local white = { r = 0.95, g = 0.95, b = 0.95, a = 1 }
    return {
        enabled = true,
        showQuests = true,
        showAchievements = true,
        behavior = {
            hideDefault = false,
            hideInCombat = false,
            locked = false,
            autoGrowV = true,
            autoGrowH = false,
            autoExpandNewQuests = false,
            alwaysExpandAchievements = false,
            tooltips = true,
        },
        background = {
            enabled = false,
            border = false,
            alpha = 60,
            hideWhenLocked = false,
        },
        fonts = {
            category = { face = "ZoFontGameBold", effect = "soft-shadow-thin", size = 22, color = white },
            quest = { face = "ZoFontGame", effect = "soft-shadow-thin", size = 20, color = questYellow },
            task = { face = "ZoFontGameSmall", effect = "soft-shadow-thin", size = 18, color = white },
            achieve = { face = "ZoFontGame", effect = "soft-shadow-thin", size = 20, color = questYellow },
            achieveTask = { face = "ZoFontGameSmall", effect = "soft-shadow-thin", size = 18, color = white },
        },
        collapseState = {
            zones = {},
            quests = {},
            achieves = {},
        },
        pos = {
            x = 200,
            y = 200,
            width = 360,
            height = 420,
            scale = 1,
        },
        throttleMs = 150,
    }
end

local defaults = {
    version = 3,
    debug = false,
    ui = { showStatus = true, favScope = "account", recentWindow = 0, recentMax = 100 },
    features = { completed = true, favorites = true, recent = true, todo = true },
    tracker = getTrackerDefaults(),
}

Nvk3UT.GetTrackerDefaults = getTrackerDefaults
local function OnLoaded(e,name)
    if name~="Nvk3UT" then return end
    Nvk3UT._rebuild_lock=false
    Nvk3UT.sv = ZO_SavedVars:NewAccountWide("Nvk3UT_SV", 2, nil, defaults)
    if Nvk3UT.sv then
        Nvk3UT.sv.tracker = blendDefaults(Nvk3UT.sv.tracker, copyTable(getTrackerDefaults()))
    end
    Nvk3UT.sv.features = Nvk3UT.sv.features or {}
    if Nvk3UT.sv.features.tooltips == nil then Nvk3UT.sv.features.tooltips = true end
    local U = Nvk3UT and Nvk3UT.Utils; if U and U.d then U.d("[Nvk3UT][Core][Init] loaded", "data={version:\"{VERSION}\"}") end
    if Nvk3UT.FavoritesData and Nvk3UT.FavoritesData.InitSavedVars then Nvk3UT.FavoritesData.InitSavedVars() end
    if Nvk3UT.RecentData and Nvk3UT.RecentData.InitSavedVars then Nvk3UT.RecentData.InitSavedVars() end
    if Nvk3UT.RecentData and Nvk3UT.RecentData.RegisterEvents then Nvk3UT.RecentData.RegisterEvents() end
    -- Global status refresh on achievement changes
    if EVENT_MANAGER and Nvk3UT and Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then
        local function _nvk3ut_status_refresh_on_ach_event(...)
            -- keep it light: just refresh the text, counts are computed inside UpdateStatus
            Nvk3UT.UI.UpdateStatus()
        end
        EVENT_MANAGER:RegisterForEvent("Nvk3UT_Status_AchUpdated", EVENT_ACHIEVEMENT_UPDATED, _nvk3ut_status_refresh_on_ach_event)
        EVENT_MANAGER:RegisterForEvent("Nvk3UT_Status_Awarded", EVENT_ACHIEVEMENT_AWARDED, _nvk3ut_status_refresh_on_ach_event)
    end

    local function _nvk3ut_handle_achievement_change(rawId)
        local id = tonumber(rawId)
        if not id then return end

        local Ach = Nvk3UT and Nvk3UT.Achievements
        if not (Ach and Ach.IsComplete) then
            return
        end

        local isComplete = Ach.IsComplete(id)
        if not isComplete then
            return
        end

        local utils = Nvk3UT and Nvk3UT.Utils
        local normalized = utils and utils.NormalizeAchievementId and utils.NormalizeAchievementId(id) or id

        local favoritesData = Nvk3UT and Nvk3UT.FavoritesData
        local favorites = Nvk3UT and Nvk3UT.Favorites
        if favoritesData and favoritesData.IsFavorite and favorites and favorites.Remove then
            local candidates = { id }
            if normalized and normalized ~= id then
                candidates[#candidates + 1] = normalized
            end
            for _, candidateId in ipairs(candidates) do
                if favoritesData.IsFavorite(candidateId, "account") or favoritesData.IsFavorite(candidateId, "character") then
                    favorites.Remove(candidateId)
                end
            end
        end

        local progress = Nvk3UT and Nvk3UT._recentSV and Nvk3UT._recentSV.progress
        if progress and type(progress) == "table" then
            local function tracked(val)
                if val == nil then return false end
                if progress[val] ~= nil then return true end
                local key = tostring(val)
                return progress[key] ~= nil
            end
            if tracked(id) or (normalized and normalized ~= id and tracked(normalized)) then
                local recent = Nvk3UT and Nvk3UT.Recent
                if recent and recent.CleanupCompleted then
                    recent.CleanupCompleted()
                end
            end
        end
    end

    if EVENT_MANAGER then
        EVENT_MANAGER:UnregisterForEvent("Nvk3UT_AchievementWatcher_Update", EVENT_ACHIEVEMENT_UPDATED)
        EVENT_MANAGER:RegisterForEvent("Nvk3UT_AchievementWatcher_Update", EVENT_ACHIEVEMENT_UPDATED, function(_, achievementId)
            _nvk3ut_handle_achievement_change(achievementId)
        end)
        EVENT_MANAGER:UnregisterForEvent("Nvk3UT_AchievementWatcher_Awarded", EVENT_ACHIEVEMENT_AWARDED)
        EVENT_MANAGER:RegisterForEvent("Nvk3UT_AchievementWatcher_Awarded", EVENT_ACHIEVEMENT_AWARDED, function(_, _, _, achievementId)
            _nvk3ut_handle_achievement_change(achievementId)
        end)
    end

    if Nvk3UT.QuestTracker and Nvk3UT.QuestTracker.Init then
        Nvk3UT.QuestTracker.Init()
    end
    if Nvk3UT.UI then Nvk3UT.UI.BuildLAM(); Nvk3UT.UI.UpdateStatus() end
    -- Enable integrations when ACHIEVEMENTS exists
    local function TryEnable(attempt)
        attempt=attempt or 1
        if ACHIEVEMENTS then
            if not Nvk3UT.__integrated then
                Nvk3UT.__integrated=true
                local U = Nvk3UT and Nvk3UT.Utils; if U and U.d then U.d("[Nvk3UT][Core][Integrations] enabled", "data={favorites:", tostring(Nvk3UT_EnableFavorites and true or false), ", recent:", tostring(Nvk3UT_EnableRecentCategory and true or false), ", completed:", tostring(Nvk3UT_EnableCompletedCategory and true or false), "}") end
                if Nvk3UT_EnableFavorites then Nvk3UT_EnableFavorites() end
                if Nvk3UT_EnableRecentCategory then Nvk3UT_EnableRecentCategory() end
                if Nvk3UT_EnableTodoCategory then Nvk3UT_EnableTodoCategory() end
            end
            return
        end
        if attempt<15 then zo_callLater(function() TryEnable(attempt+1) end, 500) end
    end
    TryEnable(1)
    if Nvk3UT.Tooltips and Nvk3UT.Tooltips.Init then Nvk3UT.Tooltips.Init() end
    EVENT_MANAGER:UnregisterForEvent("Nvk3UT_Load", EVENT_ADD_ON_LOADED)
end
EVENT_MANAGER:RegisterForEvent("Nvk3UT_Load", EVENT_ADD_ON_LOADED, OnLoaded)
SLASH_COMMANDS["/nvk3test"]=function() if Nvk3UT.Diagnostics then Nvk3UT.Diagnostics.SelfTest(); Nvk3UT.Diagnostics.SystemTest() end end


-- Enable Completed category
if Nvk3UT_EnableCompletedCategory then Nvk3UT_EnableCompletedCategory() end
