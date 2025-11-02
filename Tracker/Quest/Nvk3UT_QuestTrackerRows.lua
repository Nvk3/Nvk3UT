local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

Rows.isInitialized = false

local MODULE_NAME = addonName .. "QuestTrackerRows"

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

local CATEGORY_TOGGLE_WIDTH = 20
local QUEST_ICON_SLOT_WIDTH = 18
local QUEST_ICON_SLOT_HEIGHT = 18
local QUEST_ICON_SLOT_PADDING_X = 6
local ROW_TEXT_PADDING_Y = 8
local CATEGORY_MIN_HEIGHT = 26
local QUEST_MIN_HEIGHT = 24
local CONDITION_MIN_HEIGHT = 20

local DEFAULT_FONTS = {
    category = "$(BOLD_FONT)|20|soft-shadow-thick",
    quest = "$(BOLD_FONT)|16|soft-shadow-thick",
    condition = "$(BOLD_FONT)|14|soft-shadow-thick",
    toggle = "$(BOLD_FONT)|20|soft-shadow-thick",
}

local COLOR_ROW_HOVER = { 1, 1, 0.6, 1 }

local state = {
    parent = nil,
    pools = {},
    active = {},
    contentWidth = 0,
    interactiveCache = {},
}

local function IsDebugLoggingEnabled()
    local sv = Nvk3UT and Nvk3UT.sv
    return sv and sv.debug == true
end

local function DebugLog(message)
    if not IsDebugLoggingEnabled() then
        return
    end

    if d then
        d(string.format("[%s] %s", MODULE_NAME, tostring(message)))
    elseif print then
        print(string.format("[%s] %s", MODULE_NAME, tostring(message)))
    end
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

local function ApplyFont(label, font, fallback)
    if not label or not label.SetFont then
        return
    end

    local resolved = font
    if not resolved or resolved == "" then
        resolved = fallback
    end

    if not resolved or resolved == "" then
        return
    end

    label:SetFont(resolved)
end

local function ApplyBaseColor(control, baseColor)
    if not control then
        return
    end

    local color = control.baseColor
    if type(color) ~= "table" then
        color = {}
        control.baseColor = color
    end

    color[1] = baseColor and baseColor[1] or 1
    color[2] = baseColor and baseColor[2] or 1
    color[3] = baseColor and baseColor[3] or 1
    color[4] = baseColor and baseColor[4] or 1

    if control.label and control.label.SetColor then
        control.label:SetColor(color[1], color[2], color[3], color[4])
    end
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

local function UpdateQuestIconSlot(control, rowData)
    if not (control and control.iconSlot) then
        return
    end

    local isSelected = rowData and rowData.isSelected
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

local function ApplyRowMetrics(control, indent, toggleWidth, leftPadding, rightPadding, minHeight)
    if not control or not control.label then
        return
    end

    indent = indent or 0
    toggleWidth = toggleWidth or 0
    leftPadding = leftPadding or 0
    rightPadding = rightPadding or 0

    local availableWidth = (state.contentWidth or 0) - indent - toggleWidth - leftPadding - rightPadding
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
            control.toggle and control.togglePaddingX or 4,
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

local function ResetCommon(control)
    if not control then
        return
    end

    control:SetHidden(true)
    control.data = nil
    control.rowData = nil
    control.rowContext = nil
    control.isExpanded = nil
    control.baseColor = nil
    control.currentIndent = nil
end

local function ResetCategoryControl(control)
    ResetCommon(control)
    if control.label and control.label.SetText then
        control.label:SetText("")
    end
    if control.toggle and control.toggle.SetTexture then
        control.toggle:SetTexture(SelectCategoryToggleTexture(false, false))
    end
    if control.toggle and control.toggle.SetHidden then
        control.toggle:SetHidden(false)
    end
end

local function ResetQuestControl(control)
    ResetCommon(control)
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
end

local function ResetConditionControl(control)
    ResetCommon(control)
    if control.label and control.label.SetText then
        control.label:SetText("")
    end
end

local function CategoryOnMouseUp(ctrl, button, upInside)
    if not upInside or button ~= MOUSE_BUTTON_INDEX_LEFT then
        return
    end

    local context = ctrl.rowContext
    if not context then
        return
    end

    local categoryKey = ctrl.data and ctrl.data.categoryKey
    if not categoryKey then
        return
    end

    local isExpanded = context.IsCategoryExpanded and context.IsCategoryExpanded(categoryKey)
    local changed
    if context.SetCategoryExpanded then
        changed = context.SetCategoryExpanded(categoryKey, not isExpanded, context.clickContext)
    end

    if changed and context.Refresh then
        context.Refresh()
    end
end

local function CategoryOnMouseEnter(ctrl)
    local context = ctrl.rowContext
    if context and ctrl.label and context.hoverColor then
        ctrl.label:SetColor(unpack(context.hoverColor))
    end

    local expanded = ctrl.isExpanded
    if expanded == nil and context and context.IsCategoryExpanded then
        local categoryKey = ctrl.data and ctrl.data.categoryKey
        expanded = context.IsCategoryExpanded(categoryKey)
    end

    UpdateCategoryToggle(ctrl, expanded)
