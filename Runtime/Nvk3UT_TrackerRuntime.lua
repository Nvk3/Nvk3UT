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
Runtime._dirty.endeavor = Runtime._dirty.endeavor == true
Runtime._dirty.achievement = Runtime._dirty.achievement == true
Runtime._dirty.layout = Runtime._dirty.layout == true
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
Runtime._endeavorVM = Runtime._endeavorVM
Runtime.goldenDirty = true
Runtime.cache = type(Runtime.cache) == "table" and Runtime.cache or {}
if type(Runtime.cache.goldenVM) ~= "table" then
    Runtime.cache.goldenVM = { campaigns = {} }
end

local function debug(fmt, ...)
    if Addon and type(Addon.Debug) == "function" then
        Addon.Debug(fmt, ...)
    end
end

local function warn(fmt, ...)
    if Addon and type(Addon.Warn) == "function" then
        Addon.Warn(fmt, ...)
        return
    end

    debug(fmt, ...)
end

local function debugVisibility(fmt, ...)
    local diagnostics = Addon and Addon.Diagnostics
    if type(diagnostics) ~= "table" then
        diagnostics = Nvk3UT and Nvk3UT.Diagnostics
    end

    if diagnostics and type(diagnostics.DebugIfEnabled) == "function" then
        diagnostics:DebugIfEnabled("TrackerRuntime", fmt, ...)
        return
    end

    debug(fmt, ...)
end

local function resolveDiagnostics()
    local diagnostics = Addon and Addon.Diagnostics
    if type(diagnostics) == "table" then
        return diagnostics
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

local function diagnosticsDebug(fmt, ...)
    if not isDiagnosticsDebugEnabled() then
        return
    end

    local diagnostics = resolveDiagnostics()
    if diagnostics and type(diagnostics.Debug) == "function" then
        local payload = fmt
        if select("#", ...) > 0 then
            local ok, formatted = pcall(string.format, fmt, ...)
            if ok then
                payload = formatted
            end
        end

        pcall(diagnostics.Debug, diagnostics, payload)
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

local DIRTY_CHANNEL_ORDER = { "quest", "endeavor", "achievement", "layout" }

local function ensureDirtyState()
    local dirty = Runtime._dirty
    if type(dirty) ~= "table" then
        dirty = {}
        Runtime._dirty = dirty
    end

    dirty.quest = dirty.quest == true
    dirty.endeavor = dirty.endeavor == true
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

local function tryTrackerMethod(tracker, ...)
    if type(tracker) ~= "table" then
        return nil
    end

    local methodNames = { ... }
    for index = 1, #methodNames do
        local methodName = methodNames[index]
        if methodName then
            local candidate = tracker[methodName]
            if type(candidate) == "function" then
                return candidate, methodName
            end
        end
    end

    return nil, nil
end

local function updateTrackerGeometry(sectionId, trackerKey, tracker)
    local resolvedKey = trackerKey
    if type(resolvedKey) ~= "string" then
        if sectionId == "achievement" then
            resolvedKey = "AchievementTracker"
        elseif sectionId == "endeavor" then
            resolvedKey = "Endeavor"
        else
            resolvedKey = "QuestTracker"
        end
    end

    local resolvedTracker = tracker
    if type(resolvedTracker) ~= "table" then
        resolvedTracker = rawget(Addon, resolvedKey)
        if sectionId == "endeavor" and type(resolvedTracker) ~= "table" then
            resolvedTracker = rawget(Addon, "EndeavorTracker")
        end
    end

    if type(resolvedTracker) ~= "table" then
        return false
    end

    local sizeFn, sizeMode = tryTrackerMethod(resolvedTracker, "GetHeight", "GetSize", "GetContentHeight", "GetContentSize")
    if type(sizeFn) ~= "function" then
        return false
    end

    local ok, valueA, valueB = pcall(sizeFn, resolvedTracker)
    if not ok then
        debugVisibility("Runtime: tracker size query failed (%s)", tostring(resolvedKey or sectionId))
        return false
    end

    local width, height = 0, 0
    if sizeMode == "GetHeight" or sizeMode == "GetContentHeight" then
        height = valueA

        local widthFn = tryTrackerMethod(resolvedTracker, "GetWidth", "GetContentWidth")
        if type(widthFn) == "function" then
            local widthOk, measuredWidth = pcall(widthFn, resolvedTracker)
            if widthOk and measuredWidth ~= nil then
                width = measuredWidth
            end
        end
    else
        width = valueA
        height = valueB

        if height == nil then
            height = valueA
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

local function callWithOptionalSelf(targetTable, fn, preferPlainCall, ...)
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

local function buildEndeavorViewModel()
    local fallback = { items = {}, count = 0 }
    local controller = rawget(Addon, "EndeavorTrackerController")
    if type(controller) ~= "table" then
        return fallback, false
    end

    local build = controller.BuildViewModel or controller.Build
    if type(build) ~= "function" then
        return fallback, false
    end

    local viewModel, invoked = fallback, false
    safeCall(function()
        local called, result = callWithOptionalSelf(controller, build, false)
        if called and result ~= nil then
            viewModel = result
            invoked = true
        end
    end)

    if viewModel == nil then
        viewModel = fallback
    end

    return viewModel, invoked
