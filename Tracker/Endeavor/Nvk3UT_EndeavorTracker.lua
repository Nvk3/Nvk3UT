local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local EndeavorTracker = {}
EndeavorTracker.__index = EndeavorTracker

local MODULE_TAG = addonName .. ".EndeavorTracker"

local state = {
    container = nil,
    currentHeight = 0,
    isInitialized = false,
    isDisposed = false,
}

-- EBOOT TempEvents (Endeavor)
-- Purpose: SHIM-only events for Endeavor until EEVENTS_*_SWITCH migrates handlers to Events/*
-- Removal plan:
--   1) Set EBOOT_TEMP_EVENTS_ENABLED = false
--   2) Delete code between EBOOT_TEMP_EVENTS_BEGIN/END markers
--   3) Ensure Events/* registers Endeavor events; this tracker must not register any events
-- Search tags: @EBOOT @TEMP @ENDEAVOR @REMOVE_ON_EEVENTS_SWITCH
--[[ EBOOT_TEMP_EVENTS_BEGIN: Endeavor (remove on Eevents SWITCH) ]]

local EBOOT_TEMP_EVENTS_ENABLED = true -- flip to false in Eevents SWITCH token

local TEMP_EVENT_NAMESPACE = MODULE_TAG .. ".TempEvents"

local tempEvents = {
    registered = false,
    pending = false,
    timerHandle = nil,
    lastQueuedAt = 0,
    debounceMs = 150,
}

local shimStateInitialized = false
local shimModelInitialized = false
local centralEventsWarningShown = false

local initKick = {
    done = false,
    timerHandle = nil,
    delayMs = 200,
}

local progressFallback = {
    lastProgressAtMs = nil,
    timerHandle = nil,
    delayMs = 750,
}

local function CallIfFunction(fn, ...)
    if type(fn) == "function" then
        return pcall(fn, ...)
    end

    return false, "not a function"
end

local function ScheduleLater(ms, cb)
    ms = (type(ms) == "number" and ms >= 0) and ms or 0

    if type(cb) ~= "function" then
        return nil
    end

    if type(_G.zo_callLater) == "function" then
        local ok, handle = pcall(_G.zo_callLater, cb, ms)
        if ok and handle ~= nil then
            return handle
        end
    end

    local id = "Nvk3UT_Endeavor_Once_" .. tostring(getFrameTime())
    local eventManager = rawget(_G, "EVENT_MANAGER")
    if eventManager and type(eventManager.RegisterForUpdate) == "function" then
        if type(eventManager.UnregisterForUpdate) == "function" then
            eventManager:UnregisterForUpdate(id)
        end
        eventManager:RegisterForUpdate(id, ms, function()
            local manager = rawget(_G, "EVENT_MANAGER")
            if manager and type(manager.UnregisterForUpdate) == "function" then
                manager:UnregisterForUpdate(id)
            end
            CallIfFunction(cb)
        end)
        return id
    end

    return nil
end

local function RemoveScheduled(handle)
    if handle == nil then
        return
    end

    if type(handle) == "number" and type(_G.zo_removeCallLater) == "function" then
        pcall(_G.zo_removeCallLater, handle)
        return
    end

    if type(handle) == "string" then
        local eventManager = rawget(_G, "EVENT_MANAGER")
        if eventManager and type(eventManager.UnregisterForUpdate) == "function" then
            eventManager:UnregisterForUpdate(handle)
        end
    end
end

local EVENT_TIMED_ACTIVITIES_UPDATED_ID = rawget(_G, "EVENT_TIMED_ACTIVITIES_UPDATED")
local EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED_ID = rawget(_G, "EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED")
local EVENT_TIMED_ACTIVITY_SYSTEM_STATUS_UPDATED_ID = rawget(_G, "EVENT_TIMED_ACTIVITY_SYSTEM_STATUS_UPDATED")

local function getAddon()
    return rawget(_G, addonName)
end

local function runSafe(fn)
    if type(fn) ~= "function" then
        return
    end

    local addon = getAddon()
    if type(addon) == "table" then
        local safeCall = rawget(addon, "SafeCall")
        if type(safeCall) == "function" then
            safeCall(fn)
            return
        end
    end

    pcall(fn)
end

local function getFrameTime()
    local getter = rawget(_G, "GetFrameTimeMilliseconds")
    if type(getter) ~= "function" then
        getter = rawget(_G, "GetGameTimeMilliseconds")
    end

    if type(getter) == "function" then
        local ok, value = pcall(getter)
        if ok and type(value) == "number" then
            return value
        end
    end

    return 0
end

local function ensureEndeavorInitialized()
    runSafe(function()
        local addon = getAddon()
        if type(addon) ~= "table" then
            return
        end

        local sv = rawget(addon, "sv")
        if type(sv) ~= "table" then
            return
        end

        local stateModule = rawget(addon, "EndeavorState")
        if type(stateModule) == "table" then
            if type(stateModule._sv) ~= "table" and type(stateModule.Init) == "function" then
                stateModule:Init(sv)
            end

            if not shimStateInitialized and type(stateModule._sv) == "table" then
                shimStateInitialized = true
                safeDebug("[EndeavorTracker.SHIM] init state")
            end
        end

        local modelModule = rawget(addon, "EndeavorModel")
        if type(modelModule) == "table" then
            if type(modelModule.state) ~= "table" and type(modelModule.Init) == "function" then
                local stateInstance = rawget(addon, "EndeavorState")
                if type(stateInstance) == "table" then
                    modelModule:Init(stateInstance)
                end
            end

            if not shimModelInitialized and type(modelModule.state) == "table" then
                shimModelInitialized = true
                safeDebug("[EndeavorTracker.SHIM] init model")
            end
        end
    end)
end

local function shimRefreshEndeavors()
    runSafe(function()
        ensureEndeavorInitialized()

        local addon = getAddon()
        if type(addon) ~= "table" then
            return
        end

        local model = rawget(addon, "EndeavorModel")
        local countsDaily = 0
        local countsWeekly = 0
        local countsSeals = 0
        if type(model) == "table" then
            local refresh = model.RefreshFromGame or model.Refresh
            if type(refresh) == "function" then
                refresh(model)
                safeDebug("[EndeavorTracker.SHIM] model refreshed")

                local getCounts = model.GetCountsForDebug
                if type(getCounts) == "function" then
                    local ok, counts = pcall(getCounts, model)
                    if ok and type(counts) == "table" then
                        countsDaily = tonumber(counts.dailyTotal) or countsDaily
                        countsWeekly = tonumber(counts.weeklyTotal) or countsWeekly
                        countsSeals = tonumber(counts.seals) or countsSeals
                    end
                end
            end
        end

        local controller = rawget(addon, "EndeavorTrackerController")
        if type(controller) == "table" then
            local markDirty = controller.MarkDirty or controller.RequestRefresh
            if type(markDirty) == "function" then
                markDirty(controller)
            end
        end

        safeDebug("[EndeavorTracker.SHIM] counts: daily=%d weekly=%d seals=%d", countsDaily, countsWeekly, countsSeals)

        local runtime = rawget(addon, "TrackerRuntime")
        if type(runtime) == "table" then
            local queueDirty = runtime.QueueDirty or runtime.MarkDirty or runtime.RequestRefresh
            if type(queueDirty) == "function" then
                queueDirty(runtime, "endeavor")
            end
        end

        safeDebug("[EndeavorTracker.SHIM] refresh → model+dirty+queue")
    end)
end

local function clearTempEventsTimer()
    if tempEvents.timerHandle ~= nil then
        RemoveScheduled(tempEvents.timerHandle)
        tempEvents.timerHandle = nil
    end
    tempEvents.pending = false
end

local function cancelProgressFallbackTimer()
    if progressFallback.timerHandle == nil then
        return
    end

    RemoveScheduled(progressFallback.timerHandle)
    progressFallback.timerHandle = nil
end

local function queueTempEventRefresh()
    local now = getFrameTime()
    local lastQueued = tempEvents.lastQueuedAt or 0
    local elapsed = now - lastQueued
    if elapsed < 0 then
        elapsed = 0
    end

    if elapsed >= tempEvents.debounceMs then
        tempEvents.lastQueuedAt = now
        shimRefreshEndeavors()
        return
    end

    if tempEvents.pending then
        return
    end

    tempEvents.pending = true

    local delay = tempEvents.debounceMs - elapsed
    if delay < 0 then
        delay = 0
    end

    tempEvents.timerHandle = ScheduleLater(delay, function()
        tempEvents.timerHandle = nil
        tempEvents.pending = false
        tempEvents.lastQueuedAt = getFrameTime()
        shimRefreshEndeavors()
    end)

    if tempEvents.timerHandle == nil then
        tempEvents.pending = false
        tempEvents.lastQueuedAt = now
        shimRefreshEndeavors()
        return
    end

    safeDebug("[EndeavorTracker.TempEvents] refresh queued (debounced)")
end

local function queueTempEventRefreshSafe()
    runSafe(function()
        if type(queueTempEventRefresh) == "function" then
            queueTempEventRefresh()
            return
        end

        shimRefreshEndeavors()
    end)
end

function EndeavorTracker:TempEvents_QueueRefresh()
    queueTempEventRefreshSafe()
end

local function hasRecentDebouncedRefresh()
    local lastQueued = tempEvents.lastQueuedAt or 0
    if lastQueued <= 0 then
        return false
    end

    local now = getFrameTime()
    local elapsed = now - lastQueued
    if elapsed < 0 then
        elapsed = 0
    end

    return elapsed < tempEvents.debounceMs or tempEvents.pending
end

function EndeavorTracker:InitPoller_Start()
    if state.isDisposed or self._initPollerActive then
        return
    end

    self._initPollerActive = true
    self._initPollerTries = 0
    self._initPollerMaxTries = tonumber(self._initPollerMaxTries) or 10
    self._initPollerInterval = tonumber(self._initPollerInterval) or 1000

    local function GetActivitiesCount()
        local getter = rawget(_G, "GetNumTimedActivities")
        local ok, value = CallIfFunction(getter)
        if ok and type(value) == "number" then
            return value
        end

        return 0
    end

    local function FireDebouncedRefresh()
        if hasRecentDebouncedRefresh() then
            return
        end

        if type(self.TempEvents_QueueRefresh) == "function" then
            self:TempEvents_QueueRefresh()
            return
        end

        CallIfFunction(Nvk3UT and Nvk3UT.EndeavorModel and Nvk3UT.EndeavorModel.RefreshFromGame, Nvk3UT.EndeavorModel)
        CallIfFunction(Nvk3UT and Nvk3UT.EndeavorTrackerController and Nvk3UT.EndeavorTrackerController.MarkDirty, Nvk3UT.EndeavorTrackerController)
        CallIfFunction(Nvk3UT and Nvk3UT.TrackerRuntime and Nvk3UT.TrackerRuntime.QueueDirty, Nvk3UT.TrackerRuntime, "endeavor")
    end

    local function N3UT_Endeavor_InitPoller_Tick()
        self._initPollerTimer = nil

        if state.isDisposed or not self._initPollerActive then
            return
        end

        self._initPollerTries = (self._initPollerTries or 0) + 1

        local count = GetActivitiesCount()
        if count > 0 then
            safeDebug("[EndeavorTracker.SHIM] init-poller success: count=%d", count)
            FireDebouncedRefresh()
            self._initPollerActive = false
            return
        end

        if self._initPollerTries >= self._initPollerMaxTries then
            self._initPollerActive = false
            safeDebug("[EndeavorTracker.SHIM] init-poller gave up (count=0)")
            return
        end

        if state.isDisposed or not self._initPollerActive then
            return
        end

        self._initPollerTimer = ScheduleLater(self._initPollerInterval, N3UT_Endeavor_InitPoller_Tick)
    end

    self._initPollerTimer = ScheduleLater(self._initPollerInterval, N3UT_Endeavor_InitPoller_Tick)
    if self._initPollerTimer ~= nil then
        safeDebug("[EndeavorTracker.SHIM] init-poller scheduled")
        return
    end

    self._initPollerActive = false
end

function EndeavorTracker:InitPoller_Stop()
    RemoveScheduled(self._initPollerTimer)
    self._initPollerTimer = nil
    self._initPollerActive = false
    self._initPollerTries = 0
end

local function scheduleProgressFallback()
    if progressFallback.timerHandle ~= nil then
        return
    end

    runSafe(function()
        local delay = progressFallback.delayMs or 0
        progressFallback.timerHandle = ScheduleLater(delay, function()
            progressFallback.timerHandle = nil
            if state.isDisposed then
                return
            end

            local now = getFrameTime()
            local last = progressFallback.lastProgressAtMs or 0
            local elapsed = now - last
            if elapsed < 0 then
                elapsed = 0
            end

            if elapsed >= (progressFallback.delayMs or 0) then
                queueTempEventRefreshSafe()
            end
        end)

        if progressFallback.timerHandle ~= nil then
            safeDebug("[EndeavorTracker.TempEvents] fallback scheduled (no progress yet)")
        else
            queueTempEventRefreshSafe()
        end
    end)
end

local function onTimedActivitiesUpdated()
    scheduleProgressFallback()
end

local function onTimedActivitySystemStatusUpdated()
    scheduleProgressFallback()
end

local function onTimedActivityProgressUpdated()
    progressFallback.lastProgressAtMs = getFrameTime()
    safeDebug("[EndeavorTracker.TempEvents] progress → queue (debounced)")
    queueTempEventRefreshSafe()
end

local function cancelInitKickTimer(silent)
    if initKick.timerHandle == nil then
        return
    end

    RemoveScheduled(initKick.timerHandle)
    initKick.timerHandle = nil

    if not silent then
        safeDebug("[EndeavorTracker.SHIM] init-kick canceled")
    end
end

local function scheduleInitKick()
    if initKick.done then
        return
    end

    if state.isDisposed then
        return
    end

    if initKick.timerHandle ~= nil then
        return
    end

    runSafe(function()
        safeDebug("[EndeavorTracker.SHIM] init-kick scheduled")

        initKick.timerHandle = ScheduleLater(initKick.delayMs, function()
            initKick.timerHandle = nil
            if state.isDisposed then
                initKick.done = true
                return
            end

            initKick.done = true
            if not hasRecentDebouncedRefresh() then
                queueTempEventRefreshSafe()
            end
        end)

        if initKick.timerHandle == nil then
            initKick.done = true
            if not hasRecentDebouncedRefresh() then
                queueTempEventRefreshSafe()
            end
        end
    end)
end

local function tempEventsRegister()
    if tempEvents.registered then
        return
    end

    runSafe(function()
        local eventManager = rawget(_G, "EVENT_MANAGER")
        local eventManagerType = type(eventManager)
        if eventManagerType ~= "table" and eventManagerType ~= "userdata" then
            return
        end

        local registerMethod = eventManager.RegisterForEvent
        if type(registerMethod) ~= "function" then
            return
        end

        local registeredCount = 0

        if EVENT_TIMED_ACTIVITIES_UPDATED_ID then
            registerMethod(eventManager, TEMP_EVENT_NAMESPACE, EVENT_TIMED_ACTIVITIES_UPDATED_ID, onTimedActivitiesUpdated)
            registeredCount = registeredCount + 1
        end

        if EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED_ID then
            registerMethod(eventManager, TEMP_EVENT_NAMESPACE, EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED_ID, onTimedActivityProgressUpdated)
            registeredCount = registeredCount + 1
        end

        if EVENT_TIMED_ACTIVITY_SYSTEM_STATUS_UPDATED_ID then
            registerMethod(eventManager, TEMP_EVENT_NAMESPACE, EVENT_TIMED_ACTIVITY_SYSTEM_STATUS_UPDATED_ID, onTimedActivitySystemStatusUpdated)
            registeredCount = registeredCount + 1
        end

        if registeredCount > 0 then
            tempEvents.registered = true
            safeDebug("[EndeavorTracker.TempEvents] register")
        end
    end)
end

local function warnCentralEventsIfNeeded()
    if centralEventsWarningShown then
        return
    end

    runSafe(function()
        if centralEventsWarningShown then
            return
        end

        local addon = getAddon()
        if type(addon) ~= "table" then
            return
        end

        if not addon.debug then
            return
        end

        local eventsHub = rawget(addon, "Events")
        if type(eventsHub) ~= "table" then
            return
        end

        local hasHandlers = rawget(eventsHub, "HasEndeavorHandlers")
        local active = false

        if type(hasHandlers) == "function" then
            local ok, result = pcall(hasHandlers, eventsHub)
            active = ok and result == true
        elseif type(hasHandlers) == "boolean" then
            active = hasHandlers
        end

        if active then
            centralEventsWarningShown = true
            safeDebug("[EndeavorTracker.TempEvents] central events detected → temp events should be disabled after SWITCH")
        end
    end)
end

local function unregisterTempEventsInternal(options)
    local opts = options or {}
    local silentKick = opts.silentInitKick == true

    cancelInitKickTimer(silentKick)
    initKick.done = true

    cancelProgressFallbackTimer()
    progressFallback.lastProgressAtMs = nil

    EndeavorTracker:InitPoller_Stop()

    clearTempEventsTimer()
    tempEvents.pending = false
    tempEvents.lastQueuedAt = 0

    if not tempEvents.registered then
        return
    end

    runSafe(function()
        local eventManager = rawget(_G, "EVENT_MANAGER")
        local eventManagerType = type(eventManager)
        if eventManagerType ~= "table" and eventManagerType ~= "userdata" then
            tempEvents.registered = false
            safeDebug("[EndeavorTracker.TempEvents] unregister")
            return
        end

        local unregisterMethod = eventManager.UnregisterForEvent
        if type(unregisterMethod) == "function" then
            if EVENT_TIMED_ACTIVITIES_UPDATED_ID then
                unregisterMethod(eventManager, TEMP_EVENT_NAMESPACE, EVENT_TIMED_ACTIVITIES_UPDATED_ID)
            end
            if EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED_ID then
                unregisterMethod(eventManager, TEMP_EVENT_NAMESPACE, EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED_ID)
            end
            if EVENT_TIMED_ACTIVITY_SYSTEM_STATUS_UPDATED_ID then
                unregisterMethod(eventManager, TEMP_EVENT_NAMESPACE, EVENT_TIMED_ACTIVITY_SYSTEM_STATUS_UPDATED_ID)
            end
        end

        tempEvents.registered = false
        safeDebug("[EndeavorTracker.TempEvents] unregister")
    end)
end

function EndeavorTracker:TempEvents_UnregisterAll(options)
    unregisterTempEventsInternal(options)
end

--[[ EBOOT_TEMP_EVENTS_END: Endeavor ]]

local function safeDebug(fmt, ...)
    local root = rawget(_G, addonName)
    if type(root) ~= "table" then
        return
    end

    local diagnostics = root.Diagnostics
    if diagnostics and type(diagnostics.DebugIfEnabled) == "function" then
        diagnostics:DebugIfEnabled("EndeavorTracker", fmt, ...)
        return
    end

    local debugMethod = root.Debug
    if type(debugMethod) == "function" then
        if fmt == nil then
            debugMethod(root, ...)
        else
            debugMethod(root, fmt, ...)
        end
        return
    end

    if fmt == nil then
        return
    end

    local message = string.format(tostring(fmt), ...)
    local prefix = string.format("[%s]", MODULE_TAG)
    if d then
        d(prefix, message)
    elseif print then
        print(prefix, message)
    end
end

local function getRowsModule()
    local root = rawget(_G, addonName)
    if type(root) ~= "table" then
        return nil
    end

    local rows = rawget(root, "EndeavorTrackerRows")
    if type(rows) ~= "table" then
        return nil
    end

    return rows
end

local function getLayoutModule()
    local root = rawget(_G, addonName)
    if type(root) ~= "table" then
        return nil
    end

    local layout = rawget(root, "EndeavorTrackerLayout")
    if type(layout) ~= "table" then
        return nil
    end

    return layout
end

local function coerceHeight(value)
    if type(value) == "number" then
        if value ~= value then -- NaN guard
            return 0
        end
        return value
    end

    return 0
end

function EndeavorTracker.Init(sectionContainer)
    state.container = sectionContainer
    state.currentHeight = 0
    state.isInitialized = true
    state.isDisposed = false

    ensureEndeavorInitialized()

    initKick.done = false
    if initKick.timerHandle ~= nil then
        cancelInitKickTimer(true)
    end

    cancelProgressFallbackTimer()
    progressFallback.lastProgressAtMs = nil

    local rows = getRowsModule()
    if rows and type(rows.Init) == "function" then
        pcall(rows.Init)
    end

    local layout = getLayoutModule()
    if layout and type(layout.Init) == "function" then
        pcall(layout.Init)
    end

    local container = state.container
    if container and container.SetHeight then
        container:SetHeight(0)
    end

    if not EBOOT_TEMP_EVENTS_ENABLED then
        EndeavorTracker:TempEvents_UnregisterAll({ silentInitKick = true })
        return
    end

    tempEventsRegister()
    warnCentralEventsIfNeeded()

    local disableViaSwitch = false

    runSafe(function()
        local addon = getAddon()
        if type(addon) ~= "table" then
            return
        end

        local flags = rawget(addon, "Flags")
        if type(flags) ~= "table" then
            return
        end

        if flags.EEVENTS_SWITCH_ENDEAVOR == true then
            disableViaSwitch = true
        end
    end)

    if disableViaSwitch then
        EndeavorTracker:TempEvents_UnregisterAll({ silentInitKick = true })
        return
    end

    scheduleInitKick()

    if EBOOT_TEMP_EVENTS_ENABLED and not state.isDisposed then
        EndeavorTracker:InitPoller_Start()
    end

    local containerName
    if container and container.GetName then
        local ok, name = pcall(container.GetName, container)
        if ok then
            containerName = name
        end
    end

    safeDebug("EndeavorTracker.Init: container=%s", containerName or "nil")
end

function EndeavorTracker.Refresh(viewModel)
    if not state.isInitialized then
        return
    end

    local dailyCount = 0
    local weeklyCount = 0
    if type(viewModel) == "table" then
        local daily = viewModel.daily
        if type(daily) == "table" and type(daily.items) == "table" then
            dailyCount = #daily.items
        end

        local weekly = viewModel.weekly
        if type(weekly) == "table" and type(weekly.items) == "table" then
            weeklyCount = #weekly.items
        end
    end

    safeDebug("[EndeavorTracker.UI] Refresh called: dailyItems=%d weeklyItems=%d", dailyCount, weeklyCount)

    local rows = getRowsModule()
    local items = {}
    if type(viewModel) == "table" and type(viewModel.items) == "table" then
        items = viewModel.items
    end

    local builtHeight = 0
    local container = state.container
    if rows and type(rows.Build) == "function" then
        local ok, height = pcall(rows.Build, container, items)
        if ok then
            builtHeight = coerceHeight(height)
        end
    elseif container and type(container.SetHeight) == "function" then
        container:SetHeight(0)
    end

    local layoutHeight = builtHeight
    local layout = getLayoutModule()
    if layout and type(layout.Apply) == "function" then
        local ok, measured = pcall(layout.Apply, container)
        if ok then
            layoutHeight = coerceHeight(measured)
        end
    end

    state.currentHeight = coerceHeight(layoutHeight)

    if container and container.SetHeight then
        container:SetHeight(state.currentHeight)
    end

    safeDebug("EndeavorTracker.Refresh: rows=%d height=%d", type(items) == "table" and #items or 0, state.currentHeight)
end

function EndeavorTracker.GetHeight()
    return coerceHeight(state.currentHeight)
end

function EndeavorTracker.Dispose()
    state.isDisposed = true
    EndeavorTracker:TempEvents_UnregisterAll({ silentInitKick = false })
    EndeavorTracker:InitPoller_Stop()
    state.isInitialized = false
    state.currentHeight = 0
    state.container = nil
end

Nvk3UT.EndeavorTracker = EndeavorTracker

return EndeavorTracker
