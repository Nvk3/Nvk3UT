Nvk3UT = Nvk3UT or {}

local M = Nvk3UT

M.Core = M.Core or {}
local Module = M.Core

--[[
MIGRATION NOTES
- Legacy quest tracker bootstrap/helpers previously defined in Nvk3UT_Questtracker.lua
  are now owned by the modular files:
    * SavedVars / event bus               -> Nvk3UT_Core.lua (this file)
    * Quest data acquisition              -> Nvk3UT_QuestModel.lua
    * Achievement favourites aggregation  -> Nvk3UT_AchievementModel.lua
    * Tracker orchestration & settings    -> Nvk3UT_Tracker.lua
    * Unified tracker view / scroll list  -> Nvk3UT_TrackerView.lua
- Removed obsolete calls to Nvk3UT.Questtracker.* and deleted the legacy file.
- No Legacy_* shims required; callers now use Nvk3UT.Tracker directly.
]]

-- SANITY REPORT
-- Files: Core, LAM, QuestModel, AchievementModel, TrackerView, Tracker, XML – tightened publish queue, nil guards, and tooltip/layout safety.
-- TODO: Monitor future tracker feature toggles for regressions; keep diagnostics slash commands lightweight.

local subscribers = {}
Module._publishQueue = Module._publishQueue or {}
Module._isPublishing = false

local function debugLog(message)
    if d then
        d(string.format("[Nvk3UT] Core: %s", message))
    end
end

