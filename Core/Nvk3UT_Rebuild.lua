-- Core/Nvk3UT_Rebuild.lua
-- Centralized rebuild / refresh helpers for Nvk3UT.
-- This module is allowed to request a full UI/model refresh, but it should NOT
-- directly register events, build UI controls, or call ReloadUI.

Nvk3UT_Rebuild = Nvk3UT_Rebuild or {}

local Rebuild = Nvk3UT_Rebuild
Rebuild._root = type(Rebuild._root) == "table" and Rebuild._root or nil
Rebuild._selectionLock = Rebuild._selectionLock == true

local ATTACH_RETRY_MS = 100
local ATTACH_MAX_ATTEMPTS = 10

local attachToRoot

local function formatMessage(prefix, fmt, ...)
    if fmt == nil then
        return prefix
    end

    local messageFmt = prefix .. tostring(fmt)
    local ok, message = pcall(string.format, messageFmt, ...)
    if ok then
        return message
    end

    return prefix .. tostring(fmt)
end

local function _debug(fmt, ...)
    if Nvk3UT and type(Nvk3UT.Debug) == "function" then
        Nvk3UT.Debug(fmt, ...)
        return
    end

    if d then
        d(formatMessage("[Nvk3UT Rebuild] ", fmt, ...))
    end
end

local function _error(fmt, ...)
    if Nvk3UT and type(Nvk3UT.Error) == "function" then
        Nvk3UT.Error(fmt, ...)
        return
    end

    if d then
        d(formatMessage("|cFF0000[Nvk3UT Rebuild ERROR]|r ", fmt, ...))
    end
end

local function safeInvoke(label, fn, ...)
    if type(fn) ~= "function" then
        return false
    end

    local ok, result = pcall(fn, ...)
    if not ok then
        _error("%s failed: %s", tostring(label or "callback"), tostring(result))
        return false
    end

    return true, result
end

local function getRoot()
    if type(Rebuild._root) == "table" then
        return Rebuild._root
    end

    local root = rawget(_G, "Nvk3UT")
    if type(root) == "table" then
        if attachToRoot then
            attachToRoot(root)
        end
        return root
    end

    return nil
end

local function resolveAchievementsSystem()
    if type(SYSTEMS) == "table" and type(SYSTEMS.GetObject) == "function" then
        local ok, system = pcall(SYSTEMS.GetObject, SYSTEMS, "achievements")
        if ok and system then
            return system
        end
    end

    return ACHIEVEMENTS
end

local function beginSelectionLock(root)
    if type(root) == "table" then
        if root._rebuild_lock then
            return false, root
        end
        root._rebuild_lock = true
        return true, root
    end

    if Rebuild._selectionLock then
        return false, nil
    end

    Rebuild._selectionLock = true
    return true, nil
end

local function endSelectionLock(root)
    if type(root) == "table" then
        root._rebuild_lock = false
        return
    end

    Rebuild._selectionLock = false
end

local function describeContext(action, context)
    if context == nil or context == "" then
        _debug("%s() requested", action)
    else
        _debug("%s() requested (%s)", action, tostring(context))
    end
end

local function requestQuestTrackerRefresh()
    local root = getRoot()
    local tracker = root and root.QuestTracker
    if type(tracker) ~= "table" then
        return false
    end

    if type(tracker.RequestRefresh) == "function" then
        return safeInvoke("QuestTracker.RequestRefresh", tracker.RequestRefresh)
    end

    if type(tracker.Refresh) == "function" then
        return safeInvoke("QuestTracker.Refresh", tracker.Refresh)
    end

    return false
end

local function requestAchievementTrackerRefresh()
    local root = getRoot()
    local tracker = root and root.AchievementTracker
    if type(tracker) ~= "table" then
        return false
    end

    if type(tracker.RequestRefresh) == "function" then
        return safeInvoke("AchievementTracker.RequestRefresh", tracker.RequestRefresh)
    end

    if type(tracker.Refresh) == "function" then
        return safeInvoke("AchievementTracker.Refresh", tracker.Refresh)
    end

    return false
end

local function refreshTrackerHost()
    local root = getRoot()
    local host = root and root.TrackerHost
    if type(host) ~= "table" or type(host.Refresh) ~= "function" then
        return false
    end

    return safeInvoke("TrackerHost.Refresh", host.Refresh)