end

local function refreshEndeavorTracker(viewModel)
    local payload = type(viewModel) == "table" and viewModel or { items = {}, count = 0 }
    local refreshed = false

    safeCall(function()
        local facade = rawget(Addon, "Endeavor")
        if type(facade) == "table" then
            local refresh = facade.Refresh or facade.RefreshWithViewModel or facade.RefreshFromViewModel
            if type(refresh) == "function" then
                local invoked = callWithOptionalSelf(facade, refresh, true, payload)
                if invoked then
                    refreshed = true
                    return
                end
            end
        end

        local tracker = rawget(Addon, "EndeavorTracker")
        if type(tracker) ~= "table" then
            return
        end

        local refresh = tracker.Refresh or tracker.RefreshWithViewModel or tracker.RefreshFromViewModel
        if type(refresh) ~= "function" then
            return
        end

        local invoked = callWithOptionalSelf(tracker, refresh, true, payload)
        if invoked then
            refreshed = true
        end
    end)

    return refreshed
end

local function getEndeavorHeight()
    local facade = rawget(Addon, "Endeavor")
    if type(facade) == "table" then
        local getHeight = facade.GetHeight or facade.GetContentHeight or facade.GetSize
        if type(getHeight) == "function" then
            local invoked, measured = callWithOptionalSelf(facade, getHeight, true)
            if invoked and measured ~= nil then
                return normalizeLength(measured)
            end
        end
    end

    local tracker = rawget(Addon, "EndeavorTracker")
    if type(tracker) == "table" then
        local getHeight = tracker.GetHeight or tracker.GetContentHeight or tracker.GetSize
        if type(getHeight) == "function" then
            local invoked, measured = callWithOptionalSelf(tracker, getHeight, true)
            if invoked and measured ~= nil then
                return normalizeLength(measured)
            end
        end
    end

    return 0
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

local function refreshAchievementTracker(viewModel)
    local tracker = rawget(Addon, "AchievementTracker")
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
    return dirty.quest or dirty.endeavor or dirty.achievement or dirty.layout
end

local function hasInteractivityWork()
    return Runtime._interactivityDirty == true
end

local function hasPendingWork()
    if hasDirtyFlags() or hasInteractivityWork() or Runtime.goldenDirty == true then
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

    if normalized == "golden" then
        if not self.goldenDirty then
            self.goldenDirty = true
            queuedLog.golden = true
            debug("Runtime.QueueDirty: golden")
        else
            queuedLog.golden = true
        end

        if hasPendingWork() then
            scheduleProcessing()
        end

        return
    end

    if not applyAll then
        local isKnown = normalized == "quest" or normalized == "endeavor" or normalized == "achievement" or normalized == "layout"
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
                if key == "endeavor" then
                    debug("Runtime.QueueDirty: endeavor")
                end
            end
        end
    else
        if not dirty[normalized] then
            dirty[normalized] = true
            queuedLog[normalized] = true
            if normalized == "endeavor" then
                debug("Runtime.QueueDirty: endeavor")
            end
        end
    end

    if applyAll then
        if not self.goldenDirty then
            self.goldenDirty = true
            debug("Runtime.QueueDirty: golden (all)")
        end
        queuedLog.golden = true
    end

    if hasPendingWork() then
        scheduleProcessing()
    end
end

