local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local ResolveQuestCategory

local QUEST_JOURNAL_CAP = rawget(_G, "MAX_JOURNAL_QUESTS") or 25

local function StripProgressDecorations(text)
    if type(text) ~= "string" then
        return nil
    end

    local sanitized = text
    sanitized = sanitized:gsub("%s*%(%s*%d+%s*/%s*%d+%s*%)", "")
    sanitized = sanitized:gsub("%s*%[%s*%d+%s*/%s*%d+%s*%]", "")
    sanitized = sanitized:gsub("%s+", " ")
    sanitized = sanitized:gsub("^%s+", "")
    sanitized = sanitized:gsub("%s+$", "")

    if sanitized == "" then
        return nil
    end

    return sanitized
end

local function NormalizeObjectiveDisplayText(text)
    if type(text) ~= "string" then
        return nil
    end

    local displayText = text
    if zo_strformat then
        displayText = zo_strformat("<<1>>", displayText)
    end

    displayText = displayText:gsub("\r\n", "\n")
    displayText = displayText:gsub("\r", "\n")
    displayText = displayText:gsub("\t", " ")
    displayText = displayText:gsub("\n+", " ")
    displayText = displayText:gsub("^%s+", "")
    displayText = displayText:gsub("%s+$", "")

    if displayText == "" then
        return nil
    end

    return displayText
end

local function ShouldUseHeaderText(candidate, objectives)
    if type(candidate) ~= "string" then
        return nil
    end

    local headerText = candidate
    headerText = headerText:gsub("%s+", " ")
    headerText = headerText:gsub("^%s+", "")
    headerText = headerText:gsub("%s+$", "")

    if headerText == "" then
        return nil
    end

    if #headerText > 140 then
        return nil
    end

    local sentenceCount = 0
    headerText:gsub("[%.%!%?]", function()
        sentenceCount = sentenceCount + 1
    end)
    if sentenceCount >= 2 and #headerText > 80 then
        return nil
    end

    if objectives and type(objectives) == "table" then
        local headerLower = string.lower(headerText)
        for index = 1, #objectives do
            local objective = objectives[index]
            local displayText = objective and objective.displayText
            if type(displayText) == "string" then
                local comparison = string.lower(displayText)
                if comparison == headerLower then
                    return nil
                end
            end
        end
    end

    return headerText
end

local function AcquireTimestampMs()
    if type(GetFrameTimeMilliseconds) == "function" then
        return GetFrameTimeMilliseconds()
    end

    if type(GetGameTimeMilliseconds) == "function" then
        return GetGameTimeMilliseconds()
    end

    if type(GetFrameTimeSeconds) == "function" then
        local seconds = GetFrameTimeSeconds()
        if type(seconds) == "number" then
            return math.floor(seconds * 1000 + 0.5)
        end
    end

    return nil
end

