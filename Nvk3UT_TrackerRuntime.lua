--[[
    Nvk3UT_TrackerRuntime.lua

    TrackerRuntime is the host-facing runtime that owns shared tracker state
    and visibility behavior. It receives normalized ESO events from
    Nvk3UT_EventHandler and decides when the tracker host and its children
    should react. This module does **not** perform any throttling, batching,
    debounce, or coordinator work yet – it simply mirrors the timing from the
    working main branch while centralizing ownership of host-level decisions.
]]

local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local TrackerRuntime = {}
TrackerRuntime.__index = TrackerRuntime

local MODULE_NAME = addonName .. "TrackerRuntime"

local TRACKER_KEYS = {
    quest = "QuestTracker",
    achievement = "AchievementTracker",
}

local state = {
    hostControl = nil,
    lastCombatState = false,
    quest = {
        tracker = nil,
        control = nil,
        hidden = false,
    },
    achievement = {
        tracker = nil,
        control = nil,
        hidden = false,
    },
}

local function IsDebugLoggingEnabled()
    local sv = Nvk3UT and Nvk3UT.sv
    return sv and sv.debug == true
end

local function DebugLog(...)
    if not IsDebugLoggingEnabled() then
        return
    end

    if d then
        d(string.format("[%s]", MODULE_NAME), ...)
    elseif print then
        print("[" .. MODULE_NAME .. "]", ...)
    end
end

local function SafeCall(description, func, ...)
    if type(func) ~= "function" then
        return nil, nil
    end

    local ok, result = pcall(func, ...)
    if not ok then
        DebugLog(string.format("%s failed: %s", description or "callback", tostring(result)))
        return nil, result
    end

    return result, nil
end

local function ResolveTrackerModule(key)
    local trackerState = state[key]
    if trackerState and trackerState.tracker then
        return trackerState.tracker
    end

    local globalName = TRACKER_KEYS[key]
    local tracker = globalName and Nvk3UT and Nvk3UT[globalName]
    if trackerState then
        trackerState.tracker = tracker
    end
    return tracker
end

local function ApplyVisibility(trackerKey, hidden, reason)
    local trackerState = state[trackerKey]
    if not trackerState then
        return
    end

    local normalizedHidden = hidden and true or false
    if trackerState.hidden == normalizedHidden then
        return
    end

    trackerState.hidden = normalizedHidden

    local tracker = ResolveTrackerModule(trackerKey)
    if tracker and tracker.ApplyHostVisibility then
        SafeCall(string.format("%s.ApplyHostVisibility", TRACKER_KEYS[trackerKey] or trackerKey), tracker.ApplyHostVisibility, normalizedHidden, reason)
        return
    end

    local control = trackerState.control
    if control and control.SetHidden then
        control:SetHidden(normalizedHidden)
    end
end

local function IsTrackerActive(trackerKey)
    local tracker = ResolveTrackerModule(trackerKey)
    if not tracker or type(tracker.IsActive) ~= "function" then
        return true
    end

    local result = SafeCall(string.format("%s.IsActive", TRACKER_KEYS[trackerKey] or trackerKey), tracker.IsActive)
    if result == nil then
        return true
    end

    return result ~= false
end

local function ShouldQuestHideInCombat()
    local tracker = ResolveTrackerModule("quest")
    if not tracker or type(tracker.ShouldHideInCombat) ~= "function" then
        return false
    end

    local result = SafeCall("QuestTracker.ShouldHideInCombat", tracker.ShouldHideInCombat)
    return result == true
end

local function UpdateQuestVisibility(reason)
    local hidden = false
    local hiddenReason = reason or "state"

    if not IsTrackerActive("quest") then
        hidden = true
        hiddenReason = "inactive"
    elseif state.lastCombatState and ShouldQuestHideInCombat() then
        hidden = true
        hiddenReason = "combat"
    end

    ApplyVisibility("quest", hidden, hiddenReason)
end

local function UpdateAchievementVisibility(reason)
    local hidden = false
    local hiddenReason = reason or "state"

    if not IsTrackerActive("achievement") then
        hidden = true
        hiddenReason = "inactive"
    end

    ApplyVisibility("achievement", hidden, hiddenReason)
end

function TrackerRuntime.RegisterHostControls(options)
    if type(options) ~= "table" then
        options = {}
    end

    state.hostControl = options.host or state.hostControl
    state.quest.control = options.quest or state.quest.control
    state.achievement.control = options.achievement or state.achievement.control

    UpdateQuestVisibility("host-register")
    UpdateAchievementVisibility("host-register")
end

function TrackerRuntime.UnregisterHostControls()
    state.hostControl = nil
    state.quest.control = nil
    state.achievement.control = nil
    state.quest.hidden = false
    state.achievement.hidden = false
end

function TrackerRuntime.RegisterQuestTracker(options)
    if type(options) ~= "table" then
        options = {}
    end

    state.quest.tracker = options.tracker or ResolveTrackerModule("quest")
    if options.control then
        state.quest.control = options.control
    end

    UpdateQuestVisibility("register")
end

function TrackerRuntime.UnregisterQuestTracker()
    state.quest.tracker = nil
    state.quest.control = nil
    state.quest.hidden = false
end

function TrackerRuntime.RegisterAchievementTracker(options)
    if type(options) ~= "table" then
        options = {}
    end

    state.achievement.tracker = options.tracker or ResolveTrackerModule("achievement")
    if options.control then
        state.achievement.control = options.control
    end

    UpdateAchievementVisibility("register")
end

function TrackerRuntime.UnregisterAchievementTracker()
    state.achievement.tracker = nil
    state.achievement.control = nil
    state.achievement.hidden = false
end

function TrackerRuntime.UpdateQuestVisibility(reason)
    UpdateQuestVisibility(reason)
end

function TrackerRuntime.UpdateAchievementVisibility(reason)
    UpdateAchievementVisibility(reason)
end

function TrackerRuntime.UpdateAllVisibility(reason)
    UpdateQuestVisibility(reason)
    UpdateAchievementVisibility(reason)
end

local function CallRefresh(trackerKey, methodNames, reason)
    local tracker = ResolveTrackerModule(trackerKey)
    if not tracker then
        return
    end

    for index = 1, #methodNames do
        local methodName = methodNames[index]
        local func = tracker[methodName]
        if type(func) == "function" then
            SafeCall(string.format("%s.%s", TRACKER_KEYS[trackerKey] or trackerKey, methodName), func, reason)
            return
        end
    end
end

function TrackerRuntime.ForceQuestTrackerRefresh(reason)
    CallRefresh("quest", { "RequestRefresh", "Refresh" }, reason)
end

function TrackerRuntime.ForceAchievementTrackerRefresh(reason)
    CallRefresh("achievement", { "RequestRefresh", "Refresh" }, reason)
end

function TrackerRuntime.RequestFullRefresh(reason)
    TrackerRuntime.ForceQuestTrackerRefresh(reason)
    TrackerRuntime.ForceAchievementTrackerRefresh(reason)
end

function TrackerRuntime.OnCombatStateChanged(inCombat)
    local normalized = inCombat and true or false
    state.lastCombatState = normalized
    UpdateQuestVisibility("combat")
end

function TrackerRuntime.GetCombatState()
    return state.lastCombatState == true
end

Nvk3UT.TrackerRuntime = TrackerRuntime

return TrackerRuntime
