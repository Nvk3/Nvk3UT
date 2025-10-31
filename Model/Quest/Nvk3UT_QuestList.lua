local ADDON = Nvk3UT
local M = (ADDON and (ADDON.QuestList or {})) or {}

if ADDON then
    ADDON.QuestList = M
end

M._list = M._list or {}
M._byKey = M._byKey or {}
M._byJournal = M._byJournal or {}
M._version = M._version or 0
M._dirty = M._dirty ~= false -- default to dirty on first load
M._catMap = M._catMap
M._catOrder = M._catOrder

local unpack = table.unpack or unpack

local function pack(...)
    return { n = select("#", ...), ... }
end

local function debugLog(fmt, ...)
    if not (ADDON and ADDON.Debug) then
        return
    end

    ADDON:Debug(fmt, ...)
end

local function safeCallMulti(func, ...)
    if type(func) ~= "function" then
        return nil
    end

    local results = pack(pcall(func, ...))
    if results[1] then
        if results.n <= 1 then
            return nil
        end
        return unpack(results, 2, results.n)
    end

    debugLog("QuestList call failed: %s", tostring(results[2]))
    return nil
end

local function makeQuestKey(journalIndex)
    local questId = safeCallMulti(GetJournalQuestId, journalIndex)
    if questId and questId ~= 0 then
        return string.format("qid:%s", tostring(questId))
    end

    local uniqueId = safeCallMulti(GetJournalQuestUniqueId, journalIndex)
    if uniqueId then
        return string.format("uid:%s", tostring(uniqueId))
    end

    local name = safeCallMulti(GetJournalQuestName, journalIndex)
    local questType = safeCallMulti(GetJournalQuestType, journalIndex)
    return table.concat({ "jnl", tostring(journalIndex), tostring(name or "?"), tostring(questType or "?") }, ":")
end

local function buildEntry(journalIndex)
    local entry = { journalIndex = journalIndex }

    local name = safeCallMulti(GetJournalQuestName, journalIndex)
    entry.name = name or ""

    local zoneName, objectiveName, zoneIndex, poiIndex =
        safeCallMulti(GetJournalQuestLocationInfo, journalIndex)
    entry.zoneName = zoneName
    entry.objective = objectiveName
    entry.zoneIndex = zoneIndex
    entry.poiIndex = poiIndex

    local questType = safeCallMulti(GetJournalQuestType, journalIndex)
    entry.questType = questType

    local instanceType = safeCallMulti(GetJournalQuestInstanceDisplayType, journalIndex)
    entry.instanceType = instanceType

    local tracked = safeCallMulti(IsTrackedJournalQuest, journalIndex)
    entry.tracked = tracked == true

    local stepText, stepType, _, trackerOverrideText = nil, nil, nil, nil
    local stepInfo = pack(safeCallMulti(GetJournalQuestStepInfo, journalIndex, 1))
    if stepInfo.n >= 2 then
        stepText = stepInfo[1]
        stepType = stepInfo[3]
        trackerOverrideText = stepInfo[4]
    end

    local overrideText = trackerOverrideText
    if type(overrideText) == "string" and overrideText ~= "" then
        entry.stepText = overrideText
    else
        entry.stepText = stepText
    end
    entry.stepType = stepType

    local numConditions = safeCallMulti(GetJournalQuestNumConditions, journalIndex, 1)
    entry.numConditions = tonumber(numConditions) or 0

    entry.key = makeQuestKey(journalIndex)
    return entry
end