local function CollectActiveObjectives(journalIndex, questIsComplete)
    if type(GetJournalQuestNumSteps) ~= "function" or type(GetJournalQuestStepInfo) ~= "function" then
        return {}, nil
    end

    -- Collect every visible condition across all steps so the tracker mirrors the journal "Objectives" list.
    local objectiveList = {}
    local seen = {}
    local fallbackStepText = nil
    local fallbackObjectiveText = nil

    local numSteps = GetJournalQuestNumSteps(journalIndex)
    if type(numSteps) ~= "number" or numSteps <= 0 then
        return objectiveList, fallbackStepText
    end

    for stepIndex = 1, numSteps do
        local stepText, visibility, _, trackerOverrideText, stepNumConditions = GetJournalQuestStepInfo(journalIndex, stepIndex)
        local sanitizedOverrideText = StripProgressDecorations(trackerOverrideText)
        local sanitizedStepText = StripProgressDecorations(stepText)
        local fallbackObjectiveCandidate = nil

        local stepIsVisible = true
        if visibility ~= nil then
            local hiddenConstant = rawget(_G, "QUEST_STEP_VISIBILITY_HIDDEN")
            if hiddenConstant ~= nil then
                stepIsVisible = (visibility ~= hiddenConstant)
            else
                stepIsVisible = (visibility ~= false)
            end
        end

        if questIsComplete and not stepIsVisible then
            -- Completed quests sometimes hide their final step even though the journal still shows the hand-in objective.
            stepIsVisible = true
        end

        if stepIsVisible then
            local fallbackStepCandidate = sanitizedOverrideText or sanitizedStepText
            if not fallbackStepText and fallbackStepCandidate then
                fallbackStepText = fallbackStepCandidate
            end

            fallbackObjectiveCandidate = NormalizeObjectiveDisplayText(trackerOverrideText) or NormalizeObjectiveDisplayText(stepText)
            if not fallbackObjectiveText and fallbackObjectiveCandidate then
                fallbackObjectiveText = fallbackObjectiveCandidate
            end

            local addedObjectiveForStep = false

            local totalConditions = tonumber(stepNumConditions) or 0
            if type(GetJournalQuestNumConditions) == "function" then
                local countedConditions = GetJournalQuestNumConditions(journalIndex, stepIndex)
                if type(countedConditions) == "number" and countedConditions > totalConditions then
                    totalConditions = countedConditions
                end
            end

            if totalConditions > 0 and type(GetJournalQuestConditionInfo) == "function" then
                for conditionIndex = 1, totalConditions do
                    local conditionText, current, maxValue, isFailCondition, isConditionComplete, _, isConditionVisible = GetJournalQuestConditionInfo(journalIndex, stepIndex, conditionIndex)
                    local formattedCondition = NormalizeObjectiveDisplayText(conditionText)
                    local isVisibleCondition = (isConditionVisible ~= false)
                    if questIsComplete and not isVisibleCondition then
                        -- Some quests hide the final hand-in objective once the quest is flagged complete.
                        -- We still want to surface those lines so the tracker mirrors the journal UI.
                        isVisibleCondition = true
                    end
                    local isFail = (isFailCondition == true)

                    if formattedCondition and isVisibleCondition and not isFail then
                        addedObjectiveForStep = true

                        if not seen[formattedCondition] then
                            seen[formattedCondition] = true
                            objectiveList[#objectiveList + 1] = {
                                displayText = formattedCondition,
                                current = tonumber(current) or 0,
                                max = tonumber(maxValue) or 0,
                                complete = isConditionComplete == true,
                                isTurnIn = false,
                            }
                        end
                    end
                end
            end

            if not addedObjectiveForStep and fallbackObjectiveCandidate and not seen[fallbackObjectiveCandidate] then
                seen[fallbackObjectiveCandidate] = true
                objectiveList[#objectiveList + 1] = {
                    displayText = fallbackObjectiveCandidate,
                    current = 0,
                    max = 0,
                    complete = false,
                    isTurnIn = false,
                }
                addedObjectiveForStep = true
            end
        end
    end

    if #objectiveList == 0 and fallbackObjectiveText and not seen[fallbackObjectiveText] then
        objectiveList[1] = {
            displayText = fallbackObjectiveText,
            current = 0,
            max = 0,
            complete = false,
            isTurnIn = false,
        }
    end

    return objectiveList, fallbackStepText
end

local function DetermineCategoryInfo(journalIndex, questType, displayType, isRepeatable, isDaily)
    local categoryKey, categoryName, parentKey, parentName

    if type(ResolveQuestCategory) == "function" then
        local category = ResolveQuestCategory(journalIndex, questType, displayType, isRepeatable, isDaily)
        if type(category) == "table" then
            categoryKey = category.key or category.groupKey or category.categoryKey
            categoryName = category.name or category.groupName or category.categoryName

            if type(category.parent) == "table" then
                parentKey = category.parent.key or category.parent.categoryKey
                parentName = category.parent.name or category.parent.categoryName
            elseif category.groupKey and category.groupName then
                parentKey = category.groupKey
                parentName = category.groupName
            end
        end
    end

    if (not categoryKey or categoryKey == "") and type(GetCategoryKey) == "function" then
        categoryKey = GetCategoryKey(questType, displayType, isRepeatable, isDaily)
    end

    if (not categoryName or categoryName == "") and categoryKey then
        local readable = categoryKey:gsub("_", " ")
        readable = readable:gsub("%s+", " ")
        if type(zo_strformat) == "function" then
            categoryName = zo_strformat("<<1>>", readable)
        else
            categoryName = readable
        end
    end

    parentKey = parentKey or categoryKey
    parentName = parentName or categoryName

    return categoryKey, categoryName, parentKey, parentName
