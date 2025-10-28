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

local QUEST_STRUCTURE_EVENTS = {
    [EVENT_QUEST_ADDED] = true,
    [EVENT_QUEST_REMOVED] = true,
    [EVENT_QUEST_ADVANCED] = true,
    [EVENT_QUEST_LOG_UPDATED] = true,
    [EVENT_QUEST_CONDITION_COUNTER_CHANGED] = true,
}

local ACHIEVEMENT_STRUCTURE_EVENTS = {
    [EVENT_ACHIEVEMENTS_UPDATED] = true,
    [EVENT_ACHIEVEMENT_UPDATED] = true,
    [EVENT_ACHIEVEMENT_AWARDED] = true,
}

local ACHIEVEMENT_TRACKED_LIST_EVENT = rawget(_G, "EVENT_ACHIEVEMENT_TRACKED_LIST_UPDATED")

if ACHIEVEMENT_TRACKED_LIST_EVENT then
    ACHIEVEMENT_STRUCTURE_EVENTS[ACHIEVEMENT_TRACKED_LIST_EVENT] = true
end

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

local function IsModuleReady(target, methodName)
    if not target then
        return false
    end

    local readiness = target.IsInitialized
    if type(readiness) == "function" then
        local ok, result = pcall(readiness, target, methodName)
        if not ok then
            DebugLog(string.format(
                "IsInitialized check failed for %s: %s",
                tostring(methodName),
                tostring(result)
            ))
            return false
        end

        if result == nil then
            return true
        end

        return result ~= false
    elseif readiness ~= nil then
        return readiness ~= false
    end

    return true
end

local function Dispatch(target, methodName, ...)
    if not target then
        return false
    end

    if not IsModuleReady(target, methodName) then
        return false
    end

    local handler = target[methodName]
    if type(handler) ~= "function" then
        return false
    end

    local ok, err = pcall(handler, ...)
    if not ok then
        DebugLog(string.format("Handler %s failed: %s", tostring(methodName), tostring(err)))
        return false
    end

    return true
end

local function HandleQuestChanged(eventCode, ...)
    local controller = Nvk3UT and Nvk3UT.QuestTrackerController
    local controllerHandled = Dispatch(controller, "OnQuestChanged", eventCode, ...)

    if eventCode == EVENT_QUEST_CONDITION_COUNTER_CHANGED or eventCode == EVENT_QUEST_ADVANCED then
        controllerHandled = Dispatch(controller, "OnQuestProgress", eventCode, ...) or controllerHandled
    end

    Dispatch(Nvk3UT and Nvk3UT.QuestModel, "OnQuestChanged", eventCode, ...)

    local reason = string.format("quest:%s", tostring(eventCode))

    if QUEST_STRUCTURE_EVENTS[eventCode] then
        Dispatch(controller, "FlagStructureDirty", reason)
        Dispatch(Nvk3UT and Nvk3UT.QuestModel, "RequestImmediateRebuild", reason)
    end

    if IsDebugLoggingEnabled() then
        DebugLog(string.format(
            "Quest event %s controllerHandled=%s -> MarkQuestDirty",
            tostring(eventCode),
            tostring(controllerHandled)
        ))
    end

    Dispatch(Nvk3UT and Nvk3UT.TrackerRuntime, "MarkQuestDirty", reason)
end

local function HandleTrackingUpdate(eventCode, trackingType, context)
    local controllerHandled = Dispatch(Nvk3UT and Nvk3UT.QuestTrackerController, "OnTrackedQuestUpdate", trackingType, context)

    Dispatch(Nvk3UT and Nvk3UT.QuestModel, "OnTrackingUpdate", eventCode, trackingType, context)

    local trackingReason = string.format("quest-tracking:%s", tostring(trackingType))
    Dispatch(Nvk3UT and Nvk3UT.QuestTrackerController, "FlagStructureDirty", trackingReason)
    Dispatch(Nvk3UT and Nvk3UT.QuestModel, "RequestImmediateRebuild", trackingReason)

    if IsDebugLoggingEnabled() then
        DebugLog(string.format(
            "Quest tracking update type=%s controllerHandled=%s -> MarkQuestDirty",
            tostring(trackingType),
            tostring(controllerHandled)
        ))
    end

    Dispatch(Nvk3UT and Nvk3UT.TrackerRuntime, "MarkQuestDirty", trackingReason)
end

local function ProcessPlayerActivated()
    Dispatch(Nvk3UT and Nvk3UT.QuestModel, "OnPlayerActivated")
    local questHandled = Dispatch(Nvk3UT and Nvk3UT.QuestTrackerController, "OnPlayerActivated")
    Dispatch(Nvk3UT and Nvk3UT.QuestTrackerController, "FlagStructureDirty", "player-activated")

    if IsDebugLoggingEnabled() then
        DebugLog(string.format("PlayerActivated questHandled=%s -> MarkQuestDirty", tostring(questHandled)))
    end

    Dispatch(Nvk3UT and Nvk3UT.TrackerRuntime, "MarkQuestDirty", "player-activated")

    local achievementHandled = Dispatch(Nvk3UT and Nvk3UT.AchievementTrackerController, "OnPlayerActivated")
    Dispatch(Nvk3UT and Nvk3UT.AchievementTrackerController, "FlagStructureDirty", "player-activated")

    if IsDebugLoggingEnabled() then
        DebugLog(string.format("PlayerActivated achievementHandled=%s -> MarkAchievementDirty", tostring(achievementHandled)))
    end

    Dispatch(Nvk3UT and Nvk3UT.TrackerRuntime, "MarkAchievementDirty", "player-activated")
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
    local controllerHandled = Dispatch(Nvk3UT and Nvk3UT.AchievementTrackerController, "OnAchievementProgress", eventCode, ...)

    Dispatch(Nvk3UT and Nvk3UT.AchievementModel, "OnAchievementChanged", eventCode, ...)

    local reason = string.format("achievement:%s", tostring(eventCode))

    if ACHIEVEMENT_STRUCTURE_EVENTS[eventCode] then
        Dispatch(Nvk3UT and Nvk3UT.AchievementTrackerController, "FlagStructureDirty", reason)
        Dispatch(Nvk3UT and Nvk3UT.AchievementModel, "RequestImmediateRebuild", reason)
    end

    if IsDebugLoggingEnabled() then
        DebugLog(string.format(
            "Achievement event %s controllerHandled=%s -> MarkAchievementDirty",
            tostring(eventCode),
            tostring(controllerHandled)
        ))
    end

    Dispatch(Nvk3UT and Nvk3UT.TrackerRuntime, "MarkAchievementDirty", reason)
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

    if ACHIEVEMENT_TRACKED_LIST_EVENT then
        register("AchievementTrackedList", ACHIEVEMENT_TRACKED_LIST_EVENT, HandleAchievementChanged)
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