end

local function rebuildCompletedData()
    local root = getRoot()
    local completed = root and root.CompletedData
    if type(completed) ~= "table" or type(completed.Rebuild) ~= "function" then
        return false
    end

    return safeInvoke("CompletedData.Rebuild", completed.Rebuild)
end

---Rebuild the currently selected achievement category in the achievements UI.
---@param achievementSystem table|nil
function Rebuild.RebuildAchievementSelection(achievementSystem)
    local ach = achievementSystem or resolveAchievementsSystem()
    if type(ach) ~= "table" then
        return
    end

    local categoryTree = ach.categoryTree
    local onCategorySelected = ach.OnCategorySelected
    if type(categoryTree) ~= "table" or type(categoryTree.GetSelectedData) ~= "function" then
        return
    end

    if type(onCategorySelected) ~= "function" then
        return
    end

    local selectedData = categoryTree:GetSelectedData()
    if not selectedData then
        return
    end

    local root = getRoot()
    local acquired, owner = beginSelectionLock(root)
    if not acquired then
        return
    end

    local ok, err = pcall(onCategorySelected, ach, selectedData, true)
    endSelectionLock(owner)

    if not ok then
        _error("RebuildAchievementSelection failed: %s", tostring(err))
    end
end

Rebuild.RebuildSelected = Rebuild.RebuildAchievementSelection

---Force the quest tracker to refresh its view model / layout.
---@param context string|nil
---@return boolean triggered
function Rebuild.ForceQuestRefresh(context)
    describeContext("ForceQuestRefresh", context)

    local triggered = false

    -- TODO: Replace direct tracker refresh with Runtime dirty-queue once
    -- RUNTIME_001_CREATE_TrackerRuntime_lua lands.
    triggered = requestQuestTrackerRefresh() or triggered

    if not triggered then
        triggered = refreshTrackerHost() or triggered
    end

    return triggered
end

---Force the achievement tracker to refresh its view model / layout.
---@param context string|nil
---@return boolean triggered
function Rebuild.ForceAchievementRefresh(context)
    describeContext("ForceAchievementRefresh", context)

    local triggered = false

    -- TODO: Replace direct tracker refresh with Runtime dirty-queue once
    -- RUNTIME_001_CREATE_TrackerRuntime_lua lands.
    triggered = requestAchievementTrackerRefresh() or triggered

    if not triggered then
        triggered = refreshTrackerHost() or triggered
    end

    -- Keep the achievements journal in sync with tracker changes.
    Rebuild.RebuildAchievementSelection()

    return triggered
end

---Force a global refresh touching quests, achievements, and tracker host state.
---@param context string|nil
function Rebuild.ForceGlobalRefresh(context)
    describeContext("ForceGlobalRefresh", context)

    rebuildCompletedData()

    local questTriggered = Rebuild.ForceQuestRefresh(context)
    local achievementTriggered = Rebuild.ForceAchievementRefresh(context)

    if questTriggered or achievementTriggered then
        refreshTrackerHost()
    end

    local root = getRoot()
    if type(root) == "table" then
        if type(root.UIUpdateStatus) == "function" then
            safeInvoke("Addon:UIUpdateStatus", function()
                root:UIUpdateStatus()
            end)
        elseif root.UI and type(root.UI.UpdateStatus) == "function" then
            safeInvoke("UI.UpdateStatus", root.UI.UpdateStatus)
        end
    end
end

attachToRoot = function(root)
    if type(root) ~= "table" then
        return
    end

    Rebuild._root = root
    root.Rebuild = Rebuild
    root.RebuildSelected = Rebuild.RebuildAchievementSelection
end

function Rebuild.AttachToRoot(root)
    attachToRoot(root)
end

local function scheduleAttach(attempt)
    if type(Rebuild._root) == "table" then
        return
    end

    local root = rawget(_G, "Nvk3UT")
    if type(root) == "table" then
        attachToRoot(root)
        return
    end

    if attempt >= ATTACH_MAX_ATTEMPTS then
        return
    end

    if type(zo_callLater) == "function" then
        zo_callLater(function()
            scheduleAttach(attempt + 1)
        end, ATTACH_RETRY_MS)
    end
end

scheduleAttach(0)

return Rebuild
