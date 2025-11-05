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
Runtime._achievementHard = Runtime._achievementHard == true
Runtime._queuedChannelsForLog = Runtime._queuedChannelsForLog or {}
Runtime._isProcessingFrame = Runtime._isProcessingFrame == true
Runtime._lastProcessFrameMs = Runtime._lastProcessFrameMs or nil
Runtime._geometry = Runtime._geometry or {}
Runtime._deferredProcessFrame = Runtime._deferredProcessFrame == true
Runtime._isInCombat = Runtime._isInCombat == true
Runtime._isInCursorMode = Runtime._isInCursorMode == true
Runtime._scheduled = Runtime._scheduled == true
Runtime._scheduledCallId = Runtime._scheduledCallId or nil
Runtime._initialized = Runtime._initialized == true
Runtime._interactivityDirty = Runtime._interactivityDirty == true
Runtime._pendingStageLog = Runtime._pendingStageLog or {}

local function debug(fmt, ...)
    if Addon and type(Addon.Debug) == "function" then
        Addon.Debug(fmt, ...)
    end
end

local function safeCall(fn, ...)
    if Addon and type(Addon.SafeCall) == "function" then
        return Addon.SafeCall(fn, ...)
    end

    if type(fn) ~= "function" then
        return nil
    end

    local ok, resultTable = pcall(function(...)
        return { fn(...) }
    end, ...)

    if ok and type(resultTable) == "table" then
        return unpack(resultTable)
    end

    return nil
end

local callWithOptionalSelf

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

local function ensureGeometryState()
    local geometry = Runtime._geometry
    if type(geometry) ~= "table" then
        geometry = {}
        Runtime._geometry = geometry
    end

    return geometry
end

local function normalizeLength(value)
    local numeric = tonumber(value)
    if not numeric then
        return 0
    end

    if numeric ~= numeric then
        return 0
    end

    if numeric < 0 then
        numeric = 0
    end

    return numeric
end

local GEOMETRY_TOLERANCE = 0.1
local PENDING_STAGE_LOG_THROTTLE_MS = 2000

local function recordSectionGeometry(sectionId, width, height)
    if type(sectionId) ~= "string" then
        return false
    end

    local geometry = ensureGeometryState()
    local entry = geometry[sectionId]
    if type(entry) ~= "table" then
        entry = {}
        geometry[sectionId] = entry
    end

    width = normalizeLength(width)
    height = normalizeLength(height)

    local previousWidth = entry.width
    local previousHeight = entry.height

    entry.width = width
    entry.height = height

    if previousWidth == nil or previousHeight == nil then
        return true
    end

    if math.abs(previousWidth - width) > GEOMETRY_TOLERANCE then
        return true
    end

    if math.abs(previousHeight - height) > GEOMETRY_TOLERANCE then
        return true
    end

    return false
end

local function getDiagnostics()
    if type(Addon) == "table" and type(Addon.Diagnostics) == "table" then
        return Addon.Diagnostics
    end

    if type(Nvk3UT_Diagnostics) == "table" then
        return Nvk3UT_Diagnostics
    end

    return nil
end

local function ResolveTrackerHeight(tracker, trackerKey)
    if type(tracker) ~= "table" then
        return nil
    end

    local diagnostics = getDiagnostics()

    local function warnBadHandle(label)
        if diagnostics and type(diagnostics.WarnOnce) == "function" then
            diagnostics:WarnOnce(
                string.format("bad-fn-%s-%s", tostring(trackerKey), tostring(label)),
                string.format(
                    "Runtime tried to call a non-function on tracker %s (%s)",
                    tostring(trackerKey),
                    tostring(label)
                )
            )
        end
    end

    local getHeightFn = tracker.GetHeight
    if getHeightFn ~= nil and type(getHeightFn) ~= "function" then
        warnBadHandle("GetHeight")
    elseif type(getHeightFn) == "function" then
        local ok, height = pcall(getHeightFn, tracker)
        if ok and type(height) == "number" then
            return height
        end
    end

    local getSizeFn = tracker.getSize
    if getSizeFn ~= nil and type(getSizeFn) ~= "function" then
        warnBadHandle("getSize")
    elseif type(getSizeFn) == "function" then
        local ok, height = pcall(getSizeFn, tracker)
        if ok and type(height) == "number" then
            return height
        end
    end

    return nil
