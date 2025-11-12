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

local initKick = {
    done = false,
    timerHandle = nil,
    delayMs = 200,
}

local EVENT_TIMED_ACTIVITIES_UPDATED_ID = rawget(_G, "EVENT_TIMED_ACTIVITIES_UPDATED")
local EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED_ID = rawget(_G, "EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED")
local EVENT_TIMED_ACTIVITY_SYSTEM_STATUS_UPDATED_ID = rawget(_G, "EVENT_TIMED_ACTIVITY_SYSTEM_STATUS_UPDATED")

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
        if type(model) == "table" then
            local refresh = model.RefreshFromGame or model.Refresh
            if type(refresh) == "function" then
                refresh(model)
            end
        end

        local controller = rawget(addon, "EndeavorTrackerController")
        if type(controller) == "table" then
            local markDirty = controller.MarkDirty or controller.RequestRefresh
            if type(markDirty) == "function" then
                markDirty(controller)
            end
        end

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
        local cancel = rawget(_G, "CancelCallback")
        if type(cancel) == "function" then
            cancel(tempEvents.timerHandle)
        end
        tempEvents.timerHandle = nil
    end
    tempEvents.pending = false
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

    local callLater = rawget(_G, "zo_callLater")
    if type(callLater) ~= "function" then
        tempEvents.pending = false
        tempEvents.lastQueuedAt = now
        shimRefreshEndeavors()
        return
    end

    local delay = tempEvents.debounceMs - elapsed
    if delay < 0 then
        delay = 0
    end

    tempEvents.timerHandle = callLater(function()
        tempEvents.timerHandle = nil
        tempEvents.pending = false
        tempEvents.lastQueuedAt = getFrameTime()
        shimRefreshEndeavors()
    end, delay)

    safeDebug("[EndeavorTracker.TempEvents] refresh queued (debounced)")
end

local function onTimedActivitiesEvent()
    runSafe(queueTempEventRefresh)
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

local function cancelInitKickTimer(silent)
    if initKick.timerHandle == nil then
        return
    end

    local remove = rawget(_G, "zo_removeCallLater")
    if type(remove) == "function" then
        remove(initKick.timerHandle)
    else
        local cancel = rawget(_G, "CancelCallback")
        if type(cancel) == "function" then
            cancel(initKick.timerHandle)
        end
    end

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

        local callLater = rawget(_G, "zo_callLater")
        if type(callLater) ~= "function" then
            initKick.done = true
            if not hasRecentDebouncedRefresh() then
                onTimedActivitiesEvent()
            end
            return
        end

        initKick.timerHandle = callLater(function()
            initKick.timerHandle = nil
            if state.isDisposed then
                initKick.done = true
                return
            end

            initKick.done = true
            if not hasRecentDebouncedRefresh() then
                onTimedActivitiesEvent()
            end
        end, initKick.delayMs)
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
            registerMethod(eventManager, TEMP_EVENT_NAMESPACE, EVENT_TIMED_ACTIVITIES_UPDATED_ID, onTimedActivitiesEvent)
            registeredCount = registeredCount + 1
        end

        if EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED_ID then
            registerMethod(eventManager, TEMP_EVENT_NAMESPACE, EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED_ID, onTimedActivitiesEvent)
            registeredCount = registeredCount + 1
        end

        if EVENT_TIMED_ACTIVITY_SYSTEM_STATUS_UPDATED_ID then
            registerMethod(eventManager, TEMP_EVENT_NAMESPACE, EVENT_TIMED_ACTIVITY_SYSTEM_STATUS_UPDATED_ID, onTimedActivitiesEvent)
            registeredCount = registeredCount + 1
        end

        if registeredCount > 0 then
            tempEvents.registered = true
            safeDebug("[EndeavorTracker.TempEvents] register")
        end
    end)
end

local function tempEventsUnregister()
    if not tempEvents.registered then
        clearTempEventsTimer()
        return
    end

    runSafe(function()
        clearTempEventsTimer()

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

    tempEventsRegister()

    scheduleInitKick()

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
    cancelInitKickTimer(false)
    initKick.done = true
    tempEventsUnregister()
    state.isInitialized = false
    state.currentHeight = 0
    state.container = nil
end

Nvk3UT.EndeavorTracker = EndeavorTracker

return EndeavorTracker
