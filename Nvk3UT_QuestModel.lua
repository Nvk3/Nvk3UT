local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

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
        quests[index] = CopyTable(sv.quests[index])
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

    if QuestModel.isInitialized then
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

local CATEGORY_DEFINITIONS = {
    MAIN_STORY = { order = 10, labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_MAIN_STORY"), fallbackName = "Main Story" },
    ZONE_STORY = { order = 20, labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_ZONE_STORY"), fallbackName = "Zone Story" },
    GUILD = { order = 30, labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_GUILD"), fallbackName = "Guild" },
    CRAFTING = { order = 40, labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_CRAFTING"), fallbackName = "Crafting" },
    DUNGEON = { order = 50, labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_DUNGEON"), fallbackName = "Dungeon" },
    ALLIANCE_WAR = { order = 60, labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_ALLIANCE_WAR"), fallbackName = "Alliance War" },
    PROLOGUE = { order = 70, labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_PROLOGUE"), fallbackName = "Prologue" },
    REPEATABLE = { order = 80, labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_REPEATABLE"), fallbackName = "Repeatable" },
    COMPANION = { order = 90, labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_COMPANION"), fallbackName = "Companion" },
    MISC = { order = 100, labelId = rawget(_G, "SI_QUEST_JOURNAL_CATEGORY_MISC"), fallbackName = "Miscellaneous" },
}

local DEFAULT_CATEGORY_KEY = "MISC"

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

local function GetCategoryName(definition)
    if definition.labelId and GetString then
        local label = GetString(definition.labelId)
        if label and label ~= "" then
            return label
        end
    end
    return definition.fallbackName
end

local function BuildCategoryEntry(key)
    local definition = CATEGORY_DEFINITIONS[key] or CATEGORY_DEFINITIONS[DEFAULT_CATEGORY_KEY]
    return {
        key = key,
        name = GetCategoryName(definition),
        order = definition.order,
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
    AppendSignaturePart(parts, quest.category.key)
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

    return DEFAULT_CATEGORY_KEY
end

local function DetermineCategory(questType, displayType, isRepeatable, isDaily)
    local key = GetCategoryKey(questType, displayType, isRepeatable, isDaily)
    return BuildCategoryEntry(key)
end

local function CollectQuestSteps(journalQuestIndex)
    if not GetJournalQuestNumSteps or not GetJournalQuestStepInfo then
        return {}
    end

    local steps = {}
    local numSteps = GetJournalQuestNumSteps(journalQuestIndex) or 0
    for stepIndex = 1, numSteps do
        local stepText, stepType, numConditions, isVisible, isComplete, isOptional, isTracked = GetJournalQuestStepInfo(journalQuestIndex, stepIndex)
        numConditions = numConditions or 0
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
            local conditionText, current, maxValue, isFailCondition, isConditionComplete, isCreditShared, isConditionVisible
            if GetJournalQuestConditionInfo then
                conditionText, current, maxValue, isFailCondition, isConditionComplete, isCreditShared, isConditionVisible = GetJournalQuestConditionInfo(journalQuestIndex, stepIndex, conditionIndex)
            end
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
    if not GetJournalQuestLocationInfo then
        return nil
    end

    local zoneName, subZoneName, zoneIndex, poiIndex = GetJournalQuestLocationInfo(journalQuestIndex)
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

local function BuildQuestEntry(journalQuestIndex)
    local questName, backgroundText, activeStepText, activeStepType, questLevel, zoneName, questType, instanceDisplayType, isRepeatable, isDaily, questDescription, displayType = GetJournalQuestInfo(journalQuestIndex)
    if not questName or questName == "" then
        return nil
    end

    isRepeatable = not not isRepeatable
    isDaily = not not isDaily

    local questId = GetJournalQuestId and GetJournalQuestId(journalQuestIndex) or nil
    local isTracked = IsJournalQuestTracked and IsJournalQuestTracked(journalQuestIndex) or false
    isTracked = not not isTracked
    local isAssisted = false
    if GetTrackedIsAssisted and isTracked then
        isAssisted = GetTrackedIsAssisted(TRACK_TYPE_QUEST, journalQuestIndex) or false
    end
    isAssisted = not not isAssisted

    local isComplete = false
    if GetJournalQuestIsComplete then
        isComplete = GetJournalQuestIsComplete(journalQuestIndex)
    elseif IsJournalQuestComplete then
        isComplete = IsJournalQuestComplete(journalQuestIndex)
    end
    isComplete = not not isComplete

    local category = DetermineCategory(questType, displayType, isRepeatable, isDaily)

    local questEntry = {
        journalIndex = journalQuestIndex,
        questId = questId,
        name = questName,
        backgroundText = backgroundText,
        activeStepText = activeStepText,
        activeStepType = activeStepType,
        level = questLevel,
        zoneName = zoneName,
        questType = questType,
        instanceDisplayType = instanceDisplayType,
        displayType = displayType,
        flags = {
            tracked = isTracked,
            assisted = isAssisted,
            isComplete = isComplete,
            isRepeatable = isRepeatable,
            isDaily = isDaily,
        },
        category = category,
        steps = CollectQuestSteps(journalQuestIndex),
        location = CollectLocationInfo(journalQuestIndex),
        description = questDescription,
    }

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
    if left.category.order ~= right.category.order then
        return left.category.order < right.category.order
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

local function BuildCategoriesIndex(quests)
    local categoriesByKey = {}
    local orderedKeys = {}

    for index = 1, #quests do
        local quest = quests[index]
        local key = quest.category.key
        local categoryEntry = categoriesByKey[key]
        if not categoryEntry then
            categoryEntry = {
                key = key,
                name = quest.category.name,
                order = quest.category.order,
                quests = {},
            }
            categoriesByKey[key] = categoryEntry
            orderedKeys[#orderedKeys + 1] = key
        end
        categoryEntry.quests[#categoryEntry.quests + 1] = quest
    end

    table.sort(orderedKeys, function(left, right)
        local leftOrder = categoriesByKey[left].order
        local rightOrder = categoriesByKey[right].order
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

    if not GetNumJournalQuests then
        return quests
    end

    local total = GetNumJournalQuests() or 0
    local questCount = math.min(total, QUEST_LOG_LIMIT)
    for journalIndex = 1, questCount do
        local questEntry = BuildQuestEntry(journalIndex)
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

local function ForceRebuild(self)
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

local function OnQuestChanged(_, ...)
    local self = QuestModel
    if not self.isInitialized or not playerState.hasActivated then
        return
    end

    ScheduleRebuild(self)
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
    RegisterQuestEvent(EVENT_QUEST_REMOVED, eventHandler)
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
    EVENT_MANAGER:UnregisterForUpdate(REBUILD_IDENTIFIER)
    EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE .. "PlayerActivated", EVENT_PLAYER_ACTIVATED)
    bootstrapState.registered = false
    playerState.hasActivated = false

    QuestModel.isInitialized = false
    QuestModel.subscribers = nil
    QuestModel.currentSnapshot = nil
    QuestModel.pendingRebuild = nil
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
