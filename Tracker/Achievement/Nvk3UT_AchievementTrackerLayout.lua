local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Layout = {}
Layout.__index = Layout

local MODULE_TAG = addonName .. ".AchievementTrackerLayout"

local function logLoaded()
    local root = rawget(_G, addonName)
    if type(root) ~= "table" then
        return
    end

    local diagnostics = root.Diagnostics
    if diagnostics and type(diagnostics.DebugIfEnabled) == "function" then
        diagnostics:DebugIfEnabled(MODULE_TAG, "Loaded passthrough layout module")
    end
end

function Layout.ComputeHeight(_, currentHeightFallback)
    if currentHeightFallback ~= nil then
        return currentHeightFallback
    end

    return 0
end

function Layout.Apply(_, _, currentHeightFallback)
    if currentHeightFallback ~= nil then
        return currentHeightFallback
    end

    return 0
end

logLoaded()

Nvk3UT.AchievementTrackerLayout = Layout

return Layout
