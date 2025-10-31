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
    local questId = M:GetJournalQuestId(journalIndex)
    if questId and questId ~= 0 then
        return string.format("qid:%s", tostring(questId))
    end

    local uniqueId = M:GetJournalQuestUniqueId(journalIndex)
    if uniqueId then
        return string.format("uid:%s", tostring(uniqueId))
    end

    local name = M:GetJournalQuestName(journalIndex)
    return table.concat({ "jnl", tostring(journalIndex), tostring(name or "?") }, ":")
end

local function resetLists()
    M._list = {}
    M._byKey = {}
    M._byJournal = {}
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

    local nextVersion = (self._version or 0) + 1
    resetLists()

    local total = tonumber(self:GetNumJournalQuests()) or 0
    for journalIndex = 1, total do
        local name = self:GetJournalQuestName(journalIndex)
        if name and name ~= "" then
            local entry = {
                journalIndex = journalIndex,
                key = makeQuestKey(journalIndex),
                name = name,
            }

            local stepText, _, _, trackerOverrideText = self:GetJournalQuestStepInfo(journalIndex, 1)
            if trackerOverrideText and trackerOverrideText ~= "" then
                entry.stepText = trackerOverrideText
            elseif stepText and stepText ~= "" then
                entry.stepText = stepText
            end

            entry.numConditions = self:GetJournalQuestNumConditions(journalIndex, 1) or 0

            self._list[#self._list + 1] = entry
            self._byKey[entry.key] = entry
            self._byJournal[journalIndex] = entry.key
        end
    end

    self._version = nextVersion
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
