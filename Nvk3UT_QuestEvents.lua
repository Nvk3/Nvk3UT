local addonName = "Nvk3UT"

local NS = addonName .. "_QuestEvents"

local function OnQuestConditionChanged(_, journalIndex, ...)
    if type(journalIndex) ~= "number" then
        return
    end

    UpdateSingleQuest(journalIndex)
    RedrawSingleQuestFromLocalDB(journalIndex)
end

local function OnQuestAdvanced(_, journalIndex, ...)
    if type(journalIndex) ~= "number" then
        return
    end

    UpdateSingleQuest(journalIndex)
    RedrawSingleQuestFromLocalDB(journalIndex)
end

local function OnQuestAdded(_, journalIndex, ...)
    if type(journalIndex) ~= "number" then
        return
    end

    UpdateSingleQuest(journalIndex)
    RedrawSingleQuestFromLocalDB(journalIndex)
end

local function OnQuestToolUpdated(_, journalIndex, ...)
    if type(journalIndex) ~= "number" then
        return
    end

    UpdateSingleQuest(journalIndex)
    RedrawSingleQuestFromLocalDB(journalIndex)
end

local function OnQuestRemoved(_, isCompleted, journalIndex, questName, ...)
    if type(journalIndex) ~= "number" then
        return
    end

    RemoveQuestFromLocalQuestDB(journalIndex)
    RedrawSingleQuestFromLocalDB(journalIndex)
end

local function OnPlayerActivated(...)
    FullSync()
    RedrawQuestTrackerFromLocalDB()
    if Nvk3UT and Nvk3UT.QuestTracker and Nvk3UT.QuestTracker.HandlePlayerActivated then
        Nvk3UT.QuestTracker.HandlePlayerActivated()
    end
end

local function OnQuestListUpdated(...)
    FullSync()
    RedrawQuestTrackerFromLocalDB()
end

if not Nvk3UT_QuestEventsRegistered then
    Nvk3UT_QuestEventsRegistered = true
    EVENT_MANAGER:RegisterForEvent(NS .. "_COND", EVENT_QUEST_CONDITION_COUNTER_CHANGED, OnQuestConditionChanged)
    EVENT_MANAGER:RegisterForEvent(NS .. "_ADV", EVENT_QUEST_ADVANCED, OnQuestAdvanced)
    EVENT_MANAGER:RegisterForEvent(NS .. "_ADD", EVENT_QUEST_ADDED, OnQuestAdded)
    EVENT_MANAGER:RegisterForEvent(NS .. "_TOOL", EVENT_QUEST_TOOL_UPDATED, OnQuestToolUpdated)
    EVENT_MANAGER:RegisterForEvent(NS .. "_REM", EVENT_QUEST_REMOVED, OnQuestRemoved)
    EVENT_MANAGER:RegisterForEvent(NS .. "_PA", EVENT_PLAYER_ACTIVATED, OnPlayerActivated)
    EVENT_MANAGER:RegisterForEvent(NS .. "_LIST", EVENT_QUEST_LIST_UPDATED, OnQuestListUpdated)
end
