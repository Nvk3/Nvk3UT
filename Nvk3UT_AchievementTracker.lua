local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local AchievementTracker = {}
AchievementTracker.__index = AchievementTracker

local MODULE_NAME = addonName .. "AchievementTracker"

local unpack = table.unpack or unpack

local function IsDebugLoggingEnabled()
    local sv = Nvk3UT and Nvk3UT.sv
    return sv and sv.debug == true
end

local function DebugLog(message, ...)
    if not IsDebugLoggingEnabled() then
        return
    end

    if select("#", ...) > 0 then
        message = string.format(tostring(message), ...)
    end

    if d then
        d(string.format("[%s] %s", MODULE_NAME, tostring(message)))
    elseif print then
        print(string.format("[%s] %s", MODULE_NAME, tostring(message)))
    end
end

local function GetController()
    local controller = Nvk3UT and Nvk3UT.AchievementTrackerController
    return controller
end

local function CallController(methodName, ...)
    local controller = GetController()
    if not controller then
        DebugLog("AchievementTrackerController missing for %s", tostring(methodName))
        return nil
    end

    local fn = controller[methodName]
    if type(fn) ~= "function" then
        DebugLog("AchievementTrackerController.%s is not callable", tostring(methodName))
        return nil
    end

    local ok, results = pcall(function(...)
        return { fn(...) }
    end, ...)

    if not ok then
        DebugLog("AchievementTrackerController.%s failed: %s", tostring(methodName), tostring(results))
        return nil
    end

    if not results then
        return nil
    end

    return unpack(results)
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
    local result = CallController("IsActive", ...)
    if result == nil then
        return true
    end
    return result
end

function AchievementTracker.ApplyHostVisibility(...)
    return CallController("ApplyHostVisibility", ...)
end

function AchievementTracker.GetContentSize(...)
    local width, height = CallController("GetContentSize", ...)
    if width == nil or height == nil then
        return 0, 0
    end
    return width, height
end

function AchievementTracker.OnAchievementProgress(...)
    return CallController("OnAchievementProgress", ...)
end

function AchievementTracker.FocusAchievement(...)
    local result = CallController("FocusAchievement", ...)
    if result == nil then
        return false
    end
    return result
end

function AchievementTracker.RefreshVisibility(...)
    return CallController("RefreshVisibility", ...)
end

setmetatable(AchievementTracker, {
    __index = function(_, key)
        local controller = GetController()
        if not controller then
            return nil
        end

        local value = controller[key]
        if type(value) == "function" then
            return function(_, ...)
                return CallController(key, ...)
            end
        end

        return value
    end,
})

Nvk3UT.AchievementTracker = AchievementTracker

return AchievementTracker
