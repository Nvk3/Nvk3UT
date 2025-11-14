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
local INIT_POLLER_ACTIVE_FIELD = "_initPollerActive"
local INIT_POLLER_REMAINING_FIELD = "_initPollerRemaining"
local INIT_POLLER_TIMER_FIELD = "_initPollerTimer"

local INIT_POLLER_MAX_ATTEMPTS = 2
local INIT_POLLER_DELAY_MS = 1200

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
    diagnosticsDebug("[Golden SHIM] init-kick → refresh queued")
end

local function emitProgressRefreshDebug()
    diagnosticsDebug("Golden SHIM: progress refresh completed")
end

local function emitInitPollerTickDebug(attemptIndex, campaignCount)
    diagnosticsDebug("[Golden SHIM] init-poller tick %d → campaigns=%d", attemptIndex or 0, campaignCount or 0)
end

local function shouldDelayPromoRefresh()
    local lockFn = rawget(_G, "IsPromotionalEventSystemLocked")
    if type(lockFn) == "function" then
        local okLocked, lockedValue = pcall(lockFn)
        if okLocked and lockedValue then
            return true
        end
    end

    local countFn = rawget(_G, "GetNumActivePromotionalEventCampaigns")
    if type(countFn) == "function" then
        local okCount, countValue = pcall(countFn)
        if okCount then
            local numeric = tonumber(countValue) or 0
            if numeric <= 0 then
                return true
            end
        end
    end

    return false
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

    local okRefresh, refreshErr = pcall(model.RefreshFromGame, model)
    if not okRefresh then
        safeDebug("performModelRefresh failed: %s", tostring(refreshErr))
        diagnosticsDebug("[Golden] performModelRefresh failed: %s", tostring(refreshErr))
        return
    end

    controller:MarkDirty()
    runtime:QueueDirty("golden")
    controller[NEEDS_FULL_SYNC_FIELD] = false

    emitProgressRefreshDebug()
end

local function resolveGoldenModel()
    local root = Nvk3UT
    if type(root) ~= "table" then
        return nil
    end

    local model = root.GoldenModel
    if type(model) ~= "table" or type(model.RefreshFromGame) ~= "function" then
        return nil
    end

    return model
end

local function resolveRuntime()
    local root = Nvk3UT
    if type(root) ~= "table" then
        return nil
    end

    local runtime = root.TrackerRuntime
    if type(runtime) ~= "table" or type(runtime.QueueDirty) ~= "function" then
        return nil
    end

    return runtime
end

local function fetchCampaignCountFromModel(model)
    if type(model) ~= "table" then
        return 0
    end

    local accessors = {}
    if type(model.GetViewData) == "function" then
        table.insert(accessors, model.GetViewData)
    end
    if type(model.GetViewModel) == "function" then
        table.insert(accessors, model.GetViewModel)
    end

    for _, accessor in ipairs(accessors) do
        local ok, view = pcall(accessor, model)
        if ok and type(view) == "table" then
            local campaigns = view.campaigns
            if type(campaigns) == "table" then
                return #campaigns
            end
        end
    end

    return 0
end

local function performModelRefresh(controller)
    local model = resolveGoldenModel()
    local runtime = resolveRuntime()

    if not model or not runtime then
        return nil, 0
    end

    if type(controller) ~= "table" or type(controller.MarkDirty) ~= "function" then
        return nil, 0
    end

    local okRefresh, refreshErr = pcall(model.RefreshFromGame, model)
    if not okRefresh then
        safeDebug("performModelRefresh failed: %s", tostring(refreshErr))
        diagnosticsDebug("[Golden] performModelRefresh failed: %s", tostring(refreshErr))
        return nil, 0
    end

    controller:MarkDirty()
    runtime:QueueDirty("golden")
    controller[NEEDS_FULL_SYNC_FIELD] = false

    local campaignCount = fetchCampaignCountFromModel(model)

    if campaignCount == 0 then
        local promoApiReady = true
        if type(model) == "table" and type(model.IsPromoApiReady) == "function" then
            local okReady, ready = pcall(model.IsPromoApiReady, model)
            promoApiReady = okReady and ready == true
        end

        local guardedEmpty = false
        if type(model) == "table" and type(model.WasPromoApiGuardedEmpty) == "function" then
            local okGuard, guardFlag = pcall(model.WasPromoApiGuardedEmpty, model)
            guardedEmpty = okGuard and guardFlag == true
        end

        if not promoApiReady and guardedEmpty and type(controller.StartInitPoller) == "function" then
            controller:StartInitPoller()
        end
    end

    return model, campaignCount
end

