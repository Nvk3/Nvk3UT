local GEVENTS_SWITCH_REMOVE = true -- Marker: delete all TempEvent bootstrap in GEVENTS_*_SWITCH

-- [GEVENTS_SWITCH_REMOVE]
-- This file registers TEMP ESO event hooks for Golden during SHIM.
-- All registrations and InitKick are removed when events move to Events/* at GEVENTS_*_SWITCH.

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
    rows = {},
    rowCache = {},
    viewModel = nil,
    viewModelRaw = nil,
    fallbackHeaderCounter = 0,
}

-- TEMP EVENT BOOTSTRAP (INTRO) now SHIM-routed to Controller handlers.
-- Registrations bleiben hier bis GEVENTS_*_SWITCH, danach werden nur die Registrierungen verlagert.
-- Handler-Signaturen bleiben stabil und werden weiterverwendet.
-- Progress-only refresh: EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED löst den Sync aus; andere Events setzen nur Flags (keine UI/Layouts hier).
-- SHIM InitKick: temporary startup refresh to seed Golden data.
-- Will remain until GEVENTS_* migration centralizes lifecycle kicks.

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

local TEMP_EVENT_NAMESPACE = MODULE_TAG .. ".TempEvents"
local tempEventsRegistered = false

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

local function emitTempEventsActiveDebug()
    if not isDiagnosticsDebugEnabled() then
        return
    end

    local diagnostics = resolveDiagnostics()
    if diagnostics and type(diagnostics.Debug) == "function" then
        pcall(diagnostics.Debug, diagnostics, "Golden TempEvents active [GEVENTS_SWITCH_REMOVE]. This bootstrap will be removed on GEVENTS_*_SWITCH.")
    end
end

local function isControl(candidate)
    if type(candidate) ~= "userdata" then
        return false
    end

    if type(candidate.GetName) == "function" then
        return true
    end

    if type(candidate.GetType) == "function" then
        return true
    end

    if type(candidate.SetParent) == "function" then
        return true
    end

    return false
end

local function deferInitKick()
    if not state.initialized then
        return
    end

    local root = Nvk3UT
    if type(root) ~= "table" then
        return
    end

    local controller = root.GoldenTrackerController
    if type(controller) ~= "table" or type(controller.InitKickOnce) ~= "function" then
        return
    end

    local function trigger()
        pcall(controller.InitKickOnce, controller)
    end

    local callLater = rawget(_G, "zo_callLater")
    if type(callLater) == "function" then
        pcall(callLater, trigger, 0)
    else
        trigger()
    end
end

local function callMethod(target, methodName, ...)
    if type(target) ~= "table" then
        return false
    end

    local method = target[methodName]
    if type(method) ~= "function" then
        return false
    end

    local ok = pcall(method, target, ...)
    return ok
end

local function routeTempEvent(handlerName, ...)
    if not state.initialized then
        return
    end

    local root = Nvk3UT
    if type(root) ~= "table" then
        return
    end

    local controller = root.GoldenTrackerController
    if type(controller) ~= "table" then
        return
    end

    if type(handlerName) ~= "string" or handlerName == "" then
        return
    end

    callMethod(controller, handlerName, ...)
end

local function registerTempEvent(eventManager, eventName, eventCode, handlerName)
    if eventManager == nil then
        return
    end

    local registerFn = eventManager.RegisterForEvent
    if type(registerFn) ~= "function" then
        return
    end

    if type(eventCode) ~= "number" then
        return
    end

    local namespace = string.format("%s.%s", TEMP_EVENT_NAMESPACE, tostring(eventName))
    local callback = function(eventCode, ...)
        routeTempEvent(handlerName, eventCode, ...)
    end

    pcall(registerFn, eventManager, namespace, eventCode, callback)
end

local function InitializeTempEvents()
    if tempEventsRegistered then
        return
    end

    local eventManager = rawget(_G, "EVENT_MANAGER")
    if eventManager == nil then
        return
    end

    -- [GEVENTS_SWITCH_REMOVE] TempEvent registration (to be deleted on SWITCH)
    registerTempEvent(eventManager, "EVENT_TIMED_ACTIVITIES_UPDATED", EVENT_TIMED_ACTIVITIES_UPDATED, "OnTimedActivitiesUpdated")
    -- [GEVENTS_SWITCH_REMOVE] TempEvent registration (to be deleted on SWITCH)
    registerTempEvent(eventManager, "EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED", EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED, "OnTimedActivityProgressUpdated")
    -- [GEVENTS_SWITCH_REMOVE] TempEvent registration (to be deleted on SWITCH)
    registerTempEvent(eventManager, "EVENT_TIMED_ACTIVITY_SYSTEM_STATUS_UPDATED", EVENT_TIMED_ACTIVITY_SYSTEM_STATUS_UPDATED, "OnTimedActivitySystemStatusUpdated")

    tempEventsRegistered = true

    -- [GEVENTS_SWITCH_REMOVE] END of TempEvent registrations
end

local function UnregisterTempEvents_Golden()
    -- [GEVENTS_SWITCH_REMOVE] Call this during GEVENTS_*_SWITCH to cleanly detach TempEvents

    local eventManager = rawget(_G, "EVENT_MANAGER")
    if eventManager == nil then
        return
    end

    local unregisterFn = eventManager.UnregisterForEvent
    if type(unregisterFn) ~= "function" then
        return
    end

    local function unregister(eventName)
        local namespace = string.format("%s.%s", TEMP_EVENT_NAMESPACE, tostring(eventName))
        pcall(unregisterFn, eventManager, namespace)
    end

    unregister("EVENT_TIMED_ACTIVITIES_UPDATED")
    unregister("EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED")
    unregister("EVENT_TIMED_ACTIVITY_SYSTEM_STATUS_UPDATED")
end

local function createRootAndContent(parentControl)
    local wm = rawget(_G, "WINDOW_MANAGER")
    if wm == nil then
        safeDebug("Init aborted; WINDOW_MANAGER unavailable")
        return nil, nil
    end

    if not isControl(parentControl) then
        safeDebug("Init aborted; parent control invalid for root creation (%s)", type(parentControl))
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
    -- FIX: parent must be a UI control (userdata); host now passes the section container
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

local function releaseRow(row)
    if type(row) ~= "table" then
        return
    end

    local rowsModule = getRowsModule()
    if rowsModule and type(rowsModule.ReleaseRow) == "function" then
        local ok = pcall(rowsModule.ReleaseRow, row)
        if ok then
            return
        end
    end

    local control = row.control
    if control then
        if type(control.ClearAnchors) == "function" then
            control:ClearAnchors()
        end
        if type(control.SetHidden) == "function" then
            control:SetHidden(true)
        end
        if type(control.SetParent) == "function" then
            control:SetParent(nil)
        end
    end
end

local function formatFallbackCategoryName(categoryData)
    local name = ""
    if type(categoryData) == "table" then
        name = categoryData.name or categoryData.title or ""
    end

    if type(name) ~= "string" then
        name = tostring(name or "")
    end

    if name ~= "" then
        local ok, upper = pcall(string.upper, name)
        if ok and type(upper) == "string" then
            name = upper
        end
    end

    return name
end

local function createFallbackHeaderRow(parent, categoryData)
    if not isControl(parent) then
        return nil
    end

    local wm = rawget(_G, "WINDOW_MANAGER")
    if wm == nil then
        safeDebug("Fallback header unavailable: WINDOW_MANAGER missing")
        return nil
    end

    state.fallbackHeaderCounter = (state.fallbackHeaderCounter or 0) + 1

    local parentName = "Nvk3UT_Golden"
    if type(parent.GetName) == "function" then
        local ok, name = pcall(parent.GetName, parent)
        if ok and type(name) == "string" and name ~= "" then
            parentName = name
        end
    end

    local controlName = string.format("%s_FallbackHeader%u", parentName, state.fallbackHeaderCounter)
    local control = wm:CreateControl(controlName, parent, CT_CONTROL)
    if not isControl(control) then
        safeDebug("Fallback header control creation failed (%s)", tostring(controlName))
        return nil
    end

    if control.ClearAnchors then
        control:ClearAnchors()
    end
    if control.SetParent then
        control:SetParent(parent)
    end
    if control.SetResizeToFitDescendents then
        control:SetResizeToFitDescendents(false)
    end
    if control.SetMouseEnabled then
        control:SetMouseEnabled(false)
    end
    if control.SetHidden then
        control:SetHidden(false)
    end

    local headerHeight = 44
    if control.SetHeight then
        control:SetHeight(headerHeight)
    end
    control.__height = headerHeight

    local labelName = string.format("%s_Label", controlName)
    local label = wm:CreateControl(labelName, control, CT_LABEL)
    if label then
        if label.ClearAnchors then
            label:ClearAnchors()
        end
        if label.SetAnchor then
            label:SetAnchor(LEFT, control, LEFT, 16, 0)
            label:SetAnchor(RIGHT, control, RIGHT, -16, 0)
        end
        if label.SetHidden then
            label:SetHidden(false)
        end
        if label.SetFont then
            label:SetFont("ZoFontHeader2")
        end
        if label.SetColor then
            label:SetColor(1, 1, 1, 1)
        end
        if label.SetWrapMode and rawget(_G, "TEXT_WRAP_MODE_ELLIPSIS") then
            label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
        end
        if label.SetHorizontalAlignment and rawget(_G, "TEXT_ALIGN_LEFT") then
            label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
        end
        if label.SetVerticalAlignment and rawget(_G, "TEXT_ALIGN_CENTER") then
            label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        end

        if label.SetText then
            label:SetText(formatFallbackCategoryName(categoryData))
        end
    else
        safeDebug("Fallback header label creation failed (%s)", tostring(labelName))
    end

    return {
        control = control,
        label = label,
        height = headerHeight,
    }
end

local function resetRows()
    if type(state.rows) == "table" then
        for index = #state.rows, 1, -1 do
            local row = state.rows[index]
            releaseRow(row)
            state.rows[index] = nil
        end
    end

    if type(state.rowCache) == "table" then
        for index = #state.rowCache, 1, -1 do
            local row = state.rowCache[index]
            releaseRow(row)
            state.rowCache[index] = nil
        end
    end

    state.rows = {}
    state.rowCache = {}
end

function GoldenTracker.Init(parentControl, opts)
    state.parent = nil
    state.height = 0
    state.initialized = false
    state.root = nil
    state.content = nil

    resetRows()

    local originalParent = parentControl
    local resolvedParent = parentControl

    if type(resolvedParent) == "table" then
        if isControl(resolvedParent.control) then
            resolvedParent = resolvedParent.control
        elseif isControl(resolvedParent.container) then
            resolvedParent = resolvedParent.container
        end
    end

    if not isControl(resolvedParent) then
        safeDebug("Init aborted: invalid parent (value=%s type=%s)", tostring(originalParent), type(originalParent))
        return
    end

    state.parent = resolvedParent

    if isDiagnosticsDebugEnabled() then
        safeDebug("Init: parent=%s (%s)", tostring(resolvedParent), type(resolvedParent))
    end

    local root, content = createRootAndContent(resolvedParent)
    state.root = root
    state.content = content

    if not root or not content then
        safeDebug("Init incomplete; root or content missing")
        return
    end

    state.height = 0
    setContainerHeight(resolvedParent, 0)
    applyVisibility(resolvedParent, false)
    applyVisibility(root, true)
    applyVisibility(content, true)

    state.initialized = true

    InitializeTempEvents()

    -- [GEVENTS_SWITCH_REMOVE] Deferred InitKick (SHIM)
    deferInitKick()

    emitTempEventsActiveDebug()

    safeDebug("Init")
end

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

    local rowsModule = getRowsModule()
    local layoutModule = getLayoutModule()

    state.rowCache = state.rowCache or {}

    local previousRows = type(state.rows) == "table" and state.rows or {}

    -- recycle previously active rows into the cache
    for index = #previousRows, 1, -1 do
        local row = previousRows[index]
        if row then
            releaseRow(row)
            table.insert(state.rowCache, row)
        end
        previousRows[index] = nil
    end

    state.rows = {}

    local vm = type(viewModel) == "table" and viewModel or nil
    state.viewModelRaw = viewModel
    state.viewModel = vm
    local categories = (vm and type(vm.categories) == "table" and vm.categories) or {}
    local categoryCount = #categories
    local debugEnabled = isDiagnosticsDebugEnabled()
    if debugEnabled then
        safeDebug("[Golden.UI] VM in → cats=%d", categoryCount)
    end

    local activeRows = state.rows
    local rowCount = 0

    local hasAcquire = rowsModule and type(rowsModule.AcquireCategoryHeader) == "function"
    if rowsModule and not hasAcquire then
        safeDebug("Rows module missing AcquireCategoryHeader; using inline fallback headers")
    elseif not rowsModule then
        safeDebug("Rows module unavailable; using inline fallback headers")
    end

    local fallbackRowBuilt = false

    for categoryIndex = 1, categoryCount do
        local categoryData = categories[categoryIndex]
        if type(categoryData) == "table" then
            local recycledRow = table.remove(state.rowCache)
            local row = nil

            if hasAcquire then
                local ok, acquiredRow = pcall(rowsModule.AcquireCategoryHeader, content, recycledRow, categoryData)
                if ok and type(acquiredRow) == "table" and acquiredRow.control then
                    row = acquiredRow
                else
                    if recycledRow then
                        table.insert(state.rowCache, recycledRow)
                    end
                    if not ok then
                        safeDebug("AcquireCategoryHeader failed: %s", tostring(acquiredRow))
                    end
                end
            else
                if recycledRow then
                    table.insert(state.rowCache, recycledRow)
                end
            end

            if not row then
                row = createFallbackHeaderRow(content, categoryData)
                if row then
                    fallbackRowBuilt = true
                end
            end

            if row and row.control then
                rowCount = rowCount + 1
                activeRows[rowCount] = row
            end
        end
    end

    local totalHeight = 0

    if layoutModule and type(layoutModule.ApplyLayout) == "function" then
        totalHeight = layoutModule.ApplyLayout(content, activeRows) or 0
    else
        safeDebug("Layout module unavailable; skipping ApplyLayout")
    end

    if totalHeight <= 0 then
        if rowCount > 0 then
            for index = 1, rowCount do
                local row = activeRows[index]
                totalHeight = totalHeight + (tonumber(row and row.height) or 0)
            end
        elseif rowCount == 0 then
            totalHeight = 86
        end
    end

    local shouldShow = totalHeight > 0
    applyVisibility(root, not shouldShow)
    applyVisibility(content, not shouldShow)

    state.height = totalHeight
    setContainerHeight(container, totalHeight)

    if debugEnabled then
        safeDebug("[Golden.UI] Refresh: cats=%d rows=%d height=%d fallback=%s", categoryCount, rowCount, totalHeight, tostring(fallbackRowBuilt))
    end
end

function GoldenTracker.GetHeight()
    local height = tonumber(state.height) or 0
    if height < 0 then
        height = 0
    end
    return height
end

Nvk3UT.GoldenTracker = GoldenTracker

return GoldenTracker
