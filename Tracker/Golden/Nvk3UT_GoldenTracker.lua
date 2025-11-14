local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = Nvk3UT and Nvk3UT.GoldenTrackerRows
local Layout = Nvk3UT and Nvk3UT.GoldenTrackerLayout

local GoldenTracker = {}
GoldenTracker.__index = GoldenTracker

local MODULE_TAG = addonName .. ".GoldenTracker"

local state = {
    parent = nil,
    root = nil,
    content = nil,
    height = 0,
    initialized = false,
}

local function getAddonRoot()
    local root = rawget(_G, addonName)
    if type(root) == "table" then
        return root
    end
    return Nvk3UT
end

local function isDebugEnabled()
    local root = getAddonRoot()

    local utils = root and root.Utils or Nvk3UT_Utils
    if type(utils) == "table" and type(utils.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(utils.IsDebugEnabled)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local diagnostics = root and root.Diagnostics or Nvk3UT_Diagnostics
    if type(diagnostics) == "table" and type(diagnostics.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return diagnostics:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    if type(root) == "table" and type(root.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return root:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local sv = root and (root.sv or root.SV)
    if type(sv) == "table" and sv.debug ~= nil then
        return sv.debug == true
    end

    return false
end

local function safeDebug(message, ...)
    if not isDebugEnabled() then
        return
    end

    local root = getAddonRoot()
    local debugFn = root and root.Debug
    if type(debugFn) ~= "function" then
        return
    end

    local payload = tostring(message)
    if select("#", ...) > 0 then
        local formatString = type(message) == "string" and message or payload
        local ok, formatted = pcall(string.format, formatString, ...)
        if ok and formatted ~= nil then
            payload = formatted
        end
    end

    pcall(debugFn, string.format("%s: %s", MODULE_TAG, tostring(payload)))
end

local function runSafe(fn)
    if type(fn) ~= "function" then
        return
    end

    local root = getAddonRoot()
    if type(root) == "table" then
        local safeCall = rawget(root, "SafeCall")
        if type(safeCall) == "function" then
            local ok = pcall(safeCall, fn)
            if ok then
                return
            end
        end
    end

    pcall(fn)
end

local function getRowsModule()
    if Rows and type(Rows) == "table" then
        return Rows
    end

    Rows = Nvk3UT and Nvk3UT.GoldenTrackerRows
    if type(Rows) == "table" then
        return Rows
    end

    return nil
end

local function getLayoutModule()
    if Layout and type(Layout) == "table" then
        return Layout
    end

    Layout = Nvk3UT and Nvk3UT.GoldenTrackerLayout
    if type(Layout) == "table" then
        return Layout
    end

    return nil
end

local function ClearChildren(control)
    if not control then
        return
    end

    local getNumChildren = control.GetNumChildren
    local getChild = control.GetChild
    if type(getNumChildren) ~= "function" or type(getChild) ~= "function" then
        return
    end

    local okCount, childCount = pcall(getNumChildren, control)
    if not okCount or type(childCount) ~= "number" or childCount <= 0 then
        return
    end

    for index = childCount - 1, 0, -1 do
        local okChild, child = pcall(getChild, control, index)
        if okChild and child then
            if child.SetHidden then
                child:SetHidden(true)
            end
            if child.ClearAnchors then
                child:ClearAnchors()
            end
            if child.SetParent then
                child:SetParent(nil)
            end
        end
    end
end

local function createRootAndContent(parentControl)
    local wm = rawget(_G, "WINDOW_MANAGER")
    if wm == nil then
        safeDebug("Init aborted; WINDOW_MANAGER unavailable")
        return nil, nil
    end

    local parentName = "Nvk3UT_Golden"
    if parentControl and type(parentControl.GetName) == "function" then
        local okName, name = pcall(parentControl.GetName, parentControl)
        if okName and type(name) == "string" and name ~= "" then
            parentName = name
        end
    end

    local rootName = parentName .. "Root"
    local rootControl = wm:CreateControl(rootName, parentControl, CT_CONTROL)
    if rootControl then
        if rootControl.SetResizeToFitDescendents then
            rootControl:SetResizeToFitDescendents(true)
        end
        if rootControl.SetHidden then
            rootControl:SetHidden(true)
        end
        if rootControl.SetMouseEnabled then
            rootControl:SetMouseEnabled(false)
        end
    end

    local contentControl
    if rootControl then
        local contentName = parentName .. "Content"
        contentControl = wm:CreateControl(contentName, rootControl, CT_CONTROL)
        if contentControl then
            if contentControl.SetResizeToFitDescendents then
                contentControl:SetResizeToFitDescendents(true)
            end
            if contentControl.SetHidden then
                contentControl:SetHidden(true)
            end
            if contentControl.SetMouseEnabled then
                contentControl:SetMouseEnabled(false)
            end
        end
    end

    return rootControl, contentControl
end

local function setContainerHeight(container, height)
    local numericHeight = tonumber(height) or 0
    if numericHeight < 0 then
        numericHeight = 0
    end

    if container and container.SetHeight then
        container:SetHeight(numericHeight)
    end
end

local function applyVisibility(control, hidden)
    if control and control.SetHidden then
        control:SetHidden(hidden)
    end
end

local function safeCreateRow(rowFn, parent, data)
    if type(rowFn) ~= "function" or parent == nil then
        return nil
    end

    local ok, row = pcall(rowFn, parent, data)
    if ok and row then
        return row
    end

    if not ok then
        safeDebug("Row creation failed: %s", tostring(row))
    end

    return nil
end

function GoldenTracker.Init(parentControl)
    state.parent = parentControl
    state.height = 0
    state.initialized = false
    state.root = nil
    state.content = nil

    if not parentControl then
        safeDebug("Init skipped; parent control missing")
        return
    end

    local root, content = createRootAndContent(parentControl)
    state.root = root
    state.content = content

    if not root or not content then
        safeDebug("Init incomplete; root or content missing")
        return
    end

    ClearChildren(content)

    state.height = 0
    setContainerHeight(parentControl, 0)
    applyVisibility(parentControl, false)
    applyVisibility(root, true)
    applyVisibility(content, true)

    state.initialized = true

    safeDebug("Init")

    local initReason = "init"
    safeDebug("[GoldenTracker.SHIM] init-kick (reason=%s)", initReason)
    GoldenTracker:RequestFullRefresh(initReason)
end

local function goldenDataChanged(reason)
    local reasonForLog = reason
    if reasonForLog == nil or reasonForLog == "" then
        reasonForLog = "n/a"
    else
        reasonForLog = tostring(reasonForLog)
    end

    local results = {
        modelRefreshed = false,
        controllerMarked = false,
        runtimeQueued = false,
    }

    runSafe(function()
        local root = getAddonRoot()
        if type(root) ~= "table" then
            safeDebug("[GoldenTracker.SHIM] data change aborted (reason=%s; addon missing)", reasonForLog)
            return
        end

        local model = rawget(root, "GoldenModel")
        if type(model) == "table" then
            local refresh = model.RefreshFromGame or model.Refresh
            if type(refresh) == "function" then
                local ok, err = pcall(refresh, model)
                if ok then
                    results.modelRefreshed = true
                    safeDebug("[GoldenTracker.SHIM] model refreshed (reason=%s)", reasonForLog)
                else
                    safeDebug("[GoldenTracker.SHIM] model refresh failed (reason=%s, error=%s)", reasonForLog, tostring(err))
                end
            end
        end

        local controller = rawget(root, "GoldenTrackerController")
        if type(controller) == "table" then
            local markDirty = controller.MarkDirty or controller.RequestRefresh
            if type(markDirty) == "function" then
                local ok, err = pcall(markDirty, controller, reason)
                if ok then
                    results.controllerMarked = true
                else
                    safeDebug("[GoldenTracker.SHIM] mark dirty failed (reason=%s, error=%s)", reasonForLog, tostring(err))
                end
            end
        end

        local runtime = rawget(root, "TrackerRuntime")
        if type(runtime) == "table" then
            local queueDirty = runtime.QueueDirty or runtime.MarkDirty or runtime.RequestRefresh
            if type(queueDirty) == "function" then
                local ok, err = pcall(queueDirty, runtime, "golden")
                if ok then
                    results.runtimeQueued = true
                else
                    safeDebug("[GoldenTracker.SHIM] queue dirty failed (reason=%s, error=%s)", reasonForLog, tostring(err))
                end
            end
        end

        safeDebug(
            "[GoldenTracker.SHIM] data changed (reason=%s model=%s dirty=%s queued=%s)",
            reasonForLog,
            tostring(results.modelRefreshed),
            tostring(results.controllerMarked),
            tostring(results.runtimeQueued)
        )
    end)

    return results.modelRefreshed or results.controllerMarked or results.runtimeQueued
end

local function resolveGoldenRefreshReason(...)
    local argumentCount = select("#", ...)
    if argumentCount == 0 then
        return nil
    end

    local first = select(1, ...)
    if type(first) == "table" then
        if first == GoldenTracker then
            if argumentCount >= 2 then
                return select(2, ...)
            end
            return nil
        end

        local mt = getmetatable(first)
        if mt ~= nil then
            if mt == GoldenTracker then
                if argumentCount >= 2 then
                    return select(2, ...)
                end
                return nil
            end

            if type(mt) == "table" and mt.__index == GoldenTracker then
                if argumentCount >= 2 then
                    return select(2, ...)
                end
                return nil
            end
        end
    end

    return first
end

local function requestGoldenDataRefreshInternal(reason)
    return goldenDataChanged(reason) == true
end

function GoldenTracker:NotifyDataChanged(reason)
    local resolvedReason = resolveGoldenRefreshReason(self, reason)
    return requestGoldenDataRefreshInternal(resolvedReason)
end

function GoldenTracker.RequestDataRefresh(...)
    local resolvedReason = resolveGoldenRefreshReason(...)
    return requestGoldenDataRefreshInternal(resolvedReason)
end

GoldenTracker.RequestRefresh = GoldenTracker.RequestDataRefresh
GoldenTracker.RequestFullRefresh = GoldenTracker.RequestDataRefresh

-- TEMP EVENTS (Golden) — will be removed in GEVENTS_00X_SWITCH
-- Will be removed in GEVENTS_00X_SWITCH
--[[ GEVENTS_TEMP_EVENTS_BEGIN: Golden (remove on GEVENTS_00X_SWITCH) ]]

local GOLDEN_TEMP_EVENT_NAMESPACE = MODULE_TAG .. ".TempEvents"

local GOLDEN_TEMP_EVENT_HANDLES = {
    updated = GOLDEN_TEMP_EVENT_NAMESPACE .. ".PursuitsUpdated",
    progress = GOLDEN_TEMP_EVENT_NAMESPACE .. ".ProgressUpdated",
    status = GOLDEN_TEMP_EVENT_NAMESPACE .. ".StatusUpdated",
}

local GOLDEN_TEMP_EVENT_REASONS = {
    updated = "EVENT_GOLDEN_PURSUITS_UPDATED",
    progress = "EVENT_GOLDEN_PURSUITS_PROGRESS_UPDATED",
    status = "EVENT_GOLDEN_PURSUITS_STATUS_UPDATED",
}

local GOLDEN_TEMP_EVENT_IDS = {
    updated = rawget(_G, "EVENT_GOLDEN_PURSUITS_UPDATED"),
    progress = rawget(_G, "EVENT_GOLDEN_PURSUITS_PROGRESS_UPDATED"),
    status = rawget(_G, "EVENT_GOLDEN_PURSUITS_STATUS_UPDATED"),
}

local goldenTempEventsState = {
    registered = false,
}

local function onGoldenPursuitsUpdated(...)
    safeDebug("[GoldenTracker.TempEvents] %s", GOLDEN_TEMP_EVENT_REASONS.updated)
    GoldenTracker:RequestFullRefresh(GOLDEN_TEMP_EVENT_REASONS.updated)
end

local function onGoldenPursuitsProgressUpdated(...)
    safeDebug("[GoldenTracker.TempEvents] %s", GOLDEN_TEMP_EVENT_REASONS.progress)
    GoldenTracker:RequestFullRefresh(GOLDEN_TEMP_EVENT_REASONS.progress)
end

local function onGoldenPursuitsStatusUpdated(...)
    safeDebug("[GoldenTracker.TempEvents] %s", GOLDEN_TEMP_EVENT_REASONS.status)
    GoldenTracker:RequestFullRefresh(GOLDEN_TEMP_EVENT_REASONS.status)
end

local function registerGoldenTempEvents()
    if goldenTempEventsState.registered then
        return
    end

    local eventManager = rawget(_G, "EVENT_MANAGER")
    if eventManager == nil then
        return
    end

    local registerMethod = eventManager.RegisterForEvent
    if type(registerMethod) ~= "function" then
        return
    end

    local registeredCount = 0

    if GOLDEN_TEMP_EVENT_IDS.updated ~= nil then
        eventManager:RegisterForEvent(
            GOLDEN_TEMP_EVENT_HANDLES.updated,
            GOLDEN_TEMP_EVENT_IDS.updated,
            onGoldenPursuitsUpdated
        )
        registeredCount = registeredCount + 1
    end

    if GOLDEN_TEMP_EVENT_IDS.progress ~= nil then
        eventManager:RegisterForEvent(
            GOLDEN_TEMP_EVENT_HANDLES.progress,
            GOLDEN_TEMP_EVENT_IDS.progress,
            onGoldenPursuitsProgressUpdated
        )
        registeredCount = registeredCount + 1
    end

    if GOLDEN_TEMP_EVENT_IDS.status ~= nil then
        eventManager:RegisterForEvent(
            GOLDEN_TEMP_EVENT_HANDLES.status,
            GOLDEN_TEMP_EVENT_IDS.status,
            onGoldenPursuitsStatusUpdated
        )
        registeredCount = registeredCount + 1
    end

    if registeredCount > 0 then
        goldenTempEventsState.registered = true
        safeDebug("[GoldenTracker.TempEvents] register (%d handlers)", registeredCount)
    end
end

local function unregisterGoldenTempEvents()
    if not goldenTempEventsState.registered then
        return
    end

    local eventManager = rawget(_G, "EVENT_MANAGER")
    if eventManager == nil then
        return
    end

    local unregisterMethod = eventManager.UnregisterForEvent
    if type(unregisterMethod) ~= "function" then
        return
    end

    unregisterMethod(eventManager, GOLDEN_TEMP_EVENT_HANDLES.updated)
    unregisterMethod(eventManager, GOLDEN_TEMP_EVENT_HANDLES.progress)
    unregisterMethod(eventManager, GOLDEN_TEMP_EVENT_HANDLES.status)

    goldenTempEventsState.registered = false
    safeDebug("[GoldenTracker.TempEvents] unregister")
end

function GoldenTracker:TempEvents_Register()
    registerGoldenTempEvents()
end

function GoldenTracker:TempEvents_Unregister()
    unregisterGoldenTempEvents()
end

registerGoldenTempEvents()

--[[ GEVENTS_TEMP_EVENTS_END: Golden ]]

function GoldenTracker.Refresh(viewModel)
    if not state.initialized then
        return
    end

    local container = state.parent
    local root = state.root
    local content = state.content

    if not container or not root or not content then
        state.height = 0
        setContainerHeight(container, 0)
        return
    end

    ClearChildren(content)

    local rowsModule = getRowsModule()
    local layoutModule = getLayoutModule()
    local rows = {}

    local vm = type(viewModel) == "table" and viewModel or {}
    local categories = type(vm.categories) == "table" and vm.categories or {}
    local status = type(vm.status) == "table" and vm.status or {}
    local statusSummary = string.format(
        "avail=%s locked=%s hasEntries=%s",
        tostring(status.isAvailable),
        tostring(status.isLocked),
        tostring(status.hasEntries)
    )

    safeDebug("Refresh start: %s categories=%d", statusSummary, #categories)

    if rowsModule and #categories > 0 then
        for categoryIndex = 1, #categories do
            local categoryData = categories[categoryIndex]
            if type(categoryData) == "table" then
                local categoryRow = safeCreateRow(rowsModule.CreateCategoryHeader, content, categoryData)
                if categoryRow then
                    table.insert(rows, categoryRow)
                end

                local entries = type(categoryData.entries) == "table" and categoryData.entries or {}
                for entryIndex = 1, #entries do
                    local entryData = entries[entryIndex]
                    if type(entryData) == "table" then
                        local entryRow = safeCreateRow(rowsModule.CreateEntryRow, content, entryData)
                        if entryRow then
                            table.insert(rows, entryRow)
                        end

                        local objectives = type(entryData.objectives) == "table" and entryData.objectives or {}
                        for objectiveIndex = 1, #objectives do
                            local objectiveData = objectives[objectiveIndex]
                            if type(objectiveData) == "table" then
                                local objectiveRow = safeCreateRow(rowsModule.CreateObjectiveRow, content, objectiveData)
                                if objectiveRow then
                                    table.insert(rows, objectiveRow)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local totalHeight = 0

    if layoutModule then
        totalHeight = layoutModule.ApplyLayout(content, rows) or 0
    else
        safeDebug("Refresh passthrough skipped; layout module unavailable")
    end

    local hasRows = #rows > 0 and layoutModule ~= nil
    applyVisibility(root, not hasRows)
    applyVisibility(content, not hasRows)

    state.height = totalHeight
    setContainerHeight(container, totalHeight)

    safeDebug("Refresh complete: %s rows=%d height=%d", statusSummary, #rows, totalHeight)
end

function GoldenTracker.GetHeight()
    local height = tonumber(state.height) or 0
    if height < 0 then
        height = 0
    end
    return height
end

Nvk3UT.GoldenTracker = GoldenTracker

function Nvk3UT_GoldenTracker_RequestFullRefresh(...)
    return GoldenTracker.RequestFullRefresh(...)
end

return GoldenTracker