function Module.Subscribe(topic, fn)
    if type(topic) ~= "string" or type(fn) ~= "function" then
        return
    end

    local bucket = subscribers[topic]
    if not bucket then
        bucket = {}
        subscribers[topic] = bucket
    end

    bucket[#bucket + 1] = fn
    return fn
end

function Module.Publish(topic, payload)
    if type(topic) ~= "string" then
        return
    end

    if not subscribers[topic] or #subscribers[topic] == 0 then
        return
    end

    local queue = Module._publishQueue
    queue[#queue + 1] = { topic = topic, payload = payload }

    if Module._isPublishing then
        return
    end

    Module._isPublishing = true

    while #queue > 0 do
        local entry = table.remove(queue, 1)
        local bucket = subscribers[entry.topic]
        if bucket and #bucket > 0 then
            local snapshot = {}
            for index = 1, #bucket do
                snapshot[index] = bucket[index]
            end

            for index = 1, #snapshot do
                local callback = snapshot[index]
                if type(callback) == "function" then
                    local ok, err = pcall(callback, entry.payload)
                    if not ok then
                        debugLog(string.format("Publish error for '%s': %s", entry.topic, tostring(err)))
                    end
                end
            end
        end
    end

    Module._isPublishing = false
end

M.Subscribe = Module.Subscribe
M.Publish = Module.Publish

function Module.Unsubscribe(topic, fn)
    if type(topic) ~= "string" or type(fn) ~= "function" then
        return
    end

    local bucket = subscribers[topic]
    if not bucket then
        return
    end

    for index = #bucket, 1, -1 do
        if bucket[index] == fn then
            table.remove(bucket, index)
        end
    end
end

M.Unsubscribe = Module.Unsubscribe

local CORE_EVENT_NAMESPACE = "Nvk3UT_Core_OnLoaded"

local function ensureSettingsNamespaces()
    if not Module.SV then
        return
    end

    Module.SV.settings = Module.SV.settings or {}
    local settings = Module.SV.settings
    settings.quest = settings.quest or {}
    settings.ach = settings.ach or {}
    settings.tracker = settings.tracker or {}
end

local function initializeSavedVars()
    Module.SV = Nvk3UT and Nvk3UT.sv or Module.SV
    ensureSettingsNamespaces()
end

local function initializeModules()
    if M.LAM and M.LAM.Init then
        M.LAM.Init()
    end

    if M.QuestModel and M.QuestModel.Init then
        M.QuestModel.Init()
    end

    if M.AchievementModel and M.AchievementModel.Init then
        M.AchievementModel.Init()
    end

    if M.Tracker and M.Tracker.Init then
        M.Tracker.Init()
    end

    if M.TrackerView and M.TrackerView.Init then
        M.TrackerView.Init()
    end
end

local function trackerColor(r, g, b, a)
    return { r = r, g = g, b = b, a = a or 1 }
end

local trackerDefaults = {
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
        category = { face = "ZoFontHeader2", effect = "soft-shadow-thin", size = 24, color = trackerColor(0.89, 0.82, 0.67, 1) },
        quest = { face = "ZoFontGameBold", effect = "soft-shadow-thin", size = 20, color = trackerColor(1, 0.82, 0.1, 1) },
        task = { face = "ZoFontGame", effect = "soft-shadow-thin", size = 18, color = trackerColor(0.9, 0.9, 0.9, 1) },
        achieve = { face = "ZoFontGameBold", effect = "soft-shadow-thin", size = 20, color = trackerColor(1, 0.82, 0.1, 1) },
        achieveTask = { face = "ZoFontGame", effect = "soft-shadow-thin", size = 18, color = trackerColor(0.9, 0.9, 0.9, 1) },
    },
    collapseState = {
        zones = {},
        quests = {},
        achieves = {},
    },
    pos = { x = 400, y = 200, scale = 1.0, width = 320, height = 360 },
    throttleMs = 150,
}

local defaults={version=3,debug=false,ui={showStatus=true,favScope='account',recentWindow=0,recentMax=100},features={completed=true,favorites=true,recent=true,todo=true},tracker=trackerDefaults}
local function OnLoaded(e,name)
    if name~="Nvk3UT" then return end
    Nvk3UT._rebuild_lock=false
    Nvk3UT.sv = ZO_SavedVars:NewAccountWide("Nvk3UT_SV", 2, nil, defaults)
    local function mergeDefaults(target, source)
        if type(target) ~= "table" or type(source) ~= "table" then
            return
        end
        for key, value in pairs(source) do
            if type(value) == "table" then
                target[key] = target[key] or {}
                mergeDefaults(target[key], value)
            elseif target[key] == nil then
                target[key] = value
            end
        end
    end
    Nvk3UT.sv.tracker = Nvk3UT.sv.tracker or {}
    mergeDefaults(Nvk3UT.sv.tracker, trackerDefaults)
    Nvk3UT.sv.settings = Nvk3UT.sv.settings or {}
    local settings = Nvk3UT.sv.settings
    settings.quest = settings.quest or {}
    settings.ach = settings.ach or {}
    settings.tracker = settings.tracker or {}

    local questSettings = settings.quest
    local achSettings = settings.ach
    local trackerSettings = settings.tracker

    if questSettings.enabled == nil then
        questSettings.enabled = Nvk3UT.sv.tracker.showQuests ~= false
    end
    if questSettings.autoExpandNew == nil then
        questSettings.autoExpandNew = Nvk3UT.sv.tracker.behavior.autoExpandNewQuests == true
    end
    if questSettings.tooltips == nil then
        local behavior = Nvk3UT.sv.tracker.behavior or {}
        questSettings.tooltips = behavior.tooltips ~= false
    end

    if achSettings.enabled == nil then
        achSettings.enabled = Nvk3UT.sv.tracker.showAchievements ~= false
    end
    if achSettings.alwaysExpand == nil then
        achSettings.alwaysExpand = Nvk3UT.sv.tracker.behavior.alwaysExpandAchievements == true
    end
    if achSettings.multiStageCombine == nil then
        achSettings.multiStageCombine = true
    end
    if achSettings.removeOnComplete == nil then
        achSettings.removeOnComplete = false
    end
    if achSettings.tooltips == nil then
        achSettings.tooltips = questSettings.tooltips ~= false
    end

    if trackerSettings.hideDefault == nil then
        trackerSettings.hideDefault = Nvk3UT.sv.tracker.behavior.hideDefault == true
    end
    if trackerSettings.hideInCombat == nil then
        trackerSettings.hideInCombat = Nvk3UT.sv.tracker.behavior.hideInCombat == true
    end
    if trackerSettings.locked == nil then
        trackerSettings.locked = Nvk3UT.sv.tracker.behavior.locked == true
    end
    if trackerSettings.autoGrowV == nil then
        trackerSettings.autoGrowV = Nvk3UT.sv.tracker.behavior.autoGrowV ~= false
    end
    if trackerSettings.autoGrowH == nil then
        trackerSettings.autoGrowH = Nvk3UT.sv.tracker.behavior.autoGrowH == true
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

    initializeSavedVars()
    initializeModules()

    EVENT_MANAGER:UnregisterForEvent(CORE_EVENT_NAMESPACE, EVENT_ADD_ON_LOADED)
end
EVENT_MANAGER:RegisterForEvent(CORE_EVENT_NAMESPACE, EVENT_ADD_ON_LOADED, OnLoaded)
SLASH_COMMANDS["/nvk3test"]=function() if Nvk3UT.Diagnostics then Nvk3UT.Diagnostics.SelfTest(); Nvk3UT.Diagnostics.SystemTest() end end

SLASH_COMMANDS["/nvk sanity"] = function()
    local function log(message)
        if d then
            d(string.format("[Nvk3UT][Sanity] %s", tostring(message)))
        end
    end

    local checks = {
        { label = "QuestModel.GetList", fn = M.QuestModel and M.QuestModel.GetList },
        { label = "AchievementModel.GetList", fn = M.AchievementModel and M.AchievementModel.GetList },
        { label = "TrackerView.BuildUnifiedFeed", fn = M.TrackerView and M.TrackerView.BuildUnifiedFeed },
    }

    local missing = false
    for _, entry in ipairs(checks) do
        if type(entry.fn) ~= "function" then
            missing = true
            log("Missing API: " .. entry.label)
        end
    end
    if not missing then
        log("Module API surface OK")
    end

    if type(checks[1].fn) == "function" then
        local ok, order, byId = pcall(checks[1].fn)
        if ok then
            local count = type(order) == "table" and #order or 0
            local mapCount = 0
            if type(byId) == "table" then
                for _ in pairs(byId) do
                    mapCount = mapCount + 1
                end
            end
            log(string.format("QuestModel order entries=%d map=%d", count, mapCount))
        else
            log("QuestModel.GetList error: " .. tostring(order))
        end
    end

    if type(checks[2].fn) == "function" then
        local ok, list = pcall(checks[2].fn)
        if ok then
            local count = type(list) == "table" and #list or 0
            log(string.format("AchievementModel list entries=%d", count))
        else
            log("AchievementModel.GetList error: " .. tostring(list))
        end
    end

    local questFeedCount = 0
    local achFeedCount = 0

    if M.QuestSection and type(M.QuestSection.BuildFeed) == "function" then
        local ok, feed = pcall(function()
            return M.QuestSection:BuildFeed()
        end)
        if ok and type(feed) == "table" then
            questFeedCount = #feed
            local first = feed[1] and tostring(feed[1].dataType) or "-"
            local last = feed[#feed] and tostring(feed[#feed].dataType) or "-"
            log(string.format("QuestSection feed count=%d first=%s last=%s", questFeedCount, first, last))
        elseif not ok then
            log("QuestSection.BuildFeed error: " .. tostring(feed))
        end
    else
        log("QuestSection unavailable or uninitialised")
    end

    if M.AchSection and type(M.AchSection.BuildFeed) == "function" then
        local ok, feed = pcall(function()
            return M.AchSection:BuildFeed()
        end)
        if ok and type(feed) == "table" then
            achFeedCount = #feed
            local first = feed[1] and tostring(feed[1].dataType) or "-"
            local last = feed[#feed] and tostring(feed[#feed].dataType) or "-"
            log(string.format("AchSection feed count=%d first=%s last=%s", achFeedCount, first, last))
        elseif not ok then
            log("AchSection.BuildFeed error: " .. tostring(feed))
        end
    else
        log("AchSection unavailable or uninitialised")
    end

    local publish = Module.Publish or (M.Core and M.Core.Publish)
    if type(publish) == "function" then
        local ok, err = pcall(publish, "settings:changed", "tracker.sanityCheck")
        if ok then
            log("settings:changed dispatch OK")
        else
            log("settings:changed dispatch error: " .. tostring(err))
        end
    end

    log(string.format("Sanity summary quests=%d achievements=%d", questFeedCount, achFeedCount))
end

SLASH_COMMANDS["/nvk test sections"] = function()
    local questSection = Nvk3UT and Nvk3UT.QuestSection
    local achSection = Nvk3UT and Nvk3UT.AchSection
    if questSection then
        local visible = questSection.IsVisible and questSection:IsVisible()
        local dirty = questSection.IsDirty and questSection:IsDirty()
        d(string.format("[Nvk3UT] QuestSection visible=%s dirty=%s", tostring(visible), tostring(dirty)))
        if questSection.BuildFeed then
            local feed = questSection:BuildFeed()
            local firstType = feed[1] and tostring(feed[1].dataType)
            local lastType = feed[#feed] and tostring(feed[#feed].dataType)
            d(string.format("[Nvk3UT] QuestSection feed count=%d first=%s last=%s", #feed, firstType or "-", lastType or "-"))
        end
    else
        d("[Nvk3UT] QuestSection not available")
    end

    if achSection then
        local visible = achSection.IsVisible and achSection:IsVisible()
        local dirty = achSection.IsDirty and achSection:IsDirty()
        d(string.format("[Nvk3UT] AchSection visible=%s dirty=%s", tostring(visible), tostring(dirty)))
        if achSection.BuildFeed then
            local feed = achSection:BuildFeed()
            local firstType = feed[1] and tostring(feed[1].dataType)
            local lastType = feed[#feed] and tostring(feed[#feed].dataType)
            d(string.format("[Nvk3UT] AchSection feed count=%d first=%s last=%s", #feed, firstType or "-", lastType or "-"))
        end
    else
        d("[Nvk3UT] AchSection not available")
    end
end


-- Enable Completed category
if Nvk3UT_EnableCompletedCategory then Nvk3UT_EnableCompletedCategory() end
