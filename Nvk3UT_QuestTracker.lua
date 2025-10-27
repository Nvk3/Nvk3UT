local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local QuestTracker = {}
QuestTracker.__index = QuestTracker

local MODULE_NAME = addonName .. "QuestTracker"
local EVENT_NAMESPACE = MODULE_NAME .. "_Event"

local Utils = Nvk3UT and Nvk3UT.Utils
local FormatCategoryHeaderText =
    (Utils and Utils.FormatCategoryHeaderText)
    or function(baseText, count, showCounts)
        local text = baseText or ""
        if showCounts ~= false and type(count) == "number" and count >= 0 then
            local numericCount = math_floor(count + 0.5)
            return string_format("%s (%d)", text, numericCount)
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

local string_format = string.format
local math_floor = math.floor
local tostring = tostring
local type = type
local pairs = pairs
local WINDOW_MANAGER = WINDOW_MANAGER

local STRUCTURE_REBUILD_BATCH_SIZE = 12
local QUEST_REBUILD_TASK_NAME = MODULE_NAME .. "_StructureRebuild"
local Async = LibAsync

local DEFAULT_FONTS = {
    category = "$(BOLD_FONT)|20|soft-shadow-thick",
    quest = "$(BOLD_FONT)|16|soft-shadow-thick",
    condition = "$(BOLD_FONT)|14|soft-shadow-thick",
    toggle = "$(BOLD_FONT)|20|soft-shadow-thick",
}

local DEFAULT_FONT_OUTLINE = "soft-shadow-thick"
local COLOR_ROW_HOVER = { 1, 1, 0.6, 1 }

local EMPTY_TABLE = {}

-- Forward-declared tracker state so helper functions defined below (such as
-- GenerateControlName or the pooling helpers) share the same table instance
-- even before it is populated later in the file. Without this, those helpers
-- would capture a nil upvalue and trigger rebuild failures once invoked.
local state

local function GenerateControlName(controlType)
    local counters = state.controlNameCounters
    if not counters then
        counters = {}
        state.controlNameCounters = counters
    end

    counters[controlType] = (counters[controlType] or 0) + 1

    local container = state.container
    local baseName = (container and container.GetName and container:GetName()) or MODULE_NAME

    -- Include a monotonically increasing suffix per control type so new pooled
    -- controls always receive unique global names. Without this, CreateControl*
    -- would collide with existing controls on rebuild, throwing an error and
    -- restarting the structure job indefinitely.
    return string_format("%s_%s_%d", baseName, controlType or "control", counters[controlType])
end

local RequestRefresh -- forward declaration for functions that trigger refreshes
local SetCategoryExpanded -- forward declaration for expansion helpers used before assignment
local SetQuestExpanded
local IsQuestExpanded -- forward declaration so earlier functions can query quest expansion state
local HandleQuestRowClick -- forward declaration for quest row click orchestration
local FlushPendingTrackedQuestUpdate -- forward declaration for deferred tracking updates
local ProcessTrackedQuestUpdate -- forward declaration for deferred tracking processing
local ApplyQuestRowVisuals -- forward declaration for the quest row refresh helper
local ResolveQuestRowData -- forward declaration for retrieving quest data during row refresh
local EnsurePools -- forward declaration for quest control pooling
local ResetCategoryControl -- forward declaration so pool acquisition can reset controls before use
local ResetQuestControl -- forward declaration for quest control reset helpers
local ResetConditionControl -- forward declaration for condition control reset helpers
local AcquireCategoryControlFromPool -- forward declaration for category pool access
local AcquireQuestControlFromPool -- forward declaration for quest pool access
local ReleaseConditionControls -- forward declaration for releasing pooled condition controls
local TrackActiveControl -- forward declaration for tracking active controls per rebuild
local ReleaseActiveControls -- forward declaration for releasing controls back to pools

--[=[
QuestTrackerRow encapsulates the data and controls for a single quest row. The
instance keeps a stable reference to the quest it represents along with the UI
control that renders it so we can refresh the row in isolation when needed.
The structure mirrors the per-row update strategy used by Ravalox, preparing
the tracker for targeted refreshes without changing existing behavior yet.
]=]
local QuestTrackerRow = {}
QuestTrackerRow.__index = QuestTrackerRow

function QuestTrackerRow:New(options)
    local opts = options or {}
    local instance = setmetatable({}, QuestTrackerRow)
    instance.questKey = opts.questKey
    instance.quest = opts.quest
    instance.control = opts.control
    instance.lastHeight = 0
    return instance
end

function QuestTrackerRow:SetControl(control)
    self.control = control
end

function QuestTrackerRow:ClearControl()
    self.control = nil
    self.lastHeight = 0
end

function QuestTrackerRow:DetachControl()
    local control = self.control
    self:ClearControl()
    return control
end

function QuestTrackerRow:SetQuest(questData)
    self.quest = questData
    if questData and questData.journalIndex then
        local normalized = NormalizeQuestKey and NormalizeQuestKey(questData.journalIndex)
        if normalized then
            self.questKey = normalized
        end
    end
end

function QuestTrackerRow:Refresh(questData)
    local resolvedData = questData
    if resolvedData == nil and ResolveQuestRowData then
        resolvedData = ResolveQuestRowData(self.questKey)
    end

    if resolvedData ~= nil then
        self:SetQuest(resolvedData)
    end

    local control = self.control
    local quest = self.quest

    if not (control and quest) then
        return
    end

    if not (ApplyQuestRowVisuals and quest) then
        return
    end

    ApplyQuestRowVisuals(control, quest)

    local getHeight = control.GetHeight
    if getHeight then
        self.lastHeight = getHeight(control) or 0
    end

    return self.lastHeight
end

function QuestTrackerRow:GetHeight()
    if self.control and self.control.GetHeight then
        self.lastHeight = self.control:GetHeight() or self.lastHeight or 0
    end

    return self.lastHeight or 0
end

state = {
    isInitialized = false,
    opts = {},
    fonts = {},
    saved = nil,
    control = nil,
    container = nil,
    categoryPool = nil,
    questPool = nil,
    conditionPool = nil,
    conditionActiveControls = {},
    orderedControls = {},
    lastAnchoredControl = nil,
    snapshot = nil,
    subscription = nil,
    categoryControls = {},
    questControls = {},
    questControlsByKey = {},
    questRows = {}, -- registry of QuestTrackerRow instances keyed by normalized quest id
    activeControls = {}, -- active row controls currently attached to the tracker
    controlNameCounters = {},
    combatHidden = false,
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
    pendingAdoptOnInit = false,
    rebuildJob = nil,
    activeRebuildContext = nil,
}

local STATE_VERSION = 1

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
        d(string_format("[%s]", MODULE_NAME), ...)
    elseif print then
        print("[" .. MODULE_NAME .. "]", ...)
    end
end

