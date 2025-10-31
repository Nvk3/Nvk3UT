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

    -- IMPORTANT: pass through ALL results (many ESO APIs return >3 values)
    return result1, result2, result3, result4, result5, result6, result7, result8, result9, result10, result11
end

local function safeCallMethod(target, methodName)
    if type(target) ~= "table" then
        return nil
    end

    local method = target[methodName]
    if type(method) ~= "function" then
        return nil
    end

    local ok, value = pcall(method, target)
    if ok then
        return value
    end

    return nil
end

local function extractCategoryIndex(categoryData)
    if type(categoryData) ~= "table" then
        return nil
    end

    return categoryData.categoryIndex
        or categoryData.index
        or categoryData.categoryType
        or categoryData.type
        or categoryData.typeId
        or safeCallMethod(categoryData, "GetCategoryIndex")
        or safeCallMethod(categoryData, "GetIndex")
        or safeCallMethod(categoryData, "GetCategoryType")
end

local function extractCategoryName(categoryData)
    if type(categoryData) ~= "table" then
        return nil
    end

    local name = categoryData.name
        or categoryData.categoryName
        or categoryData.label
        or safeCallMethod(categoryData, "GetName")
        or safeCallMethod(categoryData, "GetCategoryName")

    if type(name) == "string" and name ~= "" then
        return name
    end

    return nil
end

local function extractCategoryQuestList(categoryData)
    if type(categoryData) ~= "table" then
        return nil
    end

    local sources = {
        categoryData.quests,
        categoryData.questList,
        categoryData.questListData,
        categoryData.entries,
    }

    for index = 1, #sources do
        local candidate = sources[index]
        if type(candidate) == "table" then
            return candidate
        end
    end

    local getters = { "GetQuests", "GetQuestList", "GetQuestListData", "GetEntries" }
    for index = 1, #getters do
        local value = safeCallMethod(categoryData, getters[index])
        if type(value) == "table" then
            return value
        end
    end

    return nil
end

local function extractQuestJournalIndex(questData)
    if type(questData) ~= "table" then
        return nil
    end

    local index = questData.journalIndex
        or questData.index
        or questData.questIndex
        or safeCallMethod(questData, "GetJournalIndex")
        or safeCallMethod(questData, "GetIndex")
        or safeCallMethod(questData, "GetQuestIndex")

    if type(index) == "number" then
        return index
    end

    return nil
end

local function extractQuestCategoryIndex(questData)
    if type(questData) ~= "table" then
        return nil
    end

    local index = questData.categoryIndex
        or questData.categoryType
        or questData.type
        or safeCallMethod(questData, "GetCategoryIndex")
        or safeCallMethod(questData, "GetCategoryType")

    if type(index) == "number" then
        return index
    end

    return nil
end

local function extractQuestCategoryName(questData)
    if type(questData) ~= "table" then
        return nil
    end

    local name = questData.categoryName
        or questData.category
        or safeCallMethod(questData, "GetCategoryName")

    if type(name) == "string" and name ~= "" then
        return name
    end

    return nil
end