end

local function CategoryOnMouseExit(ctrl)
    local context = ctrl.rowContext
    if ctrl.label and ctrl.baseColor then
        ctrl.label:SetColor(unpack(ctrl.baseColor))
    end

    local expanded = ctrl.isExpanded
    if expanded == nil and context and context.IsCategoryExpanded then
        local categoryKey = ctrl.data and ctrl.data.categoryKey
        expanded = context.IsCategoryExpanded(categoryKey)
    end

    UpdateCategoryToggle(ctrl, expanded)
end

local function QuestIconOnMouseUp(toggleCtrl, button, upInside)
    if not upInside or button ~= MOUSE_BUTTON_INDEX_LEFT then
        return
    end

    local parent = toggleCtrl:GetParent()
    if not parent then
        return
    end

    local context = parent.rowContext
    local questData = parent.data and parent.data.quest
    if not (context and questData and context.ToggleQuestExpansion) then
        return
    end

    context.ToggleQuestExpansion(questData.journalIndex, context.iconToggleContext)
end

local function QuestOnMouseUp(ctrl, button, upInside)
    if not upInside then
        return
    end

    local context = ctrl.rowContext
    if not context then
        return
    end

    if button == MOUSE_BUTTON_INDEX_LEFT then
        local questData = ctrl.data and ctrl.data.quest
        if not (questData and questData.journalIndex) then
            return
        end

        local toggleMouseOver = false
        if ctrl.iconSlot then
            local toggleIsMouseOver = ctrl.iconSlot.IsMouseOver
            if type(toggleIsMouseOver) == "function" then
                toggleMouseOver = toggleIsMouseOver(ctrl.iconSlot)
            end
        end

        if toggleMouseOver then
            if context.ToggleQuestExpansion then
                context.ToggleQuestExpansion(questData.journalIndex, context.rowToggleContext)
            end
            return
        end

        if context.autoTrackEnabled == false then
            if context.ToggleQuestExpansion then
                context.ToggleQuestExpansion(questData.journalIndex, context.manualToggleContext)
            end
            return
        end

        if context.HandleQuestRowClick then
            context.HandleQuestRowClick(questData.journalIndex)
        end
    elseif button == MOUSE_BUTTON_INDEX_RIGHT then
        local questData = ctrl.data and ctrl.data.quest
        if not (questData and questData.journalIndex) then
            return
        end

        if context.ShowQuestContextMenu then
            context.ShowQuestContextMenu(ctrl, questData.journalIndex)
        end
    end
end

local function QuestOnMouseEnter(ctrl)
    if ctrl.label then
        ctrl.label:SetColor(unpack(COLOR_ROW_HOVER))
    end
end

local function QuestOnMouseExit(ctrl)
    if ctrl.label and ctrl.baseColor then
        ctrl.label:SetColor(unpack(ctrl.baseColor))
    end
end

local function EnsureCategoryInitialized(control)
    if control.__nvk_categoryInitialized then
        return
    end

    control.label = control:GetNamedChild("Label")
    control.toggle = control:GetNamedChild("Toggle")
    control.togglePaddingX = 4

    ApplyLabelDefaults(control.label)
    ApplyToggleDefaults(control.toggle)

    control:SetHandler("OnMouseUp", CategoryOnMouseUp)
    control:SetHandler("OnMouseEnter", CategoryOnMouseEnter)
    control:SetHandler("OnMouseExit", CategoryOnMouseExit)

    control.__nvk_categoryInitialized = true
end

local function EnsureQuestInitialized(control)
    if control.__nvk_questInitialized then
        return
    end

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
        control.iconSlot:SetHandler("OnMouseUp", QuestIconOnMouseUp)
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

    ApplyLabelDefaults(control.label)

    control:SetHandler("OnMouseUp", QuestOnMouseUp)
    control:SetHandler("OnMouseEnter", QuestOnMouseEnter)
    control:SetHandler("OnMouseExit", QuestOnMouseExit)

    control.__nvk_questInitialized = true
end

local function EnsureConditionInitialized(control)
    if control.__nvk_conditionInitialized then
        return
    end

    control.label = control:GetNamedChild("Label")
    ApplyLabelDefaults(control.label)

    control.__nvk_conditionInitialized = true
end

