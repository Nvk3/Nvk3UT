local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local QuestTracker = {}
QuestTracker.__index = QuestTracker

local MODULE_NAME = addonName .. "QuestTracker"

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
    local controller = Nvk3UT and Nvk3UT.QuestTrackerController
    return controller
end

local function CallController(methodName, ...)
    local controller = GetController()
    if not controller then
        DebugLog("QuestTrackerController missing for %s", tostring(methodName))
        return nil
    end

    local fn = controller[methodName]
    if type(fn) ~= "function" then
        DebugLog("QuestTrackerController.%s is not callable", tostring(methodName))
        return nil
    end

    local ok, results = pcall(function(...)
        return { fn(...) }
    end, ...)

    if not ok then
        DebugLog("QuestTrackerController.%s failed: %s", tostring(methodName), tostring(results))
        return nil
    end

    if not results then
        return nil
    end

    return unpack(results)
end

function QuestTracker.Init(...)
    return CallController("Init", ...)
end

function QuestTracker.Shutdown(...)
    return CallController("Shutdown", ...)
end

function QuestTracker.Refresh(...)
    return CallController("Refresh", ...)
end

function QuestTracker.RefreshNow(...)
    return CallController("RefreshNow", ...)
end

function QuestTracker.RequestRefresh(...)
    return CallController("RequestRefresh", ...)
end

function QuestTracker.ApplySettings(...)
    return CallController("ApplySettings", ...)
end

function QuestTracker.ApplyTheme(...)
    return CallController("ApplyTheme", ...)
end

function QuestTracker.SetActive(...)
    return CallController("SetActive", ...)
end

function QuestTracker.IsActive(...)
    local result = CallController("IsActive", ...)
    if result == nil then
        return true
    end
    return result
end

function QuestTracker.ApplyHostVisibility(...)
    return CallController("ApplyHostVisibility", ...)
end

function QuestTracker.GetContentSize(...)
    local width, height = CallController("GetContentSize", ...)
    if width == nil or height == nil then
        return 0, 0
    end
    return width, height
end

function QuestTracker.OnTrackedQuestUpdate(...)
    return CallController("OnTrackedQuestUpdate", ...)
end

function QuestTracker.OnPlayerActivated(...)
    return CallController("OnPlayerActivated", ...)
end

function QuestTracker.OnQuestChanged(...)
    local results = { CallController("OnQuestChanged", ...) }
    local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
    if runtime and type(runtime.MarkQuestDirty) == "function" then
        runtime.MarkQuestDirty("quest-tracker-api")
    end
    return unpack(results)
end

function QuestTracker.OnQuestProgress(...)
    local results = { CallController("OnQuestProgress", ...) }
    local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
    if runtime and type(runtime.MarkQuestDirty) == "function" then
        runtime.MarkQuestDirty("quest-progress-api")
    end
    return unpack(results)
end

setmetatable(QuestTracker, {
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

Nvk3UT.QuestTracker = QuestTracker

return QuestTracker
