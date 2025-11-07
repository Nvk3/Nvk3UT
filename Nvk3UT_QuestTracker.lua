local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local QuestTracker = {}
QuestTracker.__index = QuestTracker

local MODULE_NAME = addonName .. "QuestTracker"
local EVENT_NAMESPACE = MODULE_NAME .. "_Event"

local Utils = Nvk3UT and Nvk3UT.Utils
local QuestState = Nvk3UT and Nvk3UT.QuestState
local QuestSelection = Nvk3UT and Nvk3UT.QuestSelection
local QuestModel = Nvk3UT and Nvk3UT.QuestModel

local function EnsureQuestModel()
    if not QuestModel and Nvk3UT then
        QuestModel = Nvk3UT.QuestModel
    end

    return QuestModel
end

local function GetJournalIndex(questId)
    local numericQuestId = tonumber(questId)
    if not numericQuestId or numericQuestId <= 0 then
        return nil
    end

    numericQuestId = math.floor(numericQuestId)

    EnsureQuestModel()

    local model = QuestModel
    if not model then
        return nil
    end

    local resolver = model.GetJournalIndexForQuestId
    if type(resolver) ~= "function" then
        return nil
    end

    local ok, journalIndex = pcall(resolver, numericQuestId)
    if not ok then
        return nil
    end

    local numericIndex = tonumber(journalIndex)
    if not numericIndex or numericIndex <= 0 then
        return nil
    end

    return math.floor(numericIndex)
end
local FormatCategoryHeaderText =
    (Utils and Utils.FormatCategoryHeaderText)
    or function(baseText, count, showCounts)
        local text = baseText or ""
        if showCounts ~= false and type(count) == "number" and count >= 0 then
            local numericCount = math.floor(count + 0.5)
            return string.format("%s (%d)", text, numericCount)
        end
        return text
    end

local CATEGORY_TOGGLE_TEXTURES = {
    expanded = {
        up = "EsoUI/Art/Buttons/tree_open_up.dds",
        over = "EsoUI/Art/Buttons/tree_open_over.dds",
    },
    collapsed = {
        up = "EsoUI/Art/Buttons/tree_closed_up.dds",
        over = "EsoUI/Art/Buttons/tree_closed_over.dds",
    },
}

local QUEST_SELECTED_ICON_TEXTURE = "EsoUI/Art/Journal/journal_Quest_Selected.dds"

local CATEGORY_INDENT_X = 0
local QUEST_INDENT_X = 18
local QUEST_ICON_SLOT_WIDTH = 18
local QUEST_ICON_SLOT_HEIGHT = 18
local QUEST_ICON_SLOT_PADDING_X = 6
local QUEST_LABEL_INDENT_X = QUEST_INDENT_X + QUEST_ICON_SLOT_WIDTH + QUEST_ICON_SLOT_PADDING_X
-- keep objective indentation ahead of quest titles even with the persistent icon slot
local CONDITION_RELATIVE_INDENT = 18
local CONDITION_INDENT_X = QUEST_LABEL_INDENT_X + CONDITION_RELATIVE_INDENT
local VERTICAL_PADDING = 3

local CATEGORY_MIN_HEIGHT = 26
local QUEST_MIN_HEIGHT = 24
local CONDITION_MIN_HEIGHT = 20
local ROW_TEXT_PADDING_Y = 8
local TOGGLE_LABEL_PADDING_X = 4
local CATEGORY_TOGGLE_WIDTH = 20

local DEFAULT_FONTS = {
    category = "$(BOLD_FONT)|20|soft-shadow-thick",
    quest = "$(BOLD_FONT)|16|soft-shadow-thick",
    condition = "$(BOLD_FONT)|14|soft-shadow-thick",
    toggle = "$(BOLD_FONT)|20|soft-shadow-thick",
}

local DEFAULT_FONT_OUTLINE = "soft-shadow-thick"
local REFRESH_DEBOUNCE_MS = 80

local COLOR_ROW_HOVER = { 1, 1, 0.6, 1 }

local RequestRefresh -- forward declaration for functions that trigger refreshes
local SetCategoryExpanded -- forward declaration for expansion helpers used before assignment
local SetQuestExpanded
local IsQuestExpanded -- forward declaration so earlier functions can query quest expansion state
local HandleQuestRowClick -- forward declaration for quest row click orchestration
local FlushPendingTrackedQuestUpdate -- forward declaration for deferred tracking updates
local ProcessTrackedQuestUpdate -- forward declaration for deferred tracking processing
local RelayoutFromCategoryIndex -- forward declaration for targeted relayouts
local FindCategoryIndexByKey -- forward declaration for lookup helpers
local RefreshCategoryByKey -- forward declaration for targeted category refreshes
local RefreshQuestCategories -- forward declaration for quest-driven refreshes
local RefreshCategoriesForKeys -- forward declaration for bulk category refreshes
local UpdateRepoQuestFlags -- forward declaration for quest flag persistence helpers
local DoesJournalQuestExist -- forward declaration for journal lookups
local ApplyActiveQuestVisuals -- forward declaration for targeted active quest styling
local ApplyActiveQuestFromSaved -- forward declaration for active quest state sync
-- Forward declaration so SafeCall is visible to functions defined above its body.
-- Without this, calling SafeCall in ResolveQuestDebugInfo during quest accept can crash
-- because SafeCall would still be nil at that point.
local SafeCall

local state = {
    isInitialized = false,
    opts = {},
    fonts = {},
    saved = nil,
    control = nil,
    container = nil,
    categoryPool = nil,
    questPool = nil,
    conditionPool = nil,
    orderedControls = {},
    lastAnchoredControl = nil,
    snapshot = nil,
    categoryControls = {},
    questControls = {},
    pendingRefresh = false,
    contentWidth = 0,
    contentHeight = 0,
    trackedQuestIndex = nil,
    trackedCategoryKeys = {},
    trackingEventsRegistered = false,
    suppressForceExpandFor = nil,
    pendingSelection = nil,
    lastTrackedBeforeSync = nil,
    syncingTrackedState = false,
    pendingDeselection = false,
    pendingExternalReveal = nil,
    pendingTrackedUpdate = nil,
    isClickSelectInProgress = false,
    selectedQuestKey = nil,
    isRebuildInProgress = false,
    questModelSubscription = nil,
    repoPrimed = false,
    activeQuestId = nil,
    reposReady = false,
    reposReadyCallbackRef = nil,
    playerActivated = false,
    pendingActiveQuestApply = false,
}

local function UpdateReposReadyState()
    if state.reposReady then
        return true
    end

    if Nvk3UT and Nvk3UT.reposReady == true then
        state.reposReady = true
        if state.reposReadyCallbackRef and CALLBACK_MANAGER then
            CALLBACK_MANAGER:UnregisterCallback("Nvk3UT_REPOS_READY", state.reposReadyCallbackRef)
            state.reposReadyCallbackRef = nil
        end
        return true
    end

    return false
end

local function ClearReposReadySubscription()
    if state.reposReadyCallbackRef and CALLBACK_MANAGER then
        CALLBACK_MANAGER:UnregisterCallback("Nvk3UT_REPOS_READY", state.reposReadyCallbackRef)
    end

    state.reposReadyCallbackRef = nil
end

local function EnsureReposReadySubscription()
    if state.reposReady or state.reposReadyCallbackRef or not CALLBACK_MANAGER then
        return
    end

    state.reposReadyCallbackRef = function()
        state.reposReady = true
        ClearReposReadySubscription()

        if state.pendingActiveQuestApply or state.playerActivated then
            ApplyActiveQuestFromSaved()
        end
    end

    CALLBACK_MANAGER:RegisterCallback("Nvk3UT_REPOS_READY", state.reposReadyCallbackRef)
end

local PRIORITY = {
    manual = 5,
    ["click-select"] = 4,
    ["external-select"] = 4,
    auto = 2,
    init = 1,
}

NVK_DEBUG_DESELECT = NVK_DEBUG_DESELECT or false

local function IsDebugLoggingEnabled()
    local sv = Nvk3UT and Nvk3UT.sv
    return sv and sv.debug == true
end

local function DebugLog(...)
    local isEnabled = type(IsDebugLoggingEnabled) == "function" and IsDebugLoggingEnabled()
    if not isEnabled then
        return
    end

    if d then
        d(string.format("[%s]", MODULE_NAME), ...)
    elseif print then
        print("[" .. MODULE_NAME .. "]", ...)
    end
end

