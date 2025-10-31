local ADDON = Nvk3UT
local M = (ADDON and (ADDON.QuestModel or {})) or {}

if ADDON then
    ADDON.QuestModel = M
end

local function getQuestList()
    if not ADDON then
        return nil
    end

    return ADDON.QuestList
end

local function ensureQuestState()
    if not ADDON then
        return nil
    end

    local state = ADDON.QuestState
    if state and not state.db and type(state.Init) == "function" then
        state:Init()
    end

    return state
end

local function ensureQuestSelection()
    if not ADDON then
        return nil
    end

    local selection = ADDON.QuestSelection
    if selection and not selection.db and type(selection.Init) == "function" then
        selection:Init()
    end

    return selection
end

local function callQuestList(methodName, ...)
    local questList = getQuestList()
    if not questList then
        return nil
    end

    local method = questList[methodName]
    if type(method) ~= "function" then
        return nil
    end

    return method(questList, ...)
end

local function debugLog(fmt, ...)
    if not (ADDON and ADDON.Debug) then
        return
    end

    ADDON:Debug(fmt, ...)
end

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

local function normalizeObjectiveDisplayText(text)
    if type(text) ~= "string" then
        return nil
    end

    local displayText = text
    if zo_strformat then
        displayText = zo_strformat("<<1>>", displayText)
    end

    displayText = StripProgressDecorations(displayText) or displayText

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

local function shouldUseHeaderText(candidate, objectives)
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

    if type(objectives) == "table" then
        local headerLower = string.lower(headerText)
        for index = 1, #objectives do
            local objective = objectives[index]
            local displayText = objective and (objective.displayText or objective.text)
            if type(displayText) == "string" then
                if string.lower(displayText) == headerLower then
                    return nil
                end
            end
        end
    end

    return headerText
end

local function getTimestampMs()
    if type(GetFrameTimeMilliseconds) == "function" then
        local ok, value = pcall(GetFrameTimeMilliseconds)
        if ok then
            return value
        end
    end

    if type(GetGameTimeMilliseconds) == "function" then
        local ok, value = pcall(GetGameTimeMilliseconds)
        if ok then
            return value
        end
    end

    if type(GetFrameTimeSeconds) == "function" then
        local ok, value = pcall(GetFrameTimeSeconds)
        if ok then
            return math.floor((value or 0) * 1000 + 0.5)
        end
    end

    return nil
end

-- Journal category definitions --------------------------------------------

local CATEGORY_GROUP_DEFINITIONS = {
    MAIN_STORY = {
        order = 10,
        labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_MAIN_STORY"),
        fallbackName = "Main Story",
        typeId = rawget(_G, "ZO_QUEST_JOURNAL_CATEGORY_TYPE_MAIN_STORY"),
    },
    ZONE_STORY = {
        order = 20,
        labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_ZONE_STORY"),
        fallbackName = "Zone Story",
        typeId = rawget(_G, "ZO_QUEST_JOURNAL_CATEGORY_TYPE_ZONE_STORY"),
    },
    ZONE = {
        order = 30,
        labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_ZONE"),
        fallbackName = "Zone",
        typeId = rawget(_G, "ZO_QUEST_JOURNAL_CATEGORY_TYPE_ZONE"),
    },
    GUILD = {
        order = 40,
        labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_GUILD"),
        fallbackName = "Guild",
        typeId = rawget(_G, "ZO_QUEST_JOURNAL_CATEGORY_TYPE_GUILD"),
    },
    CRAFTING = {
        order = 50,
        labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_CRAFTING"),
        fallbackName = "Crafting",
        typeId = rawget(_G, "ZO_QUEST_JOURNAL_CATEGORY_TYPE_CRAFTING"),
    },
    DUNGEON = {
        order = 60,
        labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_DUNGEON"),
        fallbackName = "Dungeon",
        typeId = rawget(_G, "ZO_QUEST_JOURNAL_CATEGORY_TYPE_DUNGEON"),
    },
    ALLIANCE_WAR = {
        order = 70,
        labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_ALLIANCE_WAR"),
        fallbackName = "Alliance War",
        typeId = rawget(_G, "ZO_QUEST_JOURNAL_CATEGORY_TYPE_ALLIANCE_WAR"),
    },
    PROLOGUE = {
        order = 80,
        labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_PROLOGUE"),
        fallbackName = "Prologue",
        typeId = rawget(_G, "ZO_QUEST_JOURNAL_CATEGORY_TYPE_PROLOGUE"),
    },
    REPEATABLE = {
        order = 90,
        labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_REPEATABLE"),
        fallbackName = "Repeatable",
        typeId = rawget(_G, "ZO_QUEST_JOURNAL_CATEGORY_TYPE_REPEATABLE"),
    },
    COMPANION = {
        order = 100,
        labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_COMPANION"),
        fallbackName = "Companion",
        typeId = rawget(_G, "ZO_QUEST_JOURNAL_CATEGORY_TYPE_COMPANION"),
    },
    MISC = {
        order = 110,
        labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_MISC"),
        fallbackName = "Miscellaneous",
        typeId = rawget(_G, "ZO_QUEST_JOURNAL_CATEGORY_TYPE_MISCELLANEOUS"),
    },
}

