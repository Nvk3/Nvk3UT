local addonName = "Nvk3UT"
-- DEVNOTES: Legacy quest tracker logic and legacy event handlers removed; LocalQuestDB pipeline is the only supported path.

Nvk3UT = Nvk3UT or {}
Nvk3UT_QuestTracker = Nvk3UT_QuestTracker or {}
Nvk3UT_QuestTracker.questNodesByIndex = Nvk3UT_QuestTracker.questNodesByIndex or {}
Nvk3UT_QuestTracker.categoriesByKey = Nvk3UT_QuestTracker.categoriesByKey or {}
Nvk3UT_QuestTracker.categoriesDisplayOrder = Nvk3UT_QuestTracker.categoriesDisplayOrder or {}

local QuestTracker = Nvk3UT.QuestTracker or {}
QuestTracker.__index = QuestTracker
QuestTracker.questNodesByIndex = Nvk3UT_QuestTracker.questNodesByIndex
QuestTracker.categoriesByKey = Nvk3UT_QuestTracker.categoriesByKey
QuestTracker.categoriesDisplayOrder = Nvk3UT_QuestTracker.categoriesDisplayOrder

local MODULE_NAME = addonName .. "QuestTracker"
local EVENT_NAMESPACE = MODULE_NAME .. "_Event"

local Utils = Nvk3UT and Nvk3UT.Utils
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
local OBJECTIVE_TOP_PADDING = 2

local CATEGORY_MIN_HEIGHT = 26
local QUEST_MIN_HEIGHT = 24
local CONDITION_MIN_HEIGHT = 20
local ROW_TEXT_PADDING_Y = 8
local TOGGLE_LABEL_PADDING_X = 4
local CATEGORY_TOGGLE_WIDTH = 20
local CATEGORY_HEADER_TO_QUEST_PADDING = 6
local QUEST_VERTICAL_SPACING = VERTICAL_PADDING
local CATEGORY_VERTICAL_SPACING = VERTICAL_PADDING

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
local RelayoutFromCategoryIndex -- forward declaration for category relayout helper
local SafeCall -- forward declaration for safe wrapper utility
local UpdateQuestControlHeight -- forward declaration for quest row sizing helper

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
    combatHidden = false,
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
}

local STATE_VERSION = 1

local questNodesByIndex = QuestTracker.questNodesByIndex or {}
QuestTracker.questNodesByIndex = questNodesByIndex
Nvk3UT_QuestTracker.questNodesByIndex = questNodesByIndex

local categoriesByKey = QuestTracker.categoriesByKey or {}
QuestTracker.categoriesByKey = categoriesByKey
Nvk3UT_QuestTracker.categoriesByKey = categoriesByKey

local categoriesDisplayOrder = QuestTracker.categoriesDisplayOrder or {}
QuestTracker.categoriesDisplayOrder = categoriesDisplayOrder
Nvk3UT_QuestTracker.categoriesDisplayOrder = categoriesDisplayOrder

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
    -- Debug action emission disabled to avoid noisy chat spam.
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

local DEFAULT_CATEGORY_KEY = "__nvk3ut_misc__"

local function BuildQuestConditionsFromRecord(record)
    local conditions = {}

    if record and type(record.objectives) == "table" then
        for index = 1, #record.objectives do
            local objective = record.objectives[index]
            local displayText = objective and objective.displayText
            if type(displayText) ~= "string" or displayText == "" then
                displayText = objective and objective.text
            end
            if type(displayText) == "string" and displayText ~= "" then
                conditions[#conditions + 1] = {
                    text = displayText,
                    displayText = displayText,
                    current = objective.current,
                    max = objective.max,
                    isVisible = true,
                    isComplete = objective.complete == true and objective.isTurnIn ~= true,
                    isFailCondition = false,
                    isTurnIn = objective.isTurnIn == true,
                    forceDisplay = objective.isTurnIn == true or objective.complete ~= true,
                }
            end
        end
    end

    return conditions
end

local function BuildQuestEntryFromRecord(record)
    if not record then
        return nil
    end

    local conditions = BuildQuestConditionsFromRecord(record)
    local steps = {}
    steps[1] = {
        isVisible = true,
        conditions = conditions,
    }

    local flags = {
        tracked = record.tracked == true,
        assisted = record.assisted == true,
    }

    return {
        journalIndex = record.journalIndex,
        name = record.name,
        headerText = record.headerText,
        objectives = record.objectives,
        steps = steps,
        flags = flags,
        isComplete = record.isComplete == true,
        categoryKey = record.categoryKey,
        categoryName = record.categoryName,
        parentKey = record.parentKey,
        parentName = record.parentName,
        lastUpdateMs = record.lastUpdateMs,
    }
end

local DEFAULT_CATEGORY_NAME = "Miscellaneous"

local function ResolveCategoryFallbackName(record)
    if record and type(record.categoryName) == "string" and record.categoryName ~= "" then
        return record.categoryName
    end

    if record and type(record.categoryKey) == "string" and record.categoryKey ~= "" then
        local readable = record.categoryKey:gsub("_", " ")
        readable = readable:gsub("%s+", " ")
        if type(zo_strformat) == "function" then
            return zo_strformat("<<1>>", readable)
        end
        return readable
    end

    return DEFAULT_CATEGORY_NAME
end

