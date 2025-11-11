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

    state.currentHeight = 0

    local container = state.container
    if container and container.SetHeight then
        container:SetHeight(state.currentHeight)
    end

    safeDebug("EndeavorTracker.Refresh: empty stub, height=0")
end

function EndeavorTracker.GetHeight()
    return coerceHeight(state.currentHeight)
end

Nvk3UT.EndeavorTracker = EndeavorTracker

return EndeavorTracker
