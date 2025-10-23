local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local QuestTracker = {}
QuestTracker.__index = QuestTracker

local MODULE_NAME = addonName .. "QuestTracker"
local EVENT_NAMESPACE = MODULE_NAME .. "_Event"

local ICON_EXPANDED = "\226\150\190" -- ▼
local ICON_COLLAPSED = "\226\150\182" -- ▶

local CATEGORY_INDENT_X = 0
local QUEST_INDENT_X = 18
local CONDITION_INDENT_X = 36
local VERTICAL_PADDING = 3

local DEFAULT_FONTS = {
    category = "ZoFontGameBold",
    quest = "ZoFontGame",
    condition = "ZoFontGameSmall",
    toggle = "ZoFontGame",
}

local DEFAULT_FONT_OUTLINE = "soft-shadow-thin"
local REFRESH_DEBOUNCE_MS = 80

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
    previousDefaultTrackerHidden = nil,
    pendingRefresh = false,
}

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

local function RequestRefresh()
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
        control:SetAnchor(TOPLEFT, state.lastAnchoredControl, BOTTOMLEFT, indentX, VERTICAL_PADDING)
        control:SetAnchor(TOPRIGHT, state.lastAnchoredControl, BOTTOMRIGHT, 0, VERTICAL_PADDING)
    else
        control:SetAnchor(TOPLEFT, state.container, TOPLEFT, indentX, 0)
        control:SetAnchor(TOPRIGHT, state.container, TOPRIGHT, 0, 0)
    end

    state.lastAnchoredControl = control
    state.orderedControls[#state.orderedControls + 1] = control
    control.currentIndent = indentX
end

local function UpdateAutoSize()
    if not state.control then
        return
    end

    local maxWidth = 0
    local totalHeight = 0
    local visibleCount = 0

    for index = 1, #state.orderedControls do
        local control = state.orderedControls[index]
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

    if state.opts.autoGrowH and maxWidth > 0 then
        state.control:SetWidth(maxWidth)
    end

    if state.opts.autoGrowV then
        state.control:SetHeight(totalHeight)
    end
end

local function UpdateCategoryToggle(control, expanded)
    if control.toggle then
        control.toggle:SetText(expanded and ICON_EXPANDED or ICON_COLLAPSED)
    end
end

local function UpdateQuestToggle(control, expanded)
    if control.toggle then
        control.toggle:SetText(expanded and ICON_EXPANDED or ICON_COLLAPSED)
    end
end

local function IsCategoryExpanded(categoryKey)
    if not state.saved or not categoryKey then
        return state.opts.autoExpand ~= false
    end

    local savedValue = state.saved.catExpanded[categoryKey]
    if savedValue == nil then
        return state.opts.autoExpand ~= false
    end

    return savedValue
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
    if state.saved and categoryKey then
        state.saved.catExpanded[categoryKey] = not not expanded
    end
end

local function SetQuestExpanded(journalIndex, expanded)
    if state.saved and journalIndex then
        state.saved.questExpanded[journalIndex] = not not expanded
    end
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
            SetCategoryExpanded(catKey, expanded)
            QuestTracker.Refresh()
        end)
        control.initialized = true
    end
    ApplyFont(control.label, state.fonts.category)
    ApplyFont(control.toggle, state.fonts.toggle)
    return control, key
end

