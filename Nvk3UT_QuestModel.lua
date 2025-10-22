Nvk3UT = Nvk3UT or {}
local M = Nvk3UT

M.QuestModel = M.QuestModel or {}
local Module = M.QuestModel

local EM = EVENT_MANAGER
local QUEST_MANAGER = QUEST_JOURNAL_MANAGER

local REFRESH_HANDLE = "Nvk3UT_QuestModelRefresh"
local DEFAULT_REFRESH_DELAY_MS = 150

Module.Quests = Module.Quests or { order = {}, byId = {}, categories = {} }

local function debugLog(message)
    local utils = M and M.Utils
    if utils and utils.d and M and M.sv and M.sv.debug then
        utils.d("[QuestModel]", message)
    elseif d then
        d(string.format("[Nvk3UT] QuestModel: %s", tostring(message)))
    end
end

local function getTrackerSV()
    local sv = M and M.sv and M.sv.tracker
    if not sv then
        return nil
    end

    sv.collapseState = sv.collapseState or {}
    sv.collapseState.quests = sv.collapseState.quests or {}
    sv.collapseState.zones = sv.collapseState.zones or {}
    sv.collapseState.achieves = sv.collapseState.achieves or {}

    return sv
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result1, result2, result3, result4, result5, result6, result7 = pcall(fn, ...)
    if not ok then
        return nil
    end
    return result1, result2, result3, result4, result5, result6, result7
end

local function sanitizeText(text)
    if text == nil or text == "" then
        return ""
    end
    local utils = M and M.Utils
    if utils and utils.StripLeadingIconTag then
        text = utils.StripLeadingIconTag(text)
    end
    if zo_strformat then
        return zo_strformat("<<1>>", text)
    end
    return text
end

local function formatCategoryDisplayName(rawName)
    local sanitized = sanitizeText(rawName)
    if sanitized == "" then
        local fallback = GetString and GetString(SI_QUEST_JOURNAL_GENERAL_CATEGORY)
        return fallback ~= nil and fallback ~= "" and fallback or "General"
    end
    if zo_strformat then
        if SI_QUEST_JOURNAL_CATEGORY_NAME then
            local okFmt, formatted = pcall(zo_strformat, SI_QUEST_JOURNAL_CATEGORY_NAME, sanitized)
            if okFmt and formatted and formatted ~= "" then
                return formatted
            end
        end
        local okCaps, capitalized = pcall(zo_strformat, "<<C:1>>", sanitized)
        if okCaps and capitalized and capitalized ~= "" then
            return capitalized
        end
    end
    return sanitized
end

local function getQuestDisplayIcon(displayType)
    if QUEST_JOURNAL_KEYBOARD and QUEST_JOURNAL_KEYBOARD.GetIconTexture then
        local ok, texture = pcall(QUEST_JOURNAL_KEYBOARD.GetIconTexture, QUEST_JOURNAL_KEYBOARD, displayType)
        if ok and texture and texture ~= "" then
            return texture
        end
    end
    return "EsoUI/Art/Journal/journal_tabIcon_quests_up.dds"
end

local function formatQuestLabel(name, level)
    local questName = sanitizeText(name)
    if level and level > 0 then
        return string.format("[%d] %s", level, questName)
    end
    return questName
end