end

local function ensurePendingStageLogState()
    local state = Runtime._pendingStageLog
    if type(state) ~= "table" then
        state = {}
        Runtime._pendingStageLog = state
    end

    state.count = tonumber(state.count) or 0

    return state
end

local function flushPendingStageLog(frameStamp)
    local state = ensurePendingStageLogState()
    if not state.dirty or state.count <= 0 then
        return
    end

    local diagnostics = getDiagnostics()
    local emitted = false

    if diagnostics and type(diagnostics.DebugRateLimited) == "function" then
        local count = tonumber(state.count) or 0
        local lastId = tonumber(state.lastId) or 0
        local lastStageId = tonumber(state.lastStageId) or 0
        local lastIndex = tonumber(state.lastIndex) or 0

        emitted = diagnostics:DebugRateLimited("achv-stage", PENDING_STAGE_LOG_THROTTLE_MS, function()
            return string.format(
                "Achievement stage pending: collapsed %d updates (last id=%d stage=%d index=%d)",
                count,
                lastId,
                lastStageId,
                lastIndex
            )
        end)
    else
        local now = frameStamp
        if now == nil then
            now = getFrameTimeMs()
        end
        if now == nil and type(GetGameTimeMilliseconds) == "function" then
            now = GetGameTimeMilliseconds()
        end

        if now ~= nil and state.lastLogMs ~= nil then
            if (now - state.lastLogMs) < PENDING_STAGE_LOG_THROTTLE_MS then
                return
            end
        end

        if type(now) == "number" then
            state.lastLogMs = now
        end

        debug(
            "Achievement stage pending: collapsed %d updates (last id=%d stage=%d index=%d)",
            tonumber(state.count) or 0,
            tonumber(state.lastId) or 0,
            tonumber(state.lastStageId) or 0,
            tonumber(state.lastIndex) or 0
        )

        emitted = true
    end

    if emitted then
        state.count = 0
        state.lastId = nil
        state.lastStageId = nil
        state.lastIndex = nil
        state.dirty = false
    end
end

local function updateTrackerGeometry(sectionId)
    local trackerKey
    if sectionId == "achievement" then
        trackerKey = "AchievementTracker"
    else
        trackerKey = "QuestTracker"
    end

    local tracker = rawget(Addon, trackerKey)
    if type(tracker) ~= "table" then
        return false
    end

    local height = ResolveTrackerHeight(tracker, trackerKey)
    if height == nil then
        local diagnostics = getDiagnostics()
        if diagnostics and type(diagnostics.WarnOnce) == "function" then
            diagnostics:WarnOnce(
                "height-missing-" .. tostring(trackerKey),
                string.format("Tracker height missing; skipping geometry this frame (%s)", tostring(trackerKey))
            )
        end
        return false
    end

    local width = nil

    local getSize = tracker.GetContentSize
    if type(getSize) == "function" then
        local sizeInvoked, sizeWidth, sizeHeight = callWithOptionalSelf(tracker, getSize, false)
        if sizeInvoked then
            if sizeWidth ~= nil then
                width = sizeWidth
            end
            if height == nil and sizeHeight ~= nil and type(sizeHeight) == "number" then
                height = sizeHeight
            end
        end
    end

    if width == nil then
        local geometry = ensureGeometryState()
        local previous = geometry[sectionId]
        if type(previous) == "table" then
            width = previous.width
        end
    end

    return recordSectionGeometry(sectionId, width, height)
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