local function BuildLocalSnapshot()
    local snapshot = { categories = { ordered = {}, byKey = {} } }

    local questSource = LocalQuestDB and LocalQuestDB.quests
    if type(questSource) ~= "table" then
        return snapshot
    end

    local categoriesByKey = {}
    for journalIndex, record in pairs(questSource) do
        local questEntry = BuildQuestEntryFromRecord(record)
        if questEntry then
            local categoryKey = NormalizeCategoryKey(record.categoryKey) or DEFAULT_CATEGORY_KEY
            local category = categoriesByKey[categoryKey]
            if not category then
                local parentKey = NormalizeCategoryKey(record.parentKey)
                local parentName = record.parentName
                local categoryName = ResolveCategoryFallbackName(record)
                category = {
                    key = categoryKey,
                    name = categoryName,
                    quests = {},
                    groupKey = parentKey,
                    groupName = parentName,
                    type = nil,
                    groupOrder = nil,
                }
                if parentKey and parentName then
                    category.parent = {
                        key = parentKey,
                        name = parentName,
                    }
                end
                categoriesByKey[categoryKey] = category
            end
            category.quests[#category.quests + 1] = questEntry
        end
    end

    local ordered = {}
    for key, category in pairs(categoriesByKey) do
        category.key = key
        ordered[#ordered + 1] = category
    end

    table.sort(ordered, function(a, b)
        local nameA = string.lower(a.name or "")
        local nameB = string.lower(b.name or "")
        if nameA == nameB then
            return (a.key or "") < (b.key or "")
        end
        return nameA < nameB
    end)

    for index = 1, #ordered do
        local category = ordered[index]
        table.sort(category.quests, function(left, right)
            local nameA = string.lower(left.name or "")
            local nameB = string.lower(right.name or "")
            if nameA == nameB then
                return (left.journalIndex or 0) < (right.journalIndex or 0)
            end
            return nameA < nameB
        end)
    end

    snapshot.categories.ordered = ordered
    snapshot.categories.byKey = categoriesByKey

    return snapshot
end

local function FindQuestCategoryIndex(snapshot, journalIndex)
    if not snapshot or not snapshot.categories or not snapshot.categories.ordered then
        return nil, nil
    end

    local ordered = snapshot.categories.ordered
    for categoryIndex = 1, #ordered do
        local category = ordered[categoryIndex]
        for questIndex = 1, #category.quests do
            local quest = category.quests[questIndex]
            if quest and quest.journalIndex == journalIndex then
                return categoryIndex, questIndex
            end
        end
    end

    return nil, nil
end

local function FindCategoryIndexByKey(snapshot, categoryKey)
    if not snapshot or not snapshot.categories or not snapshot.categories.ordered then
        return nil
    end

    local normalized = NormalizeCategoryKey(categoryKey)
    if not normalized then
        return nil
    end

    local ordered = snapshot.categories.ordered
    for index = 1, #ordered do
        local category = ordered[index]
        if category and NormalizeCategoryKey(category.key) == normalized then
            return index
        end
    end

    return nil
end

local function RelayoutFromSnapshotIndex(_, context)
    if not state.isInitialized then
        return
    end

    if not state.snapshot then
        QuestTracker.RedrawQuestTrackerFromLocalDB(context)
        return
    end

    QuestTracker:RestackAllCategories()
    UpdateContentSize()
    NotifyHostContentChanged()
end

local function RelayoutCategoryByKey(categoryKey, context)
    if not categoryKey then
        RelayoutFromSnapshotIndex(1, context)
        return
    end

    local normalized = NormalizeCategoryKey and NormalizeCategoryKey(categoryKey) or categoryKey
    local entry = categoriesByKey[normalized] or categoriesByKey[categoryKey]
    if not entry then
        QuestTracker.RedrawQuestTrackerFromLocalDB(context)
        return
    end

    entry.isExpanded = IsCategoryExpanded and IsCategoryExpanded(categoryKey) or false
    if entry.control then
        entry.control.isExpanded = entry.isExpanded
    end

    QuestTracker:RestackCategory(entry.storageKey or normalized)
    QuestTracker:RestackAllCategories()
    UpdateContentSize()
    NotifyHostContentChanged()
end

local function RelayoutCategoriesByKeySet(categoryKeys, context)
    if not categoryKeys then
        RelayoutFromSnapshotIndex(1, context)
        return
    end

    local touched = false
    for key in pairs(categoryKeys) do
        local normalized = NormalizeCategoryKey and NormalizeCategoryKey(key) or key
        local entry = categoriesByKey[normalized] or categoriesByKey[key]
        if entry then
            entry.isExpanded = IsCategoryExpanded and IsCategoryExpanded(key) or false
            if entry.control then
                entry.control.isExpanded = entry.isExpanded
            end
            QuestTracker:RestackCategory(entry.storageKey or normalized)
            touched = true
        end
    end

    if touched then
        QuestTracker:RestackAllCategories()
        UpdateContentSize()
        NotifyHostContentChanged()
    end
end

local function RelayoutQuestByJournalIndex(journalIndex, context)
    QuestTracker.RedrawSingleQuestFromLocalDB(journalIndex, context)
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
    -- State write logging disabled to prevent chat spam.
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

    local newExpanded = expanded and true or false

    state.saved.cat[key] = {
        expanded = newExpanded,
        source = source,
        ts = now,
    }

    LogStateWrite("cat", key, newExpanded, source, priority)

    return true
end

function QuestTracker:UpdateQuestControlHeight(node)
    local questControl = node and node.questControl
    if not questControl then
        return
    end

    local questTop = 0
    if questControl.GetTop then
        questTop = questControl:GetTop() or 0
    end

    local titleBottom = questTop
    local titleLabel = questControl.titleLabel or questControl.label
    if titleLabel and titleLabel.GetBottom then
        titleBottom = titleLabel:GetBottom() or questTop
    elseif questControl.baseHeight then
        titleBottom = questTop + questControl.baseHeight
    else
        titleBottom = questTop + QUEST_MIN_HEIGHT
    end

    local objectivesBottom = questTop
    local container = questControl.objectiveContainer or questControl.objectivesContainer
    local lastObjective = node and node.objectiveControls and node.objectiveControls[#node.objectiveControls]
    if lastObjective and lastObjective.GetBottom then
        objectivesBottom = lastObjective:GetBottom() or questTop
    elseif container and container.GetBottom then
        objectivesBottom = container:GetBottom() or questTop
    end

    local contentBottom = titleBottom
    if objectivesBottom > contentBottom then
        contentBottom = objectivesBottom
    end

    local paddingBottom = self.questBottomPadding or 4
    local newHeight = math.max(QUEST_MIN_HEIGHT, contentBottom - questTop + paddingBottom)

    if questControl.SetHeight then
        questControl:SetHeight(newHeight)
    end

    if container and container.SetHeight and container.GetTop then
        local containerTop = container:GetTop() or questTop
        local containerHeight = 0
        if lastObjective and lastObjective.GetBottom then
            containerHeight = math.max(0, (lastObjective:GetBottom() or containerTop) - containerTop)
        elseif container.GetBottom then
            containerHeight = math.max(0, (container:GetBottom() or containerTop) - containerTop)
        end
        container:SetHeight(containerHeight)
        node.objectivesHeight = containerHeight
        questControl.objectivesHeight = containerHeight
    end
end

UpdateQuestControlHeight = function(node)
    return QuestTracker:UpdateQuestControlHeight(node)
end

function QuestTracker:RestackCategory(categoryKey)
    local normalized = NormalizeCategoryKey and NormalizeCategoryKey(categoryKey) or categoryKey
    local entry = categoriesByKey[normalized] or categoriesByKey[categoryKey]
    if not (entry and entry.control) then
        return
    end

    local control = entry.control
    local questListArea = entry.questListArea or control.questListArea
    if not questListArea then
        return
    end

    local expanded = entry.isExpanded
    if expanded == nil and entry.key then
        expanded = IsCategoryExpanded and IsCategoryExpanded(entry.key)
    end
    expanded = expanded and true or false
    entry.isExpanded = expanded
    control.isExpanded = expanded

    local spacing = self.questVerticalSpacing or QUEST_VERTICAL_SPACING or 0
    local prevQuestCtrl = nil
    local lastVisible = nil

    for _, journalIndex in ipairs(entry.quests or {}) do
        local node = questNodesByIndex[journalIndex]
        local questControl = node and node.questControl
        if questControl then
            if UpdateQuestControlHeight then
                UpdateQuestControlHeight(node)
            end

            questControl:SetHidden(not expanded)

            if expanded then
                questControl:ClearAnchors()
                if prevQuestCtrl then
                    questControl:SetAnchor(TOPLEFT, prevQuestCtrl, BOTTOMLEFT, 0, spacing)
                else
                    questControl:SetAnchor(TOPLEFT, questListArea, TOPLEFT, 0, 0)
                end
                questControl:SetAnchor(RIGHT, questListArea, RIGHT, 0, 0)
                prevQuestCtrl = questControl
                lastVisible = questControl
            end
        end
    end

    if questListArea.SetHidden then
        questListArea:SetHidden(not expanded)
    end

    local totalQuestHeight = 0
    if expanded and lastVisible and lastVisible.GetBottom and questListArea.GetTop then
        local bottom = lastVisible:GetBottom() or 0
        local top = questListArea:GetTop() or 0
        totalQuestHeight = math.max(0, bottom - top)
    end

    if questListArea.SetHeight then
        questListArea:SetHeight(expanded and totalQuestHeight or 0)
    end

    local headerLabel = control.headerLabel or control.label
    local headerHeight = control.baseHeight or CATEGORY_MIN_HEIGHT
    if headerLabel and headerLabel.GetHeight then
        headerHeight = math.max(headerHeight, headerLabel:GetHeight() or 0)
    end

    local padding = self.headerToQuestPadding or CATEGORY_HEADER_TO_QUEST_PADDING or 0
    local categoryHeight = headerHeight
    if expanded and totalQuestHeight > 0 then
        categoryHeight = headerHeight + padding + totalQuestHeight
    end
    categoryHeight = math.max(CATEGORY_MIN_HEIGHT, categoryHeight)

    if control.SetHeight then
        control:SetHeight(categoryHeight)
    end

    local colorRole = entry.isExpanded and "activeTitle" or "categoryTitle"
    local r, g, b, a = GetQuestTrackerColor(colorRole)
    ApplyBaseColor(control, r, g, b, a)
    UpdateCategoryToggle(control, entry.isExpanded)
    UpdateCategoryHeaderDisplay(entry)
end

function QuestTracker:RestackAllCategories()
    local container = self.scrollChildControl or state.container
    if not container then
        return
    end

    local catSpacing = self.categoryVerticalSpacing or CATEGORY_VERTICAL_SPACING or 0
    local prevCategory = nil

    for _, key in ipairs(categoriesDisplayOrder) do
        local normalized = NormalizeCategoryKey and NormalizeCategoryKey(key) or key
        local entry = categoriesByKey[normalized] or categoriesByKey[key]
        local control = entry and entry.control
        if control and not control:IsHidden() then
            control:ClearAnchors()
            if prevCategory then
                control:SetAnchor(TOPLEFT, prevCategory, BOTTOMLEFT, 0, catSpacing)
            else
                control:SetAnchor(TOPLEFT, container, TOPLEFT, 0, 0)
            end
            control:SetAnchor(RIGHT, container, RIGHT, 0, 0)
            prevCategory = control
        end
    end

    if prevCategory and prevCategory.GetBottom and container.GetTop then
        local fullHeight = math.max(0, (prevCategory:GetBottom() or 0) - (container:GetTop() or 0))
        if container.SetHeight then
            container:SetHeight(fullHeight)
        end
        state.contentHeight = fullHeight
    else
        if container.SetHeight then
            container:SetHeight(0)
        end
        state.contentHeight = 0
    end

    local containerWidth = container.GetWidth and container:GetWidth() or 0
    if containerWidth and containerWidth > 0 then
        state.contentWidth = containerWidth
    end
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

    local newExpanded = expanded and true or false

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

    if control.label.SetHeight then
        control.label:SetHeight(targetHeight)
    end

    if control.usesAutoHeight then
        control.baseHeight = targetHeight
    else
        control:SetHeight(targetHeight)
    end
end

RefreshControlMetrics = function(control)
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

        local baseHeight = control.baseHeight or QUEST_MIN_HEIGHT
        local objectiveHeight = control.objectivesHeight or 0
        if control.objectiveContainer and control.objectiveContainer.GetHeight then
            local containerHeight = control.objectiveContainer:GetHeight() or 0
            if containerHeight > objectiveHeight then
                objectiveHeight = containerHeight
            end
        end

        if control.SetHeight then
            control:SetHeight(baseHeight + math.max(0, objectiveHeight))
        end
    elseif rowType == "condition" or rowType == "objective" then
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
    -- Quest selection logging disabled for performance.
end

local function LogQuestExpansion(action, trigger, journalIndex, beforeExpanded, afterExpanded, source, extraFields)
    -- Quest expansion logging disabled for performance.
end

local function LogCategoryExpansion(action, trigger, categoryKey, beforeExpanded, afterExpanded, source, extraFields)
    -- Category expansion logging disabled for performance.
end

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
    -- External select logging disabled to prevent chat spam.
end

local function LogExpandCategory(categoryId, reason)
    -- Category expansion logging disabled to prevent chat spam.
end

local function LogMissingCategory(questId)
    -- Missing category logging disabled to prevent chat spam.
end

local function LogScrollIntoView(questId)
    -- Scroll logging disabled to prevent chat spam.
end

local function ExpandCategoriesForExternalSelect(journalIndex)
    if not (state.saved and journalIndex) then
        return false, false
    end

    local keys, found = CollectCategoryKeysForQuest(journalIndex)
    local expandedKeys = nil

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
                    expandedKeys = expandedKeys or {}
                    expandedKeys[key] = true
                end
            end
        end
    end

    if (not found) or not keys or next(keys) == nil then
        LogMissingCategory(journalIndex)
    end

    if expandedKeys then
        RelayoutCategoriesByKeySet(expandedKeys, {
            trigger = "external-select",
            source = "QuestTracker:ExpandCategoriesForExternalSelect",
        })
    end

    return expandedKeys ~= nil, found
end

local function ExpandCategoriesForClickSelect(journalIndex)
    if not (state.saved and journalIndex) then
        return false, false
    end

    local keys, found = CollectCategoryKeysForQuest(journalIndex)
    local expandedKeys = nil

    if keys then
        local context = {
            trigger = "click-select",
            source = "QuestTracker:ExpandCategoriesForClickSelect",
        }

        for key in pairs(keys) do
            if key and SetCategoryExpanded then
                local changed = SetCategoryExpanded(key, true, context)
                if changed then
                    expandedKeys = expandedKeys or {}
                    expandedKeys[key] = true
                end
            end
        end
    end

    if (not found) or not keys or next(keys) == nil then
        LogMissingCategory(journalIndex)
    end

    if expandedKeys then
        RelayoutCategoriesByKeySet(expandedKeys, {
            trigger = "click-select",
            source = "QuestTracker:ExpandCategoriesForClickSelect",
        })
    end

    return expandedKeys ~= nil, found
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

    for key in pairs(keys) do
        if key then
            local changed = SetCategoryExpanded(key, true, logContext)
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

        if previousTracked ~= currentTracked or hasTracked or hadTracked or pendingApplied or expansionChanged then
            if previousTracked then
                RelayoutQuestByJournalIndex(previousTracked, context)
            end
            if currentTracked then
                RelayoutQuestByJournalIndex(currentTracked, context)
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

    local previousTracked = state.trackedQuestIndex

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
        if previousTracked and previousTracked ~= numeric then
            RelayoutQuestByJournalIndex(previousTracked, actionContext)
        end
        RelayoutQuestByJournalIndex(numeric, actionContext)
    end

    return true
end

HandleQuestRowClick = function(journalIndex)
    local questId = tonumber(journalIndex)
    if not questId or questId <= 0 then
        return
    end

    if state.isClickSelectInProgress then
        return
    end

    state.isClickSelectInProgress = true

    state.pendingSelection = nil

    local previousQuest = state.trackedQuestIndex

    ApplyImmediateTrackedQuest(questId, "click-select")

    local rowContext = {
        trigger = "click-select",
        source = "QuestTracker:HandleQuestRowClick",
    }

    if previousQuest and previousQuest ~= questId then
        RelayoutQuestByJournalIndex(previousQuest, rowContext)
    end
    RelayoutQuestByJournalIndex(questId, rowContext)

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

    if previousQuest and previousQuest ~= questId then
        RelayoutQuestByJournalIndex(previousQuest, rowContext)
    end
    RelayoutQuestByJournalIndex(questId, rowContext)
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

local function HandlePlayerActivation()
    local function execute()
        SyncTrackedQuestState(nil, true, {
            trigger = "init",
            source = "QuestTracker:HandlePlayerActivation",
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

    return string.format("%s|%d|%s", face, size, outline or DEFAULT_FONT_OUTLINE)
end

local function ResetLayoutState()
    state.orderedControls = {}
    state.lastAnchoredControl = nil
    state.categoryControls = {}
    state.questControls = {}
    for key in pairs(questNodesByIndex) do
        questNodesByIndex[key] = nil
    end
    for key in pairs(categoriesByKey) do
        categoriesByKey[key] = nil
    end
    for index = #categoriesDisplayOrder, 1, -1 do
        categoriesDisplayOrder[index] = nil
    end
end

local function RemoveOrderedControl(control)
    if not control then
        return
    end

    for index = #state.orderedControls, 1, -1 do
        if state.orderedControls[index] == control then
            table.remove(state.orderedControls, index)
        end
    end

    if state.lastAnchoredControl == control then
        state.lastAnchoredControl = state.orderedControls[#state.orderedControls]
    end
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
    local visibleCategories = 0
    local spacing = CATEGORY_VERTICAL_SPACING or 0

    for index = 1, #categoriesDisplayOrder do
        local key = categoriesDisplayOrder[index]
        local normalized = NormalizeCategoryKey and NormalizeCategoryKey(key) or key
        local entry = categoriesByKey[normalized] or categoriesByKey[key]
        local control = entry and entry.control
        if control then
            RefreshControlMetrics(control)
        end
        if control and not control:IsHidden() then
            local width = (control:GetWidth() or 0)
            if width > maxWidth then
                maxWidth = width
            end
            if visibleCategories > 0 and spacing > 0 then
                totalHeight = totalHeight + spacing
            end
            totalHeight = totalHeight + (control:GetHeight() or 0)
            visibleCategories = visibleCategories + 1
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
        RelayoutQuestByJournalIndex(journalIndex, toggleContext)
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
        control.headerLabel = control.label
        if control.toggle and control.toggle.SetTexture then
            control.toggle:SetTexture(SelectCategoryToggleTexture(false, false))
        end
        if not control.questListArea then
            local questList = CreateControl(control:GetName() .. "QuestList", control, CT_CONTROL)
            questList:SetAnchor(TOPLEFT, control.label, BOTTOMLEFT, 0, CATEGORY_HEADER_TO_QUEST_PADDING)
            questList:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, CATEGORY_HEADER_TO_QUEST_PADDING)
            questList:SetHidden(true)
            if questList.SetResizeToFitDescendents then
                questList:SetResizeToFitDescendents(false)
            end
            if questList.SetHeight then
                questList:SetHeight(0)
            end
            if questList.SetMouseEnabled then
                questList:SetMouseEnabled(false)
            end
            control.questListArea = questList
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
                RelayoutCategoryByKey(catKey, {
                    trigger = "click",
                    source = "QuestTracker:OnCategoryClick",
                })
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
        control.objectiveContainer = control:GetNamedChild("Objectives")
        if control.SetResizeToFitDescendents then
            control:SetResizeToFitDescendents(false)
        end
        if control.objectiveContainer and control.objectiveContainer.SetResizeToFitDescendents then
            control.objectiveContainer:SetResizeToFitDescendents(false)
        end
        if control.objectiveContainer and control.objectiveContainer.SetHeight then
            control.objectiveContainer:SetHeight(0)
        end
        control.objectivesHeight = 0
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
    control.usesAutoHeight = true
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
        if control.questListArea then
            if control.questListArea.SetHidden then
                control.questListArea:SetHidden(true)
            end
            if control.questListArea.SetHeight then
                control.questListArea:SetHeight(0)
            end
        end
    end)
    state.questPool:SetCustomResetBehavior(function(control)
        resetControl(control)
        if control.label and control.label.SetText then
            control.label:SetText("")
        end
        if control.SetResizeToFitDescendents then
            control:SetResizeToFitDescendents(false)
        end
        control.objectivesHeight = 0
        if control.SetHeight then
            control:SetHeight(QUEST_MIN_HEIGHT)
        end
        if control.objectiveContainer then
            if control.objectiveContainer.SetHidden then
                control.objectiveContainer:SetHidden(true)
            end
            if control.objectiveContainer.SetResizeToFitDescendents then
                control.objectiveContainer:SetResizeToFitDescendents(false)
            end
            if control.objectiveContainer.SetHeight then
                control.objectiveContainer:SetHeight(0)
            end
            local childCount = control.objectiveContainer:GetNumChildren() or 0
            for childIndex = 1, childCount do
                local child = control.objectiveContainer:GetChild(childIndex)
                if child and child.SetHidden then
                    child:SetHidden(true)
                end
            end
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

local function EnsureQuestNode(journalIndex)
    if not journalIndex then
        return nil
    end

    local node = questNodesByIndex[journalIndex]
    if not node then
        node = {
            objectiveControls = {},
        }
        questNodesByIndex[journalIndex] = node
    elseif type(node.objectiveControls) ~= "table" then
        node.objectiveControls = {}
    end

    return node
end

local function ApplyObjectivesToNode(node, objectives, expanded)
    if not node then
        return false
    end

    local questControl = node.questControl
    local container = questControl and questControl.objectiveContainer
    if not (questControl and container) then
        return false
    end

    local controls = node.objectiveControls
    if type(controls) ~= "table" then
        controls = {}
        node.objectiveControls = controls
    end

    if next(controls) == nil and container and container.GetNumChildren then
        local childCount = container:GetNumChildren() or 0
        for childIndex = 1, childCount do
            local child = container:GetChild(childIndex)
            if child then
                controls[childIndex] = child
                if (not child.label or not child.label.SetText) and child.GetNamedChild then
                    child.label = child:GetNamedChild("Label")
                end
            end
        end
    end

    local objectiveCount = type(objectives) == "table" and #objectives or 0
    local baseHeight = questControl.baseHeight or (questControl:GetHeight() or QUEST_MIN_HEIGHT)

    if not expanded or objectiveCount == 0 then
        for index = 1, #controls do
            local objectiveControl = controls[index]
            if objectiveControl and objectiveControl.SetHidden then
                objectiveControl:SetHidden(true)
            end
        end
        if container.SetHidden then
            container:SetHidden(true)
        end
        if container.SetHeight then
            container:SetHeight(0)
        end
        if container.SetResizeToFitDescendents then
            container:SetResizeToFitDescendents(true)
        end
        questControl.objectivesHeight = 0
        if questControl.SetHeight then
            questControl:SetHeight(baseHeight)
        end
        return true
    end

    local previous = nil
    local indent = (questControl.currentIndent or QUEST_INDENT_X) + CONDITION_RELATIVE_INDENT
    local objectiveHeightTotal = 0

    for index = 1, objectiveCount do
        local objective = objectives[index]
        local objectiveControl = controls[index]

        if not objectiveControl and container and container.GetChild then
            objectiveControl = container:GetChild(index)
            if objectiveControl then
                controls[index] = objectiveControl
            end
        end

        if not objectiveControl then
            local baseName = questControl:GetName()
            if not baseName or baseName == "" then
                local journalIndex = node.journalIndex or index
                baseName = string.format("Nvk3UTQuest%d", journalIndex)
            end
            baseName = tostring(baseName):gsub("[^%w_]", "_")
            local controlName = string.format("%sObjective%d", baseName, index)
            objectiveControl = CreateControlFromVirtual(controlName, container, "QuestCondition_Template")
            if not objectiveControl then
                return false
            end
            controls[index] = objectiveControl
        end

        if (not objectiveControl.label or not objectiveControl.label.SetText) and objectiveControl.GetNamedChild then
            objectiveControl.label = objectiveControl:GetNamedChild("Label")
        end

        ApplyLabelDefaults(objectiveControl.label)

        objectiveControl.rowType = "objective"
        objectiveControl.currentIndent = indent
        objectiveControl:ClearAnchors()
        if previous then
            objectiveControl:SetAnchor(TOPLEFT, previous, BOTTOMLEFT, 0, VERTICAL_PADDING)
        else
            objectiveControl:SetAnchor(TOPLEFT, container, TOPLEFT, 0, OBJECTIVE_TOP_PADDING)
        end
        -- Anchor the right edge to the container so every objective line uses the
        -- same available width regardless of the previous row's measured width.
        objectiveControl:SetAnchor(RIGHT, container, RIGHT, 0, 0)

        local lineText = objective and objective.displayText or ""
        if objective and objective.isTurnIn then
            lineText = "* " .. lineText
        end

        if objectiveControl.label then
            ApplyFont(objectiveControl.label, state.fonts.condition, DEFAULT_FONTS.condition)
            objectiveControl.label:SetText(lineText)
            local r, g, b, a = GetQuestTrackerColor("objectiveText")
            objectiveControl.label:SetColor(r, g, b, a)
        end

        ApplyRowMetrics(objectiveControl, indent, 0, 0, 0, CONDITION_MIN_HEIGHT)
        objectiveControl:SetHidden(false)

        local height = objectiveControl.GetHeight and objectiveControl:GetHeight() or CONDITION_MIN_HEIGHT
        if index == 1 then
            objectiveHeightTotal = OBJECTIVE_TOP_PADDING + height
        else
            objectiveHeightTotal = objectiveHeightTotal + VERTICAL_PADDING + height
        end

        previous = objectiveControl
    end

    for index = objectiveCount + 1, #controls do
        local objectiveControl = controls[index]
        if objectiveControl and objectiveControl.SetHidden then
            objectiveControl:SetHidden(true)
        end
    end

    objectiveHeightTotal = math.max(0, objectiveHeightTotal)

    if container.SetHidden then
        container:SetHidden(false)
    end
    if container.SetResizeToFitDescendents then
        container:SetResizeToFitDescendents(false)
    end
    if container.SetHeight then
        container:SetHeight(objectiveHeightTotal)
    end

    node.objectivesHeight = objectiveHeightTotal
    questControl.objectivesHeight = objectiveHeightTotal
    if UpdateQuestControlHeight then
        UpdateQuestControlHeight(node)
    elseif questControl.SetHeight then
        questControl:SetHeight(baseHeight + objectiveHeightTotal)
    end

    return true
end

local function ApplyQuestEntryToNode(node, questEntry, categoryControl)
    if not (node and questEntry) then
        return false
    end

    local questControl = node.questControl
    if not questControl then
        return false
    end

    questControl.data = questControl.data or {}
    questControl.data.quest = questEntry

    node.categoryControl = categoryControl
    node.categoryKey = NormalizeCategoryKey(questEntry.categoryKey)
    node.storageKey = node.categoryKey or questEntry.categoryKey
    node.journalIndex = questEntry.journalIndex

    if questControl.label then
        questControl.label:SetText(questEntry.name or "")
    end

    local colorRole = DetermineQuestColorRole(questEntry)
    local r, g, b, a = GetQuestTrackerColor(colorRole)
    ApplyBaseColor(questControl, r, g, b, a)
    UpdateQuestIconSlot(questControl)

    local expanded = IsQuestExpanded(questEntry.journalIndex)
    node.isExpanded = expanded and true or false

    local objectivesApplied = ApplyObjectivesToNode(node, questEntry.objectives, expanded)
    if not objectivesApplied then
        return false
    end
    RefreshControlMetrics(questControl)

    return true
end

local function LayoutQuest(quest, categoryControl, categoryEntry)
    local control = AcquireQuestControl()
    control.data = { quest = quest }
    control.currentIndent = QUEST_INDENT_X

    if categoryEntry and categoryEntry.questListArea and control.SetParent then
        control:SetParent(categoryEntry.questListArea)
    end

    ApplyRowMetrics(
        control,
        QUEST_INDENT_X,
        QUEST_ICON_SLOT_WIDTH,
        QUEST_ICON_SLOT_PADDING_X,
        0,
        QUEST_MIN_HEIGHT
    )
    control:SetHidden(false)

    if quest and quest.journalIndex then
        state.questControls[quest.journalIndex] = control
        local node = EnsureQuestNode(quest.journalIndex)
        node.questControl = control
        ApplyQuestEntryToNode(node, quest, categoryControl)
    end

    state.orderedControls[#state.orderedControls + 1] = control

    return control
end

local function UpdateCategoryHeaderDisplay(entry)
    if not entry then
        return
    end

    local control = entry.control
    local label = (control and control.label) or entry.headerLabel
    if not (control and label) then
        return
    end

    local count = entry.quests and #entry.quests or 0
    label:SetText(FormatCategoryHeaderText(entry.name or "", count, "quest"))
end

local function RemoveQuestFromEntry(entry, journalIndex)
    if not (entry and entry.quests and journalIndex) then
        return
    end

    for index = #entry.quests, 1, -1 do
        if entry.quests[index] == journalIndex then
            table.remove(entry.quests, index)
        end
    end
end

local function EnsureQuestInEntry(entry, journalIndex)
    if not (entry and entry.quests and journalIndex) then
        return
    end

    for index = 1, #entry.quests do
        if entry.quests[index] == journalIndex then
            return
        end
    end

    entry.quests[#entry.quests + 1] = journalIndex
end

local function ApplyRecordToQuestNode(tracker, node, record, entry, options)
    if not (tracker and node and record) then
        return false
    end

    local questControl = node.questControl
    if not questControl then
        return false
    end

    local questEntry = BuildQuestEntryFromRecord(record)
    if not questEntry then
        return false
    end

    questControl.data = questControl.data or {}
    questControl.data.quest = questEntry

    node.journalIndex = questEntry.journalIndex
    local normalizedCategory = NormalizeCategoryKey and NormalizeCategoryKey(record.categoryKey) or record.categoryKey
    node.categoryKey = normalizedCategory
    node.storageKey = normalizedCategory or record.categoryKey
    node.categoryControl = entry and entry.control or node.categoryControl

    if questControl.label then
        questControl.label:SetText(questEntry.name or "")
    end
    if questControl.titleLabel then
        questControl.titleLabel:SetText(questEntry.name or "")
    end

    local colorRole = DetermineQuestColorRole and DetermineQuestColorRole(questEntry)
    if colorRole then
        local r, g, b, a = GetQuestTrackerColor(colorRole)
        ApplyBaseColor(questControl, r, g, b, a)
    end
    UpdateQuestIconSlot(questControl)

    local container = questControl.objectiveContainer or questControl.objectivesContainer
    if not container then
        return false
    end

    local controls = node.objectiveControls
    if type(controls) ~= "table" then
        controls = {}
        node.objectiveControls = controls
    end

    for index = #controls, 1, -1 do
        local ctrl = controls[index]
        if ctrl and ctrl.SetHidden then
            ctrl:SetHidden(true)
        end
        controls[index] = nil
    end

    local objectives = questEntry.objectives or {}
    local isExpanded = IsQuestExpanded and IsQuestExpanded(questEntry.journalIndex)
    node.isExpanded = isExpanded and true or false

    if not isExpanded or #objectives == 0 then
        if container.SetHidden then
            container:SetHidden(true)
        end
        if container.SetHeight then
            container:SetHeight(0)
        end
        node.objectivesHeight = 0
        questControl.objectivesHeight = 0
        tracker:UpdateQuestControlHeight(node)
    else
        local prev = nil
        local firstYOffset = tracker.objectiveLineTopPadding or OBJECTIVE_TOP_PADDING or 2
        local spacing = tracker.objectiveLineSpacing or VERTICAL_PADDING or 0
        local indent = (questControl.currentIndent or QUEST_INDENT_X) + CONDITION_RELATIVE_INDENT

        for index, objective in ipairs(objectives) do
            local ctrl = container:GetChild(index)
            if not ctrl then
                local baseName = questControl:GetName() or string.format("Nvk3UTQuest%d", questEntry.journalIndex or index)
                baseName = tostring(baseName):gsub("[^%w_]", "_")
                local controlName = string.format("%sObjective%d", baseName, index)
                ctrl = CreateControlFromVirtual(controlName, container, "QuestCondition_Template")
            end

            controls[index] = ctrl

            if ctrl then
                if (not ctrl.label or not ctrl.label.SetText) and ctrl.GetNamedChild then
                    ctrl.label = ctrl:GetNamedChild("Label")
                end

                ctrl.rowType = "objective"
                ctrl.currentIndent = indent
                ctrl:ClearAnchors()
                if prev then
                    ctrl:SetAnchor(TOPLEFT, prev, BOTTOMLEFT, 0, spacing)
                else
                    ctrl:SetAnchor(TOPLEFT, container, TOPLEFT, 0, firstYOffset)
                end
                ctrl:SetAnchor(RIGHT, container, RIGHT, 0, 0)

                local lineText = objective.displayText or ""
                if objective.isTurnIn then
                    lineText = "* " .. lineText
                end

                if ctrl.label then
                    ApplyFont(ctrl.label, state.fonts.condition, DEFAULT_FONTS.condition)
                    ctrl.label:SetText(lineText)
                    local r, g, b, a = GetQuestTrackerColor("objectiveText")
                    ctrl.label:SetColor(r, g, b, a)
                end

                ApplyRowMetrics(ctrl, indent, 0, 0, 0, CONDITION_MIN_HEIGHT)
                ctrl:SetHidden(false)
                prev = ctrl
            end
        end

        local childCount = container.GetNumChildren and container:GetNumChildren() or 0
        for index = #objectives + 1, childCount do
            local extra = container:GetChild(index)
            if extra and extra.SetHidden then
                extra:SetHidden(true)
            end
        end

        local containerTop = container.GetTop and container:GetTop() or 0
        local bottom = containerTop
        if prev and prev.GetBottom then
            bottom = prev:GetBottom() or containerTop
        end
        local containerHeight = math.max(0, bottom - containerTop)

        if container.SetHidden then
            container:SetHidden(false)
        end
        if container.SetHeight then
            container:SetHeight(containerHeight)
        end

        node.objectivesHeight = containerHeight
        questControl.objectivesHeight = containerHeight
        tracker:UpdateQuestControlHeight(node)
    end

    if entry then
        EnsureQuestInEntry(entry, questEntry.journalIndex)
        UpdateCategoryHeaderDisplay(entry)
    end

    if entry and entry.control and entry.control.SetHidden then
        entry.control:SetHidden(false)
    end
    if entry and entry.isExpanded ~= nil and node.questControl then
        node.questControl:SetHidden(not entry.isExpanded)
    end

    if not (options and options.deferRestack) then
        local keyForRestack = nil
        if entry then
            keyForRestack = entry.storageKey or entry.key or node.categoryKey
        else
            keyForRestack = node.categoryKey
        end
        if keyForRestack then
            tracker:RestackCategory(keyForRestack)
        end
        tracker:RestackAllCategories()
    end

    return true
end

local function BuildQuestRow(tracker, entry, questEntry)
    if not (tracker and entry and questEntry) then
        return nil
    end

    local questControl = AcquireQuestControl()
    if entry.questListArea and questControl.SetParent then
        questControl:SetParent(entry.questListArea)
    end
    questControl.rowType = "quest"
    questControl.currentIndent = QUEST_INDENT_X
    questControl:SetHidden(not entry.isExpanded)

    ApplyRowMetrics(
        questControl,
        QUEST_INDENT_X,
        QUEST_ICON_SLOT_WIDTH,
        QUEST_ICON_SLOT_PADDING_X,
        0,
        QUEST_MIN_HEIGHT
    )

    state.questControls[questEntry.journalIndex] = questControl
    state.orderedControls[#state.orderedControls + 1] = questControl

    local node = EnsureQuestNode(questEntry.journalIndex)
    node.questControl = questControl
    node.categoryControl = entry.control
    node.categoryKey = entry.storageKey
    node.storageKey = entry.storageKey

    entry.quests[#entry.quests + 1] = questEntry.journalIndex

    local recordTable = LocalQuestDB and LocalQuestDB.quests
    local record = recordTable and recordTable[questEntry.journalIndex]
    if not record then
        record = {
            journalIndex = questEntry.journalIndex,
            name = questEntry.name,
            objectives = questEntry.objectives,
            categoryKey = questEntry.categoryKey,
            parentKey = questEntry.parentKey,
        }
    end

    ApplyRecordToQuestNode(tracker, node, record, entry, { deferRestack = true })

    return questControl
end

local function BuildCategoryFromSnapshot(tracker, category)
    if not (tracker and category and category.quests and #category.quests > 0) then
        return nil
    end

    local control = AcquireCategoryControl()
    local normalizedKey = NormalizeCategoryKey and NormalizeCategoryKey(category.key) or category.key
    control.currentIndent = CATEGORY_INDENT_X
    control.data = {
        categoryKey = category.key,
        parentKey = category.parent and category.parent.key or nil,
        parentName = category.parent and category.parent.name or nil,
    }
    control:SetHidden(false)

    local entry = {
        key = normalizedKey,
        storageKey = normalizedKey or category.key,
        control = control,
        questListArea = control.questListArea,
        quests = {},
        headerLabel = control.headerLabel or control.label,
        name = category.name,
    }

    entry.isExpanded = IsCategoryExpanded and IsCategoryExpanded(category.key) or false
    control.isExpanded = entry.isExpanded

    if control.questListArea then
        control.questListArea:SetHidden(not entry.isExpanded)
        control.questListArea:SetHeight(0)
    end

    categoriesByKey[entry.storageKey] = entry
    categoriesDisplayOrder[#categoriesDisplayOrder + 1] = entry.storageKey
    state.categoryControls[entry.storageKey] = control
    state.orderedControls[#state.orderedControls + 1] = control

    UpdateCategoryToggle(control, entry.isExpanded)
    ApplyRowMetrics(
        control,
        CATEGORY_INDENT_X,
        GetToggleWidth(control.toggle, CATEGORY_TOGGLE_WIDTH),
        TOGGLE_LABEL_PADDING_X,
        0,
        CATEGORY_MIN_HEIGHT
    )

    control.label:SetText(FormatCategoryHeaderText(category.name or "", #category.quests, "quest"))
    control.categoryEntry = entry

    for _, questEntry in ipairs(category.quests) do
        BuildQuestRow(tracker, entry, questEntry)
    end

    UpdateCategoryHeaderDisplay(entry)
    tracker:RestackCategory(entry.storageKey)

    return entry
end

function QuestTracker:RebuildFromSnapshot(snapshot)
    EnsurePools()
    ReleaseAll(state.categoryPool)
    ReleaseAll(state.questPool)
    ReleaseAll(state.conditionPool)
    ResetLayoutState()

    PrimeInitialSavedState()
    ApplyActiveQuestFromSaved()

    local ordered = snapshot and snapshot.categories and snapshot.categories.ordered or {}
    for index = 1, #ordered do
        BuildCategoryFromSnapshot(self, ordered[index])
    end

    self:RestackAllCategories()
    UpdateContentSize()
    NotifyHostContentChanged()
    ProcessPendingExternalReveal()
end

local function LayoutCategory(category)
    local control = AcquireCategoryControl()
    local normalizedKey = NormalizeCategoryKey(category.key)
    control.currentIndent = CATEGORY_INDENT_X

    control.data = {
        categoryKey = category.key,
        parentKey = category.parent and category.parent.key or nil,
        parentName = category.parent and category.parent.name or nil,
        groupKey = category.groupKey,
        groupName = category.groupName,
        categoryType = category.type,
        groupOrder = category.groupOrder,
    }

    if normalizedKey then
        state.categoryControls[normalizedKey] = control
    end

    local count = #category.quests
    control.label:SetText(FormatCategoryHeaderText(category.name or "", count, "quest"))
    local expanded = IsCategoryExpanded(category.key)
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

    local storageKey = normalizedKey or category.key
    local entry = {
        key = normalizedKey,
        storageKey = storageKey,
        control = control,
        questListArea = control.questListArea,
        quests = {},
        headerLabel = control.headerLabel or control.label,
        isExpanded = expanded and true or false,
        name = category.name,
    }
    control.categoryEntry = entry

    if storageKey then
        categoriesByKey[storageKey] = entry
    end
    categoriesDisplayOrder[#categoriesDisplayOrder + 1] = storageKey

    state.orderedControls[#state.orderedControls + 1] = control

    if control.questListArea then
        if control.questListArea.SetHidden then
            control.questListArea:SetHidden(not expanded)
        end
        if control.questListArea.SetHeight then
            control.questListArea:SetHeight(0)
        end
    end

    for index = 1, count do
        local quest = category.quests[index]
        if quest and quest.journalIndex then
            entry.quests[#entry.quests + 1] = quest.journalIndex
            local node = EnsureQuestNode(quest.journalIndex)
            if node then
                node.categoryControl = control
                node.categoryKey = normalizedKey
                node.storageKey = storageKey
                node.journalIndex = quest.journalIndex
            end
        end
        if expanded and quest then
            LayoutQuest(quest, control, entry)
        end
    end

    UpdateCategoryHeaderDisplay(entry)
    QuestTracker:RestackCategory(storageKey)
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
        local entry = control.categoryEntry
        local storageKey = entry and entry.storageKey
        if not storageKey then
            local rawKey = control.data and control.data.categoryKey
            storageKey = NormalizeCategoryKey and NormalizeCategoryKey(rawKey) or rawKey
        end
        if storageKey then
            categoriesByKey[storageKey] = nil
            for index = #categoriesDisplayOrder, 1, -1 do
                if categoriesDisplayOrder[index] == storageKey then
                    table.remove(categoriesDisplayOrder, index)
                end
            end
        end
        control.categoryEntry = nil
        if state.categoryPool and control.poolKey then
            state.categoryPool:ReleaseObject(control.poolKey)
        end
    elseif rowType == "quest" then
        local questData = control.data and control.data.quest
        if questData and questData.journalIndex then
            state.questControls[questData.journalIndex] = nil
            questNodesByIndex[questData.journalIndex] = nil
            for key, category in pairs(categoriesByKey) do
                local quests = category and category.quests
                if quests then
                    for index = #quests, 1, -1 do
                        if quests[index] == questData.journalIndex then
                            table.remove(quests, index)
                        end
                    end
                end
            end
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

    for index = #categoriesDisplayOrder, keepCategoryCount + 1, -1 do
        local key = categoriesDisplayOrder[index]
        if key then
            categoriesByKey[key] = nil
        end
        table.remove(categoriesDisplayOrder, index)
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

RelayoutFromCategoryIndex = function()
    if not state.isInitialized then
        return
    end

    if not state.snapshot then
        QuestTracker.RedrawQuestTrackerFromLocalDB({
            trigger = "missing-snapshot",
            source = "QuestTracker:RelayoutFromCategoryIndex",
        })
        return
    end

    QuestTracker:RestackAllCategories()
    UpdateContentSize()
    NotifyHostContentChanged()
    ProcessPendingExternalReveal()
end

local function ApplySnapshotFromLocalDB(snapshot, context)
    state.snapshot = snapshot

    local trackingContext = {
        trigger = (context and context.trigger) or "refresh",
        source = (context and context.source) or "QuestTracker:ApplyLocalSnapshot",
    }

    UpdateTrackedQuestCache(nil, trackingContext)

    if state.trackedQuestIndex then
        EnsureTrackedQuestVisible(state.trackedQuestIndex, nil, trackingContext)
    end

    NotifyStatusRefresh()
end

-- NOTE: Full rebuild of the entire quest tracker.
-- This should only run during initialization or when FullSync()
-- handles global quest events (EVENT_PLAYER_ACTIVATED and EVENT_QUEST_LIST_UPDATED).
-- Do not call this from expand/select/assist changes or single-quest updates.
function QuestTracker.RedrawQuestTrackerFromLocalDB(context)
    local snapshot = BuildLocalSnapshot()
    ApplySnapshotFromLocalDB(snapshot, context)

    if not state.isInitialized then
        return
    end

    QuestTracker:RebuildFromSnapshot(snapshot)
end

-- NOTE: Incremental redraw for one quest row.
-- This updates only the quest's title/icon/objective text without rebuilding categories.
function QuestTracker:RefreshQuestObjectivesOnly(journalIndex)
    local numeric = tonumber(journalIndex) or journalIndex
    if not numeric then
        return false
    end

    local node = questNodesByIndex[numeric]
    local recordTable = LocalQuestDB and LocalQuestDB.quests
    local record = recordTable and recordTable[numeric]

    if not node or not node.questControl then
        if record then
            QuestTracker.RedrawQuestTrackerFromLocalDB({
                trigger = "missing-node",
                source = "QuestTracker:RefreshQuestObjectivesOnly",
            })
        end
        return false
    end

    local storageKey = node.categoryKey or node.storageKey
    local entry = nil
    if storageKey then
        local normalized = NormalizeCategoryKey and NormalizeCategoryKey(storageKey) or storageKey
        entry = categoriesByKey[normalized] or categoriesByKey[storageKey]
    end

    if not record then
        local questControl = node.questControl
        if questControl then
            if questControl.SetHidden then
                questControl:SetHidden(true)
            end
            RemoveOrderedControl(questControl)
            if state.questPool and questControl.poolKey then
                state.questPool:ReleaseObject(questControl.poolKey)
            end
            state.questControls[numeric] = nil
            node.questControl = nil
        end

        if entry then
            RemoveQuestFromEntry(entry, numeric)
            UpdateCategoryHeaderDisplay(entry)
            if entry.control and entry.control.SetHidden then
                entry.control:SetHidden(#entry.quests == 0)
            end
            self:RestackCategory(entry.storageKey or storageKey)
        end

        questNodesByIndex[numeric] = nil
        self:RestackAllCategories()
        UpdateContentSize()
        NotifyHostContentChanged()
        return true
    end

    local normalizedCategory = NormalizeCategoryKey and NormalizeCategoryKey(record.categoryKey) or record.categoryKey
    if node.categoryKey and normalizedCategory and node.categoryKey ~= normalizedCategory then
        QuestTracker.RedrawQuestTrackerFromLocalDB({
            trigger = "category-change",
            source = "QuestTracker:RefreshQuestObjectivesOnly",
        })
        return true
    end

    if not entry then
        entry = categoriesByKey[normalizedCategory] or categoriesByKey[record.categoryKey]
        if not entry then
            QuestTracker.RedrawQuestTrackerFromLocalDB({
                trigger = "missing-category",
                source = "QuestTracker:RefreshQuestObjectivesOnly",
            })
            return false
        end
    end

    if entry.control and entry.control.SetHidden then
        entry.control:SetHidden(false)
    end

    local applied = ApplyRecordToQuestNode(self, node, record, entry, nil)
    if not applied then
        return false
    end

    UpdateContentSize()
    NotifyHostContentChanged()

    return true
end

function QuestTracker.RedrawSingleQuestFromLocalDB(journalIndex, context)
    local snapshot = BuildLocalSnapshot()
    ApplySnapshotFromLocalDB(snapshot, context)

    if not state.isInitialized then
        return
    end

    local handled = QuestTracker:RefreshQuestObjectivesOnly(journalIndex)
    if handled then
        return
    end

    QuestTracker.RedrawQuestTrackerFromLocalDB({
        trigger = "fallback-single",
        source = "QuestTracker.RedrawSingleQuestFromLocalDB",
    })
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
    RefreshVisibility()
end

local function RegisterCombatEvents()
    if not state.opts.hideInCombat then
        return
    end

    EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE .. "Combat", EVENT_PLAYER_COMBAT_STATE, OnCombatState)
    state.combatHidden = IsUnitInCombat and IsUnitInCombat("player") or false
    RefreshVisibility()
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
    QuestTracker.scrollChildControl = parentControl
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

    state.isInitialized = true
    RefreshVisibility()
    QuestTracker.RedrawQuestTrackerFromLocalDB({
        trigger = "init",
        source = "QuestTracker:Init",
    })
    AdoptTrackedQuestOnInit()
end

function QuestTracker.HandlePlayerActivated()
    HandlePlayerActivation()
end

function QuestTracker.Refresh()
    QuestTracker.RedrawQuestTrackerFromLocalDB({
        trigger = "manual-refresh",
        source = "QuestTracker.Refresh",
    })
end

function QuestTracker.Shutdown()
    if not state.isInitialized then
        return
    end

    UnregisterCombatEvents()
    UnregisterTrackingEvents()

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
    QuestTracker.scrollChildControl = nil
    state.control = nil
    state.snapshot = nil
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
    for key in pairs(questNodesByIndex) do
        questNodesByIndex[key] = nil
    end
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
