local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = Nvk3UT and Nvk3UT.GoldenTrackerRows

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

local debugFlags = {
    refreshLogged = false,
}

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

local function clearChildren(control)
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

local function accumulateHeight(total, control)
    if not control then
        return total
    end

    local height = 0
    if type(control.__height) == "number" then
        height = control.__height
    elseif control.GetHeight then
        local ok, value = pcall(control.GetHeight, control)
        if ok and type(value) == "number" then
            height = value
        end
    end

    if height < 0 then
        height = 0
    end

    return total + height
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

    clearChildren(content)

    state.height = 0
    setContainerHeight(parentControl, 0)
    applyVisibility(parentControl, false)
    applyVisibility(root, true)
    applyVisibility(content, true)

    state.initialized = true

    safeDebug("Init")
end

local function renderCategories(content, categories)
    local rowsModule = getRowsModule()
    if rowsModule == nil then
        safeDebug("Refresh skipping rendering; Rows module unavailable")
        return 0
    end

    local totalHeight = 0

    local firstCategory = categories[1]
    if type(firstCategory) ~= "table" then
        return 0
    end

    local categoryControl = safeCreateRow(rowsModule.CreateCategoryHeader, content, firstCategory)
    totalHeight = accumulateHeight(totalHeight, categoryControl)

    local entries = type(firstCategory.entries) == "table" and firstCategory.entries or {}
    for index = 1, #entries do
        local entryControl = safeCreateRow(rowsModule.CreateEntryRow, content, entries[index])
        totalHeight = accumulateHeight(totalHeight, entryControl)
    end

    return totalHeight
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
        return
    end

    clearChildren(content)

    local vm = type(viewModel) == "table" and viewModel or {}
    local categories = type(vm.categories) == "table" and vm.categories or {}

    if #categories == 0 then
        state.height = 0
        setContainerHeight(container, 0)
        applyVisibility(root, true)
        applyVisibility(content, true)
        return
    end

    applyVisibility(root, false)
    applyVisibility(content, false)

    local totalHeight = renderCategories(content, categories)

    state.height = totalHeight
    setContainerHeight(container, totalHeight)

    if not debugFlags.refreshLogged then
        debugFlags.refreshLogged = true
        safeDebug("Refresh (stub)")
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