local function buildCategoryMap()
    local map, order = {}, {}
    local numCategories = tonumber(safeCallMulti(GetJournalNumQuestCategories)) or 0

    for categoryIndex = 1, numCategories do
        local categoryName, numInCategory = safeCallMulti(GetJournalQuestCategoryInfo, categoryIndex)
        if categoryName and categoryName ~= "" then
            order[#order + 1] = { index = categoryIndex, name = categoryName }
            if type(GetJournalQuestIndexFromCategory) == "function" then
                for questIndex = 1, tonumber(numInCategory) or 0 do
                    local journalIndex = safeCallMulti(GetJournalQuestIndexFromCategory, categoryIndex, questIndex)
                    if journalIndex then
                        map[journalIndex] = { index = categoryIndex, name = categoryName }
                    end
                end
            end
        end
    end

    if next(map) == nil and type(GetJournalQuestCategoryType) == "function" then
        local numQuests = tonumber(safeCallMulti(GetNumJournalQuests)) or 0
        for journalIndex = 1, numQuests do
            local categoryIndex = safeCallMulti(GetJournalQuestCategoryType, journalIndex)
            if categoryIndex then
                local categoryName = safeCallMulti(GetJournalQuestCategoryInfo, categoryIndex)
                map[journalIndex] = {
                    index = categoryIndex,
                    name = categoryName,
                }
                if categoryIndex then
                    local seen = false
                    for _, entry in ipairs(order) do
                        if entry.index == categoryIndex then
                            seen = true
                            break
                        end
                    end
                    if not seen then
                        order[#order + 1] = { index = categoryIndex, name = categoryName }
                    end
                end
            end
        end

        table.sort(order, function(left, right)
            return (left.index or math.huge) < (right.index or math.huge)
        end)
    end

    return map, order
end

function M:MarkDirty()
    self._dirty = true
end

function M:Clear()
    self._list = {}
    self._byKey = {}
    self._byJournal = {}
    self._version = (self._version or 0) + 1
    self._dirty = false
end

function M:RefreshFromGame(force)
    if not self._dirty and not force then
        return self._version
    end

    self._catMap, self._catOrder = buildCategoryMap()

    local numQuests = safeCallMulti(GetNumJournalQuests) or 0

    self:Clear()

    for journalIndex = 1, tonumber(numQuests) or 0 do
        local name = safeCallMulti(GetJournalQuestName, journalIndex)
        if name and name ~= "" then
            local entry = buildEntry(journalIndex)
            local categoryInfo = self._catMap and self._catMap[journalIndex] or nil
            if categoryInfo then
                entry.categoryIndex = tonumber(categoryInfo.index) or 9999
                entry.categoryName = categoryInfo.name
            else
                entry.categoryIndex = 9999
                entry.categoryName = "MISCELLANEOUS"
            end
            entry.categoryKey = string.format("cat:%s", tostring(entry.categoryIndex))

            self._list[#self._list + 1] = entry
            self._byKey[entry.key] = entry
            self._byJournal[journalIndex] = entry.key
        end
    end

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

function M:GetQuestInfo(journalIndex)
    local name, backgroundText, activeStepText, activeStepType, questLevel, zoneName, questType, instanceDisplayType,
        isRepeatable, isDaily, questDescription, displayType = safeCallMulti(GetJournalQuestInfo, journalIndex)

    if not name or name == "" then
        return nil
    end

    return {
        name = name,
        backgroundText = backgroundText,
        activeStepText = activeStepText,
        activeStepType = activeStepType,
        level = questLevel,
        zoneName = zoneName,
        questType = questType,
        instanceDisplayType = instanceDisplayType,
        isRepeatable = isRepeatable == true,
        isDaily = isDaily == true,
        description = questDescription,
        displayType = displayType,
    }
end

function M:GetQuestId(journalIndex)
    local questId = safeCallMulti(GetJournalQuestId, journalIndex)
    if questId and questId ~= 0 then
        return questId
    end
    return nil
end

function M:IsQuestTracked(journalIndex)
    if type(IsJournalQuestTracked) == "function" then
        local tracked = safeCallMulti(IsJournalQuestTracked, journalIndex)
        if tracked ~= nil then
            return tracked == true
        end
    end

    local tracked = safeCallMulti(IsTrackedJournalQuest, journalIndex)
    return tracked == true
end

function M:IsQuestAssisted(journalIndex)
    if type(GetTrackedIsAssisted) ~= "function" then
        return false
    end

    local assisted = safeCallMulti(GetTrackedIsAssisted, TRACK_TYPE_QUEST, journalIndex)
    return assisted == true
end

function M:IsQuestComplete(journalIndex)
    if type(GetJournalQuestIsComplete) == "function" then
        local complete = safeCallMulti(GetJournalQuestIsComplete, journalIndex)
        if complete ~= nil then
            return complete == true
        end
    end

    if type(IsJournalQuestComplete) == "function" then
        local complete = safeCallMulti(IsJournalQuestComplete, journalIndex)
        return complete == true
    end

    return false
end

function M:GetQuestLocation(journalIndex)
    local zoneName, subZoneName, zoneIndex, poiIndex = safeCallMulti(GetJournalQuestLocationInfo, journalIndex)
    if zoneName or subZoneName or zoneIndex or poiIndex then
        return {
            zoneName = zoneName,
            subZoneName = subZoneName,
            zoneIndex = zoneIndex,
            poiIndex = poiIndex,
        }
    end
    return nil
end

function M:GetQuestNumSteps(journalIndex)
    local count = safeCallMulti(GetJournalQuestNumSteps, journalIndex)
    return tonumber(count) or 0
end

function M:GetQuestStepInfo(journalIndex, stepIndex)
    return safeCallMulti(GetJournalQuestStepInfo, journalIndex, stepIndex)
end

function M:GetQuestNumConditions(journalIndex, stepIndex)
    local count = safeCallMulti(GetJournalQuestNumConditions, journalIndex, stepIndex)
    return tonumber(count) or 0
end

function M:GetQuestConditionInfo(journalIndex, stepIndex, conditionIndex)
    return safeCallMulti(GetJournalQuestConditionInfo, journalIndex, stepIndex, conditionIndex)
end

function M:GetQuestListData()
    if not (QUEST_JOURNAL_MANAGER and QUEST_JOURNAL_MANAGER.GetQuestListData) then
        return nil, nil, nil
    end

    local results = pack(pcall(QUEST_JOURNAL_MANAGER.GetQuestListData, QUEST_JOURNAL_MANAGER))
    if not results[1] then
        debugLog("QuestList:GetQuestListData failed: %s", tostring(results[2]))
        return nil, nil, nil
    end

    if results.n < 3 then
        return nil, nil, nil
    end

    return results[2], results[3], results[4]
end

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
    local registerModule = ADDON.RegisterModule
    registerModule("QuestList", function()
        if type(M.RefreshFromGame) == "function" then
            M:RefreshFromGame(true)
        end
    end)
end

return M
