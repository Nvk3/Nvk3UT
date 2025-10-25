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
local CONDITION_INDENT_X = 36
local VERTICAL_PADDING = 3

local CATEGORY_MIN_HEIGHT = 26
local QUEST_MIN_HEIGHT = 24
local CONDITION_MIN_HEIGHT = 20
local ROW_TEXT_PADDING_Y = 8
local TOGGLE_LABEL_PADDING_X = 4
local CATEGORY_TOGGLE_WIDTH = 20
local QUEST_ICON_SLOT_WIDTH = 18
local QUEST_ICON_SLOT_HEIGHT = 18
local QUEST_ICON_SLOT_PADDING_X = 6

local DEFAULT_FONTS = {
    category = "ZoFontGameBold",
    quest = "ZoFontGame",
    condition = "ZoFontGameSmall",
    toggle = "ZoFontGame",
}

local DEFAULT_FONT_OUTLINE = "soft-shadow-thin"
local REFRESH_DEBOUNCE_MS = 80

local COLOR_QUEST_DEFAULT = { 0.75, 0.75, 0.75, 1 }
local COLOR_QUEST_TRACKED = { 1, 0.95, 0.6, 1 }
local COLOR_QUEST_ASSISTED = COLOR_QUEST_TRACKED
local COLOR_QUEST_WATCHED = { 0.9, 0.9, 0.9, 1 }
local COLOR_CATEGORY_COLLAPSED = COLOR_QUEST_DEFAULT
local COLOR_CATEGORY_EXPANDED = COLOR_QUEST_TRACKED
local COLOR_ROW_HOVER = { 1, 1, 0.6, 1 }

local RequestRefresh -- forward declaration for functions that trigger refreshes
local SetCategoryExpanded -- forward declaration for expansion helpers used before assignment
local SetQuestExpanded
local IsQuestExpanded -- forward declaration so earlier functions can query quest expansion state
local ForEachQuest -- forward declaration for quest iteration used by debug helpers
local ForEachQuestIndex -- forward declaration for quest index iteration used by debug helpers

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
    combatHidden = false,
    subscription = nil,
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
}

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

NVK_DEBUG_DESELECT = NVK_DEBUG_DESELECT or false

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

local function IsDebugLoggingEnabled()
    local sv = Nvk3UT and Nvk3UT.sv
    return sv and sv.debug == true
end

local function DebugLog(...)
    if not IsDebugLoggingEnabled() then
        return
    end

    if d then
        d(string.format("[%s]", MODULE_NAME), ...)
    elseif print then
        print("[" .. MODULE_NAME .. "]", ...)
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
    if not IsDebugLoggingEnabled() then
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

ForEachQuest = function(callback)
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

ForEachQuestIndex = function(callback)
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
                keys[category.key] = true
            end
            if category and category.parent and category.parent.key then
                keys[category.parent.key] = true
            end
        end
    end)

    return keys, found
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

local function UpdateTrackedQuestCache(forcedIndex)
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
        local cachedIndex = normalize(state.trackedQuestIndex)
        if cachedIndex then
            trackedIndex = cachedIndex
        end
    end

    local trackedCategories = {}

    if trackedIndex then
        trackedCategories = CollectCategoryKeysForQuest(trackedIndex)
    else
        ForEachQuest(function(quest)
            if trackedIndex or not (quest and quest.flags and quest.flags.tracked) then
                return
            end

            local fallbackIndex = normalize(quest.journalIndex) or tonumber(quest.journalIndex)
            if not fallbackIndex or fallbackIndex <= 0 then
                return
            end

            trackedIndex = fallbackIndex
            trackedCategories = CollectCategoryKeysForQuest(trackedIndex)
        end)
    end

    if type(trackedCategories) ~= "table" then
        trackedCategories = {}
    end

    if trackedIndex then
        state.pendingDeselection = false
    end

    state.trackedQuestIndex = trackedIndex
    state.trackedCategoryKeys = trackedCategories
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

local function ApplyImmediateTrackedQuest(journalIndex)
    if not journalIndex then
        return
    end

    state.lastTrackedBeforeSync = state.trackedQuestIndex
    local keys = CollectCategoryKeysForQuest(journalIndex)
    state.trackedCategoryKeys = keys
    state.trackedQuestIndex = journalIndex
    state.pendingDeselection = false
end