local DEFAULT_GROUP_KEY = "MISC"

local function resolveDefinitionName(definition)
    if definition and definition.labelId and GetString then
        local label = GetString(definition.labelId)
        if label and label ~= "" then
            return label
        end
    end

    if definition then
        return definition.fallbackName
    end

    return ""
end

local groupEntryCache = {}
local baseCategoryCache = nil

local function resetBaseCategoryCache()
    baseCategoryCache = nil
end

local function getGroupDefinition(groupKey)
    return CATEGORY_GROUP_DEFINITIONS[groupKey] or CATEGORY_GROUP_DEFINITIONS[DEFAULT_GROUP_KEY]
end

local function getGroupEntry(groupKey)
    groupKey = groupKey or DEFAULT_GROUP_KEY

    if groupEntryCache[groupKey] then
        return groupEntryCache[groupKey]
    end

    local definition = getGroupDefinition(groupKey)
    local entry = {
        key = groupKey,
        name = resolveDefinitionName(definition),
        order = definition and definition.order or 0,
        type = definition and definition.typeId or nil,
    }

    groupEntryCache[groupKey] = entry
    return entry
end

local function copyParentInfo(parent)
    if not parent then
        return nil
    end

    return {
        key = parent.key,
        name = parent.name,
        order = parent.order,
        type = parent.type,
    }
end

local function normalizeNameForKey(name)
    if not name or name == "" then
        return nil
    end

    local normalized = tostring(name)
    normalized = normalized:gsub("|[cC]%x%x%x%x%x%x%x%x", "")
    normalized = normalized:gsub("|[rR]", "")
    normalized = normalized:gsub("%s+", " ")
    normalized = normalized:gsub("[^%w%s\128-\255]", "")
    normalized = normalized:lower()
    normalized = normalized:gsub("%s", "_")
    normalized = normalized:gsub("_+", "_")
    normalized = normalized:gsub("^_", "")
    normalized = normalized:gsub("_$", "")

    if normalized == "" then
        return nil
    end

    return normalized
end