local function questStepKey(questIndex, questId)
    if type(GetJournalQuestNumSteps) ~= "function" then
        return tostring(questId or questIndex or "")
    end
    local parts = {}
    local steps = safeCall(GetJournalQuestNumSteps, questIndex) or 0
    for stepIndex = 1, steps do
        local okStep,
            stepText,
            visibility,
            stepType,
            trackerComplete,
            _,
            _,
            stepOverride = pcall(GetJournalQuestStepInfo, questIndex, stepIndex)
        if okStep and not trackerComplete then
            local summary = stepOverride ~= "" and stepOverride or stepText or ""
            summary = sanitizeText(summary)
            if summary ~= "" then
                parts[#parts + 1] = string.format("%d:%s", stepIndex, summary)
            end
        end
    end
    if #parts == 0 then
        parts[#parts + 1] = "complete"
    end
    return string.format("%d:%s", questId or 0, table.concat(parts, "|"))
end

local function gatherTrackedQuestSet()
    if type(GetTrackedQuestIndices) ~= "function" then
        return nil
    end
    local ok, ... = pcall(GetTrackedQuestIndices)
    if not ok then
        return nil
    end
    local count = select("#", ...)
    local values = { ... }
    local set = {}
    for index = 1, count do
        local questIndex = values[index]
        if type(questIndex) == "number" and questIndex > 0 then
            set[questIndex] = true
        end
    end
    if next(set) then
        return set
    end
    return nil
end

local function isQuestTracked(questIndex, trackedLookup)
    if trackedLookup and trackedLookup[questIndex] then
        return true
    end
    local trackers = {
        GetJournalQuestIsTracked,
        GetIsQuestTracked,
        GetIsJournalQuestTracked,
    }
    for _, fn in ipairs(trackers) do
        if type(fn) == "function" then
            local ok, tracked = pcall(fn, questIndex)
            if ok and tracked ~= nil then
                return tracked
            end
        end
    end
    if type(IsJournalQuestStepTracked) == "function" and type(GetJournalQuestNumSteps) == "function" then
        local steps = safeCall(GetJournalQuestNumSteps, questIndex) or 0
        for stepIndex = 1, steps do
            local okStep, trackedStep = pcall(IsJournalQuestStepTracked, questIndex, stepIndex)
            if okStep and trackedStep then
                return true
            end
        end
        return false
    end
    if trackedLookup then
        return false
    end
    return true
end

local function buildQuestSteps(questIndex)
    local stepEntries = {}
    local summaries = {}
    local seenSummaries = {}
    local objectives = {}
    local steps = safeCall(GetJournalQuestNumSteps, questIndex) or 0
    for stepIndex = 1, steps do
        local okStep,
            stepText,
            visibility,
            stepType,
            trackerComplete,
            _,
            _,
            stepOverride = pcall(GetJournalQuestStepInfo, questIndex, stepIndex)
        if okStep then
            local hidden = (QUEST_STEP_VISIBILITY_HIDDEN and visibility == QUEST_STEP_VISIBILITY_HIDDEN)
            if not hidden then
                local summary = stepOverride ~= "" and stepOverride or stepText or ""
                summary = sanitizeText(summary)
                if summary ~= "" and not seenSummaries[summary] then
                    summaries[#summaries + 1] = summary
                    seenSummaries[summary] = true
                end
            end

            local conditionEntries = {}
            local numConditions = safeCall(GetJournalQuestNumConditions, questIndex, stepIndex) or 0
            for conditionIndex = 1, numConditions do
                local okCondition,
                    conditionText,
                    cur,
                    max,
                    isFail,
                    isComplete = pcall(GetJournalQuestConditionInfo, questIndex, stepIndex, conditionIndex)
                if okCondition then
                    local visible = true
                    if type(IsJournalQuestConditionVisible) == "function" then
                        local okVisible, isVisible = pcall(IsJournalQuestConditionVisible, questIndex, stepIndex, conditionIndex)
                        if okVisible then
                            visible = isVisible
                        end
                    end
                    if visible and conditionText ~= "" then
                        local normalized = sanitizeText(conditionText)
                        local conditionEntry = {
                            text = normalized,
                            current = cur,
                            max = max,
                            done = isComplete,
                            isFail = isFail,
                            stepIndex = stepIndex,
                            conditionIndex = conditionIndex,
                        }
                        conditionEntries[#conditionEntries + 1] = conditionEntry
                        if not isComplete and not isFail then
                            objectives[#objectives + 1] = {
                                text = normalized,
                                current = cur,
                                max = max,
                                stepIndex = stepIndex,
                                conditionIndex = conditionIndex,
                            }
                        end
                    end
                end
            end

            stepEntries[#stepEntries + 1] = {
                index = stepIndex,
                text = sanitizeText(stepOverride ~= "" and stepOverride or stepText or ""),
                done = trackerComplete,
                stepType = stepType,
                trackerComplete = trackerComplete,
                conditions = conditionEntries,
            }
        end
    end
    return stepEntries, summaries, objectives
end

local function buildCategoryLookup(allCategories)
    local lookup = {}
    for index, categoryData in ipairs(allCategories) do
        local name = categoryData.name or ""
        local sanitizedName = formatCategoryDisplayName(name)
        local key = string.format("cat:%d:%d", categoryData.type or 0, index)
        lookup[name] = {
            key = key,
            name = sanitizedName,
            type = categoryData.type or 0,
            orderIndex = index,
        }
    end
    return lookup
end

local function ensureCategory(lookup, orderCounter, categoryName, categoryType)
    local key = categoryName ~= "" and categoryName or "__general__"
    local data = lookup[key]
    if data then
        return data, orderCounter
    end
    orderCounter = orderCounter + 1
    data = {
        key = string.format("cat:%d:%d", categoryType or 999, orderCounter),
        name = formatCategoryDisplayName(categoryName ~= "" and categoryName or ""),
        type = categoryType or 999,
        orderIndex = orderCounter,
    }
    lookup[key] = data
    return data, orderCounter
end

function Module.Scan()
    Module.Quests = Module.Quests or { order = {}, byId = {}, categories = {} }
    Module.Quests.order = {}
    Module.Quests.byId = {}
    Module.Quests.categories = {}

    if not (QUEST_MANAGER and QUEST_MANAGER.GetQuestListData) then
        debugLog("Quest journal manager unavailable")
        return Module.Quests
    end

    local okData, allQuests, allCategories = pcall(QUEST_MANAGER.GetQuestListData, QUEST_MANAGER)
    if not okData or type(allQuests) ~= "table" or type(allCategories) ~= "table" then
        debugLog("Failed to retrieve quest list data")
        return Module.Quests
    end

    local trackedLookup = gatherTrackedQuestSet()
    local trackerSV = getTrackerSV()
    local collapseLookup = trackerSV and trackerSV.collapseState and trackerSV.collapseState.quests or nil
    local categoryLookup = buildCategoryLookup(allCategories)
    local orderCounter = #allCategories

    local GENERAL = formatCategoryDisplayName("")

    for _, questData in ipairs(allQuests) do
        local questIndex = questData.questIndex
        if questIndex and isQuestTracked(questIndex, trackedLookup) then
            local questId = questData.questId or safeCall(GetJournalQuestId, questIndex) or 0
            local rawName = questData.name or questData.questName or ""
            local questName = sanitizeText(rawName)
            if questName == "" then
                questName = sanitizeText(select(1, safeCall(GetJournalQuestName, questIndex)) or "")
            end

            local categoryName = questData.categoryName or GENERAL
            local categoryType = questData.categoryType or 0
            local categoryEntry, newCounter = ensureCategory(categoryLookup, orderCounter, categoryName, categoryType)
            orderCounter = newCounter

            local steps, summaries, objectives = buildQuestSteps(questIndex)
            local stepText = summaries[1]
            if not stepText or stepText == "" then
                stepText = sanitizeText(
                    questData.trackerOverrideText or questData.stepText or questData.conditionText or ""
                )
            end

            local questKey = questStepKey(questIndex, questId)
            local entry = {
                id = questId,
                questId = questId,
                key = questKey,
                journalIndex = questIndex,
                title = questName,
                name = questName,
                displayName = formatQuestLabel(questName, questData.level),
                zoneName = categoryEntry.name ~= "" and categoryEntry.name or GENERAL,
                zoneKey = categoryEntry.key,
                zoneType = categoryEntry.type,
                zoneOrderIndex = categoryEntry.orderIndex,
                zoneIcon = "EsoUI/Art/Journal/journal_tabIcon_locations_up.dds",
                isComplete = questData.isComplete or false,
                isTracked = true,
                isCollapsed = collapseLookup and collapseLookup[questKey] == true or false,
                objectives = objectives,
                steps = steps,
                stepSummaries = summaries,
                stepText = stepText,
                icon = getQuestDisplayIcon(questData.displayType),
                order = questData.sortOrder or questIndex,
                level = questData.level,
                displayType = questData.displayType,
                updatedAt = GetFrameTimeMilliseconds and GetFrameTimeMilliseconds() or GetTimeStamp(),
                priorityScore = questData.sortOrder or questIndex,
            }

            Module.Quests.byId[questKey] = entry
            Module.Quests.order[#Module.Quests.order + 1] = questKey
        end
    end

    return Module.Quests
end

function Module.GetList()
    if not Module.Quests or not Module.Quests.order then
        Module.Scan()
    end
    return Module.Quests.order or {}, Module.Quests.byId or {}
end

function Module.ForceRefresh()
    if EM and EM.UnregisterForUpdate then
        EM:UnregisterForUpdate(REFRESH_HANDLE)
    end
    Module.refreshPending = false
    Module.dirty = false
    Module.Scan()
    if M.Publish then
        M.Publish("quests:changed", Module.Quests)
    elseif M.Core and M.Core.Publish then
        M.Core.Publish("quests:changed", Module.Quests)
    end
end

function Module.ThrottledRefresh()
    if Module.refreshPending then
        return
    end
    Module.refreshPending = true
    local delay = DEFAULT_REFRESH_DELAY_MS
    local trackerSV = M and M.sv and M.sv.tracker
    if trackerSV and trackerSV.throttleMs then
        delay = tonumber(trackerSV.throttleMs) or delay
    end

    local function callback()
        Module.refreshPending = false
        if Module.dirty then
            Module.ForceRefresh()
        end
    end

    if EM and EM.RegisterForUpdate then
        EM:RegisterForUpdate(REFRESH_HANDLE, delay, function()
            if EM.UnregisterForUpdate then
                EM:UnregisterForUpdate(REFRESH_HANDLE)
            end
            callback()
        end)
    else
        zo_callLater(callback, delay)
    end
end

local function handleQuestUpdate()
    Module.dirty = true
    Module.ThrottledRefresh()
end

function Module.Init()
    debugLog("Init() invoked")
    Module.dirty = true
    if not EM then
        Module.ForceRefresh()
        return
    end

    EM:UnregisterForEvent("Nvk3UT_QuestModel_Activated", EVENT_PLAYER_ACTIVATED)
    EM:RegisterForEvent("Nvk3UT_QuestModel_Activated", EVENT_PLAYER_ACTIVATED, handleQuestUpdate)
    EM:UnregisterForEvent("Nvk3UT_QuestModel_QuestAdded", EVENT_QUEST_ADDED)
    EM:RegisterForEvent("Nvk3UT_QuestModel_QuestAdded", EVENT_QUEST_ADDED, handleQuestUpdate)
    EM:UnregisterForEvent("Nvk3UT_QuestModel_QuestRemoved", EVENT_QUEST_REMOVED)
    EM:RegisterForEvent("Nvk3UT_QuestModel_QuestRemoved", EVENT_QUEST_REMOVED, handleQuestUpdate)
    EM:UnregisterForEvent("Nvk3UT_QuestModel_QuestAdvanced", EVENT_QUEST_ADVANCED)
    EM:RegisterForEvent("Nvk3UT_QuestModel_QuestAdvanced", EVENT_QUEST_ADVANCED, handleQuestUpdate)
    EM:UnregisterForEvent("Nvk3UT_QuestModel_ConditionChanged", EVENT_QUEST_CONDITION_COUNTER_CHANGED)
    EM:RegisterForEvent(
        "Nvk3UT_QuestModel_ConditionChanged",
        EVENT_QUEST_CONDITION_COUNTER_CHANGED,
        handleQuestUpdate
    )
    EM:UnregisterForEvent("Nvk3UT_QuestModel_PlayerCombat", EVENT_PLAYER_COMBAT_STATE)
    EM:RegisterForEvent("Nvk3UT_QuestModel_PlayerCombat", EVENT_PLAYER_COMBAT_STATE, function()
        handleQuestUpdate()
    end)
    EM:UnregisterForEvent("Nvk3UT_QuestModel_ObjectiveCompleted", EVENT_OBJECTIVE_COMPLETED)
    EM:RegisterForEvent("Nvk3UT_QuestModel_ObjectiveCompleted", EVENT_OBJECTIVE_COMPLETED, handleQuestUpdate)

    Module.ForceRefresh()
end

function Module.SetTracked(questKey, shouldTrack)
    if not questKey then
        return
    end

    local quests = Module.Quests or {}
    local quest = quests.byId and quests.byId[questKey]
    if not quest then
        return
    end

    if shouldTrack == nil then
        shouldTrack = not (quest.isTracked ~= false)
    end

    quest.isTracked = shouldTrack and true or false

    local journalIndex = quest.journalIndex
    if journalIndex then
        local applied = false
        if QUEST_MANAGER and QUEST_MANAGER.SetQuestIsTracked then
            local ok = pcall(QUEST_MANAGER.SetQuestIsTracked, QUEST_MANAGER, journalIndex, shouldTrack)
            applied = applied or ok
        end
        if type(SetTrackedIsTracked) == "function" then
            local ok = pcall(SetTrackedIsTracked, journalIndex, shouldTrack)
            applied = applied or ok
        end
        if shouldTrack and type(SetTrackedQuestIndex) == "function" then
            pcall(SetTrackedQuestIndex, journalIndex)
        end
        if not applied and QUEST_MANAGER and QUEST_MANAGER.SetQuestStepIsTracked and type(quest.steps) == "table" then
            for _, step in ipairs(quest.steps) do
                if step.index then
                    pcall(QUEST_MANAGER.SetQuestStepIsTracked, QUEST_MANAGER, journalIndex, step.index, shouldTrack)
                end
            end
        end
    end

    Module.ForceRefresh()
end

return
