local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local QuestTracker = {}
QuestTracker.__index = QuestTracker

local MODULE_NAME = addonName .. "QuestTracker"

local function GetController()
    local controller = Nvk3UT and Nvk3UT.QuestTrackerController
    if not controller then
        error(string.format("[%s] QuestTrackerController is not available", MODULE_NAME))
    end
    return controller
end

local function CallController(methodName, ...)
    local controller = GetController()
    local fn = controller[methodName]
    if type(fn) ~= "function" then
        error(string.format("[%s] QuestTrackerController.%s is not a function", MODULE_NAME, tostring(methodName)))
    end
    return fn(...)
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
    return CallController("IsActive", ...)
end

function QuestTracker.ApplyHostVisibility(...)
    return CallController("ApplyHostVisibility", ...)
end

function QuestTracker.GetContentSize(...)
    return CallController("GetContentSize", ...)
end

function QuestTracker.OnTrackedQuestUpdate(...)
    return CallController("OnTrackedQuestUpdate", ...)
end

function QuestTracker.OnPlayerActivated(...)
    return CallController("OnPlayerActivated", ...)
end

function QuestTracker.OnQuestChanged(...)
    return CallController("OnQuestChanged", ...)
end

function QuestTracker.OnQuestProgress(...)
    return CallController("OnQuestProgress", ...)
end

Nvk3UT.QuestTracker = QuestTracker

return QuestTracker
