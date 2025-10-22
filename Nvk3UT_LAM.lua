Nvk3UT = Nvk3UT or {}
local M = Nvk3UT

M.LAM = M.LAM or {}
local Module = M.LAM

local function debugLog(message)
    if d then
        d(string.format("[Nvk3UT] LAM: %s", tostring(message)))
    end
end

local function getSettings()
    local root = M and M.sv
    if not root then
        return nil
    end
    root.settings = root.settings or {}
    root.settings.quest = root.settings.quest or {}
    root.settings.ach = root.settings.ach or {}
    root.settings.tracker = root.settings.tracker or {}
    return root.settings
end

local function publish(key)
    if M and M.Publish then
        M.Publish("settings:changed", key)
    elseif M and M.Core and M.Core.Publish then
        M.Core.Publish("settings:changed", key)
    end
end

local function normalizeKey(key)
    if type(key) ~= "string" then
        return nil
    end
    return key
end

function Module.GetSetting(key)
    key = normalizeKey(key)
    if not key then
        return nil
    end

    local settings = getSettings()
    if not settings then
        return nil
    end

    if key:find("^quest%.") then
        local quest = settings.quest
        return quest[key:sub(7)]
    elseif key:find("^ach%.") then
        local ach = settings.ach
        return ach[key:sub(5)]
    elseif key:find("^tracker%.") then
        local tracker = settings.tracker
        return tracker[key:sub(9)]
    end

    return nil
end

local function applyQuestKey(subKey, value)
    local settings = getSettings()
    local questSettings = settings and settings.quest
    if not questSettings then
        return
    end
    if questSettings[subKey] == value then
        return
    end
    questSettings[subKey] = value
    publish("quest." .. subKey)
    if subKey == "enabled" and M.Tracker and M.Tracker.SetShowQuests then
        M.Tracker.SetShowQuests(value)
    elseif subKey == "autoExpandNew" and M.Tracker and M.Tracker.SetBehaviorOption then
        M.Tracker.SetBehaviorOption("autoExpandNewQuests", value)
    elseif subKey == "tooltips" and M.Tracker and M.Tracker.SetBehaviorOption then
        M.Tracker.SetBehaviorOption("tooltips", value)
    end
end

local function applyAchKey(subKey, value)
    local settings = getSettings()
    local achSettings = settings and settings.ach
    if not achSettings then
        return
    end
    if achSettings[subKey] == value then
        return
    end
    achSettings[subKey] = value
    publish("ach." .. subKey)
    if subKey == "enabled" and M.Tracker and M.Tracker.SetShowAchievements then
        M.Tracker.SetShowAchievements(value)
    elseif subKey == "alwaysExpand" and M.Tracker and M.Tracker.SetBehaviorOption then
        M.Tracker.SetBehaviorOption("alwaysExpandAchievements", value)
    elseif subKey == "tooltips" and M.Tracker and M.Tracker.SetBehaviorOption then
        M.Tracker.SetBehaviorOption("tooltips", value)
    end
end

local function applyTrackerKey(subKey, value)
    local settings = getSettings()
    local trackerSettings = settings and settings.tracker
    if not trackerSettings then
        return
    end
    if trackerSettings[subKey] == value then
        return
    end
    trackerSettings[subKey] = value
    publish("tracker." .. subKey)
    if subKey == "hideDefault" and M.Tracker and M.Tracker.SetBehaviorOption then
        M.Tracker.SetBehaviorOption("hideDefault", value)
    elseif subKey == "hideInCombat" and M.Tracker and M.Tracker.SetBehaviorOption then
        M.Tracker.SetBehaviorOption("hideInCombat", value)
    elseif subKey == "locked" and M.Tracker and M.Tracker.SetBehaviorOption then
        M.Tracker.SetBehaviorOption("locked", value)
    elseif (subKey == "autoGrowV" or subKey == "autoGrowH") and M.Tracker and M.Tracker.SetBehaviorOption then
        M.Tracker.SetBehaviorOption(subKey, value)
    elseif subKey == "throttle" and M.Tracker and M.Tracker.SetThrottle then
        M.Tracker.SetThrottle(value)
    end
end

function Module.SetSetting(key, value)
    key = normalizeKey(key)
    if not key then
        return
    end

    if key:find("^quest%.") then
        applyQuestKey(key:sub(7), value)
        return
    end

    if key:find("^ach%.") then
        applyAchKey(key:sub(5), value)
        return
    end

    if key:find("^tracker%.") then
        applyTrackerKey(key:sub(9), value)
        return
    end

    debugLog(string.format("Unknown setting key '%s'", key))
end

function Module.Init()
    debugLog("Init() invoked")
    getSettings()
end

function Module.ForceRefresh()
    if M and M.Tracker then
        M.Tracker.MarkDirty()
    end
end

return
