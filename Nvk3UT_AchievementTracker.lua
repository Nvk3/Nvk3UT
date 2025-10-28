local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local AchievementTracker = {}
AchievementTracker.__index = AchievementTracker

local MODULE_NAME = addonName .. "AchievementTracker"

local function GetController()
    local controller = Nvk3UT and Nvk3UT.AchievementTrackerController
    if not controller then
        error(string.format("[%s] AchievementTrackerController is not available", MODULE_NAME))
    end
    return controller
end

local function CallController(methodName, ...)
    local controller = GetController()
    local fn = controller[methodName]
    if type(fn) ~= "function" then
        error(string.format("[%s] AchievementTrackerController.%s is not a function", MODULE_NAME, tostring(methodName)))
    end
    return fn(...)
end

function AchievementTracker.Init(...)
    return CallController("Init", ...)
end

function AchievementTracker.Shutdown(...)
    return CallController("Shutdown", ...)
end

function AchievementTracker.Refresh(...)
    return CallController("Refresh", ...)
end

function AchievementTracker.RefreshNow(...)
    return CallController("RefreshNow", ...)
end

function AchievementTracker.RequestRefresh(...)
    return CallController("RequestRefresh", ...)
end

function AchievementTracker.ApplySettings(...)
    return CallController("ApplySettings", ...)
end

function AchievementTracker.ApplyTheme(...)
    return CallController("ApplyTheme", ...)
end

function AchievementTracker.SetActive(...)
    return CallController("SetActive", ...)
end

function AchievementTracker.IsActive(...)
    return CallController("IsActive", ...)
end

function AchievementTracker.ApplyHostVisibility(...)
    return CallController("ApplyHostVisibility", ...)
end

function AchievementTracker.GetContentSize(...)
    return CallController("GetContentSize", ...)
end

function AchievementTracker.OnAchievementProgress(...)
    return CallController("OnAchievementProgress", ...)
end

Nvk3UT.AchievementTracker = AchievementTracker

return AchievementTracker
