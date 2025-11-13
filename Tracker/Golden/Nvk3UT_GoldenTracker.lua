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

-- TEMP EVENT BOOTSTRAP (INTRO) now SHIM-routed to Controller handlers.
-- Registrations bleiben hier bis GEVENTS_*_SWITCH, danach werden nur die Registrierungen verlagert.
-- Handler-Signaturen bleiben stabil und werden weiterverwendet.

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

    registerTempEvent(eventManager, "EVENT_TIMED_ACTIVITIES_UPDATED", EVENT_TIMED_ACTIVITIES_UPDATED, "OnTimedActivitiesUpdated")
    registerTempEvent(eventManager, "EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED", EVENT_TIMED_ACTIVITY_PROGRESS_UPDATED, "OnTimedActivityProgressUpdated")
    registerTempEvent(eventManager, "EVENT_TIMED_ACTIVITY_SYSTEM_STATUS_UPDATED", EVENT_TIMED_ACTIVITY_SYSTEM_STATUS_UPDATED, "OnTimedActivitySystemStatusUpdated")

    tempEventsRegistered = true
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

    InitializeTempEvents()

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

    ClearChildren(content)

    local rowsModule = getRowsModule()
    local layoutModule = getLayoutModule()
    local rows = {}

    local vm = type(viewModel) == "table" and viewModel or {}
    local categories = type(vm.categories) == "table" and vm.categories or {}

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

    safeDebug("Refresh passthrough layout, rows=%d height=%d", #rows, totalHeight)
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