local function registerCategoryName(lookup, name, entry)
    if not lookup or not entry then
        return
    end

    if not name or name == "" then
        return
    end

    local bucket = lookup[name]
    if not bucket then
        bucket = {}
        lookup[name] = bucket
    end

    bucket[#bucket + 1] = entry
end

local function registerCategoryLookupVariants(lookup, name, entry)
    if not lookup or not entry then
        return
    end

    registerCategoryName(lookup, name, entry)

    local normalized = normalizeNameForKey(name)
    if normalized and normalized ~= name then
        registerCategoryName(lookup, normalized, entry)
    end
end

local function fetchCategoryCandidates(lookup, name)
    if not lookup then
        return nil
    end

    if not name or name == "" then
        return nil
    end

    return lookup[name] or lookup[normalizeNameForKey(name)]
end

local function extractQuestJournalIndex(questData)
    if type(questData) ~= "table" then
        return nil
    end

    if questData.journalIndex ~= nil then
        return questData.journalIndex
    end

    local getter = questData.GetJournalIndex or questData.GetIndex
    if type(getter) == "function" then
        local ok, value = pcall(getter, questData)
        if ok then
            return value
        end
    end

    return nil
end

local function extractQuestCategoryName(questData)
    if type(questData) ~= "table" then
        return nil
    end

    if questData.categoryName ~= nil then
        return questData.categoryName
    end

    local getter = questData.GetCategoryName
    if type(getter) == "function" then
        local ok, value = pcall(getter, questData)
        if ok then
            return value
        end
    end

    return nil
end

local function extractQuestCategoryType(questData)
    if type(questData) ~= "table" then
        return nil
    end

    if questData.categoryType ~= nil then
        return questData.categoryType
    end

    if questData.type ~= nil then
        return questData.type
    end

    local getter = questData.GetCategoryType
    if type(getter) == "function" then
        local ok, value = pcall(getter, questData)
        if ok then
            return value
        end
    end

    return nil
end

local function extractCategoryName(categoryData)
    if type(categoryData) ~= "table" then
        return nil
    end

    if categoryData.name ~= nil then
        return categoryData.name
    end

    local getter = categoryData.GetName
    if type(getter) == "function" then
        local ok, value = pcall(getter, categoryData)
        if ok then
            return value
        end
    end

    return nil
end

local function extractCategoryType(categoryData)
    if type(categoryData) ~= "table" then
        return nil
    end

    if categoryData.type ~= nil then
        return categoryData.type
    end

    if categoryData.categoryType ~= nil then
        return categoryData.categoryType
    end

    local getter = categoryData.GetType or categoryData.GetCategoryType
    if type(getter) == "function" then
        local ok, value = pcall(getter, categoryData)
        if ok then
            return value
        end
    end

    return nil
end

local function extractCategoryIdentifier(categoryData)
    if type(categoryData) ~= "table" then
        return nil
    end

    if categoryData.key ~= nil then
        return categoryData.key
    end

    if categoryData.id ~= nil then
        return categoryData.id
    end

    local getter = categoryData.GetKey or categoryData.GetId
    if type(getter) == "function" then
        local ok, value = pcall(getter, categoryData)
        if ok then
            return value
        end
    end

    return nil
end

local function createLeafEntry(groupEntry, name, leafOrder, categoryType, identifier)
    local key = normalizeNameForKey(identifier or name) or (groupEntry.key .. "_" .. tostring(leafOrder))
    local entry = {
        key = key,
        name = name or groupEntry.name,
        order = (groupEntry.order or 0) * 1000 + leafOrder,
        type = categoryType,
        groupKey = groupEntry.key,
        groupName = groupEntry.name,
        groupOrder = groupEntry.order,
        groupType = groupEntry.type,
        rawOrder = leafOrder,
        identifier = identifier,
    }

    entry.parent = copyParentInfo({
        key = groupEntry.key,
        name = groupEntry.name,
        order = groupEntry.order,
        type = groupEntry.type,
    })

    return entry
end

local function cloneCategoryEntry(entry)
    if not entry then
        return nil
    end

    local copy = {
        key = entry.key,
        name = entry.name,
        order = entry.order,
        type = entry.type,
        groupKey = entry.groupKey,
        groupName = entry.groupName,
        groupOrder = entry.groupOrder,
        groupType = entry.groupType,
        rawOrder = entry.rawOrder,
        identifier = entry.identifier,
    }

    if entry.parent then
        copy.parent = copyParentInfo(entry.parent)
    elseif entry.groupKey or entry.groupName then
        copy.parent = copyParentInfo({
            key = entry.groupKey,
            name = entry.groupName,
            order = entry.groupOrder,
            type = entry.groupType,
        })
    end

    if copy.parent then
        copy.parentKey = copy.parent.key
        copy.parentName = copy.parent.name
    end

    return copy
end

local function buildCategoryTypeToGroupMapping()
    local mapping = {}

    local function assign(constantName, groupKey)
        local value = rawget(_G, constantName)
        if value ~= nil then
            mapping[value] = groupKey
        end
    end

    assign("ZO_QUEST_JOURNAL_CATEGORY_TYPE_MAIN_STORY", "MAIN_STORY")
    assign("ZO_QUEST_JOURNAL_CATEGORY_TYPE_ZONE_STORY", "ZONE_STORY")
    assign("ZO_QUEST_JOURNAL_CATEGORY_TYPE_ZONE", "ZONE")
    assign("ZO_QUEST_JOURNAL_CATEGORY_TYPE_GUILD", "GUILD")
    assign("ZO_QUEST_JOURNAL_CATEGORY_TYPE_CRAFTING", "CRAFTING")
    assign("ZO_QUEST_JOURNAL_CATEGORY_TYPE_DUNGEON", "DUNGEON")
    assign("ZO_QUEST_JOURNAL_CATEGORY_TYPE_ALLIANCE_WAR", "ALLIANCE_WAR")
    assign("ZO_QUEST_JOURNAL_CATEGORY_TYPE_PROLOGUE", "PROLOGUE")
    assign("ZO_QUEST_JOURNAL_CATEGORY_TYPE_REPEATABLE", "REPEATABLE")
    assign("ZO_QUEST_JOURNAL_CATEGORY_TYPE_COMPANION", "COMPANION")
    assign("ZO_QUEST_JOURNAL_CATEGORY_TYPE_MISCELLANEOUS", "MISC")

    return mapping
end

local CATEGORY_TYPE_TO_GROUP = buildCategoryTypeToGroupMapping()

local function buildQuestTypeMapping()
    local mapping = {}

    local function assign(constantName, categoryKey)
        local value = rawget(_G, constantName)
        if value ~= nil then
            mapping[value] = categoryKey
        end
    end

    assign("QUEST_TYPE_MAIN_STORY", "MAIN_STORY")
    assign("QUEST_TYPE_GUILD", "GUILD")
    assign("QUEST_TYPE_CRAFTING", "CRAFTING")
    assign("QUEST_TYPE_DUNGEON", "DUNGEON")
    assign("QUEST_TYPE_UNDAUNTED_PLEDGE", "DUNGEON")
    assign("QUEST_TYPE_RAID", "DUNGEON")
    assign("QUEST_TYPE_AVA", "ALLIANCE_WAR")
    assign("QUEST_TYPE_AVA_GROUP", "ALLIANCE_WAR")
    assign("QUEST_TYPE_AVA_GRAND", "ALLIANCE_WAR")
    assign("QUEST_TYPE_PVP", "ALLIANCE_WAR")
    assign("QUEST_TYPE_AVA_WW", "ALLIANCE_WAR")
    assign("QUEST_TYPE_PROLOGUE", "PROLOGUE")
    assign("QUEST_TYPE_COMPANION", "COMPANION")
    assign("QUEST_TYPE_CLASS", "MISC")
    assign("QUEST_TYPE_GROUP", "MISC")
    assign("QUEST_TYPE_HOUSING", "MISC")
    assign("QUEST_TYPE_HOLIDAY_EVENT", "REPEATABLE")
    assign("QUEST_TYPE_HOLIDAY_DAILY", "REPEATABLE")
    assign("QUEST_TYPE_BATTLEGROUND", "ALLIANCE_WAR")

    return mapping
end

local function buildDisplayTypeMapping()
    local mapping = {}

    local function assign(constantName, categoryKey)
        local value = rawget(_G, constantName)
        if value ~= nil then
            mapping[value] = categoryKey
        end
    end

    assign("QUEST_DISPLAY_TYPE_ZONE_STORY", "ZONE_STORY")
    assign("QUEST_DISPLAY_TYPE_REPEATABLE", "REPEATABLE")
    assign("QUEST_DISPLAY_TYPE_EVENT", "REPEATABLE")
    assign("QUEST_DISPLAY_TYPE_WEEKLY", "REPEATABLE")
    assign("QUEST_DISPLAY_TYPE_DAILY", "REPEATABLE")

    return mapping
end

local QUEST_TYPE_TO_CATEGORY = buildQuestTypeMapping()
local QUEST_DISPLAY_TYPE_TO_CATEGORY = buildDisplayTypeMapping()

local function normalizeLeafCategory(categoryData, orderIndex)
    local categoryType = extractCategoryType(categoryData)
    local groupKey = CATEGORY_TYPE_TO_GROUP[categoryType] or DEFAULT_GROUP_KEY
    local groupEntry = getGroupEntry(groupKey)
    local name = extractCategoryName(categoryData) or groupEntry.name
    local identifier = extractCategoryIdentifier(categoryData)

    return createLeafEntry(groupEntry, name, orderIndex or 0, categoryType, identifier)
end

local function buildBaseCategoryCacheFromData(questListData, categoryList)
    local categoriesByKey = {}
    local categoriesByName = {}
    local orderedCategories = {}

    for index = 1, #(categoryList or {}) do
        local rawCategory = categoryList[index]
        local entry = normalizeLeafCategory(rawCategory, index)
        orderedCategories[#orderedCategories + 1] = entry
        categoriesByKey[entry.key] = entry

        local categoryName = extractCategoryName(rawCategory)
        registerCategoryLookupVariants(categoriesByName, categoryName, entry)
    end

    local questCategoriesByJournalIndex = {}

    for index = 1, #(questListData or {}) do
        local questData = questListData[index]
        local questIndex = extractQuestJournalIndex(questData)
        local categoryName = extractQuestCategoryName(questData)
        local categoryEntry = nil

        local possible = fetchCategoryCandidates(categoriesByName, categoryName)
        if categoryName and possible then
            if #possible == 1 then
                categoryEntry = possible[1]
            else
                local candidateType = extractQuestCategoryType(questData)
                if candidateType ~= nil then
                    for _, entry in ipairs(possible) do
                        if entry.type == candidateType then
                            categoryEntry = entry
                            break
                        end
                    end
                end
                if not categoryEntry then
                    categoryEntry = possible[1]
                end
            end
        end

        if questIndex and categoryEntry then
            questCategoriesByJournalIndex[questIndex] = categoryEntry
        end
    end

    return {
        ordered = orderedCategories,
        byKey = categoriesByKey,
        byName = categoriesByName,
        byJournalIndex = questCategoriesByJournalIndex,
    }
end

local function acquireQuestJournalData()
    local questList = getQuestList()
    if not questList or type(questList.GetQuestListData) ~= "function" then
        return nil, nil, nil
    end

    return questList:GetQuestListData()
end

local function acquireBaseCategoryCache()
    if baseCategoryCache then
        return baseCategoryCache
    end

    local questListData, categoryList = acquireQuestJournalData()
    if type(questListData) ~= "table" or type(categoryList) ~= "table" then
        return nil
    end

    baseCategoryCache = buildBaseCategoryCacheFromData(questListData, categoryList)
    return baseCategoryCache
end

local function appendSignaturePart(parts, value)
    parts[#parts + 1] = tostring(value)
end

local function buildQuestSignature(quest)
    local parts = {}
    appendSignaturePart(parts, quest.journalIndex)
    appendSignaturePart(parts, quest.questId or "nil")
    appendSignaturePart(parts, quest.name or "")
    appendSignaturePart(parts, quest.zoneName or "")

    local category = quest.category or {}
    appendSignaturePart(parts, category.key or "nil")
    appendSignaturePart(parts, (category.parent and category.parent.key) or "nil")
    appendSignaturePart(parts, category.type or "nil")
    appendSignaturePart(parts, category.groupKey or "nil")
    appendSignaturePart(parts, category.groupOrder or "nil")

    local meta = quest.meta or {}
    appendSignaturePart(parts, meta.parentKey or "nil")
    appendSignaturePart(parts, meta.categoryType or "nil")
    appendSignaturePart(parts, meta.groupKey or "nil")

    appendSignaturePart(parts, quest.flags.tracked and 1 or 0)
    appendSignaturePart(parts, quest.flags.assisted and 1 or 0)
    appendSignaturePart(parts, quest.flags.isComplete and 1 or 0)
    appendSignaturePart(parts, quest.flags.isRepeatable and 1 or 0)
    appendSignaturePart(parts, quest.flags.isDaily and 1 or 0)
    appendSignaturePart(parts, quest.questType or "nil")
    appendSignaturePart(parts, quest.displayType or "nil")
    appendSignaturePart(parts, quest.instanceDisplayType or "nil")

    for stepIndex = 1, #(quest.steps or {}) do
        local step = quest.steps[stepIndex]
        appendSignaturePart(parts, step.stepText or "")
        appendSignaturePart(parts, step.stepType or "")
        appendSignaturePart(parts, step.isVisible and 1 or 0)
        appendSignaturePart(parts, step.isComplete and 1 or 0)
        for conditionIndex = 1, #(step.conditions or {}) do
            local condition = step.conditions[conditionIndex]
            appendSignaturePart(parts, condition.text or "")
            appendSignaturePart(parts, condition.current or "")
            appendSignaturePart(parts, condition.max or "")
            appendSignaturePart(parts, condition.isComplete and 1 or 0)
            appendSignaturePart(parts, condition.isVisible and 1 or 0)
            appendSignaturePart(parts, condition.isFailCondition and 1 or 0)
        end
    end

    return table.concat(parts, "|")
end

local function buildOverallSignature(quests)
    local parts = {}
    for index = 1, #quests do
        parts[index] = quests[index].signature
    end
    return table.concat(parts, "\31")
end

local function getCategoryKey(questType, displayType, isRepeatable, isDaily)
    if displayType and QUEST_DISPLAY_TYPE_TO_CATEGORY[displayType] then
        return QUEST_DISPLAY_TYPE_TO_CATEGORY[displayType]
    end

    if isRepeatable or isDaily then
        return "REPEATABLE"
    end

    if questType and QUEST_TYPE_TO_CATEGORY[questType] then
        return QUEST_TYPE_TO_CATEGORY[questType]
    end

    return DEFAULT_GROUP_KEY
end

local function determineLegacyCategory(questType, displayType, isRepeatable, isDaily)
    local key = getCategoryKey(questType, displayType, isRepeatable, isDaily)
    local groupEntry = getGroupEntry(key)
    return createLeafEntry(groupEntry, groupEntry.name, 0, groupEntry.type, groupEntry.key)
end

local function resolveQuestCategory(journalIndex, questType, displayType, isRepeatable, isDaily, listEntry)
    if type(listEntry) == "table" then
        local index = listEntry.categoryIndex
        local name = listEntry.categoryName
        local key = listEntry.categoryKey or (index and ("cat:" .. tostring(index)))
        if key or name or index then
            local category = {
                key = key or "cat:9999",
                name = name or "MISCELLANEOUS",
                order = index or 9999,
                rawOrder = index,
                index = index,
            }
            return category
        end
    end

    local cache = acquireBaseCategoryCache()
    if cache and cache.byJournalIndex then
        local entry = cache.byJournalIndex[journalIndex]
        if entry then
            return cloneCategoryEntry(entry)
        end
    end

    return determineLegacyCategory(questType, displayType, isRepeatable, isDaily)
end

local function collectQuestConditions(journalIndex, stepIndex)
    local conditions = {}
    local numConditions = tonumber(callQuestList("GetJournalQuestNumConditions", journalIndex, stepIndex)) or 0
    for conditionIndex = 1, numConditions do
        local conditionText, current, maxValue, isFailCondition, isComplete, isVisible, isTracked, isShared, isHidden, isOptional,
            countDisplayType = callQuestList("GetJournalQuestConditionInfo", journalIndex, stepIndex, conditionIndex)

        conditions[#conditions + 1] = {
            conditionIndex = conditionIndex,
            text = conditionText,
            current = current,
            max = maxValue,
            isFailCondition = isFailCondition == true,
            isComplete = isComplete == true,
            isVisible = isVisible ~= false and isHidden ~= true,
            isTracked = isTracked == true,
            isShared = isShared == true,
            isHidden = isHidden == true,
            isOptional = isOptional == true,
            countDisplayType = countDisplayType,
        }
    end

    return conditions
end

local function collectQuestSteps(journalIndex)
    local steps = {}
    local numSteps = tonumber(callQuestList("GetJournalQuestNumSteps", journalIndex)) or 0

    for stepIndex = 1, numSteps do
        local stepText, visibility, stepType, trackerOverrideText, stepNumConditions =
            callQuestList("GetJournalQuestStepInfo", journalIndex, stepIndex)

        local stepEntry = {
            stepIndex = stepIndex,
            stepText = stepText,
            trackerOverrideText = trackerOverrideText,
            stepType = stepType,
            visibility = visibility,
            numConditions = stepNumConditions or 0,
            conditions = collectQuestConditions(journalIndex, stepIndex),
        }

        stepEntry.isVisible = stepEntry.visibility ~= false
        local hiddenConstant = rawget(_G, "QUEST_STEP_VISIBILITY_HIDDEN")
        if hiddenConstant ~= nil and stepEntry.visibility ~= nil then
            stepEntry.isVisible = stepEntry.visibility ~= hiddenConstant
        end

        steps[#steps + 1] = stepEntry
    end

    return steps
end

local function collectQuestObjectivesFromJournal(journalIndex, questIsComplete)
    local objectives = {}
    local seen = {}
    local fallbackStepText = nil
    local fallbackObjectiveText = nil
    local fallbackStepIndex = nil

    local hiddenConstant = rawget(_G, "QUEST_STEP_VISIBILITY_HIDDEN")
    local numSteps = tonumber(callQuestList("GetJournalQuestNumSteps", journalIndex)) or 0

    for stepIndex = 1, numSteps do
        local stepText, visibility, _, trackerOverrideText =
            callQuestList("GetJournalQuestStepInfo", journalIndex, stepIndex)
        local sanitizedOverride = StripProgressDecorations(trackerOverrideText)
        local sanitizedStep = StripProgressDecorations(stepText)
        local fallbackStepCandidate = sanitizedOverride or sanitizedStep

        local stepIsVisible = true
        if visibility ~= nil then
            if hiddenConstant ~= nil then
                stepIsVisible = (visibility ~= hiddenConstant)
            else
                stepIsVisible = (visibility ~= false)
            end
        end

        if questIsComplete and not stepIsVisible then
            stepIsVisible = true
        end

        if not fallbackStepText and fallbackStepCandidate then
            fallbackStepText = fallbackStepCandidate
            fallbackStepIndex = stepIndex
        end

        local fallbackObjectiveCandidate =
            normalizeObjectiveDisplayText(trackerOverrideText) or normalizeObjectiveDisplayText(stepText)
        if not fallbackObjectiveText and fallbackObjectiveCandidate then
            fallbackObjectiveText = fallbackObjectiveCandidate
        end

        local addedObjectiveForStep = false
        local totalConditions = tonumber(callQuestList("GetJournalQuestNumConditions", journalIndex, stepIndex)) or 0

        for conditionIndex = 1, totalConditions do
            local conditionText, current, maxValue, isFailCondition, isConditionComplete, _, isConditionVisible, isTracked,
                isShared, isHidden, isOptional, countDisplayType =
                callQuestList("GetJournalQuestConditionInfo", journalIndex, stepIndex, conditionIndex)

            local formattedCondition = normalizeObjectiveDisplayText(conditionText)
            local visibleCondition = (isConditionVisible ~= false) and (isHidden ~= true)
            if questIsComplete and not visibleCondition then
                visibleCondition = true
            end

            local isFail = (isFailCondition == true)

            if formattedCondition and visibleCondition and not isFail then
                addedObjectiveForStep = true
                if not seen[formattedCondition] then
                    seen[formattedCondition] = true
                    objectives[#objectives + 1] = {
                        text = conditionText,
                        displayText = formattedCondition,
                        current = tonumber(current) or 0,
                        max = tonumber(maxValue) or 0,
                        complete = isConditionComplete == true,
                        isTurnIn = false,
                        isTracked = isTracked == true,
                        isShared = isShared == true,
                        isOptional = isOptional == true,
                        countDisplayType = countDisplayType,
                    }
                end
            end
        end

        if not addedObjectiveForStep and fallbackObjectiveCandidate and not seen[fallbackObjectiveCandidate] then
            seen[fallbackObjectiveCandidate] = true
            objectives[#objectives + 1] = {
                text = fallbackObjectiveCandidate,
                displayText = fallbackObjectiveCandidate,
                current = 0,
                max = 0,
                complete = false,
                isTurnIn = questIsComplete and not stepIsVisible,
            }
        end
    end

    if #objectives == 0 and fallbackObjectiveText and not seen[fallbackObjectiveText] then
        objectives[1] = {
            text = fallbackObjectiveText,
            displayText = fallbackObjectiveText,
            current = 0,
            max = 0,
            complete = false,
            isTurnIn = questIsComplete,
        }
    end

    return objectives, fallbackStepText, fallbackStepIndex
end

local function copyObjectivesFromEntry(listEntry)
    if type(listEntry) ~= "table" then
        return nil
    end

    local source = listEntry.objectives
    if type(source) ~= "table" or #source == 0 then
        return nil
    end

    local copy = {}
    for index = 1, #source do
        local objective = source[index]
        if type(objective) == "table" then
            local clone = {}
            for key, value in pairs(objective) do
                clone[key] = value
            end
            copy[#copy + 1] = clone
        end
    end

    return copy, listEntry.stepText, listEntry.stepIndex
end

local function collectQuestObjectives(journalIndex, questIsComplete, listEntry)
    local copiedObjectives, headerText, stepIndex = copyObjectivesFromEntry(listEntry)
    if copiedObjectives then
        local header = shouldUseHeaderText(headerText, copiedObjectives) or headerText
        return copiedObjectives, header, stepIndex
    end

    local objectives, fallbackStepText, fallbackStepIndex =
        collectQuestObjectivesFromJournal(journalIndex, questIsComplete)
    local header = shouldUseHeaderText(fallbackStepText, objectives) or fallbackStepText
    return objectives, header, fallbackStepIndex
end

local function buildQuestEntry(listEntry)
    if type(listEntry) ~= "table" then
        return nil
    end

    local journalIndex = listEntry.journalIndex
    if not journalIndex then
        return nil
    end

    local questName, backgroundText, activeStepText, activeStepType, questLevel, zoneName, questType, instanceDisplayType,
        isRepeatable, isDaily, questDescription, displayType = callQuestList("GetJournalQuestInfo", journalIndex)

    if not questName or questName == "" then
        return nil
    end

    isRepeatable = isRepeatable == true
    isDaily = isDaily == true

    local questId = callQuestList("GetJournalQuestId", journalIndex)
    if questId == 0 then
        questId = nil
    end

    local tracked = callQuestList("IsTrackedJournalQuest", journalIndex)
    local assisted = callQuestList("IsAssistedQuest", journalIndex)
    if assisted == nil and tracked then
        local trackTypeQuest = rawget(_G, "TRACK_TYPE_QUEST")
        if type(GetTrackedIsAssisted) == "function" and trackTypeQuest ~= nil then
            assisted = GetTrackedIsAssisted(trackTypeQuest, journalIndex)
        end
    end

    local isComplete = callQuestList("IsJournalQuestComplete", journalIndex)

    local objectives, stepHeader, stepIndex = collectQuestObjectives(journalIndex, isComplete == true, listEntry)
    local category = resolveQuestCategory(journalIndex, questType, displayType, isRepeatable, isDaily, listEntry)

    if category then
        if listEntry.categoryKey and not category.key then
            category.key = listEntry.categoryKey
        end
        if listEntry.categoryName and not category.name then
            category.name = listEntry.categoryName
        end
        if listEntry.categoryIndex and (category.order == nil or category.order == 0) then
            category.order = listEntry.categoryIndex
            category.rawOrder = listEntry.categoryIndex
            category.index = category.index or listEntry.categoryIndex
        end
    end

    local questEntry = {
        key = listEntry.key,
        journalIndex = journalIndex,
        questId = questId,
        name = questName,
        backgroundText = backgroundText,
        activeStepText = stepHeader or activeStepText,
        stepIndex = stepIndex,
        steps = collectQuestSteps(journalIndex),
        objectives = objectives,
        flags = {
            tracked = tracked == true,
            assisted = assisted == true,
            isComplete = isComplete == true,
            isRepeatable = isRepeatable,
            isDaily = isDaily,
        },
        questType = questType,
        displayType = displayType,
        instanceDisplayType = instanceDisplayType,
        location = (function()
            local zoneNameInfo, subZoneName, zoneIndex, poiIndex = callQuestList("GetJournalQuestLocationInfo", journalIndex)
            if zoneNameInfo or subZoneName or zoneIndex or poiIndex then
                return {
                    zoneName = zoneNameInfo,
                    subZoneName = subZoneName,
                    zoneIndex = zoneIndex,
                    poiIndex = poiIndex,
                }
            end
            return nil
        end)(),
        category = category,
        description = questDescription,
        zoneName = zoneName,
        meta = {
            questType = questType,
            displayType = displayType,
            categoryType = category and category.type or nil,
            categoryKey = category and category.key or nil,
            groupKey = category and category.groupKey or nil,
            groupName = category and category.groupName or nil,
            parentKey = category and category.parent and category.parent.key or nil,
            parentName = category and category.parent and category.parent.name or nil,
            zoneName = zoneName,
            isRepeatable = isRepeatable,
            isDaily = isDaily,
        },
    }

    if category then
        questEntry.categoryKey = category.key
        questEntry.categoryName = category.name
        questEntry.categoryIndex = category.rawOrder or category.order
    end

    questEntry.numConditions = #questEntry.objectives
    questEntry.hasObjectives = questEntry.numConditions > 0
    questEntry.signature = buildQuestSignature(questEntry)

    return questEntry
end

local function compareStrings(left, right)
    if left == right then
        return 0
    elseif not left or left == "" then
        return 1
    elseif not right or right == "" then
        return -1
    end

    if left < right then
        return -1
    else
        return 1
    end
end

local function compareQuestEntries(left, right)
    local leftCategory = left.category or {}
    local rightCategory = right.category or {}

    local leftOrder = leftCategory.order or 0
    local rightOrder = rightCategory.order or 0
    if leftOrder ~= rightOrder then
        return leftOrder < rightOrder
    end

    if left.flags.assisted ~= right.flags.assisted then
        return left.flags.assisted and not right.flags.assisted
    end

    if left.flags.tracked ~= right.flags.tracked then
        return left.flags.tracked and not right.flags.tracked
    end

    local zoneCompare = compareStrings(left.zoneName, right.zoneName)
    if zoneCompare ~= 0 then
        return zoneCompare < 0
    end

    local nameCompare = compareStrings(left.name, right.name)
    if nameCompare ~= 0 then
        return nameCompare < 0
    end

    return (left.journalIndex or 0) < (right.journalIndex or 0)
end

local function buildCategoriesIndex(rows)
    local categoriesByKey = {}
    local orderedKeys = {}

    for index = 1, #rows do
        local row = rows[index]
        local category = row.category or {}
        local key = category.key or string.format("unknown:%d", index)
        local categoryEntry = categoriesByKey[key]
        if not categoryEntry then
            categoryEntry = {
                key = key,
                name = category.name or "",
                order = category.order or 0,
                type = category.type,
                groupKey = category.groupKey,
                groupName = category.groupName,
                groupOrder = category.groupOrder,
                groupType = category.groupType,
                parent = category.parent and copyParentInfo(category.parent) or nil,
                quests = {},
            }
            categoriesByKey[key] = categoryEntry
            orderedKeys[#orderedKeys + 1] = key
        end

        categoryEntry.quests[#categoryEntry.quests + 1] = row
    end

    table.sort(orderedKeys, function(left, right)
        local leftOrder = categoriesByKey[left].order or 0
        local rightOrder = categoriesByKey[right].order or 0
        if leftOrder ~= rightOrder then
            return leftOrder < rightOrder
        end
        return left < right
    end)

    local orderedCategories = {}
    for index = 1, #orderedKeys do
        local key = orderedKeys[index]
        local entry = categoriesByKey[key]
        entry.count = #entry.quests
        orderedCategories[index] = entry
    end

    return {
        byKey = categoriesByKey,
        ordered = orderedCategories,
    }
end

local function buildSectionsFromCategories(categories)
    local sections = {}
    if categories and categories.ordered then
        for _, category in ipairs(categories.ordered) do
            sections[#sections + 1] = {
                id = category.key,
                title = category.name,
                count = #category.quests,
                rows = category.quests,
            }
        end
    end
    return sections
end

local function buildQuestRows(rawEntries, questState, questSelection)
    local rows = {}
    local indexByKey = {}
    local indexByJournal = {}

    for _, entry in ipairs(rawEntries) do
        local questEntry = buildQuestEntry(entry)
        if questEntry then
            rows[#rows + 1] = questEntry
        end
    end

    table.sort(rows, compareQuestEntries)

    for index = 1, #rows do
        local quest = rows[index]
        local key = quest.key or quest.journalIndex
        if key then
            indexByKey[key] = quest
        end
        if quest.journalIndex then
            indexByJournal[quest.journalIndex] = quest
        end

        quest.expanded = questState and quest.key and questState:IsQuestExpanded(quest.key) or false
        quest.isActive = questSelection and quest.key and questSelection:GetActiveQuestId() == quest.key or false
        quest.isFocused = questSelection and quest.key and questSelection:GetFocusedQuestId() == quest.key or false
    end

    return rows, indexByKey, indexByJournal
end

local function collectQuestEntries()
    local questList = getQuestList()
    if not questList or type(questList.GetList) ~= "function" then
        return {}
    end

    local list = questList:GetList() or {}
    local entries = {}
    for index = 1, #list do
        entries[#entries + 1] = list[index]
    end
    return entries
end

M._version = M._version or 0
M._dirty = M._dirty ~= false
M._vm = M._vm or nil

function M:MarkDirty()
    self._dirty = true
end

local function buildSnapshot(rows, indexByKey, indexByJournal)
    local categories = buildCategoriesIndex(rows)
    local sections = buildSectionsFromCategories(categories)

    local snapshot = {
        version = nil,
        total = #rows,
        quests = rows,
        categories = categories,
        sections = sections,
        indexByKey = indexByKey,
        indexByJournal = indexByJournal,
        updatedAtMs = getTimestampMs(),
    }

    snapshot.signature = buildOverallSignature(rows)

    return snapshot
end

function M:RefreshFromGame(force)
    local questList = getQuestList()
    if questList and type(questList.RefreshFromGame) == "function" then
        questList:RefreshFromGame(force)
    end

    if not self._dirty and not force then
        return self._version
    end

    resetBaseCategoryCache()

    local questState = ensureQuestState()
    local questSelection = ensureQuestSelection()
    local rawEntries = collectQuestEntries()
    local rows, indexByKey, indexByJournal = buildQuestRows(rawEntries, questState, questSelection)

    local rowsWithObjectives = 0
    for index = 1, #rows do
        local quest = rows[index]
        if type(quest.objectives) == "table" and #quest.objectives > 0 then
            rowsWithObjectives = rowsWithObjectives + 1
        end
    end

    if #rows == 0 then
        local questListObj = getQuestList()
        local count = 0
        if questListObj and type(questListObj.GetList) == "function" then
            local list = questListObj:GetList() or {}
            count = #list
        end
        debugLog("QuestModel: built 0 rows; QuestList entries=%d", count)
    end

    self._version = (self._version or 0) + 1
    local snapshot = buildSnapshot(rows, indexByKey, indexByJournal)
    snapshot.version = self._version

    self._vm = snapshot
    self._dirty = false

    debugLog(
        "QuestModel: view built with %d rows (v%d); rowsWithObjectives=%d.",
        #rows,
        self._version,
        rowsWithObjectives
    )

    return self._version
end

function M:GetViewData()
    return self._vm
end

function M:OnQuestAccepted(journalIndex)
    local questList = getQuestList()
    if questList and type(questList.OnQuestAccepted) == "function" then
        questList:OnQuestAccepted(journalIndex)
    end
    self:MarkDirty()
end

function M:OnQuestUpdated(journalIndex)
    local questList = getQuestList()
    if questList and type(questList.OnQuestUpdated) == "function" then
        questList:OnQuestUpdated(journalIndex)
    end
    self:MarkDirty()
end

function M:OnQuestRemoved(journalIndexOrKey)
    local questList = getQuestList()
    if questList and type(questList.OnQuestRemoved) == "function" then
        questList:OnQuestRemoved(journalIndexOrKey)
    end

    local questState = ensureQuestState()
    if questState and type(journalIndexOrKey) == "string" and type(questState.OnQuestRemoved) == "function" then
        questState:OnQuestRemoved(journalIndexOrKey)
    end

    local questSelection = ensureQuestSelection()
    if questSelection and type(journalIndexOrKey) == "string" and type(questSelection.OnQuestRemoved) == "function" then
        questSelection:OnQuestRemoved(journalIndexOrKey, "model_remove")
    end

    self:MarkDirty()
end

return M
