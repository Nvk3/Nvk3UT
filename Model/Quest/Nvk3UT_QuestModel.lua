local ADDON = Nvk3UT
local M = ADDON and (ADDON.QuestModel or {}) or {}

if ADDON then
    ADDON.QuestModel = M
end

local function getQuestList()
    if not ADDON then
        return nil
    end
    if not ADDON.QuestList then
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

local function debugLog(fmt, ...)
    if not (ADDON and ADDON.Debug) then
        return
    end
    ADDON:Debug(fmt, ...)
end

local function normalizeQuestKey(value)
    if value == nil then
        return nil
    end
    if type(value) == "number" then
        if value > 0 then
            return tostring(value)
        end
        return nil
    end
    if type(value) == "string" then
        local numeric = tonumber(value)
        if numeric and numeric > 0 then
            return tostring(numeric)
        end
        if value ~= "" then
            return value
        end
        return nil
    end
    return tostring(value)
end

local function stripProgressDecorations(text)
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
    if objectives and type(objectives) == "table" then
        local headerLower = string.lower(headerText)
        for index = 1, #objectives do
            local objective = objectives[index]
            local displayText = objective and objective.displayText
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

local function collectQuestObjectives(journalIndex, questIsComplete)
    local questList = getQuestList()
    if not questList then
        return {}, nil
    end
    if not (questList.GetQuestNumSteps and questList.GetQuestStepInfo) then
        return {}, nil
    end

    local objectiveList = {}
    local seen = {}
    local fallbackStepText = nil
    local fallbackObjectiveText = nil

    local numSteps = questList:GetQuestNumSteps(journalIndex)
    if type(numSteps) ~= "number" or numSteps <= 0 then
        return objectiveList, fallbackStepText
    end

    for stepIndex = 1, numSteps do
        local stepText, visibility, _, trackerOverrideText, stepNumConditions =
            questList:GetQuestStepInfo(journalIndex, stepIndex)
        local sanitizedOverrideText = stripProgressDecorations(trackerOverrideText)
        local sanitizedStepText = stripProgressDecorations(stepText)
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
            stepIsVisible = true
        end

        if sanitizedOverrideText then
            fallbackObjectiveCandidate = sanitizedOverrideText
        elseif sanitizedStepText then
            fallbackObjectiveCandidate = sanitizedStepText
        end

        if not fallbackStepText and sanitizedStepText then
            fallbackStepText = sanitizedStepText
        end

        if sanitizedOverrideText and not seen[sanitizedOverrideText] then
            seen[sanitizedOverrideText] = true
            objectiveList[#objectiveList + 1] = {
                displayText = sanitizedOverrideText,
                current = 0,
                max = 0,
                complete = false,
                isTurnIn = false,
            }
        elseif sanitizedStepText and not seen[sanitizedStepText] then
            seen[sanitizedStepText] = true
            objectiveList[#objectiveList + 1] = {
                displayText = sanitizedStepText,
                current = 0,
                max = 0,
                complete = false,
                isTurnIn = false,
            }
        end

        if stepNumConditions and stepNumConditions > 0 and questList.GetQuestConditionInfo then
            for conditionIndex = 1, stepNumConditions do
                local conditionText, cur, maxValue, isComplete, _, isVisible, isFail, isTracked, isShared, isHidden, isOptional,
                    countDisplayType = questList:GetQuestConditionInfo(journalIndex, stepIndex, conditionIndex)
                local normalizedText = normalizeObjectiveDisplayText(conditionText)
                if normalizedText and normalizedText ~= "" then
                    local bucketKey = string.lower(normalizedText)
                    if not seen[bucketKey] then
                        seen[bucketKey] = true
                        objectiveList[#objectiveList + 1] = {
                            displayText = normalizedText,
                            current = tonumber(cur) or 0,
                            max = tonumber(maxValue) or 0,
                            complete = isComplete == true,
                            isTurnIn = false,
                            isVisible = isVisible ~= false,
                            isFailCondition = isFail == true,
                            isTracked = isTracked == true,
                            isCreditShared = isShared == true,
                            isHidden = isHidden == true,
                            isOptional = isOptional == true,
                            countDisplayType = countDisplayType,
                        }
                    end
                end
            end
        end

        if not fallbackObjectiveText and fallbackObjectiveCandidate then
            fallbackObjectiveText = fallbackObjectiveCandidate
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

