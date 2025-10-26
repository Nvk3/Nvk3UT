local addonName = "Nvk3UT"

local NS = addonName .. "_QuestEvents"

Nvk3UT_QuestUpdateScheduler = Nvk3UT_QuestUpdateScheduler or {
    pending = {},
    queue = {},
    queueSet = {},
    processing = false,
    timerActive = false,
    DEBOUNCE_MS = 100,
}

local scheduler = Nvk3UT_QuestUpdateScheduler

local function ProcessNextPendingQuest()
    local queue = scheduler.queue
    local nextIndex = queue and queue[1]

    if not nextIndex then
        scheduler.processing = false
        return
    end

    table.remove(queue, 1)
    scheduler.queueSet[nextIndex] = nil

    if type(Nvk3UT_ProcessSingleQuestUpdate) == "function" then
        Nvk3UT_ProcessSingleQuestUpdate(nextIndex)
    else
        UpdateSingleQuest(nextIndex)
        RedrawSingleQuestFromLocalDB(nextIndex)
    end

    zo_callLater(ProcessNextPendingQuest, 0)
end

local function QuestUpdateScheduler_Flush()
    scheduler.timerActive = false

    local pending = scheduler.pending
    scheduler.pending = {}

    local queue = scheduler.queue
    if type(queue) ~= "table" then
        queue = {}
        scheduler.queue = queue
    end

    local queueSet = scheduler.queueSet

    for journalIndex in pairs(pending) do
        if not queueSet[journalIndex] then
            queue[#queue + 1] = journalIndex
            queueSet[journalIndex] = true
        end
    end

    if (not scheduler.processing) and (#queue > 0) then
        scheduler.processing = true
        ProcessNextPendingQuest()
    end
end

local function QuestUpdateScheduler_Request(journalIndex)
    if type(journalIndex) ~= "number" then
        return
    end

    scheduler.pending[journalIndex] = true

    if not scheduler.timerActive then
        scheduler.timerActive = true
        zo_callLater(QuestUpdateScheduler_Flush, scheduler.DEBOUNCE_MS)
    end
end

local function OnQuestConditionChanged(_, journalIndex, ...)
    QuestUpdateScheduler_Request(journalIndex)
end

local function OnQuestAdvanced(_, journalIndex, ...)
    QuestUpdateScheduler_Request(journalIndex)
end

local function OnQuestAdded(_, journalIndex, ...)
    QuestUpdateScheduler_Request(journalIndex)
end

local function OnQuestToolUpdated(_, journalIndex, ...)
    QuestUpdateScheduler_Request(journalIndex)
end

local function OnQuestRemoved(_, isCompleted, journalIndex, questName, ...)
    if type(journalIndex) ~= "number" then
        return
    end

    scheduler.pending[journalIndex] = nil
    if scheduler.queueSet[journalIndex] then
        scheduler.queueSet[journalIndex] = nil

        local queue = scheduler.queue
        for index = #queue, 1, -1 do
            if queue[index] == journalIndex then
                table.remove(queue, index)
            end
        end
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
