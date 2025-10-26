local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local ResolveQuestCategory

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

local function ResolveDefinitionName(definition)
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

local groupEntryCache = {}

local function GetGroupDefinition(groupKey)
    return CATEGORY_GROUP_DEFINITIONS[groupKey] or CATEGORY_GROUP_DEFINITIONS[DEFAULT_GROUP_KEY]
end

local function GetGroupEntry(groupKey)
    groupKey = groupKey or DEFAULT_GROUP_KEY

    if groupEntryCache[groupKey] then
        return groupEntryCache[groupKey]
    end

    local definition = GetGroupDefinition(groupKey)
    local entry = {
        key = groupKey,
        name = ResolveDefinitionName(definition),
        order = definition and definition.order or 0,
        type = definition and definition.typeId or nil,
    }

    groupEntryCache[groupKey] = entry
    return entry
end

local function CopyParentInfo(parent)
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

local function NormalizeNameForKey(name)
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

local function RegisterCategoryName(lookup, name, entry)
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

local function RegisterCategoryLookupVariants(lookup, name, entry)
    if not lookup or not entry then
        return
    end

    RegisterCategoryName(lookup, name, entry)

    local normalized = NormalizeNameForKey(name)
    if normalized and normalized ~= name then
        RegisterCategoryName(lookup, normalized, entry)
    end
end

local function FetchCategoryCandidates(lookup, name)
    if not lookup then
        return nil
    end

    if not name or name == "" then
        return nil
    end

    local candidates = lookup[name]
    if candidates then
        return candidates
    end

    local normalized = NormalizeNameForKey(name)
    if normalized then
        return lookup[normalized]
    end

    return nil
end