local function DebugDeselect(context, details)
    if not NVK_DEBUG_DESELECT then
        return
    end

    local parts = { string_format("[%s][DESELECT] %s", MODULE_NAME, tostring(context)) }

    if type(details) == "table" then
        for key, value in pairs(details) do
            parts[#parts + 1] = string_format("%s=%s", tostring(key), tostring(value))
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
        parts[#parts + 1] = string_format("%s=nil", key)
        return
    end

    local valueType = type(value)
    if valueType == "boolean" then
        parts[#parts + 1] = string_format("%s=%s", key, value and "true" or "false")
    elseif valueType == "number" then
        parts[#parts + 1] = string_format("%s=%s", key, tostring(value))
    elseif treatAsString or valueType == "string" then
        parts[#parts + 1] = string_format('%s="%s"', key, EscapeDebugString(value))
    else
        parts[#parts + 1] = string_format("%s=%s", key, tostring(value))
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

ResolveQuestRowData = function(questKey)
    local normalized = NormalizeQuestKey(questKey)
    if not normalized then
        return nil
    end

    local numeric = QuestKeyToJournalIndex(normalized)
    if numeric and state.questControls then
        local control = state.questControls[numeric]
        if control and control.data and control.data.quest then
            return control.data.quest
        end
    end

    local snapshot = state.snapshot
    if not snapshot or not snapshot.categories or not snapshot.categories.ordered then
        return nil
    end

    for categoryIndex = 1, #snapshot.categories.ordered do
        local category = snapshot.categories.ordered[categoryIndex]
        local quests = category and category.quests
        if type(quests) == "table" then
            for questIndex = 1, #quests do
                local quest = quests[questIndex]
                if quest and NormalizeQuestKey(quest.journalIndex) == normalized then
                    return quest
                end
            end
        end
    end

    return nil
end

local function QueueQuestStructureUpdate(context)
    local host = Nvk3UT and Nvk3UT.TrackerHost
    if host and host.MarkQuestsStructureDirty then
        host.MarkQuestsStructureDirty(context)
    end
end

local function QueueLayoutUpdate(context)
    local host = Nvk3UT and Nvk3UT.TrackerHost
    if host and host.MarkLayoutDirty then
        host.MarkLayoutDirty(context)
    end
end

local function GetQuestRebuildJob()
    state.rebuildJob = state.rebuildJob or {
        active = false,
        restartRequested = false,
        batchSize = STRUCTURE_REBUILD_BATCH_SIZE,
        totalProcessed = 0,
        reason = nil,
    }

    return state.rebuildJob
end

local function ClearActiveRebuildContext()
    state.activeRebuildContext = nil
end

local function ShouldAbortRebuild()
    local job = state.rebuildJob
    return job and job.active and job.restartRequested == true
end

local function ConsumeStructureBudget(amount)
    local context = state.activeRebuildContext
    if not context then
        return
    end

    local processed = amount or 1
    context.pending = (context.pending or 0) + processed
    context.total = (context.total or 0) + processed

    local job = state.rebuildJob
    if job and job.active then
        job.totalProcessed = (job.totalProcessed or 0) + processed
    end

    local batchSize = context.batchSize or STRUCTURE_REBUILD_BATCH_SIZE

    if context.pending >= batchSize then
        context.pending = 0
        context.batches = (context.batches or 0) + 1

        if context.onBatchReady then
            context.onBatchReady(context)
        end

        local task = context.task
        if task and task.Yield then
            task:Yield()
        end
    end
end

local function QueueQuestRowRefreshByKey(questKey, context)
    if not questKey then
        return false
    end

    local normalized = questKey
    if NormalizeQuestKey then
        normalized = NormalizeQuestKey(questKey) or questKey
    end

    if normalized == nil then
        return false
    end

    local host = Nvk3UT and Nvk3UT.TrackerHost
    if host and host.QueueQuestRowRefresh then
        return host.QueueQuestRowRefresh(normalized, context)
    end

    return false
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

    local questKey = NormalizeQuestKey(quest.journalIndex)
    local selected = false
    if questKey and state.selectedQuestKey then
        selected = questKey == state.selectedQuestKey
    end

    local tracked = false
    if state.trackedQuestIndex and quest.journalIndex then
        tracked = quest.journalIndex == state.trackedQuestIndex
    end

    local flags = quest.flags or {}
    local assisted = flags.assisted == true
    local watched = flags.tracked == true

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

local function QuestKeyToJournalIndex(questKey)
    if questKey == nil then
        return nil
    end

    if type(questKey) == "table" and questKey.questKey then
        questKey = questKey.questKey
    end

    local numeric = tonumber(questKey)
    if numeric and numeric > 0 then
        return numeric
    end

    return nil
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


local function FindQuestCategoryIndex(snapshot, journalIndex)
    if not snapshot or not snapshot.categories or not snapshot.categories.ordered then
        return nil, nil
    end

    local ordered = snapshot.categories.ordered
    if type(ordered) ~= "table" then
        return nil, nil
    end

    for categoryIndex = 1, #ordered do
        local category = ordered[categoryIndex]
        local quests = category and category.quests
        if type(quests) == "table" then
            for questIndex = 1, #quests do
                local quest = quests[questIndex]
                if quest and quest.journalIndex == journalIndex then
                    return categoryIndex, questIndex
                end
            end
        end
    end

    return nil, nil
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
        formatted = string_format(
            "STATE_WRITE cat=%s expanded=%s source=%s prio=%d",
            tostring(key),
            tostring(expanded),
            tostring(source),
            priority or 0
        )
    elseif entity == "quest" then
        formatted = string_format(
            "STATE_WRITE quest=%s expanded=%s source=%s prio=%d",
            tostring(key),
            tostring(expanded),
            tostring(source),
            priority or 0
        )
    elseif entity == "active" then
        formatted = string_format(
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

local function EnsureActiveSavedState()
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
    if not state.saved then
        state.selectedQuestKey = nil
        return nil
    end

    local active = EnsureActiveSavedState()
    local questKey = active and active.questKey or nil
    if questKey ~= nil then
        questKey = NormalizeQuestKey(questKey)
    end

    state.selectedQuestKey = questKey
    return questKey
end

local function ApplyActiveQuestFromSaved()
    local questKey = SyncSelectedQuestFromSaved()
    local journalIndex = QuestKeyToJournalIndex(questKey)

    state.trackedQuestIndex = journalIndex

    if journalIndex then
        state.trackedCategoryKeys = CollectCategoryKeysForQuest(journalIndex)
    else
        state.trackedCategoryKeys = {}
    end

    return journalIndex
end

local function WriteCategoryState(categoryKey, expanded, source, options)
    if not state.saved then
        return false
    end

    local key = NormalizeCategoryKey(categoryKey)
    if not key then
        return false
    end

    source = source or "auto"
    options = options or {}
    state.saved.cat = state.saved.cat or {}

    local prev = state.saved.cat[key]
    local newExpanded = expanded and true or false
    -- Avoid marking the tracker dirty when the category state already matches
    -- the requested value. Previously we rewrote the same state, which
    -- re-queued rebuilds and fed the infinite loop triggered by the duplicate
    -- control failure.
    if prev and prev.expanded ~= nil and prev.expanded == newExpanded then
        return false
    end

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

    state.saved.cat[key] = {
        expanded = newExpanded,
        source = source,
        ts = now,
    }

    LogStateWrite("cat", key, newExpanded, source, priority)

    return true
end

local function WriteQuestState(questKey, expanded, source, options)
    if not state.saved then
        return false
    end

    local key = NormalizeQuestKey(questKey)
    if not key then
        return false
    end

    source = source or "auto"
    options = options or {}
    state.saved.quest = state.saved.quest or {}

    local prev = state.saved.quest[key]
    local newExpanded = expanded and true or false
    -- Mirror the category guard so repeated quest expand requests do not keep
    -- setting the dirty flag when nothing actually changed.
    if prev and prev.expanded ~= nil and prev.expanded == newExpanded then
        return false
    end

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

    state.saved.quest[key] = {
        expanded = newExpanded,
        source = source,
        ts = now,
    }

    LogStateWrite("quest", key, newExpanded, source, priority)

    return true
end

local function WriteActiveQuest(questKey, source, options)
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
    if not state.saved then
        return
    end

    if not state.snapshot or not state.snapshot.categories then
        return
    end

    local ordered = state.snapshot.categories.ordered
    if type(ordered) ~= "table" then
        return
    end

    state.saved.initializedAt = state.saved.initializedAt or GetCurrentTimeSeconds()
    local initTimestamp = tonumber(state.saved.initializedAt) or GetCurrentTimeSeconds()

    local primedCategories = 0
    local primedQuests = 0

    for index = 1, #ordered do
        local category = ordered[index]
        if category then
            local catKey = NormalizeCategoryKey(category.key)
            if catKey then
                local entry = state.saved.cat and state.saved.cat[catKey]
                local entryTs = (entry and entry.ts) or 0
                if entryTs < initTimestamp or not entry then
                    if WriteCategoryState(catKey, true, "init", { timestamp = initTimestamp }) then
                        primedCategories = primedCategories + 1
                    end
                end
            end

            if type(category.quests) == "table" then
                for questIndex = 1, #category.quests do
                    local quest = category.quests[questIndex]
                    if quest then
                        local questKey = NormalizeQuestKey(quest.journalIndex)
                        if questKey then
                            local entry = state.saved.quest and state.saved.quest[questKey]
                            local entryTs = (entry and entry.ts) or 0
                            if entryTs < initTimestamp or not entry then
                                if WriteQuestState(questKey, true, "init", { timestamp = initTimestamp }) then
                                    primedQuests = primedQuests + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local active = EnsureActiveSavedState()
    local activeTs = (active and active.ts) or 0
    if activeTs < initTimestamp then
        WriteActiveQuest(active and active.questKey or nil, "init", { timestamp = initTimestamp })
    end

    if IsDebugLoggingEnabled() and (primedCategories > 0 or primedQuests > 0) then
        DebugLog(string_format(
            "STATE_PRIME timestamp=%.3f categories=%d quests=%d",
            initTimestamp,
            primedCategories,
            primedQuests
        ))
    end
end

local function EnsureSavedDefaults(saved)
    saved.defaults = saved.defaults or {}
    if saved.defaults.categoryExpanded == nil then
        saved.defaults.categoryExpanded = true
    else
        saved.defaults.categoryExpanded = saved.defaults.categoryExpanded and true or false
    end
    if saved.defaults.questExpanded == nil then
        saved.defaults.questExpanded = true
    else
        saved.defaults.questExpanded = saved.defaults.questExpanded and true or false
    end
end

local function MigrateLegacySavedState(saved)
    if type(saved) ~= "table" then
        return
    end

    saved.cat = saved.cat or {}
    saved.quest = saved.quest or {}

    local legacyCategories = saved.catExpanded
    if type(legacyCategories) == "table" then
        for key, value in pairs(legacyCategories) do
            local normalized = NormalizeCategoryKey(key)
            if normalized then
                saved.cat[normalized] = {
                    expanded = value and true or false,
                    source = "init",
                    ts = 0,
                }
            end
        end
    end

    saved.catExpanded = nil

    local legacyQuests = saved.questExpanded
    if type(legacyQuests) == "table" then
        for key, value in pairs(legacyQuests) do
            local normalized = NormalizeQuestKey(key)
            if normalized then
                saved.quest[normalized] = {
                    expanded = value and true or false,
                    source = "init",
                    ts = 0,
                }
            end
        end
    end

    saved.questExpanded = nil

    if type(saved.active) ~= "table" then
        saved.active = {
            questKey = nil,
            source = "init",
            ts = 0,
        }
    else
        if saved.active.questKey ~= nil then
            saved.active.questKey = NormalizeQuestKey(saved.active.questKey)
        end
        saved.active.source = saved.active.source or "init"
        saved.active.ts = saved.active.ts or 0
    end

    EnsureSavedDefaults(saved)
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
        local questData = control.data and control.data.quest
        local questKey = questData and NormalizeQuestKey(questData.journalIndex)
        local row = questKey and state.questRows[questKey]
        if row then
            row:SetControl(control)
        end
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

local function SafeCall(func, ...)
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
        DebugLog(string_format("QuestManager call failed (%s): %s", methodName, tostring(result)))
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

    DebugLog(string_format("EXTERNAL_SELECT questId=%s", tostring(questId)))
end

local function LogExpandCategory(categoryId, reason)
    if not IsDebugLoggingEnabled() then
        return
    end

    DebugLog(string_format(
        "EXPAND_CATEGORY categoryId=%s reason=%s",
        tostring(categoryId),
        reason or "external-select"
    ))
end

local function LogMissingCategory(questId)
    if not IsDebugLoggingEnabled() then
        return
    end

    DebugLog(string_format("WARN missing-category questId=%s", tostring(questId)))
end

local function LogScrollIntoView(questId)
    if not IsDebugLoggingEnabled() then
        return
    end

    DebugLog(string_format("SCROLL_INTO_VIEW questId=%s", tostring(questId)))
end

local function ExpandCategoriesForExternalSelect(journalIndex)
    if not (state.saved and journalIndex) then
        return false, false
    end

    local keys, found = CollectCategoryKeysForQuest(journalIndex)
    local expandedAny = false

    if keys then
        local context = {
            trigger = "external-select",
            source = "QuestTracker:ExpandCategoriesForExternalSelect",
            forceWrite = true,
        }

        for key in pairs(keys) do
            if key and SetCategoryExpanded then
                local changed = SetCategoryExpanded(key, true, context)
                if changed then
                    expandedAny = true
                    LogExpandCategory(key, "external-select")
                end
            end
        end
    end

    if (not found) or not keys or next(keys) == nil then
        LogMissingCategory(journalIndex)
    end

    if expandedAny then
        QueueQuestStructureUpdate({
            reason = "QuestTracker:ExpandCategoriesForExternalSelect",
            trigger = "external-select",
        })
    end

    return expandedAny, found
end

local function ExpandCategoriesForClickSelect(journalIndex)
    if not (state.saved and journalIndex) then
        return false, false
    end

    local keys, found = CollectCategoryKeysForQuest(journalIndex)
    local expandedAny = false

    if keys then
        local context = {
            trigger = "click-select",
            source = "QuestTracker:ExpandCategoriesForClickSelect",
        }

        for key in pairs(keys) do
            if key and SetCategoryExpanded then
                local changed = SetCategoryExpanded(key, true, context)
                if changed then
                    expandedAny = true
                    LogExpandCategory(key, "click-select")
                end
            end
        end
    end

    if (not found) or not keys or next(keys) == nil then
        LogMissingCategory(journalIndex)
    end

    if expandedAny then
        QueueQuestStructureUpdate({
            reason = "QuestTracker:ExpandCategoriesForClickSelect",
            trigger = "click-select",
        })
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

local function DoesJournalQuestExist(journalIndex)
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
        local numeric = tonumber(index)
        if not numeric or numeric <= 0 then
            return nil
        end

        if DoesJournalQuestExist(numeric) then
            return numeric
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

            if not (quest and quest.flags and quest.flags.tracked) then
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
    if not (journalIndex and IsJournalQuestTracked and SetTracked) then
        return
    end

    if IsJournalQuestTracked(journalIndex) then
        return
    end

    if not SafeCall(SetTracked, TRACK_TYPE_QUEST, journalIndex, true) then
        SafeCall(SetTracked, TRACK_TYPE_QUEST, journalIndex)
    end
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
    if not (state.saved and journalIndex) then
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

    DebugDeselect("AutoExpandQuestForTracking", {
        journalIndex = journalIndex,
        forceExpand = tostring(forceExpand),
        previous = tostring(
            state.saved
                and state.saved.quest
                and state.saved.quest[questKey]
                and state.saved.quest[questKey].expanded
        ),
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
    if not (state.saved and journalIndex) then
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
    }

    local debugEnabled = IsDebugLoggingEnabled()

    for key in pairs(keys) do
        if key then
            local changed = SetCategoryExpanded(key, true, logContext)
            if debugEnabled and not changed then
                DebugLog(
                    "Category expand skipped",
                    "category",
                    key,
                    "journalIndex",
                    journalIndex,
                    "trigger",
                    logContext.trigger
                )
            end
        end
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

        local needsRowRefresh = previousTracked ~= currentTracked or hasTracked or hadTracked or pendingApplied or expansionChanged

        if expansionChanged then
            QueueQuestStructureUpdate({
                reason = "QuestTracker:SyncTrackedQuestState",
                trigger = trigger,
            })
        end

        if needsRowRefresh then
            if previousTracked then
                QueueQuestRowRefreshByKey(
                    NormalizeQuestKey(previousTracked),
                    {
                        reason = "QuestTracker:TrackedQuestChanged",
                        trigger = trigger,
                        source = source,
                    }
                )
            end

            if currentTracked then
                QueueQuestRowRefreshByKey(
                    NormalizeQuestKey(currentTracked),
                    {
                        reason = "QuestTracker:TrackedQuestChanged",
                        trigger = trigger,
                        source = source,
                    }
                )
            end
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
    if not (QUEST_JOURNAL_KEYBOARD and QUEST_JOURNAL_KEYBOARD.FocusQuestWithIndex) then
        return
    end

    SafeCall(function(journal, index)
        journal:FocusQuestWithIndex(index)
    end, QUEST_JOURNAL_KEYBOARD, journalIndex)
end

local function ForceAssistTrackedQuest(journalIndex)
    if not (FOCUSED_QUEST_TRACKER and FOCUSED_QUEST_TRACKER.ForceAssist) then
        return
    end

    SafeCall(function(tracker, index)
        tracker:ForceAssist(index)
    end, FOCUSED_QUEST_TRACKER, journalIndex)
end

local function RequestRefreshInternal(context)
    if not state.isInitialized then
        return
    end

    QueueQuestStructureUpdate(context or { reason = "QuestTracker.RequestRefresh" })
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

    local shouldRequestRefresh = options.requestRefresh
    if shouldRequestRefresh == nil then
        shouldRequestRefresh = true
    end

    if shouldRequestRefresh then
        QueueQuestRowRefreshByKey(
            NormalizeQuestKey(numeric),
            {
                reason = "QuestTracker:TrackQuestByJournalIndex",
                trigger = options.trigger or "auto",
                source = options.source,
            }
        )
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
            DebugLog(string_format("CLICK_SELECT_SKIPPED questId=%s reason=in-progress", tostring(questId)))
        end
        return
    end

    state.isClickSelectInProgress = true

    if IsDebugLoggingEnabled() then
        DebugLog(string_format("CLICK_SELECT_START questId=%s", tostring(questId)))
    end

    state.pendingSelection = nil

    local previousQuest = state.trackedQuestIndex
    local previousQuestString = previousQuest and tostring(previousQuest) or "nil"

    ApplyImmediateTrackedQuest(questId, "click-select")

    if IsDebugLoggingEnabled() then
        DebugLog(string_format("SET_ACTIVE questId=%s prev=%s", tostring(questId), previousQuestString))
    end

    local questKey = NormalizeQuestKey(questId)
    QueueQuestRowRefreshByKey(
        questKey,
        {
            reason = "QuestTracker:HandleQuestRowClick",
            trigger = "click",
            source = "QuestTracker:HandleQuestRowClick",
        }
    )

    if previousQuest then
        QueueQuestRowRefreshByKey(
            NormalizeQuestKey(previousQuest),
            {
                reason = "QuestTracker:HandleQuestRowClick",
                trigger = "click",
                source = "QuestTracker:HandleQuestRowClick",
            }
        )
    end

    if IsDebugLoggingEnabled() then
        DebugLog(string_format("UI_SELECT questId=%s", tostring(questId)))
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

    if IsDebugLoggingEnabled() then
        DebugLog(string_format("CLICK_SELECT_END questId=%s", tostring(questId)))
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
    local function execute()
        SyncTrackedQuestState(nil, true, {
            trigger = "init",
            source = "QuestTracker:OnPlayerActivated",
            isExternal = true,
        })
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
    local saved = Nvk3UT.sv.QuestTracker or {}
    Nvk3UT.sv.QuestTracker = saved

    if type(saved.stateVersion) ~= "number" or saved.stateVersion < STATE_VERSION then
        MigrateLegacySavedState(saved)
        saved.stateVersion = STATE_VERSION
    end

    saved.cat = saved.cat or {}
    saved.quest = saved.quest or {}

    state.saved = saved
    EnsureActiveSavedState()

    EnsureSavedDefaults(saved)

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

    return string_format("%s|%d|%s", face, size, outline or DEFAULT_FONT_OUTLINE)
end

local function ResetLayoutState()
    state.orderedControls = {}
    state.lastAnchoredControl = nil
    state.contentWidth = 0
    state.contentHeight = 0
end

local function ClearArray(array)
    if not array then
        return
    end

    for index = #array, 1, -1 do
        array[index] = nil
    end
end

local function ClearTable(tbl)
    if not tbl then
        return
    end

    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function TrackActiveControl(control)
    if not control then
        return
    end

    if control._nvkActive then
        return
    end

    control._nvkActive = true

    local active = state.activeControls
    if not active then
        active = {}
        state.activeControls = active
    end

    active[#active + 1] = control
end

local function BeginStructureRebuild()
    if not state.container then
        if IsDebugLoggingEnabled() then
            DebugLog("REBUILD_ABORT no container")
        end
        return false
    end

    -- Release previously active controls before we start creating or reattaching
    -- new ones. This prevents duplicate global control names from being created
    -- on the next rebuild and is the core fix for the infinite rebuild loop that
    -- was triggered by repeated duplicate-name failures.
    if type(ReleaseActiveControls) == "function" then
        ReleaseActiveControls()
    end

    ResetLayoutState()

    local poolsReady = false
    if type(EnsurePools) == "function" then
        poolsReady = EnsurePools()
    end

    if not poolsReady then
        if IsDebugLoggingEnabled() then
            DebugLog("REBUILD_ABORT pools unavailable")
        end
        return false
    end

    state.categoryControls = {}
    state.questControls = {}
    state.questControlsByKey = {}

    if ReleaseConditionControls then
        ReleaseConditionControls()
    end

    return true
end

local function ReturnCategoryControl(control)
    if not control then
        return
    end

    ResetCategoryControl(control)
    control._nvkActive = nil

    if IsDebugLoggingEnabled() then
        DebugLog("POOL_RETURN category")
    end

    local pool = state.categoryPool
    if not pool then
        state.categoryPool = { control }
    else
        pool[#pool + 1] = control
    end
end

local function ReturnQuestControl(questKey, control)
    if not control then
        return
    end

    ResetQuestControl(control)
    control._nvkActive = nil

    if IsDebugLoggingEnabled() then
        DebugLog(string_format("POOL_RETURN quest key=%s", tostring(questKey)))
    end

    local pool = state.questPool
    if not pool then
        state.questPool = { control }
    else
        pool[#pool + 1] = control
    end
end

ReleaseActiveControls = function()
    -- Return every previously active control to its pool before the next
    -- rebuild. This ensures the upcoming rebuild acquires controls from a clean
    -- slate and avoids duplicate CreateControl* calls with conflicting global
    -- names, which previously triggered the "duplicate control name" error and
    -- the resulting infinite rebuild loop.
    if ReleaseConditionControls then
        ReleaseConditionControls()
    end

    if state.categoryControls then
        for key, control in pairs(state.categoryControls) do
            if control then
                if control.SetHidden then
                    control:SetHidden(true)
                end
                ReturnCategoryControl(control)
            end
            state.categoryControls[key] = nil
        end
    end

    if state.questRows then
        for questKey, row in pairs(state.questRows) do
            if row and row.DetachControl then
                local detached = row:DetachControl()
                if detached then
                    if detached.SetHidden then
                        detached:SetHidden(true)
                    end
                    ReturnQuestControl(questKey, detached)
                end
            end
        end
    end

    if state.questControls then
        ClearTable(state.questControls)
    end

    if state.questControlsByKey then
        ClearTable(state.questControlsByKey)
    end

    local active = state.activeControls
    if active then
        ClearArray(active)
    end
end

local function FinalizeStructureRebuild()
    -- Drop quest row objects that no longer have a visible control after the
    -- rebuild. This mirrors the previous reusable-control cleanup so stale
    -- quests do not keep requesting controls or remain in the registry.
    if state.questRows then
        for questKey, row in pairs(state.questRows) do
            local control = row and row.control
            if not control or not state.questControlsByKey[questKey] then
                if row and row.ClearControl then
                    row:ClearControl()
                end
                if not state.questControlsByKey[questKey] then
                    state.questRows[questKey] = nil
                end
            end
        end
    end
end

local function RequestCategoryControl(category)
    local normalizedKey = category and NormalizeCategoryKey and NormalizeCategoryKey(category.key)
    local control = nil

    if type(AcquireCategoryControlFromPool) == "function" then
        control = AcquireCategoryControlFromPool()
    else
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_ACQUIRE category missing helper")
        end
    end

    if not control then
        return nil
    end

    control.rowType = "category"
    TrackActiveControl(control)

    if normalizedKey then
        state.categoryControls[normalizedKey] = control
    end

    return control
end

local function RequestQuestControl(questKey)
    local control = nil

    if type(AcquireQuestControlFromPool) == "function" then
        control = AcquireQuestControlFromPool()
    else
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_ACQUIRE quest missing helper")
        end
    end

    if not control then
        return nil
    end

    control.rowType = "quest"
    TrackActiveControl(control)

    return control
end

local function AnchorControl(control, indentX)
    indentX = indentX or 0

    if not control then
        return
    end

    control.currentIndent = indentX
    control:ClearAnchors()

    if state.container then
        control:SetAnchor(TOPLEFT, state.container, TOPLEFT, indentX, 0)
        control:SetAnchor(TOPRIGHT, state.container, TOPRIGHT, 0, 0)
    end

    state.lastAnchoredControl = control
    state.orderedControls[#state.orderedControls + 1] = control
end

local function PerformLayoutPass()
    local container = state.container
    if not container then
        state.contentWidth = 0
        state.contentHeight = 0
        state.lastAnchoredControl = nil
        return 0, 0
    end

    local yOffset = 0
    local visibleCount = 0
    local maxWidth = 0
    local lastVisible = nil
    local orderedControls = state.orderedControls
    local verticalPadding = VERTICAL_PADDING

    for index = 1, #orderedControls do
        local control = orderedControls[index]
        if control then
            RefreshControlMetrics(control)

            if not control:IsHidden() then
                local indent = control.currentIndent or 0
                if control.SetParent then
                    control:SetParent(container)
                end
                control:ClearAnchors()
                control:SetAnchor(TOPLEFT, container, TOPLEFT, indent, yOffset)
                control:SetAnchor(TOPRIGHT, container, TOPRIGHT, 0, yOffset)

                local width = (control:GetWidth() or 0) + indent
                if width > maxWidth then
                    maxWidth = width
                end

                local height = control:GetHeight() or 0
                yOffset = yOffset + height
                visibleCount = visibleCount + 1
                lastVisible = control

                if visibleCount > 0 then
                    yOffset = yOffset + verticalPadding
                end
            end
        end
    end

    if visibleCount > 0 then
        yOffset = yOffset - verticalPadding
    else
        yOffset = 0
    end

    state.lastAnchoredControl = lastVisible
    state.contentWidth = maxWidth
    state.contentHeight = math.max(0, yOffset)

    if container.SetHeight then
        container:SetHeight(state.contentHeight)
    end

    if IsDebugLoggingEnabled() then
        DebugLog(string_format(
            "LAYOUT_QUEST rows=%d height=%.2f",
            visibleCount,
            state.contentHeight or 0
        ))
    end

    return visibleCount, state.contentHeight
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
    if state.saved and state.saved.defaults and state.saved.defaults.categoryExpanded ~= nil then
        return state.saved.defaults.categoryExpanded and true or false
    end

    return state.opts.autoExpand ~= false
end

local function GetDefaultQuestExpanded()
    if state.saved and state.saved.defaults and state.saved.defaults.questExpanded ~= nil then
        return state.saved.defaults.questExpanded and true or false
    end

    return state.opts.autoExpand ~= false
end

local function IsCategoryExpanded(categoryKey)
    local key = NormalizeCategoryKey(categoryKey)
    if not key then
        return GetDefaultCategoryExpanded()
    end

    if state.saved and state.saved.cat then
        local entry = state.saved.cat[key]
        if entry and entry.expanded ~= nil then
            return entry.expanded and true or false
        end
    end

    return GetDefaultCategoryExpanded()
end

IsQuestExpanded = function(journalIndex)
    local key = NormalizeQuestKey(journalIndex)
    if not key then
        return GetDefaultQuestExpanded()
    end

    if state.saved and state.saved.quest then
        local entry = state.saved.quest[key]
        if entry and entry.expanded ~= nil then
            return entry.expanded and true or false
        end
    end

    return GetDefaultQuestExpanded()
end

SetCategoryExpanded = function(categoryKey, expanded, context)
    if not state.saved then
        EnsureSavedVars()
    end

    local key = NormalizeCategoryKey(categoryKey)
    if not key then
        return false
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

    local changed = WriteCategoryState(key, expanded, stateSource, writeOptions)
    if not changed then
        return false
    end

    DebugDeselect("SetCategoryExpanded", {
        categoryKey = key,
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

    QueueQuestStructureUpdate({
        reason = "QuestTracker:SetCategoryExpanded",
        trigger = context and context.trigger,
        source = context and context.source,
    })

    return true
end

SetQuestExpanded = function(journalIndex, expanded, context)
    if not state.saved then
        EnsureSavedVars()
    end

    local key = NormalizeQuestKey(journalIndex)
    if not key then
        return false
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

    local changed = WriteQuestState(key, expanded, stateSource, writeOptions)
    if not changed then
        return false
    end

    DebugDeselect("SetQuestExpanded", {
        journalIndex = key,
        previous = tostring(beforeExpanded),
        newValue = tostring(expanded),
    })

    local numericIndex = QuestKeyToJournalIndex(key) or key

    LogQuestExpansion(
        expanded and "expand" or "collapse",
        (context and context.trigger) or "unknown",
        numericIndex,
        beforeExpanded,
        expanded,
        (context and context.source) or "QuestTracker:SetQuestExpanded"
    )

    QueueQuestStructureUpdate({
        reason = "QuestTracker:SetQuestExpanded",
        trigger = context and context.trigger,
        source = context and context.source,
    })

    return true
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
    if changed then
        QueueQuestStructureUpdate({
            reason = "QuestTracker:ToggleQuestExpansion",
            trigger = toggleContext.trigger,
            source = toggleContext.source,
        })
    end

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
        text = string_format("* %s", text)
    end

    if zo_strformat then
        return zo_strformat("<<1>>", text)
    end

    return text
end

local function AcquireCategoryControlInternal(forceReset)
    local ensured = false
    if type(EnsurePools) == "function" then
        if forceReset then
            ensured = EnsurePools(true)
        else
            ensured = EnsurePools()
        end
    end
    if not ensured then
        return nil
    end

    local pool = state.categoryPool
    local control = nil

    if pool and #pool > 0 then
        control = pool[#pool]
        pool[#pool] = nil
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_TAKE category")
        end
        if control.SetParent then
            control:SetParent(state.container)
        end
    end

    if not control then
        if not (WINDOW_MANAGER and WINDOW_MANAGER.CreateControlFromVirtual) then
            return nil
        end
        local name = GenerateControlName("CategoryHeader")
        control = WINDOW_MANAGER:CreateControlFromVirtual(name, state.container, "CategoryHeader_Template")
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_CREATE category")
        end
    end

    if not control then
        return nil
    end

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
            local changed = SetCategoryExpanded(catKey, expanded, {
                trigger = "click",
                source = "QuestTracker:OnCategoryClick",
            })
            if changed then
                QuestTracker.Refresh()
            end
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

    ResetCategoryControl(control)
    control.rowType = "category"
    ApplyLabelDefaults(control.label)
    ApplyToggleDefaults(control.toggle)
    ApplyFont(control.label, state.fonts.category, DEFAULT_FONTS.category)
    ApplyFont(control.toggle, state.fonts.toggle, DEFAULT_FONTS.toggle)
    return control
end

AcquireCategoryControlFromPool = function()
    local control = AcquireCategoryControlInternal(false)

    if not control then
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_RECOVER category start")
        end
        control = AcquireCategoryControlInternal(true)
        if control and IsDebugLoggingEnabled() then
            DebugLog("POOL_RECOVER category success")
        elseif not control and IsDebugLoggingEnabled() then
            DebugLog("POOL_RECOVER category failed")
        end
    end

    if not control and IsDebugLoggingEnabled() then
        DebugLog("POOL_MISSING category")
    end

    return control
end

local function AcquireQuestControlInternal(forceReset)
    local ensured = false
    if type(EnsurePools) == "function" then
        if forceReset then
            ensured = EnsurePools(true)
        else
            ensured = EnsurePools()
        end
    end
    if not ensured then
        return nil
    end

    local pool = state.questPool
    local control = nil

    if pool and #pool > 0 then
        control = pool[#pool]
        pool[#pool] = nil
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_TAKE quest")
        end
        if control.SetParent then
            control:SetParent(state.container)
        end
    end

    if not control then
        if not (WINDOW_MANAGER and WINDOW_MANAGER.CreateControlFromVirtual) then
            return nil
        end
        local name = GenerateControlName("QuestHeader")
        control = WINDOW_MANAGER:CreateControlFromVirtual(name, state.container, "QuestHeader_Template")
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_CREATE quest")
        end
    end

    if not control then
        return nil
    end

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
                if not questData or not questData.journalIndex then
                    return
                end
                ToggleQuestExpansion(questData.journalIndex, {
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

    ResetQuestControl(control)
    control.rowType = "quest"
    ApplyLabelDefaults(control.label)
    ApplyFont(control.label, state.fonts.quest, DEFAULT_FONTS.quest)
    return control
end

AcquireQuestControlFromPool = function()
    local control = AcquireQuestControlInternal(false)

    if not control then
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_RECOVER quest start")
        end
        control = AcquireQuestControlInternal(true)
        if control and IsDebugLoggingEnabled() then
            DebugLog("POOL_RECOVER quest success")
        elseif not control and IsDebugLoggingEnabled() then
            DebugLog("POOL_RECOVER quest failed")
        end
    end

    if not control and IsDebugLoggingEnabled() then
        DebugLog("POOL_MISSING quest")
    end

    return control
end


local function AcquireConditionControl()
    if type(EnsurePools) ~= "function" or not EnsurePools() then
        return nil
    end

    local pool = state.conditionPool
    if not pool then
        return nil
    end

    local control = nil
    if #pool > 0 then
        control = pool[#pool]
        pool[#pool] = nil
        if control.SetParent then
            control:SetParent(state.container)
        end
    end

    if not control then
        if not (WINDOW_MANAGER and WINDOW_MANAGER.CreateControlFromVirtual) then
            return nil
        end
        local name = GenerateControlName("QuestCondition")
        control = WINDOW_MANAGER:CreateControlFromVirtual(name, state.container, "QuestCondition_Template")
    end

    if not control then
        return nil
    end

    if not control.initialized then
        control.label = control:GetNamedChild("Label")
        control.initialized = true
    end

    ResetConditionControl(control)
    control.rowType = "condition"
    ApplyLabelDefaults(control.label)
    ApplyFont(control.label, state.fonts.condition, DEFAULT_FONTS.condition)

    local active = state.conditionActiveControls
    active[#active + 1] = control

    return control
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

local function ResetBaseControl(control)
    if not control then
        return
    end

    if control.SetHidden then
        control:SetHidden(true)
    end
    if control.data then
        ClearTable(control.data)
    end
    control.currentIndent = nil
    control.baseColor = nil
    control.isExpanded = nil
    control._nvkActive = nil
end

-- Assign the forward-declared reset helpers after all dependencies are in
-- scope so earlier pooling helpers (like AcquireCategoryControlInternal)
-- always invoke a real function instead of hitting a nil placeholder.
ResetCategoryControl = function(control)
    ResetBaseControl(control)
    local toggle = control and control.toggle
    if toggle then
        if toggle.SetTexture then
            toggle:SetTexture(SelectCategoryToggleTexture(false, false))
        end
        if toggle.SetHidden then
            toggle:SetHidden(false)
        end
    end
end

ResetQuestControl = function(control)
    ResetBaseControl(control)
    if control and control.label and control.label.SetText then
        control.label:SetText("")
    end
    local iconSlot = control and control.iconSlot
    if iconSlot then
        if iconSlot.SetTexture then
            iconSlot:SetTexture(nil)
        end
        if iconSlot.SetAlpha then
            iconSlot:SetAlpha(0)
        end
        if iconSlot.SetHidden then
            iconSlot:SetHidden(false)
        end
    end
end

ResetConditionControl = function(control)
    ResetBaseControl(control)
    if control and control.label and control.label.SetText then
        control.label:SetText("")
    end
end

ReleaseConditionControls = function()
    local active = state.conditionActiveControls
    if not active then
        return
    end

    local pool = state.conditionPool
    if not pool then
        pool = {}
        state.conditionPool = pool
    end

    for index = #active, 1, -1 do
        local control = active[index]
        if control then
            ResetConditionControl(control)
            pool[#pool + 1] = control
        end
        active[index] = nil
    end
end

EnsurePools = function(forceReset)
    if not (state.container and WINDOW_MANAGER and WINDOW_MANAGER.CreateControlFromVirtual) then
        return false
    end

    state.conditionActiveControls = state.conditionActiveControls or {}

    if forceReset then
        ReleaseConditionControls()

        if state.categoryPool then
            for index = 1, #state.categoryPool do
                ResetCategoryControl(state.categoryPool[index])
            end
        end

        if state.questPool then
            for index = 1, #state.questPool do
                ResetQuestControl(state.questPool[index])
            end
        end

        if state.conditionPool then
            for index = 1, #state.conditionPool do
                ResetConditionControl(state.conditionPool[index])
            end
        end
    end

    state.categoryPool = state.categoryPool or {}
    state.questPool = state.questPool or {}
    state.conditionPool = state.conditionPool or {}

    return true
end

local function LayoutCondition(condition)
    if not ShouldDisplayCondition(condition) then
        return
    end

    local control = AcquireConditionControl()
    if not control then
        if IsDebugLoggingEnabled() then
            DebugLog("LAYOUT condition missing control")
        end
        QueueQuestStructureUpdate({ reason = "QuestTracker.LayoutConditionMissingControl", trigger = "pool" })
        return
    end
    local data = control.data
    if data then
        data.condition = condition
        data.quest = nil
        data.categoryKey = nil
        data.parentKey = nil
    else
        data = { condition = condition }
        control.data = data
    end
    control.label:SetText(FormatConditionText(condition))
    if control.label then
        local r, g, b, a = GetQuestTrackerColor("objectiveText")
        control.label:SetColor(r, g, b, a)
    end
    TrackActiveControl(control)
    ApplyRowMetrics(control, CONDITION_INDENT_X, 0, 0, 0, CONDITION_MIN_HEIGHT)
    control:SetHidden(false)
    AnchorControl(control, CONDITION_INDENT_X)
    ConsumeStructureBudget(1)

    if ShouldAbortRebuild() then
        return
    end
end

local function ApplyQuestRowVisuals(control, quest)
    if not (control and quest) then
        return
    end

    local data = control.data
    if data then
        data.quest = quest
        data.condition = nil
        data.categoryKey = nil
        data.parentKey = nil
    else
        data = { quest = quest }
        control.data = data
    end

    local questName = quest and quest.name
    if (questName == nil or questName == "") and quest and quest.journalIndex then
        -- When the snapshot unexpectedly lacks the quest title we recover by
        -- querying the live journal.  The pooling refactor keeps row controls
        -- alive across rebuilds, so we must always be prepared to repaint the
        -- header text from authoritative game APIs instead of leaving it
        -- blank.
        if GetJournalQuestName then
            local ok, fallback = SafeCall(GetJournalQuestName, quest.journalIndex)
            if ok and type(fallback) == "string" and fallback ~= "" then
                questName = fallback
            end
        end

        -- Some ESO builds return the name only via GetJournalQuestInfo for a
        -- brief period during login.  Querying that path as a secondary
        -- fallback keeps the tracker populated even when the lightweight
        -- GetJournalQuestName helper is still empty.
        if (questName == nil or questName == "") and GetJournalQuestInfo then
            local ok, infoName = SafeCall(function(index)
                local name = GetJournalQuestInfo(index)
                return name
            end, quest.journalIndex)
            if ok and type(infoName) == "string" and infoName ~= "" then
                questName = infoName
            end
        end
    end

    if type(questName) == "string" and questName ~= "" then
        if zo_strformat then
            questName = zo_strformat("<<1>>", questName)
        end
        -- Persist the resolved title on the quest payload so subsequent row
        -- refreshes (for example after pooling hand-offs) no longer have to
        -- perform the journal lookups again.
        if quest then
            quest.name = questName
        end
    end

    if control.label and control.label.SetText then
        control.label:SetText(questName or "")
    end

    local colorRole = DetermineQuestColorRole(quest)
    local r, g, b, a = GetQuestTrackerColor(colorRole)
    ApplyBaseColor(control, r, g, b, a)

    UpdateQuestIconSlot(control)

    ApplyRowMetrics(
        control,
        QUEST_INDENT_X,
        QUEST_ICON_SLOT_WIDTH,
        QUEST_ICON_SLOT_PADDING_X,
        0,
        QUEST_MIN_HEIGHT
    )
end

local function LayoutQuest(quest)
    local questKey = NormalizeQuestKey(quest.journalIndex)
    local control = RequestQuestControl(questKey)
    if not control then
        if state.questPool then
            if IsDebugLoggingEnabled() then
                DebugLog("LAYOUT quest missing control", tostring(questKey))
            end
            QueueQuestStructureUpdate({ reason = "QuestTracker.LayoutQuestMissingControl", trigger = "pool" })
        elseif IsDebugLoggingEnabled() then
            DebugLog("LAYOUT quest missing pool", tostring(questKey))
        end
        return
    end
    local expanded = IsQuestExpanded(quest.journalIndex)
    if IsDebugLoggingEnabled() then
        DebugLog(string_format(
            "BUILD_APPLY quest=%s expanded=%s",
            tostring(questKey or quest.journalIndex),
            tostring(expanded)
        ))
    end

    local row
    if questKey then
        row = state.questRows[questKey]
        if not row then
            row = QuestTrackerRow:New({
                questKey = questKey,
            })
            state.questRows[questKey] = row
        end
        row:SetControl(control)
        row:Refresh(quest)
    else
        ApplyQuestRowVisuals(control, quest)
    end

    control:SetHidden(false)
    AnchorControl(control, QUEST_INDENT_X)
    ConsumeStructureBudget(1)

    if ShouldAbortRebuild() then
        return
    end

    if quest and quest.journalIndex then
        state.questControls[quest.journalIndex] = control
    end

    if questKey then
        state.questControlsByKey[questKey] = control
    end

    if expanded and type(quest.steps) == "table" then
        for stepIndex = 1, #quest.steps do
            local step = quest.steps[stepIndex]
            if step and step.isVisible ~= false then
                local conditions = step.conditions
                if type(conditions) == "table" then
                    for conditionIndex = 1, #conditions do
                        local condition = conditions[conditionIndex]
                        if condition then
                            LayoutCondition(condition)
                            if ShouldAbortRebuild() then
                                return
                            end
                        end
                    end
                end
            end
        end
    end
end

local function LayoutCategory(category)
    local control = RequestCategoryControl(category)
    if not control then
        if state.categoryPool then
            if IsDebugLoggingEnabled() then
                DebugLog("LAYOUT category missing control", tostring(category and category.key))
            end
            QueueQuestStructureUpdate({ reason = "QuestTracker.LayoutCategoryMissingControl", trigger = "pool" })
        elseif IsDebugLoggingEnabled() then
            DebugLog("LAYOUT category missing pool")
        end
        return
    end
    local data = control.data
    if not data then
        data = {}
        control.data = data
    end
    data.categoryKey = category.key
    data.parentKey = category.parent and category.parent.key or nil
    data.parentName = category.parent and category.parent.name or nil
    data.groupKey = category.groupKey
    data.groupName = category.groupName
    data.categoryType = category.type
    data.groupOrder = category.groupOrder
    local normalizedKey = NormalizeCategoryKey(category.key)
    if normalizedKey then
        state.categoryControls[normalizedKey] = control
    end
    local quests = type(category.quests) == "table" and category.quests or EMPTY_TABLE
    local count = #quests
    control.label:SetText(FormatCategoryHeaderText(category.name or "", count, "quest"))
    local expanded = IsCategoryExpanded(category.key)
    if IsDebugLoggingEnabled() then
        DebugLog(string_format(
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
    ConsumeStructureBudget(1)

    if ShouldAbortRebuild() then
        return
    end

    if expanded and count > 0 then
        for index = 1, count do
            LayoutQuest(quests[index])
            if ShouldAbortRebuild() then
                return
            end
        end
    end
end

local function RelayoutFromCategoryIndex(_)
    Rebuild()
end

local function ApplySnapshot(snapshot, context)
    state.snapshot = snapshot

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

local function OnSnapshotUpdated(snapshot)
    state.snapshot = snapshot

    if not state.isInitialized then
        return
    end

    QueueQuestStructureUpdate({
        reason = "QuestTracker:OnSnapshotUpdated",
        trigger = "snapshot",
    })
end

local function SubscribeToModel()
    if state.subscription or not Nvk3UT.QuestModel or not Nvk3UT.QuestModel.Subscribe then
        return
    end

    state.subscription = function(snapshot)
        OnSnapshotUpdated(snapshot)
    end

    Nvk3UT.QuestModel.Subscribe(state.subscription)
end

local function UnsubscribeFromModel()
    if not state.subscription then
        return
    end

    if Nvk3UT.QuestModel and Nvk3UT.QuestModel.Unsubscribe then
        Nvk3UT.QuestModel.Unsubscribe(state.subscription)
    end

    state.subscription = nil
end


local function ExecuteRebuild()
    if not state.container then
        return
    end

    if IsDebugLoggingEnabled() then
        DebugLog("REBUILD_START")
    end

    ApplyActiveQuestFromSaved()
    local rebuildReady = BeginStructureRebuild()

    if not rebuildReady then
        state.lastStructureFailure = "pools"
        if IsDebugLoggingEnabled() then
            DebugLog("REBUILD_DEFER prerequisites unavailable")
        end
        return false
    end

    state.lastStructureFailure = nil

    if not state.snapshot or not state.snapshot.categories or not state.snapshot.categories.ordered then
        FinalizeStructureRebuild()
        NotifyHostContentChanged()
        if IsDebugLoggingEnabled() then
            DebugLog("REBUILD_END")
        end
        return false
    end

    PrimeInitialSavedState()

    for index = 1, #state.snapshot.categories.ordered do
        local category = state.snapshot.categories.ordered[index]
        if category and category.quests and #category.quests > 0 then
            LayoutCategory(category)
            if ShouldAbortRebuild() then
                break
            end
        end
    end

    local builtRowCount = #state.orderedControls

    FinalizeStructureRebuild()
    NotifyHostContentChanged()
    ProcessPendingExternalReveal()

    if builtRowCount == 0 then
        -- It is valid for a rebuild to produce zero visible rows (for example
        -- when the player has no active quests).  Previously this scenario was
        -- treated as an implicit failure which bubbled up as REBUILD_ERROR and
        -- left the tracker empty forever.  Instead we explicitly short-circuit
        -- here, reset the layout metrics, and let the coordinator show an empty
        -- tracker without throwing.
        state.contentWidth = 0
        state.contentHeight = 0
        state.lastAnchoredControl = nil
        if state.container and state.container.SetHeight then
            state.container:SetHeight(0)
        end
        if IsDebugLoggingEnabled() then
            DebugLog("REBUILD_END rows=0")
        end
        return true
    end

    if state.pendingAdoptOnInit then
        -- Only adopt the tracked quest once rows exist.  When the tracker is
        -- empty we leave the flag set so the next successful rebuild can
        -- perform the adoption instead of spinning in place.
        state.pendingAdoptOnInit = false
        AdoptTrackedQuestOnInit()
    end

    if IsDebugLoggingEnabled() then
        DebugLog(string_format("REBUILD_END rows=%d", builtRowCount))
    end

    return true
end

local function Rebuild()
    if state.isRebuildInProgress then
        -- Guard against nested rebuild attempts so that one failing iteration
        -- does not schedule another rebuild on top of itself. The previous
        -- implementation re-entered endlessly when LibAsync restarted the job
        -- after a duplicate-name failure.
        if IsDebugLoggingEnabled() then
            DebugLog("REBUILD_SKIP reentry")
        end
        return false
    end

    state.isRebuildInProgress = true

    local ok, result = pcall(ExecuteRebuild)

    state.isRebuildInProgress = false

    if not ok then
        -- Propagate the failure to the caller without re-raising the Lua error.
        -- The previous behaviour rethrew here which produced REBUILD_ERROR
        -- spam and prevented the async job from ever settling.
        if IsDebugLoggingEnabled() then
            DebugLog("REBUILD_ERROR", tostring(result))
        end
        state.lastStructureFailure = "error"
        return false
    end

    return result == true
end

local function RunQuestRebuildSynchronously(reason)
    local job = GetQuestRebuildJob()
    job.totalProcessed = 0
    job.reason = reason or job.reason or "questStructure"
    job.restartRequested = false
    job.active = false
    job.async = nil

    if IsDebugLoggingEnabled() then
        DebugLog(string_format("REBUILD_SYNC reason=%s", tostring(job.reason or "")))
    end

    local ok, err = pcall(Rebuild)
    if not ok then
        state.isRebuildInProgress = false
        if IsDebugLoggingEnabled() then
            DebugLog("REBUILD_ERROR", tostring(err))
        end
    end

    QueueLayoutUpdate({
        reason = "QuestTracker.StructureComplete",
        trigger = "structureComplete",
    })

    return ok == true
end

local function StartQuestRebuildJob(reason)
    local job = GetQuestRebuildJob()
    job.batchSize = STRUCTURE_REBUILD_BATCH_SIZE
    job.reason = reason or job.reason or "questStructure"
    job.restartRequested = false

    if job.active then
        job.restartRequested = true
        if IsDebugLoggingEnabled() then
            DebugLog(string_format("REBUILD_RESTART reason=%s", tostring(job.reason or "")))
        end
        return true
    end

    if not Async or not Async.Create then
        return RunQuestRebuildSynchronously(job.reason)
    end

    local asyncTask = Async:Create(QUEST_REBUILD_TASK_NAME)
    if not asyncTask then
        return RunQuestRebuildSynchronously(job.reason)
    end

    job.async = asyncTask
    job.active = true
    job.restartRequested = false
    job.totalProcessed = 0

    if IsDebugLoggingEnabled() then
        DebugLog(string_format("REBUILD_ASYNC_START reason=%s", tostring(job.reason or "")))
    end

    asyncTask:Then(function(task)
        repeat
            job.restartRequested = false
            job.totalProcessed = 0

            state.activeRebuildContext = {
                task = task,
                batchSize = job.batchSize or STRUCTURE_REBUILD_BATCH_SIZE,
                pending = 0,
                total = 0,
                batches = 0,
                onBatchReady = function(context)
                    if IsDebugLoggingEnabled() then
                        DebugLog(string_format(
                            "REBUILD_BATCH quest batches=%d total=%d reason=%s",
                            context.batches or 0,
                            context.total or 0,
                            tostring(job.reason or "")
                        ))
                    end
                    QueueLayoutUpdate({
                        reason = "QuestTracker.StructureBatch",
                        trigger = "structureBatch",
                    })
                end,
            }

            local ok, err = pcall(Rebuild)
            if not ok then
                state.isRebuildInProgress = false
                if IsDebugLoggingEnabled() then
                    DebugLog("REBUILD_ERROR", tostring(err))
                end
            end

            ClearActiveRebuildContext()

            if IsDebugLoggingEnabled() then
                DebugLog(string_format(
                    "REBUILD_ITERATION_COMPLETE rows=%d restart=%s reason=%s",
                    job.totalProcessed or 0,
                    tostring(job.restartRequested),
                    tostring(job.reason or "")
                ))
            end

            QueueLayoutUpdate({
                reason = "QuestTracker.StructureIteration",
                trigger = "structure",
            })
        until not job.restartRequested
    end)
    :Then(function()
        if IsDebugLoggingEnabled() then
            DebugLog("REBUILD_ASYNC_DONE")
        end
        QueueLayoutUpdate({
            reason = "QuestTracker.StructureComplete",
            trigger = "structureComplete",
        })
    end)
    :Finally(function()
        ClearActiveRebuildContext()
        job.active = false
        job.async = nil

        if job.restartRequested then
            local restartReason = job.reason or "questStructure"
            job.restartRequested = false
            StartQuestRebuildJob(restartReason)
        end
    end)
    :Start()

    return true
end

local function RefreshVisibility()
    if not state.control then
        return
    end

    local hidden = false

    if state.opts.active == false then
        hidden = true
    elseif state.opts.hideInCombat then
        hidden = state.combatHidden
    end

    state.control:SetHidden(hidden)
    NotifyHostContentChanged()
end

local function OnCombatState(_, inCombat)
    state.combatHidden = inCombat
    QueueLayoutUpdate({ reason = "QuestTracker.OnCombatState", trigger = "combat" })
end

local function RegisterCombatEvents()
    if not state.opts.hideInCombat then
        return
    end

    EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE .. "Combat", EVENT_PLAYER_COMBAT_STATE, OnCombatState)
    state.combatHidden = IsUnitInCombat and IsUnitInCombat("player") or false
    QueueLayoutUpdate({ reason = "QuestTracker.RegisterCombatEvents", trigger = "combat" })
end

local function UnregisterCombatEvents()
    EVENT_MANAGER:UnregisterForEvent(EVENT_NAMESPACE .. "Combat", EVENT_PLAYER_COMBAT_STATE)
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
    state.opts = {}
    state.fonts = {}
    state.pendingSelection = nil
    state.lastTrackedBeforeSync = nil
    state.syncingTrackedState = false
    state.pendingDeselection = false
    state.pendingExternalReveal = nil
    state.rebuildJob = nil
    ClearActiveRebuildContext()

    QuestTracker.ApplyTheme(state.saved or {})
    QuestTracker.ApplySettings(state.saved or {})

    if opts then
        QuestTracker.ApplyTheme(opts)
        QuestTracker.ApplySettings(opts)
    end

    if state.opts.hideInCombat then
        RegisterCombatEvents()
    else
        UnregisterCombatEvents()
    end

    RegisterTrackingEvents()
    SubscribeToModel()

    if Nvk3UT.QuestModel and Nvk3UT.QuestModel.GetSnapshot then
        state.snapshot = Nvk3UT.QuestModel.GetSnapshot() or state.snapshot
    end

    state.isInitialized = true

    QueueLayoutUpdate({ reason = "QuestTracker.Init", trigger = "init" })
    QueueQuestStructureUpdate({ reason = "QuestTracker.Init", trigger = "init" })

    state.pendingAdoptOnInit = true

    local host = Nvk3UT and Nvk3UT.TrackerHost
    if host and host.ProcessTrackerUpdates then
        host.ProcessTrackerUpdates()
    end
end

-- Returns the registered QuestTrackerRow instance for the given quest journal
-- index or normalized quest key. This allows callers to fetch a stable row
-- object and refresh it without rebuilding the entire tracker.
function QuestTracker.GetQuestRow(questId)
    local questKey = NormalizeQuestKey(questId)
    if not questKey then
        return nil
    end

    return state.questRows[questKey]
end

function QuestTracker.Refresh(context)
    if not state.isInitialized then
        return
    end

    QueueQuestStructureUpdate(context or { reason = "QuestTracker.Refresh", trigger = "refresh" })
end

function QuestTracker.ProcessStructureUpdate(context)
    if not state.isInitialized then
        return false
    end

    if Nvk3UT.QuestModel and Nvk3UT.QuestModel.GetSnapshot then
        state.snapshot = Nvk3UT.QuestModel.GetSnapshot() or state.snapshot
    end

    ApplySnapshot(state.snapshot, {
        trigger = "refresh",
        source = "QuestTracker.ProcessStructureUpdate",
    })

    local job = GetQuestRebuildJob()
    local reason
    if type(context) == "table" then
        reason = context.reason or context.trigger
    elseif type(context) == "string" then
        reason = context
    end
    job.reason = reason or job.reason or "QuestTracker.ProcessStructureUpdate"

    if job.active then
        job.restartRequested = true
        if IsDebugLoggingEnabled() then
            DebugLog(string_format(
                "REBUILD_RESTART_REQUEST reason=%s",
                tostring(job.reason or "")
            ))
        end
        return true
    end

    local started = StartQuestRebuildJob(job.reason)
    return started == true
end

function QuestTracker.RunLayoutPass()
    return PerformLayoutPass()
end

function QuestTracker.ProcessLayoutUpdate()
    RefreshVisibility()
end

function QuestTracker.Shutdown()
    if not state.isInitialized then
        return
    end

    if state.rebuildJob then
        local job = state.rebuildJob
        if job.async and job.async.Cancel then
            pcall(job.async.Cancel, job.async)
        end
        state.rebuildJob = nil
    end
    ClearActiveRebuildContext()

    if type(ReleaseActiveControls) == "function" then
        ReleaseActiveControls()
    end

    UnregisterCombatEvents()
    UnregisterTrackingEvents()
    UnsubscribeFromModel()

    if state.categoryPool then
        for index = 1, #state.categoryPool do
            ResetCategoryControl(state.categoryPool[index])
        end
        state.categoryPool = nil
    end

    if state.questPool then
        for index = 1, #state.questPool do
            ResetQuestControl(state.questPool[index])
        end
        state.questPool = nil
    end

    ReleaseConditionControls()
    state.conditionPool = nil
    state.conditionActiveControls = {}

    state.container = nil
    state.control = nil
    state.snapshot = nil
    state.orderedControls = {}
    state.lastAnchoredControl = nil
    state.categoryControls = {}
    state.questControls = {}
    state.questControlsByKey = {}
    state.questRows = {}
    state.activeControls = {}
    state.controlNameCounters = {}
    state.isInitialized = false
    state.opts = {}
    state.fonts = {}
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
    state.pendingAdoptOnInit = false
    NotifyHostContentChanged()
end

function QuestTracker.SetActive(active)
    state.opts.active = active
    QueueLayoutUpdate({ reason = "QuestTracker.SetActive", trigger = "setting" })
    NotifyStatusRefresh()
end

function QuestTracker.ApplySettings(settings)
    if type(settings) ~= "table" then
        return
    end

    state.opts.hideInCombat = settings.hideInCombat and true or false
    state.opts.autoExpand = settings.autoExpand ~= false
    state.opts.autoTrack = settings.autoTrack ~= false
    state.opts.active = (settings.active ~= false)

    if state.isInitialized then
        if state.opts.hideInCombat then
            RegisterCombatEvents()
        else
            UnregisterCombatEvents()
            state.combatHidden = false
        end
    end

    QueueLayoutUpdate({ reason = "QuestTracker.ApplySettings", trigger = "setting" })
    QueueQuestStructureUpdate({ reason = "QuestTracker.ApplySettings", trigger = "setting" })
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

    QueueQuestStructureUpdate({ reason = "QuestTracker.ApplyTheme", trigger = "theme" })
end

function QuestTracker.IsActive()
    return state.opts.active ~= false
end

function QuestTracker.RequestRefresh()
    RequestRefresh()
end

function QuestTracker.IsStructureRebuildActive()
    local job = state.rebuildJob
    if job and job.active then
        return true
    end

    return state.isRebuildInProgress == true
end

function QuestTracker.GetContentSize()
    return state.contentWidth or 0, state.contentHeight or 0
end

Nvk3UT.QuestTracker = QuestTracker

return QuestTracker
