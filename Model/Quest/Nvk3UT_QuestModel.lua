local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local ResolveQuestCategory
local QuestState = Nvk3UT and Nvk3UT.QuestState
local QuestSelection = Nvk3UT and Nvk3UT.QuestSelection
local QuestList = Nvk3UT and Nvk3UT.QuestList

local function GetQuestState()
    if not QuestState and Nvk3UT then
        QuestState = Nvk3UT.QuestState
    end
    return QuestState
end

local function GetQuestSelection()
    if not QuestSelection and Nvk3UT then
        QuestSelection = Nvk3UT.QuestSelection
    end
    return QuestSelection
end

local function GetQuestList()
    if not QuestList and Nvk3UT then
        QuestList = Nvk3UT.QuestList
    end
    return QuestList
end

local function NormalizeQuestKey(journalIndex)
    if journalIndex == nil then
        return nil
    end

    if type(journalIndex) == "number" then
        if journalIndex > 0 then
            return tostring(journalIndex)
        end
        return nil
    end

    if type(journalIndex) == "string" then
        local numeric = tonumber(journalIndex)
        if numeric and numeric > 0 then
            return tostring(numeric)
        end
        if journalIndex ~= "" then
            return journalIndex
        end
        return nil
    end

    return tostring(journalIndex)
end

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
    local questList = GetQuestList()
    if not (questList and questList.GetQuestNumSteps and questList.GetQuestStepInfo) then
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
            stepIsVisible = true
        end

        if stepIsVisible then
            local fallbackStepCandidate = sanitizedOverrideText or sanitizedStepText
            if not fallbackStepText and fallbackStepCandidate then
                fallbackStepText = fallbackStepCandidate
            end

            fallbackObjectiveCandidate =
                NormalizeObjectiveDisplayText(trackerOverrideText) or NormalizeObjectiveDisplayText(stepText)
            if not fallbackObjectiveText and fallbackObjectiveCandidate then
                fallbackObjectiveText = fallbackObjectiveCandidate
            end

            local addedObjectiveForStep = false

            local totalConditions = tonumber(stepNumConditions) or 0
            local countedConditions = questList:GetQuestNumConditions(journalIndex, stepIndex)
            if type(countedConditions) == "number" and countedConditions > totalConditions then
                totalConditions = countedConditions
            end

            if totalConditions > 0 and questList.GetQuestConditionInfo then
                for conditionIndex = 1, totalConditions do
                    local conditionText, current, maxValue, isFailCondition, isConditionComplete, _, isConditionVisible =
                        questList:GetQuestConditionInfo(journalIndex, stepIndex, conditionIndex)
                    local formattedCondition = NormalizeObjectiveDisplayText(conditionText)
                    local isVisibleCondition = (isConditionVisible ~= false)
                    if questIsComplete and not isVisibleCondition then
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

local QuestModel = {}
QuestModel.__index = QuestModel

local QUEST_MODEL_NAME = addonName .. "QuestModel"
local EVENT_NAMESPACE = QUEST_MODEL_NAME .. "_Event"
local REBUILD_IDENTIFIER = QUEST_MODEL_NAME .. "_Rebuild"

local QUEST_SAVED_VARS_NAME = "Nvk3UT_Data_Quests"
local QUEST_SAVED_VARS_VERSION = 1
local QUEST_SAVED_VARS_DEFAULTS = {
    version = 1,
    meta = {
        initialized = false,
        lastInit = nil,
    },
    quests = {},
    settings = {
        autoVerticalResize = false,
    },
}

local questSavedVars = nil
local bootstrapState = {
    registered = false,
    executed = false,
}
local playerState = {
    hasActivated = false,
}

local DEBUG_INIT = false

local function IsDebugLoggingEnabled()
    if DEBUG_INIT then
        return true
    end

    local root = Nvk3UT and Nvk3UT.sv
    return root and root.debug == true
end