local function BuildLeafKey(groupEntry, identifier, name, orderSuffix)
    local parts = { groupEntry.key }

    if identifier ~= nil then
        parts[#parts + 1] = tostring(identifier)
    end

    local normalizedName = NormalizeNameForKey(name)
    if normalizedName then
        parts[#parts + 1] = normalizedName
    end

    parts[#parts + 1] = tostring(orderSuffix or 0)

    return table.concat(parts, ":")
end

local function CreateLeafEntry(groupEntry, name, orderSuffix, categoryType, identifier, overrideKey)
    local leafOrder = orderSuffix or 0
    local key = overrideKey or BuildLeafKey(groupEntry, identifier, name, leafOrder)

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

    entry.parent = CopyParentInfo({
        key = groupEntry.key,
        name = groupEntry.name,
        order = groupEntry.order,
        type = groupEntry.type,
    })

    return entry
end

local function CloneCategoryEntry(entry)
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
        copy.parent = CopyParentInfo(entry.parent)
    elseif entry.groupKey or entry.groupName then
        copy.parent = CopyParentInfo({
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

local function BuildCategoryTypeToGroupMapping()
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

local CATEGORY_TYPE_TO_GROUP = BuildCategoryTypeToGroupMapping()

local function ExtractCategoryName(categoryData)
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

local function ExtractCategoryType(categoryData)
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

local function ExtractCategoryIdentifier(categoryData)
    if type(categoryData) ~= "table" then
        return nil
    end

    local fields = { "categoryId", "categoryIndex", "categoryId64", "index", "id", "dataId" }
    for index = 1, #fields do
        local fieldName = fields[index]
        local value = categoryData[fieldName]
        if value ~= nil then
            return value
        end

        local getterName = string.format("Get%s", fieldName:gsub("^%l", string.upper))
        local getter = categoryData[getterName]
        if type(getter) == "function" then
            local ok, result = pcall(getter, categoryData)
            if ok and result ~= nil then
                return result
            end
        end
    end

    return nil
end

local function ExtractQuestJournalIndex(questData)
    if type(questData) ~= "table" then
        return nil
    end

    if type(questData.questIndex) == "number" then
        return questData.questIndex
    end

    if type(questData.journalIndex) == "number" then
        return questData.journalIndex
    end

    local getter = questData.GetQuestIndex or questData.GetJournalIndex
    if type(getter) == "function" then
        local ok, value = pcall(getter, questData)
        if ok then
            return value
        end
    end

    return nil
end

local function ExtractQuestCategoryName(questData)
    if type(questData) ~= "table" then
        return nil
    end

    if questData.categoryName ~= nil then
        return questData.categoryName
    end

    if questData.name ~= nil and questData.category ~= nil then
        return questData.category
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

local function ExtractQuestCategoryType(questData)
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

local function NormalizeLeafCategory(categoryData, orderIndex)
    local categoryType = ExtractCategoryType(categoryData)
    local groupKey = CATEGORY_TYPE_TO_GROUP[categoryType] or DEFAULT_GROUP_KEY
    local groupEntry = GetGroupEntry(groupKey)
    local name = ExtractCategoryName(categoryData) or groupEntry.name
    local identifier = ExtractCategoryIdentifier(categoryData)

    return CreateLeafEntry(groupEntry, name, orderIndex or 0, categoryType, identifier)
end

local function BuildQuestCategoryCache()
    local manager = rawget(_G, "QUEST_JOURNAL_MANAGER")
    if type(manager) ~= "table" or type(manager.GetQuestListData) ~= "function" then
        return nil
    end

    local ok, questList, categoryList = pcall(manager.GetQuestListData, manager)
    if not ok or type(questList) ~= "table" or type(categoryList) ~= "table" then
        return nil
    end

    local categoriesByName = {}

    for index = 1, #categoryList do
        local rawCategory = categoryList[index]
        local entry = NormalizeLeafCategory(rawCategory, index)
        RegisterCategoryLookupVariants(categoriesByName, entry.name, entry)
    end

    local questCategoriesByJournalIndex = {}

    for index = 1, #questList do
        local questData = questList[index]
        local questIndex = ExtractQuestJournalIndex(questData)
        local categoryName = ExtractQuestCategoryName(questData)
        local possible = FetchCategoryCandidates(categoriesByName, categoryName)
        local categoryEntry = nil

        if possible then
            if #possible == 1 then
                categoryEntry = possible[1]
            else
                local candidateType = ExtractQuestCategoryType(questData)
                if candidateType ~= nil then
                    for _, entry in ipairs(possible) do
                        if entry.type == candidateType then
                            categoryEntry = entry
                            break
                        end
                    end
                end
                categoryEntry = categoryEntry or possible[1]
            end
        end

        if questIndex and categoryEntry then
            questCategoriesByJournalIndex[questIndex] = categoryEntry
        end
    end

    return {
        byJournalIndex = questCategoriesByJournalIndex,
    }
end

local function BuildQuestTypeMapping()
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

local function BuildDisplayTypeMapping()
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

local QUEST_TYPE_TO_CATEGORY = BuildQuestTypeMapping()
local QUEST_DISPLAY_TYPE_TO_CATEGORY = BuildDisplayTypeMapping()

local function GetCategoryKey(questType, displayType, isRepeatable, isDaily)
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

local function DetermineLegacyCategory(questType, displayType, isRepeatable, isDaily)
    local key = GetCategoryKey(questType, displayType, isRepeatable, isDaily)
    local groupEntry = GetGroupEntry(key)
    return CreateLeafEntry(groupEntry, groupEntry.name, 0, groupEntry.type, groupEntry.key, groupEntry.key)
end

local function ResolveQuestCategoryInternal(journalQuestIndex, questType, displayType, isRepeatable, isDaily)
    local cache = BuildQuestCategoryCache()
    if cache and cache.byJournalIndex then
        local entry = cache.byJournalIndex[journalQuestIndex]
        if entry then
            return CloneCategoryEntry(entry)
        end
    end

    return DetermineLegacyCategory(questType, displayType, isRepeatable, isDaily)
end

ResolveQuestCategory = ResolveQuestCategoryInternal

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

    record.categoryKey = record.categoryKey or "MISC"
    record.categoryName = record.categoryName or "Miscellaneous"
    record.parentKey = record.parentKey or record.categoryKey
    record.parentName = record.parentName or record.categoryName

    if d then
        d(string.format(
            "[Nvk3UT] Quest %s -> category=%s (%s) parent=%s",
            tostring(record.name),
            tostring(record.categoryName),
            tostring(record.categoryKey),
            tostring(record.parentName)
        ))
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

        d(string.format(
            "[Nvk3UT] FullSync() -> quests=%d, version=%d",
            questCount,
            LocalQuestDB.version
        ))
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

end

local function BuildVisibleQuestSnapshot(record)
    if not record then
        return nil
    end

    local snapshot = {
        name = record.name,
        categoryKey = record.categoryKey,
        categoryName = record.categoryName,
        objectives = {},
    }

    local objectives = record.objectives or {}
    for index = 1, #objectives do
        local objective = objectives[index]
        snapshot.objectives[index] = {
            displayText = objective and objective.displayText or nil,
            isTurnIn = not not (objective and objective.isTurnIn),
        }
    end

    return snapshot
end

local function AreVisibleQuestDetailsUnchanged(oldSnapshot, newSnapshot)
    if (not oldSnapshot) or (not newSnapshot) then
        return false
    end

    if oldSnapshot.name ~= newSnapshot.name then
        return false
    end

    if oldSnapshot.categoryKey ~= newSnapshot.categoryKey then
        return false
    end

    if oldSnapshot.categoryName ~= newSnapshot.categoryName then
        return false
    end

    local oldObjectives = oldSnapshot.objectives or {}
    local newObjectives = newSnapshot.objectives or {}

    if #oldObjectives ~= #newObjectives then
        return false
    end

    for index = 1, #oldObjectives do
        local oldObjective = oldObjectives[index]
        local newObjective = newObjectives[index]

        if (not oldObjective) or (not newObjective) then
            return false
        end

        if oldObjective.displayText ~= newObjective.displayText then
            return false
        end

        if oldObjective.isTurnIn ~= newObjective.isTurnIn then
            return false
        end
    end

    return true
end

function Nvk3UT_ProcessSingleQuestUpdate(journalIndex)
    if type(journalIndex) ~= "number" then
        return
    end

    LocalQuestDB = LocalQuestDB or { quests = {}, version = 0 }

    local questsTable = LocalQuestDB.quests or {}
    local oldRecord = questsTable[journalIndex]
    local oldSnapshot = BuildVisibleQuestSnapshot(oldRecord)

    UpdateSingleQuest(journalIndex)

    questsTable = LocalQuestDB.quests or {}
    local newRecord = questsTable[journalIndex]

    if not newRecord then
        RedrawSingleQuestFromLocalDB(journalIndex)
        return
    end

    local newSnapshot = BuildVisibleQuestSnapshot(newRecord)

    if AreVisibleQuestDetailsUnchanged(oldSnapshot, newSnapshot) then
        return
    end

    RedrawSingleQuestFromLocalDB(journalIndex)
end

function RemoveQuestFromLocalQuestDB(journalIndex)
    LocalQuestDB = LocalQuestDB or { quests = {}, version = 0 }

    LocalQuestDB.quests[journalIndex] = nil
    LocalQuestDB.version = (LocalQuestDB.version or 0) + 1

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
