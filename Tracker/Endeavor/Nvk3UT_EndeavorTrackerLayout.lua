local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Layout = {}
Layout.__index = Layout

local MODULE_TAG = addonName .. ".EndeavorTrackerLayout"

local lastHeight = 0

local function safeDebug(fmt, ...)
    local root = rawget(_G, addonName)
    if type(root) ~= "table" then
        return
    end

    local diagnostics = root.Diagnostics
    if diagnostics and type(diagnostics.DebugIfEnabled) == "function" then
        diagnostics:DebugIfEnabled("EndeavorTrackerLayout", fmt, ...)
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
        if value ~= value then
            return 0
        end
        return value
    end

    return 0
end

function Layout.Init()
    lastHeight = 0
end

function Layout.Apply(container)
    local measured = 0

    if container and type(container.GetHeight) == "function" then
        local ok, height = pcall(container.GetHeight, container)
        if ok then
            measured = coerceHeight(height)
        end
    end

    lastHeight = measured

    safeDebug("EndeavorTrackerLayout.Apply: height=%d", measured)

    return measured
end

function Layout.GetLastHeight()
    return coerceHeight(lastHeight)
end

Nvk3UT.EndeavorTrackerLayout = Layout

return Layout