local function collectQuestConditions(journalIndex, stepIndex)
    local questList = getQuestList()
    if not questList then
        return {}
    end
    if not questList.GetQuestNumConditions or not questList.GetQuestConditionInfo then
        return {}
    end

    local conditions = {}
    local count = questList:GetQuestNumConditions(journalIndex, stepIndex) or 0
    for conditionIndex = 1, count do
        local text, cur, maxValue, isComplete, _, isVisible, isFail, isTracked, isShared, isHidden, isOptional,
            countDisplayType = questList:GetQuestConditionInfo(journalIndex, stepIndex, conditionIndex)
        local displayText = normalizeObjectiveDisplayText(text)
        conditions[#conditions + 1] = {
            text = text,
            displayText = displayText,
            current = tonumber(cur) or 0,
            max = tonumber(maxValue) or 0,
            isComplete = isComplete == true,
            isVisible = isVisible ~= false,
            isFailCondition = isFail == true,
            isTracked = isTracked == true,
            isCreditShared = isShared == true,
            isHidden = isHidden == true,
            isOptional = isOptional == true,
            countDisplayType = countDisplayType,
        }
    end

    return conditions
end

local function collectQuestSteps(journalIndex)
    local questList = getQuestList()
    if not questList then
        return {}
    end
    if not questList.GetQuestNumSteps or not questList.GetQuestStepInfo then
        return {}
    end

    local steps = {}
    local numSteps = questList:GetQuestNumSteps(journalIndex) or 0
    for stepIndex = 1, numSteps do
        local stepText, visibility, stepType, trackerOverrideText =
            questList:GetQuestStepInfo(journalIndex, stepIndex)
        local conditions = collectQuestConditions(journalIndex, stepIndex)
        steps[#steps + 1] = {
            stepText = stepText,
            stepType = stepType,
            trackerOverrideText = trackerOverrideText,
            isVisible = visibility ~= rawget(_G, "QUEST_STEP_VISIBILITY_HIDDEN"),
            conditions = conditions,
        }
    end

    return steps
end

local function collectLocationInfo(journalIndex)
    local questList = getQuestList()
    if not (questList and questList.GetQuestLocation) then
        return nil
    end
    return questList:GetQuestLocation(journalIndex)
end

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
local groupEntryCache = {}

local function resolveDefinitionName(definition)
    if definition and definition.labelId and type(GetString) == "function" then
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

local function getGroupEntry(groupKey)
    groupKey = groupKey or DEFAULT_GROUP_KEY
    if groupEntryCache[groupKey] then
        return groupEntryCache[groupKey]
    end
    local definition = CATEGORY_GROUP_DEFINITIONS[groupKey] or CATEGORY_GROUP_DEFINITIONS[DEFAULT_GROUP_KEY]
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

