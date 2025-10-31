local ADDON = Nvk3UT
local M = (ADDON and (ADDON.QuestList or {})) or {}

if ADDON then
    ADDON.QuestList = M
end

M._list = M._list or {}
M._byKey = M._byKey or {}
M._byJournal = M._byJournal or {}
M._version = M._version or 0
M._dirty = M._dirty ~= false

-- Journal categories (rebuilt on each refresh)
M._catMap = M._catMap or nil   -- [journalIndex] = { index = ci, name = catName }
M._catOrder = M._catOrder or nil -- array of { index, name } in basegame order

local function debugLog(fmt, ...)
    if not (ADDON and ADDON.Debug) then
        return
    end

    ADDON:Debug(fmt, ...)
end

local function callESO(func, ...)
    if type(func) ~= "function" then
        return nil
    end

    local ok, result1, result2, result3, result4, result5, result6, result7, result8, result9, result10, result11 =
        pcall(func, ...)
    if not ok then
        debugLog("QuestList call failed: %s", tostring(result1))
        return nil
    end

    return result1, result2, result3, result4, result5, result6, result7, result8, result9, result10, result11
end

local function makeQuestKey(journalIndex)
    local questId = callESO(GetJournalQuestId, journalIndex)
    if questId and questId ~= 0 then
        return string.format("qid:%s", tostring(questId))
    end

    local uniqueId = callESO(GetJournalQuestUniqueId, journalIndex)
    if uniqueId then
        return string.format("uid:%s", tostring(uniqueId))
    end

    local name = callESO(GetJournalQuestName, journalIndex)
    return table.concat({ "jnl", tostring(journalIndex), tostring(name or "?") }, ":")
end

local function resetLists()
    M._list = {}
    M._byKey = {}
    M._byJournal = {}
end

-- Build journal categories in basegame order (robust on older clients)
local function buildCategoryMap()
    local map, order = {}, {}
    local numCats = callESO(GetJournalNumQuestCategories) or 0

    for ci = 1, numCats do
        local catName, numInCat = callESO(GetJournalQuestCategoryInfo, ci)
        if catName then
            table.insert(order, { index = ci, name = catName })
            if GetJournalQuestIndexFromCategory then
                for qi = 1, (numInCat or 0) do
                    local journalIndex = callESO(GetJournalQuestIndexFromCategory, ci, qi)
                    if journalIndex then
                        map[journalIndex] = { index = ci, name = catName }
                    end
                end
            end
        end
    end

    if next(map) == nil then
        local total = callESO(GetNumJournalQuests) or 0
        for j = 1, total do
            local catIdx = callESO(GetJournalQuestCategoryType, j)
            if catIdx then
                local catName = callESO(GetJournalQuestCategoryInfo, catIdx)
                map[j] = { index = catIdx, name = catName or "MISCELLANEOUS" }
                local seen
                for _, o in ipairs(order) do
                    if o.index == catIdx then
                        seen = true
                        break
                    end
                end
                if not seen then
                    table.insert(order, { index = catIdx, name = catName or "MISCELLANEOUS" })
                end
            end
        end
        table.sort(order, function(a, b)
            return (a.index or 9999) < (b.index or 9999)
        end)
    end

    return map, order
end

local function stripProgressDecorations(text)
    if type(text) ~= "string" then
        return nil
    end

    local s = text
    s = s:gsub("%s*%(%s*%d+%s*/%s*%d+%s*%)", "")
    s = s:gsub("%s*%[%s*%d+%s*/%s*%d+%s*%]", "")
    s = s:gsub("%s+", " ")
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    if s == "" then
        return nil
    end
    return s
end

local function findActiveStepIndex(journalIndex)
    local numSteps = callESO(GetJournalQuestNumSteps, journalIndex) or 0
    if numSteps <= 0 then
        return 1, nil
    end

    local hiddenConstant = rawget(_G, "QUEST_STEP_VISIBILITY_HIDDEN")

    for stepIndex = 1, numSteps do
        local stepText, visibility, _, trackerOverrideText =
            callESO(GetJournalQuestStepInfo, journalIndex, stepIndex)
        local numConditions = callESO(GetJournalQuestNumConditions, journalIndex, stepIndex) or 0
        local stepVisible = true
        if visibility ~= nil then
            if hiddenConstant ~= nil then
                stepVisible = (visibility ~= hiddenConstant)
            else
                stepVisible = (visibility ~= false)
            end
        end

        if stepVisible and numConditions > 0 then
            local title = stripProgressDecorations(trackerOverrideText) or stripProgressDecorations(stepText)
            return stepIndex, title
        end
    end

    local stepText, _, _, trackerOverrideText = callESO(GetJournalQuestStepInfo, journalIndex, 1)
    return 1, (stripProgressDecorations(trackerOverrideText) or stripProgressDecorations(stepText))
