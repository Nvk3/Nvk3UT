-- Tracker/Golden/Nvk3UT_GoldenTrackerController.lua
-- Provides a stub controller for the Golden tracker mirroring the Endeavor tracker API.

local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Controller = Nvk3UT.GoldenTrackerController or {}
Nvk3UT.GoldenTrackerController = Controller

local state = {
    dirty = true,
    viewModel = nil,
}

local MODULE_TAG = addonName .. ".GoldenTrackerController"

local function safeDebug(message, ...)
    local debugFn = Nvk3UT and Nvk3UT.Debug
    if type(debugFn) ~= "function" then
        return
    end

    local payload = message
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, message, ...)
        if ok then
            payload = formatted
        end
    end

    pcall(debugFn, string.format("%s: %s", MODULE_TAG, tostring(payload)))
end

local function resolveDiagnostics()
    local root = Nvk3UT
    if type(root) == "table" then
        local diagnostics = root.Diagnostics
        if type(diagnostics) == "table" then
            return diagnostics
        end
    end

    if type(Nvk3UT_Diagnostics) == "table" then
        return Nvk3UT_Diagnostics
    end

    return nil
end

local function isDiagnosticsDebugEnabled()
    local diagnostics = resolveDiagnostics()
    if diagnostics and type(diagnostics.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(diagnostics.IsDebugEnabled, diagnostics)
        if ok and enabled then
            return true
        end
    end

    return false
end

local function emitShimDebug(eventName)
    if not isDiagnosticsDebugEnabled() then
        return
    end

    local diagnostics = resolveDiagnostics()
    if diagnostics and type(diagnostics.Debug) == "function" then
        pcall(diagnostics.Debug, diagnostics, string.format("Golden SHIM: %s → refresh queued", tostring(eventName)))
    end
end

local function processTimedActivityEvent(controller, eventName)
    local root = Nvk3UT
    if type(root) ~= "table" then
        return
    end

    local model = root.GoldenModel
    if type(model) ~= "table" or type(model.RefreshFromGame) ~= "function" then
        return
    end

    local runtime = root.TrackerRuntime
    if type(runtime) ~= "table" or type(runtime.QueueDirty) ~= "function" then
        return
    end

    if type(controller) ~= "table" or type(controller.MarkDirty) ~= "function" then
        return
    end

    model:RefreshFromGame()
    controller:MarkDirty()
    runtime:QueueDirty("golden")

    emitShimDebug(eventName)
end

local function ensureViewModel()
    if type(state.viewModel) ~= "table" then
        state.viewModel = { categories = {} }
    else
        local categories = state.viewModel.categories
        if type(categories) ~= "table" then
            state.viewModel.categories = {}
        end
    end

    return state.viewModel
end

function Controller:Init()
    state.dirty = true
    state.viewModel = nil
    safeDebug("Init")
end

function Controller:MarkDirty()
    state.dirty = true
end

function Controller:IsDirty()
    return state.dirty == true
end

function Controller:ClearDirty()
    state.dirty = false
end

function Controller:BuildViewModel()
    local categories = {
        {
            id = "GOLDEN_DAILY",
            name = "GOLDEN — DAILY",
            entries = {
                {
                    id = "GOLDEN_SAMPLE_ENTRY_1",
                    title = "Example Golden Daily",
                    count = 0,
                    max = 1,
                    objectives = {
                        {
                            id = "obj1",
                            title = "Do a golden thing",
                            progress = 0,
                            max = 1,
                        },
                    },
                },
            },
        },
        {
            id = "GOLDEN_WEEKLY",
            name = "GOLDEN — WEEKLY",
            entries = {},
        },
    }

    state.viewModel = {
        categories = categories,
    }

    local viewModel = ensureViewModel()
    state.dirty = false

    local count = #(viewModel.categories or {})
    safeDebug("BuildViewModel done, cats=%d", count)

    return viewModel
end

function Controller:GetViewModel()
    return ensureViewModel()
end

function Controller:OnTimedActivitiesUpdated(eventCode, ...)
    processTimedActivityEvent(self, "EVENT_TIMED_ACTIVITIES_UPDATED")
end

function Controller:OnTimedActivityProgressUpdated(eventCode, ...)
    processTimedActivityEvent(self, "EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED")
end

function Controller:OnTimedActivitySystemStatusUpdated(eventCode, ...)
    processTimedActivityEvent(self, "EVENT_TIMED_ACTIVITY_SYSTEM_STATUS_UPDATED")
end

return Controller
