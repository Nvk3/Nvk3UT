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

local INIT_KICK_FLAG_FIELD = "_didInitKick"
local NEEDS_FULL_SYNC_FIELD = "_needsFullSync"
local LAST_PROGRESS_FRAME_FIELD = "_lastProgressFrameId"

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

local function diagnosticsDebug(message, ...)
    if not isDiagnosticsDebugEnabled() then
        return
    end

    local diagnostics = resolveDiagnostics()
    if diagnostics and type(diagnostics.Debug) == "function" then
        local payload = message
        if select("#", ...) > 0 then
            local ok, formatted = pcall(string.format, message, ...)
            if ok then
                payload = formatted
            end
        end

        pcall(diagnostics.Debug, diagnostics, payload)
    end
end

local function emitRequestFullSyncDebug(reason)
    diagnosticsDebug("Golden SHIM: request full sync (%s)", tostring(reason))
end

local function emitInitKickDebug()
    diagnosticsDebug("Golden InitKick → initial refresh queued")
end

local function emitProgressRefreshDebug()
    diagnosticsDebug("Golden SHIM: progress refresh completed")
end

local function shouldSkipProgressThisFrame(controller)
    local frameTimeFn = rawget(_G, "GetFrameTimeMilliseconds")
    if type(frameTimeFn) ~= "function" then
        return false
    end

    local ok, frameTime = pcall(frameTimeFn)
    if not ok or type(frameTime) ~= "number" then
        return false
    end

    local lastFrame = controller[LAST_PROGRESS_FRAME_FIELD]
    controller[LAST_PROGRESS_FRAME_FIELD] = frameTime
    return lastFrame == frameTime
end

local function requestFullSync(controller, reason)
    if type(controller) ~= "table" then
        return
    end

    controller[NEEDS_FULL_SYNC_FIELD] = true
    emitRequestFullSyncDebug(reason)
end

local function doProgressRefresh(controller)
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

    if shouldSkipProgressThisFrame(controller) then
        return
    end

    model:RefreshFromGame()
    controller:MarkDirty()
    runtime:QueueDirty("golden")

    controller[NEEDS_FULL_SYNC_FIELD] = false

    emitProgressRefreshDebug()
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
    if type(self) == "table" then
        self[NEEDS_FULL_SYNC_FIELD] = false
        self[LAST_PROGRESS_FRAME_FIELD] = nil
    end
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

    diagnosticsDebug("[GoldenVM] cats=%d", #(categories or {}))
    local inspectCount = math.min(#categories, 5)
    for index = 1, inspectCount do
        local category = categories[index]
        local entriesCount = nil
        local hideFlag = nil
        if type(category) == "table" then
            local entries = category.entries
            if type(entries) == "table" then
                entriesCount = #entries
            end
            hideFlag = category.hide or category.hidden or category.hideEntire
        end

        diagnosticsDebug("[GoldenVM] cat[%d] name='%s' entries=%s hide=%s", index, tostring(category and category.name), tostring(entriesCount), tostring(hideFlag))
    end

    local viewModel = ensureViewModel()
    state.dirty = false

    local count = #(viewModel.categories or {})
    safeDebug("BuildViewModel done, cats=%d", count)

    return viewModel
end

function Controller:GetViewModel()
    return ensureViewModel()
end

-- [GEVENTS_SWITCH_REMOVE] InitKick is SHIM-only; remove when lifecycle moves to Events/*
function Controller:InitKickOnce()
    if type(self) ~= "table" then
        return
    end

    if self[INIT_KICK_FLAG_FIELD] then
        return
    end

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

    if type(self.MarkDirty) ~= "function" then
        return
    end

    self[INIT_KICK_FLAG_FIELD] = true
    self[NEEDS_FULL_SYNC_FIELD] = false

    model:RefreshFromGame()
    self:MarkDirty()
    runtime:QueueDirty("golden")

    emitInitKickDebug()
end

-- [GEVENTS_SWITCH_REMOVE] Handler is SHIM target for TempEvents; Events/* will call equivalent APIs after SWITCH
function Controller:OnTimedActivitiesUpdated(eventCode, ...)
    if type(self) == "table" and type(self.InitKickOnce) == "function" then
        self:InitKickOnce()
    end
    requestFullSync(self, "activities_updated")
end

-- [GEVENTS_SWITCH_REMOVE] Handler is SHIM target for TempEvents; Events/* will call equivalent APIs after SWITCH
function Controller:OnTimedActivityProgressUpdated(eventCode, ...)
    if type(self) == "table" and type(self.InitKickOnce) == "function" then
        self:InitKickOnce()
    end
    doProgressRefresh(self)
end

-- [GEVENTS_SWITCH_REMOVE] Handler is SHIM target for TempEvents; Events/* will call equivalent APIs after SWITCH
function Controller:OnTimedActivitySystemStatusUpdated(eventCode, ...)
    if type(self) == "table" and type(self.InitKickOnce) == "function" then
        self:InitKickOnce()
    end
    requestFullSync(self, "system_status_updated")
end

return Controller