end

local function buildObjectivesForStep(journalIndex, stepIndex)
    local objectives = {}
    local numConditions = callESO(GetJournalQuestNumConditions, journalIndex, stepIndex) or 0

    for conditionIndex = 1, numConditions do
        local text, cur, maxValue, isFail, isComplete =
            callESO(GetJournalQuestConditionInfo, journalIndex, stepIndex, conditionIndex)
        if text and text ~= "" then
            objectives[#objectives + 1] = {
                text = text,
                cur = cur or 0,
                max = maxValue or 0,
                complete = isComplete == true,
                failed = isFail == true,
            }
        end
    end

    return objectives
end

local function buildEntry(journalIndex)
    local name = callESO(GetJournalQuestName, journalIndex)
    if not name or name == "" then
        return nil
    end

    local entry = {
        journalIndex = journalIndex,
        key = makeQuestKey(journalIndex),
        name = name,
    }

    local questId = callESO(GetJournalQuestId, journalIndex)
    if questId and questId ~= 0 then
        entry.questId = questId
    end

    entry.uniqueId = callESO(GetJournalQuestUniqueId, journalIndex)

    local zoneName, objectiveName, zoneIndex, poiIndex = callESO(GetJournalQuestLocationInfo, journalIndex)
    entry.zoneName = zoneName
    entry.objective = objectiveName
    entry.zoneIndex = zoneIndex
    entry.poiIndex = poiIndex

    local questName, backgroundText, activeStepText, activeStepType, questLevel, questZoneName, questType, instanceDisplayType,
        isRepeatable, isDaily, questDescription, displayType = callESO(GetJournalQuestInfo, journalIndex)

    entry.backgroundText = backgroundText
    entry.activeStepText = activeStepText
    entry.activeStepType = activeStepType
    entry.questLevel = questLevel
    entry.zoneName = questZoneName or entry.zoneName
    entry.questType = questType
    entry.instanceType = instanceDisplayType
    entry.displayType = displayType
    entry.isRepeatable = isRepeatable == true
    entry.isDaily = isDaily == true
    entry.description = questDescription

    local tracked = callESO(IsTrackedJournalQuest, journalIndex)
    entry.tracked = tracked == true

    local assisted = nil
    if type(IsAssistedQuest) == "function" then
        assisted = callESO(IsAssistedQuest, journalIndex)
    else
        local trackTypeQuest = rawget(_G, "TRACK_TYPE_QUEST")
        if type(GetTrackedIsAssisted) == "function" and trackTypeQuest ~= nil then
            assisted = callESO(GetTrackedIsAssisted, trackTypeQuest, journalIndex)
        end
    end
    entry.assisted = assisted == true

    local isComplete = nil
    if type(GetJournalQuestIsComplete) == "function" then
        isComplete = callESO(GetJournalQuestIsComplete, journalIndex)
    else
        isComplete = callESO(IsJournalQuestComplete, journalIndex)
    end
    entry.isComplete = isComplete == true

    local stepIndex, stepTitle = findActiveStepIndex(journalIndex)
    entry.stepIndex = stepIndex
    entry.stepText = stepTitle
    entry.objectives = buildObjectivesForStep(journalIndex, stepIndex)
    entry.hasObjectives = (#entry.objectives > 0)
    entry.numConditions = #entry.objectives

    local cat = (M._catMap and M._catMap[journalIndex]) or nil
    entry.categoryIndex = cat and cat.index or 9999
    entry.categoryName = cat and cat.name or "MISCELLANEOUS"
    entry.categoryKey = "cat:" .. tostring(entry.categoryIndex)

    return entry
end

function M:MarkDirty()
    self._dirty = true
end

function M:Clear()
    resetLists()
    self._version = (self._version or 0) + 1
    self._dirty = false
end

function M:RefreshFromGame(force)
    if not self._dirty and not force then
        return self._version
    end

    self._catMap, self._catOrder = buildCategoryMap()

    resetLists()

    local total = callESO(GetNumJournalQuests) or 0
    for journalIndex = 1, total do
        local entry = buildEntry(journalIndex)
        if entry then
            self._list[#self._list + 1] = entry
            self._byKey[entry.key] = entry
            self._byJournal[journalIndex] = entry.key
        end
    end

    self._version = (self._version or 0) + 1
    self._dirty = false
    debugLog("QuestList: built %d quests (v%d).", #self._list, self._version)
    return self._version
end

function M:GetVersion()
    return self._version
end

function M:GetList()
    return self._list
end

function M:GetByKey(key)
    return key and self._byKey[key] or nil
end

function M:GetKeyByJournalIndex(journalIndex)
    return journalIndex and self._byJournal[journalIndex] or nil
end

function M:GetByJournalIndex(journalIndex)
    local key = self:GetKeyByJournalIndex(journalIndex)
    if not key then
        return nil
    end
    return self._byKey[key]
end

-- ESO API wrappers ---------------------------------------------------------

function M:GetNumJournalQuests()
    return callESO(GetNumJournalQuests)
end

function M:GetJournalQuestName(journalIndex)
    return callESO(GetJournalQuestName, journalIndex)
end

function M:GetJournalQuestId(journalIndex)
    return callESO(GetJournalQuestId, journalIndex)
end

function M:GetJournalQuestUniqueId(journalIndex)
    return callESO(GetJournalQuestUniqueId, journalIndex)
end

function M:GetJournalQuestType(journalIndex)
    return callESO(GetJournalQuestType, journalIndex)
end

function M:GetJournalQuestInstanceDisplayType(journalIndex)
    return callESO(GetJournalQuestInstanceDisplayType, journalIndex)
end

function M:GetJournalQuestDisplayType(journalIndex)
    return callESO(GetJournalQuestDisplayType, journalIndex)
end

function M:IsTrackedJournalQuest(journalIndex)
    return callESO(IsTrackedJournalQuest, journalIndex)
end

function M:IsAssistedQuest(journalIndex)
    if type(IsAssistedQuest) == "function" then
        return callESO(IsAssistedQuest, journalIndex)
    end

    local trackTypeQuest = rawget(_G, "TRACK_TYPE_QUEST")
    if type(GetTrackedIsAssisted) == "function" and trackTypeQuest ~= nil then
        return callESO(GetTrackedIsAssisted, trackTypeQuest, journalIndex)
    end

    return nil
end

function M:IsJournalQuestComplete(journalIndex)
    if type(GetJournalQuestIsComplete) == "function" then
        return callESO(GetJournalQuestIsComplete, journalIndex)
    end

    if type(IsJournalQuestComplete) == "function" then
        return callESO(IsJournalQuestComplete, journalIndex)
    end

    return nil
end

function M:GetJournalQuestNumSteps(journalIndex)
    return callESO(GetJournalQuestNumSteps, journalIndex)
end

function M:GetJournalQuestStepInfo(journalIndex, stepIndex)
    return callESO(GetJournalQuestStepInfo, journalIndex, stepIndex)
end

function M:GetJournalQuestNumConditions(journalIndex, stepIndex)
    return callESO(GetJournalQuestNumConditions, journalIndex, stepIndex)
end

function M:GetJournalQuestConditionInfo(journalIndex, stepIndex, conditionIndex)
    return callESO(GetJournalQuestConditionInfo, journalIndex, stepIndex, conditionIndex)
end

function M:GetJournalQuestLocationInfo(journalIndex)
    return callESO(GetJournalQuestLocationInfo, journalIndex)
end

function M:GetJournalQuestInfo(journalIndex)
    return callESO(GetJournalQuestInfo, journalIndex)
end

function M:GetJournalNumQuestCategories()
    return callESO(GetJournalNumQuestCategories)
end

function M:GetJournalQuestCategoryInfo(categoryIndex)
    return callESO(GetJournalQuestCategoryInfo, categoryIndex)
end

function M:GetJournalQuestCategoryType(journalIndex)
    return callESO(GetJournalQuestCategoryType, journalIndex)
end

function M:GetJournalQuestIndexFromCategory(categoryIndex, questIndex)
    return callESO(GetJournalQuestIndexFromCategory, categoryIndex, questIndex)
end

function M:GetQuestListData()
    if not (QUEST_JOURNAL_MANAGER and QUEST_JOURNAL_MANAGER.GetQuestListData) then
        return nil, nil, nil
    end

    local ok, questList, categoryList, seenCategories =
        pcall(QUEST_JOURNAL_MANAGER.GetQuestListData, QUEST_JOURNAL_MANAGER)
    if not ok then
        debugLog("QuestList:GetQuestListData failed: %s", tostring(questList))
        return nil, nil, nil
    end

    return questList, categoryList, seenCategories
end

-- Incremental helpers -----------------------------------------------------

function M:OnQuestAccepted(journalIndex)
    if journalIndex then
        self:MarkDirty()
    end
end

function M:OnQuestUpdated(journalIndex)
    if journalIndex then
        self:MarkDirty()
    end
end

function M:OnQuestRemoved(journalIndexOrKey)
    if journalIndexOrKey then
        self:MarkDirty()
    end
end

if ADDON and type(ADDON.RegisterModule) == "function" then
    ADDON:RegisterModule("QuestList", function()
        if type(M.RefreshFromGame) == "function" then
            M:RefreshFromGame(true)
        end
    end)
end

return M