local function AcquireFromPool(rowType)
    if not state.parent then
        return nil
    end

    local pool = state.pools[rowType]
    if not pool then
        return nil
    end

    local control, key = pool:AcquireObject()
    if not control then
        return nil
    end

    control.__poolKey = key
    control.__poolType = rowType
    control:SetParent(state.parent)
    control:SetHidden(true)
    control.rowType = rowType
    control.RefreshRowMetrics = RefreshControlMetrics

    if rowType == "category" then
        EnsureCategoryInitialized(control)
    elseif rowType == "quest" then
        EnsureQuestInitialized(control)
    else
        EnsureConditionInitialized(control)
    end

    state.active[#state.active + 1] = control
    return control
end

function Rows:Init(parentControl)
    state.parent = parentControl
    state.active = {}
    local cache = state.interactiveCache
    if type(cache) == "table" then
        for index = #cache, 1, -1 do
            cache[index] = nil
        end
    end

    state.pools.category = ZO_ControlPool:New("CategoryHeader_Template", parentControl)
    state.pools.quest = ZO_ControlPool:New("QuestHeader_Template", parentControl)
    state.pools.condition = ZO_ControlPool:New("QuestCondition_Template", parentControl)

    state.pools.category:SetCustomResetBehavior(ResetCategoryControl)
    state.pools.quest:SetCustomResetBehavior(ResetQuestControl)
    state.pools.condition:SetCustomResetBehavior(ResetConditionControl)

    Rows.isInitialized = true

    DebugLog("Initialized row pools")
end

function Rows:ReleaseAll()
    for index = 1, #state.active do
        local control = state.active[index]
        if control then
            local poolType = control.__poolType
            local pool = poolType and state.pools[poolType]
            if pool and control.__poolKey then
                pool:ReleaseObject(control.__poolKey)
            end
        end
    end

    state.active = {}

    local cache = state.interactiveCache
    if type(cache) == "table" then
        for index = #cache, 1, -1 do
            cache[index] = nil
        end
    end
end

function Rows:Acquire(rowType)
    rowType = rowType or "quest"

    local control = AcquireFromPool(rowType)
    if not control and IsDebugLoggingEnabled() then
        DebugLog(string.format("Failed to acquire control for rowType=%s", tostring(rowType)))
    end

    return control
end

function Rows:SetContentWidth(width)
    state.contentWidth = width or 0
end

function Rows:GetInteractiveControls()
    local cache = state.interactiveCache
    if type(cache) ~= "table" then
        cache = {}
        state.interactiveCache = cache
    end

    for index = #cache, 1, -1 do
        cache[index] = nil
    end

    local active = state.active
    if type(active) ~= "table" then
        return cache
    end

    local count = 0
    for index = 1, #active do
        local control = active[index]
        if control then
            if control.SetMouseEnabled then
                count = count + 1
                cache[count] = control
            end

            local toggle = control.toggle
            if toggle and toggle.SetMouseEnabled then
                count = count + 1
                cache[count] = toggle
            end

            local iconSlot = control.iconSlot
            if iconSlot and iconSlot.SetMouseEnabled then
                count = count + 1
                cache[count] = iconSlot
            end
        end
    end

    return cache
end

local function ApplyCategoryRowData(control, rowData)
    control.rowContext = rowData.context
    control.data = rowData.data

    local label = control and control.label
    local toggle = control and control.toggle

    ApplyFont(label, rowData.fonts and rowData.fonts.label, DEFAULT_FONTS.category)
    ApplyFont(toggle, rowData.fonts and rowData.fonts.toggle, DEFAULT_FONTS.toggle)

    if label and label.SetText then
        label:SetText(rowData.labelText or "")
    end
    ApplyBaseColor(control, rowData.baseColor)

    UpdateCategoryToggle(control, rowData.isExpanded)
end

local function ApplyQuestRowData(control, rowData)
    control.rowContext = rowData.context
    control.data = { quest = rowData.quest }

    local label = control and control.label

    ApplyFont(label, rowData.fonts and rowData.fonts.label, DEFAULT_FONTS.quest)

    if label and label.SetText then
        label:SetText(rowData.labelText or "")
    end
    ApplyBaseColor(control, rowData.baseColor)

    UpdateQuestIconSlot(control, rowData)
    control.isExpanded = rowData.isExpanded
end

local function ApplyConditionRowData(control, rowData)
    control.rowContext = rowData.context
    control.data = rowData.data

    local label = control and control.label

    ApplyFont(label, rowData.fonts and rowData.fonts.label, DEFAULT_FONTS.condition)

    if label and label.SetText then
        label:SetText(rowData.labelText or "")
    end
    ApplyBaseColor(control, rowData.baseColor)
end

function Rows:ApplyRowData(control, rowData)
    if not (control and rowData) then
        return 0
    end

    control.rowData = rowData

    if rowData.rowType == "category" then
        ApplyCategoryRowData(control, rowData)
    elseif rowData.rowType == "quest" then
        ApplyQuestRowData(control, rowData)
    else
        ApplyConditionRowData(control, rowData)
    end

    if control.SetHidden then
        control:SetHidden(false)
    end
    if control.RefreshRowMetrics then
        control:RefreshRowMetrics()
    end

    if control.GetHeight then
        return control:GetHeight() or 0
    end

    return 0
end

Nvk3UT.QuestTrackerRows = Rows

return Rows