local function AcquireQuestControl()
    local control, key = state.questPool:AcquireObject()
    if not control.initialized then
        control.label = control:GetNamedChild("Label")
        control.toggle = control:GetNamedChild("Toggle")
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
                local expanded = not IsQuestExpanded(journalIndex)
                SetQuestExpanded(journalIndex, expanded)
                QuestTracker.Refresh()
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
                ctrl.label:SetColor(1, 1, 0.6, 1)
            end
        end)
        control:SetHandler("OnMouseExit", function(ctrl)
            if ctrl.label and ctrl.baseColor then
                ctrl.label:SetColor(unpack(ctrl.baseColor))
            end
        end)
        control.initialized = true
    end
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
    end

    state.categoryPool:SetCustomResetBehavior(resetControl)
    state.questPool:SetCustomResetBehavior(function(control)
        resetControl(control)
        control.baseColor = nil
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
    control:SetHidden(false)
    AnchorControl(control, CONDITION_INDENT_X)
end

local function LayoutQuest(quest)
    local control = AcquireQuestControl()
    control.data = { quest = quest }
    control.label:SetText(quest.name or "")
    local baseColor = { 1, 1, 1, 1 }
    if quest.flags then
        if quest.flags.assisted then
            baseColor = { 1, 0.95, 0.6, 1 }
        elseif quest.flags.tracked then
            baseColor = { 0.9, 0.9, 0.9, 1 }
        else
            baseColor = { 0.75, 0.75, 0.75, 1 }
        end
    end
    control.baseColor = baseColor
    if control.label then
        control.label:SetColor(unpack(baseColor))
    end

    local expanded = IsQuestExpanded(quest.journalIndex)
    UpdateQuestToggle(control, expanded)
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
    control.data = { categoryKey = category.key }
    local count = #category.quests
    control.label:SetText(string.format("%s (%d)", category.name or "", count))
    local expanded = IsCategoryExpanded(category.key)
    UpdateCategoryToggle(control, expanded)
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
        UpdateAutoSize()
        return
    end

    for index = 1, #state.snapshot.categories.ordered do
        local category = state.snapshot.categories.ordered[index]
        if category and category.quests and #category.quests > 0 then
            LayoutCategory(category)
        end
    end

    UpdateAutoSize()
end

local function ApplyLockState()
    if not state.control or not state.control.SetMovable then
        return
    end
    local lock = state.opts.lock
    if lock == nil then
        return
    end
    state.control:SetMovable(not lock)
end

local function ApplyHideDefaultTracker()
    if not ZO_QuestTracker then
        return
    end
    if state.opts.hideDefault == nil then
        return
    end
    if state.previousDefaultTrackerHidden == nil then
        state.previousDefaultTrackerHidden = ZO_QuestTracker:IsHidden()
    end
    ZO_QuestTracker:SetHidden(state.opts.hideDefault)
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
    if state.isInitialized then
        Rebuild()
    end
end

function QuestTracker.Init(parentControl, opts)
    if state.isInitialized then
        return
    end

    assert(parentControl ~= nil, "QuestTracker.Init requires a parent control")

    state.control = parentControl
    state.container = WINDOW_MANAGER:CreateControl(nil, parentControl, CT_CONTROL)
    state.container:SetResizeToFitDescendents(true)
    state.control.holder = state.container

    EnsureSavedVars()
    state.opts = {}
    state.fonts = {}

    QuestTracker.ApplyTheme(state.saved or {})
    QuestTracker.ApplySettings(state.saved or {})

    if opts then
        QuestTracker.ApplyTheme(opts)
        QuestTracker.ApplySettings(opts)
    end

    ApplyContainerPadding()
    AttachBackdrop()
    ApplyLockState()
    ApplyHideDefaultTracker()
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
    else
        DebugLog("QuestModel is not available")
    end

    state.isInitialized = true
    RefreshVisibility()
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

    if state.container then
        if state.container.Destroy then
            state.container:Destroy()
        else
            state.container:SetHidden(true)
            state.container:SetParent(nil)
        end
        state.container = nil
    end

    if state.previousDefaultTrackerHidden ~= nil and ZO_QuestTracker then
        ZO_QuestTracker:SetHidden(state.previousDefaultTrackerHidden)
    end

    if state.control then
        state.control.holder = nil
    end
    state.control = nil
    state.snapshot = nil
    state.orderedControls = {}
    state.lastAnchoredControl = nil
    state.isInitialized = false
    state.previousDefaultTrackerHidden = nil
    state.opts = {}
    state.fonts = {}
    state.pendingRefresh = false
end

function QuestTracker.SetActive(active)
    state.opts.active = active
    RefreshVisibility()
end

local function ApplyAutoGrow(settings)
    if type(settings) ~= "table" then
        return
    end

    if settings.autoGrowV ~= nil then
        state.opts.autoGrowV = settings.autoGrowV and true or false
    end

    if settings.autoGrowH ~= nil then
        state.opts.autoGrowH = settings.autoGrowH and true or false
    end
end

function QuestTracker.ApplySettings(settings)
    if type(settings) ~= "table" then
        return
    end

    state.opts.lock = settings.lock ~= nil and settings.lock or state.opts.lock
    state.opts.hideDefault = settings.hideDefault ~= nil and settings.hideDefault or state.opts.hideDefault
    state.opts.hideInCombat = settings.hideInCombat and true or false
    state.opts.autoExpand = settings.autoExpand ~= false
    state.opts.active = (settings.active ~= false)

    ApplyAutoGrow(settings)

    ApplyLockState()
    ApplyHideDefaultTracker()

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

function QuestTracker.RequestRefresh()
    RequestRefresh()
end

Nvk3UT.QuestTracker = QuestTracker

return QuestTracker
