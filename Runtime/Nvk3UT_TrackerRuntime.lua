-- Runtime/Nvk3UT_TrackerRuntime.lua
-- Central runtime scheduler that batches tracker refresh work.

Nvk3UT = Nvk3UT or {}
local Addon = Nvk3UT

Addon.TrackerRuntime = Addon.TrackerRuntime or {}
local Runtime = Addon.TrackerRuntime

local WEAK_VALUE_MT = { __mode = "v" }
local unpack = unpack or table.unpack

Runtime._hostRef = Runtime._hostRef or setmetatable({}, WEAK_VALUE_MT)
Runtime._dirty = Runtime._dirty or {}
Runtime._dirty.quest = Runtime._dirty.quest == true
Runtime._dirty.achievement = Runtime._dirty.achievement == true
Runtime._dirty.layout = Runtime._dirty.layout == true
Runtime._queuedChannelsForLog = Runtime._queuedChannelsForLog or {}
Runtime._isProcessingFrame = Runtime._isProcessingFrame == true
Runtime._lastProcessFrameMs = Runtime._lastProcessFrameMs or nil
Runtime._isInCombat = Runtime._isInCombat == true
Runtime._isInCursorMode = Runtime._isInCursorMode == true
Runtime._scheduled = Runtime._scheduled == true
Runtime._scheduledCallId = Runtime._scheduledCallId or nil
Runtime._initialized = Runtime._initialized == true
Runtime._interactivityDirty = Runtime._interactivityDirty == true

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

local DIRTY_CHANNEL_ORDER = { "quest", "achievement", "layout" }

local function ensureDirtyState()
    local dirty = Runtime._dirty
    if type(dirty) ~= "table" then
        dirty = {}
        Runtime._dirty = dirty
    end

    dirty.quest = dirty.quest == true
    dirty.achievement = dirty.achievement == true
    dirty.layout = dirty.layout == true

    return dirty
end

local function ensureQueuedLogTable()
    local queued = Runtime._queuedChannelsForLog
    if type(queued) ~= "table" then
        queued = {}
        Runtime._queuedChannelsForLog = queued
    end

    return queued
end

local function getFrameTimeMs()
    if type(GetFrameTimeMilliseconds) == "function" then
        return GetFrameTimeMilliseconds()
    end

    if type(GetGameTimeMilliseconds) == "function" then
        return GetGameTimeMilliseconds()
    end

    return nil
end

local function formatChannelList(set)
    local ordered = {}
    for index = 1, #DIRTY_CHANNEL_ORDER do
        local channel = DIRTY_CHANNEL_ORDER[index]
        if set and set[channel] then
            ordered[#ordered + 1] = channel
        end
    end

    if #ordered == 0 then
        return "none"
    end

    return table.concat(ordered, "/")
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
    local dirty = ensureDirtyState()
    return dirty.quest or dirty.achievement or dirty.layout
end

local function hasInteractivityWork()
    return Runtime._interactivityDirty == true
end

local function hasPendingWork()
    return hasDirtyFlags() or hasInteractivityWork()
end

local function executeProcessing()
    Runtime._scheduled = false
    Runtime._scheduledCallId = nil

    local nowMs = getFrameTimeMs()
    safeCall(function()
        Runtime:ProcessFrame(nowMs)
    end)
end

local function scheduleProcessing()
    if Runtime._scheduled then
        return
    end

    if not hasPendingWork() then
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
    self._interactivityDirty = true
    self._initialized = true
    debug("TrackerRuntime.Init(%s)", tostring(hostWindow))
    scheduleProcessing()
end

function Runtime:QueueDirty(channel, opts)
    local dirty = ensureDirtyState()
    local queuedLog = ensureQueuedLogTable()

    local normalized = type(channel) == "string" and channel or "all"
    local applyAll = normalized == "all"

    if not applyAll then
        local isKnown = normalized == "quest" or normalized == "achievement" or normalized == "layout"
        if not isKnown then
            debug("Runtime: QueueDirty unknown channel '%s', defaulting to all", tostring(channel))
            applyAll = true
        end
    end

    if applyAll then
        for index = 1, #DIRTY_CHANNEL_ORDER do
            local key = DIRTY_CHANNEL_ORDER[index]
            if not dirty[key] then
                dirty[key] = true
                queuedLog[key] = true
            end
        end
    else
        if not dirty[normalized] then
            dirty[normalized] = true
            queuedLog[normalized] = true
        end
    end

    if hasPendingWork() then
        scheduleProcessing()
    end
end

function Runtime:ProcessFrame(nowMs)
    if self._isProcessingFrame then
        return
    end

    if not hasPendingWork() then
        return
    end

    local frameStamp = nowMs
    if frameStamp == nil then
        frameStamp = getFrameTimeMs()
    end

    if frameStamp ~= nil and self._lastProcessFrameMs ~= nil and frameStamp == self._lastProcessFrameMs then
        scheduleProcessing()
        return
    end

    self._isProcessingFrame = true
    self._lastProcessFrameMs = frameStamp

    local function process()
        local dirty = ensureDirtyState()
        local questDirty = dirty.quest
        local achievementDirty = dirty.achievement
        local layoutDirty = dirty.layout

        dirty.quest = false
        dirty.achievement = false
        dirty.layout = false

        local processedChannels = {}
        local refreshed = false

        if questDirty then
            processedChannels.quest = true
            local built = buildQuestViewModel()
            local refreshedQuest = refreshQuestTracker()
            refreshed = refreshed or refreshedQuest or built
        end

        if achievementDirty then
            processedChannels.achievement = true
            local built = buildAchievementViewModel()
            local refreshedAchievement = refreshAchievementTracker()
            refreshed = refreshed or refreshedAchievement or built
        end

        if refreshed or layoutDirty then
            processedChannels.layout = true
            applyTrackerHostLayout()
        end

        if Runtime._interactivityDirty == true then
            Runtime._interactivityDirty = false
            local hostWindow = getHostWindow()
            if hostWindow and type(hostWindow.SetMouseEnabled) == "function" then
                safeCall(hostWindow.SetMouseEnabled, hostWindow, self._isInCursorMode == true)
            end
        end

        local queuedLog = ensureQueuedLogTable()
        local logQueued = nil
        if next(queuedLog) ~= nil then
            logQueued = formatChannelList(queuedLog)
        end

        for key in pairs(queuedLog) do
            queuedLog[key] = nil
        end

        local logProcessed = nil
        if next(processedChannels) ~= nil then
            logProcessed = formatChannelList(processedChannels)
        end

        if logQueued or logProcessed then
            debug("Runtime: queued %s; processed %s", logQueued or "none", logProcessed or "none")
        end
    end

    local ok, err = pcall(process)

    self._isProcessingFrame = false

    if hasPendingWork() then
        scheduleProcessing()
    end

    if not ok then
        error(err)
    end
end

function Runtime:SetCombatState(isInCombat)
    local normalized = isInCombat == true
    if self._isInCombat == normalized then
        return
    end

    local wasInCombat = self._isInCombat == true
    self._isInCombat = normalized

    if wasInCombat and not normalized then
        self:QueueDirty("layout")
    end
end

function Runtime:SetCursorMode(isInCursorMode)
    local normalized = isInCursorMode == true
    if self._isInCursorMode == normalized then
        return
    end

    self._isInCursorMode = normalized
    self._interactivityDirty = true
    debug("Runtime: cursor mode changed -> %s", tostring(normalized))
    scheduleProcessing()
end

return Runtime