end

local function IsValidQuestJournalIndex(journalIndex)
    if type(journalIndex) ~= "number" then
        return false
    end

    if journalIndex < 1 or journalIndex > QUEST_JOURNAL_CAP then
        return false
    end

    if type(GetJournalQuestInfo) == "function" then
        local ok, questName = pcall(GetJournalQuestInfo, journalIndex)
        if ok and type(questName) == "string" and questName ~= "" then
            return true
        end
    end

    if type(GetJournalQuestName) == "function" then
        local ok, questName = pcall(GetJournalQuestName, journalIndex)
        if ok and type(questName) == "string" and questName ~= "" then
            return true
        end
    end

    return false
end

-- LocalQuestDB stores the lightweight runtime quest state used by the tracker.
LocalQuestDB = LocalQuestDB or {
    quests = {},
    version = 0,
}

-- Build a lightweight quest record for a single quest journalIndex using live journal data.
function BuildQuestRecordFromAPI(journalIndex)
    if not IsValidQuestJournalIndex(journalIndex) then
        return nil
    end

    if type(GetJournalQuestInfo) ~= "function" then
        return nil
    end

    local ok, questName, _, activeStepText, _, _, _, questType, _, isRepeatable, isDaily, _, displayType = pcall(GetJournalQuestInfo, journalIndex)
    if not ok or type(questName) ~= "string" or questName == "" then
        return nil
    end

    local sanitizedName = StripProgressDecorations(questName) or questName
    local sanitizedHeader = StripProgressDecorations(activeStepText)

    local tracked = false
    if type(IsJournalQuestTracked) == "function" then
        tracked = IsJournalQuestTracked(journalIndex) == true
    end

    local assisted = false
    if tracked and type(GetTrackedIsAssisted) == "function" and rawget(_G, "TRACK_TYPE_QUEST") ~= nil then
        assisted = GetTrackedIsAssisted(TRACK_TYPE_QUEST, journalIndex) == true
    end

    local isComplete = false
    if type(GetJournalQuestIsComplete) == "function" then
        isComplete = GetJournalQuestIsComplete(journalIndex) == true
    elseif type(IsJournalQuestComplete) == "function" then
        isComplete = IsJournalQuestComplete(journalIndex) == true
    end

    local objectives, fallbackStepText = CollectActiveObjectives(journalIndex, isComplete)
    local lastStepText = fallbackStepText or sanitizedHeader

    if isComplete then
        local markedTurnIn = false
        for index = 1, #objectives do
            local objective = objectives[index]
            if not objective.complete then
                objective.isTurnIn = true
                objective.complete = false
                markedTurnIn = true
                break
            end
        end

        if not markedTurnIn and #objectives > 0 then
            objectives[1].isTurnIn = true
            objectives[1].complete = false
            markedTurnIn = true
        end

        if not markedTurnIn then
            local turnInText = sanitizedHeader or lastStepText
            turnInText = turnInText or sanitizedName
            turnInText = StripProgressDecorations(turnInText)
            if turnInText then
                objectives[1] = {
                    displayText = turnInText,
                    current = 0,
                    max = 0,
                    complete = false,
                    isTurnIn = true,
                }
            end
        end
    end

    local headerCandidate = sanitizedHeader or fallbackStepText
    local headerText = ShouldUseHeaderText(headerCandidate, objectives)

    local categoryKey, categoryName, parentKey, parentName = DetermineCategoryInfo(journalIndex, questType, displayType, isRepeatable == true, isDaily == true)

    local record = {
        journalIndex = journalIndex,
        name = sanitizedName,
        headerText = headerText,
        objectives = objectives, -- each entry stores displayText/current/max/complete/isTurnIn
        tracked = tracked,
        assisted = assisted,
        isComplete = isComplete,
        categoryKey = categoryKey,
        categoryName = categoryName,
        parentKey = parentKey,
        parentName = parentName,
        lastUpdateMs = AcquireTimestampMs(),
    }

    if d then
        d(string.format("[Nvk3UT] BuildQuestRecordFromAPI(%d) -> %s", journalIndex, tostring(record.name)))
    end

    return record
end