local function buildLeafKey(groupEntry, identifier, name, orderSuffix)
    local parts = { groupEntry.key }
    if identifier ~= nil then
        parts[#parts + 1] = tostring(identifier)
    end
    local normalizedName = normalizeNameForKey(name)
    if normalizedName then
        parts[#parts + 1] = normalizedName
    end
    parts[#parts + 1] = tostring(orderSuffix or 0)
    return table.concat(parts, ":")
end

local function createLeafEntry(groupEntry, name, orderSuffix, categoryType, identifier, overrideKey)
    local leafOrder = orderSuffix or 0
    local key = overrideKey or buildLeafKey(groupEntry, identifier, name, leafOrder)
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

local function buildCategoryTypeToGroup()
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

local CATEGORY_TYPE_TO_GROUP = buildCategoryTypeToGroup()

local function getCategoryKey(questType, displayType, isRepeatable, isDaily)
    if displayType and CATEGORY_TYPE_TO_GROUP[displayType] then
        return CATEGORY_TYPE_TO_GROUP[displayType]
    end
    if isRepeatable or isDaily then
        return "REPEATABLE"
    end
    if questType and CATEGORY_TYPE_TO_GROUP[questType] then
        return CATEGORY_TYPE_TO_GROUP[questType]
    end
    return DEFAULT_GROUP_KEY
end

local function determineLegacyCategory(questType, displayType, isRepeatable, isDaily)
    local groupKey = getCategoryKey(questType, displayType, isRepeatable, isDaily)
    local groupEntry = getGroupEntry(groupKey)
    return createLeafEntry(groupEntry, groupEntry.name, 0, groupEntry.type, groupEntry.key, groupEntry.key)
end

local function resolveQuestCategory(journalIndex, questType, displayType, isRepeatable, isDaily)
    local questList = getQuestList()
    if not questList or not questList.GetQuestListData then
        return determineLegacyCategory(questType, displayType, isRepeatable, isDaily)
    end

    local list, categoryList, seenCategories = questList:GetQuestListData()
    if type(list) ~= "table" or type(categoryList) ~= "table" then
        return determineLegacyCategory(questType, displayType, isRepeatable, isDaily)
    end

    local categoriesByKey = {}
    local categoriesByName = {}
    for _, category in ipairs(categoryList) do
        if category.key and not categoriesByKey[category.key] then
            local entry = cloneCategoryEntry(category)
            categoriesByKey[entry.key] = entry
            if entry.name then
                categoriesByName[entry.name] = categoriesByName[entry.name] or {}
                table.insert(categoriesByName[entry.name], entry)
            end
        end
    end

    local listData = list[journalIndex]
    if type(listData) == "table" then
        local key = listData.categoryKey
        if key and categoriesByKey[key] then
            return cloneCategoryEntry(categoriesByKey[key])
        end
        local name = listData.categoryName
        if name and categoriesByName[name] and categoriesByName[name][1] then
            return cloneCategoryEntry(categoriesByName[name][1])
        end
    end

    return determineLegacyCategory(questType, displayType, isRepeatable, isDaily)
end

local function normalizeQuestCategoryData(quest)
    if type(quest) ~= "table" then
        return quest
    end
    quest.flags = quest.flags or {}
    if type(quest.category) ~= "table" then
        quest.category = determineLegacyCategory(
            quest.questType,
            quest.displayType,
            quest.flags.isRepeatable,
            quest.flags.isDaily
        )
    end
    local category = quest.category
    if not category.groupKey or not category.groupName or category.groupOrder == nil then
        local groupKey = category.groupKey
            or CATEGORY_TYPE_TO_GROUP[category.type]
            or (quest.meta and quest.meta.groupKey)
            or CATEGORY_TYPE_TO_GROUP[quest.meta and quest.meta.categoryType]
            or (category.parent and category.parent.key)
            or getCategoryKey(quest.questType, quest.displayType, quest.flags.isRepeatable, quest.flags.isDaily)
            or category.key
        local groupEntry = getGroupEntry(groupKey)
        category.groupKey = groupEntry.key
        category.groupName = groupEntry.name
        category.groupOrder = groupEntry.order
        category.groupType = groupEntry.type
    end
    category.parent = copyParentInfo(category.parent) or copyParentInfo({
        key = category.groupKey,
        name = category.groupName,
        order = category.groupOrder,
        type = category.groupType,
    })
    if not category.order then
        local orderBase = category.groupOrder or 0
        category.order = orderBase * 1000 + (category.rawOrder or 0)
    end
    quest.category = category
    quest.meta = quest.meta or {}
    local meta = quest.meta
    meta.questType = meta.questType or quest.questType
    meta.displayType = meta.displayType or quest.displayType
    meta.categoryType = meta.categoryType or category.type
    meta.categoryKey = meta.categoryKey or category.key
    meta.groupKey = meta.groupKey or category.groupKey
    meta.groupName = meta.groupName or category.groupName
    meta.parentKey = meta.parentKey or (category.parent and category.parent.key)
    meta.parentName = meta.parentName or (category.parent and category.parent.name)
    return quest
end

local function buildQuestSignature(quest)
    local parts = {}
    local function append(value)
        parts[#parts + 1] = tostring(value)
    end
    append(quest.journalIndex)
    append(quest.questId or "nil")
    append(quest.name or "")
    append(quest.zoneName or "")
    local category = quest.category or {}
    append(category.key or "nil")
    append((category.parent and category.parent.key) or "nil")
    append(category.type or "nil")
    append(category.groupKey or "nil")
    append(category.groupOrder or "nil")
    local meta = quest.meta or {}
    append(meta.parentKey or "nil")
    append(meta.categoryType or "nil")
    append(meta.groupKey or "nil")
    append(quest.flags.tracked and 1 or 0)
    append(quest.flags.assisted and 1 or 0)
    append(quest.flags.isComplete and 1 or 0)
    append(quest.flags.isRepeatable and 1 or 0)
    append(quest.flags.isDaily and 1 or 0)
    append(quest.questType or "nil")
    append(quest.displayType or "nil")
    append(quest.instanceDisplayType or "nil")
    for _, step in ipairs(quest.steps or {}) do
        append(step.stepText or "")
        append(step.stepType or "")
        append(step.isVisible and 1 or 0)
        append(step.isComplete and 1 or 0)
        for _, condition in ipairs(step.conditions or {}) do
            append(condition.text or "")
            append(condition.current or "")
            append(condition.max or "")
            append(condition.isComplete and 1 or 0)
            append(condition.isVisible and 1 or 0)
            append(condition.isFailCondition and 1 or 0)
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
    end
    return 1
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
    if left.questId and right.questId then
        return left.questId < right.questId
    end
    return (left.journalIndex or 0) < (right.journalIndex or 0)
end

local function buildCategoriesIndex(quests)
    local categoriesByKey = {}
    local orderedKeys = {}
    for _, quest in ipairs(quests) do
        local category = quest.category or {}
        local key = category.key or string.format("unknown:%d", quest.journalIndex or 0)
        local categoryEntry = categoriesByKey[key]
        if not categoryEntry then
            categoryEntry = cloneCategoryEntry(category) or { key = key, name = category.name or "" }
            categoryEntry.quests = {}
            categoryEntry.count = 0
            categoriesByKey[key] = categoryEntry
            orderedKeys[#orderedKeys + 1] = key
        end
        categoryEntry.quests[#categoryEntry.quests + 1] = quest
        categoryEntry.count = categoryEntry.count + 1
    end
    table.sort(orderedKeys, function(leftKey, rightKey)
        local leftEntry = categoriesByKey[leftKey]
        local rightEntry = categoriesByKey[rightKey]
        local leftOrder = leftEntry and leftEntry.order or 0
        local rightOrder = rightEntry and rightEntry.order or 0
        if leftOrder ~= rightOrder then
            return leftOrder < rightOrder
        end
        return leftKey < rightKey
    end)
    local orderedCategories = {}
    for index = 1, #orderedKeys do
        orderedCategories[index] = categoriesByKey[orderedKeys[index]]
    end
    return {
        byKey = categoriesByKey,
        ordered = orderedCategories,
    }
end

local function buildQuestEntry(listEntry)
    local questList = getQuestList()
    if not questList then
        return nil
    end
    if type(listEntry) ~= "table" then
        return nil
    end
    local journalIndex = listEntry.journalIndex
    if not journalIndex then
        return nil
    end
    local info = questList:GetQuestInfo(journalIndex)
    if not info or not info.name or info.name == "" then
        return nil
    end
    local questId = questList:GetQuestId(journalIndex)
    local isTracked = questList:IsQuestTracked(journalIndex)
    local isAssisted = questList:IsQuestAssisted(journalIndex)
    local isComplete = questList:IsQuestComplete(journalIndex)
    local category = resolveQuestCategory(journalIndex, info.questType, info.displayType, info.isRepeatable, info.isDaily)
    local objectives, fallbackStepText = collectQuestObjectives(journalIndex, isComplete)
    local questEntry = {
        key = listEntry.key or normalizeQuestKey(journalIndex),
        journalIndex = journalIndex,
        questId = questId,
        name = info.name,
        backgroundText = info.backgroundText,
        activeStepText = info.activeStepText or fallbackStepText,
        activeStepType = info.activeStepType,
        level = info.level,
        zoneName = info.zoneName or listEntry.zoneName,
        questType = info.questType,
        instanceDisplayType = info.instanceDisplayType,
        displayType = info.displayType,
        flags = {
            tracked = isTracked,
            assisted = isAssisted,
            isComplete = isComplete,
            isRepeatable = info.isRepeatable,
            isDaily = info.isDaily,
        },
        category = category,
        steps = collectQuestSteps(journalIndex),
        location = collectLocationInfo(journalIndex),
        description = info.description,
        objectives = objectives,
    }
    questEntry.meta = {
        questType = info.questType,
        displayType = info.displayType,
        categoryType = category and category.type or nil,
        categoryKey = category and category.key or nil,
        groupKey = category and category.groupKey or nil,
        groupName = category and category.groupName or nil,
        parentKey = category and category.parent and category.parent.key or nil,
        parentName = category and category.parent and category.parent.name or nil,
        zoneName = questEntry.zoneName,
        isRepeatable = info.isRepeatable,
        isDaily = info.isDaily,
    }
    normalizeQuestCategoryData(questEntry)
    questEntry.signature = buildQuestSignature(questEntry)
    return questEntry
end

local function collectQuestEntries()
    local questList = getQuestList()
    if not questList then
        return {}
    end
    if questList.RefreshFromGame then
        questList:RefreshFromGame()
    end
    local entries = questList.GetList and questList:GetList() or {}
    local quests = {}
    for index = 1, #entries do
        local questEntry = buildQuestEntry(entries[index])
        if questEntry then
            quests[#quests + 1] = questEntry
        end
    end
    table.sort(quests, compareQuestEntries)
    return quests
end

local function buildRows(quests)
    local rows = {}
    local questState = ensureQuestState()
    local questSelection = ensureQuestSelection()
    local activeKey = questSelection and questSelection:GetActiveQuestId() or nil
    local focusedKey = questSelection and questSelection:GetFocusedQuestId() or nil
    for index = 1, #quests do
        local quest = quests[index]
        local key = quest.key or normalizeQuestKey(quest.journalIndex)
        quest.isActive = (activeKey ~= nil and key ~= nil and activeKey == key) or false
        quest.isFocused = (focusedKey ~= nil and key ~= nil and focusedKey == key) or false
        quest.expanded = questState and questState:IsQuestExpanded(key) or false
        rows[#rows + 1] = quest
    end
    return rows
end

local function buildSectionsFromCategories(categories)
    local sections = {}
    for index = 1, #categories.ordered do
        local category = categories.ordered[index]
        sections[#sections + 1] = {
            id = category.key,
            title = category.name,
            count = #category.quests,
            rows = category.quests,
            groupKey = category.groupKey,
            groupName = category.groupName,
        }
    end
    return sections
end

M._version = M._version or 0
M._dirty = M._dirty ~= false
M._vm = M._vm or nil

function M:MarkDirty()
    self._dirty = true
end

function M:RefreshFromGame(force)
    local questList = getQuestList()
    if questList and questList.RefreshFromGame then
        questList:RefreshFromGame(force)
    end
    if not self._dirty and not force then
        return self._version
    end
    local quests = collectQuestEntries()
    local rows = buildRows(quests)
    local categories = buildCategoriesIndex(rows)
    local sections = buildSectionsFromCategories(categories)
    self._version = (self._version or 0) + 1
    self._vm = {
        version = self._version,
        total = #rows,
        indexByKey = {},
        indexByJournal = {},
        sections = sections,
        categories = categories,
        quests = rows,
        updatedAtMs = getTimestampMs(),
        signature = buildOverallSignature(rows),
    }
    for _, row in ipairs(rows) do
        local key = row.key or normalizeQuestKey(row.journalIndex)
        if key then
            self._vm.indexByKey[key] = row
        end
        if row.journalIndex then
            self._vm.indexByJournal[row.journalIndex] = row
        end
    end
    self._dirty = false
    debugLog("QuestModel: view built with %d quests (v%d).", #rows, self._version)
    return self._version
end

function M:GetViewData()
    return self._vm
end

function M:OnQuestAccepted(journalIndex)
    local questList = getQuestList()
    if questList and questList.OnQuestAccepted then
        questList:OnQuestAccepted(journalIndex)
    end
    self:MarkDirty()
end

function M:OnQuestUpdated(journalIndex)
    local questList = getQuestList()
    if questList and questList.OnQuestUpdated then
        questList:OnQuestUpdated(journalIndex)
    end
    self:MarkDirty()
end

function M:OnQuestRemoved(journalIndexOrKey)
    local questList = getQuestList()
    if questList and questList.OnQuestRemoved then
        questList:OnQuestRemoved(journalIndexOrKey)
    end

    local key = nil
    if type(journalIndexOrKey) == "string" then
        key = journalIndexOrKey
    elseif type(journalIndexOrKey) == "number" then
        key = questList and questList:GetKeyByJournalIndex(journalIndexOrKey) or normalizeQuestKey(journalIndexOrKey)
    end

    if key then
        local questState = ensureQuestState()
        if questState and questState.OnQuestRemoved then
            questState:OnQuestRemoved(key)
        end
        local questSelection = ensureQuestSelection()
        if questSelection and questSelection.OnQuestRemoved then
            questSelection:OnQuestRemoved(key, "model_remove")
        end
    end

    self:MarkDirty()
end

return M
