local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local TrackerRuntime = {}
TrackerRuntime.__index = TrackerRuntime

local MODULE_NAME = addonName .. "TrackerRuntime"

local state = {
    lastCombatState = false,
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

local function NotifyQuestTracker(inCombat)
    local questTracker = Nvk3UT and Nvk3UT.QuestTracker
    if not questTracker then
        return
    end

    local handler = questTracker.OnCombatStateChanged
    if type(handler) ~= "function" then
        return
    end

    local ok, err = pcall(handler, inCombat)
    if not ok then
        DebugLog("QuestTracker.OnCombatStateChanged failed", tostring(err))
    end
end

function TrackerRuntime.OnCombatStateChanged(inCombat)
    local normalized = inCombat and true or false
    state.lastCombatState = normalized
    NotifyQuestTracker(normalized)
end

function TrackerRuntime.GetCombatState()
    return state.lastCombatState == true
end

Nvk3UT.TrackerRuntime = TrackerRuntime

return TrackerRuntime