local function DebugDeselect(context, details)
    if not NVK_DEBUG_DESELECT then
        return
    end

    local parts = { string.format("[%s][DESELECT] %s", MODULE_NAME, tostring(context)) }

    if type(details) == "table" then
        for key, value in pairs(details) do
            parts[#parts + 1] = string.format("%s=%s", tostring(key), tostring(value))
        end
    elseif details ~= nil then
        parts[#parts + 1] = tostring(details)
    end

    local message = table.concat(parts, " | ")

    if d then
        d(message)
    elseif print then
        print(message)
    end
end

local function EscapeDebugString(value)
    return tostring(value):gsub('"', '\\"')
end

local function AppendDebugField(parts, key, value, treatAsString)
    if key == nil or key == "" then
        return
    end

    if value == nil then
        parts[#parts + 1] = string.format("%s=nil", key)
        return
    end

    local valueType = type(value)
    if valueType == "boolean" then
        parts[#parts + 1] = string.format("%s=%s", key, value and "true" or "false")
    elseif valueType == "number" then
        parts[#parts + 1] = string.format("%s=%s", key, tostring(value))
    elseif treatAsString or valueType == "string" then
        parts[#parts + 1] = string.format('%s="%s"', key, EscapeDebugString(value))
    else
        parts[#parts + 1] = string.format("%s=%s", key, tostring(value))
    end
end

local function EmitDebugAction(action, trigger, entityType, fieldList)
    if not (type(IsDebugLoggingEnabled) == "function" and IsDebugLoggingEnabled()) then
        return
    end

    local parts = { "[NVK]" }
    AppendDebugField(parts, "action", action or "unknown")
    AppendDebugField(parts, "trigger", trigger or "unknown")
    AppendDebugField(parts, "type", entityType or "unknown")

    if type(fieldList) == "table" then
        for index = 1, #fieldList do
            local entry = fieldList[index]
            if entry and entry.key then
                AppendDebugField(parts, entry.key, entry.value, entry.string)
            end
        end
    end

    local message = table.concat(parts, " ")
    if d then
        d(message)
    elseif print then
        print(message)
    end
end

local function GetQuestTrackerColor(role)
    local host = Nvk3UT and Nvk3UT.TrackerHost
    if host then
        if host.EnsureAppearanceDefaults then
            host.EnsureAppearanceDefaults()
        end
        if host.GetTrackerColor then
            return host.GetTrackerColor("questTracker", role)
        end
    end
    return 1, 1, 1, 1
end

local function ApplyBaseColor(control, r, g, b, a)
    if not control then
        return
    end

    local color = control.baseColor
    if type(color) ~= "table" then
        color = {}
        control.baseColor = color
    end

    color[1] = r or 1
    color[2] = g or 1
    color[3] = b or 1
    color[4] = a or 1

    if control.label and control.label.SetColor then
        control.label:SetColor(color[1], color[2], color[3], color[4])
    end
end

local function GetCurrentTimeSeconds()
    if QuestState and QuestState.GetCurrentTimeSeconds then
        return QuestState.GetCurrentTimeSeconds()
    end

    if GetFrameTimeSeconds then
        local ok, now = pcall(GetFrameTimeSeconds)
        if ok and type(now) == "number" then
            return now
        end
    end

    if GetGameTimeMilliseconds then
        local ok, ms = pcall(GetGameTimeMilliseconds)
        if ok and type(ms) == "number" then
            return ms / 1000
        end
    end

    if os and os.clock then
        return os.clock()
    end

    return 0
end

local function NormalizeCategoryKey(categoryKey)
    if QuestState and QuestState.NormalizeCategoryKey then
        return QuestState.NormalizeCategoryKey(categoryKey)
    end

    if categoryKey == nil then
        return nil
    end

    if type(categoryKey) == "string" then
        return categoryKey
    end

    if type(categoryKey) == "number" then
        return tostring(categoryKey)
    end

    return tostring(categoryKey)
end

local function NormalizeQuestKey(journalIndex)
    if QuestState and QuestState.NormalizeQuestKey then
        return QuestState.NormalizeQuestKey(journalIndex)
    end

    if journalIndex == nil then
        return nil
    end

    if type(journalIndex) == "string" then
        local numeric = tonumber(journalIndex)
        if numeric and numeric > 0 then
            return tostring(numeric)
        end
        return journalIndex
    end

    if type(journalIndex) == "number" then
        if journalIndex > 0 then
            return tostring(journalIndex)
        end
        return nil
    end

    return tostring(journalIndex)
end

local function DetermineQuestColorRole(quest)
    if not quest then
        return "entryTitle"
    end

    local normalizedQuestKey = NormalizeQuestKey(quest.journalIndex)
    local selected = false
    if normalizedQuestKey and state.selectedQuestKey then
        selected = normalizedQuestKey == state.selectedQuestKey
    end

    local tracked = false
    if state.trackedQuestIndex and quest.journalIndex then
        tracked = quest.journalIndex == state.trackedQuestIndex
    end

    local flags = quest.flags or {}
    local repoFlags
    if QuestState and QuestState.GetQuestFlags then
        repoFlags = QuestState.GetQuestFlags(normalizedQuestKey or quest.journalIndex)
    end

    local assisted = (repoFlags and repoFlags.assisted == true) or flags.assisted == true
    local watched = (repoFlags and repoFlags.tracked == true) or flags.tracked == true

    if assisted or selected or tracked then
        return "activeTitle"
    end

    -- Keep the legacy watcher branch in place even though it currently maps to the
    -- default entry color so future enhancements can differentiate it again without
    -- having to rediscover the selection logic.
    if watched then
        return "entryTitle"
    end

    return "entryTitle"
end

local function ResolveQuestIdFromKey(questKey)
    if questKey == nil then
        return nil
    end

    if type(questKey) == "table" then
        if questKey.questId ~= nil then
            return ResolveQuestIdFromKey(questKey.questId)
        elseif questKey.questKey ~= nil then
            return ResolveQuestIdFromKey(questKey.questKey)
        elseif questKey.journalIndex ~= nil then
            return ResolveQuestIdFromKey(questKey.journalIndex)
        end
    end

    if QuestState and QuestState.NormalizeQuestKey then
        local normalized = QuestState.NormalizeQuestKey(questKey)
        if normalized ~= nil then
            local numeric = tonumber(normalized)
            if numeric and numeric > 0 then
                return math.floor(numeric)
            end
        end
    end

    local numeric = tonumber(questKey)
    if numeric and numeric > 0 then
        return math.floor(numeric)
    end

    return nil
end

local function GetJournalIndexForQuestKey(questKey)
    if questKey == nil then
        return nil
    end

    local questId = ResolveQuestIdFromKey(questKey)

    local journalIndex = GetJournalIndex(questId)
    if journalIndex then
        return journalIndex
    end

    if type(questKey) == "table" and questKey.journalIndex ~= nil then
        local numericIndex = tonumber(questKey.journalIndex)
        if numericIndex and numericIndex > 0 then
            numericIndex = math.floor(numericIndex)
            if DoesJournalQuestExist and DoesJournalQuestExist(numericIndex) then
                return numericIndex
            end
        end
    end

    local numeric = tonumber(questKey)
    if numeric and numeric > 0 then
        numeric = math.floor(numeric)
        if not DoesJournalQuestExist or DoesJournalQuestExist(numeric) then
            return numeric
        end
    end

    return nil
end

local function GetQuestIdForJournalIndex(journalIndex)
    local numericIndex = tonumber(journalIndex)
    if not numericIndex or numericIndex <= 0 then
        return nil
    end

    numericIndex = math.floor(numericIndex)

    if type(GetJournalQuestId) ~= "function" then
        return nil
    end

    local ok, questId = pcall(GetJournalQuestId, numericIndex)
    if not ok then
        return nil
    end

    local numericQuestId = tonumber(questId)
    if not numericQuestId or numericQuestId <= 0 then
        return nil
    end

    return math.floor(numericQuestId)
end

local function ForEachQuest(callback)
    if type(callback) ~= "function" then
        return
    end

    if not state.snapshot or not state.snapshot.categories then
        return
    end

    local ordered = state.snapshot.categories.ordered
    if type(ordered) ~= "table" then
        return
    end

    for index = 1, #ordered do
        local category = ordered[index]
        if category and type(category.quests) == "table" then
            for questIndex = 1, #category.quests do
                local quest = category.quests[questIndex]
                if quest then
                    callback(quest, category)
                end
            end
        end
    end
end

local function ForEachQuestIndex(callback)
    if type(callback) ~= "function" then
        return
    end

    local visited = {}

    ForEachQuest(function(quest, category)
        if quest and quest.journalIndex then
            visited[quest.journalIndex] = true
            callback(quest.journalIndex, quest, category)
        end
    end)

    if not GetNumJournalQuests then
        return
    end

    local total = GetNumJournalQuests() or 0
    local maxIndex = MAX_JOURNAL_QUESTS or total
    if maxIndex and maxIndex > total then
        total = maxIndex
    end

    for index = 1, total do
        if not visited[index] then
            local isValid = true
            if IsValidJournalQuestIndex then
                isValid = IsValidJournalQuestIndex(index)
            elseif GetJournalQuestName then
                local name = GetJournalQuestName(index)
                isValid = name ~= nil and name ~= ""
            end

            if isValid then
                callback(index, nil, nil)
            end
        end
    end
end

local function SyncQuestFlagsFromSnapshot(snapshot)
    if not QuestState or not QuestState.UpdateQuestFlagsFromQuest then
        return
    end

    local current = snapshot or state.snapshot
    local categories = current and current.categories and current.categories.ordered
    if type(categories) ~= "table" then
        if QuestState.PruneQuestFlags then
            QuestState.PruneQuestFlags({})
        end
        return
    end

    local valid = {}

    for index = 1, #categories do
        local category = categories[index]
        if category and type(category.quests) == "table" then
            for questIndex = 1, #category.quests do
                local quest = category.quests[questIndex]
                if quest then
                    if QuestState.UpdateQuestFlagsFromQuest then
                        QuestState.UpdateQuestFlagsFromQuest(quest)
                    end

                    local questId
                    if QuestState.NormalizeQuestKey then
                        questId = QuestState.NormalizeQuestKey(quest.questId or quest.journalIndex)
                    end
                    if not questId then
                        questId = tonumber(quest.questId) or tonumber(quest.journalIndex)
                        if questId then
                            questId = math.floor(questId)
                        end
                    end
                    if questId then
                        valid[questId] = true
                    end
                end
            end
        end
    end

    if QuestState.PruneQuestFlags then
        QuestState.PruneQuestFlags(valid)
    end
end

local function CollectCategoryKeysForQuest(journalIndex)
    local keys = {}
    if not journalIndex then
        return keys, false
    end

    local found = false
    ForEachQuest(function(quest, category)
        if quest.journalIndex == journalIndex then
            found = true
            if category and category.key then
                local normalized = NormalizeCategoryKey(category.key)
                if normalized then
                    keys[normalized] = true
                end
            end
            if category and category.parent and category.parent.key then
                local normalizedParent = NormalizeCategoryKey(category.parent.key)
                if normalizedParent then
                    keys[normalizedParent] = true
                end
            end
        end
    end)

    return keys, found
end

local function FindCategoryIndexByKey(categoryKey)
    local normalized = NormalizeCategoryKey(categoryKey)
    if not normalized then
        return nil
    end

    local snapshot = state.snapshot
    local categories = snapshot and snapshot.categories and snapshot.categories.ordered
    if type(categories) ~= "table" then
        return nil
    end

    for index = 1, #categories do
        local category = categories[index]
        if category then
            local key = NormalizeCategoryKey(category.key)
            if key and key == normalized then
                return index
            end
        end
    end

    return nil
end

local function RefreshCategoriesForKeys(keys)
    if type(keys) ~= "table" or next(keys) == nil then
        return
    end

    local earliestIndex = nil

    for key in pairs(keys) do
        local index = FindCategoryIndexByKey(key)
        if not index then
            earliestIndex = false
            break
        end

        if not earliestIndex or index < earliestIndex then
            earliestIndex = index
        end
    end

    if earliestIndex == false then
        if RequestRefresh then
            RequestRefresh()
        end
        return
    end

    if earliestIndex then
        if RelayoutFromCategoryIndex then
            RelayoutFromCategoryIndex(earliestIndex)
        end
        return
    end

    if RequestRefresh then
        RequestRefresh()
    end
end

local function RefreshCategoryByKey(categoryKey)
    local index = FindCategoryIndexByKey(categoryKey)
    if index then
        if RelayoutFromCategoryIndex then
            RelayoutFromCategoryIndex(index)
        end
        return true
    end

    if RequestRefresh then
        RequestRefresh()
    end

    return false
end

local function RefreshQuestCategories(questKey)
    local journalIndex = GetJournalIndexForQuestKey(questKey)
    if not journalIndex then
        if RequestRefresh then
            RequestRefresh()
        end
        return
    end

    local keys = CollectCategoryKeysForQuest(journalIndex)
    if not keys or next(keys) == nil then
        if RequestRefresh then
            RequestRefresh()
        end
        return
    end

    RefreshCategoriesForKeys(keys)
end

local function UpdateRepoQuestFlags(questKey, mutator)
    if not (QuestState and QuestState.SetQuestFlags and QuestState.GetQuestFlags) then
        return
    end

    local normalized = questKey
    if QuestState.NormalizeQuestKey then
        normalized = QuestState.NormalizeQuestKey(questKey) or normalized
    end

    if not normalized then
        return
    end

    local flags = QuestState.GetQuestFlags and QuestState.GetQuestFlags(normalized) or {}
    if type(flags) ~= "table" then
        flags = {}
    end

    if type(mutator) == "function" then
        local ok, err = pcall(mutator, flags)
        if not ok then
            if IsDebugLoggingEnabled() then
                DebugLog(string.format("FLAG_MUTATOR_ERROR quest=%s err=%s", tostring(normalized), tostring(err)))
            end
        end
    end

    QuestState.SetQuestFlags(normalized, flags)
end

local function ResolveStateSource(context, fallback)
    if type(context) == "string" then
        return ResolveStateSource({ trigger = context }, fallback)
    end

    if type(context) == "table" then
        if context.stateSource then
            return context.stateSource
        end

        local trigger = context.trigger
        if trigger == "click" or trigger == "manual" then
            return "manual"
        elseif trigger == "click-select" then
            return "click-select"
        elseif trigger == "external-select" or trigger == "external" then
            return "external-select"
        elseif trigger == "init" then
            return "init"
        elseif trigger == "auto" or trigger == "refresh" or trigger == "unknown" then
            return "auto"
        end
    end

    return fallback or "auto"
end

local function LogStateWrite(entity, key, expanded, source, priority)
    local debugCheck = IsDebugLoggingEnabled
    if type(debugCheck) ~= "function" or not debugCheck() then
        return
    end

    local formatted
    if entity == "cat" then
        formatted = string.format(
            "STATE_WRITE cat=%s expanded=%s source=%s prio=%d",
            tostring(key),
            tostring(expanded),
            tostring(source),
            priority or 0
        )
    elseif entity == "quest" then
        formatted = string.format(
            "STATE_WRITE quest=%s expanded=%s source=%s prio=%d",
            tostring(key),
            tostring(expanded),
            tostring(source),
            priority or 0
        )
    elseif entity == "active" then
        formatted = string.format(
            "STATE_WRITE active=%s source=%s prio=%d",
            tostring(key),
            tostring(source),
            priority or 0
        )
    end

    if formatted then
        DebugLog(formatted)
    end
end

-- TEMP SHIM (QMODEL_002): TODO remove on SWITCH token; forwards to QuestSelection for active-state ensures.
local function EnsureActiveSavedState()
    if QuestSelection and QuestSelection.EnsureActiveSavedState then
        return QuestSelection.EnsureActiveSavedState()
    end

    if QuestState and QuestState.EnsureActiveSavedState then
        return QuestState.EnsureActiveSavedState()
    end

    if not state.saved then
        return nil
    end

    local active = state.saved.active
    if type(active) ~= "table" then
        active = {
            questKey = nil,
            source = "init",
            ts = 0,
        }
        state.saved.active = active
    end

    if active.questKey ~= nil then
        active.questKey = NormalizeQuestKey(active.questKey)
    end

    if type(active.source) ~= "string" or active.source == "" then
        active.source = "init"
    end

    active.ts = tonumber(active.ts) or 0

    return active
end

local function SyncSelectedQuestFromSaved()
    local questKey

    if QuestSelection and QuestSelection.GetActiveQuestKey then
        questKey = QuestSelection.GetActiveQuestKey()
    elseif QuestState and QuestState.GetSelectedQuestId then
        questKey = QuestState.GetSelectedQuestId()
    elseif state.saved then
        local active = EnsureActiveSavedState()
        questKey = active and active.questKey or nil
    end

    if questKey ~= nil then
        questKey = NormalizeQuestKey(questKey)
    end

    state.selectedQuestKey = questKey

    return questKey
end

local function PerformApplyActiveQuestFromSaved()
    local previousActiveQuestId = state.activeQuestId
    local questKey = SyncSelectedQuestFromSaved()
    local journalIndex = GetJournalIndexForQuestKey(questKey)

    state.trackedQuestIndex = journalIndex

    if not journalIndex then
        state.trackedCategoryKeys = {}

        if previousActiveQuestId ~= nil or state.activeQuestId ~= nil then
            if IsDebugLoggingEnabled() then
                DebugLog(string.format(
                    "ACTIVE_SYNC_SKIPPED questKey=%s", tostring(questKey)
                ))
            end

            state.activeQuestId = nil
            ApplyActiveQuestVisuals(previousActiveQuestId, nil)
        end

        return nil
    end

    state.trackedCategoryKeys = CollectCategoryKeysForQuest(journalIndex)

    local newActiveQuestId
    if journalIndex then
        newActiveQuestId = GetQuestIdForJournalIndex(journalIndex)
    end

    if not newActiveQuestId then
        newActiveQuestId = ResolveQuestIdFromKey(questKey)
    end

    if newActiveQuestId then
        local numericQuestId = tonumber(newActiveQuestId)
        if numericQuestId and numericQuestId > 0 then
            newActiveQuestId = math.floor(numericQuestId)
        else
            newActiveQuestId = nil
        end
    end

    if previousActiveQuestId ~= newActiveQuestId then
        state.activeQuestId = newActiveQuestId
        ApplyActiveQuestVisuals(previousActiveQuestId, newActiveQuestId)
    end

    return journalIndex
end

ApplyActiveQuestFromSaved = function()
    local reposReady = UpdateReposReadyState()
    if not reposReady then
        state.pendingActiveQuestApply = true
        EnsureReposReadySubscription()
        return nil
    end

    if not state.playerActivated then
        state.pendingActiveQuestApply = true
        return nil
    end

    state.pendingActiveQuestApply = false
    return PerformApplyActiveQuestFromSaved()
end

-- TEMP SHIM (QMODEL_001): TODO remove on SWITCH token; forwards category expansion state to Nvk3UT.QuestState.
local function WriteCategoryState(categoryKey, expanded, source, options)
    if not (QuestState and QuestState.SetCategoryExpanded) then
        return false, nil
    end

    local changed, normalizedKey, newExpanded, priority, resolvedSource =
        QuestState.SetCategoryExpanded(categoryKey, expanded, source, options)
    if not changed then
        return false, normalizedKey
    end

    LogStateWrite("cat", normalizedKey, newExpanded, resolvedSource or source or "auto", priority)
    return true, normalizedKey
end

-- TEMP SHIM (QMODEL_001): TODO remove on SWITCH token; forwards quest expansion state to Nvk3UT.QuestState.
local function WriteQuestState(questKey, expanded, source, options)
    if not (QuestState and QuestState.SetQuestExpanded) then
        return false, nil
    end

    local changed, normalizedKey, newExpanded, priority, resolvedSource =
        QuestState.SetQuestExpanded(questKey, expanded, source, options)
    if not changed then
        return false, normalizedKey
    end

    LogStateWrite("quest", normalizedKey, newExpanded, resolvedSource or source or "auto", priority)
    return true, normalizedKey
end

-- TEMP SHIM (QMODEL_002): TODO remove on SWITCH token; forwards active quest state to QuestSelection.
local function WriteActiveQuest(questKey, source, options)
    if QuestSelection and QuestSelection.SetActive then
        local changed, normalizedKey, priority, resolvedSource =
            QuestSelection.SetActive(questKey, source, options)
        if not changed then
            return false
        end

        LogStateWrite("active", normalizedKey, nil, resolvedSource or source or "auto", priority)
        ApplyActiveQuestFromSaved()
        return true
    end

    if QuestState and QuestState.SetSelectedQuestId then
        local changed, normalizedKey, priority, resolvedSource =
            QuestState.SetSelectedQuestId(questKey, source, options)
        if not changed then
            return false
        end

        LogStateWrite("active", normalizedKey, nil, resolvedSource or source or "auto", priority)
        ApplyActiveQuestFromSaved()
        return true
    end

    if not state.saved then
        return false
    end

    source = source or "auto"
    options = options or {}
    local normalized = questKey and NormalizeQuestKey(questKey) or nil
    local prev = EnsureActiveSavedState()
    local priorityOverride = options.priorityOverride
    local priority = priorityOverride or PRIORITY[source] or 0
    local prevPriority = prev and (PRIORITY[prev.source] or 0) or 0
    local overrideTimestamp = tonumber(options.timestamp)
    local now = overrideTimestamp or GetCurrentTimeSeconds()
    local prevTs = (prev and prev.ts) or 0
    local forceWrite = options.force == true
    local allowTimestampRegression = options.allowTimestampRegression == true

    if prev and not forceWrite then
        if prevPriority > priority then
            return false
        end

        if prevPriority == priority and not allowTimestampRegression and now < prevTs then
            return false
        end
    end

    state.saved.active = {
        questKey = normalized,
        source = source,
        ts = now,
    }

    LogStateWrite("active", normalized, nil, source, priority)

    ApplyActiveQuestFromSaved()

    return true
end

local function PrimeInitialSavedState()
    if state.repoPrimed then
        return
    end

    if not (state.snapshot and state.snapshot.categories) then
        return
    end

    local ordered = state.snapshot.categories.ordered
    if type(ordered) ~= "table" or #ordered == 0 then
        state.repoPrimed = true
        return
    end

    local timestamp = GetCurrentTimeSeconds()
    local categoryContext = {
        trigger = "init",
        source = "QuestTracker:PrimeInitialSavedState",
        forceWrite = true,
        allowTimestampRegression = true,
        deferRefresh = true,
        timestamp = timestamp,
    }
    local questContext = {
        trigger = "init",
        source = "QuestTracker:PrimeInitialSavedState",
        forceWrite = true,
        allowTimestampRegression = true,
        deferRefresh = true,
        timestamp = timestamp,
    }

    for index = 1, #ordered do
        local category = ordered[index]
        if category then
            local catKey = NormalizeCategoryKey(category.key)
            if catKey then
                SetCategoryExpanded(catKey, true, categoryContext)
            end

            if type(category.quests) == "table" then
                for questIndex = 1, #category.quests do
                    local quest = category.quests[questIndex]
                    if quest then
                        local questKey = NormalizeQuestKey(quest.journalIndex)
                        if questKey then
                            SetQuestExpanded(questKey, true, questContext)
                        end
                    end
                end
            end
        end
    end

    state.repoPrimed = true
end

local function ApplyLabelDefaults(label)
    if not label or not label.SetHorizontalAlignment then
        return
    end

    label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    if label.SetVerticalAlignment then
        label:SetVerticalAlignment(TEXT_ALIGN_TOP)
    end
    if label.SetWrapMode then
        label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    end
end

local function ApplyToggleDefaults(toggle)
    if not toggle or not toggle.SetVerticalAlignment then
        return
    end

    toggle:SetVerticalAlignment(TEXT_ALIGN_TOP)
end

local function GetToggleWidth(toggle, fallback)
    if toggle then
        if toggle.IsHidden and toggle:IsHidden() then
            return 0
        end

        if toggle.GetWidth then
            local width = toggle:GetWidth()
            if width and width > 0 then
                return width
            end
        end
    end

    return fallback or 0
end

local function GetContainerWidth()
    if not state.container or not state.container.GetWidth then
        return 0
    end

    local width = state.container:GetWidth()
    if not width or width <= 0 then
        return 0
    end

    return width
end

local function ApplyRowMetrics(control, indent, toggleWidth, leftPadding, rightPadding, minHeight)
    if not control or not control.label then
        return
    end

    indent = indent or 0
    toggleWidth = toggleWidth or 0
    leftPadding = leftPadding or 0
    rightPadding = rightPadding or 0

    local containerWidth = GetContainerWidth()
    local availableWidth = containerWidth - indent - toggleWidth - leftPadding - rightPadding
    if availableWidth < 0 then
        availableWidth = 0
    end

    control.label:SetWidth(availableWidth)

    local textHeight = control.label:GetTextHeight() or 0
    local targetHeight = textHeight + ROW_TEXT_PADDING_Y
    if minHeight then
        targetHeight = math.max(minHeight, targetHeight)
    end

    control:SetHeight(targetHeight)
end

local function RefreshControlMetrics(control)
    if not control or not control.label then
        return
    end

    local indent = control.currentIndent or 0
    local rowType = control.rowType

    if rowType == "category" then
        ApplyRowMetrics(
            control,
            indent,
            GetToggleWidth(control.toggle, CATEGORY_TOGGLE_WIDTH),
            TOGGLE_LABEL_PADDING_X,
            0,
            CATEGORY_MIN_HEIGHT
        )
    elseif rowType == "quest" then
        ApplyRowMetrics(
            control,
            indent,
            QUEST_ICON_SLOT_WIDTH,
            QUEST_ICON_SLOT_PADDING_X,
            0,
            QUEST_MIN_HEIGHT
        )
    elseif rowType == "condition" then
        ApplyRowMetrics(control, indent, 0, 0, 0, CONDITION_MIN_HEIGHT)
    end
end

local function ResolveQuestDebugInfo(journalIndex)
    local info = { id = journalIndex or "-" }

    if not journalIndex then
        return info
    end

    local questName
    local categoryKey
    local categoryName

    ForEachQuest(function(quest, category)
        if quest and quest.journalIndex == journalIndex then
            questName = quest.name or questName
            if category then
                categoryKey = category.key or categoryKey
                categoryName = category.name or categoryName
            end
        end
    end)

    if (not questName or questName == "") and GetJournalQuestName then
        local ok, name = SafeCall(GetJournalQuestName, journalIndex)
        if ok and type(name) == "string" and name ~= "" then
            questName = name
        end
    end

    info.name = questName
    info.categoryId = categoryKey
    info.categoryName = categoryName

    return info
end

local function ResolveCategoryDebugInfo(categoryKey)
    local info = { id = categoryKey or "-" }

    if not categoryKey then
        return info
    end

    if state.snapshot and state.snapshot.categories then
        local ordered = state.snapshot.categories.ordered
        if type(ordered) == "table" then
            for index = 1, #ordered do
                local category = ordered[index]
                if category then
                    if category.key == categoryKey then
                        info.name = category.name or info.name
                        return info
                    end
                    if category.parent and category.parent.key == categoryKey then
                        info.name = category.parent.name or info.name
                        return info
                    end
                end
            end
        end
    end

    ForEachQuest(function(_, category)
        if not category then
            return
        end
        if category.key == categoryKey then
            info.name = category.name or info.name
        elseif category.parent and category.parent.key == categoryKey then
            info.name = category.parent.name or info.name
        end
    end)

    return info
end

local function LogQuestSelectionChange(action, trigger, journalIndex, beforeSelectedId, afterSelectedId, source, extraFields)
    if not IsDebugLoggingEnabled() then
        return
    end

    local info = ResolveQuestDebugInfo(journalIndex)
    local fields = {
        { key = "id", value = info.id },
    }

    if info.name then
        fields[#fields + 1] = { key = "name", value = info.name, string = true }
    end
    if info.categoryId then
        fields[#fields + 1] = { key = "categoryId", value = info.categoryId }
    end
    if info.categoryName then
        fields[#fields + 1] = { key = "categoryName", value = info.categoryName, string = true }
    end

    fields[#fields + 1] = { key = "before.selectedId", value = beforeSelectedId }
    fields[#fields + 1] = { key = "after.selectedId", value = afterSelectedId }

    if type(extraFields) == "table" then
        for index = 1, #extraFields do
            fields[#fields + 1] = extraFields[index]
        end
    end

    if source then
        fields[#fields + 1] = { key = "source", value = source, string = true }
    end

    EmitDebugAction(action, trigger, "quest", fields)
end

local function LogQuestExpansion(action, trigger, journalIndex, beforeExpanded, afterExpanded, source, extraFields)
    if not IsDebugLoggingEnabled() then
        return
    end

    local info = ResolveQuestDebugInfo(journalIndex)
    local fields = {
        { key = "id", value = info.id },
    }

    if info.name then
        fields[#fields + 1] = { key = "name", value = info.name, string = true }
    end
    if info.categoryId then
        fields[#fields + 1] = { key = "categoryId", value = info.categoryId }
    end
    if info.categoryName then
        fields[#fields + 1] = { key = "categoryName", value = info.categoryName, string = true }
    end

    fields[#fields + 1] = { key = "before.expanded", value = beforeExpanded }
    fields[#fields + 1] = { key = "after.expanded", value = afterExpanded }

    if type(extraFields) == "table" then
        for index = 1, #extraFields do
            fields[#fields + 1] = extraFields[index]
        end
    end

    if source then
        fields[#fields + 1] = { key = "source", value = source, string = true }
    end

    EmitDebugAction(action, trigger, "quest", fields)
end

local function LogCategoryExpansion(action, trigger, categoryKey, beforeExpanded, afterExpanded, source, extraFields)
    if not IsDebugLoggingEnabled() then
        return
    end

    local info = ResolveCategoryDebugInfo(categoryKey)
    local fields = {
        { key = "id", value = info.id },
    }

    if info.name then
        fields[#fields + 1] = { key = "name", value = info.name, string = true }
    end

    fields[#fields + 1] = { key = "before.expanded", value = beforeExpanded }
    fields[#fields + 1] = { key = "after.expanded", value = afterExpanded }

    if type(extraFields) == "table" then
        for index = 1, #extraFields do
            fields[#fields + 1] = extraFields[index]
        end
    end

    if source then
        fields[#fields + 1] = { key = "source", value = source, string = true }
    end

    EmitDebugAction(action, trigger, "category", fields)
end

-- SafeCall implementation (assigned to the forward-declared upvalue above)
-- Hoisting this assignment prevents the quest-accept crash when ESO auto-assists a new quest.
SafeCall = function(func, ...)
    if type(func) ~= "function" then
        return false, nil
    end

    local ok, result = pcall(func, ...)
    if not ok then
        DebugLog("Call failed", tostring(result))
        return false, nil
    end

    return true, result
end

local function IsTruthy(value)
    return value ~= nil and value ~= false
end

local function NormalizeJournalIndex(journalIndex)
    local numeric = tonumber(journalIndex)
    if not numeric or numeric <= 0 then
        return nil
    end
    return numeric
end

local function QuestManagerCall(methodName, journalIndex)
    if not QUEST_JOURNAL_MANAGER or type(methodName) ~= "string" then
        return false, nil
    end

    local method = QUEST_JOURNAL_MANAGER[methodName]
    if type(method) ~= "function" then
        return false, nil
    end

    local ok, result = pcall(method, QUEST_JOURNAL_MANAGER, journalIndex)
    if not ok then
        DebugLog(string.format("QuestManager call failed (%s): %s", methodName, tostring(result)))
        return false, nil
    end

    return true, result
end

local function IsPlayerInGroup()
    if type(IsUnitGrouped) == "function" then
        local ok, grouped = SafeCall(IsUnitGrouped, "player")
        if ok then
            return grouped == true
        end
    end

    if type(GetGroupSize) == "function" then
        local ok, size = SafeCall(GetGroupSize)
        if ok then
            local numeric = tonumber(size) or 0
            return numeric > 1
        end
    end

    return false
end

local function CanQuestBeShared(journalIndex)
    local normalized = NormalizeJournalIndex(journalIndex)
    if not normalized then
        return false
    end

    if not IsPlayerInGroup() then
        return false
    end

    local managerOk, managerResult = QuestManagerCall("CanShareQuest", normalized)
    if managerOk and IsTruthy(managerResult) then
        return true
    end

    managerOk, managerResult = QuestManagerCall("CanShareQuestInJournal", normalized)
    if managerOk and IsTruthy(managerResult) then
        return true
    end

    if type(GetIsQuestSharable) == "function" then
        local ok, shareable = SafeCall(GetIsQuestSharable, normalized)
        if ok and IsTruthy(shareable) then
            return true
        end
    end

    return false
end

local function ShareQuestWithGroup(journalIndex)
    local normalized = NormalizeJournalIndex(journalIndex)
    if not normalized then
        return
    end

    local managerOk = QuestManagerCall("ShareQuest", normalized)
    if managerOk then
        return
    end

    if type(ShareQuest) == "function" then
        SafeCall(ShareQuest, normalized)
    end
end

local function CanQuestBeShownOnMap(journalIndex)
    local normalized = NormalizeJournalIndex(journalIndex)
    if not normalized then
        return false
    end

    -- Mirror the base quest journal gating so availability matches the vanilla UI.
    local managerOk, managerResult = QuestManagerCall("CanShowOnMap", normalized)
    if managerOk then
        return IsTruthy(managerResult)
    end

    if type(DoesJournalQuestHaveWorldMapLocation) == "function" then
        local ok, hasLocation = SafeCall(DoesJournalQuestHaveWorldMapLocation, normalized)
        if ok then
            return IsTruthy(hasLocation)
        end
    end

    return false
end

local function ShowQuestOnMap(journalIndex)
    local normalized = NormalizeJournalIndex(journalIndex)
    if not normalized then
        return
    end

    if type(ZO_WorldMap_ShowQuestOnMap) ~= "function" then
        return
    end

    -- Mirror the reference tracker by delegating straight to the base-game
    -- world map helper so the selected quest is highlighted using vanilla
    -- logic.
    SafeCall(ZO_WorldMap_ShowQuestOnMap, normalized)
end

local function CanQuestBeAbandoned(journalIndex)
    local normalized = NormalizeJournalIndex(journalIndex)
    if not normalized then
        return false
    end

    if type(IsJournalQuestAbandonable) == "function" then
        local ok, abandonable = SafeCall(IsJournalQuestAbandonable, normalized)
        if ok then
            return IsTruthy(abandonable)
        end
    end

    return true
end

local function ConfirmAbandonQuest(journalIndex)
    local normalized = NormalizeJournalIndex(journalIndex)
    if not normalized then
        return
    end

    local managerOk = QuestManagerCall("ConfirmAbandonQuest", normalized)
    if managerOk then
        return
    end

    if type(AbandonQuest) == "function" then
        SafeCall(AbandonQuest, normalized)
    end
end

local function BuildQuestContextMenuEntries(journalIndex)
    local entries = {}

    entries[#entries + 1] = {
        label = "Quest teilen",
        enabled = function()
            return CanQuestBeShared(journalIndex)
        end,
        callback = function()
            if CanQuestBeShared(journalIndex) then
                ShareQuestWithGroup(journalIndex)
            end
        end,
    }

    entries[#entries + 1] = {
        label = "Auf der Karte anzeigen",
        enabled = function()
            return CanQuestBeShownOnMap(journalIndex)
        end,
        callback = function()
            if CanQuestBeShownOnMap(journalIndex) then
                ShowQuestOnMap(journalIndex)
            end
        end,
    }

    entries[#entries + 1] = {
        label = "Quest aufgeben",
        enabled = function()
            return CanQuestBeAbandoned(journalIndex)
        end,
        callback = function()
            if CanQuestBeAbandoned(journalIndex) then
                ConfirmAbandonQuest(journalIndex)
            end
        end,
    }

    return entries
end

local function ShowQuestContextMenu(control, journalIndex)
    if not control then
        return
    end

    local entries = BuildQuestContextMenuEntries(journalIndex)
    if #entries == 0 then
        return
    end

    if Utils and Utils.ShowContextMenu and Utils.ShowContextMenu(control, entries) then
        return
    end

    if not (ClearMenu and AddCustomMenuItem and ShowMenu) then
        return
    end

    ClearMenu()

    local added = 0
    local function evaluateGate(gate)
        if gate == nil then
            return true
        end

        local gateType = type(gate)
        if gateType == "function" then
            local ok, result = pcall(gate, control)
            if not ok then
                return false
            end
            return result ~= false
        elseif gateType == "boolean" then
            return gate
        end

        return true
    end

    for index = 1, #entries do
        local entry = entries[index]
        if entry and type(entry.label) == "string" and type(entry.callback) == "function" then
            if evaluateGate(entry.visible) then
                local enabled = evaluateGate(entry.enabled)
                local itemType = (_G and _G.MENU_ADD_OPTION_LABEL) or 1
                local originalCallback = entry.callback
                local callback = originalCallback
                if type(originalCallback) == "function" then
                    callback = function(...)
                        if type(ClearMenu) == "function" then
                            pcall(ClearMenu)
                        end
                        originalCallback(...)
                    end
                end
                local beforeCount
                if type(ZO_Menu_GetNumMenuItems) == "function" then
                    local ok, count = pcall(ZO_Menu_GetNumMenuItems)
                    if ok and type(count) == "number" then
                        beforeCount = count
                    end
                end
                AddCustomMenuItem(entry.label, callback, itemType)
                local afterCount
                if type(ZO_Menu_GetNumMenuItems) == "function" then
                    local ok, count = pcall(ZO_Menu_GetNumMenuItems)
                    if ok and type(count) == "number" then
                        afterCount = count
                    end
                end
                local itemIndex = afterCount or ((type(beforeCount) == "number" and beforeCount + 1) or nil)
                if itemIndex and type(SetMenuItemEnabled) == "function" then
                    pcall(SetMenuItemEnabled, itemIndex, enabled ~= false)
                end
                added = added + 1
            end
        end
    end

    if added > 0 then
        ShowMenu(control)
    else
        ClearMenu()
    end
end

local function LogExternalSelect(questId)
    if not IsDebugLoggingEnabled() then
        return
    end

    DebugLog(string.format("EXTERNAL_SELECT questId=%s", tostring(questId)))
end

local function LogExpandCategory(categoryId, reason)
    if not IsDebugLoggingEnabled() then
        return
    end

    DebugLog(string.format(
        "EXPAND_CATEGORY categoryId=%s reason=%s",
        tostring(categoryId),
        reason or "external-select"
    ))
end

local function LogMissingCategory(questId)
    if not IsDebugLoggingEnabled() then
        return
    end

    DebugLog(string.format("WARN missing-category questId=%s", tostring(questId)))
end

local function LogScrollIntoView(questId)
    if not IsDebugLoggingEnabled() then
        return
    end

    DebugLog(string.format("SCROLL_INTO_VIEW questId=%s", tostring(questId)))
end

local function ExpandCategoriesForExternalSelect(journalIndex)
    if not journalIndex then
        return false, false
    end

    local keys, found = CollectCategoryKeysForQuest(journalIndex)
    local expandedAny = false
    local changedKeys = {}

    if keys then
        local context = {
            trigger = "external-select",
            source = "QuestTracker:ExpandCategoriesForExternalSelect",
            forceWrite = true,
            deferRefresh = true,
        }

        for key in pairs(keys) do
            if key and SetCategoryExpanded then
                local changed, normalizedKey = SetCategoryExpanded(key, true, context)
                if changed then
                    expandedAny = true
                    changedKeys[normalizedKey or key] = true
                    LogExpandCategory(normalizedKey or key, "external-select")
                end
            end
        end
    end

    if (not found) or not keys or next(keys) == nil then
        LogMissingCategory(journalIndex)
    end

    if expandedAny then
        RefreshCategoriesForKeys(changedKeys)
    end

    return expandedAny, found
end

local function ExpandCategoriesForClickSelect(journalIndex)
    if not journalIndex then
        return false, false
    end

    local keys, found = CollectCategoryKeysForQuest(journalIndex)
    local expandedAny = false
    local changedKeys = {}

    if keys then
        local context = {
            trigger = "click-select",
            source = "QuestTracker:ExpandCategoriesForClickSelect",
            deferRefresh = true,
        }

        for key in pairs(keys) do
            if key and SetCategoryExpanded then
                local changed, normalizedKey = SetCategoryExpanded(key, true, context)
                if changed then
                    expandedAny = true
                    changedKeys[normalizedKey or key] = true
                    LogExpandCategory(normalizedKey or key, "click-select")
                end
            end
        end
    end

    if (not found) or not keys or next(keys) == nil then
        LogMissingCategory(journalIndex)
    end

    if expandedAny then
        RefreshCategoriesForKeys(changedKeys)
    end

    return expandedAny, found
end

local function FindQuestControlByJournalIndex(journalIndex)
    if not journalIndex then
        return nil
    end

    if state.questControls then
        local numeric = tonumber(journalIndex) or journalIndex
        local control = state.questControls[numeric]
        if control then
            return control
        end
    end

    for index = 1, #state.orderedControls do
        local control = state.orderedControls[index]
        if control and control.rowType == "quest" then
            local questData = control.data and control.data.quest
            if questData and questData.journalIndex == journalIndex then
                return control
            end
        end
    end

    return nil
end

local function ApplyQuestControlVisualState(control)
    if not control then
        return false
    end

    local quest = control.data and control.data.quest
    if not quest then
        return false
    end

    local colorRole = DetermineQuestColorRole(quest)
    local r, g, b, a = GetQuestTrackerColor(colorRole)
    ApplyBaseColor(control, r, g, b, a)
    UpdateQuestIconSlot(control)

    return true
end

local function ResolveQuestControlForQuestId(questId)
    local numericQuestId = tonumber(questId)
    if not numericQuestId or numericQuestId <= 0 then
        return nil
    end

    numericQuestId = math.floor(numericQuestId)

    local journalIndex = GetJournalIndex(numericQuestId)

    if not journalIndex and state.questControls then
        for _, control in pairs(state.questControls) do
            local questData = control and control.data and control.data.quest
            if questData then
                local questDataId = tonumber(questData.questId)
                if questDataId and math.floor(questDataId) == numericQuestId then
                    journalIndex = questData.journalIndex
                    break
                end

                local fallbackId = tonumber(questData.journalIndex)
                if fallbackId and math.floor(fallbackId) == numericQuestId then
                    journalIndex = questData.journalIndex
                    break
                end
            end
        end
    end

    if not journalIndex then
        return nil
    end

    local control = FindQuestControlByJournalIndex(journalIndex)
    if not control then
        return nil
    end

    local questData = control.data and control.data.quest
    if not questData then
        return nil
    end

    return control
end

local function ApplyActiveQuestVisuals(oldQuestId, newQuestId)
    if oldQuestId == newQuestId then
        oldQuestId = nil
    end

    if IsDebugLoggingEnabled() then
        DebugLog(string.format(
            "ACTIVE_VISUAL %s -> %s",
            tostring(oldQuestId),
            tostring(newQuestId)
        ))
    end

    if not state.isInitialized then
        return false
    end

    local updated = false

    if oldQuestId then
        local control = ResolveQuestControlForQuestId(oldQuestId)
        if ApplyQuestControlVisualState(control) then
            updated = true
        end
    end

    if newQuestId then
        local control = ResolveQuestControlForQuestId(newQuestId)
        if ApplyQuestControlVisualState(control) then
            updated = true
        end
    end

    return updated
end

local function EnsureQuestRowVisible(journalIndex, options)
    options = options or {}
    local allowQueue = options.allowQueue ~= false

    local control = FindQuestControlByJournalIndex(journalIndex)
    if not control or (control.IsHidden and control:IsHidden()) then
        if allowQueue and journalIndex then
            state.pendingExternalReveal = { questId = journalIndex }
        end
        return false
    end

    local host = Nvk3UT and Nvk3UT.TrackerHost
    if not (host and host.ScrollControlIntoView) then
        if allowQueue and journalIndex then
            state.pendingExternalReveal = { questId = journalIndex }
        end
        return false
    end

    local ok, ensured = pcall(host.ScrollControlIntoView, control)
    if not ok or not ensured then
        if allowQueue and journalIndex then
            state.pendingExternalReveal = { questId = journalIndex }
        end
        return false
    end

    LogScrollIntoView(journalIndex)

    return true
end

local function ProcessPendingExternalReveal()
    local pending = state.pendingExternalReveal
    if not pending then
        return
    end

    state.pendingExternalReveal = nil
    EnsureQuestRowVisible(pending.questId, { allowQueue = false })
end

DoesJournalQuestExist = function(journalIndex)
    if not (journalIndex and GetJournalQuestName) then
        return false
    end

    local ok, name = SafeCall(GetJournalQuestName, journalIndex)
    if not ok then
        return false
    end

    if type(name) ~= "string" then
        return false
    end

    return name ~= ""
end

local function GetFocusedQuestIndex()
    if QUEST_JOURNAL_MANAGER and QUEST_JOURNAL_MANAGER.GetFocusedQuestIndex then
        local ok, focused = SafeCall(function(manager)
            return manager:GetFocusedQuestIndex()
        end, QUEST_JOURNAL_MANAGER)
        if ok then
            local numeric = tonumber(focused)
            if numeric and numeric > 0 then
                return numeric
            end
        end
    end

    return nil
end

local function UpdateTrackedQuestCache(forcedIndex, context)
    local function normalize(index)
        local resolved = GetJournalIndexForQuestKey(index)
        if resolved then
            return resolved
        end

        local numeric = tonumber(index)
        if numeric and numeric > 0 then
            numeric = math.floor(numeric)
            if not DoesJournalQuestExist or DoesJournalQuestExist(numeric) then
                return numeric
            end
        end

        return nil
    end

    local trackedIndex = normalize(forcedIndex)
    local allowFocusFallback = not state.pendingDeselection

    if not trackedIndex and GetTrackedQuestIndex then
        local ok, current = SafeCall(GetTrackedQuestIndex)
        if ok then
            trackedIndex = normalize(current)
        end
    end

    if not trackedIndex and allowFocusFallback then
        trackedIndex = normalize(GetFocusedQuestIndex())
    end

    if not trackedIndex and not state.pendingDeselection then
        local active = EnsureActiveSavedState()
        local savedActive = active and active.questKey
        trackedIndex = normalize(savedActive)
    end

    if not trackedIndex then
        ForEachQuest(function(quest)
            if trackedIndex then
                return
            end

            if not quest then
                return
            end

            local isTracked = quest.flags and quest.flags.tracked
            if QuestState and QuestState.GetQuestFlags then
                local flags = QuestState.GetQuestFlags(quest.questId or quest.journalIndex)
                if type(flags) == "table" then
                    isTracked = flags.tracked == true or isTracked
                end
            end

            if not isTracked then
                return
            end

            local fallbackIndex = normalize(quest.journalIndex) or tonumber(quest.journalIndex)
            if fallbackIndex and fallbackIndex > 0 then
                trackedIndex = fallbackIndex
            end
        end)
    end

    if trackedIndex then
        state.pendingDeselection = false
        local sourceTag = ResolveStateSource(context, "auto")
        local writeOptions
        if context and context.isExternal then
            writeOptions = { force = true }
        end
        WriteActiveQuest(trackedIndex, sourceTag, writeOptions)
    else
        ApplyActiveQuestFromSaved()
    end
end

local function EnsureQuestTrackedState(journalIndex)
    local numeric = tonumber(journalIndex)
    if not numeric or numeric <= 0 then
        return
    end

    if not (IsJournalQuestTracked and SetTracked) then
        return
    end

    if IsJournalQuestTracked(numeric) then
        return
    end

    if not SafeCall(SetTracked, TRACK_TYPE_QUEST, numeric, true) then
        SafeCall(SetTracked, TRACK_TYPE_QUEST, numeric)
    end

    UpdateRepoQuestFlags(numeric, function(flags)
        flags.tracked = true
        flags.journalIndex = numeric
    end)
end

local function ClearOtherTrackedQuests(journalIndex)
    if not IsJournalQuestTracked then
        return
    end

    ForEachQuestIndex(function(index)
        if index and index ~= journalIndex and IsJournalQuestTracked(index) then
            local cleared = false
            if SetTracked then
                cleared = SafeCall(SetTracked, TRACK_TYPE_QUEST, index, false)
                if not cleared then
                    cleared = SafeCall(SetTracked, TRACK_TYPE_QUEST, index)
                end
            end
            if not cleared and QUEST_JOURNAL_MANAGER and QUEST_JOURNAL_MANAGER.StopTrackingQuest then
                SafeCall(function(manager, questIndex)
                    manager:StopTrackingQuest(questIndex)
                end, QUEST_JOURNAL_MANAGER, index)
            end

            UpdateRepoQuestFlags(index, function(flags)
                flags.tracked = false
            end)
        end
    end)
end

local function EnsureExclusiveAssistedQuest(journalIndex)
    local numeric = tonumber(journalIndex)
    if not numeric or numeric <= 0 then
        return
    end

    if AssistJournalQuest then
        SafeCall(AssistJournalQuest, numeric)
        return
    end

    if not (type(SetTrackedIsAssisted) == "function" and TRACK_TYPE_QUEST) then
        return
    end

    ForEachQuestIndex(function(index)
        if not index then
            return
        end

        local isTarget = index == numeric
        local shouldAssist = isTarget and true or false

        if isTarget then
            SafeCall(SetTrackedIsAssisted, TRACK_TYPE_QUEST, index, shouldAssist)
        elseif type(GetTrackedIsAssisted) == "function" then
            local ok, assisted = SafeCall(GetTrackedIsAssisted, TRACK_TYPE_QUEST, index)
            if ok and assisted then
                SafeCall(SetTrackedIsAssisted, TRACK_TYPE_QUEST, index, false)
            end
        end

        UpdateRepoQuestFlags(index, function(flags)
            flags.assisted = shouldAssist
        end)
    end)
end

local function ApplyImmediateTrackedQuest(journalIndex, stateSource)
    if not journalIndex then
        return false
    end

    state.lastTrackedBeforeSync = state.trackedQuestIndex

    local sourceTag = stateSource or "auto"
    local changed = WriteActiveQuest(journalIndex, sourceTag)
    if not changed then
        ApplyActiveQuestFromSaved()
    end

    state.pendingDeselection = false

    return changed
end

local function AutoExpandQuestForTracking(journalIndex, forceExpand, context)
    if not journalIndex then
        return
    end

    if forceExpand == false then
        DebugDeselect("AutoExpandQuestForTracking:skipped", {
            journalIndex = journalIndex,
            forceExpand = tostring(forceExpand),
        })
        return
    end

    local questKey = NormalizeQuestKey(journalIndex)
    local previousExpanded = IsQuestExpanded(questKey)

    DebugDeselect("AutoExpandQuestForTracking", {
        journalIndex = journalIndex,
        forceExpand = tostring(forceExpand),
        previous = tostring(previousExpanded),
    })

    local logContext = {
        trigger = (context and context.trigger) or "auto",
        source = (context and context.source) or "QuestTracker:AutoExpandQuestForTracking",
    }

    if context then
        if context.stateSource ~= nil then
            logContext.stateSource = context.stateSource
        end
        if context.forceWrite then
            logContext.forceWrite = true
        end
    end

    SetQuestExpanded(journalIndex, true, logContext)
end

local function EnsureTrackedCategoriesExpanded(journalIndex, forceExpand, context)
    if not journalIndex then
        return
    end

    if forceExpand == false then
        DebugDeselect("EnsureTrackedCategoriesExpanded:skipped", {
            journalIndex = journalIndex,
            forceExpand = tostring(forceExpand),
        })
        return
    end

    local keys = CollectCategoryKeysForQuest(journalIndex)
    local logContext = {
        trigger = (context and context.trigger) or "auto",
        source = (context and context.source) or "QuestTracker:EnsureTrackedCategoriesExpanded",
        deferRefresh = true,
    }

    local debugEnabled = IsDebugLoggingEnabled()
    local changedKeys = {}

    for key in pairs(keys) do
        if key then
            local changed, normalizedKey = SetCategoryExpanded(key, true, logContext)
            if changed then
                changedKeys[normalizedKey or key] = true
            elseif debugEnabled then
                DebugLog(
                    "Category expand skipped",
                    "category",
                    normalizedKey or key,
                    "journalIndex",
                    journalIndex,
                    "trigger",
                    logContext.trigger
                )
            end
        end
    end

    if next(changedKeys) ~= nil then
        RefreshCategoriesForKeys(changedKeys)
    end
end

local function EnsureTrackedQuestVisible(journalIndex, forceExpand, context)
    if not journalIndex then
        return
    end

    DebugDeselect("EnsureTrackedQuestVisible", {
        journalIndex = journalIndex,
        forceExpand = tostring(forceExpand),
    })
    local logContext = {
        trigger = (context and context.trigger) or "auto",
        source = (context and context.source) or "QuestTracker:EnsureTrackedQuestVisible",
    }
    if context and context.stateSource ~= nil then
        logContext.stateSource = context.stateSource
    end
    local isExternal = context and context.isExternal
    local isNewTarget = context and context.isNewTarget
    if isExternal then
        LogExternalSelect(journalIndex)
        ExpandCategoriesForExternalSelect(journalIndex)
    else
        EnsureTrackedCategoriesExpanded(journalIndex, forceExpand, logContext)
    end
    if isExternal and isNewTarget then
        logContext.forceWrite = true
    end
    AutoExpandQuestForTracking(journalIndex, forceExpand, logContext)
    if isExternal then
        EnsureQuestRowVisible(journalIndex, { allowQueue = true })
    end
end

local function SyncTrackedQuestState(forcedIndex, forceExpand, context)
    if state.syncingTrackedState then
        DebugDeselect("SyncTrackedQuestState:reentry", {
            forcedIndex = forcedIndex,
            forceExpand = tostring(forceExpand),
        })
        return
    end

    context = context or {}
    state.syncingTrackedState = true

    repeat
        local previousTracked = state.lastTrackedBeforeSync
        if previousTracked == nil then
            previousTracked = state.trackedQuestIndex
        end

        UpdateTrackedQuestCache(forcedIndex, context)
        state.lastTrackedBeforeSync = nil

        local currentTracked = state.trackedQuestIndex
        local shouldForceExpand = forceExpand == true
        local pending = state.pendingSelection
        local pendingApplied = false
        local expansionChanged = false
        local skipVisibilityUpdate = false

        DebugDeselect("SyncTrackedQuestState:enter", {
            forcedIndex = forcedIndex,
            forceExpand = tostring(forceExpand),
            previousTracked = tostring(previousTracked),
            currentTracked = tostring(currentTracked),
            pendingIndex = pending and pending.index,
            pendingDeselection = tostring(state.pendingDeselection),
        })

        if previousTracked and (not currentTracked or currentTracked == previousTracked) and IsJournalQuestTracked then
            local ok, trackedState = SafeCall(IsJournalQuestTracked, previousTracked)
            if ok and not trackedState then
                DebugDeselect("SyncTrackedQuestState:deselect-detected", {
                    previousTracked = previousTracked,
                    currentTracked = tostring(currentTracked),
                    forcedIndex = forcedIndex,
                    pendingDeselection = tostring(state.pendingDeselection),
                })
                if currentTracked == previousTracked then
                    state.trackedQuestIndex = nil
                    state.trackedCategoryKeys = {}
                    currentTracked = nil
                end
                state.pendingDeselection = true
                shouldForceExpand = false
                skipVisibilityUpdate = true
            end
        end

        local trigger = context.trigger
        if not trigger and pending and pending.trigger then
            trigger = pending.trigger
        end
        if not trigger then
            if context.isExternal then
                trigger = "external"
            else
                trigger = "unknown"
            end
        end

        local source = context.source or (pending and pending.source) or "QuestTracker:SyncTrackedQuestState"
        local isExternalFlag = context.isExternal
        if isExternalFlag == nil and trigger == "external" then
            isExternalFlag = true
        end

        if pending and currentTracked == pending.index then
            local wasExpandedBefore = IsQuestExpanded(currentTracked)
            pendingApplied = true
            local pendingContext = {
                trigger = pending.trigger or trigger,
                source = pending.source or source,
            }
            expansionChanged = SetQuestExpanded(currentTracked, pending.expanded, pendingContext) or expansionChanged

            if pending.forceExpand ~= nil then
                shouldForceExpand = pending.forceExpand and true or false
            elseif pending.expanded then
                shouldForceExpand = true
            else
                shouldForceExpand = false
            end

            DebugDeselect("SyncTrackedQuestState:pending-applied", {
                index = currentTracked,
                expandedBefore = tostring(wasExpandedBefore),
                expandedAfter = tostring(IsQuestExpanded(currentTracked)),
                shouldForceExpand = tostring(shouldForceExpand),
            })
        end

        state.pendingSelection = nil

        if currentTracked and state.suppressForceExpandFor and state.suppressForceExpandFor == currentTracked then
            if not (pendingApplied and shouldForceExpand) then
                shouldForceExpand = false
            end
            state.suppressForceExpandFor = nil
        elseif not currentTracked or state.suppressForceExpandFor ~= currentTracked then
            state.suppressForceExpandFor = nil
        end

        if currentTracked then
            state.pendingDeselection = false
        end

        if currentTracked
            and isExternalFlag
            and previousTracked == currentTracked
            and not pendingApplied
            and (not pending or pending.index ~= currentTracked)
        then
            shouldForceExpand = false
            skipVisibilityUpdate = true
            DebugDeselect("SyncTrackedQuestState:external-refresh-skip-expand", {
                index = tostring(currentTracked),
                previousTracked = tostring(previousTracked),
                pendingApplied = tostring(pendingApplied),
                pendingIndex = pending and tostring(pending.index) or "nil",
            })
        end

        if currentTracked and not skipVisibilityUpdate and previousTracked and currentTracked == previousTracked and not pendingApplied and not forcedIndex then
            if IsJournalQuestTracked then
                local ok, trackedState = SafeCall(IsJournalQuestTracked, currentTracked)
                if ok and not trackedState then
                    skipVisibilityUpdate = true
                    shouldForceExpand = false
                    DebugDeselect("SyncTrackedQuestState:skip-visibility", {
                        index = currentTracked,
                        trackedState = tostring(trackedState),
                    })
                end
            end
        end

        local isNewTarget = currentTracked and currentTracked ~= previousTracked

        if currentTracked and not skipVisibilityUpdate then
            DebugDeselect("SyncTrackedQuestState:ensure-visible", {
                index = currentTracked,
                shouldForceExpand = tostring(shouldForceExpand),
            })
            local visibilityContext = {
                trigger = trigger,
                source = source,
                isExternal = isExternalFlag,
                isNewTarget = isNewTarget,
            }
            EnsureTrackedQuestVisible(currentTracked, shouldForceExpand, visibilityContext)
        else
            DebugDeselect("SyncTrackedQuestState:skip-ensure-visible", {
                index = tostring(currentTracked),
                skipVisibilityUpdate = tostring(skipVisibilityUpdate),
            })
        end

        if previousTracked ~= currentTracked then
            if previousTracked then
                local deselectFields
                if IsDebugLoggingEnabled() then
                    deselectFields = {
                        { key = "inDeselect", value = state.pendingDeselection },
                    }
                    if isExternalFlag ~= nil then
                        deselectFields[#deselectFields + 1] = { key = "isExternal", value = isExternalFlag }
                    end
                end
                LogQuestSelectionChange(
                    "deselect",
                    trigger,
                    previousTracked,
                    previousTracked,
                    currentTracked,
                    source,
                    deselectFields
                )
            end

            if currentTracked then
                local selectFields
                if IsDebugLoggingEnabled() and isExternalFlag ~= nil then
                    selectFields = {
                        { key = "isExternal", value = isExternalFlag },
                    }
                end
                LogQuestSelectionChange(
                    "select",
                    trigger,
                    currentTracked,
                    previousTracked,
                    currentTracked,
                    source,
                    selectFields
                )
            end
        end

        if not state.isInitialized then
            break
        end

        local hasTracked = currentTracked ~= nil
        local hadTracked = previousTracked ~= nil

        if RequestRefresh and (previousTracked ~= currentTracked or hasTracked or hadTracked or pendingApplied or expansionChanged) then
            RequestRefresh()
        end
    until true

    if state.pendingDeselection and not state.trackedQuestIndex then
        local clearSource = ResolveStateSource(context, "auto")
        WriteActiveQuest(nil, clearSource)
        state.pendingDeselection = false
    end

    state.syncingTrackedState = false
end

local function FocusQuestInJournal(journalIndex)
    local numeric = tonumber(journalIndex)
    if not numeric or numeric <= 0 then
        return
    end

    if not (QUEST_JOURNAL_KEYBOARD and QUEST_JOURNAL_KEYBOARD.FocusQuestWithIndex) then
        return
    end

    SafeCall(function(journal, index)
        journal:FocusQuestWithIndex(index)
    end, QUEST_JOURNAL_KEYBOARD, numeric)
end

local function ForceAssistTrackedQuest(journalIndex)
    local numeric = tonumber(journalIndex)
    if not numeric or numeric <= 0 then
        return
    end

    if not (FOCUSED_QUEST_TRACKER and FOCUSED_QUEST_TRACKER.ForceAssist) then
        return
    end

    SafeCall(function(tracker, index)
        tracker:ForceAssist(index)
    end, FOCUSED_QUEST_TRACKER, numeric)
end

local function RequestRefreshInternal()
    if not state.isInitialized then
        return
    end
    if state.pendingRefresh then
        return
    end

    state.pendingRefresh = true

    local function execute()
        state.pendingRefresh = false
        QuestTracker.Refresh()
    end

    if zo_callLater then
        zo_callLater(execute, REFRESH_DEBOUNCE_MS)
    else
        execute()
    end
end

RequestRefresh = RequestRefreshInternal

local function TrackQuestByJournalIndex(journalIndex, options)
    local numeric = tonumber(journalIndex)
    if not numeric or numeric <= 0 then
        return false
    end

    if state.opts.autoTrack == false then
        return false
    end

    options = options or {}

    local actionContext = {
        trigger = options.trigger or "auto",
        source = options.source or "QuestTracker:TrackQuestByJournalIndex",
    }

    if options.stateSource then
        actionContext.stateSource = options.stateSource
    end

    state.pendingDeselection = false

    DebugDeselect("TrackQuestByJournalIndex", {
        journalIndex = numeric,
        forceExpand = tostring(options.forceExpand),
        skipAutoExpand = tostring(options.skipAutoExpand),
        pendingSelection = state.pendingSelection and state.pendingSelection.index,
    })

    if options.skipAutoExpand then
        state.suppressForceExpandFor = numeric
    else
        if options.forceExpand == false then
            state.suppressForceExpandFor = numeric
        else
            state.suppressForceExpandFor = nil
        end
        AutoExpandQuestForTracking(numeric, options.forceExpand, actionContext)
        EnsureTrackedCategoriesExpanded(numeric, options.forceExpand, actionContext)
    end

    if options.applyImmediate ~= false then
        ApplyImmediateTrackedQuest(numeric, ResolveStateSource(actionContext, "auto"))
    end

    if SetTrackedQuestIndex then
        SafeCall(SetTrackedQuestIndex, numeric)
    elseif QUEST_JOURNAL_MANAGER and QUEST_JOURNAL_MANAGER.SetTrackedQuestIndex then
        SafeCall(function(manager, index)
            manager:SetTrackedQuestIndex(index)
        end, QUEST_JOURNAL_MANAGER, numeric)
    end

    FocusQuestInJournal(numeric)
    ForceAssistTrackedQuest(numeric)
    EnsureQuestTrackedState(numeric)
    ClearOtherTrackedQuests(numeric)
    EnsureExclusiveAssistedQuest(numeric)

    UpdateRepoQuestFlags(numeric, function(flags)
        flags.tracked = true
        flags.journalIndex = numeric

        local categoryKey
        local keys = CollectCategoryKeysForQuest(numeric)
        if type(keys) == "table" then
            for key in pairs(keys) do
                categoryKey = key
                break
            end
        end

        flags.categoryKey = categoryKey
    end)

    local shouldRequestRefresh = options.requestRefresh
    if shouldRequestRefresh == nil then
        shouldRequestRefresh = true
    end

    if shouldRequestRefresh then
        RequestRefresh()
    end

    return true
end

HandleQuestRowClick = function(journalIndex)
    local questId = tonumber(journalIndex)
    if not questId or questId <= 0 then
        return
    end

    if state.isClickSelectInProgress then
        if IsDebugLoggingEnabled() then
            DebugLog(string.format("CLICK_SELECT_SKIPPED questId=%s reason=in-progress", tostring(questId)))
        end
        return
    end

    state.isClickSelectInProgress = true

    if IsDebugLoggingEnabled() then
        DebugLog(string.format("CLICK_SELECT_START questId=%s", tostring(questId)))
    end

    state.pendingSelection = nil

    local previousQuest = state.trackedQuestIndex
    local previousQuestString = previousQuest and tostring(previousQuest) or "nil"

    ApplyImmediateTrackedQuest(questId, "click-select")

    if IsDebugLoggingEnabled() then
        DebugLog(string.format("SET_ACTIVE questId=%s prev=%s", tostring(questId), previousQuestString))
    end

    RequestRefresh()

    if IsDebugLoggingEnabled() then
        DebugLog(string.format("UI_SELECT questId=%s", tostring(questId)))
    end

    local nextExpanded = not IsQuestExpanded(questId)
    state.pendingSelection = {
        index = questId,
        expanded = nextExpanded,
        forceExpand = nextExpanded,
        trigger = "click",
        source = "QuestTracker:HandleQuestRowClick",
    }

    SetQuestExpanded(questId, nextExpanded, {
        trigger = "click-select",
        source = "QuestTracker:HandleQuestRowClick",
    })

    ExpandCategoriesForClickSelect(questId)

    EnsureQuestRowVisible(questId, { allowQueue = false })

    state.isClickSelectInProgress = false

    FlushPendingTrackedQuestUpdate()

    local trackOptions = {
        forceExpand = nextExpanded,
        trigger = "click",
        source = "QuestTracker:OnRowClick",
        skipAutoExpand = true,
        applyImmediate = false,
        requestRefresh = false,
        stateSource = "click-select",
    }

    local tracked = TrackQuestByJournalIndex(questId, trackOptions)

    if tracked then
        ProcessTrackedQuestUpdate(TRACK_TYPE_QUEST, {
            trigger = "click",
            source = "QuestTracker:HandleQuestRowClick",
            forcedIndex = questId,
            forceExpand = nextExpanded,
            isExternal = false,
            stateSource = "click-select",
        })
    else
        state.pendingSelection = nil
    end

    RequestRefresh()

    if IsDebugLoggingEnabled() then
        DebugLog(string.format("CLICK_SELECT_END questId=%s", tostring(questId)))
    end
end

local function AdoptTrackedQuestOnInit()
    local journalIndex = state.trackedQuestIndex

    if not journalIndex or journalIndex <= 0 then
        journalIndex = GetFocusedQuestIndex()
    end

    if (not journalIndex or journalIndex <= 0) and GetTrackedQuestIndex then
        local ok, current = SafeCall(GetTrackedQuestIndex)
        if ok then
            local numeric = tonumber(current)
            if numeric and numeric > 0 then
                journalIndex = numeric
            end
        end
    end

    if not journalIndex or journalIndex <= 0 then
        return
    end

    if not state.trackedQuestIndex then
        ApplyImmediateTrackedQuest(journalIndex, "init")
    end

    EnsureTrackedQuestVisible(journalIndex, true, {
        trigger = "init",
        source = "QuestTracker:AdoptTrackedQuestOnInit",
    })

    if state.opts.autoTrack == false then
        return
    end

    local currentTracked = nil
    if GetTrackedQuestIndex then
        local ok, current = SafeCall(GetTrackedQuestIndex)
        if ok then
            currentTracked = tonumber(current)
        end
    end

    if currentTracked ~= journalIndex then
        TrackQuestByJournalIndex(journalIndex, {
            forceExpand = true,
            trigger = "init",
            source = "QuestTracker:AdoptTrackedQuestOnInit",
        })
        return
    end

    ForceAssistTrackedQuest(journalIndex)
    EnsureQuestTrackedState(journalIndex)
    ClearOtherTrackedQuests(journalIndex)
    EnsureExclusiveAssistedQuest(journalIndex)
end

ProcessTrackedQuestUpdate = function(trackingType, context)
    if trackingType and trackingType ~= TRACK_TYPE_QUEST then
        return
    end

    local resolvedContext = context or {}

    if not resolvedContext.trigger then
        if state.pendingSelection and state.pendingSelection.trigger then
            resolvedContext.trigger = state.pendingSelection.trigger
        elseif resolvedContext.isExternal == false then
            resolvedContext.trigger = "unknown"
        else
            resolvedContext.trigger = "external"
        end
    end

    if resolvedContext.isExternal == nil then
        resolvedContext.isExternal = resolvedContext.trigger ~= "click"
    end

    if not resolvedContext.source then
        resolvedContext.source = "QuestTracker:OnTrackedQuestUpdate"
    end

    local forcedIndex = resolvedContext.forcedIndex

    SyncTrackedQuestState(forcedIndex, true, resolvedContext)
end

local function OnTrackedQuestUpdate(_, trackingType, context)
    if state.isClickSelectInProgress then
        state.pendingTrackedUpdate = {
            trackingType = trackingType,
            context = context,
        }
        return
    end

    ProcessTrackedQuestUpdate(trackingType, context)
end

FlushPendingTrackedQuestUpdate = function()
    local pending = state.pendingTrackedUpdate
    if not pending then
        return
    end

    state.pendingTrackedUpdate = nil
    ProcessTrackedQuestUpdate(pending.trackingType, pending.context)
end

local function OnFocusedTrackerAssistChanged(_, assistedData)
    local questIndex = assistedData and assistedData.arg1
    if questIndex ~= nil then
        local numeric = tonumber(questIndex)
        if numeric and numeric > 0 then
            SyncTrackedQuestState(numeric, true, {
                trigger = "external",
                source = "QuestTracker:OnFocusedTrackerAssistChanged",
                isExternal = true,
            })
            return
        end
    end

    SyncTrackedQuestState(nil, true, {
        trigger = "external",
        source = "QuestTracker:OnFocusedTrackerAssistChanged",
        isExternal = true,
    })
end

local function OnPlayerActivated()
    state.playerActivated = true
    UpdateReposReadyState()

    local function execute()
        SyncTrackedQuestState(nil, true, {
            trigger = "init",
            source = "QuestTracker:OnPlayerActivated",
            isExternal = true,
        })

        ApplyActiveQuestFromSaved()
    end

    if zo_callLater then
        zo_callLater(execute, 20)
    else
        execute()
    end
end

local function RegisterTrackingEvents()
    if state.trackingEventsRegistered then
        return
    end

    if EVENT_MANAGER then
        EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE .. "TrackUpdate", EVENT_TRACKING_UPDATE, OnTrackedQuestUpdate)
        EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE .. "PlayerActivated", EVENT_PLAYER_ACTIVATED, OnPlayerActivated)
    end

    if FOCUSED_QUEST_TRACKER and FOCUSED_QUEST_TRACKER.RegisterCallback then
        FOCUSED_QUEST_TRACKER:RegisterCallback("QuestTrackerAssistStateChanged", OnFocusedTrackerAssistChanged)
    end

    state.trackingEventsRegistered = true
end

local function UnregisterTrackingEvents()
    if not state.trackingEventsRegistered then
        return
    end

    if EVENT_MANAGER then
        EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE .. "TrackUpdate", EVENT_TRACKING_UPDATE)
        EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE .. "PlayerActivated", EVENT_PLAYER_ACTIVATED)
    end

    if FOCUSED_QUEST_TRACKER and FOCUSED_QUEST_TRACKER.UnregisterCallback then
        FOCUSED_QUEST_TRACKER:UnregisterCallback("QuestTrackerAssistStateChanged", OnFocusedTrackerAssistChanged)
    end

    state.trackingEventsRegistered = false
end

local function NotifyHostContentChanged()
    local host = Nvk3UT and Nvk3UT.TrackerHost
    if not (host and host.NotifyContentChanged) then
        return
    end

    pcall(host.NotifyContentChanged)
end

local function NotifyStatusRefresh()
    local ui = Nvk3UT and Nvk3UT.UI
    if ui and ui.UpdateStatus then
        ui.UpdateStatus()
    end
end

local function EnsureSavedVars()
    Nvk3UT.sv = Nvk3UT.sv or {}

    if QuestState and QuestState.Bind then
        local characterSaved = QuestState.Bind(Nvk3UT.sv)
        state.characterSaved = characterSaved
        if QuestSelection and QuestSelection.Bind then
            QuestSelection.Bind(Nvk3UT.sv, characterSaved)
        end
    end

    local accountSV = Nvk3UT.sv
    local questSettings = accountSV.QuestTracker or {}
    accountSV.QuestTracker = questSettings
    state.saved = questSettings

    if not QuestState or not QuestState.Bind then
        EnsureActiveSavedState()
        if QuestSelection and QuestSelection.Bind then
            QuestSelection.Bind(Nvk3UT.sv, questSettings)
        end
    end

    ApplyActiveQuestFromSaved()
end

local function ApplyFont(label, font, fallback)
    if not label or not label.SetFont then
        return
    end
    local resolved = font
    if resolved == nil or resolved == "" then
        resolved = fallback
    end
    if resolved == nil or resolved == "" then
        return
    end
    label:SetFont(resolved)
end

local function ResolveFont(fontId)
    if not fontId or fontId == "" then
        return nil
    end

    if type(fontId) == "string" then
        return fontId
    end

    return nil
end

local function MergeFonts(opts)
    local fonts = {}
    fonts.category = ResolveFont(opts.category) or DEFAULT_FONTS.category
    fonts.quest = ResolveFont(opts.quest) or DEFAULT_FONTS.quest
    fonts.condition = ResolveFont(opts.condition) or DEFAULT_FONTS.condition
    fonts.toggle = ResolveFont(opts.toggle) or DEFAULT_FONTS.toggle
    return fonts
end

local function BuildFontString(descriptor, fallback)
    if type(descriptor) ~= "table" then
        return ResolveFont(descriptor) or fallback
    end

    local face = descriptor.face or descriptor.path
    local size = descriptor.size
    local outline = descriptor.outline or DEFAULT_FONT_OUTLINE

    if not face or face == "" or not size then
        return fallback
    end

    return string.format("%s|%d|%s", face, size, outline or DEFAULT_FONT_OUTLINE)
end

local function ResetLayoutState()
    state.orderedControls = {}
    state.lastAnchoredControl = nil
    state.categoryControls = {}
    state.questControls = {}
end

local function ReleaseAll(pool)
    if pool then
        pool:ReleaseAllObjects()
    end
end

local function AnchorControl(control, indentX)
    indentX = indentX or 0
    control:ClearAnchors()

    if state.lastAnchoredControl then
        local previousIndent = state.lastAnchoredControl.currentIndent or 0
        local offsetX = indentX - previousIndent
        control:SetAnchor(TOPLEFT, state.lastAnchoredControl, BOTTOMLEFT, offsetX, VERTICAL_PADDING)
        control:SetAnchor(TOPRIGHT, state.lastAnchoredControl, BOTTOMRIGHT, 0, VERTICAL_PADDING)
    else
        control:SetAnchor(TOPLEFT, state.container, TOPLEFT, indentX, 0)
        control:SetAnchor(TOPRIGHT, state.container, TOPRIGHT, 0, 0)
    end

    state.lastAnchoredControl = control
    state.orderedControls[#state.orderedControls + 1] = control
    control.currentIndent = indentX
end

local function UpdateContentSize()
    local maxWidth = 0
    local totalHeight = 0
    local visibleCount = 0

    for index = 1, #state.orderedControls do
        local control = state.orderedControls[index]
        if control then
            RefreshControlMetrics(control)
        end
        if control and not control:IsHidden() then
            visibleCount = visibleCount + 1
            local width = (control:GetWidth() or 0) + (control.currentIndent or 0)
            if width > maxWidth then
                maxWidth = width
            end
            totalHeight = totalHeight + (control:GetHeight() or 0)
            if visibleCount > 1 then
                totalHeight = totalHeight + VERTICAL_PADDING
            end
        end
    end

    state.contentWidth = maxWidth
    state.contentHeight = totalHeight
end

local function SelectCategoryToggleTexture(expanded, isMouseOver)
    local textures = expanded and CATEGORY_TOGGLE_TEXTURES.expanded or CATEGORY_TOGGLE_TEXTURES.collapsed
    if isMouseOver then
        return textures.over
    end
    return textures.up
end

local function UpdateCategoryToggle(control, expanded)
    if not (control and control.toggle and control.toggle.SetTexture) then
        return
    end

    local isMouseOver = false
    if control.IsMouseOver and control:IsMouseOver() then
        isMouseOver = true
    elseif control.toggle and control.toggle.IsMouseOver and control.toggle:IsMouseOver() then
        isMouseOver = true
    end

    local texture = SelectCategoryToggleTexture(expanded, isMouseOver)
    control.toggle:SetTexture(texture)
    control.isExpanded = expanded and true or false
end

local function UpdateQuestIconSlot(control)
    if not (control and control.iconSlot) then
        return
    end

    local questData = control.data and control.data.quest
    local isSelected = false
    if questData then
        local questKey = NormalizeQuestKey(questData.journalIndex)
        if questKey and state.selectedQuestKey then
            isSelected = questKey == state.selectedQuestKey
        elseif state.trackedQuestIndex then
            isSelected = questData.journalIndex == state.trackedQuestIndex
        end
    end

    if isSelected then
        if control.iconSlot.SetTexture then
            control.iconSlot:SetTexture(QUEST_SELECTED_ICON_TEXTURE)
        end
        if control.iconSlot.SetAlpha then
            control.iconSlot:SetAlpha(1)
        end
        if control.iconSlot.SetHidden then
            control.iconSlot:SetHidden(false)
        end
    else
        if control.iconSlot.SetTexture then
            control.iconSlot:SetTexture(nil)
        end
        if control.iconSlot.SetAlpha then
            control.iconSlot:SetAlpha(0)
        end
        if control.iconSlot.SetHidden then
            control.iconSlot:SetHidden(false)
        end
    end
end

local function GetDefaultCategoryExpanded()
    if QuestState and QuestState.GetCategoryDefaultExpanded then
        local savedDefault = QuestState.GetCategoryDefaultExpanded()
        if savedDefault ~= nil then
            return savedDefault and true or false
        end
    end

    return state.opts.autoExpand ~= false
end

local function GetDefaultQuestExpanded()
    if QuestState and QuestState.GetQuestDefaultExpanded then
        local savedDefault = QuestState.GetQuestDefaultExpanded()
        if savedDefault ~= nil then
            return savedDefault and true or false
        end
    end

    return state.opts.autoExpand ~= false
end

local function IsCategoryExpanded(categoryKey)
    local key = NormalizeCategoryKey(categoryKey)
    if not key then
        return GetDefaultCategoryExpanded()
    end

    if QuestState and QuestState.IsCategoryExpanded then
        local stored = QuestState.IsCategoryExpanded(key)
        if stored ~= nil then
            return stored and true or false
        end
    end

    return GetDefaultCategoryExpanded()
end

IsQuestExpanded = function(journalIndex)
    local key = NormalizeQuestKey(journalIndex)
    if not key then
        return GetDefaultQuestExpanded()
    end

    if QuestState and QuestState.IsQuestExpanded then
        local stored = QuestState.IsQuestExpanded(key)
        if stored ~= nil then
            return stored and true or false
        end
    end

    return GetDefaultQuestExpanded()
end

SetCategoryExpanded = function(categoryKey, expanded, context)
    local key = NormalizeCategoryKey(categoryKey)
    if not key then
        return false, nil
    end

    local beforeExpanded = IsCategoryExpanded(key)
    local stateSource = ResolveStateSource(context, expanded and "auto" or "auto")
    local writeOptions
    if context and context.forceWrite and expanded and not beforeExpanded then
        writeOptions = { force = true }
    end

    if context and (context.trigger == "click" or context.trigger == "click-select") then
        writeOptions = writeOptions or {}
        writeOptions.force = true
        writeOptions.allowTimestampRegression = true
    end

    if context and context.timestamp then
        writeOptions = writeOptions or {}
        writeOptions.timestamp = context.timestamp
    end

    local changed, normalizedKey = WriteCategoryState(key, expanded, stateSource, writeOptions)
    if not changed then
        return false, normalizedKey
    end

    DebugDeselect("SetCategoryExpanded", {
        categoryKey = normalizedKey or key,
        previous = tostring(beforeExpanded),
        newValue = tostring(expanded),
    })

    local manualCollapseRespected
    if context and context.manualCollapseRespected ~= nil then
        manualCollapseRespected = context.manualCollapseRespected and true or false
    elseif context and context.trigger == "click" then
        manualCollapseRespected = true
    end

    local extraFields
    if IsDebugLoggingEnabled() then
        if manualCollapseRespected ~= nil then
            extraFields = extraFields or {}
            extraFields[#extraFields + 1] = {
                key = "manualCollapseRespected",
                value = manualCollapseRespected,
            }
        end
    end

    LogCategoryExpansion(
        expanded and "expand" or "collapse",
        (context and context.trigger) or "unknown",
        key,
        beforeExpanded,
        expanded,
        (context and context.source) or "QuestTracker:SetCategoryExpanded",
        extraFields
    )

    if not (context and context.deferRefresh) then
        RefreshCategoryByKey(normalizedKey or key)
    end

    return true, normalizedKey or key
end

SetQuestExpanded = function(journalIndex, expanded, context)
    local key = NormalizeQuestKey(journalIndex)
    if not key then
        return false, nil
    end

    local beforeExpanded = IsQuestExpanded(key)
    local stateSource = ResolveStateSource(context, expanded and "auto" or "auto")
    local writeOptions
    if context and context.forceWrite and expanded and not beforeExpanded then
        writeOptions = { force = true }
    end

    if context and (context.trigger == "click" or context.trigger == "click-select") then
        writeOptions = writeOptions or {}
        writeOptions.force = true
        writeOptions.allowTimestampRegression = true
    end

    if context and context.timestamp then
        writeOptions = writeOptions or {}
        writeOptions.timestamp = context.timestamp
    end

    local changed, normalizedKey = WriteQuestState(key, expanded, stateSource, writeOptions)
    if not changed then
        return false, normalizedKey
    end

    DebugDeselect("SetQuestExpanded", {
        journalIndex = normalizedKey or key,
        previous = tostring(beforeExpanded),
        newValue = tostring(expanded),
    })

    local numericIndex = GetJournalIndexForQuestKey(normalizedKey or key)

    LogQuestExpansion(
        expanded and "expand" or "collapse",
        (context and context.trigger) or "unknown",
        numericIndex,
        beforeExpanded,
        expanded,
        (context and context.source) or "QuestTracker:SetQuestExpanded"
    )

    if not (context and context.deferRefresh) then
        RefreshQuestCategories(normalizedKey or key)
    end

    return true, normalizedKey or key
end

local function ToggleQuestExpansion(journalIndex, context)
    if not journalIndex then
        return false
    end

    local expanded = IsQuestExpanded(journalIndex)
    local toggleContext = context or {}
    if toggleContext.trigger == nil then
        toggleContext = {
            trigger = "unknown",
            source = toggleContext.source,
        }
    elseif toggleContext.source == nil then
        toggleContext = {
            trigger = toggleContext.trigger,
            source = nil,
        }
    end
    if not toggleContext.source then
        toggleContext.source = "QuestTracker:ToggleQuestExpansion"
    end

    local changed = SetQuestExpanded(journalIndex, not expanded, toggleContext)

    return changed
end

local function FormatConditionText(condition)
    if not condition then
        return ""
    end

    local text = condition.displayText or condition.text
    if type(text) ~= "string" or text == "" then
        return ""
    end

    if condition.isTurnIn then
        text = string.format("* %s", text)
    end

    if zo_strformat then
        return zo_strformat("<<1>>", text)
    end

    return text
end

local function AcquireCategoryControl()
    local control, key = state.categoryPool:AcquireObject()
    if not control.initialized then
        control.label = control:GetNamedChild("Label")
        control.toggle = control:GetNamedChild("Toggle")
        if control.toggle and control.toggle.SetTexture then
            control.toggle:SetTexture(SelectCategoryToggleTexture(false, false))
        end
        control.isExpanded = false
        control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
            if not upInside or button ~= MOUSE_BUTTON_INDEX_LEFT then
                return
            end
            local catKey = ctrl.data and ctrl.data.categoryKey
            if not catKey then
                return
            end
            local expanded = not IsCategoryExpanded(catKey)
            SetCategoryExpanded(catKey, expanded, {
                trigger = "click",
                source = "QuestTracker:OnCategoryClick",
            })
        end)
        control:SetHandler("OnMouseEnter", function(ctrl)
            if ctrl.label then
                ctrl.label:SetColor(unpack(COLOR_ROW_HOVER))
            end
            local expanded = ctrl.isExpanded
            if expanded == nil then
                local catKey = ctrl.data and ctrl.data.categoryKey
                expanded = IsCategoryExpanded(catKey)
            end
            UpdateCategoryToggle(ctrl, expanded)
        end)
        control:SetHandler("OnMouseExit", function(ctrl)
            if ctrl.label and ctrl.baseColor then
                ctrl.label:SetColor(unpack(ctrl.baseColor))
            end
            local expanded = ctrl.isExpanded
            if expanded == nil then
                local catKey = ctrl.data and ctrl.data.categoryKey
                expanded = IsCategoryExpanded(catKey)
            end
            UpdateCategoryToggle(ctrl, expanded)
        end)
        control.initialized = true
    end
    control.rowType = "category"
    control.poolKey = key
    ApplyLabelDefaults(control.label)
    ApplyToggleDefaults(control.toggle)
    ApplyFont(control.label, state.fonts.category, DEFAULT_FONTS.category)
    ApplyFont(control.toggle, state.fonts.toggle, DEFAULT_FONTS.toggle)
    return control, key
end

local function AcquireQuestControl()
    local control, key = state.questPool:AcquireObject()
    if not control.initialized then
        control.label = control:GetNamedChild("Label")
        control.iconSlot = control:GetNamedChild("IconSlot")
        if control.iconSlot then
            control.iconSlot:SetDimensions(QUEST_ICON_SLOT_WIDTH, QUEST_ICON_SLOT_HEIGHT)
            control.iconSlot:ClearAnchors()
            control.iconSlot:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
            if control.iconSlot.SetTexture then
                control.iconSlot:SetTexture(nil)
            end
            if control.iconSlot.SetAlpha then
                control.iconSlot:SetAlpha(0)
            end
            if control.iconSlot.SetHidden then
                control.iconSlot:SetHidden(false)
            end
            if control.iconSlot.SetMouseEnabled then
                control.iconSlot:SetMouseEnabled(true)
            end
            control.iconSlot:SetHandler("OnMouseUp", function(toggleCtrl, button, upInside)
                if not upInside or button ~= MOUSE_BUTTON_INDEX_LEFT then
                    return
                end
                local parent = toggleCtrl:GetParent()
                local questData = parent and parent.data and parent.data.quest
                if not questData then
                    return
                end
                local journalIndex = questData.journalIndex
                ToggleQuestExpansion(journalIndex, {
                    trigger = "click",
                    source = "QuestTracker:OnToggleClick",
                })
            end)
        end
        if control.label then
            control.label:ClearAnchors()
            if control.iconSlot then
                control.label:SetAnchor(TOPLEFT, control.iconSlot, TOPRIGHT, QUEST_ICON_SLOT_PADDING_X, 0)
            else
                control.label:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
            end
            control.label:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
        end
        control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
            if not upInside then
                return
            end
            if button == MOUSE_BUTTON_INDEX_LEFT then
                local questData = ctrl.data and ctrl.data.quest
                if not questData then
                    return
                end
                local journalIndex = questData.journalIndex
                local toggleMouseOver = false
                if ctrl.iconSlot then
                    local toggleIsMouseOver = ctrl.iconSlot.IsMouseOver
                    if type(toggleIsMouseOver) == "function" then
                        toggleMouseOver = toggleIsMouseOver(ctrl.iconSlot)
                    end
                end

                if toggleMouseOver then
                    ToggleQuestExpansion(journalIndex, {
                        trigger = "click",
                        source = "QuestTracker:OnRowClickToggle",
                    })
                    return
                end

                if state.opts.autoTrack == false then
                    ToggleQuestExpansion(journalIndex, {
                        trigger = "click",
                        source = "QuestTracker:OnRowClickManualToggle",
                    })
                    return
                end

                HandleQuestRowClick(journalIndex)
            elseif button == MOUSE_BUTTON_INDEX_RIGHT then
                local questData = ctrl.data and ctrl.data.quest
                if not questData then
                    return
                end
                ShowQuestContextMenu(ctrl, questData.journalIndex)
            end
        end)
        control:SetHandler("OnMouseEnter", function(ctrl)
            if ctrl.label then
                ctrl.label:SetColor(unpack(COLOR_ROW_HOVER))
            end
        end)
        control:SetHandler("OnMouseExit", function(ctrl)
            if ctrl.label and ctrl.baseColor then
                ctrl.label:SetColor(unpack(ctrl.baseColor))
            end
        end)
        control.initialized = true
    end
    control.rowType = "quest"
    control.poolKey = key
    ApplyLabelDefaults(control.label)
    ApplyFont(control.label, state.fonts.quest, DEFAULT_FONTS.quest)
    return control, key
end

local function AcquireConditionControl()
    local control, key = state.conditionPool:AcquireObject()
    if not control.initialized then
        control.label = control:GetNamedChild("Label")
        control.initialized = true
    end
    control.rowType = "condition"
    control.poolKey = key
    ApplyLabelDefaults(control.label)
    ApplyFont(control.label, state.fonts.condition, DEFAULT_FONTS.condition)
    return control, key
end

local function ShouldDisplayCondition(condition)
    if not condition then
        return false
    end

    if condition.forceDisplay then
        local text = condition.displayText or condition.text
        return type(text) == "string" and text ~= ""
    end

    if condition.isVisible == false then
        return false
    end

    if condition.isComplete then
        return false
    end

    if condition.isFailCondition then
        return false
    end

    local text = condition.displayText or condition.text
    if not text or text == "" then
        return false
    end

    return true
end

local function AttachBackdrop()
    EnsureBackdrop()
end

local function EnsurePools()
    if state.categoryPool then
        return
    end

    state.categoryPool = ZO_ControlPool:New("CategoryHeader_Template", state.container)
    state.questPool = ZO_ControlPool:New("QuestHeader_Template", state.container)
    state.conditionPool = ZO_ControlPool:New("QuestCondition_Template", state.container)

    local function resetControl(control)
        control:SetHidden(true)
        control.data = nil
        control.currentIndent = nil
        control.baseColor = nil
        control.isExpanded = nil
    end

    state.categoryPool:SetCustomResetBehavior(function(control)
        resetControl(control)
        if control.toggle then
            if control.toggle.SetTexture then
                control.toggle:SetTexture(SelectCategoryToggleTexture(false, false))
            end
            if control.toggle.SetHidden then
                control.toggle:SetHidden(false)
            end
        end
    end)
    state.questPool:SetCustomResetBehavior(function(control)
        resetControl(control)
        if control.label and control.label.SetText then
            control.label:SetText("")
        end
        if control.iconSlot then
            if control.iconSlot.SetTexture then
                control.iconSlot:SetTexture(nil)
            end
            if control.iconSlot.SetAlpha then
                control.iconSlot:SetAlpha(0)
            end
            if control.iconSlot.SetHidden then
                control.iconSlot:SetHidden(false)
            end
        end
    end)
    state.conditionPool:SetCustomResetBehavior(resetControl)
end

local function LayoutCondition(condition)
    if not ShouldDisplayCondition(condition) then
        return
    end

    local control = AcquireConditionControl()
    control.data = { condition = condition }
    control.label:SetText(FormatConditionText(condition))
    if control.label then
        local r, g, b, a = GetQuestTrackerColor("objectiveText")
        control.label:SetColor(r, g, b, a)
    end
    ApplyRowMetrics(control, CONDITION_INDENT_X, 0, 0, 0, CONDITION_MIN_HEIGHT)
    control:SetHidden(false)
    AnchorControl(control, CONDITION_INDENT_X)
end

local function LayoutQuest(quest)
    local control = AcquireQuestControl()
    control.data = { quest = quest }
    control.label:SetText(quest.name or "")

    local colorRole = DetermineQuestColorRole(quest)
    local r, g, b, a = GetQuestTrackerColor(colorRole)
    ApplyBaseColor(control, r, g, b, a)

    local questKey = NormalizeQuestKey(quest.journalIndex)
    local expanded = IsQuestExpanded(quest.journalIndex)
    if IsDebugLoggingEnabled() then
        DebugLog(string.format(
            "BUILD_APPLY quest=%s expanded=%s",
            tostring(questKey or quest.journalIndex),
            tostring(expanded)
        ))
    end
    UpdateQuestIconSlot(control)
    ApplyRowMetrics(
        control,
        QUEST_INDENT_X,
        QUEST_ICON_SLOT_WIDTH,
        QUEST_ICON_SLOT_PADDING_X,
        0,
        QUEST_MIN_HEIGHT
    )
    control:SetHidden(false)
    AnchorControl(control, QUEST_INDENT_X)

    if quest and quest.journalIndex then
        state.questControls[quest.journalIndex] = control
    end

    if expanded then
        for stepIndex = 1, #quest.steps do
            local step = quest.steps[stepIndex]
            if step.isVisible ~= false then
                for conditionIndex = 1, #step.conditions do
                    LayoutCondition(step.conditions[conditionIndex])
                end
            end
        end
    end
end

local function LayoutCategory(category)
    local control = AcquireCategoryControl()
    control.data = {
        categoryKey = category.key,
        parentKey = category.parent and category.parent.key or nil,
        parentName = category.parent and category.parent.name or nil,
        groupKey = category.groupKey,
        groupName = category.groupName,
        categoryType = category.type,
        groupOrder = category.groupOrder,
    }
    local normalizedKey = NormalizeCategoryKey(category.key)
    if normalizedKey then
        state.categoryControls[normalizedKey] = control
    end
    local count = #category.quests
    control.label:SetText(FormatCategoryHeaderText(category.name or "", count, "quest"))
    local expanded = IsCategoryExpanded(category.key)
    if IsDebugLoggingEnabled() then
        DebugLog(string.format(
            "BUILD_APPLY cat=%s expanded=%s",
            tostring(category.key),
            tostring(expanded)
        ))
    end
    local colorRole = expanded and "activeTitle" or "categoryTitle"
    local r, g, b, a = GetQuestTrackerColor(colorRole)
    ApplyBaseColor(control, r, g, b, a)
    UpdateCategoryToggle(control, expanded)
    ApplyRowMetrics(
        control,
        CATEGORY_INDENT_X,
        GetToggleWidth(control.toggle, CATEGORY_TOGGLE_WIDTH),
        TOGGLE_LABEL_PADDING_X,
        0,
        CATEGORY_MIN_HEIGHT
    )
    control:SetHidden(false)
    AnchorControl(control, CATEGORY_INDENT_X)

    if expanded then
        for index = 1, count do
            LayoutQuest(category.quests[index])
        end
    end
end

local function ReleaseRowControl(control)
    if not control then
        return
    end

    local rowType = control.rowType
    if rowType == "category" then
        local normalized = control.data and NormalizeCategoryKey(control.data.categoryKey)
        if normalized then
            state.categoryControls[normalized] = nil
        end
        if state.categoryPool and control.poolKey then
            state.categoryPool:ReleaseObject(control.poolKey)
        end
    elseif rowType == "quest" then
        local questData = control.data and control.data.quest
        if questData and questData.journalIndex then
            state.questControls[questData.journalIndex] = nil
        end
        if state.questPool and control.poolKey then
            state.questPool:ReleaseObject(control.poolKey)
        end
    else
        if state.conditionPool and control.poolKey then
            state.conditionPool:ReleaseObject(control.poolKey)
        end
    end
end

local function TrimOrderedControlsToCategory(keepCategoryCount)
    if keepCategoryCount <= 0 then
        ReleaseAll(state.categoryPool)
        ReleaseAll(state.questPool)
        ReleaseAll(state.conditionPool)
        ResetLayoutState()
        return
    end

    local categoryCounter = 0
    local releaseStartIndex = nil

    for index = 1, #state.orderedControls do
        local control = state.orderedControls[index]
        if control and control.rowType == "category" then
            categoryCounter = categoryCounter + 1
            if categoryCounter > keepCategoryCount then
                releaseStartIndex = index
                break
            end
        end
    end

    if releaseStartIndex then
        for index = #state.orderedControls, releaseStartIndex, -1 do
            ReleaseRowControl(state.orderedControls[index])
            table.remove(state.orderedControls, index)
        end
    end

    state.lastAnchoredControl = state.orderedControls[#state.orderedControls]
end

local function RelayoutFromCategoryIndex(startCategoryIndex)
    ApplyActiveQuestFromSaved()
    EnsurePools()

    if not state.snapshot or not state.snapshot.categories or not state.snapshot.categories.ordered then
        ReleaseAll(state.categoryPool)
        ReleaseAll(state.questPool)
        ReleaseAll(state.conditionPool)
        ResetLayoutState()
        UpdateContentSize()
        NotifyHostContentChanged()
        ProcessPendingExternalReveal()
        return
    end

    if startCategoryIndex <= 1 then
        ReleaseAll(state.categoryPool)
        ReleaseAll(state.questPool)
        ReleaseAll(state.conditionPool)
        ResetLayoutState()
        startCategoryIndex = 1
    else
        TrimOrderedControlsToCategory(startCategoryIndex - 1)
    end

    PrimeInitialSavedState()

    for index = startCategoryIndex, #state.snapshot.categories.ordered do
        local category = state.snapshot.categories.ordered[index]
        if category and category.quests and #category.quests > 0 then
            LayoutCategory(category)
        end
    end

    UpdateContentSize()
    NotifyHostContentChanged()
    ProcessPendingExternalReveal()
end

local function ApplySnapshot(snapshot, context)
    state.snapshot = snapshot
    SyncQuestFlagsFromSnapshot(snapshot)

    local trackingContext = {
        trigger = (context and context.trigger) or "refresh",
        source = (context and context.source) or "QuestTracker:ApplySnapshot",
    }

    UpdateTrackedQuestCache(nil, trackingContext)

    if state.trackedQuestIndex then
        EnsureTrackedQuestVisible(state.trackedQuestIndex, nil, trackingContext)
    end

    NotifyStatusRefresh()
end

-- Apply the latest quest snapshot from the event-driven model and update the layout.
local function OnQuestModelSnapshotUpdated(snapshot, context)
    ApplySnapshot(snapshot or { categories = { ordered = {}, byKey = {} } }, context)

    if not state.isInitialized then
        return
    end

    RelayoutFromCategoryIndex(1)
end

-- Listen for snapshot updates from the quest model so the tracker stays in sync with game events.
local function SubscribeToQuestModel()
    if state.questModelSubscription then
        return
    end

    EnsureQuestModel()

    if not (QuestModel and QuestModel.Subscribe) then
        return
    end

    state.questModelSubscription = function(snapshot)
        OnQuestModelSnapshotUpdated(snapshot, {
            trigger = "model",
            source = "QuestTracker:QuestModelSubscription",
        })
    end

    QuestModel.Subscribe(state.questModelSubscription)
end

local function UnsubscribeFromQuestModel()
    EnsureQuestModel()

    if state.questModelSubscription and QuestModel and QuestModel.Unsubscribe then
        QuestModel.Unsubscribe(state.questModelSubscription)
    end

    state.questModelSubscription = nil
end

local function Rebuild()
    if not state.container then
        return
    end

    if IsDebugLoggingEnabled() then
        DebugLog("REBUILD_START")
    end

    state.isRebuildInProgress = true
    ApplyActiveQuestFromSaved()

    EnsurePools()

    ReleaseAll(state.categoryPool)
    ReleaseAll(state.questPool)
    ReleaseAll(state.conditionPool)
    ResetLayoutState()

    if not state.snapshot or not state.snapshot.categories or not state.snapshot.categories.ordered then
        UpdateContentSize()
        NotifyHostContentChanged()
        state.isRebuildInProgress = false
        if IsDebugLoggingEnabled() then
            DebugLog("REBUILD_END")
        end
        return
    end

    PrimeInitialSavedState()

    for index = 1, #state.snapshot.categories.ordered do
        local category = state.snapshot.categories.ordered[index]
        if category and category.quests and #category.quests > 0 then
            LayoutCategory(category)
        end
    end

    UpdateContentSize()
    NotifyHostContentChanged()
    ProcessPendingExternalReveal()

    state.isRebuildInProgress = false

    if IsDebugLoggingEnabled() then
        DebugLog("REBUILD_END")
    end
end

local function RefreshVisibility()
    if not state.control then
        return
    end

    local hidden = state.opts.active == false

    state.control:SetHidden(hidden)
    NotifyHostContentChanged()
end

function QuestTracker.Init(parentControl, opts)
    if state.isInitialized then
        return
    end

    assert(parentControl ~= nil, "QuestTracker.Init requires a parent control")

    state.control = parentControl
    state.container = parentControl
    if state.control and state.control.SetResizeToFitDescendents then
        state.control:SetResizeToFitDescendents(true)
    end

    EnsureSavedVars()

    if not UpdateReposReadyState() then
        EnsureReposReadySubscription()
    end

    if Nvk3UT and Nvk3UT.playerActivated == true then
        state.playerActivated = true
    end

    if state.playerActivated then
        ApplyActiveQuestFromSaved()
    end

    state.opts = {}
    state.fonts = {}
    state.pendingSelection = nil
    state.lastTrackedBeforeSync = nil
    state.syncingTrackedState = false
    state.pendingDeselection = false
    state.pendingExternalReveal = nil

    QuestTracker.ApplyTheme(state.saved or {})
    QuestTracker.ApplySettings(state.saved or {})

    if opts then
        QuestTracker.ApplyTheme(opts)
        QuestTracker.ApplySettings(opts)
    end

    RegisterTrackingEvents()

    SubscribeToQuestModel()

    state.isInitialized = true
    RefreshVisibility()

    EnsureQuestModel()

    local snapshot = state.snapshot
        or (QuestModel and QuestModel.GetSnapshot and QuestModel.GetSnapshot())

    OnQuestModelSnapshotUpdated(snapshot, {
        trigger = "init",
        source = "QuestTracker:Init",
    })
    AdoptTrackedQuestOnInit()
end

function QuestTracker.Refresh()
    Rebuild()
end

function QuestTracker.ApplyActiveQuestVisuals(oldQuestId, newQuestId)
    return ApplyActiveQuestVisuals(oldQuestId, newQuestId)
end

function QuestTracker.Shutdown()
    if not state.isInitialized then
        return
    end

    UnregisterTrackingEvents()
    UnsubscribeFromQuestModel()
    ClearReposReadySubscription()

    if state.categoryPool then
        state.categoryPool:ReleaseAllObjects()
        state.categoryPool = nil
    end

    if state.questPool then
        state.questPool:ReleaseAllObjects()
        state.questPool = nil
    end

    if state.conditionPool then
        state.conditionPool:ReleaseAllObjects()
        state.conditionPool = nil
    end

    state.container = nil
    state.control = nil
    state.snapshot = nil
    if QuestState and QuestState.PruneQuestFlags then
        QuestState.PruneQuestFlags({})
    end
    state.orderedControls = {}
    state.lastAnchoredControl = nil
    state.categoryControls = {}
    state.questControls = {}
    state.isInitialized = false
    state.opts = {}
    state.fonts = {}
    state.pendingRefresh = false
    state.contentWidth = 0
    state.contentHeight = 0
    state.trackedQuestIndex = nil
    state.trackedCategoryKeys = {}
    state.trackingEventsRegistered = false
    state.suppressForceExpandFor = nil
    state.pendingSelection = nil
    state.lastTrackedBeforeSync = nil
    state.syncingTrackedState = false
    state.pendingDeselection = false
    state.pendingExternalReveal = nil
    state.selectedQuestKey = nil
    state.isRebuildInProgress = false
    state.questModelSubscription = nil
    state.repoPrimed = false
    state.activeQuestId = nil
    state.reposReady = false
    state.playerActivated = false
    state.pendingActiveQuestApply = false
    NotifyHostContentChanged()
end

function QuestTracker.SetActive(active)
    state.opts.active = active
    RefreshVisibility()
    NotifyStatusRefresh()
end

function QuestTracker.ApplySettings(settings)
    if type(settings) ~= "table" then
        return
    end

    state.opts.autoExpand = settings.autoExpand ~= false
    state.opts.autoTrack = settings.autoTrack ~= false
    state.opts.active = (settings.active ~= false)

    RefreshVisibility()
    RequestRefresh()
    NotifyStatusRefresh()
end

function QuestTracker.ApplyTheme(settings)
    if type(settings) ~= "table" then
        return
    end

    state.opts.fonts = state.opts.fonts or {}

    local fonts = settings.fonts or {}
    state.opts.fonts.category = BuildFontString(fonts.category, state.opts.fonts.category or DEFAULT_FONTS.category)
    state.opts.fonts.quest = BuildFontString(fonts.title, state.opts.fonts.quest or DEFAULT_FONTS.quest)
    state.opts.fonts.condition = BuildFontString(fonts.line, state.opts.fonts.condition or DEFAULT_FONTS.condition)
    state.opts.fonts.toggle = state.opts.fonts.category or DEFAULT_FONTS.toggle
    state.fonts = MergeFonts(state.opts.fonts)

    RequestRefresh()
end

function QuestTracker.IsActive()
    return state.opts.active ~= false
end

function QuestTracker.RequestRefresh()
    RequestRefresh()
end

function QuestTracker.GetContentSize()
    UpdateContentSize()
    return state.contentWidth or 0, state.contentHeight or 0
end

Nvk3UT.QuestTracker = QuestTracker

return QuestTracker