function callWithOptionalSelf(targetTable, fn, preferPlainCall, ...)
    if type(fn) ~= "function" then
        return false
    end

    local args = { ... }
    local invoked = false
    local results = nil

    local function tryInvoke(withSelf)
        if withSelf and targetTable == nil then
            return false
        end

        if Addon and type(Addon.SafeCall) == "function" then
            if withSelf then
                results = { Addon.SafeCall(fn, targetTable, unpack(args)) }
            else
                results = { Addon.SafeCall(fn, unpack(args)) }
            end
            invoked = true
            return true
        end

        local ok, callResults = pcall(function()
            if withSelf then
                return { fn(targetTable, unpack(args)) }
            end

            return { fn(unpack(args)) }
        end)

        if ok and type(callResults) == "table" then
            invoked = true
            results = callResults
            return true
        end

        return false
    end

    if preferPlainCall then
        if not tryInvoke(false) then
            tryInvoke(true)
        end
    else
        if not tryInvoke(true) then
            tryInvoke(false)
        end
    end

    if results == nil then
        return invoked
    end

    return invoked, unpack(results)
end

local function buildQuestViewModel()
    local controller = rawget(Addon, "QuestTrackerController")
    if type(controller) ~= "table" then
        return nil, false
    end

    local build = controller.BuildViewModel or controller.Build
    if type(build) ~= "function" then
        return nil, false
    end

    local invoked, viewModel = callWithOptionalSelf(controller, build, false)
    if not invoked then
        return nil, false
    end

    return viewModel, true
end

local function refreshQuestTracker(viewModel)
    local tracker = rawget(Addon, "QuestTracker")
    if type(tracker) ~= "table" then
        return false
    end

    local refreshWithModel = tracker.RefreshWithViewModel or tracker.RefreshFromViewModel
    if type(refreshWithModel) == "function" then
        local invoked = callWithOptionalSelf(tracker, refreshWithModel, false, viewModel)
        if invoked then
            return true
        end
    end

    local requestRefresh = tracker.RequestRefresh
    if type(requestRefresh) == "function" then
        callWithOptionalSelf(tracker, requestRefresh, false)
        return true
    end

    local refresh = tracker.Refresh
    if type(refresh) == "function" then
        local invoked = callWithOptionalSelf(tracker, refresh, false, viewModel)
        return invoked
    end

    return false
end

local function buildAchievementViewModel()
    local controller = rawget(Addon, "AchievementTrackerController")
    if type(controller) ~= "table" then
        return nil, false
    end

    local build = controller.BuildViewModel or controller.Build
    if type(build) ~= "function" then
        return nil, false
    end

    local invoked, viewModel = callWithOptionalSelf(controller, build, false)
    if not invoked then
        return nil, false
    end

    return viewModel, true
end

local function refreshAchievementTracker(viewModel, opts)
    local tracker = rawget(Addon, "AchievementTracker")
    if type(tracker) ~= "table" then
        return false
    end

    local refreshWithModel = tracker.RefreshWithViewModel or tracker.RefreshFromViewModel
    if type(refreshWithModel) == "function" then
        local invoked = callWithOptionalSelf(tracker, refreshWithModel, false, viewModel, opts)
        if invoked then
            return true
        end
    end

    local requestRefresh = tracker.RequestRefresh
    if type(requestRefresh) == "function" then
        callWithOptionalSelf(tracker, requestRefresh, false)
        return true
    end

    local refresh = tracker.Refresh
    if type(refresh) == "function" then
        local invoked = callWithOptionalSelf(tracker, refresh, false, viewModel, opts)
        return invoked
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
    if hasDirtyFlags() or hasInteractivityWork() then
        return true
    end

    return Runtime._deferredProcessFrame == true
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
    self._deferredProcessFrame = false
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

function Runtime:QueueAchievementHard()
    local dirty = ensureDirtyState()
    local queuedLog = ensureQueuedLogTable()

    if not dirty.achievement then
        dirty.achievement = true
    end

    self._achievementHard = true
    queuedLog.achievement = true

    if hasPendingWork() then
        scheduleProcessing()
    end