local function DebugInitLog(message, ...)
    if not IsDebugLoggingEnabled() then
        return
    end

    local formatted = message
    local argumentCount = select("#", ...)
    if argumentCount > 0 then
        formatted = string.format(message, ...)
    end

    if d then
        d(string.format("[Nvk3UT][QuestInit] %s", formatted))
    elseif print then
        print("[Nvk3UT][QuestInit]", formatted)
    end
end

local function CopyTable(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = CopyTable(entry)
    end
    return copy
end

local function EnsureSavedVars()
    if questSavedVars then
        return questSavedVars
    end

    if not ZO_SavedVars then
        questSavedVars = CopyTable(QUEST_SAVED_VARS_DEFAULTS)
        DebugInitLog("[Init] SavedVars ensured (fallback)")
        return questSavedVars
    end

    local sv = ZO_SavedVars:NewCharacterIdSettings(
        QUEST_SAVED_VARS_NAME,
        QUEST_SAVED_VARS_VERSION,
        nil,
        QUEST_SAVED_VARS_DEFAULTS
    )

    sv.version = sv.version or QUEST_SAVED_VARS_DEFAULTS.version

    if type(sv.meta) ~= "table" then
        sv.meta = {}
    end
    if sv.meta.initialized == nil then
        sv.meta.initialized = false
    else
        sv.meta.initialized = sv.meta.initialized == true
    end
    if sv.meta.lastInit ~= nil then
        local numeric = tonumber(sv.meta.lastInit)
        sv.meta.lastInit = numeric
    end

    if type(sv.quests) ~= "table" then
        sv.quests = {}
    end

    if type(sv.settings) ~= "table" then
        sv.settings = {}
    end
    if sv.settings.autoVerticalResize == nil then
        sv.settings.autoVerticalResize = false
    else
        sv.settings.autoVerticalResize = sv.settings.autoVerticalResize == true
    end

    questSavedVars = sv
    DebugInitLog("[Init] SavedVars ensured")
    return questSavedVars
end

local function MarkInitialized(sv)
    if not sv then
        return
    end

    sv.meta = sv.meta or {}
    sv.meta.initialized = true
    if GetTimeStamp then
        sv.meta.lastInit = GetTimeStamp()
    else
        sv.meta.lastInit = sv.meta.lastInit or 0
    end
end

local function PersistQuests(quests)
    local sv = EnsureSavedVars()
    if not sv then
        return 0
    end

    local stored = {}
    if type(quests) == "table" then
        for index = 1, #quests do
            stored[index] = CopyTable(quests[index])
        end
    end

    sv.quests = stored
    MarkInitialized(sv)
    return #stored
end

local function ShouldBootstrap(sv)
    if bootstrapState.executed then
        return false
    end

    if not sv then
        return false
    end

    local hasQuests = type(sv.quests) == "table" and next(sv.quests) ~= nil
    if not hasQuests then
        return true
    end

    if type(sv.meta) ~= "table" or sv.meta.initialized ~= true then
        return true
    end

    return false
end

local BuildSnapshotFromQuests
local CollectQuestEntries
local ForceRebuild
local NormalizeQuestCategoryData
local GetCategoryKey
local GetCategoryParentCopy

local function BuildSnapshotFromSaved()
    local sv = EnsureSavedVars()
    if not sv then
        return nil
    end

    if type(sv.quests) ~= "table" or next(sv.quests) == nil then
        return nil
    end

    local quests = {}
    for index = 1, #sv.quests do
        local questCopy = CopyTable(sv.quests[index])
        quests[index] = NormalizeQuestCategoryData(questCopy)
    end

    return BuildSnapshotFromQuests and BuildSnapshotFromQuests(quests) or nil
end

local function BootstrapQuestData()
    if bootstrapState.executed then
        return 0
    end

    local quests = CollectQuestEntries and CollectQuestEntries() or {}
    local stored = PersistQuests(quests)
    bootstrapState.executed = true
    DebugInitLog("[Init] BootstrapQuestData → %d quests stored", stored)
    return stored
end

local function OnPlayerActivated()
    if bootstrapState.registered and EVENT_MANAGER then
        EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE .. "PlayerActivated", EVENT_PLAYER_ACTIVATED)
        bootstrapState.registered = false
    end

    local sv = EnsureSavedVars()
    local requiresBootstrap = ShouldBootstrap(sv)
    DebugInitLog("[Init] OnPlayerActivated → Bootstrap required: %s", tostring(requiresBootstrap))

    playerState.hasActivated = true

    if requiresBootstrap then
        BootstrapQuestData()
    end

    if QuestModel.isInitialized and type(ForceRebuild) == "function" then
        ForceRebuild(QuestModel)
    end
