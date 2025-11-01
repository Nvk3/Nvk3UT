-- Runtime/Nvk3UT_TrackerRuntime.lua
-- Central runtime scheduler that batches tracker refresh work.

Nvk3UT = Nvk3UT or {}
local Addon = Nvk3UT

Addon.TrackerRuntime = Addon.TrackerRuntime or {}
local Runtime = Addon.TrackerRuntime

local WEAK_VALUE_MT = { __mode = "v" }
local unpack = unpack or table.unpack

Runtime._hostRef = Runtime._hostRef or setmetatable({}, WEAK_VALUE_MT)
Runtime._questDirty = Runtime._questDirty == true
Runtime._achievementDirty = Runtime._achievementDirty == true
Runtime._layoutDirty = Runtime._layoutDirty == true
Runtime._isInCombat = Runtime._isInCombat == true
Runtime._isInCursorMode = Runtime._isInCursorMode == true
Runtime._scheduled = Runtime._scheduled == true
Runtime._scheduledCallId = Runtime._scheduledCallId or nil
Runtime._initialized = Runtime._initialized == true

local function debug(fmt, ...)
    if Addon and type(Addon.Debug) == "function" then
        Addon.Debug(fmt, ...)
    end
end

local function safeCall(fn, ...)
    if Addon and type(Addon.SafeCall) == "function" then
        return Addon.SafeCall(fn, ...)
    end

    if type(fn) == "function" then
        local ok, result = pcall(fn, ...)
        if ok then
            return result
        end
    end

    return nil
end

local function getHostWindow()
    local ref = Runtime._hostRef
    if type(ref) ~= "table" then
        return nil
    end

    return ref.hostWindow
end

local function setHostWindow(hostWindow)
    local ref = Runtime._hostRef
    if type(ref) ~= "table" then
        ref = setmetatable({}, WEAK_VALUE_MT)
        Runtime._hostRef = ref
    end

    ref.hostWindow = hostWindow
end

local function callWithOptionalSelf(targetTable, fn, preferPlainCall, ...)
    if type(fn) ~= "function" then
        return false
    end

    local invoked = false
    local args = { ... }

    local function tryInvoke(withSelf)
        if withSelf and targetTable == nil then
            return false
        end

        local ok
        if withSelf then
            ok = pcall(fn, targetTable, unpack(args))
        else
            ok = pcall(fn, unpack(args))
        end

        if ok then
            invoked = true
            return true
        end

        return false
    end

    safeCall(function()
        if preferPlainCall then
            if tryInvoke(false) then
                return
            end
            tryInvoke(true)
            return
        end

        if tryInvoke(true) then
            return
        end

        tryInvoke(false)
    end)

    return invoked
end

local function buildQuestViewModel()
    local controller = rawget(Addon, "QuestTrackerController")
    if type(controller) ~= "table" then
        return false
    end

    local build = controller.BuildViewModel or controller.Build
    if type(build) ~= "function" then
        return false
    end

    return callWithOptionalSelf(controller, build, false)
end

local function refreshQuestTracker()
    local tracker = rawget(Addon, "QuestTracker")
    if type(tracker) ~= "table" then
        return false
    end

    local requestRefresh = tracker.RequestRefresh
    if type(requestRefresh) == "function" then
        safeCall(requestRefresh)
        return true
    end

    local refresh = tracker.Refresh
    if type(refresh) == "function" then
        safeCall(refresh)
        return true
    end

    return false
end

local function buildAchievementViewModel()
    local controller = rawget(Addon, "AchievementTrackerController")
    if type(controller) ~= "table" then
        return false
    end

    local build = controller.BuildViewModel or controller.Build
    if type(build) ~= "function" then
        return false
    end

    return callWithOptionalSelf(controller, build, false)
end

