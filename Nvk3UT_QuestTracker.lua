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

local ICON_EXPANDED = "\226\150\190" -- ▼
local ICON_COLLAPSED = "\226\150\182" -- ▶
local ICON_TRACKED = "\226\152\133" -- ★

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
local QUEST_TOGGLE_WIDTH = 18

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
    if toggle and toggle.GetWidth then
        local width = toggle:GetWidth()
        if width and width > 0 then
            return width
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
            GetToggleWidth(control.toggle, QUEST_TOGGLE_WIDTH),
            TOGGLE_LABEL_PADDING_X,
            0,
            QUEST_MIN_HEIGHT
        )
    elseif rowType == "condition" then
        ApplyRowMetrics(control, indent, 0, 0, 0, CONDITION_MIN_HEIGHT)
    end
end

local function DebugLog(...)
    if not state.opts.debug then
        return
    end

    if d then
        d(string.format("[%s]", MODULE_NAME), ...)
    elseif print then
        print("[" .. MODULE_NAME .. "]", ...)
    end
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
                keys[category.key] = true
            end
            if category and category.parent and category.parent.key then
                keys[category.parent.key] = true
            end
        end
    end)

    return keys, found
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
    local trackedIndex = nil
    if forcedIndex ~= nil then
        local numeric = tonumber(forcedIndex)
        if numeric and numeric > 0 then
            trackedIndex = numeric
        end
    end

    if not trackedIndex then
        trackedIndex = GetFocusedQuestIndex()
    end

    if (not trackedIndex or trackedIndex <= 0) and GetTrackedQuestIndex then
        local ok, current = SafeCall(GetTrackedQuestIndex)
        if ok then
            local numeric = tonumber(current)
            if numeric and numeric > 0 then
                trackedIndex = numeric
            end
        end
    end

    local trackedCategories = {}
    local fallbackTrackedIndex = nil

    ForEachQuest(function(quest, category)
        if quest.flags and quest.flags.tracked then
            fallbackTrackedIndex = fallbackTrackedIndex or quest.journalIndex
        end
        if trackedIndex and quest.journalIndex == trackedIndex then
            if category and category.key then
                trackedCategories[category.key] = true
            end
            if category and category.parent and category.parent.key then
                trackedCategories[category.parent.key] = true
            end
        end
    end)

    if trackedIndex and next(trackedCategories) == nil then
        local keys = CollectCategoryKeysForQuest(trackedIndex)
        trackedCategories = keys
    end

    if not trackedIndex and fallbackTrackedIndex then
        trackedIndex = fallbackTrackedIndex
        local keys = CollectCategoryKeysForQuest(trackedIndex)
        for key in pairs(keys) do
            trackedCategories[key] = true
        end
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
    if SetTrackedIsAssisted then
        ForEachQuestIndex(function(index)
            if index == journalIndex then
                SafeCall(SetTrackedIsAssisted, TRACK_TYPE_QUEST, index, true)
            elseif GetTrackedIsAssisted and GetTrackedIsAssisted(TRACK_TYPE_QUEST, index) then
                SafeCall(SetTrackedIsAssisted, TRACK_TYPE_QUEST, index, false)
            end
        end)
    elseif AssistJournalQuest then
        SafeCall(AssistJournalQuest, journalIndex)
    end
end

local function ApplyImmediateTrackedQuest(journalIndex)
    if not journalIndex then
        return
    end

    local keys = CollectCategoryKeysForQuest(journalIndex)
    state.trackedCategoryKeys = keys
    state.trackedQuestIndex = journalIndex
end

local function AutoExpandQuestForTracking(journalIndex)
    if not (state.saved and journalIndex) then
        return
    end

    if state.saved.questExpanded[journalIndex] ~= nil then
        return
    end

    state.saved.questExpanded[journalIndex] = true
end

local function EnsureTrackedCategoriesExpanded(journalIndex)
    if not (state.saved and journalIndex) then
        return
    end

    local keys = CollectCategoryKeysForQuest(journalIndex)

    for key in pairs(keys) do
        if key and state.saved.catExpanded[key] == nil then
            state.saved.catExpanded[key] = true
        end
    end
end

local function EnsureTrackedQuestVisible(journalIndex)
    if not journalIndex then
        return
    end

    EnsureTrackedCategoriesExpanded(journalIndex)
    AutoExpandQuestForTracking(journalIndex)
end

local function SyncTrackedQuestState(forcedIndex)
    local previousTracked = state.trackedQuestIndex

    UpdateTrackedQuestCache(forcedIndex)

    local currentTracked = state.trackedQuestIndex
    if currentTracked then
        EnsureTrackedQuestVisible(currentTracked)
    end

    if not state.isInitialized then
        return
    end

    local hasTracked = currentTracked ~= nil
    local hadTracked = previousTracked ~= nil

    if RequestRefresh and (previousTracked ~= currentTracked or hasTracked or hadTracked) then
        RequestRefresh()
    end
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

local function TrackQuestByJournalIndex(journalIndex)
    local numeric = tonumber(journalIndex)
    if not numeric or numeric <= 0 then
        return
    end

    if state.opts.autoTrack == false then
        return
    end

    AutoExpandQuestForTracking(numeric)
    EnsureTrackedCategoriesExpanded(numeric)

    ApplyImmediateTrackedQuest(numeric)

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

    RequestRefresh()
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

    EnsureTrackedQuestVisible(journalIndex)

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
        TrackQuestByJournalIndex(journalIndex)
        return
    end

    ForceAssistTrackedQuest(journalIndex)
    EnsureQuestTrackedState(journalIndex)
    ClearOtherTrackedQuests(journalIndex)
    EnsureExclusiveAssistedQuest(journalIndex)