end

local function RegisterForPlayerActivated()
    if bootstrapState.registered or not EVENT_MANAGER then
        return
    end

    EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE .. "PlayerActivated", EVENT_PLAYER_ACTIVATED, OnPlayerActivated)
    bootstrapState.registered = true
end

local function OnAddOnLoaded(_, name)
    if name ~= addonName then
        return
    end

    if EVENT_MANAGER then
        EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE .. "OnLoaded", EVENT_ADD_ON_LOADED)
    end

    EnsureSavedVars()
    RegisterForPlayerActivated()
    DebugInitLog("[Init] OnAddOnLoaded → SavedVars ready")
end

if EVENT_MANAGER then
    EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE .. "OnLoaded", EVENT_ADD_ON_LOADED, OnAddOnLoaded)
end

local MIN_DEBOUNCE_MS = 50
local MAX_DEBOUNCE_MS = 120
local DEFAULT_DEBOUNCE_MS = 80

local QUEST_LOG_LIMIT = 25

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

local function ResetBaseCategoryCache()
    baseCategoryCache = nil
end

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

local function BuildBaseCategoryCacheFromData(questList, categoryList)
    local categoriesByKey = {}
    local categoriesByName = {}
    local orderedCategories = {}

    for index = 1, #categoryList do
        local rawCategory = categoryList[index]
        local entry = NormalizeLeafCategory(rawCategory, index)
        orderedCategories[#orderedCategories + 1] = entry
        categoriesByKey[entry.key] = entry

        local categoryName = ExtractCategoryName(rawCategory)
        RegisterCategoryLookupVariants(categoriesByName, categoryName, entry)
    end

    local questCategoriesByJournalIndex = {}

    for index = 1, #questList do
        local questData = questList[index]
        local questIndex = ExtractQuestJournalIndex(questData)
        local categoryName = ExtractQuestCategoryName(questData)
        local categoryEntry = nil

        local possible = FetchCategoryCandidates(categoriesByName, categoryName)
        if categoryName and possible then
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

local function AcquireQuestJournalData()
    local questList = GetQuestList()
    if not (questList and questList.GetQuestListData) then
        return nil, nil, nil
    end

    local list, categoryList, seenCategories = questList:GetQuestListData()
    if type(list) ~= "table" or type(categoryList) ~= "table" then
        return nil, nil, nil
    end

    return list, categoryList, seenCategories
end

local function AcquireBaseCategoryCache()
    if baseCategoryCache then
        return baseCategoryCache
    end

    local questList, categoryList = AcquireQuestJournalData()
    if type(questList) ~= "table" or type(categoryList) ~= "table" then
        return nil
    end

    baseCategoryCache = BuildBaseCategoryCacheFromData(questList, categoryList)
    return baseCategoryCache
end
local function GetTimestampMs()
    if GetFrameTimeMilliseconds then
        return GetFrameTimeMilliseconds()
    end

    if GetGameTimeMilliseconds then
        return GetGameTimeMilliseconds()
    end

    if GetFrameTimeSeconds then
        return math.floor(GetFrameTimeSeconds() * 1000 + 0.5)
    end

    return nil
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

local function ClampDebounce(value)
    if value < MIN_DEBOUNCE_MS then
        return MIN_DEBOUNCE_MS
    elseif value > MAX_DEBOUNCE_MS then
        return MAX_DEBOUNCE_MS
    end
    return value
end

local function AppendSignaturePart(parts, value)
    parts[#parts + 1] = tostring(value)
end

local function BuildQuestSignature(quest)
    local parts = {}
    AppendSignaturePart(parts, quest.journalIndex)
    AppendSignaturePart(parts, quest.questId or "nil")
    AppendSignaturePart(parts, quest.name or "")
    AppendSignaturePart(parts, quest.zoneName or "")

    local category = quest.category or {}
    AppendSignaturePart(parts, category.key or "nil")
    AppendSignaturePart(parts, (category.parent and category.parent.key) or "nil")
    AppendSignaturePart(parts, category.type or "nil")
    AppendSignaturePart(parts, category.groupKey or "nil")
    AppendSignaturePart(parts, category.groupOrder or "nil")

    local meta = quest.meta or {}
    AppendSignaturePart(parts, meta.parentKey or "nil")
    AppendSignaturePart(parts, meta.categoryType or "nil")
    AppendSignaturePart(parts, meta.groupKey or "nil")

    AppendSignaturePart(parts, quest.flags.tracked and 1 or 0)
    AppendSignaturePart(parts, quest.flags.assisted and 1 or 0)
    AppendSignaturePart(parts, quest.flags.isComplete and 1 or 0)
    AppendSignaturePart(parts, quest.flags.isRepeatable and 1 or 0)
    AppendSignaturePart(parts, quest.flags.isDaily and 1 or 0)
    AppendSignaturePart(parts, quest.questType or "nil")
    AppendSignaturePart(parts, quest.displayType or "nil")
    AppendSignaturePart(parts, quest.instanceDisplayType or "nil")

    for stepIndex = 1, #quest.steps do
        local step = quest.steps[stepIndex]
        AppendSignaturePart(parts, step.stepText or "")
        AppendSignaturePart(parts, step.stepType or "")
        AppendSignaturePart(parts, step.isVisible and 1 or 0)
        AppendSignaturePart(parts, step.isComplete and 1 or 0)
        for conditionIndex = 1, #step.conditions do
            local condition = step.conditions[conditionIndex]
            AppendSignaturePart(parts, condition.text or "")
            AppendSignaturePart(parts, condition.current or "")
            AppendSignaturePart(parts, condition.max or "")
            AppendSignaturePart(parts, condition.isComplete and 1 or 0)
            AppendSignaturePart(parts, condition.isVisible and 1 or 0)
            AppendSignaturePart(parts, condition.isFailCondition and 1 or 0)
        end
    end

    return table.concat(parts, "|")
end

local function BuildOverallSignature(quests)
    local parts = {}
    for index = 1, #quests do
        parts[index] = quests[index].signature
    end
    return table.concat(parts, "\31")
end

function GetCategoryKey(questType, displayType, isRepeatable, isDaily)
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
    local cache = AcquireBaseCategoryCache()
    if cache and cache.byJournalIndex then
        local entry = cache.byJournalIndex[journalQuestIndex]
        if entry then
            return CloneCategoryEntry(entry)
        end
    end

    return DetermineLegacyCategory(questType, displayType, isRepeatable, isDaily)
end

ResolveQuestCategory = ResolveQuestCategoryInternal

function NormalizeQuestCategoryData(quest)
    if type(quest) ~= "table" then
        return quest
    end

    quest.flags = quest.flags or {}

    if type(quest.category) ~= "table" then
        local fallback = DetermineLegacyCategory(quest.questType, quest.displayType, quest.flags.isRepeatable, quest.flags.isDaily)
        quest.category = CloneCategoryEntry(fallback)
    end

    local category = quest.category

    if not category.groupKey or not category.groupName or category.groupOrder == nil then
        local groupKey = category.groupKey
            or CATEGORY_TYPE_TO_GROUP[category.type]
            or (quest.meta and quest.meta.groupKey)
            or CATEGORY_TYPE_TO_GROUP[quest.meta and quest.meta.categoryType]
            or (category.parent and category.parent.key)
            or GetCategoryKey(quest.questType, quest.displayType, quest.flags.isRepeatable, quest.flags.isDaily)
            or category.key

        local groupEntry = GetGroupEntry(groupKey)
        category.groupKey = groupEntry.key
        category.groupName = groupEntry.name
        category.groupOrder = groupEntry.order
        category.groupType = groupEntry.type
    end

    category.parent = GetCategoryParentCopy(category)

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
    meta.zoneName = meta.zoneName or quest.zoneName

    if meta.isRepeatable == nil then
        meta.isRepeatable = quest.flags.isRepeatable
    end

    if meta.isDaily == nil then
        meta.isDaily = quest.flags.isDaily
    end

    return quest
end

local function CollectQuestSteps(journalQuestIndex)
    local questList = GetQuestList()
    if not (questList and questList.GetQuestNumSteps and questList.GetQuestStepInfo) then
        return {}
    end

    local steps = {}
    local numSteps = questList:GetQuestNumSteps(journalQuestIndex) or 0
    for stepIndex = 1, numSteps do
        local stepText, stepType, numConditions, isVisible, isComplete, isOptional, isTracked =
            questList:GetQuestStepInfo(journalQuestIndex, stepIndex)
        numConditions = tonumber(numConditions) or 0
        local stepEntry = {
            stepIndex = stepIndex,
            stepText = stepText,
            stepType = stepType,
            numConditions = numConditions,
            isVisible = not not isVisible,
            isComplete = not not isComplete,
            isOptional = not not isOptional,
            isTracked = not not isTracked,
            conditions = {},
        }

        local conditions = stepEntry.conditions
        for conditionIndex = 1, numConditions do
            local conditionText, current, maxValue, isFailCondition, isConditionComplete, isCreditShared, isConditionVisible =
                questList:GetQuestConditionInfo(journalQuestIndex, stepIndex, conditionIndex)
            conditions[#conditions + 1] = {
                conditionIndex = conditionIndex,
                text = conditionText,
                current = current,
                max = maxValue,
                isFailCondition = not not isFailCondition,
                isComplete = not not isConditionComplete,
                isCreditShared = not not isCreditShared,
                isVisible = not not isConditionVisible,
            }
        end

        steps[#steps + 1] = stepEntry
    end

    return steps
end

local function CollectLocationInfo(journalQuestIndex)
    local questList = GetQuestList()
    if not (questList and questList.GetQuestLocation) then
        return nil
    end

    return questList:GetQuestLocation(journalQuestIndex)
end

local function BuildQuestEntry(listEntry)
    local questList = GetQuestList()
    if not questList then
        return nil
    end

    if type(listEntry) ~= "table" then
        return nil
    end

    local journalQuestIndex = listEntry.journalIndex
    if not journalQuestIndex then
        return nil
    end

    local info = questList:GetQuestInfo(journalQuestIndex)
    if not info or not info.name or info.name == "" then
        return nil
    end

    local questName = info.name
    local questId = questList:GetQuestId(journalQuestIndex)
    local isTracked = questList:IsQuestTracked(journalQuestIndex)
    local isAssisted = questList:IsQuestAssisted(journalQuestIndex)
    local isComplete = questList:IsQuestComplete(journalQuestIndex)
    local category = ResolveQuestCategory and ResolveQuestCategory(
        journalQuestIndex,
        info.questType,
        info.displayType,
        info.isRepeatable,
        info.isDaily
    )

    local zoneName = info.zoneName or listEntry.zoneName

    local questEntry = {
        journalIndex = journalQuestIndex,
        questId = questId,
        name = questName,
        backgroundText = info.backgroundText,
        activeStepText = info.activeStepText,
        activeStepType = info.activeStepType,
        level = info.level,
        zoneName = zoneName,
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
        steps = CollectQuestSteps(journalQuestIndex),
        location = CollectLocationInfo(journalQuestIndex),
        description = info.description,
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
        zoneName = zoneName,
        isRepeatable = info.isRepeatable,
        isDaily = info.isDaily,
    }

    NormalizeQuestCategoryData(questEntry)

    questEntry.signature = BuildQuestSignature(questEntry)

    return questEntry
end

local function CompareStrings(left, right)
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

local function CompareQuestEntries(left, right)
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

    local zoneCompare = CompareStrings(left.zoneName, right.zoneName)
    if zoneCompare ~= 0 then
        return zoneCompare < 0
    end

    local nameCompare = CompareStrings(left.name, right.name)
    if nameCompare ~= 0 then
        return nameCompare < 0
    end

    if left.questId and right.questId then
        return left.questId < right.questId
    end

    return left.journalIndex < right.journalIndex
end

local function LogDebug(self, ...)
    if not self.debugEnabled then
        return
    end

    if d then
        d(string.format("[%s]", QUEST_MODEL_NAME), ...)
    elseif print then
        print("[" .. QUEST_MODEL_NAME .. "]", ...)
    end
end

local function RegisterQuestEvent(eventId, handler)
    EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE .. tostring(eventId), eventId, handler)
end

local function UnregisterQuestEvent(eventId)
    EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE .. tostring(eventId), eventId)
end

local function NotifySubscribers(self)
    if not self.subscribers then
        return
    end

    for callback in pairs(self.subscribers) do
        local success, err = pcall(callback, self.currentSnapshot)
        if not success then
            LogDebug(self, "Subscriber callback failed", err)
        end
    end
end

GetCategoryParentCopy = function(category)
    if not category then
        return nil
    end

    if category.parent then
        return CopyParentInfo(category.parent)
    end

    if category.groupKey or category.groupName then
        return CopyParentInfo({
            key = category.groupKey,
            name = category.groupName,
            order = category.groupOrder,
            type = category.groupType,
        })
    end

    return nil
end

local function BuildCategoriesIndex(quests)
    local categoriesByKey = {}
    local orderedKeys = {}

    for index = 1, #quests do
        local quest = quests[index]
        local category = quest.category or {}
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
                parent = GetCategoryParentCopy(category),
                quests = {},
            }
            categoriesByKey[key] = categoryEntry
            orderedKeys[#orderedKeys + 1] = key
        end
        categoryEntry.quests[#categoryEntry.quests + 1] = quest
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
        orderedCategories[index] = categoriesByKey[key]
    end

    return {
        byKey = categoriesByKey,
        ordered = orderedCategories,
    }
end

CollectQuestEntries = function()
    local quests = {}

    local questList = GetQuestList()
    if not questList then
        return quests
    end

    if questList.RefreshFromGame then
        questList:RefreshFromGame()
    end

    local entries = questList.GetList and questList:GetList() or {}
    for index = 1, #entries do
        local questEntry = BuildQuestEntry(entries[index])
        if questEntry then
            quests[#quests + 1] = questEntry
        end
    end

    table.sort(quests, CompareQuestEntries)
    return quests
end

BuildSnapshotFromQuests = function(quests)
    if type(quests) ~= "table" then
        quests = {}
    end

    for index = 1, #quests do
        quests[index] = NormalizeQuestCategoryData(quests[index])
    end

    local snapshot = {
        updatedAtMs = GetTimestampMs(),
        quests = quests,
        categories = BuildCategoriesIndex(quests),
        signature = BuildOverallSignature(quests),
        questById = {},
        questByJournalIndex = {},
    }

    for index = 1, #quests do
        local quest = quests[index]
        if quest then
            if quest.questId then
                snapshot.questById[quest.questId] = quest
            end
            if quest.journalIndex then
                snapshot.questByJournalIndex[quest.journalIndex] = quest
            end
        end
    end

    return snapshot
end

local function BuildSnapshot(self)
    local quests = CollectQuestEntries()
    local snapshot = BuildSnapshotFromQuests(quests)
    return snapshot, quests
end

local function SnapshotsDiffer(previous, current)
    if not previous then
        return true
    end
    return previous.signature ~= current.signature
end

local function PerformRebuild(self)
    if not self.isInitialized or not playerState.hasActivated then
        return false
    end

    local snapshot, quests = BuildSnapshot(self)
    if not snapshot then
        return false
    end

    if not SnapshotsDiffer(self.currentSnapshot, snapshot) then
        PersistQuests(quests)
        return false
    end

    snapshot.revision = (self.currentSnapshot and self.currentSnapshot.revision or 0) + 1
    self.currentSnapshot = snapshot
    PersistQuests(quests)
    NotifySubscribers(self)
    return true
end

local function ScheduleRebuild(self)
    if not playerState.hasActivated then
        return
    end

    if self.pendingRebuild then
        return
    end

    self.pendingRebuild = true

    local interval = self.debounceMs or DEFAULT_DEBOUNCE_MS

    EVENT_MANAGER:RegisterForUpdate(
        REBUILD_IDENTIFIER,
        interval,
        function()
            EVENT_MANAGER:UnregisterForUpdate(REBUILD_IDENTIFIER)
            self.pendingRebuild = false
            PerformRebuild(self)
        end
    )
end

ForceRebuild = function(self)
    if not self.isInitialized or not playerState.hasActivated then
        return false
    end

    if self.pendingRebuild then
        EVENT_MANAGER:UnregisterForUpdate(REBUILD_IDENTIFIER)
        self.pendingRebuild = false
    end

    local updated = PerformRebuild(self)
    return updated
end

local function OnQuestChanged(eventCode, ...)
    local self = QuestModel
    if not self.isInitialized or not playerState.hasActivated then
        return
    end

    local questList = GetQuestList()
    if questList then
        local journalIndex = select(1, ...)
        if eventCode == EVENT_QUEST_ADDED and questList.OnQuestAccepted then
            if journalIndex then
                questList:OnQuestAccepted(journalIndex)
            else
                questList:MarkDirty()
            end
        elseif eventCode ~= EVENT_QUEST_REMOVED and questList.OnQuestUpdated then
            if journalIndex then
                questList:OnQuestUpdated(journalIndex)
            else
                questList:MarkDirty()
            end
        elseif questList.MarkDirty then
            questList:MarkDirty()
        end
    end

    ResetBaseCategoryCache()
    ScheduleRebuild(self)
end

local function OnQuestRemoved(eventCode, isCompleted, journalIndex, ...)
    local questList = GetQuestList()
    if questList then
        if journalIndex and questList.OnQuestRemoved then
            questList:OnQuestRemoved(journalIndex)
        elseif questList.MarkDirty then
            questList:MarkDirty()
        end
    end

    local normalized = NormalizeQuestKey(journalIndex)
    if normalized then
        local questStateModule = GetQuestState()
        if questStateModule then
            if not questStateModule.db and type(questStateModule.Init) == "function" then
                questStateModule:Init()
            end
            if questStateModule.OnQuestRemoved then
                questStateModule:OnQuestRemoved(normalized)
            end
        end

        local questSelectionModule = GetQuestSelection()
        if questSelectionModule then
            if not questSelectionModule.db and type(questSelectionModule.Init) == "function" then
                questSelectionModule:Init()
            end
            if questSelectionModule.OnQuestRemoved then
                local reason = isCompleted and "completed" or "abandon"
                questSelectionModule:OnQuestRemoved(normalized, reason)
            end
        end
    end

    OnQuestChanged(eventCode, isCompleted, journalIndex, ...)
end

local function OnTrackingUpdate(eventCode, trackingType)
    if trackingType ~= TRACK_TYPE_QUEST then
        return
    end
    OnQuestChanged(eventCode)
end

function QuestModel.Init(opts)
    if QuestModel.isInitialized then
        return
    end

    opts = opts or {}

    EnsureSavedVars()
    RegisterForPlayerActivated()

    QuestModel.debugEnabled = opts.debug or false

    local requestedDebounce = tonumber(opts.debounceMs)
    if requestedDebounce then
        QuestModel.debounceMs = ClampDebounce(requestedDebounce)
    else
        QuestModel.debounceMs = DEFAULT_DEBOUNCE_MS
    end
    QuestModel.subscribers = {}
    QuestModel.isInitialized = true

    local savedSnapshot = BuildSnapshotFromSaved()
    if savedSnapshot then
        savedSnapshot.revision = (QuestModel.currentSnapshot and QuestModel.currentSnapshot.revision) or 0
        QuestModel.currentSnapshot = savedSnapshot
    else
        QuestModel.currentSnapshot = nil
    end

    local eventHandler = function(...)
        OnQuestChanged(...)
    end

    RegisterQuestEvent(EVENT_QUEST_ADDED, eventHandler)
    RegisterQuestEvent(EVENT_QUEST_REMOVED, OnQuestRemoved)
    RegisterQuestEvent(EVENT_QUEST_ADVANCED, eventHandler)
    RegisterQuestEvent(EVENT_QUEST_CONDITION_COUNTER_CHANGED, eventHandler)
    RegisterQuestEvent(EVENT_QUEST_LOG_UPDATED, eventHandler)
    EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE .. "TRACKING", EVENT_TRACKING_UPDATE, OnTrackingUpdate)

    if playerState.hasActivated then
        ForceRebuild(QuestModel)
    end

    if QuestModel.currentSnapshot and next(QuestModel.subscribers) then
        NotifySubscribers(QuestModel)
    end
end

function QuestModel.Shutdown()
    if not QuestModel.isInitialized then
        return
    end

    UnregisterQuestEvent(EVENT_QUEST_ADDED)
    UnregisterQuestEvent(EVENT_QUEST_REMOVED)
    UnregisterQuestEvent(EVENT_QUEST_ADVANCED)
    UnregisterQuestEvent(EVENT_QUEST_CONDITION_COUNTER_CHANGED)
    UnregisterQuestEvent(EVENT_QUEST_LOG_UPDATED)
    EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE .. "TRACKING", EVENT_TRACKING_UPDATE)
    EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE .. "OnLoaded", EVENT_ADD_ON_LOADED)
    EVENT_MANAGER:UnregisterForUpdate(REBUILD_IDENTIFIER)
    EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE .. "PlayerActivated", EVENT_PLAYER_ACTIVATED)
    bootstrapState.registered = false
    playerState.hasActivated = false

    QuestModel.isInitialized = false
    QuestModel.subscribers = nil
    QuestModel.currentSnapshot = nil
    QuestModel.pendingRebuild = nil
    groupEntryCache = {}
    ResetBaseCategoryCache()
end

function QuestModel.GetSnapshot()
    return QuestModel.currentSnapshot
end

function QuestModel.Subscribe(callback)
    assert(type(callback) == "function", "QuestModel.Subscribe expects a function")

    QuestModel.subscribers = QuestModel.subscribers or {}
    QuestModel.subscribers[callback] = true

    if QuestModel.isInitialized and playerState.hasActivated and not QuestModel.currentSnapshot then
        ForceRebuild(QuestModel)
    end

    callback(QuestModel.currentSnapshot)
end

function QuestModel.Unsubscribe(callback)
    if QuestModel.subscribers then
        QuestModel.subscribers[callback] = nil
    end
end

Nvk3UT.QuestModel = QuestModel

return QuestModel