-- Rebuild the entire LocalQuestDB with the current quest journal snapshot.
function FullSync()
    LocalQuestDB.quests = {}

    local maxSlots = QUEST_JOURNAL_CAP
    for journalIndex = 1, maxSlots do
        if IsValidQuestJournalIndex(journalIndex) then
            local questRecord = BuildQuestRecordFromAPI(journalIndex)
            if questRecord then
                LocalQuestDB.quests[journalIndex] = questRecord
            end
        end
    end

    LocalQuestDB.version = (LocalQuestDB.version or 0) + 1

    if d then
        local questCount = 0
        for _ in pairs(LocalQuestDB.quests) do
            questCount = questCount + 1
        end

        d(string.format("[Nvk3UT] FullSync() completed. LocalQuestDB.version = %d", LocalQuestDB.version))
        d(string.format("[Nvk3UT] Quests synced: %d", questCount))
    end

end

function UpdateSingleQuest(journalIndex)
    LocalQuestDB = LocalQuestDB or { quests = {}, version = 0 }

    local isValid = true
    if type(IsValidQuestJournalIndex) == "function" then
        isValid = IsValidQuestJournalIndex(journalIndex)
    end

    if isValid then
        local questRecord = BuildQuestRecordFromAPI(journalIndex)
        if questRecord then
            LocalQuestDB.quests[journalIndex] = questRecord
        else
            LocalQuestDB.quests[journalIndex] = nil
        end
    else
        LocalQuestDB.quests[journalIndex] = nil
    end

    LocalQuestDB.version = (LocalQuestDB.version or 0) + 1

    if d then
        d(string.format("[Nvk3UT] UpdateSingleQuest(%s) -> version %s", tostring(journalIndex), tostring(LocalQuestDB.version)))
    end

end

function RemoveQuestFromLocalQuestDB(journalIndex)
    LocalQuestDB = LocalQuestDB or { quests = {}, version = 0 }

    LocalQuestDB.quests[journalIndex] = nil
    LocalQuestDB.version = (LocalQuestDB.version or 0) + 1

    if d then
        d(string.format("[Nvk3UT] RemoveQuestFromLocalQuestDB(%s) -> version %s", tostring(journalIndex), tostring(LocalQuestDB.version)))
    end

end

function RedrawQuestTrackerFromLocalDB(context)
    if Nvk3UT and Nvk3UT.QuestTracker and Nvk3UT.QuestTracker.RedrawQuestTrackerFromLocalDB then
        local finalContext = context or {
            trigger = "event",
            source = "QuestEvents:RedrawQuestTracker",
        }
        Nvk3UT.QuestTracker.RedrawQuestTrackerFromLocalDB(finalContext)
    end
end

function RedrawSingleQuestFromLocalDB(journalIndex, context)
    if Nvk3UT and Nvk3UT.QuestTracker and Nvk3UT.QuestTracker.RedrawSingleQuestFromLocalDB then
        local finalContext = context or {
            trigger = "event",
            source = "QuestEvents:RedrawSingleQuest",
        }
        Nvk3UT.QuestTracker.RedrawSingleQuestFromLocalDB(journalIndex, finalContext)
    end
end

local QuestModel = {}
QuestModel.__index = QuestModel

local function BuildSnapshotForUI()
    local snapshot = { quests = {} }
    local questSource = LocalQuestDB and LocalQuestDB.quests
    if type(questSource) ~= "table" then
        return snapshot
    end

    for _, record in pairs(questSource) do
        snapshot.quests[#snapshot.quests + 1] = record
    end

    table.sort(snapshot.quests, function(left, right)
        local nameA = string.lower(left and left.name or "")
        local nameB = string.lower(right and right.name or "")
        if nameA == nameB then
            return (left and left.journalIndex or 0) < (right and right.journalIndex or 0)
        end
        return nameA < nameB
    end)

    return snapshot
end

function QuestModel.Init(opts)
    if QuestModel.isInitialized then
        return
    end

    QuestModel.isInitialized = true
    QuestModel.debugEnabled = opts and opts.debug == true

    FullSync()
    RedrawQuestTrackerFromLocalDB({
        trigger = "init",
        source = "QuestModel:Init",
    })
end

function QuestModel.Shutdown()
    QuestModel.isInitialized = false
end

function QuestModel.GetSnapshot()
    return BuildSnapshotForUI()
end
Nvk3UT.QuestModel = QuestModel

return QuestModel
