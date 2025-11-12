local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Utils = Nvk3UT and Nvk3UT.Utils

local EndeavorTracker = {}
EndeavorTracker.__index = EndeavorTracker

local MODULE_TAG = addonName .. ".EndeavorTracker"

local function cloneTable(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, element in pairs(value) do
        if type(element) == "table" then
            copy[key] = cloneTable(element)
        else
            copy[key] = element
        end
    end

    return copy
end

local DEFAULT_SETTINGS = {
    enabled = true,
    showCounts = true,
    completedHandling = "hide",
}

local DEFAULT_THEME = {
    colors = {
        categoryTitle = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
        entryName = { r = 1, g = 1, b = 0, a = 1 },
        objective = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
        active = { r = 1, g = 1, b = 1, a = 1 },
        completed = { r = 0.7, g = 0.7, b = 0.7, a = 1 },
    },
    font = {
        family = "$(BOLD_FONT)",
        size = 16,
        outline = "soft-shadow-thick",
    },
}

local DEFAULT_ENTRY_FONT_STRING = string.format(
    "%s|%d|%s",
    DEFAULT_THEME.font.family,
    DEFAULT_THEME.font.size,
    DEFAULT_THEME.font.outline
)

local DEFAULT_CATEGORY_FONT_STRING = string.format(
    "%s|%d|%s",
    DEFAULT_THEME.font.family,
    DEFAULT_THEME.font.size + 4,
    DEFAULT_THEME.font.outline
)

local DEFAULT_OBJECTIVE_FONT_STRING = string.format(
    "%s|%d|%s",
    DEFAULT_THEME.font.family,
    math.max(10, DEFAULT_THEME.font.size - 2),
    DEFAULT_THEME.font.outline
)

local FONT_SIZE_MIN = 10
local FONT_SIZE_MAX = 48

local state = {
    container = nil,
    currentHeight = 0,
    isInitialized = false,
    isDisposed = false,
    ui = nil,
    settings = cloneTable(DEFAULT_SETTINGS),
    theme = {
        colors = cloneTable(DEFAULT_THEME.colors),
        fonts = {
            category = DEFAULT_CATEGORY_FONT_STRING,
            entry = DEFAULT_ENTRY_FONT_STRING,
            objective = DEFAULT_OBJECTIVE_FONT_STRING,
        },
    },
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

local safeDebug

local INIT_POLLER_UPDATE_NAME = "Nvk3UT_Endeavor_InitPoller"

local CATEGORY_ROW_HEIGHT = 26
local SECTION_ROW_HEIGHT = 24
local CATEGORY_CHEVRON_SIZE = 20
local CATEGORY_LABEL_OFFSET_X = 4
local SECTION_LABEL_OFFSET_X = 0

local CHEVRON_TEXTURES = {
    expanded = "EsoUI/Art/Buttons/tree_open_up.dds",
    collapsed = "EsoUI/Art/Buttons/tree_closed_up.dds",
}

local CATEGORY_COLOR_ROLE_EXPANDED = "activeTitle"
local CATEGORY_COLOR_ROLE_COLLAPSED = "categoryTitle"
local ENTRY_COLOR_ROLE_DEFAULT = "entryTitle"
local ENTRY_COLOR_ROLE_EXPANDED = "activeTitle"

local COLOR_ROLE_MAP = {
    categoryTitle = "categoryTitle",
    entryTitle = "entryName",
    objectiveText = "objective",
    activeTitle = "active",
    completed = "completed",
}

local function sanitizeColorComponent(component, fallback)
    local numeric = tonumber(component)
    if numeric == nil or numeric ~= numeric then
        numeric = fallback
    end

    if numeric < 0 then
        numeric = 0
    elseif numeric > 1 then
        numeric = 1
    end

    return numeric
end

local function sanitizeFontSize(value, fallback)
    local numeric = tonumber(value)
    if numeric == nil or numeric ~= numeric then
        numeric = fallback or DEFAULT_THEME.font.size
    end

    numeric = math.floor(numeric + 0.5)
    if numeric < FONT_SIZE_MIN then
        numeric = FONT_SIZE_MIN
    elseif numeric > FONT_SIZE_MAX then
        numeric = FONT_SIZE_MAX
    end

    return numeric
end

local function normalizeColor(source, defaults)
    local base = defaults or DEFAULT_THEME.colors.categoryTitle
    local tableValue = type(source) == "table" and source or {}
    return {
        r = sanitizeColorComponent(tableValue.r, base.r),
        g = sanitizeColorComponent(tableValue.g, base.g),
        b = sanitizeColorComponent(tableValue.b, base.b),
        a = sanitizeColorComponent(tableValue.a, base.a),
    }
end

local function buildFontString(family, size, outline)
    local resolvedFamily = family or DEFAULT_THEME.font.family
    local resolvedOutline = outline or DEFAULT_THEME.font.outline
    local resolvedSize = sanitizeFontSize(size, DEFAULT_THEME.font.size)
    return string.format("%s|%d|%s", resolvedFamily, resolvedSize, resolvedOutline)
end

local function computeFonts(fontOptions)
    local options = type(fontOptions) == "table" and fontOptions or {}
    local family = options.Family or DEFAULT_THEME.font.family
    local outline = options.Outline or DEFAULT_THEME.font.outline
    local baseSize = sanitizeFontSize(options.Size, DEFAULT_THEME.font.size)
    local categorySize = sanitizeFontSize(baseSize + 4, DEFAULT_THEME.font.size + 4)
    local objectiveSize = sanitizeFontSize(baseSize - 2, DEFAULT_THEME.font.size - 2)

    return {
        category = buildFontString(family, categorySize, outline),
        entry = buildFontString(family, baseSize, outline),
        objective = buildFontString(family, objectiveSize, outline),
    }
end

local function sanitizeCompletedHandling(value)
    if value == "recolor" then
        return "recolor"
    end
    return "hide"
end

local function FormatParensCount(a, b)
    local aNum = tonumber(a) or 0
    if aNum < 0 then
        aNum = 0
    end

    local bNum = tonumber(b) or 1
    if bNum < 1 then
        bNum = 1
    end

    if aNum > bNum then
        aNum = bNum
    end

    return string.format("(%d/%d)", math.floor(aNum + 0.5), math.floor(bNum + 0.5))
end

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

    local cbLabel = tostring(cb or "cb")
    cbLabel = cbLabel:gsub("[^%w_]", "_")
    local id = "Nvk3UT_Endeavor_Once_" .. cbLabel .. "_" .. tostring(getFrameTime())
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

local function getSavedVars()
    local addon = getAddon()
    if type(addon) ~= "table" then
        return nil
    end

    local sv = rawget(addon, "sv")
    if type(sv) ~= "table" then
        return nil
    end

    return sv
end

local function getSavedEndeavorOptions()
    local sv = getSavedVars()
    if type(sv) ~= "table" then
        return nil
    end

    local options = sv.Endeavor
    if type(options) ~= "table" then
        return nil
    end

    return options
end

local function isGlobalDebugEnabled()
    local diagnostics = Nvk3UT_Diagnostics
    if diagnostics and type(diagnostics.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(diagnostics.IsDebugEnabled, diagnostics)
        if ok then
            return enabled == true
        end
    end

    local addon = getAddon()
    if type(addon) == "table" and type(addon.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(addon.IsDebugEnabled, addon)
        if ok then
            return enabled == true
        end
    end

    return false
end

local function applyLabelFont(label, font)
    if label and label.SetFont and font and font ~= "" then
        label:SetFont(font)
    end
end

local function applyLabelColor(label, role)
    if not label or not label.SetColor then
        return
    end

    local key = COLOR_ROLE_MAP[role] or role
    local colors = state.theme and state.theme.colors or {}
    local color = colors[key]
    if type(color) ~= "table" then
        color = DEFAULT_THEME.colors[key] or { r = 1, g = 1, b = 1, a = 1 }
    end

    local r = color.r or 1
    local g = color.g or 1
    local b = color.b or 1
    local a = color.a or 1
    label:SetColor(r, g, b, a)
end

local function getFontForRole(role)
    local fonts = state.theme and state.theme.fonts or {}
    if role == "category" then
        return fonts.category or DEFAULT_CATEGORY_FONT_STRING
    elseif role == "objective" then
        return fonts.objective or DEFAULT_OBJECTIVE_FONT_STRING
    end
    return fonts.entry or DEFAULT_ENTRY_FONT_STRING
end

local function getSettings()
    if type(state.settings) ~= "table" then
        state.settings = cloneTable(DEFAULT_SETTINGS)
    end
    return state.settings
end

local function getTheme()
    if type(state.theme) ~= "table" then
        state.theme = {
            colors = cloneTable(DEFAULT_THEME.colors),
            fonts = {
                category = DEFAULT_CATEGORY_FONT_STRING,
                entry = DEFAULT_ENTRY_FONT_STRING,
                objective = DEFAULT_OBJECTIVE_FONT_STRING,
            },
        }
    end
    if type(state.theme.colors) ~= "table" then
        state.theme.colors = cloneTable(DEFAULT_THEME.colors)
    end
    if type(state.theme.fonts) ~= "table" then
        state.theme.fonts = {
            category = DEFAULT_CATEGORY_FONT_STRING,
            entry = DEFAULT_ENTRY_FONT_STRING,
            objective = DEFAULT_OBJECTIVE_FONT_STRING,
        }
    end
    return state.theme
end

local function updateVisibility()
    local settings = getSettings()
    local enabled = settings.enabled ~= false
    local container = state.container

    if container and container.SetHidden then
        container:SetHidden(not enabled)
    end

    if not enabled then
        state.currentHeight = 0
        if container and container.SetHeight then
            container:SetHeight(0)
        end
    end
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

local function getEndeavorState()
    local addon = getAddon()
    if type(addon) ~= "table" then
        return nil
    end

    local stateModule = rawget(addon, "EndeavorState")
    if type(stateModule) ~= "table" then
        return nil
    end

    return stateModule
end

function EndeavorTracker.ApplySettings(options)
    local source = type(options) == "table" and options or {}
    local settings = getSettings()

    local enabledValue = source.Enabled
    if enabledValue == nil then
        enabledValue = source.enabled
    end
    settings.enabled = enabledValue ~= false

    local showCountsValue = source.ShowCountsInHeaders
    if showCountsValue == nil then
        showCountsValue = source.showCounts
    end
    settings.showCounts = showCountsValue ~= false

    local handlingValue = source.CompletedHandling
    if handlingValue == nil then
        handlingValue = source.completedHandling
    end
    settings.completedHandling = sanitizeCompletedHandling(handlingValue)

    updateVisibility()
end

function EndeavorTracker.ApplyTheme(options)
    local source = type(options) == "table" and options or {}
    local theme = getTheme()
    local colorsSource = type(source.Colors) == "table" and source.Colors or source.colors or {}

    theme.colors.categoryTitle = normalizeColor(colorsSource.CategoryTitle or colorsSource.categoryTitle, DEFAULT_THEME.colors.categoryTitle)
    theme.colors.entryName = normalizeColor(colorsSource.EntryName or colorsSource.entryName, DEFAULT_THEME.colors.entryName)
    theme.colors.objective = normalizeColor(colorsSource.Objective or colorsSource.objective, DEFAULT_THEME.colors.objective)
    theme.colors.active = normalizeColor(colorsSource.Active or colorsSource.active, DEFAULT_THEME.colors.active)
    theme.colors.completed = normalizeColor(colorsSource.Completed or colorsSource.completed, DEFAULT_THEME.colors.completed)

    local fontSource = source.Font or source.font
    theme.fonts = computeFonts(fontSource)
end

function EndeavorTracker.GetOptions()
    return cloneTable(getSettings())
end

function EndeavorTracker.GetTheme()
    return cloneTable(getTheme())
end

local function queueTrackerDirty()
    runSafe(function()
        local addon = getAddon()
        if type(addon) ~= "table" then
            return
        end

        local runtime = rawget(addon, "TrackerRuntime")
        if type(runtime) ~= "table" then
            return
        end

        local queueDirty = runtime.QueueDirty or runtime.MarkDirty or runtime.RequestRefresh
        if type(queueDirty) == "function" then
            queueDirty(runtime, "endeavor")
        end
    end)
end

local function toggleRootExpanded()
    local stateModule = getEndeavorState()
    if type(stateModule) ~= "table" then
        return
    end

    local expanded = false
    local ok, value = CallIfFunction(stateModule.IsExpanded, stateModule)
    if ok and value == true then
        expanded = true
    end

    local okSet = CallIfFunction(stateModule.SetExpanded, stateModule, not expanded)
    if okSet then
        queueTrackerDirty()
    end
end

local function toggleCategoryExpanded(key)
    if key == nil then
        return
    end

    local stateModule = getEndeavorState()
    if type(stateModule) ~= "table" then
        return
    end

    local expanded = false
    local ok, value = CallIfFunction(stateModule.IsCategoryExpanded, stateModule, key)
    if ok and value == true then
        expanded = true
    end

    local okSet = CallIfFunction(stateModule.SetCategoryExpanded, stateModule, key, not expanded)
    if okSet then
        queueTrackerDirty()
    end
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

        if not isGlobalDebugEnabled() then
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

    stopInitPoller(EndeavorTracker)

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

safeDebug = function(fmt, ...)
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

local function N3UT_Endeavor_InitPoller_Tick()
    local tracker = Nvk3UT and Nvk3UT.EndeavorTrackerInstance
    if not tracker or tracker._disposed or not tracker._initPollerActive then
        if EVENT_MANAGER and type(EVENT_MANAGER.UnregisterForUpdate) == "function" then
            EVENT_MANAGER:UnregisterForUpdate(INIT_POLLER_UPDATE_NAME)
        end
        if tracker and Nvk3UT and Nvk3UT.EndeavorTrackerInstance == tracker then
            Nvk3UT.EndeavorTrackerInstance = nil
        end
        return
    end

    if isGlobalDebugEnabled() then
        safeDebug("[EndeavorTracker.SHIM] poller tick")
    end

    tracker._initPollerTries = (tonumber(tracker._initPollerTries) or 0) + 1

    local count = 0
    if type(GetNumTimedActivities) == "function" then
        local value = GetNumTimedActivities()
        if type(value) == "number" then
            count = value
        end
    end

    if count > 0 then
        if isGlobalDebugEnabled() then
            safeDebug("[EndeavorTracker.SHIM] init-poller success: count=%d", count)
        end

        if type(tracker.TempEvents_QueueRefresh) == "function" then
            tracker:TempEvents_QueueRefresh()
        else
            CallIfFunction(Nvk3UT and Nvk3UT.EndeavorModel and Nvk3UT.EndeavorModel.RefreshFromGame, Nvk3UT.EndeavorModel)
            CallIfFunction(Nvk3UT and Nvk3UT.EndeavorTrackerController and Nvk3UT.EndeavorTrackerController.MarkDirty, Nvk3UT.EndeavorTrackerController)
            CallIfFunction(Nvk3UT and Nvk3UT.TrackerRuntime and Nvk3UT.TrackerRuntime.QueueDirty, Nvk3UT.TrackerRuntime, "endeavor")
        end

        tracker._initPollerActive = false
        if EVENT_MANAGER and type(EVENT_MANAGER.UnregisterForUpdate) == "function" then
            EVENT_MANAGER:UnregisterForUpdate(INIT_POLLER_UPDATE_NAME)
        end
        if Nvk3UT and Nvk3UT.EndeavorTrackerInstance == tracker then
            Nvk3UT.EndeavorTrackerInstance = nil
        end
        return
    end

    local maxTries = tonumber(tracker._initPollerMaxTries) or 10
    if tracker._initPollerTries >= maxTries then
        tracker._initPollerActive = false
        if isGlobalDebugEnabled() then
            safeDebug("[EndeavorTracker.SHIM] init-poller gave up (count=0)")
        end
        if EVENT_MANAGER and type(EVENT_MANAGER.UnregisterForUpdate) == "function" then
            EVENT_MANAGER:UnregisterForUpdate(INIT_POLLER_UPDATE_NAME)
        end
        if Nvk3UT and Nvk3UT.EndeavorTrackerInstance == tracker then
            Nvk3UT.EndeavorTrackerInstance = nil
        end
        return
    end
end

local function startInitPoller(tracker)
    if not tracker or tracker._disposed or tracker._initPollerActive then
        return
    end

    tracker._initPollerActive = true
    tracker._initPollerTries = 0
    tracker._initPollerMaxTries = tonumber(tracker._initPollerMaxTries) or 10
    tracker._initPollerInterval = tonumber(tracker._initPollerInterval) or 1000

    if Nvk3UT then
        Nvk3UT.EndeavorTrackerInstance = tracker
    end

    if EVENT_MANAGER and type(EVENT_MANAGER.RegisterForUpdate) == "function" then
        if type(EVENT_MANAGER.UnregisterForUpdate) == "function" then
            EVENT_MANAGER:UnregisterForUpdate(INIT_POLLER_UPDATE_NAME)
        end
        EVENT_MANAGER:RegisterForUpdate(INIT_POLLER_UPDATE_NAME, tracker._initPollerInterval, N3UT_Endeavor_InitPoller_Tick)
        if isGlobalDebugEnabled() then
            safeDebug("[EndeavorTracker.SHIM] init-poller scheduled")
        end
    else
        tracker._initPollerActive = false
        if Nvk3UT and Nvk3UT.EndeavorTrackerInstance == tracker then
            Nvk3UT.EndeavorTrackerInstance = nil
        end
    end
end

local function stopInitPoller(tracker)
    if not tracker then
        return
    end

    tracker._initPollerActive = false
    tracker._initPollerTries = 0

    if EVENT_MANAGER and type(EVENT_MANAGER.UnregisterForUpdate) == "function" then
        EVENT_MANAGER:UnregisterForUpdate(INIT_POLLER_UPDATE_NAME)
    end

    if Nvk3UT and Nvk3UT.EndeavorTrackerInstance == tracker then
        Nvk3UT.EndeavorTrackerInstance = nil
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

local function ensureUi(container)
    if container == nil then
        return state.ui
    end

    local wm = WINDOW_MANAGER
    if wm == nil then
        return state.ui
    end

    local ui = state.ui
    if type(ui) ~= "table" then
        ui = {}
        state.ui = ui
    end

    local containerName
    if type(container.GetName) == "function" then
        local ok, name = pcall(container.GetName, container)
        if ok and type(name) == "string" then
            containerName = name
        end
    end

    local baseName = (containerName or "Nvk3UT_Endeavor") .. "_"
    ui.baseName = baseName

    local category = ui.category
    if type(category) ~= "table" then
        local controlName = baseName .. "Category"
        local control = GetControl(controlName)
        if not control then
            control = wm:CreateControl(controlName, container, CT_CONTROL)
        else
            control:SetParent(container)
        end
        control:SetResizeToFitDescendents(false)
        control:SetHeight(CATEGORY_ROW_HEIGHT)
        control:SetMouseEnabled(true)
        control:SetHidden(false)
        control:SetHandler("OnMouseUp", function(_, button, upInside)
            if button == MOUSE_BUTTON_INDEX_LEFT and upInside then
                toggleRootExpanded()
            end
        end)

        local chevronName = controlName .. "Chevron"
        local chevron = GetControl(chevronName)
        if not chevron then
            chevron = wm:CreateControl(chevronName, control, CT_TEXTURE)
        end
        chevron:SetParent(control)
        chevron:SetMouseEnabled(false)
        chevron:SetHidden(false)
        chevron:SetDimensions(CATEGORY_CHEVRON_SIZE, CATEGORY_CHEVRON_SIZE)
        chevron:ClearAnchors()
        local offsetY = math.floor((CATEGORY_ROW_HEIGHT - CATEGORY_CHEVRON_SIZE) * 0.5)
        chevron:SetAnchor(TOPLEFT, control, TOPLEFT, 0, offsetY)
        chevron:SetTexture(CHEVRON_TEXTURES.collapsed)

        local labelName = controlName .. "Label"
        local label = GetControl(labelName)
        if not label then
            label = wm:CreateControl(labelName, control, CT_LABEL)
        end
        label:SetParent(control)
        label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
        label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
        label:ClearAnchors()
        label:SetAnchor(TOPLEFT, chevron, TOPRIGHT, CATEGORY_LABEL_OFFSET_X, 0)
        label:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, 0, 0)
        applyLabelFont(label, getFontForRole("category"))

        ui.category = {
            control = control,
            label = label,
            chevron = chevron,
        }
    else
        local control = category.control
        if control then
            control:SetParent(container)
            control:SetHeight(CATEGORY_ROW_HEIGHT)
        end
        local label = category.label
        applyLabelFont(label, getFontForRole("category"))
    end

    local daily = ui.daily
    if type(daily) ~= "table" then
        local controlName = baseName .. "Daily"
        local control = GetControl(controlName)
        if not control then
            control = wm:CreateControl(controlName, container, CT_CONTROL)
        else
            control:SetParent(container)
        end
        control:SetResizeToFitDescendents(false)
        control:SetHeight(SECTION_ROW_HEIGHT)
        control:SetMouseEnabled(true)
        control:SetHidden(false)
        control:SetHandler("OnMouseUp", function(_, button, upInside)
            if button == MOUSE_BUTTON_INDEX_LEFT and upInside then
                toggleCategoryExpanded("daily")
            end
        end)

        local labelName = controlName .. "Label"
        local label = GetControl(labelName)
        if not label then
            label = wm:CreateControl(labelName, control, CT_LABEL)
        end
        label:SetParent(control)
        label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
        label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
        label:ClearAnchors()
        label:SetAnchor(TOPLEFT, control, TOPLEFT, SECTION_LABEL_OFFSET_X, 0)
        label:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, 0, 0)
        applyLabelFont(label, getFontForRole("entry"))

        ui.daily = {
            control = control,
            label = label,
        }
    else
        local control = daily.control
        if control then
            control:SetParent(container)
            control:SetHeight(SECTION_ROW_HEIGHT)
        end
        local label = daily.label
        applyLabelFont(label, getFontForRole("entry"))
    end

    local weekly = ui.weekly
    if type(weekly) ~= "table" then
        local controlName = baseName .. "Weekly"
        local control = GetControl(controlName)
        if not control then
            control = wm:CreateControl(controlName, container, CT_CONTROL)
        else
            control:SetParent(container)
        end
        control:SetResizeToFitDescendents(false)
        control:SetHeight(SECTION_ROW_HEIGHT)
        control:SetMouseEnabled(true)
        control:SetHidden(false)
        control:SetHandler("OnMouseUp", function(_, button, upInside)
            if button == MOUSE_BUTTON_INDEX_LEFT and upInside then
                toggleCategoryExpanded("weekly")
            end
        end)

        local labelName = controlName .. "Label"
        local label = GetControl(labelName)
        if not label then
            label = wm:CreateControl(labelName, control, CT_LABEL)
        end
        label:SetParent(control)
        label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
        label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
        label:ClearAnchors()
        label:SetAnchor(TOPLEFT, control, TOPLEFT, SECTION_LABEL_OFFSET_X, 0)
        label:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, 0, 0)
        applyLabelFont(label, getFontForRole("entry"))

        ui.weekly = {
            control = control,
            label = label,
        }
    else
        local control = weekly.control
        if control then
            control:SetParent(container)
            control:SetHeight(SECTION_ROW_HEIGHT)
        end
        local label = weekly.label
        applyLabelFont(label, getFontForRole("entry"))
    end

    local dailyObjectives = ui.dailyObjectives
    if type(dailyObjectives) ~= "table" then
        local controlName = baseName .. "DailyObjectives"
        local control = GetControl(controlName)
        if not control then
            control = wm:CreateControl(controlName, container, CT_CONTROL)
        else
            control:SetParent(container)
        end
        control:SetResizeToFitDescendents(false)
        control:SetMouseEnabled(false)
        control:SetHidden(true)
        control:SetHeight(0)

        ui.dailyObjectives = {
            control = control,
        }
    else
        local control = dailyObjectives.control
        if control then
            control:SetParent(container)
        end
    end

    local weeklyObjectives = ui.weeklyObjectives
    if type(weeklyObjectives) ~= "table" then
        local controlName = baseName .. "WeeklyObjectives"
        local control = GetControl(controlName)
        if not control then
            control = wm:CreateControl(controlName, container, CT_CONTROL)
        else
            control:SetParent(container)
        end
        control:SetResizeToFitDescendents(false)
        control:SetMouseEnabled(false)
        control:SetHidden(true)
        control:SetHeight(0)

        ui.weeklyObjectives = {
            control = control,
        }
    else
        local control = weeklyObjectives.control
        if control then
            control:SetParent(container)
        end
    end

    return ui
end

function EndeavorTracker.Init(sectionContainer, options)
    state.container = sectionContainer
    state.currentHeight = 0
    state.isInitialized = true
    state.isDisposed = false
    EndeavorTracker._disposed = false
    state.ui = nil

    local savedOptions = options or getSavedEndeavorOptions() or {}
    EndeavorTracker.ApplySettings(savedOptions)
    EndeavorTracker.ApplyTheme(savedOptions)

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
        startInitPoller(EndeavorTracker)
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

    if EndeavorTracker._building then
        safeDebug("[EndeavorTracker.UI] Refresh skipped due to active guard")
        return
    end

    EndeavorTracker._building = true
    local function release()
        EndeavorTracker._building = false
    end

    local container = state.container
    if container == nil then
        release()
        return
    end

    local settings = getSettings()
    local vm = type(viewModel) == "table" and viewModel or {}
    local categoryVm = type(vm.category) == "table" and vm.category or {}
    local dailyVm = type(vm.daily) == "table" and vm.daily or {}
    local weeklyVm = type(vm.weekly) == "table" and vm.weekly or {}

    local dailyObjectivesList = type(dailyVm.objectives) == "table" and dailyVm.objectives or {}
    local weeklyObjectivesList = type(weeklyVm.objectives) == "table" and weeklyVm.objectives or {}

    safeDebug("[EndeavorTracker.UI] Refresh: daily=%d weekly=%d", #dailyObjectivesList, #weeklyObjectivesList)

    local ui = ensureUi(container)
    if type(ui) ~= "table" then
        release()
        return
    end

    if settings.enabled == false then
        updateVisibility()

        local rows = getRowsModule()
        local dailyObjectivesControl = ui.dailyObjectives and ui.dailyObjectives.control
        local weeklyObjectivesControl = ui.weeklyObjectives and ui.weeklyObjectives.control

        if rows and type(rows.ClearObjectives) == "function" then
            if dailyObjectivesControl then
                rows.ClearObjectives(dailyObjectivesControl)
            end
            if weeklyObjectivesControl then
                rows.ClearObjectives(weeklyObjectivesControl)
            end
        end

        if dailyObjectivesControl and dailyObjectivesControl.SetHidden then
            dailyObjectivesControl:SetHidden(true)
        end
        if weeklyObjectivesControl and weeklyObjectivesControl.SetHidden then
            weeklyObjectivesControl:SetHidden(true)
        end
        if ui.category and ui.category.control and ui.category.control.SetHidden then
            ui.category.control:SetHidden(true)
        end
        if ui.daily and ui.daily.control and ui.daily.control.SetHidden then
            ui.daily.control:SetHidden(true)
        end
        if ui.weekly and ui.weekly.control and ui.weekly.control.SetHidden then
            ui.weekly.control:SetHidden(true)
        end

        release()
        return
    end

    updateVisibility()

    local categoryControl = ui.category and ui.category.control
    local categoryLabel = ui.category and ui.category.label
    local categoryChevron = ui.category and ui.category.chevron

    local function resolveTitle(value, fallback)
        if value == nil or value == "" then
            return fallback
        end
        return tostring(value)
    end

    local categoryTitle = resolveTitle(categoryVm.title, "Bestrebungen")
    local categoryRemaining = tonumber(categoryVm.remaining) or 0
    categoryRemaining = math.max(0, math.floor(categoryRemaining + 0.5))
    if categoryLabel and categoryLabel.SetText then
        local showCounts = settings.showCounts ~= false
        local formatHeader = Utils and Utils.FormatCategoryHeaderText
        if type(formatHeader) == "function" then
            categoryLabel:SetText(formatHeader(categoryTitle, categoryRemaining, showCounts))
        elseif showCounts then
            categoryLabel:SetText(string.format("%s (%d)", categoryTitle, categoryRemaining))
        else
            categoryLabel:SetText(categoryTitle)
        end
    end

    local categoryExpanded = categoryVm.expanded == true
    if categoryChevron and categoryChevron.SetTexture then
        local texturePath = categoryExpanded and CHEVRON_TEXTURES.expanded or CHEVRON_TEXTURES.collapsed
        categoryChevron:SetTexture(texturePath)
    end

    if categoryLabel then
        local role = categoryExpanded and CATEGORY_COLOR_ROLE_EXPANDED or CATEGORY_COLOR_ROLE_COLLAPSED
        applyLabelColor(categoryLabel, role)
    end

    local dailyControl = ui.daily and ui.daily.control
    local dailyLabel = ui.daily and ui.daily.label
    if dailyLabel and dailyLabel.SetText then
        local dailyTitle = resolveTitle(dailyVm.title or "Tägliche Bestrebungen", "Tägliche Bestrebungen")
        if settings.showCounts ~= false then
            dailyLabel:SetText(string.format(
                "%s %s",
                dailyTitle,
                FormatParensCount(dailyVm.displayCompleted or dailyVm.completed, dailyVm.displayLimit or dailyVm.total)
            ))
        else
            dailyLabel:SetText(dailyTitle)
        end
    end

    local weeklyControl = ui.weekly and ui.weekly.control
    local weeklyLabel = ui.weekly and ui.weekly.label
    if weeklyLabel and weeklyLabel.SetText then
        local weeklyTitle = resolveTitle(weeklyVm.title or "Wöchentliche Bestrebungen", "Wöchentliche Bestrebungen")
        if settings.showCounts ~= false then
            weeklyLabel:SetText(string.format(
                "%s %s",
                weeklyTitle,
                FormatParensCount(weeklyVm.displayCompleted or weeklyVm.completed, weeklyVm.displayLimit or weeklyVm.total)
            ))
        else
            weeklyLabel:SetText(weeklyTitle)
        end
    end

    local dailyExpanded = categoryExpanded and dailyVm.expanded == true
    local weeklyExpanded = categoryExpanded and weeklyVm.expanded == true

    if dailyLabel then
        local role = dailyExpanded and ENTRY_COLOR_ROLE_EXPANDED or ENTRY_COLOR_ROLE_DEFAULT
        applyLabelColor(dailyLabel, role)
    end

    if weeklyLabel then
        local role = weeklyExpanded and ENTRY_COLOR_ROLE_EXPANDED or ENTRY_COLOR_ROLE_DEFAULT
        applyLabelColor(weeklyLabel, role)
    end

    if categoryControl and categoryControl.SetHidden then
        categoryControl:SetHidden(false)
    end

    if dailyControl and dailyControl.SetHidden then
        dailyControl:SetHidden(not categoryExpanded)
    end
    if weeklyControl and weeklyControl.SetHidden then
        weeklyControl:SetHidden(not categoryExpanded)
    end

    local rows = getRowsModule()
    local dailyObjectivesControl = ui.dailyObjectives and ui.dailyObjectives.control
    local weeklyObjectivesControl = ui.weeklyObjectives and ui.weeklyObjectives.control

    if rows then
        if dailyObjectivesControl then
            if dailyExpanded and type(rows.BuildObjectives) == "function" then
                rows.BuildObjectives(dailyObjectivesControl, dailyObjectivesList)
                dailyObjectivesControl:SetHidden(false)
            else
                if type(rows.ClearObjectives) == "function" then
                    rows.ClearObjectives(dailyObjectivesControl)
                elseif type(rows.BuildObjectives) == "function" then
                    rows.BuildObjectives(dailyObjectivesControl, {})
                elseif dailyObjectivesControl.SetHeight then
                    dailyObjectivesControl:SetHeight(0)
                end
                dailyObjectivesControl:SetHidden(true)
            end
        end

        if weeklyObjectivesControl then
            if weeklyExpanded and type(rows.BuildObjectives) == "function" then
                rows.BuildObjectives(weeklyObjectivesControl, weeklyObjectivesList)
                weeklyObjectivesControl:SetHidden(false)
            else
                if type(rows.ClearObjectives) == "function" then
                    rows.ClearObjectives(weeklyObjectivesControl)
                elseif type(rows.BuildObjectives) == "function" then
                    rows.BuildObjectives(weeklyObjectivesControl, {})
                elseif weeklyObjectivesControl.SetHeight then
                    weeklyObjectivesControl:SetHeight(0)
                end
                weeklyObjectivesControl:SetHidden(true)
            end
        end
    else
        if dailyObjectivesControl then
            dailyObjectivesControl:SetHidden(true)
            if dailyObjectivesControl.SetHeight then
                dailyObjectivesControl:SetHeight(0)
            end
        end
        if weeklyObjectivesControl then
            weeklyObjectivesControl:SetHidden(true)
            if weeklyObjectivesControl.SetHeight then
                weeklyObjectivesControl:SetHeight(0)
            end
        end
    end

    local layout = getLayoutModule()
    local layoutContext = {
        category = { control = categoryControl },
        categoryExpanded = categoryExpanded,
        daily = { control = dailyControl },
        dailyExpanded = dailyVm.expanded == true,
        dailyObjectives = { control = dailyObjectivesControl, expanded = dailyExpanded },
        weekly = { control = weeklyControl },
        weeklyExpanded = weeklyVm.expanded == true,
        weeklyObjectives = { control = weeklyObjectivesControl, expanded = weeklyExpanded },
    }

    local measuredHeight = 0
    if layout and type(layout.Apply) == "function" then
        local ok, height = pcall(layout.Apply, container, layoutContext)
        if ok then
            measuredHeight = coerceHeight(height)
        end
    else
        local fallbackHeight = 0
        if categoryControl and categoryControl.GetHeight then
            fallbackHeight = fallbackHeight + coerceHeight(categoryControl:GetHeight())
        else
            fallbackHeight = fallbackHeight + CATEGORY_ROW_HEIGHT
        end

        if categoryExpanded then
            if dailyControl and dailyControl.GetHeight then
                fallbackHeight = fallbackHeight + coerceHeight(dailyControl:GetHeight())
            else
                fallbackHeight = fallbackHeight + SECTION_ROW_HEIGHT
            end

            if dailyExpanded and dailyObjectivesControl and dailyObjectivesControl.GetHeight then
                fallbackHeight = fallbackHeight + coerceHeight(dailyObjectivesControl:GetHeight())
            end

            if weeklyControl and weeklyControl.GetHeight then
                fallbackHeight = fallbackHeight + coerceHeight(weeklyControl:GetHeight())
            else
                fallbackHeight = fallbackHeight + SECTION_ROW_HEIGHT
            end

            if weeklyExpanded and weeklyObjectivesControl and weeklyObjectivesControl.GetHeight then
                fallbackHeight = fallbackHeight + coerceHeight(weeklyObjectivesControl:GetHeight())
            end
        end

        measuredHeight = fallbackHeight
    end

    state.currentHeight = coerceHeight(measuredHeight)
    if container and container.SetHeight then
        container:SetHeight(state.currentHeight)
    end

    safeDebug(
        "[Endeavor.UI] cat=%s remaining=%d daily=%d/%d weekly=%d/%d",
        tostring(categoryExpanded),
        categoryRemaining,
        tonumber(dailyVm.displayCompleted or dailyVm.completed) or 0,
        tonumber(dailyVm.displayLimit or dailyVm.total) or 0,
        tonumber(weeklyVm.displayCompleted or weeklyVm.completed) or 0,
        tonumber(weeklyVm.displayLimit or weeklyVm.total) or 0
    )

    safeDebug(
        "[Endeavor.UI] formatted: daily=%s weekly=%s",
        FormatParensCount(dailyVm.displayCompleted or dailyVm.completed, dailyVm.displayLimit or dailyVm.total),
        FormatParensCount(weeklyVm.displayCompleted or weeklyVm.completed, weeklyVm.displayLimit or weeklyVm.total)
    )

    release()
end

function EndeavorTracker.GetHeight()
    if getSettings().enabled == false then
        return 0
    end

    return coerceHeight(state.currentHeight)
end

function EndeavorTracker.Dispose()
    EndeavorTracker._disposed = true
    state.isDisposed = true
    EndeavorTracker:TempEvents_UnregisterAll({ silentInitKick = false })
    state.isInitialized = false
    state.currentHeight = 0
    state.container = nil
    state.ui = nil
end

Nvk3UT.EndeavorTracker = EndeavorTracker

return EndeavorTracker