local function registerCategoryEntry(seen, order, catIndex, catName)
    local key
    if catIndex ~= nil then
        key = "idx:" .. tostring(catIndex)
    elseif catName and catName ~= "" then
        key = "name:" .. tostring(catName)
    else
        key = "anon:" .. tostring(#order + 1)
    end

    local entry = seen[key]
    if not entry then
        local assignedIndex = catIndex
        if assignedIndex == nil then
            assignedIndex = #order + 9000
        end
        entry = {
            index = assignedIndex,
            name = catName or "MISCELLANEOUS",
        }
        order[#order + 1] = entry
        seen[key] = entry
    else
        if catName and (not entry.name or entry.name == "") then
            entry.name = catName
        end
        if catIndex and (not entry.index or entry.index >= 9000) then
            entry.index = catIndex
        end
    end

    return entry
end

local function AcquireQuestJournalData()
    if not (QUEST_JOURNAL_MANAGER and QUEST_JOURNAL_MANAGER.GetQuestListData) then
        return nil, nil, nil
    end

    local ok, questList, categoryList, seenCategories =
        pcall(QUEST_JOURNAL_MANAGER.GetQuestListData, QUEST_JOURNAL_MANAGER)
    if not ok then
        debugLog("QuestList:AcquireQuestJournalData failed: %s", tostring(questList))
        return nil, nil, nil
    end

    if type(questList) ~= "table" or type(categoryList) ~= "table" then
        return nil, nil, nil
    end

    return questList, categoryList, seenCategories
end

local function BuildBaseCategoryCacheFromData(questListData, categoryList)
    local map, order = {}, {}
    local seen = {}

    if type(categoryList) == "table" then
        for index = 1, #categoryList do
            local categoryData = categoryList[index]
            local categoryIndex = extractCategoryIndex(categoryData)
            local categoryName = extractCategoryName(categoryData)
            local entry = registerCategoryEntry(seen, order, categoryIndex, categoryName)

            local questEntries = extractCategoryQuestList(categoryData)
            if type(questEntries) == "table" then
                for questIdx = 1, #questEntries do
                    local questData = questEntries[questIdx]
                    local journalIndex = extractQuestJournalIndex(questData)
                    if journalIndex then
                        map[journalIndex] = { index = entry.index, name = entry.name }
                    end
                end
            end
        end
    end

    if next(map) == nil and type(questListData) == "table" then
        for index = 1, #questListData do
            local questData = questListData[index]
            local journalIndex = extractQuestJournalIndex(questData)
            if journalIndex then
                local categoryIndex = extractQuestCategoryIndex(questData)
                local categoryName = extractQuestCategoryName(questData)
                local entry = registerCategoryEntry(seen, order, categoryIndex, categoryName)
                map[journalIndex] = { index = entry.index, name = entry.name }
            end
        end

        table.sort(order, function(left, right)
            return (left.index or 9999) < (right.index or 9999)
        end)
    end

    return map, order
end

local function appendCategoryOrder(order, seen, index, name)
    if not index then
        return
    end

    local label = name or "MISCELLANEOUS"
    local key = string.format("%s|%s", tostring(index), label)
    if seen[key] then
        return
    end

    order[#order + 1] = { index = index, name = label }
    seen[key] = true
end

local function deriveCategoriesFromQuestModel()
    local questModel = ADDON and ADDON.QuestModel
    if not questModel then
        return nil, nil
    end

    if type(questModel.MarkCategoriesDirty) == "function" then
        pcall(questModel.MarkCategoriesDirty, questModel)
    end

    if type(questModel.GetCategoryForJournalIndex) ~= "function" then
        return nil, nil
    end

    local ok, byJournal, ordered = pcall(questModel.GetCategoryForJournalIndex, questModel, nil)
    if not ok then
        debugLog("QuestList: QuestModel:GetCategoryForJournalIndex failed: %s", tostring(byJournal))
        return nil, nil
    end

    if type(byJournal) ~= "table" then
        return nil, nil
    end

    local map = {}
    for journalIndex, categoryEntry in pairs(byJournal) do
        if type(journalIndex) == "number" and type(categoryEntry) == "table" then
            local orderIndex = tonumber(categoryEntry.order)
                or tonumber(categoryEntry.rawOrder)
                or tonumber(categoryEntry.index)
                or tonumber(categoryEntry.groupOrder)
                or tonumber(categoryEntry.orderIndex)
                or tonumber(journalIndex)
            local name = categoryEntry.name or categoryEntry.title or categoryEntry.categoryName

            map[journalIndex] = {
                index = orderIndex or 9999,
                name = name or "MISCELLANEOUS",
            }
        end
    end

    local order = {}
    local seen = {}
    if type(ordered) == "table" then
        for idx = 1, #ordered do
            local entry = ordered[idx]
            if type(entry) == "table" then
                local orderIndex = tonumber(entry.order)
                    or tonumber(entry.rawOrder)
                    or tonumber(entry.index)
                    or tonumber(idx)
                appendCategoryOrder(order, seen, orderIndex, entry.name or entry.title)
            end
        end
    end

    if #order == 0 then
        -- ensure deterministic order even if ordered list missing
        local fallbackSeen = {}
        local sortedJournal = {}
        for journalIndex, info in pairs(map) do
            sortedJournal[#sortedJournal + 1] = { index = info.index, name = info.name }
        end
        table.sort(sortedJournal, function(left, right)
            return (left.index or 9999) < (right.index or 9999)
        end)
        for idx = 1, #sortedJournal do
            local entry = sortedJournal[idx]
            appendCategoryOrder(order, fallbackSeen, entry.index, entry.name)
        end
    end

    return map, order
end

local function assignJournalCategory(map, journalIndex, orderIndex, name)
    if not journalIndex then
        return
    end

    map[journalIndex] = {
        index = orderIndex or 9999,
        name = name or "MISCELLANEOUS",
    }
end

local function buildFallbackCategoryMap()
    local map, order = {}, {}
    local seenOrder = {}
    local sequentialIndex = 0

    local numCategories = callESO(GetJournalNumQuestCategories) or 0
    for categoryIndex = 1, numCategories do
        local categoryName, numSubcategories = callESO(GetJournalQuestCategoryInfo, categoryIndex)
        local usedSubcategories = false

        if type(GetJournalQuestSubcategoryInfo) == "function" and type(GetJournalQuestIndexFromSubcategory) == "function" then
            local totalSubcategories = tonumber(numSubcategories) or 0
            for subIndex = 1, totalSubcategories do
                local subName, numQuests = callESO(GetJournalQuestSubcategoryInfo, categoryIndex, subIndex)
                if subName and subName ~= "" then
                    sequentialIndex = sequentialIndex + 1
                    appendCategoryOrder(order, seenOrder, sequentialIndex, subName)

                    local questCount = tonumber(numQuests) or 0
                    if questCount <= 0 then
                        local questOffset = 1
                        while true do
                            local journalIndex = callESO(
                                GetJournalQuestIndexFromSubcategory,
                                categoryIndex,
                                subIndex,
                                questOffset
                            )
                            if not journalIndex then
                                break
                            end
                            assignJournalCategory(map, journalIndex, sequentialIndex, subName)
                            questOffset = questOffset + 1
                        end
                    else
                        for questOffset = 1, questCount do
                            local journalIndex = callESO(
                                GetJournalQuestIndexFromSubcategory,
                                categoryIndex,
                                subIndex,
                                questOffset
                            )
                            if journalIndex then
                                assignJournalCategory(map, journalIndex, sequentialIndex, subName)
                            end
                        end
                    end

                    usedSubcategories = true
                end
            end
        end

        if not usedSubcategories then
            sequentialIndex = sequentialIndex + 1
            local headerName = categoryName or "MISCELLANEOUS"
            appendCategoryOrder(order, seenOrder, sequentialIndex, headerName)

            local questCount = nil
            if type(GetJournalQuestNumQuestsInCategory) == "function" then
                questCount = callESO(GetJournalQuestNumQuestsInCategory, categoryIndex)
            end
            local totalQuests = tonumber(questCount) or tonumber(numSubcategories) or 0

            if type(GetJournalQuestIndexFromCategory) == "function" then
                if totalQuests > 0 then
                    for questOffset = 1, totalQuests do
                        local journalIndex = callESO(GetJournalQuestIndexFromCategory, categoryIndex, questOffset)
                        if journalIndex then
                            assignJournalCategory(map, journalIndex, sequentialIndex, headerName)
                        end
                    end
                else
                    local questOffset = 1
                    while true do
                        local journalIndex = callESO(GetJournalQuestIndexFromCategory, categoryIndex, questOffset)
                        if not journalIndex then
                            break
                        end
                        assignJournalCategory(map, journalIndex, sequentialIndex, headerName)
                        questOffset = questOffset + 1
                    end
                end
            end
        end
    end

    return map, order
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
        local stepText, stepType, stepVisibility, trackerOverrideText =
            callESO(GetJournalQuestStepInfo, journalIndex, stepIndex)
        local numConditions = callESO(GetJournalQuestNumConditions, journalIndex, stepIndex) or 0

        local stepVisible = true
        if stepVisibility ~= nil then
            if hiddenConstant ~= nil then
                stepVisible = (stepVisibility ~= hiddenConstant)
            else
                stepVisible = (stepVisibility ~= false)
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
    if not cat then
        cat = { index = 9999, name = "MISCELLANEOUS" }
    end

    entry.categoryIndex = cat.index
    entry.categoryName = cat.name
    entry.categoryKey = "cat:" .. tostring(entry.categoryIndex)

    return entry
end

function M:MarkDirty()
    self._dirty = true
    local questModel = ADDON and ADDON.QuestModel
    if questModel and type(questModel.MarkCategoriesDirty) == "function" then
        pcall(questModel.MarkCategoriesDirty, questModel)
    end
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

    local map, order = deriveCategoriesFromQuestModel()

    if (not map or next(map) == nil) or (not order or #order == 0) then
        local questListData, categoryList = AcquireQuestJournalData()
        if questListData or categoryList then
            local managerMap, managerOrder = BuildBaseCategoryCacheFromData(questListData, categoryList)
            if managerMap and next(managerMap) ~= nil then
                map = managerMap
            end
            if managerOrder and #managerOrder > 0 then
                order = managerOrder
            end
        end
    end

    if (not map or next(map) == nil) or (not order or #order == 0) then
        local fallbackMap, fallbackOrder = buildFallbackCategoryMap()
        if fallbackMap and next(fallbackMap) ~= nil then
            map = fallbackMap
        end
        if fallbackOrder and #fallbackOrder > 0 then
            order = fallbackOrder
        end
    end

    map = map or {}
    order = order or {}

    table.sort(order, function(left, right)
        return (left.index or 9999) < (right.index or 9999)
    end)

    M._catMap = map
    M._catOrder = order

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

    local sampleParts = {}
    local sampleCount = 0
    for journalIndex, info in pairs(M._catMap or {}) do
        local label = info and info.name or "?"
        sampleParts[#sampleParts + 1] = string.format("%s=%s", tostring(journalIndex), tostring(label))
        sampleCount = sampleCount + 1
        if sampleCount >= 5 then
            break
        end
    end

    debugLog(
        "QuestList: built %d quests (v%d), cats=%d (mapped=%s) samples=[%s].",
        #self._list,
        self._version,
        M._catOrder and #M._catOrder or 0,
        tostring(M._catMap and next(M._catMap) ~= nil),
        table.concat(sampleParts, ", ")
    )
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