end

function Runtime:RecordAchievementStagePending(id, stageId, index)
    if Addon and type(Addon.IsDebugEnabled) == "function" then
        if not Addon:IsDebugEnabled() then
            return
        end
    end

    local state = ensurePendingStageLogState()
    state.count = state.count + 1
    state.lastId = tonumber(id) or id
    state.lastStageId = tonumber(stageId) or stageId
    state.lastIndex = tonumber(index) or index
    state.dirty = true

    scheduleProcessing()
end

function Runtime:ProcessFrame(nowMs)
    if self._isProcessingFrame then
        self._deferredProcessFrame = true
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
        local questDirty = dirty.quest == true
        local achievementDirty = dirty.achievement == true
        local layoutDirty = dirty.layout == true

        dirty.quest = false
        dirty.achievement = false
        dirty.layout = false

        local interactivityDirty = self._interactivityDirty == true
        self._interactivityDirty = false

        local questViewModel, questVmBuilt = nil, false
        if questDirty then
            questViewModel, questVmBuilt = buildQuestViewModel()
            if questVmBuilt then
                debug("Runtime: built quest view model")
            end
        end

        local achievementViewModel, achievementVmBuilt = nil, false
        if achievementDirty then
            achievementViewModel, achievementVmBuilt = buildAchievementViewModel()
            if achievementVmBuilt then
                debug("Runtime: built achievement view model")
            end
        end

        local questGeometryChanged = false
        if questDirty or questVmBuilt then
            local refreshedQuest = refreshQuestTracker(questViewModel)
            if refreshedQuest then
                questGeometryChanged = updateTrackerGeometry("quest")
                if questGeometryChanged then
                    debug("Runtime: quest tracker refreshed (geometry changed)")
                end
            end
        end

        local achievementHard = self._achievementHard == true
        self._achievementHard = false

        local achievementGeometryChanged = false
        if achievementDirty or achievementVmBuilt then
            local refreshOpts = nil
            if achievementHard then
                refreshOpts = { hard = true }
            end
            local refreshedAchievement = refreshAchievementTracker(achievementViewModel, refreshOpts)
            if refreshedAchievement then
                achievementGeometryChanged = updateTrackerGeometry("achievement")
                if achievementGeometryChanged then
                    debug("Runtime: achievement tracker refreshed (geometry changed)")
                end
            end
        end

        local journal = rawget(Addon, "Journal")
        if type(journal) == "table" then
            local flushFavorites = journal.FlushPendingFavoritesRefresh
            if type(flushFavorites) == "function" then
                if Addon and type(Addon.SafeCall) == "function" then
                    Addon.SafeCall(flushFavorites, journal, "runtime")
                else
                    pcall(flushFavorites, journal, "runtime")
                end
            end
        end

        local layoutShouldApply = layoutDirty or questGeometryChanged or achievementGeometryChanged or achievementHard
        if layoutShouldApply then
            if applyTrackerHostLayout() then
                debug("Runtime: applied tracker host layout")
            end
        end

        if interactivityDirty then
            local hostWindow = getHostWindow()
            if hostWindow and type(hostWindow.SetMouseEnabled) == "function" then
                safeCall(hostWindow.SetMouseEnabled, hostWindow, self._isInCursorMode == true)
                debug("Runtime: interactivity updated (cursor=%s)", tostring(self._isInCursorMode == true))
            end
        end

        flushPendingStageLog(frameStamp)

        local queuedLog = ensureQueuedLogTable()
        for key in pairs(queuedLog) do
            queuedLog[key] = nil
        end
    end

    local ok, err = pcall(process)

    self._isProcessingFrame = false

    local rerun = self._deferredProcessFrame == true
    self._deferredProcessFrame = false

    if rerun or hasPendingWork() then
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
