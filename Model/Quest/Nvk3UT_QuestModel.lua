local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local function GetQuestListModule()
    return Nvk3UT and Nvk3UT.QuestList
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

local questJournalListUpdatedCallback = nil

local DEBUG_INIT = false

local function IsDebugLoggingEnabled()
    if DEBUG_INIT then
        return true
    end

    local utils = (Nvk3UT and Nvk3UT.Utils) or Nvk3UT_Utils
    if utils and type(utils.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(utils.IsDebugEnabled)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local diagnostics = (Nvk3UT and Nvk3UT.Diagnostics) or Nvk3UT_Diagnostics
    if diagnostics and type(diagnostics.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return diagnostics:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local root = Nvk3UT
    if root and type(root.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return root:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    return false
end

local function QM_Debug(fmt, ...)
    local diagnostics = (Nvk3UT and Nvk3UT.Diagnostics) or Nvk3UT_Diagnostics
    if diagnostics and type(diagnostics.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return diagnostics:IsDebugEnabled()
        end)
        if ok and enabled then
            local message = fmt
            if select("#", ...) > 0 then
                message = string.format(fmt, ...)
            end

            if type(diagnostics.Debug) == "function" then
                diagnostics:Debug(string.format("[QuestModel] %s", message))
                return
            end
        end
    end

    if not IsDebugLoggingEnabled() then
        return
    end

    local message = fmt
    if select("#", ...) > 0 then
        message = string.format(fmt, ...)
    end

    if d then
        d(string.format("[QuestModel] %s", message))
    elseif print then
        print("[QuestModel]", message)
    end
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

local function GetQuestIdForJournalIndex(journalIndex)
    if type(journalIndex) ~= "number" or journalIndex <= 0 then
        return nil
    end

    if type(GetJournalQuestId) ~= "function" then
        return nil
    end

    local ok, questId = pcall(GetJournalQuestId, journalIndex)
    if ok then
        return questId
    end

    return nil
end

local function BindQuestList(savedVars)
    local questList = GetQuestListModule()
    if questList and questList.Bind then
        pcall(function()
            questList:Bind(savedVars)
        end)
    end
end

local function EnsureSavedVars()
    if questSavedVars then
        return questSavedVars
    end

    if not ZO_SavedVars then
        questSavedVars = CopyTable(QUEST_SAVED_VARS_DEFAULTS)
        DebugInitLog("[Init] SavedVars ensured (fallback)")
        BindQuestList(questSavedVars)
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
    elseif next(sv.quests) ~= nil then
        -- Objectives/steps are no longer persisted; clear legacy data eagerly.
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

    BindQuestList(sv)

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

    sv.quests = {}
    MarkInitialized(sv)
    return 0
end

local function ShouldBootstrap(sv)
    if bootstrapState.executed then
        return false
    end

    if not sv then
        return false
    end

    if type(sv.meta) ~= "table" or sv.meta.initialized ~= true then
        return true
    end

    return false
end

local function BuildSnapshotFromSaved()
    local sv = EnsureSavedVars()
    if not sv then
        return nil
    end

    if type(sv.quests) == "table" and next(sv.quests) ~= nil then
        sv.quests = {}
    end

    return nil
end

local function BootstrapQuestData()
    if bootstrapState.executed then
        return 0
    end

    local questList = GetQuestListModule()
    local quests = {}
    if questList and questList.RefreshFromGame then
        quests = questList:RefreshFromGame()
    end

    local stored = PersistQuests(quests)
    bootstrapState.executed = true
    DebugInitLog("[Init] BootstrapQuestData → %d quests stored", stored)
    return stored
end

local ForceRebuildInternal

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

    if QuestModel.isInitialized and ForceRebuildInternal then
        ForceRebuildInternal(QuestModel)
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

local function ClampDebounce(value)
    if value < MIN_DEBOUNCE_MS then
        return MIN_DEBOUNCE_MS
    elseif value > MAX_DEBOUNCE_MS then
        return MAX_DEBOUNCE_MS
    end
    return value
end

local function LogDebug(self, ...)
    if not IsDebugLoggingEnabled() then
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
        return 0
    end

    local notified = 0
    for callback in pairs(self.subscribers) do
        notified = notified + 1
        local success, err = pcall(callback, self.currentSnapshot)
        if not success then
            LogDebug(self, "Subscriber callback failed", err)
        end
    end

    return notified
end

local function ResetBaseCategoryCache()
    -- TEMP SHIM (QMODEL_004): delegate cache resets to QuestList.
    local questList = GetQuestListModule()
    if questList and questList.ResetBaseCategoryCache then
        questList.ResetBaseCategoryCache()
    elseif questList and questList.ResetCaches then
        questList:ResetCaches()
    end
end

local function CollectQuestEntries(forceFullRebuild)
    if type(AcquireQuestData) ~= "function" then
        QM_Debug("CollectQuestEntries: AcquireQuestData is not a function (type=%s)", type(AcquireQuestData))
        return {}, {}
    end

    local questData, questListData, categoryListData, seenCategories = AcquireQuestData()

    local questList = GetQuestListModule()
    if questList and questList.RefreshFromGame then
        return questList:RefreshFromGame(forceFullRebuild, questData, categoryListData, questListData, seenCategories)
    end

    return {}, questData
end

local function BuildSnapshotFromQuests(quests)
    -- TEMP SHIM (QMODEL_004): reuse QuestList snapshot builder.
    local questList = GetQuestListModule()
    if questList and questList.BuildSnapshotFromQuests then
        return questList:BuildSnapshotFromQuests(quests)
    end

    quests = type(quests) == "table" and quests or {}
    return {
        updatedAtMs = nil,
        quests = quests,
        categories = {
            ordered = {},
            byKey = {},
        },
        signature = nil,
        questById = {},
        questByJournalIndex = {},
    }
end

local function BuildSnapshot(self, forceFullRebuild)
    local quests, questData = CollectQuestEntries(forceFullRebuild)
    if type(quests) ~= "table" then
        quests = {}
    end

    local snapshot = BuildSnapshotFromQuests(quests)
    if not snapshot or type(snapshot) ~= "table" then
        snapshot = BuildSnapshotFromQuests({})
    end

    if type(snapshot.categories) ~= "table" then
        snapshot.categories = { ordered = {}, byKey = {} }
    end
    if type(snapshot.categories.ordered) ~= "table" then
        snapshot.categories.ordered = {}
    end
    if type(snapshot.categories.byKey) ~= "table" then
        snapshot.categories.byKey = {}
    end
    if type(snapshot.quests) ~= "table" then
        snapshot.quests = {}
    end
    if type(snapshot.questById) ~= "table" then
        snapshot.questById = {}
    end
    if type(snapshot.questByJournalIndex) ~= "table" then
        snapshot.questByJournalIndex = {}
    end

    return snapshot, quests, questData
end

local function SnapshotsDiffer(previous, current, forceFullRebuild)
    if forceFullRebuild then
        return true
    end

    if not previous then
        return true
    end
    return previous.signature ~= current.signature
end

local function CountSnapshotQuests(snapshot)
    if not snapshot or type(snapshot.quests) ~= "table" then
        return 0
    end
    return #snapshot.quests
end

local function BuildQuestIdSet(snapshot)
    local ids = {}
    local mapping = {}

    if snapshot and type(snapshot.quests) == "table" then
        for _, quest in ipairs(snapshot.quests) do
            local questId = quest and quest.questId
            if questId ~= nil then
                mapping[questId] = true
                ids[#ids + 1] = questId
            end
        end
    end

    return ids, mapping
end

local function CollectConditionList(journalQuestIndex, stepIndex, totalConditions)
    local conditions = {}

    if type(totalConditions) == "number" and totalConditions > 0 and type(GetJournalQuestConditionInfo) == "function" then
        for conditionIndex = 1, totalConditions do
            local conditionText, current, maxValue, isFailCondition, isConditionComplete, _, isConditionVisible =
                GetJournalQuestConditionInfo(journalQuestIndex, stepIndex, conditionIndex)

            conditions[#conditions + 1] = {
                displayText = conditionText,
                text = conditionText,
                current = current,
                max = maxValue,
                complete = isConditionComplete == true,
                isVisible = isConditionVisible ~= false,
                isFailCondition = isFailCondition == true,
                index = conditionIndex,
            }
        end
    end

    return conditions
end

local function CollectQuestSteps(journalQuestIndex)
    if type(GetJournalQuestNumSteps) ~= "function" or type(GetJournalQuestStepInfo) ~= "function" then
        return {}
    end

    local steps = {}
    local numSteps = GetJournalQuestNumSteps(journalQuestIndex) or 0
    for stepIndex = 1, numSteps do
        local stepText, stepType, numConditions, isVisible, isCompleteStep, isOptional, isTracked =
            GetJournalQuestStepInfo(journalQuestIndex, stepIndex)

        local totalConditions = tonumber(numConditions) or 0
        if type(GetJournalQuestNumConditions) == "function" then
            local countedConditions = GetJournalQuestNumConditions(journalQuestIndex, stepIndex)
            if type(countedConditions) == "number" and countedConditions > totalConditions then
                totalConditions = countedConditions
            end
        end

        local conditions = CollectConditionList(journalQuestIndex, stepIndex, totalConditions)

        steps[#steps + 1] = {
            stepIndex = stepIndex,
            stepText = stepText,
            stepType = stepType,
            numConditions = numConditions,
            totalConditions = totalConditions,
            isVisible = isVisible ~= false,
            isComplete = isCompleteStep == true,
            isOptional = isOptional == true,
            isTracked = isTracked == true,
            conditions = conditions,
        }
    end

    return steps
end

local function CollectLocationInfo(journalQuestIndex)
    if type(GetJournalQuestLocationInfo) ~= "function" then
        return {}
    end

    local zoneName, subZoneName, zoneIndex, poiIndex = GetJournalQuestLocationInfo(journalQuestIndex)
    local data = {
        zoneName = zoneName,
        subZoneName = subZoneName,
        zoneIndex = zoneIndex,
        poiIndex = poiIndex,
        isShareable = nil,
    }

    if type(GetJournalQuestShareable) == "function" then
        local shareable = GetJournalQuestShareable(journalQuestIndex)
        data.isShareable = shareable == true
    end

    return data
end

local function AcquireQuestData()
    local questData = {}
    local questListData = nil
    local categoryListData = nil
    local seenCategories = nil

    if QUEST_JOURNAL_MANAGER and type(QUEST_JOURNAL_MANAGER.GetQuestListData) == "function" then
        local ok, questList, categoryList, seen = pcall(QUEST_JOURNAL_MANAGER.GetQuestListData, QUEST_JOURNAL_MANAGER)
        if ok then
            questListData = questList
            categoryListData = categoryList
            seenCategories = seen
        end
    end

    local questCount = type(GetNumJournalQuests) == "function" and GetNumJournalQuests() or 0
    for journalIndex = 1, questCount do
        local questName, backgroundText, activeStepText, activeStepType, questLevel, zoneName, questType, instanceDisplayType,
            isRepeatable, isDaily, questDescription, displayType = GetJournalQuestInfo(journalIndex)

        local questId = GetQuestIdForJournalIndex(journalIndex)
        local tracked = type(IsJournalQuestTracked) == "function" and IsJournalQuestTracked(journalIndex) or false
        local assisted = false
        if tracked and type(GetTrackedIsAssisted) == "function" then
            assisted = GetTrackedIsAssisted(TRACK_TYPE_QUEST, journalIndex) or false
        end

        local isComplete = false
        if type(GetJournalQuestIsComplete) == "function" then
            isComplete = GetJournalQuestIsComplete(journalIndex)
        elseif type(IsJournalQuestComplete) == "function" then
            isComplete = IsJournalQuestComplete(journalIndex)
        end

        questData[#questData + 1] = {
            journalIndex = journalIndex,
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
            isRepeatable = isRepeatable == true,
            isDaily = isDaily == true,
            description = questDescription,
            tracked = tracked == true,
            assisted = assisted == true,
            isComplete = isComplete == true,
            steps = CollectQuestSteps(journalIndex),
            location = CollectLocationInfo(journalIndex),
        }
    end

    QM_Debug("AcquireQuestData: questCount=%d, built=%d", questCount or 0, #questData)

    return questData, questListData, categoryListData, seenCategories
end

local function PerformRebuildFromGame(self, forceFullRebuild)
    if not self.isInitialized or not playerState.hasActivated then
        return false
    end

    local previousSnapshot = self.currentSnapshot
    local prevRevision = previousSnapshot and previousSnapshot.revision or 0
    local prevQuestCount = CountSnapshotQuests(previousSnapshot)
    local _, prevQuestIdSet = BuildQuestIdSet(previousSnapshot)

    QM_Debug("Rebuild start: force=%s, prevRevision=%d, prevQuestCount=%d", tostring(forceFullRebuild), prevRevision, prevQuestCount)

    local snapshot, quests, questData = BuildSnapshot(self, forceFullRebuild)
    if not snapshot then
        return false
    end

    local newQuestCount = CountSnapshotQuests(snapshot)
    QM_Debug(
        "PerformRebuildFromGame: force=%s prevQuests=%d newQuests=%d",
        tostring(forceFullRebuild),
        prevQuestCount or 0,
        newQuestCount or 0
    )

    local snapshotsDiffer = SnapshotsDiffer(self.currentSnapshot, snapshot, forceFullRebuild)
    if snapshotsDiffer then
        snapshot.revision = (self.currentSnapshot and self.currentSnapshot.revision or 0) + 1
        self.currentSnapshot = snapshot
    elseif not self.currentSnapshot then
        snapshot.revision = 1
        self.currentSnapshot = snapshot
    elseif self.currentSnapshot then
        snapshot.revision = self.currentSnapshot.revision or 0
        self.currentSnapshot = snapshot
    end

    local _, newQuestIdSet = BuildQuestIdSet(snapshot)
    local newRevision = (self.currentSnapshot and self.currentSnapshot.revision) or snapshot.revision or 0

    QM_Debug("Rebuild done: force=%s, newRevision=%d, newQuestCount=%d", tostring(forceFullRebuild), newRevision, newQuestCount)

    local removedIds = {}
    local addedIds = {}

    for questId in pairs(prevQuestIdSet) do
        if not newQuestIdSet[questId] then
            removedIds[#removedIds + 1] = tostring(questId)
        end
    end

    for questId in pairs(newQuestIdSet) do
        if not prevQuestIdSet[questId] then
            addedIds[#addedIds + 1] = tostring(questId)
        end
    end

    if #removedIds > 0 or #addedIds > 0 then
        QM_Debug("Rebuild diff: removedIds=%s, addedIds=%s", table.concat(removedIds, ","), table.concat(addedIds, ","))
    else
        QM_Debug("Rebuild diff: no questId changes")
    end

    if IsDebugLoggingEnabled() then
        local categoryCount = 0
        local questCount = snapshot.quests and #snapshot.quests or 0
        if snapshot.categories and snapshot.categories.ordered then
            categoryCount = #snapshot.categories.ordered
        end

        local journalCount = nil
        local questDataCount = type(questData) == "table" and #questData or 0
        if type(GetNumJournalQuests) == "function" then
            journalCount = GetNumJournalQuests()
        end

        LogDebug(
            self,
            string.format(
                "QuestModel rebuild: journalCount=%s, questDataCount=%d, snapshotCount=%d, categories=%d, revision=%d, signature=%s, force=%s",
                tostring(journalCount),
                questDataCount,
                questCount,
                categoryCount,
                snapshot.revision,
                tostring(snapshot.signature),
                tostring(forceFullRebuild)
            )
        )
    end

    PersistQuests(quests)
    local notifiedCount = NotifySubscribers(self)

    if IsDebugLoggingEnabled() then
        local afterCount = snapshot.quests and #snapshot.quests or 0
        local revision = (self.currentSnapshot and self.currentSnapshot.revision) or snapshot.revision or 0
        LogDebug(
            self,
            string.format(
                "QuestModel: PerformRebuild finished; snapshotRevision=%d, questCount=%d, notifiedSubscribers=%d",
                revision,
                afterCount,
                notifiedCount
            )
        )
    end
    return snapshotsDiffer or false
end

local function PerformRebuild(self)
    return PerformRebuildFromGame(self, false)
end

local function CancelScheduledRebuild(self)
    if not self.pendingRebuild then
        return
    end

    if EVENT_MANAGER then
        EVENT_MANAGER:UnregisterForUpdate(REBUILD_IDENTIFIER)
    end
    self.pendingRebuild = false
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

ForceRebuildInternal = function(self)
    if not self.isInitialized or not playerState.hasActivated then
        return false
    end

    if self.pendingRebuild then
        EVENT_MANAGER:UnregisterForUpdate(REBUILD_IDENTIFIER)
        self.pendingRebuild = false
    end

    local updated = PerformRebuildFromGame(self, false)
    return updated
end

QuestModel.ForceRebuild = ForceRebuildInternal
QuestModel.forceRebuild = ForceRebuildInternal

local function ForceFullRebuildFromGame(self)
    if not self.isInitialized or not playerState.hasActivated then
        return false
    end

    ResetBaseCategoryCache()

    CancelScheduledRebuild(self)

    return PerformRebuildFromGame(self, true)
end

QuestModel.ForceFullRebuildFromGame = function(self)
    return ForceFullRebuildFromGame(self or QuestModel)
end

local function OnQuestChanged(_, ...)
    local self = QuestModel
    if not self.isInitialized or not playerState.hasActivated then
        return
    end

    ResetBaseCategoryCache()
    ScheduleRebuild(self)
end

local function LogQuestEvent(eventName, journalIndex, questName, detail)
    local questId = GetQuestIdForJournalIndex(journalIndex)
    QM_Debug(
        "%s: journalIndex=%s, questId=%s, questName='%s'%s",
        eventName,
        tostring(journalIndex or -1),
        tostring(questId),
        questName or "?",
        detail or ""
    )
end

local function OnQuestAdded(eventCode, journalIndex, questName, objectiveName)
    LogQuestEvent("EVENT_QUEST_ADDED", journalIndex, questName, string.format(", objectiveName='%s'", objectiveName or "?"))
    OnQuestChanged(eventCode)
end

local function OnQuestAdvanced(eventCode, journalIndex, questName, isPushed, isComplete, mainStepChanged)
    LogQuestEvent(
        "EVENT_QUEST_ADVANCED",
        journalIndex,
        questName,
        string.format(", isPushed=%s, isComplete=%s, mainStepChanged=%s", tostring(isPushed), tostring(isComplete), tostring(mainStepChanged))
    )
    OnQuestChanged(eventCode)
end

local function OnQuestConditionChanged(
    eventCode,
    journalIndex,
    questName,
    conditionText,
    conditionType,
    curCount,
    newMax,
    isFailCondition,
    isComplete,
    isCreditShared
)
    LogQuestEvent(
        "EVENT_QUEST_CONDITION_COUNTER_CHANGED",
        journalIndex,
        questName,
        string.format(
            ", conditionText='%s', conditionType=%s, curCount=%s/%s, isFail=%s, isComplete=%s, shared=%s",
            tostring(conditionText or ""),
            tostring(conditionType),
            tostring(curCount),
            tostring(newMax),
            tostring(isFailCondition),
            tostring(isComplete),
            tostring(isCreditShared)
        )
    )
    OnQuestChanged(eventCode)
end

local function OnQuestLogUpdated(eventCode)
    local journalCount = nil
    if type(GetNumJournalQuests) == "function" then
        journalCount = GetNumJournalQuests()
    end
    QM_Debug("EVENT_QUEST_LOG_UPDATED: journalCount=%s", tostring(journalCount))
    OnQuestChanged(eventCode)
end

local function OnQuestJournalListUpdated()
    local self = QuestModel
    if not self.isInitialized or not playerState.hasActivated then
        return
    end

    local journalCount = nil
    if type(GetNumJournalQuests) == "function" then
        journalCount = GetNumJournalQuests()
    end

    local snapshotCountBefore = 0
    if self.currentSnapshot and type(self.currentSnapshot.quests) == "table" then
        snapshotCountBefore = #self.currentSnapshot.quests
    end

    QM_Debug(
        "QuestModel: QuestListUpdated → rebuilding from QUEST_JOURNAL_MANAGER; journalCount=%s, snapshotCountBefore=%d",
        tostring(journalCount),
        snapshotCountBefore
    )

    if IsDebugLoggingEnabled() then
        LogDebug(
            self,
            string.format(
                "QuestModel: QuestListUpdated → rebuilding from QUEST_JOURNAL_MANAGER; journalCount=%s, snapshotCountBefore=%d",
                tostring(journalCount),
                snapshotCountBefore
            )
        )
    end

    ForceFullRebuildFromGame(self)
end

local function OnQuestRemoved(_, isCompleted, journalIndex, questName)
    local self = QuestModel
    if not self.isInitialized or not playerState.hasActivated then
        return
    end

    LogQuestEvent(
        "EVENT_QUEST_REMOVED",
        journalIndex,
        questName,
        string.format(", isCompleted=%s", tostring(isCompleted))
    )

    ResetBaseCategoryCache()

    if IsDebugLoggingEnabled() then
        LogDebug(self, "Quest removed → awaiting QuestListUpdated for full rebuild")
    end
end

local function OnQuestCompleted(_, questName, level, previousExperience, championPoints, questType, instanceDisplayType)
    local self = QuestModel
    if not self.isInitialized or not playerState.hasActivated then
        return
    end

    QM_Debug(
        "EVENT_QUEST_COMPLETE: questName='%s', questType=%s, instanceDisplayType=%s, level=%s, xpBefore=%s, cp=%s",
        tostring(questName or ""),
        tostring(questType),
        tostring(instanceDisplayType),
        tostring(level),
        tostring(previousExperience),
        tostring(championPoints)
    )

    ResetBaseCategoryCache()

    if IsDebugLoggingEnabled() then
        LogDebug(self, "Quest completed → awaiting QuestListUpdated for full rebuild")
    end
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

    local requestedDebounce = tonumber(opts.debounceMs)
    if requestedDebounce then
        QuestModel.debounceMs = ClampDebounce(requestedDebounce)
    else
        QuestModel.debounceMs = DEFAULT_DEBOUNCE_MS
    end
    QuestModel.subscribers = {}
    QuestModel.isInitialized = true

    if QUEST_JOURNAL_MANAGER and type(QUEST_JOURNAL_MANAGER.RegisterCallback) == "function" and not QuestModel.questJournalListCallbackRegistered then
        questJournalListUpdatedCallback = questJournalListUpdatedCallback or function(...)
            OnQuestJournalListUpdated(...)
        end

        QUEST_JOURNAL_MANAGER:RegisterCallback("QuestListUpdated", questJournalListUpdatedCallback)
        QuestModel.questJournalListCallbackRegistered = true
    end

    local savedSnapshot = BuildSnapshotFromSaved()
    if savedSnapshot then
        savedSnapshot.revision = (QuestModel.currentSnapshot and QuestModel.currentSnapshot.revision) or 0
        QuestModel.currentSnapshot = savedSnapshot
    else
        QuestModel.currentSnapshot = nil
    end

    RegisterQuestEvent(EVENT_QUEST_ADDED, OnQuestAdded)
    RegisterQuestEvent(EVENT_QUEST_ADVANCED, OnQuestAdvanced)
    RegisterQuestEvent(EVENT_QUEST_CONDITION_COUNTER_CHANGED, OnQuestConditionChanged)
    RegisterQuestEvent(EVENT_QUEST_LOG_UPDATED, OnQuestLogUpdated)
    RegisterQuestEvent(EVENT_QUEST_REMOVED, OnQuestRemoved)
    RegisterQuestEvent(EVENT_QUEST_COMPLETE, OnQuestCompleted)
    EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE .. "TRACKING", EVENT_TRACKING_UPDATE, OnTrackingUpdate)

    if playerState.hasActivated then
        ForceRebuildInternal(QuestModel)
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
    UnregisterQuestEvent(EVENT_QUEST_COMPLETE)
    EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE .. "TRACKING", EVENT_TRACKING_UPDATE)
    EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE .. "OnLoaded", EVENT_ADD_ON_LOADED)
    EVENT_MANAGER:UnregisterForUpdate(REBUILD_IDENTIFIER)
    EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE .. "PlayerActivated", EVENT_PLAYER_ACTIVATED)

    if QuestModel.questJournalListCallbackRegistered and QUEST_JOURNAL_MANAGER and type(QUEST_JOURNAL_MANAGER.UnregisterCallback) == "function" and questJournalListUpdatedCallback then
        QUEST_JOURNAL_MANAGER:UnregisterCallback("QuestListUpdated", questJournalListUpdatedCallback)
        QuestModel.questJournalListCallbackRegistered = false
    end
    bootstrapState.registered = false
    playerState.hasActivated = false

    QuestModel.isInitialized = false
    QuestModel.subscribers = nil
    QuestModel.currentSnapshot = nil
    QuestModel.pendingRebuild = nil

    ResetBaseCategoryCache()
end

function QuestModel.GetSavedVars()
    return questSavedVars
end

function QuestModel.GetSnapshot()
    return QuestModel.currentSnapshot
end

function QuestModel.Subscribe(callback)
    assert(type(callback) == "function", "QuestModel.Subscribe expects a function")

    QuestModel.subscribers = QuestModel.subscribers or {}
    QuestModel.subscribers[callback] = true

    if QuestModel.isInitialized and playerState.hasActivated and not QuestModel.currentSnapshot then
        ForceRebuildInternal(QuestModel)
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
