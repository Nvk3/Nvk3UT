--[[
    Nvk3UT_EventHandler.lua
    This module is the single source of truth for registering ESO API events that affect the addon.
    It normalizes ESO callbacks (quests, achievements, combat state, etc.) and forwards them to the
    appropriate subsystem controllers and runtimes.
    It never touches UI controls directly, performs no layout work, and introduces no batching or
    performance throttling. The name avoids "Tracker" on purpose so future systems beyond the
    trackers (custom achievements, endeavors, and more) can share the same dispatch layer.
]]

local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local EventHandler = {}
EventHandler.__index = EventHandler

local MODULE_NAME = addonName .. "EventHandler"
local EVENT_NAMESPACE = MODULE_NAME .. "_"

local state = {
    isInitialized = false,
    eventsRegistered = false,
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

local function Dispatch(target, methodName, ...)
    if not target then
        return
    end

    local handler = target[methodName]
    if type(handler) ~= "function" then
        return
    end

    local ok, err = pcall(handler, ...)
    if not ok then
        DebugLog(string.format("Handler %s failed: %s", tostring(methodName), tostring(err)))
    end
end

local function HandleQuestChanged(eventCode, ...)
    Dispatch(Nvk3UT and Nvk3UT.QuestModel, "OnQuestChanged", eventCode, ...)
    Dispatch(Nvk3UT and Nvk3UT.QuestTrackerController, "OnQuestChanged", eventCode, ...)

    if eventCode == EVENT_QUEST_CONDITION_COUNTER_CHANGED or eventCode == EVENT_QUEST_ADVANCED then
        Dispatch(Nvk3UT and Nvk3UT.QuestTrackerController, "OnQuestProgress", eventCode, ...)
    end
end

local function HandleTrackingUpdate(eventCode, trackingType, context)
    Dispatch(Nvk3UT and Nvk3UT.QuestModel, "OnTrackingUpdate", eventCode, trackingType, context)
    Dispatch(Nvk3UT and Nvk3UT.QuestTrackerController, "OnTrackedQuestUpdate", trackingType, context)
end

local function ProcessPlayerActivated()
    Dispatch(Nvk3UT and Nvk3UT.QuestModel, "OnPlayerActivated")
    Dispatch(Nvk3UT and Nvk3UT.QuestTrackerController, "OnPlayerActivated")
end

local function HandlePlayerActivated()
    ProcessPlayerActivated()
end

-- Combat visibility is routed through the TrackerRuntime so the host can
-- apply policies like hide-in-combat across every child tracker.
local function HandleCombatState(_, inCombat)
    Dispatch(Nvk3UT and Nvk3UT.TrackerRuntime, "OnCombatStateChanged", inCombat)
end

local function HandleAchievementChanged(eventCode, ...)
    Dispatch(Nvk3UT and Nvk3UT.AchievementModel, "OnAchievementChanged", eventCode, ...)
    Dispatch(Nvk3UT and Nvk3UT.AchievementTrackerController, "OnAchievementProgress", eventCode, ...)
end

local function RegisterEvents()
    if state.eventsRegistered or not EVENT_MANAGER then
        return
    end

    local function register(key, eventId, callback)
        if not eventId then
            return
        end

        local eventName = EVENT_NAMESPACE .. key
        EVENT_MANAGER:UnregisterForEvent(eventName, eventId)
        EVENT_MANAGER:RegisterForEvent(eventName, eventId, callback)
    end

    register("QuestAdded", EVENT_QUEST_ADDED, HandleQuestChanged)
    register("QuestRemoved", EVENT_QUEST_REMOVED, HandleQuestChanged)
    register("QuestAdvanced", EVENT_QUEST_ADVANCED, HandleQuestChanged)
    register("QuestCondition", EVENT_QUEST_CONDITION_COUNTER_CHANGED, HandleQuestChanged)
    register("QuestLogUpdated", EVENT_QUEST_LOG_UPDATED, HandleQuestChanged)
    register("QuestTracking", EVENT_TRACKING_UPDATE, HandleTrackingUpdate)
    register("PlayerActivated", EVENT_PLAYER_ACTIVATED, HandlePlayerActivated)
    register("CombatState", EVENT_PLAYER_COMBAT_STATE, HandleCombatState)

    register("AchievementsUpdated", EVENT_ACHIEVEMENTS_UPDATED, HandleAchievementChanged)
    register("AchievementUpdated", EVENT_ACHIEVEMENT_UPDATED, HandleAchievementChanged)
    register("AchievementAwarded", EVENT_ACHIEVEMENT_AWARDED, HandleAchievementChanged)

    local trackedListEvent = rawget(_G, "EVENT_ACHIEVEMENT_TRACKED_LIST_UPDATED")
    if trackedListEvent then
        register("AchievementTrackedList", trackedListEvent, HandleAchievementChanged)
    end

    state.eventsRegistered = true
end

local function InitializeCurrentState()
    if type(IsUnitInCombat) == "function" then
        local ok, inCombat = pcall(IsUnitInCombat, "player")
        if ok then
            Dispatch(Nvk3UT and Nvk3UT.TrackerRuntime, "OnCombatStateChanged", inCombat)
        end
    end

    if type(IsPlayerActivated) == "function" then
        local ok, activated = pcall(IsPlayerActivated)
        if ok and activated then
            ProcessPlayerActivated()
        end
    end
end

function EventHandler.Init()
    if state.isInitialized then
        return
    end

    RegisterEvents()
    InitializeCurrentState()

    state.isInitialized = true
end

function EventHandler.OnEndeavorProgressChanged(...)
    -- Placeholder for future Endeavor systems.
end

function EventHandler.OnCustomAchievementCategoryChanged(...)
    -- Placeholder for future custom achievement category systems.
end

Nvk3UT.EventHandler = EventHandler

return EventHandler