local function refreshAchievementTracker()
    local tracker = rawget(Addon, "AchievementTracker")
    if type(tracker) ~= "table" then
        return false
    end

    local requestRefresh = tracker.RequestRefresh
    if type(requestRefresh) == "function" then
        safeCall(requestRefresh)
        return true
    end

    local refresh = tracker.Refresh
    if type(refresh) == "function" then
        safeCall(refresh)
        return true
    end

    return false
end

local function applyTrackerHostLayout()
    local layout = rawget(Addon, "TrackerHostLayout")
    if type(layout) ~= "table" then
        return false
    end

    local apply = layout.Apply or layout.ApplyLayout or layout.Refresh or layout.Update
    if type(apply) ~= "function" then
        return false
    end

    local hostWindow = getHostWindow()

    if hostWindow ~= nil then
        local applied = callWithOptionalSelf(layout, apply, true, hostWindow)
        if applied then
            return true
        end
    end

    return callWithOptionalSelf(layout, apply, true)
end

local function hasDirtyFlags()
    return Runtime._questDirty or Runtime._achievementDirty or Runtime._layoutDirty
end

local function clearDirtyFlags()
    Runtime._questDirty = false
    Runtime._achievementDirty = false
    Runtime._layoutDirty = false
end

local function executeProcessing()
    Runtime._scheduled = false
    Runtime._scheduledCallId = nil

    safeCall(function()
        Runtime:ProcessFrame()
    end)
end

local function scheduleProcessing()
    if Runtime._scheduled then
        return
    end

    if not hasDirtyFlags() then
        return
    end

    Runtime._scheduled = true

    if type(zo_callLater) == "function" then
        Runtime._scheduledCallId = zo_callLater(executeProcessing, 0)
        return
    end

    executeProcessing()
end

function Runtime:Init(hostWindow)
    setHostWindow(hostWindow)
    self._initialized = true
    debug("TrackerRuntime.Init(%s)", tostring(hostWindow))
end

function Runtime:QueueDirty(kind)
    if kind == "quest" then
        self._questDirty = true
    elseif kind == "achievement" then
        self._achievementDirty = true
    elseif kind == "layout" then
        self._layoutDirty = true
    else
        debug("TrackerRuntime.QueueDirty ignored unknown kind '%s'", tostring(kind))
        return
    end

    scheduleProcessing()
end

function Runtime:ProcessFrame()
    if not hasDirtyFlags() then
        return
    end

    debug("TrackerRuntime.ProcessFrame begin")

    local questDirty = self._questDirty
    local achievementDirty = self._achievementDirty
    local layoutDirty = self._layoutDirty

    clearDirtyFlags()

    local refreshed = false

    if questDirty then
        debug("TrackerRuntime processing quest dirty")
        local built = buildQuestViewModel()
        local refreshedQuest = refreshQuestTracker()
        refreshed = refreshed or refreshedQuest or built
    end

    if achievementDirty then
        debug("TrackerRuntime processing achievement dirty")
        local built = buildAchievementViewModel()
        local refreshedAchievement = refreshAchievementTracker()
        refreshed = refreshed or refreshedAchievement or built
    end

    if refreshed or layoutDirty then
        debug("TrackerRuntime applying layout (refreshed=%s, layoutDirty=%s)", tostring(refreshed), tostring(layoutDirty))
        applyTrackerHostLayout()
    end

    debug("TrackerRuntime.ProcessFrame end")

    if hasDirtyFlags() then
        scheduleProcessing()
    end
end

function Runtime:SetCombatState(isInCombat)
    local normalized = isInCombat == true
    if self._isInCombat == normalized then
        return
    end

    self._isInCombat = normalized
    self._layoutDirty = true
    scheduleProcessing()
end

function Runtime:SetCursorMode(isInCursorMode)
    local normalized = isInCursorMode == true
    if self._isInCursorMode == normalized then
        return
    end

    self._isInCursorMode = normalized
    self._layoutDirty = true
    scheduleProcessing()
end

return Runtime