end

local function OnTrackedQuestUpdate(_, trackingType)
    if trackingType and trackingType ~= TRACK_TYPE_QUEST then
        return
    end

    SyncTrackedQuestState()
end

local function OnFocusedTrackerAssistChanged(_, assistedData)
    local questIndex = assistedData and assistedData.arg1
    if questIndex ~= nil then
        local numeric = tonumber(questIndex)
        if numeric and numeric > 0 then
            SyncTrackedQuestState(numeric)
            return
        end
    end

    SyncTrackedQuestState()
end

local function OnPlayerActivated()
    local function execute()
        SyncTrackedQuestState()
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

local function UpdateCategoryToggle(control, expanded)
    if control.toggle then
        control.toggle:SetText(expanded and ICON_EXPANDED or ICON_COLLAPSED)
    end
end

local function UpdateQuestToggle(control, expanded)
    if not (control and control.toggle) then
        return
    end

    local icon = expanded and ICON_EXPANDED or ICON_COLLAPSED
    local questData = control.data and control.data.quest
    if questData and state.trackedQuestIndex and questData.journalIndex == state.trackedQuestIndex then
        icon = ICON_TRACKED
    end

    control.toggle:SetText(icon)
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

local function IsQuestExpanded(journalIndex)
    if not state.saved or not journalIndex then
        return state.opts.autoExpand ~= false
    end

    local savedValue = state.saved.questExpanded[journalIndex]
    if savedValue == nil then
        return state.opts.autoExpand ~= false
    end

    return savedValue
end

local function SetCategoryExpanded(categoryKey, expanded)
    if not (state.saved and categoryKey) then
        return false
    end

    local newValue = not not expanded
    if state.saved.catExpanded[categoryKey] == newValue then
        return false
    end

    state.saved.catExpanded[categoryKey] = newValue
    return true
end

local function SetQuestExpanded(journalIndex, expanded)
    if not (state.saved and journalIndex) then
        return false
    end

    local newValue = not not expanded
    if state.saved.questExpanded[journalIndex] == newValue then
        return false
    end

    state.saved.questExpanded[journalIndex] = newValue
    return true
end

local function ToggleQuestExpansion(journalIndex)
    if not journalIndex then
        return false
    end

    local expanded = IsQuestExpanded(journalIndex)
    local changed = SetQuestExpanded(journalIndex, not expanded)
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
        control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
            if not upInside or button ~= MOUSE_BUTTON_INDEX_LEFT then
                return
            end
            local catKey = ctrl.data and ctrl.data.categoryKey
            if not catKey then
                return
            end
            local expanded = not IsCategoryExpanded(catKey)
            local changed = SetCategoryExpanded(catKey, expanded)
            if changed then
                QuestTracker.Refresh()
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
        control.toggle = control:GetNamedChild("Toggle")
        if control.toggle and control.toggle.SetMouseEnabled then
            control.toggle:SetMouseEnabled(true)
        end
        if control.toggle then
            control.toggle:SetHandler("OnMouseUp", function(toggleCtrl, button, upInside)
                if not upInside or button ~= MOUSE_BUTTON_INDEX_LEFT then
                    return
                end
                local parent = toggleCtrl:GetParent()
                local questData = parent and parent.data and parent.data.quest
                if not questData then
                    return
                end
                local journalIndex = questData.journalIndex
                ToggleQuestExpansion(journalIndex)
            end)
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
                if ctrl.toggle then
                    local toggleIsMouseOver = ctrl.toggle.IsMouseOver
                    if type(toggleIsMouseOver) == "function" then
                        toggleMouseOver = toggleIsMouseOver(ctrl.toggle)
                    end
                end

                if toggleMouseOver then
                    ToggleQuestExpansion(journalIndex)
                    return
                end

                if state.opts.autoTrack == false then
                    ToggleQuestExpansion(journalIndex)
                    return
                end

                local wasTracked = state.trackedQuestIndex and state.trackedQuestIndex == journalIndex

                TrackQuestByJournalIndex(journalIndex)

                if wasTracked then
                    ToggleQuestExpansion(journalIndex)
                else
                    local changed = SetQuestExpanded(journalIndex, true)
                    if changed then
                        QuestTracker.Refresh()
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
                    if SetTrackedIsAssisted then
                        SetTrackedIsAssisted(TRACK_TYPE_QUEST, journalIndex, not assisted)
                    elseif AssistJournalQuest and not assisted then
                        AssistJournalQuest(journalIndex)
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
    ApplyToggleDefaults(control.toggle)
    ApplyFont(control.label, state.fonts.quest)
    ApplyFont(control.toggle, state.fonts.toggle)
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
        if control.toggle then
            control.toggle:SetText(ICON_COLLAPSED)
        end
    end

    state.categoryPool:SetCustomResetBehavior(resetControl)
    state.questPool:SetCustomResetBehavior(function(control)
        resetControl(control)
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
    UpdateQuestToggle(control, expanded)
    ApplyRowMetrics(
        control,
        QUEST_INDENT_X,
        GetToggleWidth(control.toggle, QUEST_TOGGLE_WIDTH),
        TOGGLE_LABEL_PADDING_X,
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
        EnsureTrackedQuestVisible(state.trackedQuestIndex)
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