function Runtime:MarkGoldenDirty()
    self:QueueDirty("golden")
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
        local endeavorDirty = dirty.endeavor == true
        local achievementDirty = dirty.achievement == true
        local layoutDirty = dirty.layout == true
        local goldenDirty = self.goldenDirty == true

        dirty.quest = false
        dirty.endeavor = false
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

        local endeavorViewModel, endeavorVmBuilt = nil, false
        local endeavorRebuilt = false
        if endeavorDirty or self._endeavorVM == nil then
            endeavorViewModel, endeavorVmBuilt = buildEndeavorViewModel()
            self._endeavorVM = endeavorViewModel
            endeavorRebuilt = true
            local endeavorCount = 0
            if type(endeavorViewModel) == "table" and type(endeavorViewModel.items) == "table" then
                endeavorCount = #endeavorViewModel.items
            elseif type(endeavorViewModel) == "table" and type(endeavorViewModel.count) == "number" then
                endeavorCount = endeavorViewModel.count
            end
            debug("Runtime.BuildVM.Endeavor: count=%s", tostring(endeavorCount))
        else
            endeavorViewModel = self._endeavorVM
        end

        if endeavorViewModel == nil then
            endeavorViewModel = { items = {}, count = 0 }
            self._endeavorVM = endeavorViewModel
        end

        local achievementViewModel, achievementVmBuilt = nil, false
        if achievementDirty then
            achievementViewModel, achievementVmBuilt = buildAchievementViewModel()
            if achievementVmBuilt then
                debug("Runtime: built achievement view model")
            end
        end

        if goldenDirty then
            self.goldenDirty = false

            local cache = self.cache
            if type(cache) ~= "table" then
                cache = {}
                self.cache = cache
            end

            if type(cache.goldenVM) ~= "table" then
                cache.goldenVM = { campaigns = {} }
            end

            local controller = rawget(Addon, "GoldenTrackerController")
            if type(controller) == "table" then
                safeCall(function()
                    if type(controller.Init) == "function" and not controller.__inited then
                        controller:Init()
                        controller.__inited = true
                    end

                    if type(controller.BuildViewModel) == "function" then
                        controller:BuildViewModel()
                    end

                    if type(controller.GetViewModel) == "function" then
                        cache.goldenVM = controller:GetViewModel() or { campaigns = {} }
                    end

                    if type(cache.goldenVM) ~= "table" then
                        cache.goldenVM = { campaigns = {} }
                    end

                    local vm = cache.goldenVM
                    local campaigns = 0
                    if type(vm) == "table" and type(vm.campaigns) == "table" then
                        campaigns = #vm.campaigns
                    end

                    debug(("Runtime: Golden VM built, campaigns=%d"):format(campaigns))
                end)
            else
                if type(cache.goldenVM) ~= "table" then
                    cache.goldenVM = { campaigns = {} }
                end

                warn("Runtime: GoldenTrackerController missing; cached empty VM")
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

        local endeavorGeometryChanged = false
        if endeavorDirty or endeavorVmBuilt or endeavorRebuilt then
            local refreshedEndeavor = refreshEndeavorTracker(endeavorViewModel)
            local endeavorHeight = getEndeavorHeight()
            debug("Runtime.Refresh.Endeavor: height=%s", tostring(endeavorHeight))
            if refreshedEndeavor then
                endeavorGeometryChanged = updateTrackerGeometry("endeavor", "Endeavor")
                if endeavorGeometryChanged then
                    debug("Runtime: endeavor tracker refreshed (geometry changed)")
                end
            end
        end

        local achievementGeometryChanged = false
        if achievementDirty or achievementVmBuilt then
            local refreshedAchievement = refreshAchievementTracker(achievementViewModel)
            if refreshedAchievement then
                if not achievementVmBuilt then
                    debug("Runtime: deferred achievement geometry update (view model not built)")
                else
                    achievementGeometryChanged = updateTrackerGeometry("achievement")
                    if achievementGeometryChanged then
                        debug("Runtime: achievement tracker refreshed (geometry changed)")
                    end
                end
            end
        end

        local goldenGeometryChanged = false
        local goldenRefreshed = false
        local goldenTracker = rawget(Addon, "GoldenTracker")
        local shouldRefreshGolden = goldenDirty or layoutDirty or questGeometryChanged or endeavorGeometryChanged or achievementGeometryChanged
        if shouldRefreshGolden and type(goldenTracker) == "table" and type(goldenTracker.Refresh) == "function" then
            local cache = self.cache
            if type(cache) ~= "table" then
                cache = {}
                self.cache = cache
            end

            local viewModel = cache.goldenVM
            if type(viewModel) ~= "table" then
                viewModel = { campaigns = {} }
                cache.goldenVM = viewModel
            end

            diagnosticsDebug("[GoldenRT] handoff VM → campaigns=%d", type(viewModel.campaigns) == "table" and #viewModel.campaigns or 0)
            safeCall(function()
                goldenTracker:Refresh(viewModel)
                goldenRefreshed = true

                if goldenDirty then
                    local campaignCount = 0
                    if type(viewModel.campaigns) == "table" then
                        campaignCount = #viewModel.campaigns
                    end

                    debug(("Runtime: Golden refresh wired, campaigns=%d"):format(campaignCount))
                end
            end)
        end

        if goldenRefreshed then
            goldenGeometryChanged = updateTrackerGeometry("golden", "GoldenTracker", goldenTracker)
            if goldenGeometryChanged then
                debug("Runtime: golden tracker refreshed (geometry changed)")
            end
        end

        if layoutDirty or questGeometryChanged or endeavorGeometryChanged or achievementGeometryChanged or goldenGeometryChanged then
            if applyTrackerHostLayout() then
                debugVisibility("Runtime: applied tracker host layout")
            end
        end

        if interactivityDirty then
            local hostWindow = getHostWindow()
            if hostWindow and type(hostWindow.SetMouseEnabled) == "function" then
                safeCall(hostWindow.SetMouseEnabled, hostWindow, self._isInCursorMode == true)
                debugVisibility("Runtime: interactivity updated (cursor=%s)", tostring(self._isInCursorMode == true))
            end
        end

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
    debugVisibility("Runtime: cursor mode changed -> %s", tostring(normalized))
    scheduleProcessing()
end

return Runtime