local function scheduleInitPollerTick(controller)
    if type(controller) ~= "table" then
        return
    end

    local function runTick()
        controller[INIT_POLLER_TIMER_FIELD] = nil

        local remaining = tonumber(controller[INIT_POLLER_REMAINING_FIELD]) or 0
        if remaining <= 0 then
            controller[INIT_POLLER_ACTIVE_FIELD] = false
            controller[INIT_POLLER_REMAINING_FIELD] = 0
            return
        end

        local attemptIndex = (INIT_POLLER_MAX_ATTEMPTS - remaining) + 1

        if shouldDelayPromoRefresh() then
            controller[INIT_POLLER_REMAINING_FIELD] = remaining
            local callLater = rawget(_G, "zo_callLater")
            if type(callLater) == "function" then
                controller[INIT_POLLER_ACTIVE_FIELD] = true
                scheduleInitPollerTick(controller)
            else
                controller[INIT_POLLER_ACTIVE_FIELD] = false
            end
            return
        end

        controller[INIT_POLLER_REMAINING_FIELD] = remaining - 1

        local model, campaignCount = performModelRefresh(controller)
        if not model then
            controller[INIT_POLLER_ACTIVE_FIELD] = false
            controller[INIT_POLLER_REMAINING_FIELD] = 0
            return
        end

        emitInitPollerTickDebug(attemptIndex, campaignCount)

        if campaignCount == 0 and (tonumber(controller[INIT_POLLER_REMAINING_FIELD]) or 0) > 0 then
            scheduleInitPollerTick(controller)
        else
            controller[INIT_POLLER_ACTIVE_FIELD] = false
            controller[INIT_POLLER_REMAINING_FIELD] = 0
        end
    end

    local callLater = rawget(_G, "zo_callLater")
    if type(callLater) ~= "function" then
        runTick()
        return
    end

    local ok, callId = pcall(callLater, runTick, INIT_POLLER_DELAY_MS)
    if ok then
        controller[INIT_POLLER_TIMER_FIELD] = callId
    else
        controller[INIT_POLLER_TIMER_FIELD] = nil
        runTick()
    end
end

local function ensureViewModel()
    if type(state.viewModel) ~= "table" then
        state.viewModel = { campaigns = {} }
    else
        local campaigns = state.viewModel.campaigns
        if type(campaigns) ~= "table" then
            state.viewModel.campaigns = {}
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
        local timerHandle = self[INIT_POLLER_TIMER_FIELD]
        if timerHandle ~= nil then
            local removeCallLater = rawget(_G, "zo_removeCallLater")
            if type(removeCallLater) == "function" then
                pcall(removeCallLater, timerHandle)
            end
        end
        self[INIT_POLLER_ACTIVE_FIELD] = false
        self[INIT_POLLER_REMAINING_FIELD] = 0
        self[INIT_POLLER_TIMER_FIELD] = nil
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
    local root = Nvk3UT
    local model = root and root.GoldenModel
    local resolvedViewModel = nil

    if type(model) == "table" then
        if type(model.GetViewData) == "function" then
            local ok, vm = pcall(model.GetViewData, model)
            if ok and type(vm) == "table" then
                resolvedViewModel = vm
            end
        elseif type(model.GetViewModel) == "function" then
            local ok, vm = pcall(model.GetViewModel, model)
            if ok and type(vm) == "table" then
                resolvedViewModel = vm
            end
        end
    end

    if type(resolvedViewModel) == "table" then
        state.viewModel = resolvedViewModel
    end

    local viewModel = ensureViewModel()
    local campaigns = viewModel.campaigns or {}

    diagnosticsDebug("[GoldenVM] campaigns=%d", #campaigns)
    local inspectCount = math.min(#campaigns, 5)
    for index = 1, inspectCount do
        local campaign = campaigns[index]
        local activityCount = nil
        local completedFlag = nil
        if type(campaign) == "table" then
            if type(campaign.activities) == "table" then
                activityCount = #campaign.activities
            end
            completedFlag = campaign.isCompleted
        end

        diagnosticsDebug(
            "[GoldenVM] campaign[%d] name='%s' activities=%s completed=%s",
            index,
            tostring(campaign and campaign.name),
            tostring(activityCount),
            tostring(completedFlag)
        )
    end

    state.dirty = false

    safeDebug("BuildViewModel done, campaigns=%d", #campaigns)

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

-- [GEVENTS_SWITCH_REMOVE] InitPoller is SHIM-only; remove when lifecycle moves to Events/*
function Controller:StartInitPoller()
    if type(self) ~= "table" then
        return
    end

    if self[INIT_POLLER_ACTIVE_FIELD] then
        return
    end

    local model = resolveGoldenModel()
    local runtime = resolveRuntime()
    if not model or not runtime then
        return
    end

    if type(self.MarkDirty) ~= "function" then
        return
    end

    self[INIT_POLLER_ACTIVE_FIELD] = true
    self[INIT_POLLER_REMAINING_FIELD] = INIT_POLLER_MAX_ATTEMPTS

    scheduleInitPollerTick(self)
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