local function AutoExpandQuestForTracking(journalIndex, forceExpand, context)
    if not (state.saved and journalIndex) then
        return
    end

    if not forceExpand and state.saved.questExpanded[journalIndex] ~= nil then
        return
    end

    DebugDeselect("AutoExpandQuestForTracking", {
        journalIndex = journalIndex,
        forceExpand = tostring(forceExpand),
        previous = tostring(state.saved.questExpanded[journalIndex]),
    })
    local logContext = {
        trigger = (context and context.trigger) or "auto",
        source = (context and context.source) or "QuestTracker:AutoExpandQuestForTracking",
    }
    SetQuestExpanded(journalIndex, true, logContext)
end

local function EnsureTrackedCategoriesExpanded(journalIndex, forceExpand, context)
    if not (state.saved and journalIndex) then
        return
    end

    local keys = CollectCategoryKeysForQuest(journalIndex)

    local logContext
    local debugContext
    local debugEnabled = IsDebugLoggingEnabled()

    for key in pairs(keys) do
        if key then
            local savedValue = state.saved.catExpanded[key]
            local manualCollapsed = savedValue == false
            if manualCollapsed then
                if debugEnabled then
                    DebugLog(
                        "Respecting manual category collapse",
                        "category", key,
                        "journalIndex", journalIndex,
                        "trigger", (context and context.trigger) or "auto"
                    )
                end
            elseif forceExpand or savedValue == nil then
                if not logContext then
                    logContext = {
                        trigger = (context and context.trigger) or "auto",
                        source = (context and context.source) or "QuestTracker:EnsureTrackedCategoriesExpanded",
                    }
                    if debugEnabled then
                        debugContext = {
                            trigger = logContext.trigger,
                            source = logContext.source,
                            manualCollapseRespected = true,
                        }
                    end
                end
                SetCategoryExpanded(key, true, debugEnabled and debugContext or logContext)
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
    EnsureTrackedCategoriesExpanded(journalIndex, forceExpand, logContext)
    AutoExpandQuestForTracking(journalIndex, forceExpand, logContext)
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

        UpdateTrackedQuestCache(forcedIndex)
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

        if currentTracked and not skipVisibilityUpdate then
            DebugDeselect("SyncTrackedQuestState:ensure-visible", {
                index = currentTracked,
                shouldForceExpand = tostring(shouldForceExpand),
            })
            local visibilityContext = {
                trigger = trigger,
                source = source,
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

    local actionContext = {
        trigger = options.trigger or "auto",
        source = options.source or "QuestTracker:TrackQuestByJournalIndex",
    }

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
        ApplyImmediateTrackedQuest(numeric)
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
        RequestRefresh()
    end

    return true
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
        ApplyImmediateTrackedQuest(journalIndex)
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

local function OnTrackedQuestUpdate(_, trackingType, context)
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
    Nvk3UT.sv.QuestTracker = Nvk3UT.sv.QuestTracker or {}
    local saved = Nvk3UT.sv.QuestTracker
    saved.catExpanded = saved.catExpanded or {}
    saved.questExpanded = saved.questExpanded or {}
    state.saved = saved
end

local function ApplyFont(label, font)
    if not label or not label.SetFont then
        return
    end
    label:SetFont(font)
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
    if questData and state.trackedQuestIndex then
        isSelected = questData.journalIndex == state.trackedQuestIndex
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

local function IsCategoryExpanded(categoryKey)
    if not categoryKey then
        return state.opts.autoExpand ~= false
    end

    if state.saved then
        local savedValue = state.saved.catExpanded[categoryKey]
        if savedValue ~= nil then
            return savedValue
        end
    end

    if state.trackedCategoryKeys and state.trackedCategoryKeys[categoryKey] then
        return true
    end

    return state.opts.autoExpand ~= false
end

IsQuestExpanded = function(journalIndex)
    if not state.saved or not journalIndex then
        return state.opts.autoExpand ~= false
    end

    local savedValue = state.saved.questExpanded[journalIndex]
    if savedValue == nil then
        return state.opts.autoExpand ~= false
    end

    return savedValue
end

SetCategoryExpanded = function(categoryKey, expanded, context)
    if not (state.saved and categoryKey) then
        return false
    end

    local beforeExpanded = IsCategoryExpanded and IsCategoryExpanded(categoryKey)
    local newValue = not not expanded
    local oldValue = state.saved.catExpanded[categoryKey]
    if oldValue == newValue then
        return false
    end

    state.saved.catExpanded[categoryKey] = newValue
    DebugDeselect("SetCategoryExpanded", {
        categoryKey = categoryKey,
        previous = tostring(oldValue),
        newValue = tostring(newValue),
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
        newValue and "expand" or "collapse",
        (context and context.trigger) or "unknown",
        categoryKey,
        beforeExpanded,
        newValue,
        (context and context.source) or "QuestTracker:SetCategoryExpanded",
        extraFields
    )
    return true
end

SetQuestExpanded = function(journalIndex, expanded, context)
    if not (state.saved and journalIndex) then
        return false
    end

    local beforeExpanded = IsQuestExpanded and IsQuestExpanded(journalIndex)
    local newValue = not not expanded
    local oldValue = state.saved.questExpanded[journalIndex]
    if oldValue == newValue then
        return false
    end

    state.saved.questExpanded[journalIndex] = newValue
    DebugDeselect("SetQuestExpanded", {
        journalIndex = journalIndex,
        previous = tostring(oldValue),
        newValue = tostring(newValue),
    })
    LogQuestExpansion(
        newValue and "expand" or "collapse",
        (context and context.trigger) or "unknown",
        journalIndex,
        beforeExpanded,
        newValue,
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
        QuestTracker.Refresh()
    end

    return changed
end

local function FormatConditionText(condition)
    if not condition then
        return ""
    end

    local text = condition.text or ""
    local current = condition.current
    local maxValue = condition.max

    local hasCurrent = current ~= nil and current ~= ""
    local hasMax = maxValue ~= nil and maxValue ~= ""

    if hasCurrent and hasMax then
        return zo_strformat("<<1>> (<<2>>/<<3>>)", text, current, maxValue)
    elseif hasCurrent then
        return zo_strformat("<<1>> (<<2>>)", text, current)
    else
        return text
    end
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
    control.rowType = "category"
    ApplyLabelDefaults(control.label)
    ApplyToggleDefaults(control.toggle)
    ApplyFont(control.label, state.fonts.category)
    ApplyFont(control.toggle, state.fonts.toggle)
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
            control.iconSlot:SetAnchor(LEFT, control, LEFT, 0, 0)
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

                local nextExpanded = not IsQuestExpanded(journalIndex)
                state.pendingSelection = {
                    index = journalIndex,
                    expanded = nextExpanded,
                    forceExpand = nextExpanded,
                    trigger = "click",
                    source = "QuestTracker:OnRowClick",
                }

                local trackOptions = {
                    forceExpand = nextExpanded,
                    requestRefresh = false,
                    trigger = "click",
                    source = "QuestTracker:OnRowClick",
                }

                local tracked = TrackQuestByJournalIndex(journalIndex, trackOptions)

                if tracked then
                    OnTrackedQuestUpdate(nil, TRACK_TYPE_QUEST, {
                        trigger = "click",
                        source = "QuestTracker:OnRowClick",
                        forcedIndex = journalIndex,
                    })
                else
                    state.pendingSelection = nil
                    local changed = SetQuestExpanded(journalIndex, nextExpanded, {
                        trigger = "click",
                        source = "QuestTracker:OnRowClickFallback",
                    })
                    if changed then
                        QuestTracker.Refresh()
                    else
                        RequestRefresh()
                    end
                end
            elseif button == MOUSE_BUTTON_INDEX_RIGHT then
                if not ctrl.data or not ctrl.data.quest then
                    return
                end
                if not (ClearMenu and AddCustomMenuItem and ShowMenu) then
                    return
                end

                ClearMenu()
                local questData = ctrl.data.quest
                local journalIndex = questData.journalIndex
                local assisted = questData.flags and questData.flags.assisted
                local tracked = questData.flags and questData.flags.tracked

                local assistLabel = assisted and "Stop Assisting" or "Assist"
                AddCustomMenuItem(assistLabel, function()
                    local numericIndex = tonumber(journalIndex)
                    if not numericIndex then
                        return
                    end

                    if AssistJournalQuest and not assisted then
                        SafeCall(AssistJournalQuest, numericIndex)
                        return
                    end

                    if type(SetTrackedIsAssisted) == "function" and TRACK_TYPE_QUEST then
                        SafeCall(SetTrackedIsAssisted, TRACK_TYPE_QUEST, numericIndex, assisted and false or true)
                    end
                end)

                if tracked ~= false then
                    AddCustomMenuItem("Untrack", function()
                        if QUEST_JOURNAL_MANAGER and QUEST_JOURNAL_MANAGER.StopTrackingQuest then
                            QUEST_JOURNAL_MANAGER:StopTrackingQuest(journalIndex)
                        elseif SetTracked then
                            local ok = pcall(SetTracked, TRACK_TYPE_QUEST, journalIndex, false)
                            if not ok then
                                SetTracked(TRACK_TYPE_QUEST, journalIndex)
                            end
                        end
                    end)
                end

                AddCustomMenuItem("Show On Map", function()
                    if QUEST_JOURNAL_MANAGER and QUEST_JOURNAL_MANAGER.ShowQuestOnMap then
                        QUEST_JOURNAL_MANAGER:ShowQuestOnMap(journalIndex)
                    elseif ZO_WorldMap_ShowQuestOnMap then
                        ZO_WorldMap_ShowQuestOnMap(journalIndex)
                    end
                end)
                ShowMenu(ctrl)
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
    ApplyLabelDefaults(control.label)
    ApplyFont(control.label, state.fonts.quest)
    return control, key
end

local function AcquireConditionControl()
    local control, key = state.conditionPool:AcquireObject()
    if not control.initialized then
        control.label = control:GetNamedChild("Label")
        control.initialized = true
    end
    control.rowType = "condition"
    ApplyLabelDefaults(control.label)
    ApplyFont(control.label, state.fonts.condition)
    return control, key
end

local function ShouldDisplayCondition(condition)
    if not condition then
        return false
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

    local text = condition.text
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
    ApplyRowMetrics(control, CONDITION_INDENT_X, 0, 0, 0, CONDITION_MIN_HEIGHT)
    control:SetHidden(false)
    AnchorControl(control, CONDITION_INDENT_X)
end

local function LayoutQuest(quest)
    local control = AcquireQuestControl()
    control.data = { quest = quest }
    control.label:SetText(quest.name or "")
    local baseColor = COLOR_QUEST_DEFAULT
    local flags = quest.flags or {}
    if state.trackedQuestIndex and quest.journalIndex == state.trackedQuestIndex then
        baseColor = COLOR_QUEST_TRACKED
    elseif flags.assisted then
        baseColor = COLOR_QUEST_ASSISTED
    elseif flags.tracked then
        baseColor = COLOR_QUEST_WATCHED
    end
    control.baseColor = baseColor
    if control.label then
        control.label:SetColor(unpack(baseColor))
    end

    local expanded = IsQuestExpanded(quest.journalIndex)
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
    local count = #category.quests
    control.label:SetText(FormatCategoryHeaderText(category.name or "", count, "quest"))
    local expanded = IsCategoryExpanded(category.key)
    local baseColor = expanded and COLOR_CATEGORY_EXPANDED or COLOR_CATEGORY_COLLAPSED
    control.baseColor = baseColor
    if control.label then
        control.label:SetColor(unpack(baseColor))
    end
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

local function Rebuild()
    if not state.container then
        return
    end

    EnsurePools()

    ReleaseAll(state.categoryPool)
    ReleaseAll(state.questPool)
    ReleaseAll(state.conditionPool)
    ResetLayoutState()

    if not state.snapshot or not state.snapshot.categories or not state.snapshot.categories.ordered then
        UpdateContentSize()
        NotifyHostContentChanged()
        return
    end

    for index = 1, #state.snapshot.categories.ordered do
        local category = state.snapshot.categories.ordered[index]
        if category and category.quests and #category.quests > 0 then
            LayoutCategory(category)
        end
    end

    UpdateContentSize()
    NotifyHostContentChanged()
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

local function OnSnapshotUpdated(snapshot)
    state.snapshot = snapshot
    UpdateTrackedQuestCache()
    if state.trackedQuestIndex then
        EnsureTrackedQuestVisible(state.trackedQuestIndex, nil, {
            trigger = "refresh",
            source = "QuestTracker:OnSnapshotUpdated",
        })
    end
    if state.isInitialized then
        Rebuild()
    end
    NotifyStatusRefresh()
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

    state.subscription = function(snapshot)
        OnSnapshotUpdated(snapshot)
    end

    if Nvk3UT.QuestModel and Nvk3UT.QuestModel.Subscribe then
        Nvk3UT.QuestModel.Subscribe(state.subscription)
        state.snapshot = Nvk3UT.QuestModel.GetSnapshot and Nvk3UT.QuestModel.GetSnapshot() or state.snapshot
        UpdateTrackedQuestCache()
    else
        DebugLog("QuestModel is not available")
    end

    RegisterTrackingEvents()

    state.isInitialized = true
    RefreshVisibility()
    AdoptTrackedQuestOnInit()
    Rebuild()
end

function QuestTracker.Refresh()
    Rebuild()
end

function QuestTracker.Shutdown()
    if not state.isInitialized then
        return
    end

    if state.subscription and Nvk3UT.QuestModel and Nvk3UT.QuestModel.Unsubscribe then
        Nvk3UT.QuestModel.Unsubscribe(state.subscription)
    end
    state.subscription = nil

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
    state.control = nil
    state.snapshot = nil
    state.orderedControls = {}
    state.lastAnchoredControl = nil
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
