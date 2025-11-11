local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local EndeavorTracker = {}
EndeavorTracker.__index = EndeavorTracker

local MODULE_TAG = addonName .. ".EndeavorTracker"

local state = {
    container = nil,
    currentHeight = 0,
    isInitialized = false,
}

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

local function safeDebug(fmt, ...)
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

local function coerceHeight(value)
    if type(value) == "number" then
        if value ~= value then -- NaN guard
            return 0
        end
        return value
    end

    return 0
end

function EndeavorTracker.Init(sectionContainer)
    state.container = sectionContainer
    state.currentHeight = 0
    state.isInitialized = true

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

    local rows = getRowsModule()
    local items = {}
    if type(viewModel) == "table" and type(viewModel.items) == "table" then
        items = viewModel.items
    end

    local builtHeight = 0
    local container = state.container
    if rows and type(rows.Build) == "function" then
        local ok, height = pcall(rows.Build, container, items)
        if ok then
            builtHeight = coerceHeight(height)
        end
    elseif container and type(container.SetHeight) == "function" then
        container:SetHeight(0)
    end

    local layoutHeight = builtHeight
    local layout = getLayoutModule()
    if layout and type(layout.Apply) == "function" then
        local ok, measured = pcall(layout.Apply, container)
        if ok then
            layoutHeight = coerceHeight(measured)
        end
    end

    state.currentHeight = coerceHeight(layoutHeight)

    if container and container.SetHeight then
        container:SetHeight(state.currentHeight)
    end

    safeDebug("EndeavorTracker.Refresh: rows=%d height=%d", type(items) == "table" and #items or 0, state.currentHeight)
end

function EndeavorTracker.GetHeight()
    return coerceHeight(state.currentHeight)
end

Nvk3UT.EndeavorTracker = EndeavorTracker

return EndeavorTracker
